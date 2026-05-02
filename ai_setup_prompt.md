# AI-assisted setup

Paste this entire prompt into Claude Code (or any Claude chat with file access)
from inside the project you want to configure. Claude will read the project,
infer the right answers for each placeholder, generate an `answers.env`, and
run `setup.sh`. Anything Claude can't determine confidently it will ask about
before writing files.

---

## Prompt to paste

> I want to set up Claude Code config in this project using the
> [claude-config-template](https://github.com/<your-username>/claude-config-template).
> The template lives at `<absolute path to your local clone of the template repo>`.
>
> Please do the following:
>
> 1. **Inspect the project I'm currently in.**
>    Read `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`,
>    `requirements.txt`, `manage.py`, top-level `README.md`, and the source
>    layout. From that, infer:
>    - **Language + version** (Python 3.x, Node 20.x, Go 1.22, etc.)
>    - **Backend framework** (Django, FastAPI, Flask, Express, NestJS, Rails, etc.)
>    - **Frontend stack** (Next.js, Vue, plain templates, none — if API-only)
>    - **Source directory** (`src/`, `apps/`, `lib/`, etc.)
>    - **Test command** — check `package.json` scripts, `pyproject.toml` `[tool.pytest]`, or look for `pytest.ini` / `Makefile`
>    - **Lint command** — check for `eslint`, `ruff`, `pylint`, `golangci-lint`, etc.
>    - **Format command** — `prettier`, `black`, `ruff format`, `gofmt`, etc.
>    - **Build / dev-server command** — `npm run dev`, `python manage.py runserver`, `cargo run`, etc.
>    - **Default branch name** — check `git remote show origin` or `.git/HEAD`
>    - **Database** — `settings.py`, `database.yml`, `prisma/schema.prisma`, `docker-compose.yml`
>    - **Background tasks** — does the project use Celery / BullMQ / Sidekiq?
>    - **E2E testing** — is Playwright / Cypress installed?
>
> 2. **Read `<template repo path>/template.config.yaml`** so you know every
>    placeholder the template expects.
>
> 3. **Make a draft `answers.env`** in the project root with one
>    `KEY=VALUE` line per placeholder. For anything you genuinely can't
>    determine — *and only those* — leave the value blank and add a
>    `# TODO: <what's missing>` comment on the line above.
>
> 4. **Show me the answers.env** before doing anything else. List the answers
>    in three groups:
>    - **Inferred with high confidence** — what you derived and from where (cite the file).
>    - **Inferred with low confidence** — your best guess + the alternative.
>    - **Unknown — please confirm** — the TODOs.
>
> 5. **Wait for my approval or edits.**
>
> 6. **After I approve, run:**
>    ```bash
>    bash <template repo path>/setup.sh --target . --answers ./answers.env
>    ```
>    and confirm the script ran successfully.
>
> 7. **Add to `.gitignore`** (creating one if missing):
>    ```
>    .claude/settings.local.json
>    .claude/mcp.json
>    answers.env
>    ```
>
> 8. **Restart-Claude-Code reminder.** Tell me Claude Code needs to be
>    restarted to pick up the new hooks and slash commands.
>
> Do not modify anything else. Do not invent placeholder values where the
> project doesn't tell you. If a value is genuinely ambiguous, ask one
> targeted clarifying question and stop.

---

## Why this prompt is shaped this way

- **It tells Claude where the template is.** Without this, Claude would have
  to guess. Replace `<absolute path>` with your real path before pasting.
- **It limits Claude to inference + question, not invention.** The "low
  confidence + TODO" pattern keeps you in the loop on real ambiguities.
- **It separates draft from action.** Claude never writes `.claude/` until
  you approve the answers — so if you spot a wrong test command, you can fix
  it in one place before substitution.
- **It explicitly excludes git config and .gitignore additions** as the only
  side effect besides the setup script — so you can audit the diff easily.
