# claude-config-template

A reusable [Claude Code](https://docs.claude.com/en/docs/claude-code) project configuration. Drop it into a new repo, let Claude infer the right answers from your code, and you have a working `.claude/` setup with agents, slash commands, hooks, and rules tuned to your stack.

## Why

Reconfiguring `.claude/` and `CLAUDE.md` from scratch every time wastes the patterns you've already debugged on past projects. This template extracts a battle-tested config (originally built for a Django/HTMX project) and parameterizes the project-specific bits so it works on FastAPI, Next.js, Go services, or whatever you're starting next.

## Setup

You only ever set this up from inside Claude Code. There's no "answer 25 questions in your terminal" mode — Claude does the asking, because Claude can read your project and infer 90% of the answers without bothering you.

### One-time: clone the template

```bash
git clone https://github.com/<your-username>/claude-config-template.git ~/code/claude-config-template
```

### Per-project: tell Claude

In your new project, open Claude Code and say:

> Set up Claude Code config from the template at `~/code/claude-config-template`. Read the project to infer placeholder values, draft an `answers.env`, show it to me for approval, then run the renderer.

Claude will:
1. Read `package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` / etc. plus your source layout.
2. Draft an `answers.env` with confidence labels (high / low / unknown).
3. Ask you targeted questions only for the values it genuinely can't determine.
4. After you approve, run `~/code/claude-config-template/setup.sh --target . --answers ./answers.env`.
5. Add `.claude/settings.local.json`, `.claude/mcp.json`, and `answers.env` to `.gitignore`.
6. Remind you to restart Claude Code to load the new hooks and slash commands.

That's it. The flow takes ~2 minutes for a conventional project.

### If you don't have Claude Code handy

Pre-filled `answers.env` files for common stacks live in [`examples/`](./examples). Copy one, edit, and render manually:

```bash
cd ~/code/my-new-project
cp ~/code/claude-config-template/examples/python-fastapi/answers.env ./answers.env
# edit answers.env
~/code/claude-config-template/setup.sh --target . --answers ./answers.env
```

## What you get

```
.claude/
├── HELP.md                   # Decision tree + worked examples
├── settings.json             # Permissions + hook registrations
├── mcp.json.example          # MCP server template (copy → mcp.json, fill in)
├── rules/
│   ├── principles.md         # 8 always-loaded operating principles
│   ├── backend-style.md      # Backend code conventions
│   └── frontend-style.md     # Frontend code conventions (skipped for API-only)
├── agents/
│   ├── pm.md                 # Decomposes features into PR-sized tickets
│   ├── po-manager.md         # Briefs / SOWs / PRDs
│   ├── backend-dev.md        # Backend implementation, Design First
│   ├── frontend-dev.md       # Frontend implementation, Design First (optional)
│   ├── ui-designer.md        # Wireframes + specs (optional)
│   ├── code-reviewer.md      # Pre-merge correctness review
│   └── security-reviewer.md  # Auth/permissions/data audit
├── commands/                 # /feature, /plan, /commit, /pr, /audit, /design, /idea, /sow
└── hooks/
    ├── agent-enforcement.sh  # Blocks edits on default branch + non-trivial edits outside agents
    ├── auto-format.sh        # Runs your formatter after every Edit/Write
    └── coding-reminder.sh    # Injects principles reminder on coding prompts
CLAUDE.md                     # Project guidelines, principles, branch rules, agent map (project root)
```

## What gets parameterized

[`template.config.yaml`](./template.config.yaml) defines every placeholder. Highlights:

| Variable | Example value |
|---|---|
| `project_name` | `Acme Billing` |
| `language` / `language_version` | `Python` / `3.12+` |
| `backend_framework` | `FastAPI` |
| `frontend_framework` | `Next.js 14` (or skip if API-only) |
| `src_dir`, `frontend_dir`, `tests_glob` | `src/`, `frontend/`, `tests/` |
| `format_cmd`, `lint_cmd`, `test_cmd`, `build_cmd` | `ruff format .`, `ruff check .`, `pytest`, `uvicorn main:app --reload` |
| `branch_prefix`, `default_branch` | `ACME`, `main` |
| `max_files_per_pr`, `max_loc_per_pr` | `12`, `3000` |
| `has_frontend`, `has_celery`, `has_e2e`, `enforce_layer_split` | `yes` / `no` toggles |

The toggles drive **conditional sections** so you don't end up with Celery boilerplate in a project that doesn't use Celery, or a `frontend-dev` agent in an API-only repo.

## How it works

1. **Placeholders** use mustache syntax: `{{var_name}}` for direct substitution, `{{#var}}…{{/var}}` for "include if truthy", `{{^var}}…{{/var}}` for "include if falsy".
2. **File-level conditionals** use a directive at the top of a template file: `<!-- requires: has_frontend -->`. The renderer drops the file if the var is falsy.
3. **The renderer** is inline Python inside `setup.sh` (~50 lines). Narrow on purpose: no Jinja/Mustache library dependency, no surprise behavior. Standalone-tag whitespace cleanup keeps conditionals from leaving blank-line forests.

## Pre-filled examples

See [`examples/`](./examples):

- `python-fastapi/` — FastAPI service, no frontend
- `python-django/` — Django + DRF + HTMX (closest to the original 351 Exchange config)
- `node-express/` — Express API, no frontend
- `node-nextjs/` — Next.js 14 full-stack

Use them as starting points. They're the answer Claude would arrive at for a vanilla version of each stack.

## Upgrading an already-configured project

See [`docs/upgrade-guide.md`](./docs/upgrade-guide.md). Short version: keep your `answers.env` checked into the project, re-render after pulling template updates, `git diff` to see what changed.

## Versioning

Tagged releases follow [SemVer](https://semver.org):
- **Major** — breaking placeholder rename or removed file
- **Minor** — new placeholder, new agent/command, new conditional section
- **Patch** — bug fixes, doc updates

Pin to a tag if you want stability across re-renders: `git -C ~/code/claude-config-template checkout v1.2.0`.

## Out of scope

- Not a generic project scaffolder — [cookiecutter](https://github.com/cookiecutter/cookiecutter) exists.
- Not a Claude Code plugin marketplace — see [Claude Code plugins docs](https://docs.claude.com/en/docs/claude-code/plugins).
- Doesn't replace Claude Code's built-in `/init` command — it complements it. Run `/init` after rendering if you want Claude to scan your codebase and add project-specific notes to `CLAUDE.md`.

## Reference

- [`docs/what-each-file-does.md`](./docs/what-each-file-does.md) — per-file explainer
- [`docs/upgrade-guide.md`](./docs/upgrade-guide.md) — pulling template updates into existing projects
- [`template.config.yaml`](./template.config.yaml) — full placeholder schema
- [`ai_setup_prompt.md`](./ai_setup_prompt.md) — verbatim version of the setup prompt, for users who want to script it

## Credits & inspiration

The four principles at the core of this template — *Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution* — come from [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills), which distilled them from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls. If you only want the principles and don't need the agents/hooks/commands scaffold, that single-file `CLAUDE.md` is a great starting point.

Several patterns — embedded "Gotchas" sections in agents, tighter permission wildcards in `settings.json`, dynamic context injection via `` !`command` `` — were adapted from [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice).

The agent / hook / micro-PR architecture was lifted from a working Django/HTMX project where it had time to bake.

## Support

If this saved you time, you can support continued work on it:

[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-30363D?logo=GitHub-Sponsors&logoColor=#EA4AAA)](https://github.com/sponsors/JuanTrujilloDev)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/juantrujillodev)

## License

MIT.
