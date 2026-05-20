#!/bin/bash
# Hook 5: main 브랜치 직접 push 차단
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

if [[ "$BRANCH" == "main" ]]; then
  echo "Blocked: direct push to main is not allowed. Create a PR instead: gh pr create" >&2
  exit 2
fi

exit 0
