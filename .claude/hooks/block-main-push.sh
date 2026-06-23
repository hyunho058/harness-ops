#!/bin/bash
# Hook 5: main 브랜치 직접 push 차단
# PreToolUse(Bash) 입력(JSON)에서 명령어를 읽어, 실제 `git push`일 때만 검사한다.
# (브랜치만 보고 모든 Bash를 막던 과도 차단 버그 수정)
INPUT=$(cat)
if command -v jq >/dev/null 2>&1; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
else
  # jq 없음 → 원본 JSON 전체를 스캔 (fail-safe: push는 여전히 차단, 비-push는 통과)
  CMD="$INPUT"
fi

# push 명령이 아니면 통과
echo "$CMD" | grep -Eq '\bgit\b.*\bpush\b' || exit 0

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$BRANCH" == "main" ]]; then
  echo "Blocked: direct push to main is not allowed. Create a PR instead: gh pr create" >&2
  exit 2
fi

exit 0
