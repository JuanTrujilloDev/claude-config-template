# /feature

Orchestrate the full feature flow for a feature, from brief to merged PR.

## Usage

```
/feature <description>       # freeform, e.g. /feature "add CSV export"
```

## What it does

This command runs a tightly-supervised pipeline. **It pauses at each approval gate** — never skips ahead without user confirmation.

### Step 1: Pull / draft the brief

- If the argument matches `#<#>`: pull the GitHub issue via `gh issue view`.
- Otherwise: treat the argument as a freeform description.

### Step 2: po-manager produces brief
Output: `docs/specs/<YYYY-MM-DD>-<slug>.md`. **Pause for approval.**

### Step 3: pm decomposes into tickets
Output: `docs/plans/<slug>-plan.md` with sequenced tickets, each ≤12 files / <3000 LOC. **Pause for approval.**

### Step 4: Implement first ticket
- Check out the named branch (typed; never on `main`)
- Spawn `backend-dev` or `frontend-dev`
- Agent runs Design First → user approves → implements
- Agent runs full Definition of Done
- Agent opens PR via `gh pr create`


## Approval gates (do not skip)

1. After brief — user approves goal + success criteria
2. After plan — user approves ticket split + branch names
3. After Design First — user approves data model / wireframe
4. After PR opened — user reviews + merges
