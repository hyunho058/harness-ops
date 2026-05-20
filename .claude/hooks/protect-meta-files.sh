#!/bin/bash
# Hook 3: 플러그인 메타 파일 보호 (hooks/hooks.json, plugins/*)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ "$FILE_PATH" == */hooks/hooks.json || "$FILE_PATH" == */plugins/* ]]; then
  echo "Blocked: '${FILE_PATH}' is a plugin meta file. Edit via structured update only." >&2
  exit 2
fi

exit 0
