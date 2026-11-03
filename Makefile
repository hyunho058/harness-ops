# Repo-wide test command. Run from the repo root:
#
#     make test
#
# 1. skills/coherence-audit/scripts/run-tests.sh — the shared-script suite, which
#    also collects every skills/*/tests/*_test.sh as one case per file (section E).
# 2. scripts/test-block-main-push.sh — the block-main-push hook behaviour table.
#
# Make stops at the first failing command, so the target fails if either does.

.PHONY: test

test:
	bash skills/coherence-audit/scripts/run-tests.sh
	bash scripts/test-block-main-push.sh
