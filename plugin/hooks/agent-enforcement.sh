#!/bin/bash
# PreToolUse hook for Claude Code (Edit | Write).
#
# Enforces:
# - Branch discipline: never edit code under $CLAUDE_CONFIG_SRC_DIR while on
#   $CLAUDE_CONFIG_DEFAULT_BRANCH (defaults: src/ and main/master).
# - Agent gating: edits >50 lines or new defs/classes in $CLAUDE_CONFIG_SRC_DIR
#   must come from inside an agent (CLAUDE_AGENT_ACTIVE=1).
#
# Override per-project via environment variables (e.g., in .envrc with direnv,
# or your shell rc):
#   export CLAUDE_CONFIG_SRC_DIR=apps           # default: src
#   export CLAUDE_CONFIG_FRONTEND_DIR=apps/frontend  # default: (none)
#   export CLAUDE_CONFIG_DEFAULT_BRANCH=develop # default: main

set -uo pipefail

INPUT=$(cat)
export HOOK_INPUT="$INPUT"

SUMMARY=$(python3 -c '
import json, os, sys
try:
    data = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    sys.exit(0)
ti = data.get("tool_input", {}) or {}
fp = (ti.get("file_path") or "").replace("\t", " ")
ns = ti.get("new_string") or ti.get("content") or ""
line_count = ns.count("\n") + (1 if ns and not ns.endswith("\n") else 0)
has_new_def = 0
for line in ns.splitlines():
    s = line.lstrip()
    if (
        s.startswith("def ")
        or s.startswith("class ")
        or s.startswith("export class ")
        or s.startswith("export function ")
        or s.startswith("function ")
    ):
        has_new_def = 1
        break
print(f"{fp}\t{line_count}\t{has_new_def}")
')

if [ -z "$SUMMARY" ]; then exit 0; fi

FILE_PATH=$(printf '%s' "$SUMMARY" | awk -F'\t' '{print $1}')
LINE_COUNT=$(printf '%s' "$SUMMARY" | awk -F'\t' '{print $2}')
HAS_NEW_DEF=$(printf '%s' "$SUMMARY" | awk -F'\t' '{print $3}')

if [ -z "$FILE_PATH" ]; then exit 0; fi

# Defaults; override via environment variables.
SRC_DIR="${CLAUDE_CONFIG_SRC_DIR:-src}"
FRONTEND_DIR="${CLAUDE_CONFIG_FRONTEND_DIR:-}"
DEFAULT_BRANCH="${CLAUDE_CONFIG_DEFAULT_BRANCH:-main}"

# --- Branch Discipline ---
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -n "$PROJECT_DIR" ] && { [ -d "$PROJECT_DIR/.git" ] || [ -f "$PROJECT_DIR/.git" ]; }; then
    CURRENT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ] || [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
        # Check whether path matches src or frontend dirs.
        IN_SCOPE=0
        case "$FILE_PATH" in
            *"/$SRC_DIR/"*|*"/$SRC_DIR"|*"$SRC_DIR/"*) IN_SCOPE=1 ;;
        esac
        if [ -n "$FRONTEND_DIR" ]; then
            case "$FILE_PATH" in
                *"$FRONTEND_DIR"*) IN_SCOPE=1 ;;
            esac
        fi
        if [ "$IN_SCOPE" = "1" ]; then
            cat >&2 <<MSG
[agent-enforcement] BLOCKED: editing on '$CURRENT_BRANCH' is forbidden.
Check out a typed branch first:
  git checkout -b feature/<slug>
  git checkout -b fix/<slug>
  git checkout -b hotfix/<slug>
  git checkout -b refactor/<slug>
  git checkout -b chore/<slug>
MSG
            exit 2
        fi
    fi
fi

# --- Agent Gating ---
SCOPE=""
case "$FILE_PATH" in
    *"$FRONTEND_DIR"*)
        if [ -n "$FRONTEND_DIR" ]; then SCOPE="frontend"; fi
        ;;
esac
if [ -z "$SCOPE" ]; then
    case "$FILE_PATH" in
        *"/$SRC_DIR/"*|*"/$SRC_DIR"|*"$SRC_DIR/"*) SCOPE="backend" ;;
        *) exit 0 ;;
    esac
fi

if [ "${CLAUDE_AGENT_ACTIVE:-0}" = "1" ]; then exit 0; fi
if [ "${LINE_COUNT:-0}" -le 50 ] && [ "${HAS_NEW_DEF:-0}" -eq 0 ]; then exit 0; fi

case "$SCOPE" in
    backend) AGENT="backend-dev" ;;
    frontend) AGENT="frontend-dev" ;;
esac

DEF_LABEL="no"
[ "${HAS_NEW_DEF}" -eq 1 ] && DEF_LABEL="yes"

cat >&2 <<MSG
[agent-enforcement] BLOCKED: non-trivial edit to ${SCOPE} source.

Detected:
  file:        ${FILE_PATH}
  added lines: ${LINE_COUNT}  (threshold: 50)
  new def/class: ${DEF_LABEL}

Spawn the \`${AGENT}\` agent (Design First, then implement on the proper branch).

To override (rare): set CLAUDE_AGENT_ACTIVE=1 in your environment.
MSG
exit 2
