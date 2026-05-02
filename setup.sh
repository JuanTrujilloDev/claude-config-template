#!/usr/bin/env bash
# claude-config-template setup script.
#
# Reads template.config.yaml, prompts the user for each placeholder,
# substitutes {{var}} (and {{#var}}...{{/var}} / {{^var}}...{{/var}})
# across template/, and writes the result to a target directory.
#
# Usage:
#   ./setup.sh                        # prompts; writes to ./.claude + ./CLAUDE.md
#   ./setup.sh --target /path/to/proj # writes there instead
#   ./setup.sh --answers answers.env  # non-interactive: load answers from file
#
# Requires: bash 4+, python3 (for YAML parsing + template substitution).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"
CONFIG_FILE="$SCRIPT_DIR/template.config.yaml"

TARGET="$(pwd)"
ANSWERS_FILE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --target) TARGET="$2"; shift 2 ;;
    --answers) ANSWERS_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "Error: template/ not found at $TEMPLATE_DIR" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: template.config.yaml not found at $CONFIG_FILE" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Parse the YAML schema (via inline python3) into a JSON spec we can
# iterate over in bash.
# ---------------------------------------------------------------------------
SPEC_JSON=$(python3 - "$CONFIG_FILE" <<'PYEOF'
import sys, json, re

# Minimal YAML parser for our specific schema (avoids the PyYAML dependency).
# Supports: top-level "variables:" list, each item a dict with scalar values
# and a "choices" list. This is intentionally narrow.

with open(sys.argv[1], "r", encoding="utf-8") as f:
    text = f.read()

variables = []
current = None
in_choices = False

for raw in text.splitlines():
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    if raw.startswith("variables:"):
        continue

    # New variable starts with "  - name: ..."
    m = re.match(r"^  - name:\s*(.+?)\s*$", raw)
    if m:
        if current is not None:
            variables.append(current)
        current = {"name": m.group(1).strip()}
        in_choices = False
        continue

    if current is None:
        continue

    # "    key: value"
    m = re.match(r"^    (\w+):\s*(.*)$", raw)
    if m:
        key, val = m.group(1), m.group(2).strip()
        if key == "choices":
            # inline list "[a, b, c]"
            if val.startswith("[") and val.endswith("]"):
                items = [x.strip().strip('"').strip("'") for x in val[1:-1].split(",") if x.strip()]
                current["choices"] = items
                in_choices = False
            else:
                current["choices"] = []
                in_choices = True
            continue
        # strip surrounding quotes
        if val.startswith('"') and val.endswith('"'):
            val = val[1:-1]
        elif val.startswith("'") and val.endswith("'"):
            val = val[1:-1]
        current[key] = val
        in_choices = False
        continue

    # "    - choice"
    if in_choices:
        m = re.match(r"^      - (.+)$", raw)
        if m:
            current.setdefault("choices", []).append(m.group(1).strip())

if current is not None:
    variables.append(current)

print(json.dumps(variables))
PYEOF
)

VAR_COUNT=$(python3 -c "import json,sys; print(len(json.loads(sys.stdin.read())))" <<<"$SPEC_JSON")

# ---------------------------------------------------------------------------
# Step 2: Collect answers (interactively or from a pre-baked answers file).
# ---------------------------------------------------------------------------
declare -A ANSWERS

if [[ -n "$ANSWERS_FILE" ]]; then
  if [[ ! -f "$ANSWERS_FILE" ]]; then
    echo "Error: answers file not found: $ANSWERS_FILE" >&2
    exit 1
  fi
  # Load KEY=VALUE pairs (one per line, # comments allowed).
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    ANSWERS["$key"]="${val}"
  done < "$ANSWERS_FILE"
  echo "Loaded $(echo "${!ANSWERS[@]}" | wc -w) answers from $ANSWERS_FILE"
else
  echo ""
  echo "============================================================"
  echo "  Claude Code config template setup"
  echo "============================================================"
  echo ""

  for i in $(seq 0 $((VAR_COUNT - 1))); do
    NAME=$(echo "$SPEC_JSON" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[$i].get('name',''))")
    PROMPT=$(echo "$SPEC_JSON" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[$i].get('prompt',''))")
    DEFAULT=$(echo "$SPEC_JSON" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[$i].get('default',''))")
    DEFAULT_FROM=$(echo "$SPEC_JSON" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[$i].get('default_from',''))")
    TRANSFORM=$(echo "$SPEC_JSON" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[$i].get('transform',''))")
    CHOICES=$(echo "$SPEC_JSON" | python3 -c "import json,sys; v=json.loads(sys.stdin.read())[$i].get('choices',[]); print(','.join(v))")
    WHEN=$(echo "$SPEC_JSON" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[$i].get('when',''))")

    # Honor 'when:' clauses (e.g. "has_frontend == yes")
    if [[ -n "$WHEN" ]]; then
      WHEN_VAR=$(echo "$WHEN" | awk -F'==' '{gsub(/ /,"",$1); print $1}')
      WHEN_VAL=$(echo "$WHEN" | awk -F'==' '{gsub(/ /,"",$2); print $2}')
      if [[ "${ANSWERS[$WHEN_VAR]:-}" != "$WHEN_VAL" ]]; then
        ANSWERS["$NAME"]=""
        continue
      fi
    fi

    # Resolve default_from
    if [[ -z "$DEFAULT" && -n "$DEFAULT_FROM" ]]; then
      SRC="${ANSWERS[$DEFAULT_FROM]:-}"
      case "$TRANSFORM" in
        kebab)
          DEFAULT=$(echo "$SRC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//')
          ;;
        *) DEFAULT="$SRC" ;;
      esac
    fi

    # Build prompt suffix
    PROMPT_SUFFIX=""
    [[ -n "$CHOICES" ]] && PROMPT_SUFFIX=" [$CHOICES]"
    [[ -n "$DEFAULT" ]] && PROMPT_SUFFIX="$PROMPT_SUFFIX (default: $DEFAULT)"

    while true; do
      read -r -p "$PROMPT$PROMPT_SUFFIX > " VAL
      [[ -z "$VAL" ]] && VAL="$DEFAULT"

      # Validate against choices
      if [[ -n "$CHOICES" ]]; then
        if ! echo ",$CHOICES," | grep -q ",$VAL,"; then
          echo "  → Must be one of: $CHOICES" >&2
          continue
        fi
      fi
      break
    done

    ANSWERS["$NAME"]="$VAL"
  done
fi

# ---------------------------------------------------------------------------
# Step 3: Derive synthetic flags (e.g. ticket_tracker_plane=yes if
# ticket_tracker == Plane). These are referenced by {{#flag}} blocks in
# template files for cleaner conditionals.
# ---------------------------------------------------------------------------
case "${ANSWERS[ticket_tracker]:-}" in
  Plane)  ANSWERS[ticket_tracker_plane]=yes ;;
  Jira)   ANSWERS[ticket_tracker_jira]=yes ;;
  Linear) ANSWERS[ticket_tracker_linear]=yes ;;
  GitHub) ANSWERS[ticket_tracker_github]=yes ;;
  none)   : ;;
esac

# Normalize yes/no booleans for {{#flag}} sections.
for key in has_frontend has_celery has_e2e enforce_layer_split; do
  if [[ "${ANSWERS[$key]:-}" == "no" || "${ANSWERS[$key]:-}" == "false" || -z "${ANSWERS[$key]:-}" ]]; then
    ANSWERS["$key"]=""
  fi
done

echo ""
echo "Answers collected:"
for key in "${!ANSWERS[@]}"; do
  val="${ANSWERS[$key]}"
  printf "  %-30s = %s\n" "$key" "${val:-(empty)}"
done | sort
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] Stopping before file write."
  exit 0
fi

read -r -p "Proceed and write to $TARGET? [y/N] " CONFIRM
[[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]] || { echo "Aborted."; exit 1; }

# ---------------------------------------------------------------------------
# Step 4: Render — substitute placeholders + apply conditional sections.
# ---------------------------------------------------------------------------
mkdir -p "$TARGET"

# Serialize answers to JSON for the python renderer.
ANSWERS_JSON=$(python3 -c "
import json, os
ans = {}
import sys
for line in sys.stdin:
    line = line.rstrip('\n')
    if '=' not in line: continue
    k, v = line.split('=', 1)
    ans[k] = v
print(json.dumps(ans))
" <<EOF_ANSWERS
$(for k in "${!ANSWERS[@]}"; do printf "%s=%s\n" "$k" "${ANSWERS[$k]}"; done)
EOF_ANSWERS
)

# Render every file under template/ to TARGET/, mirroring directory structure.
python3 - "$TEMPLATE_DIR" "$TARGET" "$ANSWERS_JSON" <<'PYEOF'
import os, re, sys, json, shutil, stat

TEMPLATE_DIR, TARGET, ANSWERS_JSON = sys.argv[1], sys.argv[2], sys.argv[3]
ANS = json.loads(ANSWERS_JSON)

def truthy(v):
    if v is None: return False
    s = str(v).strip().lower()
    return s not in ("", "no", "false", "0", "none")

# Mustache-style sections.  {{#var}}...{{/var}} kept iff truthy(ANS[var]);
# {{^var}}...{{/var}} kept iff falsy.  Standalone tags (alone on a line, only
# whitespace around them) eat the trailing newline so conditionals don't leave
# a forest of blank lines.
STANDALONE_RE = re.compile(r"^[ \t]*\{\{[#^/](\w+)\}\}[ \t]*\n", re.MULTILINE)
SECTION_RE = re.compile(r"\{\{([#^])(\w+)\}\}(.*?)\{\{/\2\}\}", re.DOTALL)
VAR_RE = re.compile(r"\{\{(\w+)\}\}")

def render(text):
    # First: tag standalone tags so we can later eat their newlines without
    # losing tags that are inline (e.g. inside a sentence). Mark them with a
    # sentinel that survives the section regex.
    def standalone_marker(m):
        return m.group(0).rstrip("\n") + "\x00\n"  # \x00 marks "eat me"
    text = STANDALONE_RE.sub(standalone_marker, text)

    # Apply sections repeatedly (handles nesting).
    prev = None
    while text != prev:
        prev = text
        def repl(m):
            kind, name, body = m.group(1), m.group(2), m.group(3)
            keep = truthy(ANS.get(name)) if kind == "#" else not truthy(ANS.get(name))
            return body if keep else ""
        text = SECTION_RE.sub(repl, text)

    # Now collapse `\x00\n` (a marked standalone tag survived = whole line was kept;
    # eat the newline that followed the tag).
    text = re.sub(r"\x00\n", "", text)

    # Plain variable substitution.
    text = VAR_RE.sub(lambda m: ANS.get(m.group(1), ""), text)
    return text
written, skipped = 0, 0
for root, dirs, files in os.walk(TEMPLATE_DIR):
    rel = os.path.relpath(root, TEMPLATE_DIR)
    out_dir = TARGET if rel == "." else os.path.join(TARGET, rel)
    os.makedirs(out_dir, exist_ok=True)
    for name in files:
        src = os.path.join(root, name)
        dst = os.path.join(out_dir, name)
        try:
            with open(src, "r", encoding="utf-8") as f:
                content = f.read()
            # Honor <!-- requires: var --> directive on the first line.
            first_nl = content.find("\n")
            if first_nl > 0:
                first_line = content[:first_nl]
                req_match = re.match(r"\s*<!--\s*requires:\s*(\w+)\s*-->\s*$", first_line)
                if req_match and not truthy(ANS.get(req_match.group(1))):
                    skipped += 1
                    continue
                if req_match:
                    content = content[first_nl+1:]
            rendered = render(content)
        except UnicodeDecodeError:
            shutil.copy2(src, dst)
            written += 1
            continue
        with open(dst, "w", encoding="utf-8") as f:
            f.write(rendered)
        # Preserve executable bit on .sh
        if name.endswith(".sh"):
            os.chmod(dst, os.stat(dst).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        written += 1

print(f"  wrote {written} files")
PYEOF

# ---------------------------------------------------------------------------
# Step 5: Post-install hints.
# ---------------------------------------------------------------------------
echo ""
echo "✓ Template rendered to $TARGET"
echo ""
echo "Next steps:"
echo "  1. Review .claude/CLAUDE.md and .claude/HELP.md — adjust if needed"
echo "  2. cp .claude/mcp.json.example .claude/mcp.json  (if you use MCPs)"
echo "  3. Add .claude/settings.local.json + .claude/mcp.json to .gitignore"
echo "  4. Verify hooks are executable:  chmod +x .claude/hooks/*.sh"
echo "  5. (Re)start Claude Code to load the new config"
echo ""
