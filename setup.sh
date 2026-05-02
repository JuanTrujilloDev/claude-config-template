#!/usr/bin/env bash
# claude-config-template renderer.
#
# Reads template/ and an answers file, substitutes {{var}} placeholders
# (and {{#var}}…{{/var}} / {{^var}}…{{/var}} sections), drops files marked
# with `<!-- requires: var -->` when the var is falsy, and writes the
# result to a target directory.
#
# This is NOT an interactive setup. The expected workflow is:
#
#   1. Open Claude Code in your new project.
#   2. Tell Claude: "set up Claude Code config from <path to this template>."
#      Claude reads your project, drafts an answers.env, asks you to confirm.
#   3. Claude runs this script to render.
#
# If you'd rather drive it by hand, copy one of the pre-filled examples:
#   cp examples/python-fastapi/answers.env ./answers.env
#   ./setup.sh --target /path/to/project --answers ./answers.env
#
# Usage:
#   setup.sh --target <dir> --answers <file>
#   setup.sh --target <dir> --answers -        # read answers from stdin
#
# Answers file format: KEY=VALUE per line; # comments allowed.
# See template.config.yaml for the full list of placeholders.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"

TARGET=""
ANSWERS_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --target) TARGET="$2"; shift 2 ;;
    --answers) ANSWERS_FILE="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "Error: --target is required." >&2
  echo "Usage: setup.sh --target <dir> --answers <file>" >&2
  exit 1
fi

if [[ -z "$ANSWERS_FILE" ]]; then
  echo "Error: --answers is required." >&2
  echo "" >&2
  echo "This script is not interactive. The standard flow is:" >&2
  echo "  1. Open Claude Code in your new project." >&2
  echo "  2. Tell Claude: 'set up Claude Code config from $SCRIPT_DIR'." >&2
  echo "  3. Claude drafts an answers.env, asks you to confirm, then runs this script." >&2
  echo "" >&2
  echo "To drive it by hand, start from a pre-filled example:" >&2
  echo "  cp $SCRIPT_DIR/examples/python-fastapi/answers.env ./answers.env" >&2
  echo "  $0 --target . --answers ./answers.env" >&2
  exit 1
fi

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "Error: template/ not found at $TEMPLATE_DIR" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read answers.
# ---------------------------------------------------------------------------
declare -A ANSWERS

if [[ "$ANSWERS_FILE" == "-" ]]; then
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    ANSWERS["$key"]="${val}"
  done
else
  if [[ ! -f "$ANSWERS_FILE" ]]; then
    echo "Error: answers file not found: $ANSWERS_FILE" >&2
    exit 1
  fi
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    ANSWERS["$key"]="${val}"
  done < "$ANSWERS_FILE"
fi

# ---------------------------------------------------------------------------
# Derive synthetic flags. ticket_tracker_<name>=yes for {{#flag}} sections,
# and normalize yes/no booleans (anything blank/no/false → empty string,
# which the renderer treats as falsy).
# ---------------------------------------------------------------------------
case "${ANSWERS[ticket_tracker]:-}" in
  Plane)  ANSWERS[ticket_tracker_plane]=yes ;;
  Jira)   ANSWERS[ticket_tracker_jira]=yes ;;
  Linear) ANSWERS[ticket_tracker_linear]=yes ;;
  GitHub) ANSWERS[ticket_tracker_github]=yes ;;
  none)   : ;;
esac

for key in has_frontend has_celery has_e2e enforce_layer_split; do
  v="${ANSWERS[$key]:-}"
  if [[ "$v" == "no" || "$v" == "false" || -z "$v" ]]; then
    ANSWERS["$key"]=""
  fi
done

mkdir -p "$TARGET"

ANSWERS_JSON=$(python3 -c "
import json, sys
ans = {}
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

# ---------------------------------------------------------------------------
# Render.
# ---------------------------------------------------------------------------
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
    def standalone_marker(m):
        return m.group(0).rstrip("\n") + "\x00\n"
    text = STANDALONE_RE.sub(standalone_marker, text)

    prev = None
    while text != prev:
        prev = text
        def repl(m):
            kind, name, body = m.group(1), m.group(2), m.group(3)
            keep = truthy(ANS.get(name)) if kind == "#" else not truthy(ANS.get(name))
            return body if keep else ""
        text = SECTION_RE.sub(repl, text)

    text = re.sub(r"\x00\n", "", text)
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
        if name.endswith(".sh"):
            os.chmod(dst, os.stat(dst).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        written += 1

print(f"  rendered {written} files{', skipped ' + str(skipped) if skipped else ''}")
PYEOF

# ---------------------------------------------------------------------------
# Done.
# ---------------------------------------------------------------------------
echo ""
echo "✓ Template rendered to $TARGET"
echo ""
echo "Next steps:"
echo "  1. Review CLAUDE.md and .claude/HELP.md — adjust if needed"
echo "  2. cp .claude/mcp.json.example .claude/mcp.json  (if you use MCPs)"
echo "  3. Add to .gitignore:  .claude/settings.local.json, .claude/mcp.json"
echo "  4. (Re)start Claude Code to load the new config"
echo ""
