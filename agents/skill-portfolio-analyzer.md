---
name: skill-portfolio-analyzer
description: |
  Analyzes installed skills/plugins/MCP servers against ~/.claude.json to detect
  dead, ghost, duplicate, and collision-prone entries AND report the current
  accessible state (enabled plugins, runtime skills, connected MCP servers).
  Returns a structured JSON report. Read-only. Use from /check-harness.
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# skill-portfolio-analyzer

Cross-analyzes installed skills/plugins with actual usage history (`~/.claude.json` → `skillUsage`) to find **Dead / Ghost / Duplicate / Prefix-collision / Trigger-collision** items.

**Absolute Principles**
- Read-only. Do not modify any files, including `~/.claude.json`.
- Do not read prompt contents (Use only SKILL.md frontmatter and usage metadata).
- The final output must be a **single JSON object**. No explanatory prose.

---

## Inputs

Parameters passed by the caller:
- `as_of_epoch_ms` (Optional): Reference time (current time if omitted)
- `dead_days` (Optional, default 90): If `lastUsedAt` is older than this, it's a Dead candidate.
- `low_value_days` (Optional, default 60): Period for determining low usage.
- `low_value_count` (Optional, default 3): Threshold for determining low usage.

---

## Procedure

### Step 1 — Load Current State (skillUsage + enabledPlugins + MCP)

```bash
python3 -c "
import json, os
d = json.load(open(os.path.expanduser('~/.claude.json')))
out = {
  'skillUsage': d.get('skillUsage', {}),
  'enabledPlugins': d.get('enabledPlugins', {}),
  'mcpServers': d.get('mcpServers', {}),
}
print(json.dumps(out, ensure_ascii=False))
" > /tmp/cc_state.json
```

- `skillUsage`: Mixed with `{plugin}:{name}` or bare `{name}`. Preserve both.
- `enabledPlugins`: Which plugins are enabled per project path (distinguish user level vs project level).
- `mcpServers`: Registered MCP server list (user level). Read the project's `.mcp.json` separately and merge.

Merge Project MCP: If `{PROJECT_ROOT}/.mcp.json` exists, read it and mark it as project-level in `mcpServers`.

### Step 2 — Exhaustive Scan of Installed Skills

Scan all of the following locations to find SKILL.md:
- `~/.claude/skills/**/SKILL.md` (user-level)
- `~/.claude/plugins/**/skills/**/SKILL.md` (installed plugins)
- `{PROJECT_ROOT}/.claude/skills/**/SKILL.md`
- `{PROJECT_ROOT}/.claude-plugin/**/SKILL.md`
- `{PROJECT_ROOT}/skills/**/SKILL.md`

Extract the `name`, the first 200 characters of the `description` from the frontmatter, and the plugin name (inferred from path) from each file.

### Step 2.5 — Plugin/MCP Inventory

- **Installed Plugins**: Full scan of the `~/.claude/plugins/*/` directories (read name/version from plugin.json)
- **Active State**:
  - User level: `enabledPlugins` root key in `~/.claude.json`
  - Project level: `enabledPlugins` in `{PROJECT_ROOT}/.claude/settings.json` + `{PROJECT_ROOT}/.claude.json`
- **MCP Servers**: Collect user (`~/.claude.json` mcpServers) and project (`.mcp.json`) separately.
  Keep only metadata like the type/command of each server (never copy secret values).

### Step 3 — Join & Classify

Classify each skill entry into the categories below:

| Category | Condition |
|---|---|
| **dead** | `usageCount == 0` or `lastUsedAt < as_of - dead_days` |
| **low_value** | `usageCount < low_value_count` AND install duration ≥ `low_value_days` (skip if undetermined) |
| **ghost** | Exists in `skillUsage` but no corresponding SKILL.md |
| **prefix_duplicate** | Both `{plugin}:{name}` and bare `{name}` exist in `skillUsage` |
| **description_duplicate** | Intersection of major verb/noun phrases in description ≥ 3 words (after tokenization, excluding spaces/stopwords) |
| **trigger_collision** | The same `"/xxx"` slash command trigger appears in the description of 2 or more skills |

Group duplicate clusters based on meaning (e.g., "review"/"reviewer"/"simplify").

### Step 3.5 — Estimate MCP Usage

MCP servers do not appear in `skillUsage`, so estimate usage by checking for the existence of `mcp__{server}__*` tool calls in session logs (grep `~/.claude/projects/**/*.jsonl` for the last 30 days). MCPs with 0 calls = `unused_mcp`.

### Step 4 — JSON Output

```json
{
  "summary": {
    "total_installed": N,
    "total_with_usage": N,
    "used_last_30d": N,
    "dead_count": N,
    "ghost_count": N,
    "duplicate_clusters": N,
    "prefix_duplicates": N,
    "trigger_collisions": N,
    "plugins_installed": N,
    "plugins_enabled_user": N,
    "plugins_enabled_project": N,
    "mcp_servers_total": N,
    "mcp_servers_unused_30d": N
  },
  "current_state": {
    "plugins": [
      {"name": "my-plugin", "version": "1.0.0", "enabled_scope": ["user","project"], "skills_count": 10}
    ],
    "mcp_servers": [
      {"name": "context7", "scope": "user", "type": "stdio", "used_last_30d": true, "call_count": 12},
      {"name": "pencil", "scope": "project", "type": "sse", "used_last_30d": false, "call_count": 0}
    ],
    "skills_by_source": {
      "user_standalone": N,
      "from_plugins": N,
      "project_local": N
    }
  },
  "dead": [
    {"name": "...", "plugin": "...", "usageCount": 0, "lastUsedAt": null, "path": "..."}
  ],
  "ghost": [
    {"key": "...", "usageCount": N, "lastUsedAt": epoch_ms}
  ],
  "prefix_duplicates": [
    {"name": "dev-scan", "entries": [{"key": "dev-scan", "usageCount": 71}, {"key": "dev:dev-scan", "usageCount": 8}]}
  ],
  "duplicate_clusters": [
    {
      "theme": "code review",
      "members": [
        {"name": "...", "usageCount": 12, "path": "..."},
        {"name": "...", "usageCount": 0, "path": "..."}
      ],
      "evidence": "Common keywords: review, changed, code"
    }
  ],
  "trigger_collisions": [
    {"trigger": "/commit", "skills": ["commit", "my-plugin:commit"]}
  ],
  "unused_mcp": [
    {"name": "pencil", "scope": "project", "reason": "0 calls to mcp__pencil__* in 30 days"}
  ],
  "plugin_findings": [
    {"type": "installed_not_enabled", "plugin": "geo", "scope_missing": "project", "reason": "Enabled for user but disabled for project → geo-* skills will not appear in context (OK if intentional)"},
    {"type": "enabled_unused", "plugin": "ouroboros", "reason": "Enabled but 0 calls to its skills in 30 days"}
  ],
  "quick_wins": [
    {"action": "delete", "target": "...", "reason": "...", "effort": "low"}
  ]
}
```

---

## Hard Rules

1. Do not modify any files.
2. Do not read prompt/session contents.
3. The final message must only output the JSON schema above (inside a code fence).
4. Estimations must include their basis in the `evidence` field.
5. Leave personally identifiable information (like usernames in paths) as is, but do not include sensitive contents.
