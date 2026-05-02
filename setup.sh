#!/usr/bin/env bash
# claude-config-template renderer.
#
# Reads template/ + an answers file, substitutes {{var}} placeholders
# (and {{#var}}…{{/var}} / {{^var}}…{{/var}} sections), drops files marked
# `<!-- requires: var -->` when the var is falsy, writes to a target dir.
#
# This is NOT an interactive setup. The expected workflow is:
#
#   1. Open Claude Code in your new project.
#   2. Tell Claude: "set up Claude Code config from <path to this template>."
#      Claude reads your project, drafts an answers.env, asks you to confirm.
#   3. Claude runs this script to render.
#
# To drive it by hand, copy a pre-filled example:
#   cp examples/python-fastapi/answers.env ./answers.env
#   ./setup.sh --target /path/to/project --answers ./answers.env
#
# Usage:
#   setup.sh --target <dir> --answers <file>
#   setup.sh --target <dir> --answers -        # read answers from stdin
#
# Requires: bash 3.2+ (works on stock macOS bash) and python3.
# All non-trivial logic runs in python3 to stay portable across shells.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"

TARGET=""
ANSWERS_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --answers) ANSWERS_FILE="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Error: --target is required." >&2
  echo "Usage: setup.sh --target <dir> --answers <file>" >&2
  exit 1
fi

if [ -z "$ANSWERS_FILE" ]; then
  echo "Error: --answers is required." >&2
  echo "" >&2
  echo "This script is not interactive. The standard flow is:" >&2
  echo "  1. Open Claude Code in your new project." >&2
  echo "  2. Tell Claude: 'set up Claude Code config from $SCRIPT_DIR'." >&2
  echo "  3. Claude drafts an answers.env, asks to confirm, then runs this script." >&2
  echo "" >&2
  echo "To drive it by hand, start from a pre-filled example:" >&2
  echo "  cp $SCRIPT_DIR/examples/python-fastapi/answers.env ./answers.env" >&2
  echo "  $0 --target . --answers ./answers.env" >&2
  exit 1
fi

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "Error: template/ not found at $TEMPLATE_DIR" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required" >&2
  exit 1
fi

mkdir -p "$TARGET"

# Pipe answers (file or stdin) into python; everything else happens there.
if [ "$ANSWERS_FILE" = "-" ]; then
  ANSWERS_INPUT="$(cat)"
else
  if [ ! -f "$ANSWERS_FILE" ]; then
    echo "Error: answers file not found: $ANSWERS_FILE" >&2
    exit 1
  fi
  ANSWERS_INPUT="$(cat "$ANSWERS_FILE")"
fi

# All real work happens in python3 — works on macOS bash 3.2 because we
# never use associative arrays in bash itself.
ANSWERS_INPUT="$ANSWERS_INPUT" \
  TEMPLATE_DIR="$TEMPLATE_DIR" \
  TARGET="$TARGET" \
  python3 - <<'PYEOF'
import os, re, sys, shutil, stat

TEMPLATE_DIR = os.environ["TEMPLATE_DIR"]
TARGET = os.environ["TARGET"]
ANSWERS_INPUT = os.environ["ANSWERS_INPUT"]

# 1. Parse KEY=VALUE answers (skip blank lines + #-comments).
ANS = {}
for line in ANSWERS_INPUT.splitlines():
    line = line.rstrip("\n")
    if not line or line.lstrip().startswith("#"):
        continue
    if "=" not in line:
        continue
    k, v = line.split("=", 1)
    ANS[k.strip()] = v

# 2. Synthesize ticket_tracker_<flag>=yes for {{#flag}} sections.
tt = ANS.get("ticket_tracker", "")
flag_map = {
    "Plane":  "ticket_tracker_plane",
    "Jira":   "ticket_tracker_jira",
    "Linear": "ticket_tracker_linear",
    "GitHub": "ticket_tracker_github",
}
if tt in flag_map:
    ANS[flag_map[tt]] = "yes"

# 3. Normalize yes/no booleans — anything blank/no/false → empty (= falsy).
for k in ("has_frontend", "has_celery", "has_e2e", "enforce_layer_split"):
    v = ANS.get(k, "").strip().lower()
    if v in ("", "no", "false"):
        ANS[k] = ""

def truthy(v):
    if v is None: return False
    s = str(v).strip().lower()
    return s not in ("", "no", "false", "0", "none")

# 4. Mustache-style template renderer with standalone-tag whitespace cleanup.
STANDALONE_RE = re.compile(r"^[ \t]*\{\{[#^/](\w+)\}\}[ \t]*\n", re.MULTILINE)
SECTION_RE = re.compile(r"\{\{([#^])(\w+)\}\}(.*?)\{\{/\2\}\}", re.DOTALL)
VAR_RE = re.compile(r"\{\{(\w+)\}\}")

def render(text):
    text = STANDALONE_RE.sub(lambda m: m.group(0).rstrip("\n") + "\x00\n", text)
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

# 5. Walk template/, render each file, honor <!-- requires: var --> directives.
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

extra = f", skipped {skipped}" if skipped else ""
print(f"  rendered {written} files{extra}")
PYEOF

echo ""
echo "✓ Template rendered to $TARGET"
echo ""
echo "Next steps:"
echo "  1. Review CLAUDE.md and .claude/HELP.md — adjust if needed"
echo "  2. cp .claude/mcp.json.example .claude/mcp.json  (if you use MCPs)"
echo "  3. Add to .gitignore:  .claude/settings.local.json, .claude/mcp.json"
echo "  4. (Re)start Claude Code to load the new config"
echo ""
