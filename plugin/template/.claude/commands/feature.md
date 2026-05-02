# /feature

Orchestrate the full {{#enforce_layer_split}}BE/FE micro-PR{{/enforce_layer_split}}{{^enforce_layer_split}}feature{{/enforce_layer_split}} flow for a feature, from brief to merged PR.

## Usage

```
{{#branch_prefix}}/feature {{branch_prefix}}-<#>     # ticket-tracked, e.g. /feature {{branch_prefix}}-87
{{/branch_prefix}}/feature <description>             # freeform, e.g. /feature "add CSV export"
```

## What it does

This command runs a tightly-supervised pipeline. **It pauses at each approval gate** — never skips ahead without user confirmation.

### Step 1: Pull / draft the brief

{{#ticket_tracker_plane}}
- If the argument matches `{{branch_prefix}}-<#>`: call `mcp__plane__get_issue_using_readable_identifier` to fetch the ticket.
{{/ticket_tracker_plane}}
{{#ticket_tracker_jira}}
- If the argument matches `{{branch_prefix}}-<#>`: pull the Jira issue via `mcp__atlassian__*`.
{{/ticket_tracker_jira}}
{{#ticket_tracker_linear}}
- If the argument matches a Linear ticket ID: pull via `mcp__linear__*`.
{{/ticket_tracker_linear}}
{{#ticket_tracker_github}}
- If the argument matches `#<#>`: pull the GitHub issue via `gh issue view`.
{{/ticket_tracker_github}}
- Otherwise: treat the argument as a freeform description.

### Step 2: po-manager produces brief
Output: `docs/specs/<YYYY-MM-DD>-<slug>.md`. **Pause for approval.**

### Step 3: pm decomposes into tickets
Output: `docs/plans/<slug>-plan.md` with {{#enforce_layer_split}}BE + FE{{/enforce_layer_split}}{{^enforce_layer_split}}sequenced{{/enforce_layer_split}} tickets, each ≤{{max_files_per_pr}} files / <{{max_loc_per_pr}} LOC. **Pause for approval.**

### Step 4: Implement first ticket
- Check out the named branch (typed; never on `{{default_branch}}`)
- Spawn `backend-dev`{{#has_frontend}} or `frontend-dev`{{/has_frontend}}
- Agent runs Design First → user approves → implements
- Agent runs full Definition of Done
- Agent opens PR via `gh pr create`

{{#enforce_layer_split}}
### Step 5: Wait for BE merge, then FE
After BE merges, repeat Step 4 for the FE ticket.
{{/enforce_layer_split}}

## Approval gates (do not skip)

1. After brief — user approves goal + success criteria
2. After plan — user approves ticket split + branch names
3. After Design First — user approves data model / wireframe
4. After PR opened — user reviews + merges
