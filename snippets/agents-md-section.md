## Agent skills

The Trellis phases in `.trellis/workflow.md` are driven by the engineering skills from
[mattpocock/skills](https://github.com/mattpocock/skills), installed under
`.claude/skills/`. Trellis owns the phase gates, task state, and spec injection; those
skills own what happens inside each phase.

### Superseded skills — do not auto-load

These ship with Trellis and still sit in `.claude/skills/`, but this graft replaced what
they do. Loading one puts the main session back on the workflow it replaced.

| Skill | Replaced by | Note |
| --- | --- | --- |
| `trellis-brainstorm` | `grill-with-docs` → `to-spec` → `to-tickets` (Phase 1.1) | Its description still matches "requirements are unclear", so it competes for the same trigger. Ignore it. |
| `trellis-check` (the **skill**) | The `trellis-check` **sub-agent**, dispatched twice with `Axis: standards` / `Axis: spec` (Phase 2.2) | Same name, opposite behaviour — the skill self-fixes, the agent is read-only. Verification always uses the Agent form. |

`trellis-break-loop` is **not** superseded — Phase 3.2 keeps it as a fallback when you want
the 5-dimension root-cause classification without rebuilding a feedback loop.

The mattpocock `implement` skill carries `disable-model-invocation: true`: Phase 2.1 routes
through the `trellis-implement` sub-agent, which drives `tdd` itself, so implementation work
never lands in the main session's context.

### Issue tracker

Issues, specs, and tickets live in the Trellis task tree under `.trellis/tasks/` — not
GitHub Issues, not `.scratch/`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Triage labels

Not used — the `triage` skill is not installed, and lifecycle state lives in
`task.json.status`.
