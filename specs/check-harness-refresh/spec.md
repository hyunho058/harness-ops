# Spec: check-harness-refresh

## Meta
- **Created**: 2026-11-01
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-11-01
- **Mode**: unattended

## Goal
check-harness's structure (the 6 axes, the 4 analyzers, and the separate maker and checker)
still holds up, but two things have gone stale since it was last updated in #19/#25:

1. It doesn't know about most of the skills added since. The work loop, the ledgers and the
   reviewer gates those skills add never appear in its scoring (loop `## Lessons`; the
   `progress.md` / `build_order.md` / `pipeline.md` ledgers; `partition-manifest.md`,
   `design.md`, `brief.md`; inline checkers in specify / coherence-audit / crew / loop;
   autopilot limits and kill switch; agents that `expert` installs into `.claude/agents/`;
   worktree session directories; context-audit's `.drift-reports/latest.md`).
2. Several of its data-collection steps no longer match how Claude Code stores things, so
   some scores are probably wrong today regardless of the new skills: plugin/MCP state read
   from `~/.claude.json` keys that don't exist; an outdated plugin scan path; own skills
   counted twice (repo + installed cache copy); renamed skills shown as ghosts; a real
   trigger collision (`loop` vs `harness-ops:loop`) labelled as a prefix duplicate; the
   project session glob built but never used; subagent transcripts counted as sessions;
   skill matching that misses prefixed names; B5 keyed on a flag that is now rarely set;
   the completion check looking for `ralph`; D4 comparing unnormalised names; D2/D3
   reading only `.claude/settings.json`; project-root discovery that can land on `$HOME`;
   a halt on agy when the subagent registry comes back empty; a shared cache directory.
   Plus internal inconsistencies: the checklist says 24 items but lists 25 (L2 has 10, not
   9) and Axis 6 says "3 items + 1"; `top_ngram_share` vs `top_3gram_share`; 7-day vs
   30-day windows; analyzers told "modify no files" yet asked to save JSON; stale evals;
   other skills citing `check-harness/SKILL.md` by line number; a stale README.

Suggested order: fix collection first; then add the new artifacts to the existing items;
then decide whether the new layer (unattended safety; context-audit's report for C2)
needs its own axis or items. Findings in part 2 came from reading the code and checking it
against the actual `~/.claude` files, not from a real report.

## Non-goals
- Changing the 6-axis cycle, the 2×3 matrix, the maturity/score formulas, or the 4-analyzer
  layout (the request says the structure still holds up).
- Redesigning the HTML report's look; only placeholders/text that the new items require.
- Regenerating the Gemini CLI `.toml` commands (README already records them as stale; a
  separate job).
- Running `/check-harness` end-to-end against the live machine as part of this work
  (inferred: it would read the user's real session logs; the user offered it as optional
  confirmation, not as part of the change).
- Changing how loop, build-order, crew, autopilot, decompose, expert or context-audit
  write their artifacts — check-harness only reads them.

## Confirmed Goal
Bring check-harness (its SKILL.md, `references/checklist.md`, the four analyzer agents,
its evals, and the docs that describe or cite it) up to date with how Claude Code and the
current harness-ops skills actually store state, without changing its structure:

1. **Collection is correct** — every bug listed in Goal part 2 is fixed, and the
   deterministic parts of collection are pinned in shipped scripts with fixture tests
   (inferred: prose bash snippets are how these steps drifted unnoticed; a tested script
   cannot drift silently).
2. **New artifacts count** — the artifacts in Goal part 1 feed the existing items they
   belong to (E1/E3, B4/E2, B2, D4/D5, C2, project session scope).
3. **The new layer is decided** — unattended safety gets a scored home, and the
   checklist's item count, level tallies and field names agree everywhere they appear.

Done when (each checkable):
- `make test` exits 0 from the repo root and runs both the existing suite
  (`skills/coherence-audit/scripts/run-tests.sh`) and every `skills/check-harness/tests/*_test.sh`
  (inferred: the repo has no test command a test-writer can discover today, so one is added).
- `scripts/portability-lint.sh --sweep` exits 0.
- Every check-harness item count (`SKILL.md` frontmatter and body — which `.claude/skills/check-harness.md`
  shows through its symlink — `checklist.md` header and footer, `html-template.html` footer, `README.md`) states the same total, and the
  footer's per-level tallies equal the rows in the tables.
- No file in `skills/`, `agents/`, `references/` or `README.md` outside `skills/check-harness/` cites
  `check-harness/SKILL.md` by line number (`specs/` are dated design records and are not rewritten).

(inferred) The invocation's trailing `mode : unattened` is read as the `mode: unattended`
marker; this run asks no questions and records its own choices as `Status: assumed`.

## Research

### check-harness today
- Skill body: `skills/check-harness/SKILL.md` (665 lines). Phase 0 scope + root discovery "walk up from cwd and find the directory containing `.claude` or `CLAUDE.md`" (`skills/check-harness/SKILL.md:80-82`); shared cache `/tmp/cc-cache/check-harness/` (`:84-95`); Phase 1 spawns 5 analyzer runs via `capability:spawn-named-checker` (`:99-166`); User session scan uses `days=7` (`:124`), Project `days=30` (`:138`); analyzers are told "Save to /tmp/cc-cache/check-harness/*.json" (`:114`, `:126`, `:140`, `:150`, `:161`).
- Delegation assertion requires artifact AND registry and halts otherwise (`skills/check-harness/SKILL.md:168-188`); the halt sentence is `:184`.
- Item count claims "24": frontmatter `:6`, Phase 2 `:194`, template `:412`; `references/checklist.md:3`, `:166` ("L1: 9, L2: 9, L3: 6"). Actual rows: A1–A5, C1–C6, B2, B3/B5/B6, B1/D1–D5, E1/B4/E2/E3 = 25 (L1 9, L2 10, L3 6). Axis 6 header says "[3 items + 1]" (`references/checklist.md:94`).
- Field-name mismatch: checklist B6 uses `top_ngram_share` (`references/checklist.md:73`); the agent outputs `top_3gram_share` (`agents/session-pattern-analyzer.md:82`, `:104`).
- Evals: `skills/check-harness/evals/evals.json` has 3 evals (`id`, `name`, `prompt`, `expected_output`, `files`); none cover halting, agy, HTML output, or the new artifacts.
- README: "6-axis / 24-item checklist" (`README.md:11`). Parity stub `.claude/skills/check-harness.md` is a symlink to `../../skills/check-harness/SKILL.md` (as are `.claude/skills/loop.md` and `autopilot.md`; `.claude/skills/README.md`), so it shows whatever SKILL.md says; `.claude/hooks/check-stub-sync.sh` warns when a SKILL.md edit has no stub. The HTML template's footer hard-codes "24 items · 6 axes" (`skills/check-harness/references/html-template.html:213`).
- HTML template `skills/check-harness/references/html-template.html`; SKILL.md requires 1:1 placeholder parity (`skills/check-harness/SKILL.md:546`).

### The four analyzers (`agents/*.md`)
- skill-portfolio-analyzer reads `skillUsage`, `enabledPlugins`, `mcpServers` from `~/.claude.json` (`agents/skill-portfolio-analyzer.md:40-51`); scans `~/.claude/plugins/**/skills/**/SKILL.md` and `{PROJECT_ROOT}/skills/**/SKILL.md` (`:61-66`); plugin inventory from `~/.claude/plugins/*/` plugin.json (`:72`); `prefix_duplicate` = bare and `{plugin}:{name}` both in skillUsage (`:88`); `trigger_collision` = same `"/xxx"` in 2+ descriptions (`:90`); writes `/tmp/cc_state.json` despite "Do not modify any files" (`:50`, `:170`).
- session-pattern-analyzer builds `SESSION_GLOB` but then runs `find $HOME/.claude/projects -name "*.jsonl" -mtime -${DAYS}` (`agents/session-pattern-analyzer.md:36-46`); `plan_first_ratio` matches `specify/scaffold/plan/requirements-interview` (`:77`); `parallel_count` = `Agent.run_in_background == true` (`:79`); `completion_check_ratio` looks for `ralph` (`:81`).
- project-automation-auditor reads hooks only from `.claude/settings.json` / `.claude/settings.local.json` (`agents/project-automation-auditor.md:39-41`, `:64-68`); D4 = registered ∩ `session_report.skills_invoked` with no normalisation (`:70-74`); D5 = filename like `verifier|reviewer|audit*` in `agents/` (`:76-77`); planning artifacts = `specs/*/spec.md` or `requirements-interview-outputs/*/insights.md` (`:54-56`, `:89-91`); compounding globs (`:49-52`).
- context-quality-reviewer reads CLAUDE.md, `.claude/rules/*.md`, `.gitignore`, `.claude/settings.json`, `.mcp.json` (`agents/context-quality-reviewer.md:27-35`); never reads `.drift-reports/`.

### Machine facts (checked read-only on this machine, key names only)
- `~/.claude.json`: `skillUsage` present (values `{usageCount, lastUsedAt}`), `enabledPlugins` absent, top-level `mcpServers` absent, `projects` present with 0 entries carrying `mcpServers`.
- `~/.claude/settings.json` has `enabledPlugins` (5 entries, `name@marketplace: true`).
- `~/.claude/plugins/installed_plugins.json` maps `name@marketplace` → list of `{scope, installPath, version}`; `installPath` is `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>`. harness-ops is installed at 0.5.0 while the repo is 0.6.0 (`.claude-plugin/plugin.json`).
- `skillUsage` holds several name generations: `harness:*`, `harness-session:*`, `harness-ops:*`, old names `harness:doc-drift`, `harness-ops:deep-interview`, and bare `loop` next to `harness-ops:loop`.
- `~/.claude/projects/` has 100 top-level session JSONLs and 299 under `<session>/subagents/agent-*.jsonl`.
- Project dirs are encoded by replacing non-alphanumerics with `-` (`/private/tmp/claude-501/-Users-…` → `-private-tmp-claude-501--Users-…`); worktrees appear as `-Users-hyunhokim-IdeaProjects-harness-ops-feat-crew-skill`, which the prefix glob `${ENCODED}*` also matches.
- Session JSONL writes one tool_use per line; parallel calls share one `message.id` across lines (observed in a harness-ops session). `Agent.input.run_in_background` was `null` in 18 of 19 Agent calls sampled.
- A user-typed slash command produces no `Skill` tool_use; it is recorded only as a user message containing `<command-name>/harness-ops:specify</command-name>` (observed in this session's own JSONL).
- `jq`, `python3` (3.14) and `pytest` are installed.

### New skills' on-disk artifacts
- loop: `## Lessons` in `loop.md` with records `form: gate1-command | gate3-item | context`, `status: active | needs-review | retired` (`skills/loop/SKILL.md:109-151`); `progress.md` is transient, deleted on clean exit and gitignored (`skills/loop/SKILL.md:155-166`, `.gitignore` `specs/**/progress.md`).
- build-order: durable `build_order.md` ledger (`skills/build-order/SKILL.md:51-78`).
- crew: `specs/<feature>/pipeline.md` ledger and `brief.md` (`skills/crew/SKILL.md:10`, `:46`, `:121`).
- decompose: `specs/<set>/partition-manifest.md` (`skills/decompose/SKILL.md:78`).
- harness-factory design: `specs/<team>/design.md` (installed plugin `team-design/SKILL.md:19-23`).
- autopilot: durable `autopilot.md` with Config keys `wall_clock_cap_hours`, `max_ticks`, `consecutive_park_cap`, `per_tick_timeout_seconds`, `crash_loop`, `killswitch_path` (`skills/autopilot/references/autopilot-template.md:9-17`); six limits halt the run (`skills/autopilot/SKILL.md:202-206`).
- expert: installs `<project>/.claude/agents/<role>.md` (`skills/expert/SKILL.md:101-106`).
- context-audit: `.drift-reports/<YYYY-MM-DD-HHMM>.md` and `.drift-reports/latest.md` (`skills/context-audit/SKILL.md:88-91`).
- worktree: sibling directory `"$PARENT/<REPO>-<slug>"` (`skills/worktree/SKILL.md:190`).
- Inline checkers cite `capability:spawn-inline-checker` (coherence-audit, agent-orchestrate, crew — `references/runtime-tools.md` › `spawn-inline-checker`).

### Contracts that constrain the change
- Portability: skill bodies name capabilities, not tool names; `scripts/portability-lint.sh` forbids imperative call sites (`Agent(`, `subagent_type=`, `${CLAUDE_PLUGIN_ROOT}`) in listed skills, and listing check-harness brings `agents/*.md` into scope (`scripts/portability-lint.sh:12-20`, `references/converted-skills.md:32-39`). The lint also runs as a plugin PreToolUse hook on Write/Edit (`hooks/hooks.json`).
- Shell arguments must be absolute paths from `capability:resolve-harness-root`; pinned scripts are invoked via `capability:run-command` (`references/runtime-tools.md` › Path rule, Pinned script procedures).
- `spawn-named-checker` requires artifact + registry; only check-harness cites it (`references/runtime-tools.md` › `spawn-named-checker`; grep of `skills agents references`). `spawn-inline-checker` already says an empty agy registry "is not a pass/fail bar on its own" (`references/runtime-tools.md` › `spawn-inline-checker`).
- Line-number citations of check-harness: `skills/expert/SKILL.md:181` (`:176-178`), `skills/crew/references/review-schema.md:7` (`:180-190`) and `:130` (`:176-178`).
- Test runner: `bash skills/coherence-audit/scripts/run-tests.sh` (97 cases, all passing on this branch); sections A–D are hard-coded, nothing is collected by filename pattern. `scripts/test-block-main-push.sh` is a separate table test. No `Makefile`, `package.json`, `pyproject.toml` or CI. agent-orchestrate's acceptance-test writers detect a runner from a configured command first (`Makefile`, `package.json`, …), else existing collected test files (`skills/agent-orchestrate/references/requirement-check.md` §3 step 2).
- Project hooks: `.claude/hooks/protect-meta-files.sh` (PreToolUse on Edit/Write) guards `hooks/hooks.json` and `plugins/`; `block-main-push.sh` guards pushes (`.claude/settings.json`).

## Decisions

### D1: Deterministic collection moves into shipped, tested scripts
- **Status**: assumed
- **Rationale**: Every part-2 bug is a prose bash/jq snippet that drifted from how Claude Code stores data, and nothing tested it or noticed. Collection that has one right answer (file selection, name normalisation, plugin/MCP/hook inventory, session metrics, project signals, project root) moves into Python 3 stdlib scripts under `skills/check-harness/scripts/`, with fixture tests. The analyzers' old "split into batches of 5 and merge" rule is retired: it existed to protect the model's memory, and an LLM merging partial ratios and top-N lists by hand is exactly the retyping this decision removes; `session_metrics.py` streams its input and runs once over the whole list. The four analyzers keep the parts that need judgement (description-duplicate clusters, CLAUDE.md quality, verifier-role reading, D2/D3 hook intent) and stay separate agents, so maker ≠ checker is unchanged. **Who runs them:** each analyzer runs its own scripts, so collection stays on the checker side. An analyzer has no skill directory to resolve a root from (and `${CLAUDE_PLUGIN_ROOT}` is lint-forbidden in `agents/*.md`), so check-harness resolves the root once in Phase 0 with `capability:resolve-harness-root`, validates it with the canonical test from `references/runtime-tools.md` › `resolve-harness-root` — `test -d <root>/skills && test -d <root>/agents && test -f <root>/skills/check-harness/scripts/project_root.py` — else halt `unresolved:` per D13, and passes `harness_root={ROOT}` in every spawn prompt next to `cache_dir`; analyzer bodies invoke `python3 {harness_root}/skills/check-harness/scripts/<file>.py` via `capability:run-command`. Each analyzer applies `test -f` to every script before running it; a missing script is D2's `script failed` path (dependent items N/A), not a halt. **Script output is not retyped:** an analyzer redirects each script's stdout to `{cache_dir}/scratch-<NAME>/<script>.json` (`.txt` for `session_files.py`) and lists those paths in its return under `script_outputs`. Each `script_outputs` entry is `{script, path, status, exit}` with `status` one of `ran`, `failed` (non-zero exit; `exit` holds it), `missing` (the `test -f` failed), `denied` or `unavailable` (`capability:run-command` was refused or does not exist). check-harness reads every script-owned field from the fixed path for that analyzer and script — `{cache_dir}/scratch-<NAME>/<script>.json` (`.txt` for `session_files.py`) — whether or not the analyzer listed it, never from the analyzer's prose or JSON; a fixed-path file that does not exist makes its fields N/A with `warning: script output missing: <path>`. A `denied` or `unavailable` status is not a script failure: it halts the run (D13), because every script-owned item turning N/A would produce a report that looks complete but measured nothing; a fixed-path file that exists but is empty or does not parse as the script's documented output (a redirect creates the file before a crashing script runs) makes its fields N/A with `warning: script failed: <script> (unparseable output)`, whatever the analyzer reported; an analyzer that saw a non-zero exit records `status: failed` with `exit: <n>` on that entry. **Arguments are checked, not trusted:** every JSON-printing script echoes its effective, resolved arguments in a top-level `params` object (e.g. `{"project_root": …, "as_of_ms": …, "dead_days": …}`); `session_files.py --with-params` prints a first line `# params {json}` (`scope`, `project_dir`, `days`), which `session_metrics.py` skips as input and copies into its own output as `params.session_files` next to its own `long_session_min`. check-harness compares each `params` with the values it put in that spawn prompt; any difference makes that script's fields N/A with `warning: script params mismatch: <script>`. Analyzers must pass `--with-params`. This is why analyzers running the scripts is acceptable: the output is read from disk, its arguments are verified, and the only judgement left to the analyzer is the part D1 keeps with it. Only `project_root.py` is run by check-harness itself (Phase 0 needs the root before any spawn); if `capability:run-command` is denied or unavailable there, the run halts per D13; otherwise any exit other than 0 or 3 from it disables Project scope with `warning: script failed: project_root.py exit <n>` in the report, the same as exit 3, never a halt. Rejected for this: check-harness runs every script and hands the output to the analyzers (the orchestrator would then produce all the evidence its checkers judge — maker ≠ checker in name only). Two separate guards, because a fixture only pins the shape it was written against: regressions in the scripts are caught by the fixture tests, and upstream format changes (the actual cause of the part-2 bugs: keys moved out of `~/.claude.json`, `run_in_background` stopped being written) are surfaced as `warning: source missing|unexpected shape` lines (D2) that check-harness shows in the report and turns into N/A for the affected items, instead of a silent 0. Rejected: patching the snippets in place (the same drift recurs, still untested and still silent); one script that also scores the checklist (removes the LLM judgement the analyzers exist for, and scoring is out of scope); `python3 -I` (isolated mode drops the script's own directory from `sys.path`, which breaks the shared module — these are the repo's own files, not untrusted downloads).

### D2: Script command-line contract (shared by all scripts and their tests)
- **Status**: assumed
- **Rationale**: Parallel tasks and the acceptance tests need one fixed interface. Every script is run as `python3 <harness_root>/skills/check-harness/scripts/<file>.py …`, reads the user's files from `$HOME` (so a test points `HOME` at a fixture directory), writes its result to stdout, writes warnings to stderr as lines starting with `warning: ` (scripts that print JSON also copy each warning into the JSON's `warnings` array). Exit codes: 0 success (including degraded success with warnings), 2 usage error (unknown flag, missing required argument), 3 nothing found (`project_root.py` only). Faults never abort a run: an expected source file that is missing gives `warning: source missing: <file>`; a file that does not parse, or a known key whose value has the wrong type, gives `warning: unexpected shape: <file>[.<key>]` and that source is treated as empty; an unparseable JSONL line is skipped with one `warning: skipped <n> unparseable line(s) in <file>` per file; when `git` is missing or fails, every git-derived field is `null` with `warning: git unavailable: <reason>`. Any other exit status (e.g. 1 from an uncaught exception) or stdout that does not parse as the documented output makes the analyzer record `warning: script failed: <file> exit <n>` and report the fields that script feeds as `null`; the dependent items become N/A and the run continues — a script failure is never a D13 halt. check-harness lists every analyzer warning in the report's findings and marks an item N/A (evidence: the warning) when a source it depends on was missing or had an unexpected shape. Shared code lives in `skills/check-harness/scripts/harness_common.py`. Scripts never write files. Files: `skill_name.py`, `inventory.py`, `session_files.py`, `session_metrics.py`, `project_root.py`, `project_signals.py` (contracts in D3–D7, D9, D12, D14, D15, D18). All paths a script prints or encodes are resolved first (`os.path.realpath`), so `/tmp` and `/private/tmp` spellings agree on macOS. Rejected: one multi-command script (every task would edit the same file and serialise); JSON on stderr (callers would have to split streams).

### D3: Skill-name normalisation through one alias table
- **Status**: assumed
- **Rationale**: `skillUsage` and session logs hold several name generations. One table, `skills/check-harness/references/skill-aliases.tsv`, tab-separated `kind<TAB>from<TAB>to`, is the single source; check-harness never hard-codes aliases elsewhere. Kinds: `prefix` (owner rename: `harness`→`harness-ops`, `harness-session`→`harness-ops`), `rename` (whole-key rename, applied after `prefix`, `from` and `to` are full keys: `harness-ops:doc-drift`→`harness-ops:context-audit`, `harness-ops:deep-interview`→`harness-ops:requirements-interview`, `harness-ops:ralph`→`harness-ops:loop`, and the bare old names `doc-drift`→`harness-ops:context-audit`, `deep-interview`→`harness-ops:requirements-interview`, `ralph`→`harness-ops:loop`, since none of those was ever a built-in), `builtin` (bare names shipped with Claude Code that have no SKILL.md on disk, `to` = `-`: loop, schedule, simplify, code-review, review, security-review, init, run, update-config, keybindings-help, fewer-permission-prompts, claude-api, claude-in-chrome, workflow-authoring, dataviz, plugin-authoring), `builtin-namespace` (`anthropic-skills`, `to` = `-`). The normalised key: split the name at the first `:` into owner and skill; map the owner through `prefix`; form `owner:skill` (or bare `skill` when there was no owner); then replace the whole key through `rename` when a row's `from` equals it. A rename never applies to another owner's skill of the same name. The owner is kept so built-in `loop` (key `loop`) and `harness-ops:loop` stay different skills. `skill_name.py NAME…` prints one line per argument: `NAME<TAB>KEY`. Examples: `harness:doc-drift` → `harness-ops:context-audit`; `harness-session:specify` → `harness-ops:specify`; `ralph` → `harness-ops:loop`; `loop` → `loop`; `other-plugin:doc-drift` → `other-plugin:doc-drift`; `harness-ops:deep-interview` → `harness-ops:requirements-interview`; `anthropic-skills:pdf` → `anthropic-skills:pdf`. **Role match** (used by D9 and D16): a key matches a role list when it equals a full key in the list, or when it is bare, is not a `builtin`, and equals a listed skill part (a user's own standalone `specify` counts; the built-in `/loop` scheduler never counts as `harness-ops:loop`). A built-in counts only when the list names it explicitly as a bare built-in. Rejected: strip every prefix to a bare name (merges built-in `/loop` with `harness-ops:loop`, the exact mislabel the request reports); an alias map per analyzer (three copies drift apart).

### D4: Portfolio classification of `skillUsage` keys
- **Status**: assumed
- **Rationale**: Each `skillUsage` key gets exactly one class, decided in this order. (1) **installed** — its normalised key equals an installed skill's key. When the raw key differs from that skill's current key it is also listed as **renamed** history: usage counts summed and `lastUsedAt` maxed into the installed skill, never a ghost. (2) **builtin** — the key is bare and listed as `builtin`, or its owner is a `builtin-namespace`. (3) **prefix_duplicate** — the key is bare; no user-standalone skill, no unowned project-local skill (`.claude/skills/**`) and no built-in has that bare skill name; and exactly one owned skill — an installed plugin skill, or a project skill that D6 gives a plugin owner — has that bare skill name (the same skill recorded twice). "Has that bare skill name" compares the skill part of the D3 key, never the full key. (4) **ghost** — anything else. Separately, **name_collisions**: two or more distinct skills (installed, plus built-ins that appear in `skillUsage`) share a bare skill name, e.g. built-in `loop` and `harness-ops:loop`, or `harness-factory:generate-team` and `harness-ops:generate-team`. A5's `trigger_collisions` = name_collisions ∪ the existing same-`"/xxx"`-in-two-descriptions rule. Rejected: keep "bare + prefixed = duplicate" (calls two different skills one); treat every non-installed key as ghost (built-ins and renames become false ghosts and fail A3).

### D5: Plugin and MCP sources (`inventory.py`)
- **Status**: assumed
- **Rationale**: Installed plugins come from `~/.claude/plugins/installed_plugins.json` (`plugins` map: `name@marketplace` → list of `{scope, installPath, version}`); skills are scanned only under each entry's `installPath`, not every cached version. Enabled: user = `~/.claude/settings.json` `enabledPlugins`; project = `{project_root}/.claude/settings.json` and `.claude/settings.local.json` `enabledPlugins`. MCP servers, each tagged with its scope: `~/.claude.json` top-level `mcpServers` (user), `~/.claude.json` `projects[<key>].mcpServers` where `<key>` resolved with `realpath` equals the resolved `--project-root` (local), `{project_root}/.mcp.json` (project), and for each enabled plugin its `installPath/.mcp.json` and `installPath/.claude-plugin/plugin.json` `mcpServers` (plugin). A missing **file** yields an empty list plus D2's `warning: source missing`, and a malformed file or wrong-typed key yields `unexpected shape` — never an error, never a silent empty. An absent **optional key** (`~/.claude.json` `mcpServers` / `projects`, which Claude Code omits when nothing is configured) is an empty list with no warning; per-project and per-plugin files (`.mcp.json`, `plugin.json`) are optional files, silent when absent. (Amended during execution, 2026-11-02: the literal rule made the MCP items N/A on every machine without user-scope MCP servers.) Only name, scope, source file and `type` (or `stdio` when only `command` is given) are emitted, never `env`, `headers`, `args` or URLs with credentials. Plugin commands are skills for this purpose — Claude Code records `<plugin>:<command>` invocations in `skillUsage` — so each installed plugin's `installPath/commands/*.md` and, in a plugin source tree, `{project_root}/commands/*.md` are scanned too (name = file basename without `.md`, same owner rules; amended during execution, 2026-11-02, after a read-only run classed `harness-ops:generate-team` as a ghost). Skills are scanned from `~/.claude/skills/*/SKILL.md` (user standalone), installed plugin `installPath/skills/*/SKILL.md` (plugin), and `{project_root}/.claude/skills/**/SKILL.md` + `{project_root}/skills/*/SKILL.md` (project local). Without `--project-root`, no project source is read (no project settings, `.mcp.json`, project skills or plugin source tree) — never the cwd. `inventory.py [--project-root P] [--as-of-ms N] [--dead-days 90]` prints one JSON object with keys `params` (`project_root`, `as_of_ms`, `dead_days`, resolved effective values per D1), `summary`, `plugins`, `mcp_servers`, `skills`, `usage` (`renamed`, `builtin`, `prefix_duplicates`, `ghost`, `name_collisions`), `plugin_findings`, `warnings`. `summary` has `total_installed`, `used_last_30d`, `dead_count`, `ghost_count`, `renamed_count`, `prefix_duplicates`, `name_collisions`, `plugins_installed`, `plugins_enabled_user`, `plugins_enabled_project`, `mcp_servers_total`. Each `skills[]` entry has `name`, `key`, `owner`, `source` (`user_standalone|plugin|project_local`), `path`, `usage_count`, `last_used_at`, `dead`; an installed skill is `dead` when its merged `usage_count` is 0 (including no `skillUsage` record) or its `last_used_at` is older than `--as-of-ms` − `--dead-days`. Entry shapes: `plugins[]` = `{id` (`name@marketplace`)`, name, marketplace, version, scope, install_path, enabled_user, enabled_project, skills_count}`; `mcp_servers[]` = `{name, scope, source, type}`; `usage.renamed[]` = `{from` (raw key)`, to` (installed key)`}`; `usage.builtin[]` = raw key strings; `usage.ghost[]` = `{key, usage_count, last_used_at}`; `usage.prefix_duplicates[]` = `{name` (bare skill name)`, skill_key` (the owned skill's key)`, keys` (the raw `skillUsage` keys involved, sorted)`}`; `usage.name_collisions[]` = `{name, keys}` with `keys` sorted; `plugin_findings[]` = `{type, plugin, …}`. In the requirements, "X lists K" means X has an entry whose key (`from` for renamed, `key` for ghost, the string itself for builtin, `name` for prefix_duplicates) equals K. Rejected: keep reading `enabledPlugins`/`mcpServers` from `~/.claude.json` only (both absent on this machine → 0 plugins); glob `~/.claude/plugins/**/plugin.json` (also matches marketplace clones and old cached versions).

### D6: A plugin's own source tree is counted once
- **Status**: assumed
- **Rationale**: Whenever `{project_root}/.claude-plugin/plugin.json` exists, the project's `skills/*/SKILL.md` and `agents/*.md` take that file's `name` as owner (keys `<plugin>:<name>`, source `project_local`) — the same rule in `inventory.py` and `project_signals.py`. If that plugin is also installed, its installed `installPath` skills are skipped, and a `plugin_findings` entry `{"type": "installed_stale", "plugin", "installed_version", "source_version"}` is emitted when the two versions differ (0.5.0 vs 0.6.0 here). Rejected: prefer the installed copy (it is what runs, but it is stale while the user is editing the source, so its descriptions mislead the duplicate check); keep both (every skill becomes its own duplicate).

### D7: Session file selection (`session_files.py`)
- **Status**: assumed
- **Rationale**: Only top-level transcripts count: `~/.claude/projects/<dir>/*.jsonl` at depth 1 inside each project dir; `<session>/subagents/*.jsonl` never counts. A project dir name is the resolved absolute path (`realpath`, so `/tmp/x` encodes as `-private-tmp-x` on macOS) with every character outside `[A-Za-z0-9]` replaced by `-` (observed on this machine); `--project-dir` and every worktree path are resolved before encoding. Project scope = the dir for `--project-dir` exactly, plus the dir of every path in `git -C <project-dir> worktree list --porcelain`. Any other dir whose name starts with the project's encoded name is excluded and reported on stderr as `warning: excluded prefix-matching session dir <name>`. `--project-dir` is required with `--scope project` (absent → exit 2) and ignored with `--scope overall`. When `git worktree list` fails or git is missing, project scope is the exact dir only, with `warning: git unavailable: <reason>`. `session_files.py --scope overall|project [--project-dir P] [--days 30] [--with-params]` prints the selected files, one absolute path per line, sorted, filtered by mtime within `--days`. Rejected: keep the `${ENCODED}*` prefix glob (also matches unrelated siblings such as `harness-ops-old`, and worktrees only by accident); exact dir only (drops worktree sessions, which is where most feature work on this repo happens).

### D8: One 30-day window everywhere
- **Status**: assumed
- **Rationale**: User sessions, Project sessions, A1 and MCP usage all use 30 days, so Axis 4's min(User, Project) compares like with like and the report states one period. 100 top-level sessions in 30 days on this machine is a small input for a script that streams each JSONL line by line. Rejected: keep 7 days for User (faster, but the min() then compares a week with a month).

### D9: Session metric definitions (`session_metrics.py`)
- **Status**: assumed
- **Rationale**: `session_metrics.py [--long-session-min 20] --files-from LIST` reads the transcripts listed in LIST and prints a top-level `params` object `{session_files, long_session_min}`; — a newline-separated file of paths (blank lines and lines starting with `#` ignored as input; a first line `# params {json}` from `session_files.py --with-params` is parsed and echoed as `params.session_files`), or `-` for stdin, so `session_files.py … | session_metrics.py --files-from -` works without a temp file; a listed path that is missing or unreadable is skipped with `warning: unreadable session file: <path>` — and prints one JSON object with `sessions_analyzed`, `total_tool_calls`, `tool_frequency` (top 20), `skills_invoked` and `commands_invoked` (key → count, keys normalised per D3), `agents_invoked` (subagent type → count), `long_sessions` (integer count of sessions lasting ≥ `--long-session-min` minutes), `avg_session_duration_min`, `repeated_bash_commands` (command text before the first pipe → count, ≥5, top 15), `repeated_edit_targets` (path → count, ≥5), `automation_opportunities` (the top 5 tool-name 3-grams as `[{pattern, count}]`, pattern `A→B→C`; the suggestion text stays the analyzer's judgement), `warnings`, and `metrics` with `plan_first_ratio`, `delegation_ratio`, `parallel_count`, `background_flag_count`, `handoff_ratio`, `completion_check_ratio`, `learning_write_sessions`, `top_3gram_share`. **3-grams** are consecutive tool-name triples within one session (never across sessions); `top_3gram_share` = the sum of the 5 most frequent 3-gram counts ÷ all 3-grams, `null` when there are none. `tool_frequency` = `{tool name: count}` for the 20 most used tools, by count descending. "The last 30% of the session's tool calls" = calls with 0-based index ≥ `floor(0.7 × n)`. Session duration = the latest minus the earliest top-level `timestamp` (ISO-8601) among the file's lines; lines without one are ignored, and a file with fewer than two timestamps lasts 0 minutes. The script reads files line by line. A ratio whose denominator is 0 is `null`; every ratio (including `top_3gram_share`) is rounded to 2 decimals. Definitions: `skills_invoked` counts `Skill` tool_use `input.skill`; `commands_invoked` counts user-typed slash commands, taken from user-message lines with a match-only regex on `<command-name>/NAME</command-name>` — no other text of that message is read into a variable or emitted. A session **plans first** when an invoked skill or command role-matches (D3) `harness-ops:specify`, `harness-ops:scaffold`, `harness-ops:requirements-interview`, `harness-ops:decompose`, `harness-ops:crew`, `harness-ops:team-design`, `harness-factory:design`, `harness-factory:team-design`, or an `EnterPlanMode` tool_use occurs. **Delegation**: ≥1 `Agent` (or legacy `Task`) tool_use. **parallel_count**: number of distinct assistant `message.id` values carrying ≥2 `Agent`/`Task` tool_use blocks across their lines; `background_flag_count` keeps the old `run_in_background == true` count for information only. **Handoff** (B4, among long sessions): a `Write`/`Edit`/`MultiEdit` whose `file_path` basename is `progress.md`, `build_order.md`, `pipeline.md`, `autopilot.md` or `MEMORY.md` or whose path contains `/memory/`, or an invoked skill or command whose key's skill part is session-wrap, wrap, compound, remember or handoff (none is a built-in, so any owner counts). **Completion check**: a `Bash` command matching the Python regex `(^|[\s;&|(])(pytest|python3? -m pytest|go test|cargo test|(npm|pnpm|yarn)( run)? test|make test|vitest|jest|bats|\S*(run-tests|_test)\.sh)(\s|$)` in the last 30% of the session's tool calls (the shell builtin `test` is deliberately not a test run), or an invoked skill or command anywhere in the session that role-matches `harness-ops:loop`, `harness-ops:qa`, `harness-ops:build-order` or `harness-ops:autopilot` (the built-in `/loop` scheduler does not). **learning_write_sessions** (E2): sessions with a `Write`/`Edit`/`MultiEdit` to a basename `CLAUDE.md`, `loop.md`, `MEMORY.md`, or a path containing `/.claude/rules/`, `/memory/`, `/docs/learnings/`. Rejected: keep `run_in_background` for B5 (now the default, rarely written → B5 always fails); count lines with ≥2 Agent calls (Claude Code writes one tool_use per line, so that is always 0); ignore typed slash commands (this very session invoked specify with no Skill tool_use, so plan-first is undercounted); read the full user message to find commands (breaks the "never read prompt text" rule for no gain).

### D10: Analyzers return JSON; check-harness saves it
- **Status**: assumed
- **Rationale**: The analyzers have no Write tool and are told to modify nothing, yet were asked to save files. Now: each analyzer's final message is the JSON report only; check-harness (which has `capability:write-file`) saves each return to `{cache_dir}/<NAME>.json`. Analyzers may create scratch files only under `{cache_dir}/scratch-<NAME>/`, keyed by report name (`scratch-SESSION_USER`, `scratch-SESSION_PROJECT`, `scratch-PORTFOLIO`, `scratch-CONTEXT`, `scratch-AUTOMATION`), because session-pattern-analyzer runs twice in parallel, and nowhere else (this replaces `/tmp/cc_state.json`, `/tmp/cc-cache/sessions.txt` and `/tmp/cc-cache/scripts.json`). Their hard rule reads "Do not create or modify any file outside `{cache_dir}/scratch-<NAME>/`" (so an analyzer can never overwrite another's saved report). The artifact assertion becomes: the return parses as one JSON object that has the report's required top-level keys, and it was saved. Required keys — analyzer-owned only; an analyzer does not repeat script-owned fields: PORTFOLIO `duplicate_clusters`, `trigger_collisions`, `mcp_usage` (`[{name, scope, call_count_30d}]`), `unused_mcp`, `quick_wins`, `script_outputs`, `warnings`; SESSION_USER / SESSION_PROJECT `scope`, `period_days`, `automation_suggestions` (`[{pattern, suggestion}]`), `script_outputs`, `warnings`; CONTEXT `project_root`, `claude_md`, `rules`, `sensitive_protection`, `conditional_load_evidence`, `mcp`, `drift_report`, `script_outputs`, `warnings`; AUTOMATION `project_root`, `test_runner_configured`, `test_evidence`, `posttool_format_hook`, `posttool_format_evidence`, `pretool_block_hook`, `pretool_block_evidence`, `verifier_agents`, `isolation`, `risk_findings`, `script_outputs`, `warnings`. CONTEXT and AUTOMATION may also carry `weak_pass_flags` (`[{field, reason}]`), read by Phase 2's WEAK_PASS rule. (`posttool_format_evidence` and the optional `weak_pass_flags` were added during execution, 2026-11-02, so D2 has evidence like D3.) **Source rule for Phase 2:** a report name followed by a script-owned field means that field of the report's fixed-path script file — `PORTFOLIO.<f>` → `scratch-PORTFOLIO/inventory.json`, `SESSION_*.<f>` → `scratch-SESSION_*/session_metrics.json`, `AUTOMATION.<f>` → `scratch-AUTOMATION/project_signals.json` (e.g. `AUTOMATION.unattended`, `AUTOMATION.checker_citations`, `AUTOMATION.skills`); every other field comes from the saved analyzer return. Rejected: give analyzers Write (widens a read-only checker's power); let them write via Bash heredocs (works or not depending on the run's reading of the rules — the current flakiness).

### D11: Per-run cache directory
- **Status**: assumed
- **Rationale**: Phase 0 creates `CACHE_DIR` with `mktemp -d "${TMPDIR:-/tmp}/cc-cache/check-harness/run.XXXXXX"` (after `mkdir -p` of the parent) then creates the five directories `{CACHE_DIR}/scratch-PORTFOLIO`, `scratch-SESSION_USER`, `scratch-SESSION_PROJECT`, `scratch-CONTEXT`, `scratch-AUTOMATION` before any spawn, and passes `cache_dir={CACHE_DIR}` and `harness_root={ROOT}` (D1) to every analyzer, plus `as_of_ms=` (recorded once in Phase 0) to the analyzers whose scripts take `--as-of-ms`, so every script argument is one check-harness chose and can compare with `params`. Two concurrent runs or two worktrees can no longer overwrite each other. Hard Rule 8 (cache reuse) refers to that run's directory, and the report footer prints it. Rejected: key the dir by project name (two runs on one project still collide); delete the dir at the end (breaks follow-up reuse).

### D12: Project-root discovery never lands on `$HOME`
- **Status**: assumed
- **Rationale**: `project_root.py [DIR]` (default: cwd): if DIR is inside a git work tree, the root is `git rev-parse --show-toplevel`; otherwise walk up from DIR looking for `.claude/` or `CLAUDE.md`, where `$HOME` and every ancestor of `$HOME` never qualify. Found → print the resolved absolute path (`realpath`), exit 0. Not found → print nothing on stdout, print `no project root: <reason>` on stderr, exit 3; check-harness then disables Project scope and says why in the report. A git toplevel equal to `$HOME` (a dotfiles repo) also counts as not found. Rejected: keep the walk-up only (`~/.claude` always exists, so any folder without a project becomes `$HOME`); require git (projects without git lose Project scope).

### D13: Delegation evidence on agy follows the inline-checker rule
- **Status**: assumed
- **Rationale**: `references/runtime-tools.md` already says an empty agy registry is not a pass/fail bar for `spawn-inline-checker`; check-harness halting on it makes the skill unusable on agy. Only check-harness cites `spawn-named-checker`, but `spawn-inline-checker` ("Same assertion requirement as `spawn-named-checker` above") and `spawn-worker` (which inherits from `spawn-inline-checker`) point at it, so those two entries are rewritten to state their current rule in full instead of inheriting, and their behaviour is unchanged. The new `spawn-named-checker` rule: per analyzer, the spawn's return is required evidence; under agy `manage_subagents` is read and recorded; an empty registry is recorded as `spawn return only (agy registry empty)` and the run continues; a registry that lists other subagents but not this analyzer is a halt. check-harness still halts, with one prefix per condition: spawn tool missing → `unavailable: spawn-named-checker not provided by <runtime>`; spawn denied → `denied: …`; root validation fails → `unresolved: …`; a return is missing or does not parse as the report, or the registry lists others but not this analyzer → `failed: spawn-named-checker returned no usable result (<analyzer>: <reason>)`, a new row T8 adds to `references/runtime-tools.md` › `## Halting`; `capability:run-command` refused or missing — in Phase 0's `project_root.py` call, or reported by any analyzer as a `script_outputs` status — → `denied: run-command requires permission not granted (<where>)` or `unavailable: run-command not provided by <runtime> (<where>)`, the map's existing rows. Only a script that actually ran and failed takes D2's N/A path. The scorecard footer states the evidence grade per analyzer. Rejected: keep halting (no agy run can ever finish); drop the registry check entirely (loses the stronger signal where agy provides it).

### D14: Hook sources for D2, D3 and C3 (`project_signals.py` `hooks`)
- **Status**: assumed
- **Rationale**: Hooks that apply in a project come from several files. `hooks` lists every hook as `{source, event, matcher, command}` from: `{project_root}/.claude/settings.json` (`project`), `.claude/settings.local.json` (`project_local`), `~/.claude/settings.json` (`user`), `{project_root}/hooks/hooks.json` when `{project_root}/.claude-plugin/plugin.json` exists (`plugin_source`), and each enabled plugin's `installPath/hooks/hooks.json` (`plugin:<name@marketplace>`). Whether a command formats, lints or blocks stays the auditor's judgement, with the source in the evidence; context-quality-reviewer's C3 `hook_exists` reads the same list. Rejected: read only `.claude/settings.json` (misses this repo's portability-lint PreToolUse hook and every plugin hook).

### D15: New artifacts feed existing items (`project_signals.py`)
- **Status**: assumed
- **Rationale**: `project_signals.py --project-root P [--as-of-ms N]` prints one JSON object with `params`, `plugin_source`, `hooks`, `planning_artifacts`, `ledgers`, `lessons`, `skills`, `agents`, `checker_citations`, `unattended`, `compounding`, `warnings`. `skills` lists `{path, name, key}` for `skills/*/SKILL.md` and `.claude/skills/**/SKILL.md` (the same set D4/D5 register), plus `commands/*.md` in a plugin source tree (name = basename; amended during verification, 2026-11-02, to match D5's commands rule) (frontmatter `name`; key per D6: plugin-owned in a source tree, bare under `.claude/skills/`) — Phase 2 reads D4's registered set from `skills[].key` and `agents[].key` directly (D10 source rule). Mapping: **B2** fallback — `planning_artifacts` counts `specs/*/spec.md`, `specs/*/partition-manifest.md`, `specs/*/design.md`, `specs/*/brief.md`, `requirements-interview-outputs/*/insights.md` per kind, with `exist` true when any count > 0. **Ledger search.** `loop.md`, `autopilot.md`, `build_order.md` and `pipeline.md` are searched for under the root, excluding `.git/`, `node_modules/`, `.claude/skills/`, `skills/`, `agents/`, `references/` and any `tests/` directory — those hold skill bodies, parity stubs, templates and fixtures (`.claude/skills/loop.md` and `skills/loop/SKILL.md` both contain a lesson skeleton; `.claude/skills/autopilot.md` contains a `## Config`/`## State` copy with `<…>` placeholders). A found file is a real ledger only by structure: a `loop.md` counts for lessons when it has a line that is exactly `## Lessons` (optionally followed by whitespace and text) and under it ≥1 `### ` record with a `- form: ` line holding a single value (`gate1-command`, `gate3-item` or `context`, not the template's `a | b | c`); an `autopilot.md` counts when its `## State` section (a line starting `## State`, optionally followed by whitespace and text — the same heading rule applies to `## Config` and `## Lessons`, since the real template writes `## Config   (human-approved …)`) has a `run_started_at` with a non-placeholder value (a template or skill copy has `<ts>`; the Config defaults are real numbers even in the template, so Config cannot tell them apart), and otherwise is ignored with `warning: template-only autopilot.md: <path>`. **Value parsing** (used here and by D18): for a line `- key: value`, take the text after the first `:`, drop a trailing ` #…` comment, trim; the value is a placeholder when it is empty, `—`, or contains a `<…>` span. **E1** — adds `lessons.updated_30d`: true when a real-ledger `loop.md` has a commit within 30 days. **E3** — adds `lessons.hardened_added_90d` (added lines that are exactly `- form: gate1-command` or `- form: gate3-item`, after trimming trailing whitespace, in commits within 90 days to the real-ledger `loop.md` files) and `compounding.agents_added_90d` (files added under `agents/` or `.claude/agents/` within 90 days); E3 passes on skills, hooks, agents or hardened lessons. **B4/E2** come from D9's handoff and learning-write signals. `ledgers` = `{build_order, pipeline, autopilot}`, integer counts of found files (evidence only; `progress.md` is transient and gitignored, so it is not a durable signal). `lessons` = `{files, updated_30d, hardened_added_90d}`, `files` being the root-relative paths of real-ledger `loop.md` files. `compounding` = `{claude_md_updated_30d` (a commit touching `CLAUDE.md` within 30 days)`, rules_added_90d` (files added under `.claude/rules/`)`, skills_added_90d` (`SKILL.md` files added under `skills/` or `.claude/skills/`)`, hooks_added_90d` (distinct files changed under `hooks/`, `.claude/hooks/` or `.claude/settings.json`)`, agents_added_90d, docs_learnings_exist` (`docs/learnings/` holds ≥ 1 file; not git-derived)`}`, the 90-day counts using `git log --diff-filter=A` (added) or any change (hooks) since `--as-of-ms` − 90 days; git-derived fields are `null` when git is unavailable. These are the auditor's existing E1/E3 inputs, now computed by the script. The search walks the tree without following directory symlinks (this repo's `plugins/harness-ops -> ../` would otherwise loop). **D4** — registered = `skills/*/SKILL.md`, `.claude/skills/**/SKILL.md`, `commands/*.md` (plugin source tree), `agents/*.md`, `.claude/agents/*.md`; skills are compared with `skills_invoked ∪ commands_invoked`, agents with `agents_invoked`, all as D3 keys: in a plugin source tree (D6) `skills/*` and `agents/*.md` are keyed `<plugin>:<name>` (agent name from frontmatter `name`, e.g. `harness-ops:session-pattern-analyzer`, the form Claude Code records as the subagent type), while `.claude/skills/**` and `.claude/agents/*.md` are keyed bare (e.g. `git-operator`). `agents` lists `{path, name, key, description, analyzer}` for `agents/*.md` and `.claude/agents/*.md`, with `analyzer: true` for check-harness's four analyzers. Every path the script prints in `lessons.files`, `checker_citations`, `agents[].path` and `unattended.autopilot_files[].path` is root-relative. `checker_citations` is a list of path strings: project skill files (`skills/*/SKILL.md`, `skills/*/references/*.md`, `.claude/skills/**/*.md`) citing `capability:spawn-inline-checker` or `capability:spawn-named-checker`, excluding `skills/check-harness/`. Rejected: a new axis for these (they are the same kinds of evidence the existing items already judge).

### D16: D5 judges set-up and use of a separate checker
- **Status**: assumed
- **Rationale**: Set up = a verifier-role agent in `agents/` or `.claude/agents/` (judged from name and description) that is not one of check-harness's four analyzers, or a `checker_citations` entry. Used = project sessions invoked a skill or command that role-matches (D3) `harness-ops:specify`, `harness-ops:loop`, `harness-ops:coherence-audit`, `harness-ops:crew` or `harness-ops:agent-orchestrate`, or the built-in `code-review` named explicitly (each runs a separate checker; the built-in `/loop` scheduler does not), or a set-up verifier agent appears in `agents_invoked`. PASS = set up and used; WEAK_PASS = only one; FAIL = neither. The four analyzers judge the harness, not the project's output, so they no longer pass D5 for this repo. Rejected: keep the filename match (`context-quality-reviewer.md` and `project-automation-auditor.md` pass it today — a false PASS); count invocations alone (Behavioral only, ignoring the Static side the axis measures).

### D17: C2 has one judge; the drift report corroborates
- **Status**: assumed
- **Rationale**: context-quality-reviewer stays the C2 judge. It also reads `{project_root}/.drift-reports/latest.md` when present and reports `drift_report: {path, generated, contradictions}` (contradiction findings counted from the report's own findings list, or `null` when it cannot tell). C2: reviewer count > 0 → FAIL as today; reviewer count 0 and a drift report generated within 30 days lists ≥1 contradiction → WEAK_PASS with the report path as evidence; otherwise as today. Rejected: replace the reviewer with the drift report (it is optional and often absent); average the two (two judges again, the problem the request names).

### D18: Unattended safety is one new Verification item, D6 (L3)
- **Status**: assumed
- **Rationale**: The request says the 6-axis structure holds, and unattended safety is about trusting output produced with nobody watching — Axis 5's question. New item **D6 — Unattended runs are bounded** (L3, AUTOMATION `unattended`): N/A when the project has no real-ledger `autopilot.md` (D15's search and structure rule — skill stubs and templates are never ledgers); PASS when every such `autopilot.md`'s `## Config` gives all six limits — `wall_clock_cap_hours`, `max_ticks`, `consecutive_park_cap`, `per_tick_timeout_seconds`, `crash_loop`, `killswitch_path` — a value that is not a placeholder under D15's value parsing (so `killswitch_path: <runDir>/STOP` is a placeholder); FAIL otherwise, naming the file and missing keys. `project_signals.py` reports `unattended: {autopilot_files: [{path, missing_limits}], conforming}` with `conforming` `null` when there are no files. Worktree isolation is not scored (Known Gaps). Rejected: a 7th axis (changes the cycle, the matrix and every score formula — a non-goal); fold into D3 (D3 is about blocking individual dangerous commands, not bounding a run).

### D19: Item count, level tallies and field names agree
- **Status**: assumed
- **Rationale**: With D6 the checklist has 26 items: L1 9, L2 10, L3 7 (L3 gains D6). Every place that states a count says 26: SKILL.md frontmatter, Phase 2 sentence and template summary; `checklist.md` header, Axis 5 header ("7 items") and footer ("L1: 9 items, L2: 10 items, L3: 7 items"); Axis 6 header becomes "[4 items]"; the `html-template.html` footer (`26 items · 6 axes`); `README.md` (`.claude/skills/check-harness.md` follows SKILL.md through its symlink). B6's field is `top_3gram_share` everywhere (the producer's name). Rejected: keep "24" and drop an item (none is redundant).

### D20: A discoverable test command
- **Status**: assumed
- **Rationale**: The repo has no command a test writer can discover (no Makefile, package.json, pyproject or CI), and run-tests.sh collects nothing by pattern. Add a root `Makefile` whose `test` target runs `bash skills/coherence-audit/scripts/run-tests.sh` and `bash scripts/test-block-main-push.sh`, and add a section E to run-tests.sh that runs every `skills/*/tests/*_test.sh` (sorted) and counts each file's exit status as one case. Acceptance tests for this spec are `skills/check-harness/tests/tt{n}_{topic}_test.sh`; each builds its own fixture `HOME` and repos under `mktemp -d` and never reads the real `~/.claude`. Rejected: pytest (no existing pytest tests or config, so the detection rule would not find it, and it adds a dependency to a bash-only suite); a new runner script (still undiscoverable).

### D21: Citations by section, and the docs that describe check-harness
- **Status**: assumed
- **Rationale**: `skills/expert/SKILL.md` and `skills/crew/references/review-schema.md` cite `check-harness/SKILL.md` by line number, which this change breaks. They cite the section instead: `skills/check-harness/SKILL.md` › "Delegation assertion". `references/converted-skills.md` lists check-harness's required procedure ids as `spawn-named-checker, resolve-harness-root, run-command`. `evals/evals.json` is rewritten to current names and gains evals for: agy with an empty registry (continues, grade recorded), a missing analyzer return (halts naming which), the HTML report (no literal `{{` left), and the new artifacts (loop lessons, ledgers, autopilot limits). README describes 26 items and the scripts. Rejected: update the line numbers (break again on the next edit).

### D22: Cross-analyzer joins are computed by check-harness in Phase 2
- **Status**: assumed
- **Rationale**: All analyzers are spawned in one message and, under D10, no report exists on disk until check-harness saves the returns, so project-automation-auditor can never read `SESSION_PROJECT` (its `session_report=` input is dropped). Each analyzer reports only its own facts, and Phase 2 joins them from the saved reports: **D4** = AUTOMATION `skills[].key` / `agents[].key` (D3 keys, from `project_signals.py`) ∩ SESSION_PROJECT `skills_invoked ∪ commands_invoked` / `agents_invoked`; **D5 Used** (D16) = SESSION_PROJECT role match, or an AUTOMATION `verifier_agents` key in SESSION_PROJECT `agents_invoked`; **D5 Set up** = AUTOMATION `verifier_agents` (the auditor's role judgement, analyzers excluded) or `checker_citations`; **B4** = SESSION_* `handoff_ratio ≥ 0.5` (as today); **E2** = `learning_write_sessions ≥ 1` in either session report, OR any key in `skills_invoked ∪ commands_invoked` whose skill part is in D9's handoff list (session-wrap, wrap, compound, remember, handoff). With Project scope off or SESSION_PROJECT N/A, D4 and D5-Used are N/A. The per-axis source table in SKILL.md names the report each field comes from. Rejected: spawn the auditor after the session analyzer (serialises Phase 1, against Hard Rule 5); have the auditor run the session scripts itself (two analyzers would compute the same metrics and could disagree).

## Constraints
- `scripts/portability-lint.sh --sweep` stays clean: `skills/check-harness/SKILL.md` and `agents/*.md` name capabilities (`capability:run-command`, `capability:resolve-harness-root`, `capability:write-file`, `capability:spawn-named-checker`), never imperative tool call sites such as `Agent(`, `subagent_type=` or `${CLAUDE_PLUGIN_ROOT}`.
- Never read or emit prompt text: the only exception is D9's match-only `<command-name>` extraction.
- Read-only on `~/.claude*` and on the project: scripts write nothing; analyzers write only under `{cache_dir}`; check-harness writes only `{cache_dir}/*.json` and `.harness/check-reports/`.
- Never copy secret values (MCP `env`, `headers`, `args`, credentialed URLs) into any output.
- Python 3 standard library only; no new dependencies. Bash tests use only tools the existing suite uses (`bash`, `git`, `jq`, `python3`, coreutils).
- Edit files through their repo-root paths, never via `plugins/harness-ops/…` (`.claude/hooks/protect-meta-files.sh` blocks any path containing `/plugins/`); `hooks/hooks.json` is not changed.
- `.claude/skills/check-harness.md` stays a symlink to `../../skills/check-harness/SKILL.md`; no task edits or replaces it.
- The existing 97 run-tests.sh cases and `scripts/test-block-main-push.sh` stay green.
- No other skill's artifact format changes (loop, build-order, crew, autopilot, decompose, expert, context-audit are read, not edited — except D21's two citation lines).
- Acceptance tests never read the real `~/.claude` or the user's session logs.

## Known Gaps
- Worktree isolation of unattended runs is not scored: a finished run leaves no reliable on-disk trace of which branch or worktree it ran on. D6 scores limits and the kill switch only.
- The `builtin` list in `skill-aliases.tsv` is static and will lag new Claude Code releases; an unlisted built-in shows as a ghost until the table is updated.
- Sessions from a worktree that has since been removed are excluded from Project scope (D7 uses the live `git worktree list`) and only appear in the stderr warning.
- `installed_plugins.json`'s shape is observed, not documented; a future Claude Code change to it needs a matching script update (the fixture tests pin the observed shape).
- MCP usage is still estimated by grepping `mcp__<server>__` tool names in session logs; claude.ai connector servers that appear in no config file are not inventoried.
- No end-to-end `/check-harness` run against this machine is part of this change (Non-goals); the scores' real-world effect is unconfirmed until someone runs it.
- L2-reviewer: the third review (the last retry) returned NEEDS_FIX on D1 (script output retyped by the analyzers), D4/D6 (prefix_duplicate in a plugin source tree), D9 (elided test regex, untyped fields), D1 root validation, `project_root.py` faults and E2's basis. Each was fixed in the decisions above but not re-reviewed at L2; the L4 Spec Review checks them.

## Requirements

Conventions for every GWT below: `S` = `skills/check-harness/scripts`; a script is run from the repo root as `python3 S/<file>.py …` with `HOME` set to a fixture directory built under `mktemp -d`; "warning `X`" means a stderr line starting `warning: X` (and, for JSON-printing scripts, the same text in the JSON `warnings` array).

### R0: check-harness is current, and the repo has one discoverable test command — D20, D21, D19

#### R0.1: `make test` runs both suites and the check-harness tests
- **Given**: the repo root with `skills/check-harness/tests/*_test.sh` files present
- **When**: `make test` is run from the repo root
- **Then**: it runs `bash skills/coherence-audit/scripts/run-tests.sh` (whose new section E runs every `skills/*/tests/*_test.sh`, one case per file) and `bash scripts/test-block-main-push.sh`, and exits 0 only when every case of both passes

#### R0.2: A failing collected test fails the run
- **Given**: a `skills/*/tests/*_test.sh` file that exits 1
- **When**: `bash skills/coherence-audit/scripts/run-tests.sh` is run
- **Then**: the summary reports that file as a FAIL case and the script exits 1

#### R0.3: Portability sweep stays clean
- **Given**: the finished change
- **When**: `scripts/portability-lint.sh --sweep` is run
- **Then**: it exits 0

#### R0.4: No line-number citations of check-harness remain outside it (manual)
- **Given**: the finished change
- **When**: `grep -rn 'check-harness/SKILL.md:[0-9]' skills agents references README.md` is run, excluding `skills/check-harness/`
- **Then**: it prints nothing

### R1: Skill names normalise through one alias table — D3, D2

#### R1.1: Old owners map to harness-ops
- **Given**: `skills/check-harness/references/skill-aliases.tsv` as specified in D3
- **When**: `python3 S/skill_name.py harness:specify harness-session:qa` is run
- **Then**: stdout is exactly two lines, `harness:specify<TAB>harness-ops:specify` then `harness-session:qa<TAB>harness-ops:qa`, and the exit status is 0

#### R1.2: Renamed skills map to their current key, bare old names included
- **Given**: the alias table
- **When**: `python3 S/skill_name.py harness:doc-drift harness-ops:deep-interview ralph deep-interview` is run
- **Then**: the keys printed are `harness-ops:context-audit`, `harness-ops:requirements-interview`, `harness-ops:loop`, `harness-ops:requirements-interview`, in argument order

#### R1.3: Owners are kept and renames never cross owners
- **Given**: the alias table
- **When**: `python3 S/skill_name.py loop other-plugin:doc-drift anthropic-skills:pdf harness-ops:loop` is run
- **Then**: the keys printed are `loop`, `other-plugin:doc-drift`, `anthropic-skills:pdf`, `harness-ops:loop`

#### R1.4: No arguments is a usage error
- **Given**: any environment
- **When**: `python3 S/skill_name.py` is run with no arguments
- **Then**: the exit status is 2 and stdout is empty

### R2: The portfolio inventory reads Claude Code's real storage — D4, D5, D6, D2

#### R2.1: Plugins come from installed_plugins.json and settings
- **Given**: a fixture `HOME` whose `.claude/plugins/installed_plugins.json` lists `alpha@mkt` (installPath `…/cache/mkt/alpha/1.0.0`, version `1.0.0`) and `beta@mkt`, whose `.claude/settings.json` has `enabledPlugins: {"alpha@mkt": true}`, and a project root whose `.claude/settings.json` has `enabledPlugins: {"beta@mkt": true}`
- **When**: `python3 S/inventory.py --project-root <root>` is run
- **Then**: the JSON `plugins` has both entries with `version`, `install_path`, `alpha` `enabled_user: true`, `beta` `enabled_project: true`; `summary.plugins_installed` is 2, `plugins_enabled_user` 1, `plugins_enabled_project` 1

#### R2.2: Only each plugin's installPath is scanned for skills
- **Given**: the R2.1 fixture with `cache/mkt/alpha/1.0.0/skills/a1/SKILL.md` and an older `cache/mkt/alpha/0.9.0/skills/a1/SKILL.md`
- **When**: `python3 S/inventory.py --project-root <root>` is run
- **Then**: `skills` contains exactly one entry with key `alpha:a1`, whose `path` is under `1.0.0/`

#### R2.3: MCP servers come from every source, scoped, without secrets
- **Given**: a fixture with an MCP server in `~/.claude.json` `mcpServers`, one in `~/.claude.json` `projects[<root>].mcpServers` with `<root>` written in its unresolved spelling (e.g. `/var/…` for a `/private/var/…` temp dir on macOS, or via a symlink), one in `<root>/.mcp.json`, and one in enabled plugin `alpha`'s `installPath/.mcp.json`; each server has `env: {"TOKEN": "s3cr3t-value"}` and `args`
- **When**: `python3 S/inventory.py --project-root <root>` is run
- **Then**: `mcp_servers` lists all four with `scope` `user`, `local`, `project`, `plugin`; `summary.mcp_servers_total` is 4; the string `s3cr3t-value` appears nowhere in stdout

#### R2.4: Missing or malformed sources warn instead of silently returning empty
- **Given**: a fixture `HOME` with no `installed_plugins.json` and a `~/.claude.json` that is not valid JSON
- **When**: `python3 S/inventory.py` is run
- **Then**: the exit status is 0; `plugins` is `[]`; stderr has warning `source missing` naming `installed_plugins.json` and warning `unexpected shape` naming `.claude.json`; both appear in the JSON `warnings`

#### R2.5: Renamed history merges into the installed skill
- **Given**: an installed plugin `harness-ops@mkt` with skill `context-audit`, and `~/.claude.json` `skillUsage` holding `harness:doc-drift` (`usageCount` 3) and `harness-ops:context-audit` (`usageCount` 2)
- **When**: `python3 S/inventory.py` is run
- **Then**: the `harness-ops:context-audit` entry of `skills` has `usage_count` 5; `usage.renamed` lists `harness:doc-drift`; `usage.ghost` does not; `summary.ghost_count` is 0

#### R2.6: Built-ins are not ghosts, and same-name skills collide
- **Given**: an installed `harness-ops@mkt` with skill `loop`, and `skillUsage` with `loop` and `harness-ops:loop`
- **When**: `python3 S/inventory.py` is run
- **Then**: `usage.builtin` lists `loop`; `usage.ghost` and `usage.prefix_duplicates` do not; `usage.name_collisions` has an entry whose keys are `loop` and `harness-ops:loop`

#### R2.7: A bare record of one owned skill is a prefix duplicate
- **Given**: an installed plugin skill `alpha:report` (no built-in or standalone `report`), and `skillUsage` with `report` and `alpha:report`
- **When**: `python3 S/inventory.py` is run
- **Then**: `usage.prefix_duplicates` has an entry for `report` listing both keys; `summary.prefix_duplicates` is 1

#### R2.8: Unknown keys are ghosts
- **Given**: `skillUsage` with `vanished-skill` and `gone:thing`, neither installed, built-in nor aliased
- **When**: `python3 S/inventory.py` is run
- **Then**: `usage.ghost` lists both and `summary.ghost_count` is 2

#### R2.9: A plugin's source tree is counted once and a stale install is reported
- **Given**: a project root with `.claude-plugin/plugin.json` `{"name": "alpha", "version": "1.1.0"}` and `skills/a1/SKILL.md`, plus the installed `alpha@mkt` 1.0.0 with `skills/a1/SKILL.md`; `skillUsage` has `a1`
- **When**: `python3 S/inventory.py --project-root <root>` is run
- **Then**: `skills` has exactly one `alpha:a1`, with `source` `project_local` and `path` under the project root; `plugin_findings` has `{"type": "installed_stale", "plugin": "alpha", "installed_version": "1.0.0", "source_version": "1.1.0"}`; `usage.prefix_duplicates` lists `a1`

#### R2.10: Dead and used-in-30-days counts follow --as-of-ms and --dead-days
- **Given**: two installed skills, one with `lastUsedAt` 10 days before `--as-of-ms` and one 100 days before
- **When**: `python3 S/inventory.py --as-of-ms <T> --dead-days 90` is run
- **Then**: `summary.used_last_30d` is 1, `summary.dead_count` is 1, and only the older skill has `dead: true`

#### R2.11: inventory.py echoes its effective arguments
- **Given**: a fixture with a symlinked project root `<tmp>/link` → `<tmp>/proj`
- **When**: `python3 S/inventory.py --project-root <tmp>/link --as-of-ms 1000 --dead-days 45` is run
- **Then**: `params` is `{"project_root": "<resolved tmp>/proj", "as_of_ms": 1000, "dead_days": 45}`

### R3: Session files are the right transcripts over 30 days — D7, D8, D2

#### R3.1: Subagent transcripts never count
- **Given**: a fixture `HOME/.claude/projects/-p/` with `s1.jsonl` and `s1/subagents/agent-x.jsonl`, both modified today
- **When**: `python3 S/session_files.py --scope overall` is run
- **Then**: stdout is exactly the absolute path of `s1.jsonl`

#### R3.2: Project scope is the exact dir plus live worktrees
- **Given**: a git repo at `<tmp>/proj` with a worktree at `<tmp>/proj-wt`, and project dirs for the encoded `<tmp>/proj`, `<tmp>/proj-wt` and `<tmp>/proj-old` (not a worktree), each with one session today (`<tmp>` resolved)
- **When**: `python3 S/session_files.py --scope project --project-dir <tmp>/proj` is run
- **Then**: stdout lists the sessions of `proj` and `proj-wt` only, sorted; stderr has warning `excluded prefix-matching session dir` naming the `proj-old` dir

#### R3.3: The window defaults to 30 days
- **Given**: sessions with mtimes 5, 25 and 40 days ago
- **When**: `python3 S/session_files.py --scope overall` is run, then again with `--days 7`
- **Then**: the first run lists the 5- and 25-day sessions; the second lists only the 5-day one

#### R3.4: Paths are resolved before encoding
- **Given**: a symlink `<tmp>/link` → `<tmp>/proj` and a project dir encoded from the resolved `<tmp>/proj`
- **When**: `python3 S/session_files.py --scope project --project-dir <tmp>/link` is run
- **Then**: stdout lists that dir's session

#### R3.5: Project scope requires --project-dir
- **Given**: any fixture
- **When**: `python3 S/session_files.py --scope project` is run
- **Then**: the exit status is 2

#### R3.6: A non-git project dir falls back to the exact dir
- **Given**: `<tmp>/plain` that is not a git repo, with its encoded project dir holding one session
- **When**: `python3 S/session_files.py --scope project --project-dir <tmp>/plain` is run
- **Then**: stdout lists that session, the exit status is 0, and stderr has warning `git unavailable`

#### R3.7: --with-params echoes the effective arguments
- **Given**: any fixture
- **When**: `python3 S/session_files.py --scope project --project-dir <tmp>/proj --days 7 --with-params` is run
- **Then**: the first stdout line is `# params ` followed by JSON with `scope` `project`, `project_dir` the resolved `<tmp>/proj`, and `days` 7; the remaining lines are the session paths

### R4: Session metrics measure what Claude Code records today — D9, D3, D2

#### R4.1: Parallel spawns are counted per message id
- **Given**: a transcript where one assistant `message.id` spans two lines each holding one `Agent` tool_use, and another message id holds a single `Agent` tool_use with `run_in_background: true`
- **When**: `python3 S/session_metrics.py --files-from <list>` is run
- **Then**: `metrics.parallel_count` is 1 and `metrics.background_flag_count` is 1

#### R4.2: Typed slash commands are counted without reading the prompt
- **Given**: a transcript with a user line whose content is `<command-name>/harness-ops:specify</command-name><command-args>SECRET-PROMPT-TEXT</command-args>`
- **When**: `python3 S/session_metrics.py --files-from <list>` is run
- **Then**: `commands_invoked` has `harness-ops:specify: 1`; `metrics.plan_first_ratio` is 1.0; `SECRET-PROMPT-TEXT` appears nowhere in stdout or stderr

#### R4.3: Plan-first uses role match and plan mode
- **Given**: three transcripts: one with `Skill` input `harness:specify`, one with an `EnterPlanMode` tool_use, one with `Skill` input `loop`
- **When**: `python3 S/session_metrics.py --files-from <list>` is run
- **Then**: `metrics.plan_first_ratio` is 2/3 (rounded to 2 decimals: 0.67), and `skills_invoked` has `harness-ops:specify` and `loop`

#### R4.4: Handoff counts ledger and memory writes in long sessions
- **Given**: two transcripts lasting 30 minutes — one with a `Write` to `…/specs/x/build_order.md`, one with no such write — and one 5-minute transcript with an `Edit` to `…/memory/MEMORY.md`
- **When**: `python3 S/session_metrics.py --long-session-min 20 --files-from <list>` is run
- **Then**: `long_sessions` is 2 and `metrics.handoff_ratio` is 0.5

#### R4.5: Completion check uses test commands late in the session or harness-ops loop skills, never the built-in loop
- **Given**: transcripts: A — 10 tool calls, the 9th a `Bash` `bash skills/coherence-audit/scripts/run-tests.sh`; B — `Skill` `harness-ops:loop` as its first call; C — `Skill` `loop` and a `Bash` `test -f x` as its last call
- **When**: `python3 S/session_metrics.py --files-from <list>` is run
- **Then**: `metrics.completion_check_ratio` is 0.67

#### R4.6: Learning writes are counted per session
- **Given**: transcripts with an `Edit` to `…/CLAUDE.md`, a `Write` to `…/.claude/rules/style.md`, and one with neither
- **When**: `python3 S/session_metrics.py --files-from <list>` is run
- **Then**: `metrics.learning_write_sessions` is 2

#### R4.7: Empty denominators, bad lines and unreadable files degrade with warnings
- **Given**: a list (read from stdin via `--files-from -`) naming one 5-minute transcript that contains one unparseable line, and one path that does not exist
- **When**: `python3 S/session_metrics.py --files-from -` is run with that list on stdin
- **Then**: the exit status is 0; `sessions_analyzed` is 1; `metrics.handoff_ratio` is `null`; stderr has warning `skipped 1 unparseable line(s)` and warning `unreadable session file`

#### R4.8: 3-gram share and automation opportunities have fixed shapes
- **Given**: one transcript whose tool calls are Read, Edit, Bash repeated 4 times
- **When**: `python3 S/session_metrics.py --files-from <list>` is run
- **Then**: `metrics.top_3gram_share` is 1.0 (the fixture has only 3 distinct 3-grams); `automation_opportunities` is a list of at most 5 objects with exactly the keys `pattern` and `count`, and its first `pattern` is `Read→Edit→Bash`

#### R4.9: Params lines are skipped as input and echoed
- **Given**: a list whose first line is `# params {"scope": "project", "project_dir": "/x", "days": 30}` followed by one transcript path
- **When**: `python3 S/session_metrics.py --files-from <list>` is run
- **Then**: `sessions_analyzed` is 1 and `params.session_files` equals that JSON object; `params.long_session_min` is 20

### R5: Project-root discovery never yields $HOME — D12, D2

#### R5.1: Inside git, the root is the toplevel
- **Given**: a git repo `<tmp>/repo` with subdirectory `a/b`
- **When**: `python3 S/project_root.py <tmp>/repo/a/b` is run
- **Then**: stdout is the resolved `<tmp>/repo` and the exit status is 0

#### R5.2: Outside git, walk up to a CLAUDE.md
- **Given**: a non-git `<tmp>/proj/CLAUDE.md` and directory `<tmp>/proj/sub`
- **When**: `python3 S/project_root.py <tmp>/proj/sub` is run
- **Then**: stdout is the resolved `<tmp>/proj`

#### R5.3: $HOME and its ancestors never qualify
- **Given**: `HOME=<tmp>/home` with `<tmp>/home/.claude/` present and a non-git directory `<tmp>/home/notes`
- **When**: `python3 S/project_root.py <tmp>/home/notes` is run
- **Then**: stdout is empty, stderr starts with `no project root:`, and the exit status is 3

#### R5.4: A git toplevel equal to $HOME is not a project
- **Given**: `HOME=<tmp>/home` initialised as a git repo, and `<tmp>/home/x`
- **When**: `python3 S/project_root.py <tmp>/home/x` is run
- **Then**: the exit status is 3

### R6: Project signals see the new artifacts and every hook source — D14, D15, D18, D6, D2

#### R6.1: Hooks are listed from every source with a label
- **Given**: a project root that is a plugin source tree (`.claude-plugin/plugin.json`) with PreToolUse hooks in `.claude/settings.json`, `.claude/settings.local.json` and `hooks/hooks.json`; a user hook in `HOME/.claude/settings.json`; and an enabled installed plugin with `installPath/hooks/hooks.json`
- **When**: `python3 S/project_signals.py --project-root <root>` is run
- **Then**: `hooks` has one entry per hook with `source` values `project`, `project_local`, `plugin_source`, `user` and `plugin:<name@marketplace>`, each with `event`, `matcher` and `command`

#### R6.2: Planning artifacts are counted per kind
- **Given**: `specs/a/spec.md`, `specs/b/partition-manifest.md`, `specs/c/design.md`, `specs/c/brief.md`
- **When**: `python3 S/project_signals.py --project-root <root>` is run
- **Then**: `planning_artifacts` has `spec` 1, `partition_manifest` 1, `design` 1, `brief` 1, `insights` 0 and `exist: true`

#### R6.3: Recent real lessons count; stubs and templates do not
- **Given**: a git repo with `specs/x/loop.md` holding `## Lessons` and one `### L1` record with `- form: gate1-command`, committed 10 days before `--as-of-ms`, and `.claude/skills/loop.md` holding the lesson skeleton committed today
- **When**: `python3 S/project_signals.py --project-root <root> --as-of-ms <T>` is run
- **Then**: `lessons.updated_30d` is true and `lessons.files` lists only `specs/x/loop.md`; with the `specs/x/loop.md` commit moved to 40 days before `<T>` instead, `lessons.updated_30d` is false

#### R6.4: Hardened lessons are counted by exact added lines
- **Given**: `specs/x/loop.md` holding a `## Lessons` line and two `### ` records, whose commits within 90 days added the lines `- form: gate1-command` and `- form: gate3-item`; and `specs/y/loop.md` holding `## Lessons` and one `### <id>` record, whose commit added `- form: gate1-command | gate3-item | context`
- **When**: `python3 S/project_signals.py --project-root <root> --as-of-ms <T>` is run
- **Then**: `lessons.hardened_added_90d` is 2

#### R6.5: Agents are listed with keys and analyzer flags
- **Given**: a plugin source tree named `harness-ops` with `agents/session-pattern-analyzer.md` and `agents/qa-verifier.md`, and `.claude/agents/git-operator.md`, each with `name` and `description` frontmatter
- **When**: `python3 S/project_signals.py --project-root <root>` is run
- **Then**: `agents` has keys `harness-ops:session-pattern-analyzer` (`analyzer: true`), `harness-ops:qa-verifier` (`analyzer: false`) and `git-operator` (`analyzer: false`); with `skills/foo/SKILL.md` (`name: foo`) and `.claude/skills/bar/SKILL.md` (`name: bar`) also present, `skills` has keys `harness-ops:foo` and `bar`

#### R6.6: Checker citations exclude check-harness itself
- **Given**: `skills/check-harness/SKILL.md` and `skills/foo/SKILL.md`, both citing `capability:spawn-named-checker`, and `skills/bar/references/r.md` citing `capability:spawn-inline-checker`
- **When**: `python3 S/project_signals.py --project-root <root>` is run
- **Then**: `checker_citations` lists `skills/foo/SKILL.md` and `skills/bar/references/r.md` only

#### R6.7: Unattended ledgers are checked for all six limits
- **Given**: `runs/a/autopilot.md` with `run_started_at: 2026-10-30T01:00Z` and all six limits set, `runs/b/autopilot.md` with a real `run_started_at` but `killswitch_path: <runDir>/STOP`, and `runs/c/autopilot.md` copied from the template (`run_started_at: <ts>`)
- **When**: `python3 S/project_signals.py --project-root <root>` is run
- **Then**: `unattended.autopilot_files` lists `a` with `missing_limits: []` and `b` with `missing_limits: ["killswitch_path"]`, does not list `c`; `unattended.conforming` is false; stderr has warning `template-only autopilot.md` naming `c`; with no autopilot files at all, `unattended.conforming` is `null`

#### R6.8: Compounding counts agents, and git faults null the git fields
- **Given**: a git repo where `.claude/agents/new.md` was added 20 days before `<T>`; separately, the same tree with `.git` removed
- **When**: `python3 S/project_signals.py --project-root <root> --as-of-ms <T>` is run on each
- **Then**: the first prints `compounding.agents_added_90d` 1; the second exits 0 with `compounding.claude_md_updated_30d` and `compounding.agents_added_90d` `null` and warning `git unavailable`

### R7: check-harness orchestrates runs safely on both runtimes — D1, D8, D10, D11, D12, D13, D2

#### R7.1: Every run gets its own cache directory (manual)
- **Given**: two `/check-harness` runs started at the same time
- **When**: each reaches Phase 0
- **Then**: each creates its own `mktemp -d` directory under `${TMPDIR:-/tmp}/cc-cache/check-harness/`, creates the five `scratch-<NAME>` directories in it, passes it as `cache_dir`, saves its five reports there, and prints it in the report footer

#### R7.2: The harness root is resolved, validated and passed to analyzers (manual)
- **Given**: a `/check-harness` run
- **When**: Phase 0 runs
- **Then**: the root comes from `capability:resolve-harness-root`, passes the canonical three-part validation or the run halts with `unresolved:`, and every spawn prompt carries `harness_root=`, `cache_dir=` and `days=30`, and the PORTFOLIO, CONTEXT and AUTOMATION prompts also carry `as_of_ms=` (the epoch-ms time Phase 0 recorded)

#### R7.3: Reports come from analyzer returns and script output files (manual)
- **Given**: the analyzers have returned
- **When**: Phase 1's assertion runs
- **Then**: check-harness saves each return to `{cache_dir}/<NAME>.json`, reads every script-owned field from the fixed path `{cache_dir}/scratch-<NAME>/<script>.json` (`.txt` for `session_files.py`) whether or not `script_outputs` lists it; a missing file → N/A with `warning: script output missing: <path>`; an empty or unparseable file → N/A with `warning: script failed: <script> (unparseable output)`; a `params` that differs from the spawn prompt → N/A with `warning: script params mismatch: <script>`

#### R7.4: An empty agy registry continues with a recorded grade (manual)
- **Given**: an agy run where `manage_subagents` returns an empty list and all five spawn returns parse
- **When**: the delegation assertion runs
- **Then**: the run continues to Phase 2 and the scorecard footer reports `spawn return only (agy registry empty)` per analyzer

#### R7.5: A missing return or a registry that omits an analyzer halts by name (manual)
- **Given**: a run where one analyzer's return is missing or does not parse, or the agy registry lists other subagents but not that analyzer
- **When**: the delegation assertion runs
- **Then**: the run halts with `failed: spawn-named-checker returned no usable result (<analyzer>: <reason>)`, and no score is printed

#### R7.6: Script warnings and failures become N/A, not halts (manual)
- **Given**: an analyzer return whose `warnings` contain `source missing`, `unexpected shape` or `script failed`
- **When**: Phase 2 judges the items fed by that source
- **Then**: those items are N/A with the warning as evidence, every warning is listed in the findings, and the run completes

#### R7.7: A failed root discovery disables Project scope (manual)
- **Given**: `project_root.py` exits 3, or any status other than 0 and 3
- **When**: Phase 0 decides the scope
- **Then**: Project scope is disabled, the report states why (`no project root: …` or `script failed: project_root.py exit <n>`), and User scope still runs

#### R7.8: A denied or missing run-command halts instead of scoring nothing (manual)
- **Given**: `capability:run-command` is refused (e.g. agy headless `-p`) for Phase 0's `project_root.py` call, or an analyzer returns a `script_outputs` entry with `status` `denied` or `unavailable`
- **When**: check-harness reaches that point
- **Then**: the run halts with `denied: run-command requires permission not granted (<where>)` or `unavailable: run-command not provided by <runtime> (<where>)`, and no score is printed

### R8: The analyzers use the scripts and keep only judgement — D1, D10, D14, D16, D17, D5

#### R8.1: skill-portfolio-analyzer builds on inventory.py (manual)
- **Given**: the updated `agents/skill-portfolio-analyzer.md`
- **When**: it is read
- **Then**: it runs `inventory.py` via `capability:run-command` with `{harness_root}` and writes stdout to `{cache_dir}/scratch-PORTFOLIO/inventory.json`; it adds only description-duplicate clusters, description `"/xxx"` trigger collisions merged with `name_collisions`, and the MCP 30-day usage estimate; it no longer reads `enabledPlugins`/`mcpServers` from `~/.claude.json` itself or scans `~/.claude/plugins/*/`

#### R8.2: session-pattern-analyzer pipes the two session scripts (manual)
- **Given**: the updated `agents/session-pattern-analyzer.md`
- **When**: it is read
- **Then**: it runs `session_files.py --with-params` with its scope, project dir and `days`, feeds the list to `session_metrics.py --files-from`, saves both outputs at the fixed paths under `{cache_dir}/scratch-<NAME>/` with a `status` per `script_outputs` entry, runs `session_metrics.py` once over the whole list (no batch split), and contains no `find $HOME/.claude/projects` snippet

#### R8.3: project-automation-auditor builds on project_signals.py (manual)
- **Given**: the updated `agents/project-automation-auditor.md`
- **When**: it is read
- **Then**: it runs `project_signals.py`, judges D2/D3 from the labelled `hooks` list and verifier roles from `agents` (excluding `analyzer: true`), returns D10's AUTOMATION analyzer-owned keys (including `verifier_agents`) without repeating script-owned fields, and has no `session_report` input

#### R8.4: context-quality-reviewer reads every hook source and the drift report (manual)
- **Given**: the updated `agents/context-quality-reviewer.md`
- **When**: it is read
- **Then**: C3's `hook_exists` uses `project_signals.py`'s `hooks` list, and the report has `drift_report: {path, generated, contradictions}` read from `{project_root}/.drift-reports/latest.md` when present

#### R8.5: Analyzer I/O rules no longer contradict each other (manual)
- **Given**: the four updated agent files
- **When**: their Absolute Principles and Hard Rules are read
- **Then**: each says its final message is the JSON report only, and each forbids creating or modifying any file outside `{cache_dir}/scratch-<NAME>/`; none writes to a fixed `/tmp/...` path

### R9: The checklist and scoring cover the new layer consistently — D15, D16, D17, D18, D19, D22, D8

#### R9.1: Counts, tallies and field names agree (manual)
- **Given**: `skills/check-harness/SKILL.md`, `references/checklist.md`, `references/html-template.html`, `README.md`
- **When**: each place stating an item count is read
- **Then**: each says 26; the checklist footer reads "L1: 9 items, L2: 10 items, L3: 7 items" and matches the table rows; Axis 5 says 7 items and Axis 6 says 4 items; B6 uses `top_3gram_share`

#### R9.2: D6 "Unattended runs are bounded" is scored (manual)
- **Given**: AUTOMATION `unattended`
- **When**: Phase 2 judges D6
- **Then**: `conforming: null` → N/A; `true` → PASS; `false` → FAIL with each file and its `missing_limits` as evidence

#### R9.3: D5 scores set-up and use (manual)
- **Given**: AUTOMATION `verifier_agents` and `checker_citations`, and SESSION_PROJECT invocations
- **When**: Phase 2 judges D5
- **Then**: set up and used → PASS, only one → WEAK_PASS, neither → FAIL; check-harness's four analyzers never count as set up

#### R9.4: C2 uses the drift report as corroboration (manual)
- **Given**: CONTEXT `claude_md.quality.contradictions` and `drift_report`
- **When**: Phase 2 judges C2
- **Then**: reviewer count > 0 → FAIL; count 0 with a drift report generated within 30 days listing ≥ 1 contradiction → WEAK_PASS citing the report path; otherwise unchanged

#### R9.5: Cross-analyzer items are joined in Phase 2 (manual)
- **Given**: saved SESSION_PROJECT and AUTOMATION reports
- **When**: Phase 2 judges D4, B4 and E2, and E1/E3/B2 with the new fields
- **Then**: D4, B4 and E2 follow D22; E1 adds `lessons.updated_30d`; E3 adds `lessons.hardened_added_90d` and `compounding.agents_added_90d`; B2's artifact fallback uses every `planning_artifacts` kind; the per-axis source table names each field's report

#### R9.6: One 30-day window is stated once (manual)
- **Given**: the updated SKILL.md
- **When**: Phase 1 prompts and the report template are read
- **Then**: both session scans pass `days=30`, and the scorecard footer states a single 30-day period for User and Project

### R10: Docs, citations and evals describe the current skill — D21, D19

#### R10.1: Other skills cite check-harness by section (manual)
- **Given**: `skills/expert/SKILL.md` and `skills/crew/references/review-schema.md`
- **When**: their check-harness citations are read
- **Then**: each cites `skills/check-harness/SKILL.md` › "Delegation assertion" with no line numbers

#### R10.2: The converted-skills list names the new procedures (manual)
- **Given**: `references/converted-skills.md`
- **When**: the check-harness row is read
- **Then**: it reads `spawn-named-checker, resolve-harness-root, run-command`

#### R10.3: Evals cover the new behaviour (manual)
- **Given**: `skills/check-harness/evals/evals.json`
- **When**: it is read
- **Then**: it parses as JSON, keeps the existing three evals with current names, and adds evals for an empty agy registry, a missing analyzer return, the HTML report having no literal `{{`, and the new artifacts (loop lessons, ledgers, autopilot limits)

#### R10.4: README and stub describe 26 items and the scripts (manual)
- **Given**: `README.md` and `.claude/skills/check-harness.md`
- **When**: they are read
- **Then**: README's check-harness row says 26 items, the project-structure listing includes `skills/check-harness/scripts/` and `Makefile`, and a `## Testing` section names `make test`; `.claude/skills/check-harness.md` is still a symlink to `../../skills/check-harness/SKILL.md`

## Tasks

File ownership rule (keeps parallel tasks off each other's files): `skills/check-harness/scripts/harness_common.py` and `skills/check-harness/references/skill-aliases.tsv` are written by T2 only — later tasks import from `harness_common` and keep any extra helper inside their own script. `skills/check-harness/tests/tt*_*_test.sh` files are written by the TT tasks only. No task in this spec falls in a fenced area (no schema, migration, auth/permission or payment/secrets change; D5's "never emit secret values" is a read-side filter), so none is marked Fenced.

### T1: Discoverable test command and test collection [infra]
- **Fulfills**: R0
- **Depends on**: (none)
- Create root `Makefile` with a `test` target (and `.PHONY: test`) that runs `bash skills/coherence-audit/scripts/run-tests.sh` and then `bash scripts/test-block-main-push.sh`, failing if either fails (D20).
- Add section `E. collected skill tests` to `skills/coherence-audit/scripts/run-tests.sh`, before the summary: for each file from `ls skills/*/tests/*_test.sh` (sorted; the glob resolved from `$REPO_ROOT`, zero files is fine) run `(cd "$REPO_ROOT" && bash "<file>")` — tests may rely on the repo root as cwd — and record one `ok`/`bad` case named by its repo-relative path, using the script's existing `ok`/`bad` helpers. Update the header comment's WHAT IT COVERS list.
- Create `skills/check-harness/tests/README.md` stating the naming rule (`tt{n}_{topic}_test.sh`, self-contained fixtures under `mktemp -d`, `HOME` overridden, never the real `~/.claude`) so the directory exists before the TT tasks run.
- Verify: `make test` exits 0 with the existing 97 cases plus the block-main-push table; then create a temporary `skills/check-harness/tests/zz_fail_test.sh` containing `exit 1`, check that run-tests.sh reports it as `FAIL` and exits 1 (R0.2), and delete it.

### T2: Shared script module and alias table [infra]
- **Fulfills**: R1, R2, R3, R4, R5, R6 (enabling infra: the shared module and alias table every script imports; the CLI behaviour itself is built by T3–T7)
- **Depends on**: (none) — parallel with T1
- Create `skills/check-harness/references/skill-aliases.tsv` with exactly the rows D3 lists (`prefix`, `rename` with full keys, `builtin`, `builtin-namespace`), a `kind<TAB>from<TAB>to` header, and `#` comment lines allowed.
- Create `skills/check-harness/scripts/harness_common.py` (stdlib only) with: `home()` from `$HOME`; `warn(msg)` that prints `warning: msg` to stderr and appends to a module-level list for JSON output; `load_json(path, expect=dict)` returning `None` plus `source missing` / `unexpected shape` warnings (D2); `resolve(path)` = `os.path.realpath`; `encode_project_dir(path)` (D7: resolve, then every char outside `[A-Za-z0-9]` → `-`); `load_aliases()` reading the TSV relative to this file; `normalise(name)` (D3 key algorithm); `role_match(key, full_keys)` (D3 role match, built-ins excluded unless listed bare); `installed_plugins()` from `installed_plugins.json` and `enabled_plugins(project_root)` from user/project settings (D5); `plugin_source(project_root)` reading `.claude-plugin/plugin.json` (D6); `git(args, cwd)` returning stdout or `None` with a `git unavailable` warning; `emit(obj)` printing JSON with the collected `warnings`.
- No entry-point behaviour; T3–T7 import it (scripts run as `python3 <path>`, not `-I`, per D1).

### TT1: acceptance tests for R1's GWTs
- **Fulfills**: R1 (tests)
- **Depends on**: T1, T2

### TT2: acceptance tests for R2's GWTs
- **Fulfills**: R2 (tests)
- **Depends on**: T1, T2

### TT3: acceptance tests for R3's GWTs
- **Fulfills**: R3 (tests)
- **Depends on**: T1, T2

### TT4: acceptance tests for R4's GWTs
- **Fulfills**: R4 (tests)
- **Depends on**: T1, T2

### TT5: acceptance tests for R5's GWTs
- **Fulfills**: R5 (tests)
- **Depends on**: T1, T2

### TT6: acceptance tests for R6's GWTs
- **Fulfills**: R6 (tests)
- **Depends on**: T1, T2

### TT7: acceptance tests for R7's GWTs
- **Fulfills**: R7 (tests)
- **Depends on**: T1, T2

### TT8: acceptance tests for R8's GWTs
- **Fulfills**: R8 (tests)
- **Depends on**: T1, T2

### TT9: acceptance tests for R9's GWTs
- **Fulfills**: R9 (tests)
- **Depends on**: T1, T2

### TT10: acceptance tests for R10's GWTs
- **Fulfills**: R10 (tests)
- **Depends on**: T1, T2

(Each TT writes new files `skills/check-harness/tests/tt{n}_{topic}_test.sh` only, collected by T1's section E via `make test`; GWTs whose heading ends `(manual)` get no test. Every GWT of R7–R10 is `(manual)` — they describe skill and agent instructions that only a model executes — so TT7–TT10 write no file and return every GWT as `manual: spec-marked`; their `Depends on` edges are ordering-only. R0 is goal-level and has no TT; R0.1–R0.3 are checked by T9's final `make test` and lint run.)

### T3: `skill_name.py` [vertical]
- **Fulfills**: R1
- **Depends on**: T2, TT1 — parallel with T4, T5, T6, T7
- Create `skills/check-harness/scripts/skill_name.py`: for each argument print `NAME<TAB>KEY` via `harness_common.normalise`; no arguments → exit 2 (D2, D3).

### T4: `inventory.py` and skill-portfolio-analyzer [vertical]
- **Fulfills**: R2, R8
- **Depends on**: T2, TT2, TT8 — parallel with T3, T5, T6, T7
- Create `skills/check-harness/scripts/inventory.py` implementing D4, D5, D6 and the D2 contract (`--project-root`, `--as-of-ms`, `--dead-days`; output keys exactly as D5 lists).
- Rewrite `agents/skill-portfolio-analyzer.md` per R8.1 and R8.5: inputs `harness_root`, `cache_dir`, `project_root`, `dead_days` (drop `low_value_days` / `low_value_count` and the `low_value` class: no checklist item uses it); for the MCP usage grep, run `session_files.py --scope overall --days 30 --with-params` into `{cache_dir}/scratch-PORTFOLIO/session_files.txt` (listed in `script_outputs`) and grep only those files; run `inventory.py` via `capability:run-command` after `test -f`, stdout to `{cache_dir}/scratch-PORTFOLIO/inventory.json`, listed in `script_outputs`; keep description-duplicate clustering, description `"/xxx"` collisions (merged with `usage.name_collisions` into `trigger_collisions`) and the 30-day MCP usage grep (top-level session files only, D7); remove the `~/.claude.json` `enabledPlugins`/`mcpServers` snippet, the `~/.claude/plugins/*/` scan and `/tmp/cc_state.json`; return exactly D10's PORTFOLIO analyzer-owned keys; script-owned fields (`summary`, `plugins`, `mcp_servers`, `skills`, `usage`, `plugin_findings`) are not repeated — Phase 2 reads them from `scratch-PORTFOLIO/inventory.json`. No imperative tool names (Constraints).

### T5: `session_files.py`, `session_metrics.py` and session-pattern-analyzer [vertical]
- **Fulfills**: R3, R4, R8
- **Depends on**: T2, TT3, TT4, TT8 — parallel with T3, T4, T6, T7
- Create `skills/check-harness/scripts/session_files.py` (D7, D8 default `--days 30`) and `skills/check-harness/scripts/session_metrics.py` (D9, including the completion regex, 2-decimal rounding and `--files-from -`).
- Rewrite `agents/session-pattern-analyzer.md` per R8.2 and R8.5: inputs `harness_root`, `cache_dir`, `scope` (`overall` | `project`, passed through to `session_files.py --scope` unchanged), `project_dir`, `days` (default 30), `long_session_min`, report name (`SESSION_USER` / `SESSION_PROJECT`); runs `session_files.py … --with-params` (always passing the flag) and `session_metrics.py --files-from` that file; outputs to `{cache_dir}/scratch-<NAME>/session_files.txt` and `session_metrics.json`, listed in `script_outputs`; run `session_metrics.py` once over the whole list (remove the batch-split step and Hard Rule 3); the analyzer adds only `automation_suggestions` (`[{pattern, suggestion}]`) for the script's `automation_opportunities`; output field is `top_3gram_share`; `period_days` is 30; remove the `SESSION_GLOB`/`find` snippet and `/tmp/cc-cache/sessions.txt`.

### T6: `project_root.py` [vertical]
- **Fulfills**: R5
- **Depends on**: T2, TT5 — parallel with T3, T4, T5, T7
- Create `skills/check-harness/scripts/project_root.py` per D12 (git toplevel first, then walk-up; `$HOME` and ancestors excluded; resolved path; exit 3 with `no project root: <reason>`).

### T7: `project_signals.py`, project-automation-auditor and context-quality-reviewer [vertical]
- **Fulfills**: R6, R8
- **Depends on**: T2, TT6, TT8 — parallel with T3, T4, T5, T6
- Create `skills/check-harness/scripts/project_signals.py` per D14, D15 (ledger search exclusions, real-ledger structure tests, value parsing), D18 and D6 keying (`--project-root`, `--as-of-ms`; output keys exactly as D15 lists).
- Rewrite `agents/project-automation-auditor.md` per R8.3 and R8.5: inputs `harness_root`, `cache_dir`, `project_root`; drop `session_report`; keep D1 test-runner detection, CI, isolation and risk findings; D2/D3 judged from `hooks` with the source in evidence; return exactly D10's AUTOMATION analyzer-owned keys — `verifier_agents` being D3 keys from `agents` judged verifier-role, `analyzer: true` excluded — and not the script-owned fields, which Phase 2 reads from `scratch-AUTOMATION/project_signals.json`; remove `/tmp/cc-cache/scripts.json`.
- Update `agents/context-quality-reviewer.md` per R8.4 and R8.5: inputs add `harness_root`, `cache_dir`; C3 `hook_exists` from `project_signals.py` `hooks` (stdout to `{cache_dir}/scratch-CONTEXT/project_signals.json`); add `drift_report` (D17).

### T8: check-harness orchestration — Phase 0/1, delegation evidence, runtime map [vertical]
- **Fulfills**: R7, R10
- **Depends on**: T6, TT7, TT10 — parallel with T3, T4, T5, T7
- In `skills/check-harness/SKILL.md` Phase 0: resolve and validate the harness root (D1), run `project_root.py` (D12, R7.7), create the per-run `CACHE_DIR` and its five `scratch-<NAME>` directories (D11). Phase 2 reads script fields from the fixed paths, checks `params` against the spawn-prompt values, and applies the `failed`/unparseable/missing rules (D1). Phase 0 records `AS_OF_MS` (current epoch ms) once. Phase 1: every spawn prompt passes `harness_root=`, `cache_dir=`, `days=30` (D8), the PORTFOLIO, CONTEXT and AUTOMATION prompts pass `as_of_ms={AS_OF_MS}` (analyzers pass it to `--as-of-ms`, so the `params` check covers it) and its report name, the PORTFOLIO prompt drops `low_value_days=60, low_value_count=3` (D5/T4), and the session prompts pass `scope=overall` / `scope=project` (replacing `scope=current_project`) plus `project_dir=` — the same spellings `session_files.py --scope` takes; drop `session_report=` and every "Save to /tmp/cc-cache/…" line (D10); check-harness saves each return to `{cache_dir}/<NAME>.json` with `capability:write-file`. Rewrite "Delegation assertion" per D13 and D1's script-output rule (R7.3–R7.5), keeping that section title verbatim (T9's citations point at it). Hard Rules 2 and 8 updated to the per-run dir. Capabilities only (Constraints).
- In `references/runtime-tools.md` › `spawn-named-checker` › Required assertion: the D13 rule (spawn return required; agy registry recorded; empty registry continues with a recorded grade; a registry listing others but not this analyzer halts — stated as applying to `spawn-named-checker` only). Rewrite the first sentence of `spawn-inline-checker`'s assertion paragraph and `spawn-worker`'s to state their existing requirement in full (the artifact clause where a named report exists, the per-runtime evidence table, the registry as the stronger signal but not a pass/fail bar) instead of "Same assertion requirement as …", so their behaviour does not change. Add the D13 `failed:` row to `## Halting`.
- In `references/converted-skills.md`: check-harness row → `spawn-named-checker, resolve-harness-root, run-command` (R10.2).

### T9: Scoring, checklist, docs, evals and citations [vertical]
- **Fulfills**: R9, R10, R0
- **Depends on**: T3, T4, T5, T7, T8, TT9, TT10
- `skills/check-harness/references/checklist.md`: 26 items; new row D6 (L3) in Axis 5 ("7 items"); Axis 6 header "[4 items]"; E1/E2/E3/B2/B4/D4/D5/C2 judgment bases per D15, D16, D17, D22; B6 `top_3gram_share`; B5 basis `parallel_count ≥ 1` described as messages with ≥ 2 Agent spawns; B1 basis mentions `harness-ops:loop`/build-order/autopilot/qa instead of `ralph`; footer "Total 26 items (6 axes) | L1: 9 items, L2: 10 items, L3: 7 items"; glossary Plan-first ratio updated.
- `skills/check-harness/SKILL.md` (frontmatter, Phase 2, Phase 3 template): "26-item" everywhere (D19); per-axis source table names each field's report (D22); Status rules gain "N/A when a source warning applies" (R7.6); Phase 2 joins for D4/D5/B4/E2 (D22); D6 rule (D18); C2 rule (D17); template's Axis 5 table gains D6, Compounding Detail adds lessons/agents/ledgers, Execution Detail and footer state one 30-day period (R9.6), the checklist summary reads "6 axes · 26 items". Edit through the repo-root path.
- `.claude/skills/check-harness.md` is a symlink to SKILL.md: do not edit or replace it; confirm `test -L` still holds at the end.
- `skills/check-harness/references/html-template.html` footer: `26 items · 6 axes · session {{SESSION_ID}} · {{PERIOD}} · cache {{CACHE_DIR}} · evidence {{DELEGATION_EVIDENCE}}`; add `{{PERIOD}}`, `{{CACHE_DIR}}`, `{{DELEGATION_EVIDENCE}}` to SKILL.md's Scalars list so placeholder parity holds. The markdown template's footer line likewise states the 30-day period, `CACHE_DIR` (D11, R7.1) and the per-analyzer evidence grade (D13, R7.4).
- `README.md`: check-harness row "26-item"; project-structure listing adds `skills/check-harness/scripts/` and `Makefile`; add a `## Testing` section (before `## Project Structure`) saying `make test` runs the whole suite.
- `skills/check-harness/evals/evals.json`: per R10.3, same `{id, name, prompt, expected_output, files}` shape.
- `skills/expert/SKILL.md:181` and `skills/crew/references/review-schema.md:7`, `:130`: cite `skills/check-harness/SKILL.md` › "Delegation assertion" (D21, R10.1, R0.4).
- Finish with `make test` and `scripts/portability-lint.sh --sweep`, both exit 0 (R0.1, R0.3).

## External Dependencies

### Pre-work
- (none)

### Post-work
- Reinstall/update the harness-ops plugin (installed copy is 0.5.0) so `/harness-ops:check-harness` runs the new version outside this repo.
- Optionally run `/harness-ops:check-harness` once on this machine to confirm the real-world score changes (Non-goals; Known Gaps).
- Regenerate `.gemini/commands/harness-ops/check-harness.toml` in a separate change (Non-goals).

## Spec Review
- **Verdict**: NEEDS_FIX
- **Reviews**: 3 + fix confirmation; the 5 Open items were then fixed at the user's request ("fix the 5 open items and execute"), not re-reviewed
- **Fixed**:
  - Review 1 (14 issues): `.claude/skills/check-harness.md` recorded as a symlink (no edit); html-template footer count and new footer placeholders (T9); `spawn-inline-checker`/`spawn-worker` no longer inherit the changed assertion (T8); `failed:` halt prefix; T9 depends on T3/T4/T5/T7; T2 fulfills R1–R6 as enabling infra; TT7–TT10 stated as file-less; `inventory.py` reads no project source without `--project-root`; full `lessons`/`compounding`/`ledgers` sub-keys; R6.4 fixture structure; `## Config`/`## State` heading rule; `scope=project` spelling; footer cache dir + evidence grade assigned to T9; README `## Testing` section.
  - Review 2 + L2-reviewer (9 issues): `run-command` denied/unavailable halts (D13, R7.8); batch split retired; fixed script-output paths; JSON entry shapes in D5/D15 and the `dead` rule; session duration source; R0.2 verify step in T1; Done-when citation scope narrowed; section E runs tests from the repo root.
  - Review 3 + L2-reviewer (11 issues): R7.3 aligned with D1; `failed` status and unparseable-file rule; scratch dirs created in Phase 0; `params` echo and check (R2.11, R3.7, R4.9); `project_signals.py` `skills`; required report keys in D10; low_value dropped and PORTFOLIO session list; `projects` key resolution; 3-gram/30%/`tool_frequency` definitions; plugin.json path.
- **Open** (all 5 fixed afterwards by user request — D5 `params`; D7/D9/T5/R8.2 `--with-params`; D15 `.claude/skills/**`; D10 analyzer-owned keys + Phase 2 source rule, D22/T4/T7/R8.3 aligned; `as_of_ms` passed by check-harness):
  - [introduced] D5 / T4 — `inventory.py`'s output key list in D5 omits `params`, which D1 and R2.11 require; T4 says "exactly as D5 lists".
  - [introduced] D7 / D9 / T5 / R8.2 — `--with-params` is missing from D7's signature (D2: unknown flag → exit 2); D9's `--files-from` format doesn't mention skipping a `# params` line or emitting `params.session_files` / `params.long_session_min` (contradicts R4.9); T5/R8.2 don't tell session-pattern-analyzer to pass `--with-params`.
  - [introduced] D15 — `skills` scans `.claude/skills/*/SKILL.md` (one level) while D4/D5 register `.claude/skills/**/SKILL.md`.
  - [introduced] D10 vs D1 / R7.3 / D22 — D10's "analyzer-owned" required keys include script-produced fields (PORTFOLIO `summary`, `ghost`, `prefix_duplicates`, `plugin_findings`; AUTOMATION `project_skills`, `project_agents`), and Phase 2's source for `checker_citations` / `unattended` / `project_skills.registered` (analyzer return vs `scratch-AUTOMATION/project_signals.json`) is not settled.
  - [unresolved] D1 params check — `as_of_ms` is in no spawn prompt, so `params.as_of_ms` from `inventory.py` / `project_signals.py` can't be compared; check-harness should pass `as_of_ms=` in the PORTFOLIO and AUTOMATION prompts.
