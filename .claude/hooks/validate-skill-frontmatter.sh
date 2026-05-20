#!/bin/bash
# Hook 2: SKILL.md frontmatter 필수 필드 검증
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ "$FILE_PATH" != */skills/*/SKILL.md ]] && exit 0

CONTENT=$(cat "$FILE_PATH" 2>/dev/null)

for FIELD in "^name:" "^description:" "^allowed-tools:"; do
  if ! echo "$CONTENT" | grep -qE "$FIELD"; then
    echo "ERROR: SKILL.md missing required frontmatter field: ${FIELD}" >&2
    echo "File: ${FILE_PATH}" >&2
    exit 2
  fi
done

exit 0
