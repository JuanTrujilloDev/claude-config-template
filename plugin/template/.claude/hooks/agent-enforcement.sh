#!/bin/bash
# PreToolUse hook for Claude Code (Edit | Write).
#
# Enforces:
# - Branch discipline: never edit code under {{src_dir}} on {{default_branch}}
# - Agent gating: edits >50 lines or new defs/classes in {{src_dir}} must
#   come from inside an agent (CLAUDE_AGENT_ACTIVE=1)
#
# Trivial edits (≤50 lines, no new defs) are allowed directly.

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

if [ -z "$SUMMARY" ]; then
    exit 0
fi

FILE_PATH=$(printf '%s' "$SUMMARY" | awk -F'\t' '{print $1}')
LINE_COUNT=$(printf '%s' "$SUMMARY" | awk -F'\t' '{print $2}')
HAS_NEW_DEF=$(printf '%s' "$SUMMARY" | awk -F'\t' '{print $3}')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# --- Branch Discipline ---
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -n "$PROJECT_DIR" ] && { [ -d "$PROJECT_DIR/.git" ] || [ -f "$PROJECT_DIR/.git" ]; }; then
    CURRENT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ "$CURRENT_BRANCH" = "{{default_branch}}" ] || [ "$CURRENT_BRANCH" = "master" ]; then
        case "$FILE_PATH" in
            *{{src_dir}}/*{{#has_frontend}}|*{{frontend_dir}}*{{/has_frontend}})
                cat >&2 <<MSG
[agent-enforcement] BLOCKED: editing on '$CURRENT_BRANCH' is forbidden.
Check out a typed branch first:
  git checkout -b feature/{{#branch_prefix}}{{branch_prefix}}-<#>-{{/branch_prefix}}<slug>
  git checkout -b fix/<slug>
  git checkout -b hotfix/<slug>
  git checkout -b refactor/<slug>
  git checkout -b chore/<slug>
See .claude/HELP.md for the branch cheat sheet.
MSG
                exit 2
                ;;
        esac
    fi
fi

# --- Agent Gating: applies to {{src_dir}} only ---
case "$FILE_PATH" in
{{#has_frontend}}
    *{{frontend_dir}}*)
        SCOPE="frontend"
        ;;
{{/has_frontend}}
    *{{src_dir}}/*)
        SCOPE="backend"
        ;;
    *)
        exit 0
        ;;
esac

# Already inside an agent? Allow.
if [ "${CLAUDE_AGENT_ACTIVE:-0}" = "1" ]; then
    exit 0
fi

# Trivial edit? Allow.
if [ "${LINE_COUNT:-0}" -le 50 ] && [ "${HAS_NEW_DEF:-0}" -eq 0 ]; then
    exit 0
fi

# Non-trivial: block.
case "$SCOPE" in
    backend)
        AGENT="backend-dev"
        SCOPE_DESC="{{src_dir}} (backend code)"
        ;;
    frontend)
        AGENT="frontend-dev"
        SCOPE_DESC="{{frontend_dir}} (frontend code)"
        ;;
esac

DEF_LABEL="no"
if [ "${HAS_NEW_DEF}" -eq 1 ]; then
    DEF_LABEL="yes"
fi

cat >&2 <<MSG
[agent-enforcement] BLOCKED: non-trivial edit to ${SCOPE_DESC}.

Detected:
  file:        ${FILE_PATH}
  added lines: ${LINE_COUNT}  (threshold: 50)
  new def/class: ${DEF_LABEL}

Per CLAUDE.md, non-trivial edits MUST go through the appropriate agent.
Spawn the \`${AGENT}\` agent with the task description, scope, and success
criteria. The agent runs Design First, then implements on the proper branch.

To override (rare): set CLAUDE_AGENT_ACTIVE=1 in your environment.

See .claude/HELP.md for the full decision tree.
MSG

exit 2
