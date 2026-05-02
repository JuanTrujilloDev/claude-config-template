#!/bin/bash
# Auto-format hook for Claude Code — runs after Edit/Write.

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

EXT="${FILE_PATH##*.}"

case "$EXT" in
    py)
        if command -v ruff &> /dev/null; then
            ruff check --fix "$FILE_PATH" 2>/dev/null || true
        fi
        if command -v black &> /dev/null; then
            black --quiet "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    ts|tsx|js|jsx|mjs|cjs)
        # Try project-local prettier/eslint first
        for dir in "$CLAUDE_PROJECT_DIR" "$CLAUDE_PROJECT_DIR/{{frontend_dir}}"; do
            if [ -f "$dir/node_modules/.bin/prettier" ]; then
                (cd "$dir" && ./node_modules/.bin/prettier --write "$FILE_PATH" 2>/dev/null) || true
                break
            fi
        done
        for dir in "$CLAUDE_PROJECT_DIR" "$CLAUDE_PROJECT_DIR/{{frontend_dir}}"; do
            if [ -f "$dir/node_modules/.bin/eslint" ]; then
                (cd "$dir" && ./node_modules/.bin/eslint --fix "$FILE_PATH" 2>/dev/null) || true
                break
            fi
        done
        ;;
    go)
        command -v gofmt &> /dev/null && gofmt -w "$FILE_PATH" 2>/dev/null || true
        ;;
    rs)
        command -v rustfmt &> /dev/null && rustfmt "$FILE_PATH" 2>/dev/null || true
        ;;
    html|htm)
        # Skip prettier on template files — it breaks {% %} and {{ }} tags
        ;;
esac

exit 0
