# check-harness acceptance tests

Every `*_test.sh` file in this directory is collected by section E of
`skills/coherence-audit/scripts/run-tests.sh`, so `make test` from the repo root
runs it. Each file counts as one case: exit 0 passes, any other exit fails.

## Rules for a test file

- **Name**: `tt{n}_{topic}_test.sh`, where `{n}` is the spec's TT task number and
  `{topic}` a short snake_case label (for example `tt1_skill_name_test.sh`).
  A file that does not end in `_test.sh` is not collected.
- **Self-contained fixtures**: build every fixture (home directory, repos,
  settings, session logs) under a scratch directory from `mktemp -d`, and remove
  it on exit with a `trap`.
- **`HOME` overridden**: point `HOME` at the fixture home before running anything
  under test. A test never reads or writes the real `~/.claude`, `~/.claude.json`
  or the user's session logs.
- **cwd**: the runner starts each test with the repo root as the working
  directory, so a test may use repo-relative paths such as
  `skills/check-harness/scripts/...`.
- **Tools**: only what the existing suite uses — `bash`, `git`, `jq`, `python3`
  and coreutils.
