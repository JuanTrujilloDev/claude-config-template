# What each file does

A reference for everything in `template/` — what it controls, when it fires, and how to extend it.

## `CLAUDE.md` (project root)

Loaded by Claude Code on every session start. The "always-in-context" overview of the project: principles, tech stack, branch rules, agent map. Keep it short — anything detailed belongs in a file under `.claude/rules/` or `.claude/agents/` that Claude can pull when relevant.

## `.claude/HELP.md`

Human-facing usage guide — not auto-loaded. The decision tree ("what do I do when…?") plus worked examples of full feature flows. Reference from `CLAUDE.md` so Claude can pull it on demand.

## `.claude/settings.json`

Project-level Claude Code settings. Three things:
- **`permissions.allow`** — tools Claude can use without asking (e.g. `Bash(pytest:*)`).
- **`permissions.deny`** — tools blocked outright (e.g. `Bash(rm -rf:*)`, `Edit(.env*)`).
- **`permissions.ask`** — tools that prompt for confirmation each call (e.g. `Bash(git commit:*)`).
- **`hooks`** — registers the three shell hooks for `PreToolUse`, `PostToolUse`, and `UserPromptSubmit`.

`.claude/settings.local.json` is per-user / per-machine overrides. **Gitignore it.**

## `.claude/mcp.json.example`

Template for MCP server config. Copy to `.claude/mcp.json` and fill in real values. **Gitignore `mcp.json`** if it contains secrets — use environment variables for API keys (`${PLANE_API_KEY}` etc.).

## `.claude/rules/principles.md`

Always loaded. The non-negotiable operating principles:
1. Think Before Coding
2. Simplicity First (YAGNI)
3. Surgical Changes
4. Goal-Driven Execution
5. (optional) Backend / Frontend Split
6. Micro-PR Discipline
7. Definition of Done
8. Conciseness
9. Branch Discipline

If you change one principle, change every reference to it in `CLAUDE.md`, `HELP.md`, and the agent files. Numbering matters.

## `.claude/rules/backend-style.md`

Auto-loaded for files matching the backend glob (configured by Claude Code based on path). Covers: imports, line length, function size, validation boundaries, error handling, testing conventions, query optimization. Keep it short and pattern-focused — the agents enforce it during code review.

## `.claude/rules/frontend-style.md` *(optional)*

Skipped for API-only projects. Same shape as backend-style but for components, state management, accessibility, event handling.

## `.claude/agents/*.md`

Sub-agent definitions. Each has frontmatter (`name`, `description`) and a body that defines responsibilities, scope, and protocols. Claude Code spawns these as separate sub-conversations with their own context window.

| Agent | Role | Read-only? |
|---|---|---|
| `pm` | Decompose features into PR-sized tickets | No (writes plan docs) |
| `po-manager` | Briefs / SOWs / PRDs | No (writes spec docs) |
| `backend-dev` | Backend implementation | No (writes code) |
| `frontend-dev` | Frontend implementation | No (writes code) |
| `ui-designer` | Wireframes + specs | Yes |
| `code-reviewer` | Pre-merge review | Yes |
| `security-reviewer` | Auth/permissions/data audit | Yes |

Read-only agents never edit code — they report findings to the implementing agent.

## `.claude/commands/*.md`

Slash command definitions. Each file becomes `/<filename>` in Claude Code.

| Command | What it does |
|---|---|
| `/feature` | Full pipeline: brief → plan → implement → review → PR |
| `/plan` | Decompose into tickets via `pm` agent |
| `/design` | Wireframe + spec via `ui-designer` |
| `/idea` | Raw idea → brief via `po-manager` |
| `/sow` | Statement of Work via `po-manager` |
| `/audit` | Code-quality + security review |
| `/commit` | Conventional commit, with confirmation gate |
| `/pr` | Push + open PR, with confirmation gate |

Commands pause at approval gates. Never silently proceed past a brief, plan, or PR creation.

## `.claude/hooks/*.sh`

Shell scripts that fire on Claude Code events. Each reads the event's JSON payload from stdin.

### `agent-enforcement.sh` (PreToolUse: Edit | Write)

Runs **before** every Edit or Write. Two checks:
1. **Branch discipline** — blocks any edit to the source directory while on the default branch (`main` or `master`). Forces you to check out a typed branch first.
2. **Agent gating** — blocks edits to the source directory that exceed 50 added lines or introduce a new `def`/`class`/`export class`, unless `CLAUDE_AGENT_ACTIVE=1` is set (i.e. you're already inside an agent's sub-conversation). Trivial edits pass through.

Exit code 2 means "blocked"; the message goes to stderr and Claude Code feeds it back to the model so it self-corrects.

### `auto-format.sh` (PostToolUse: Edit | Write)

Runs **after** every Edit or Write. Looks at the file extension and runs the matching formatter:
- `.py` → `ruff check --fix` then `black`
- `.ts` / `.tsx` / `.js` / `.jsx` → project-local prettier + eslint
- `.go` → `gofmt`
- `.rs` → `rustfmt`
- `.html` → skipped (template tags break prettier)

Failures are silenced (`|| true`) — the goal is "best effort", not "block on tooling glitch".

### `coding-reminder.sh` (UserPromptSubmit)

Runs on **every** user prompt. If the prompt looks coding-related (matches keywords like `implement`, `fix`, `refactor`, file extensions, slash commands), it injects a short reminder of the operating principles into Claude's context for that turn. Non-coding prompts (`what is`, `explain`, `summarize`) are skipped.

The trigger regex is conservative — it errs toward injecting (better to remind too often than miss a real coding task).

## `.claude/agents/` vs `.claude/rules/` — when to add what

| Need | Where |
|---|---|
| A repeatable workflow with multiple steps | `agents/` |
| A coding pattern that should be auto-loaded for a file glob | `rules/` |
| A user-triggered shortcut | `commands/` |
| A check that should run before/after every Edit | `hooks/` |

---

## Plugin variant — what's different

The repo ships *two* distributable artifacts: the **template** (`template/` + `setup.sh`, parameterized) and the **plugin** (`plugin/` + `.claude-plugin/marketplace.json`, static-but-installable). Same DNA, different distribution.

### `plugin/.claude-plugin/plugin.json`

The plugin manifest — name, description, version, author, license. Claude Code reads this when listing/installing plugins. The `name` field also acts as the namespace for slash commands (`/claude-config-template:feature`, `/claude-config-template:plan`, etc.).

### `plugin/agents/`

Same 7 agents as the template, but with stack-agnostic phrasing ("your project's test command" instead of `pytest`). Path references to `.claude/rules/` are replaced with `the principles skill` / `the backend-style skill` references, since the plugin ships those as skills, not as auto-loaded rules.

### `plugin/commands/`

Same 8 slash commands. Available as `/claude-config-template:<name>` once installed.

### `plugin/skills/`

The principles and style guides shipped as skills (the new convention per the Claude Code plugin docs). Each has YAML frontmatter with a `description` so Claude knows when to invoke them.

### `plugin/hooks/hooks.json` + `plugin/hooks/*.sh`

The same three hooks (agent-enforcement, auto-format, coding-reminder) but wired through `hooks.json` (the plugin format) instead of the project's `settings.json`. The `agent-enforcement.sh` script reads env vars (`CLAUDE_CONFIG_SRC_DIR`, `CLAUDE_CONFIG_FRONTEND_DIR`, `CLAUDE_CONFIG_DEFAULT_BRANCH`) with sensible defaults — users override per-project via direnv or shell rc.

### `.claude-plugin/marketplace.json`

The repo-as-marketplace listing. Lets users do `/plugin marketplace add JuanTrujilloDev/claude-config-template` and discover the single plugin inside.

## When to use plugin vs template

| | Plugin | Template |
|---|---|---|
| **Install** | `/plugin install` (one line) | Clone + Claude-driven render |
| **Project specifics** | env vars override generic defaults | Baked-in placeholders |
| **CLAUDE.md for the project** | You write a short one yourself | Generated, fully calibrated |
| **Hooks** | Read env vars, fall back to defaults | Hardcoded to your project |
| **Style guides** | Stack-agnostic skills | Tailored prose |
| **Best for** | Quick adoption across many repos | One repo where you want full precision |

You can use both — the plugin gives every project a baseline of agents/commands/principles; the template promotes a specific project to "fully calibrated" status.
