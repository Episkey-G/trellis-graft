## Agent skills

The Trellis phases in `.trellis/workflow.md` are driven by the engineering skills from
[mattpocock/skills](https://github.com/mattpocock/skills), installed under
`.claude/skills/`. Trellis owns the phase gates, task state, and spec injection; those
skills own what happens inside each phase.

### Superseded skills — gated, not just discouraged

These ship with Trellis and still sit in every platform skill root, but this graft
replaced what they do. `install.sh` writes `disable-model-invocation: true` into each
one's `SKILL.md`, so their descriptions are no longer loaded into context and the model
cannot auto-load them. Both stay typable as `/trellis-brainstorm` and `/trellis-check`
if you want one deliberately.

| Skill | Replaced by | Why it needed a mechanism, not a note |
| --- | --- | --- |
| `trellis-brainstorm` | `grill-with-docs` → `to-spec` → `to-tickets` (Phase 1.1) | Its description ends "use when requirements are unclear … or the user describes a new feature", which matches the first prompt of almost every session — while `grill-with-docs` is invisible to the model (see below). Left ungated, it wins that trigger every time. |
| `trellis-check` (the **skill**) | The `trellis-check` **sub-agent**, dispatched twice with `Axis: standards` / `Axis: spec` (Phase 2.2) | Same name, opposite behaviour: the skill self-fixes, the agent is read-only. Its description matches "before committing changes" — exactly when Phase 2.2 wants the Agent form. Verification always uses the Agent form. |

If `trellis update --force` ever overwrites these files, re-run `trellis-graft` to
re-apply the gate.

`trellis-break-loop` is **not** superseded — Phase 3.2 keeps it as a fallback when you want
the 5-dimension root-cause classification without rebuilding a feedback loop.

### Phase 1.1 skills are user-invoked

Four mattpocock skills carry `disable-model-invocation: true` upstream, so their
descriptions never enter context — you cannot see them in your skill list and you cannot
load them:

| Skill | How it runs |
| --- | --- |
| `grill-with-docs` | The user types `/grill-with-docs`. It then loads `grilling` and `domain-modeling`, which you *can* invoke, so the interview proceeds normally from there. |
| `to-spec` | The user types `/to-spec` once the interview has settled. |
| `to-tickets` | The user types `/to-tickets`, only for multi-deliverable scope. |
| `implement` | Never invoked directly — Phase 2.1 routes through the `trellis-implement` sub-agent, which drives `tdd` itself, so implementation work never lands in the main session's context. |

When you reach Phase 1.1, **ask the user to type `/grill-with-docs`** and wait. Do not
improvise an interview from the workflow.md summary: the rules that make grilling work
(research the facts before asking, decisions belong to the user, resolve every branch of
the design tree) live in the skill body you cannot read. A simulated interview looks like
progress and produces a `prd.md` that never got stress-tested.

The same applies at every stage boundary — the chain does not advance on its own.
`grill-with-docs` is one line that delegates to `/grilling` and `/domain-modeling`; it
never hands off to `to-spec`. So when the interview has resolved every branch, **ask the
user to type `/to-spec`** instead of writing `prd.md` yourself, and ask for `/to-tickets`
only when the scope has several independently verifiable deliverables.

These four live in `~/.claude/skills/`, which is user-global — this graft installs
per-repo and does not modify them.

### Issue tracker

Issues, specs, and tickets live in the Trellis task tree under `.trellis/tasks/` — not
GitHub Issues, not `.scratch/`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Triage labels

Not used — the `triage` skill is not installed, and lifecycle state lives in
`task.json.status`.
