#!/bin/bash
# Hook 1: SKILL.md 편집 시 .claude/skills/ stub 존재 확인
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ "$FILE_PATH" != */skills/*/SKILL.md ]] && exit 0

SKILL_NAME=$(basename "$(dirname "$FILE_PATH")")
STUB="$CLAUDE_PROJECT_DIR/.claude/skills/${SKILL_NAME}.md"

if [[ ! -f "$STUB" ]]; then
  echo "WARNING: stub not found for skill '${SKILL_NAME}': ${STUB}" >&2
fi

exit 0
