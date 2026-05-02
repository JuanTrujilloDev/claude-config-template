# Upgrade guide

How to pull updates from the template into a project that's already configured.

## The model

`setup.sh` always **overwrites** files at the target. It doesn't merge. This keeps the renderer simple but means upgrades are a two-step:

1. Re-render into a temp dir.
2. `git diff` your project against the temp dir; cherry-pick the changes you want.

## Recommended workflow

### Once: keep your answers.env in the project

When you first run setup, save the answers as a checked-in file:

```bash
~/code/claude-config-template/setup.sh --target . --answers ./answers.env
git add answers.env  # keep it in the repo
```

This is the source of truth. When you upgrade the template, the same answers re-render the same config (modulo template changes).

### To upgrade

```bash
# 1. Pull the latest template
cd ~/code/claude-config-template
git pull origin main
# (or check out a tag for stability)
git checkout v1.3.0

# 2. Render into a scratch dir
cd ~/code/my-project
TMP=$(mktemp -d)
~/code/claude-config-template/setup.sh --target "$TMP" --answers ./answers.env

# 3. Diff against your current config
diff -r .claude "$TMP/.claude"
diff CLAUDE.md "$TMP/CLAUDE.md"

# 4. Apply changes you want
# Option A — full replace:
cp -r "$TMP/.claude" .
cp "$TMP/CLAUDE.md" .

# Option B — selective:
cp "$TMP/.claude/agents/code-reviewer.md" .claude/agents/

# 5. Commit
git add .claude/ CLAUDE.md
git commit -m "chore: upgrade claude-config-template to v1.3.0"
```

## Common upgrade scenarios

### New placeholder added

The schema gained a new variable (e.g. `has_docker`). When you re-render with your existing `answers.env`, the new variable will be empty, so any `{{has_docker}}` substitutions render as blank and `{{#has_docker}}…{{/has_docker}}` blocks are dropped.

**Fix:** add the new line to `answers.env` and re-render.

### Placeholder renamed

Breaking change → bumps a major version. The release notes will list the rename. Update the key in `answers.env`.

### Agent added or modified

If an agent file changes upstream, the diff in step 3 will show it. Replace the file outright unless you've customized your version.

### File removed (e.g. a command you don't use)

The renderer doesn't delete files. After replacing `.claude/`, manually `rm` the orphaned ones. Or just delete `.claude/` before the cp:

```bash
rm -rf .claude
cp -r "$TMP/.claude" .
```

This is safe because your customizations live in `answers.env`, not in the rendered files.

## When to NOT upgrade

- You've heavily customized `.claude/agents/backend-dev.md` to match your team's specific patterns. Upgrading wipes those changes.
- The new template version changes a principle you've already trained your team on.
- You're mid-sprint and don't want to debug new hook behavior.

In those cases: stay on your current template version and apply specific upstream changes by hand.

## Tracking template version

Add a comment to your project's `CLAUDE.md` after rendering:

```markdown
<!-- claude-config-template version: v1.3.0 (2026-04-30) -->
```

Or append it via `setup.sh` (not done by default — would require either a `--version` flag or reading from a `VERSION` file in the template repo).
