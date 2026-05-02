#!/bin/bash
# Auto-formats files after Edit/Write based on extension.
# Uses project-local tools when available (node_modules/.bin, .venv/bin).

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

EXT="${FILE_PATH##*.}"
FRONTEND_DIR="${CLAUDE_CONFIG_FRONTEND_DIR:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

case "$EXT" in
    py)
        command -v ruff &> /dev/null && ruff check --fix "$FILE_PATH" 2>/dev/null || true
        command -v black &> /dev/null && black --quiet "$FILE_PATH" 2>/dev/null || true
        ;;
    ts|tsx|js|jsx|mjs|cjs)
        for dir in "$PROJECT_DIR" "$PROJECT_DIR/$FRONTEND_DIR"; do
            [ -z "$dir" ] && continue
            if [ -f "$dir/node_modules/.bin/prettier" ]; then
                (cd "$dir" && ./node_modules/.bin/prettier --write "$FILE_PATH" 2>/dev/null) || true
                break
            fi
        done
        for dir in "$PROJECT_DIR" "$PROJECT_DIR/$FRONTEND_DIR"; do
            [ -z "$dir" ] && continue
            if [ -f "$dir/node_modules/.bin/eslint" ]; then
                (cd "$dir" && ./node_modules/.bin/eslint --fix "$FILE_PATH" 2>/dev/null) || true
                break
            fi
        done
        ;;
    go) command -v gofmt &> /dev/null && gofmt -w "$FILE_PATH" 2>/dev/null || true ;;
    rs) command -v rustfmt &> /dev/null && rustfmt "$FILE_PATH" 2>/dev/null || true ;;
    html|htm) ;;  # skip — breaks template tags
esac
exit 0
