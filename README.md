# claude-config-template

A reusable, parameterized [Claude Code](https://docs.claude.com/en/docs/claude-code) project configuration. Drop it into a new repo, answer ~25 questions (or let Claude itself fill them in), and you have a working `.claude/` setup with agents, slash commands, hooks, and rules tuned to your stack.

## Why

Reconfiguring `.claude/` and `CLAUDE.md` from scratch every time you start a new project wastes the patterns you've already debugged on past projects. This template extracts a battle-tested config (originally built for a Django/HTMX project) and parameterizes the project-specific bits so it works on FastAPI, Next.js, Go services, or whatever you're starting next.

## What you get

```
.claude/
├── CLAUDE.md                 # Project guidelines, principles, branch rules, agent map
├── HELP.md                   # Decision tree + worked examples
├── settings.json             # Permissions + hook registrations
├── mcp.json.example          # MCP server template (copy → mcp.json, fill in)
├── rules/
│   ├── principles.md         # 8 always-loaded operating principles
│   ├── backend-style.md      # Backend code conventions
│   └── frontend-style.md     # Frontend code conventions (skipped for API-only projects)
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
```

## Three ways to install

### 1. Interactive bash (the default)

```bash
git clone https://github.com/<your-username>/claude-config-template.git ~/code/claude-config-template
cd ~/code/my-new-project
~/code/claude-config-template/setup.sh
```

The script asks ~25 questions (project name, test command, branch convention, etc.), then renders the template into your project root.

### 2. AI-assisted (Claude does the inference)

Paste the prompt from [`ai_setup_prompt.md`](./ai_setup_prompt.md) into Claude
Code from inside your new project. Claude reads `package.json` /
`pyproject.toml` / etc., drafts an `answers.env`, shows it to you for
approval, and runs the setup script. Faster for projects with conventional
layouts; useful when you don't remember the exact lint command.

### 3. Non-interactive (CI / scripted)

```bash
~/code/claude-config-template/setup.sh \
  --target /path/to/new-project \
  --answers ./answers.env
```

Pre-bake `answers.env` (`KEY=VALUE` per line; see `template.config.yaml` for the full list) and pass it via `--answers`. No prompts.

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

Toggles drive **conditional sections** (`{{#has_celery}}…{{/has_celery}}`) so you don't end up with Celery boilerplate in a project that doesn't use Celery, or a `frontend-dev` agent in an API-only repo.

## How it works

1. **Placeholders** use mustache syntax: `{{var_name}}` for direct substitution, `{{#var}}…{{/var}}` for "include if truthy", `{{^var}}…{{/var}}` for "include if falsy".
2. **File-level conditionals** use a directive at the top of a template file: `<!-- requires: has_frontend -->`. The renderer drops the file if the var is falsy and strips the directive otherwise.
3. **The renderer** is inline Python inside `setup.sh` (~50 lines). It's narrow on purpose: no Jinja/Mustache library dependency, no surprise behavior. It does standalone-tag whitespace cleanup so conditional blocks don't leave blank-line forests.

## Pre-filled examples

See [`examples/`](./examples) for `answers.env` files matching common stacks:

- `python-fastapi/` — FastAPI service, no frontend
- `python-django/` — Django + DRF + HTMX
- `node-express/` — Express API, no frontend
- `node-nextjs/` — Next.js full-stack

Use them as starting points: `cp examples/python-fastapi/answers.env ./answers.env`, edit, then run `setup.sh --answers ./answers.env`.

## Upgrading an already-configured project

See [`docs/upgrade-guide.md`](./docs/upgrade-guide.md). Short version:

```bash
# In your project
cd ~/code/my-project
~/code/claude-config-template/setup.sh --target . --answers ./answers.env
# Then `git diff` and merge by hand.
```

The renderer always overwrites — keep your `answers.env` checked in (or close to hand) so you can re-render after pulling template updates.

## Versioning

Tagged releases follow [SemVer](https://semver.org):
- **Major** — breaking placeholder rename or removed file
- **Minor** — new placeholder, new agent/command, new conditional section
- **Patch** — bug fixes, doc updates

Pin to a tag if you want stability across re-renders: `git -C ~/code/claude-config-template checkout v1.2.0`.

## Out of scope

- Not a generic project scaffolder — [cookiecutter](https://github.com/cookiecutter/cookiecutter) exists.
- Not a Claude Code plugin marketplace — see [Claude Code plugins docs](https://docs.claude.com/en/docs/claude-code/plugins).
- Doesn't replace Claude Code's built-in `/init` command — it complements it. Run `/init` after `setup.sh` if you want Claude to scan your codebase and add project-specific notes to `CLAUDE.md`.

## Reference

- [`docs/what-each-file-does.md`](./docs/what-each-file-does.md) — per-file explainer
- [`docs/upgrade-guide.md`](./docs/upgrade-guide.md) — pulling template updates into existing projects
- [`template.config.yaml`](./template.config.yaml) — full placeholder schema
- [`ai_setup_prompt.md`](./ai_setup_prompt.md) — AI-assisted setup prompt

## License

MIT.
