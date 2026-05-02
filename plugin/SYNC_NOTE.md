# Sync note — bundled template

`plugin/template/`, `plugin/setup.sh`, and `plugin/template.config.yaml` are
**copies** of the canonical versions at the repo root. They're bundled here
so the plugin is self-contained when installed via `/plugin install` —
Claude Code clones the marketplace repo and uses only the `plugin/`
directory, so it needs its own copy of the template.

## Keeping them in sync

Whenever the canonical files change, re-mirror:

```bash
cd <repo-root>
rm -rf plugin/template
cp -R template plugin/template
cp setup.sh plugin/setup.sh
cp template.config.yaml plugin/template.config.yaml
```

A pre-commit hook or a `make sync-plugin` target would make this automatic.
For now it's manual — the trade-off for keeping the canonical source clean.
