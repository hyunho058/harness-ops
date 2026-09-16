#!/bin/bash
# Hook 1: SKILL.md 편집 시 .claude/skills/ stub 존재 확인
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ "$FILE_PATH" != */skills/*/SKILL.md ]] && exit 0

SKILL_NAME=$(basename "$(dirname "$FILE_PATH")")
STUB="$CLAUDE_PROJECT_DIR/.claude/skills/${SKILL_NAME}.md"

# The stub is a frontmatter-parity artifact, NOT a skill entry point: Claude Code
# loads a project skill from .claude/skills/<name>/SKILL.md, never from the flat
# <name>.md spelling. See .claude/skills/README.md — this warning asks for parity,
# it does not mean the skill is unavailable.
if [[ ! -f "$STUB" ]]; then
  echo "WARNING: parity stub not found for skill '${SKILL_NAME}': ${STUB}" >&2
  echo "         (a stub does not register a command — see .claude/skills/README.md)" >&2
fi

exit 0
