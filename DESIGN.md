# FLP Rulebook Engine — Design Notes

Version 0.0.1. A standalone Prolog engine, Inform 7-inspired, built for
the soft/advisory world of a life planner rather than a fully observable
game world.

## What was kept from Inform 7

- Rules are declared independently; you never hand-sequence them.
- Each rule pairs a *condition* with a *consequence* and attaches to a
  *trigger*.
- A single engine evaluates the whole rulebook for a trigger.
- The before-rule shape: preparation that runs ahead of an activity.

## What was changed, and why

**Explicit priority numbers instead of Inform's specificity sort.**
Inform sorts rules by how specific their conditions are. Elegant, but
you have to reverse-engineer it when debugging. Integer priorities are
boring and legible — kinder to debug. (The faithful Inform
reimplementation, a separate file, will keep the specificity sort
precisely because *that* artifact's goal is fidelity.)

**Per-rule outcome class: block / prereq / advise / warn.**
You asked for this. Inform's "the action fails" carries a determinism
that's wrong for a planner — coffee is still physically possible with a
full trash can. `block` is reserved for genuine safety (table saw).

**Every fact carries a staleness model.**
A game world is fully observable; an FLP world is not. `sticky` /
`live` / `decay(Days)` is the engine's honest admission that it is
often *guessing*. Stale preconditions are surfaced as questions
("still true?"), never assumed silently.

## The cohesion lever: outcomes are data, not text

`consider(Trigger, Outcomes)` returns a list of `outcome/3` terms. That
list is the real product. The pretty-printer, the `ordering_constraints`
exporter, and any future PDDL/Peleus bridge are all just folds over the
same list. Nothing about a rule is hidden in control flow — the rulebase
is plain clauses — which is what makes the engine homoiconic, keeps it
verifiable (Section 8: invariants *are* queries), and keeps every
integration target reading the same structure.

## Integration paths (designed-for, not yet built)

- **PDDL.** A `prereq` is an ordering constraint. `ordering_constraints/2`
  already emits `before(Task, Trigger)` terms; a PDDL exporter turns
  those into `:ordering` entries or action-schema preconditions.
- **Peleus (or a PL port).** Same `prereq`, read as an HTN method
  decomposition: "to do Trigger, first achieve the precondition tasks,
  then the primitive." The outcome list maps directly to a method body.
- **SPAMI.** Consumes the same structured outcomes; no text parsing.

The rule of thumb: as long as the engine's output stays *structured*,
every planner can consume it. Keep the printer downstream of the data.

## Roadmap

**0.0.1 (this file)** — core engine, staleness, per-rule outcomes,
`since/1`, maintenance goals, Julian dates, rulebase verification, and
a *derived* `rule_mentions_fact/2`: the relation between a trigger and
the facts its rules consult is introspected from the actual `rule/4`
clause bodies (walking `,`/`;`/`->`/`\+`/`once` and reading the first
argument of `since`/`fresh`/`stale`/`value`). It cannot drift from the
rules. A fact name computed at runtime is reported as the `unknown`
sentinel and caught by the `opaque_fact_reference` invariant.

**0.0.2** — Activities: ongoing processes ("focused work block") with
their own before/during/after rulebooks, distinct from discrete
actions. "Before a focus block, silence phone" hangs off an activity.

**Planned but not yet built** — documentation, a test suite, and a
thorough worked sample domain with pedagogy (requested); PDDL + Peleus
exporters; a faithful Inform 7 rulebook reimplementation in Prolog as a
*sibling* module (specificity sort, succeed/fail/stop semantics,
for-rules).

## Activities (0.0.2)

Activities live in a separate module, `flp_activities.pl`, layered on
the core. The separation is deliberate: 0.0.1's tested core stays
untouched, and activities are opt-in.

An activity is a process with duration, and following Inform 7 it has
three rulebooks: before, during, after. Three design choices are worth
recording:

- **No "for-rules".** Inform's for-rules replace an activity's default
  behavior. A planner has no default behavior to replace — FLP does not
  *perform* your focus block. For-rules are replaced by **during-rules**,
  which fire at a check-in and can consult `activity_elapsed/2`. This is
  planner-native and has no Inform analogue; it is the actual reason
  activities are more than rules.
- **Decomposition deferred.** Expanding an activity into sub-activities
  is HTN planning and belongs with the Peleus integration, not here.
- **Running state is an ordinary fact.** `fact(activity(Name), running,
  StartedJDN)` — so the lifecycle (`start_activity/1`, `end_activity/1`)
  is a thin, auditable layer over the core's existing world machinery,
  inventing no new state mechanism.

The core gained one shared helper, `evaluate_rulebook/3`, so `consider/2`
and all three activity phases run through the same gather-sort-present
code rather than three copies of it.

## Planner export (0.0.3)

`flp_export.pl` turns the engine's planning decisions into input for an
external planner. Its central choice is a **neutral intermediate form**:

    plan_fragment(Trigger, PrereqTasks, Orderings)

Every emitter — HDDL, PDDL, Peleus — is a thin fold over that term. This
is the outcomes-are-data principle one level up: extract the structure
once, let many emitters read it. Adding a fourth target never touches
extraction.

- **HDDL is the faithful target.** A `prereq` is a *decomposition*: "to
  do Trigger, first achieve these subtasks." That is exactly an HTN
  method, and HDDL expresses it directly. HDDL gets the full emitter.
- **PDDL is offered for compatibility, with a known loss.** Flat PDDL
  cannot express a partial order among the prereqs inside one action's
  precondition, so the prereq *ordering* is dropped. With a single
  prereq nothing is lost; with several, the chain is. This is honest,
  not a bug — PDDL simply cannot carry it.
- **Peleus is the most usable, least portable.** It emits Prolog terms,
  not a string, since Peleus consumes terms directly. Being an emitter 
  over the neutral form (not the form itself) is what keeps it from 
  contaminating the portable core.

## Planner backend and round-trip (0.0.4)

`flp_planner.pl` closes the loop: it runs a planner and parses the plan
back. A planner is a **backend** — four multifile hooks
(`planner_backend/1`, `backend_emit/3`, `backend_invoke/3`,
`backend_parse/3`) — and `run_planner/3` is backend-agnostic. Adding a
planner is additive; the generic runner never changes.

Two choices worth recording:

- **PyHOP needs a Python emitter, not the HDDL emitter.** PyHOP has no
  input file format — operators, methods and state are ordinary Python.
  So the PyHOP backend emits a complete Python *program*, a fifth
  emitter unrelated to 0.0.3's HDDL/PDDL/Peleus string emitters. This
  was a useful surprise: it confirmed the neutral `plan_fragment` form
  really is format-agnostic, since PyHOP is about as far from HDDL as a
  target gets.
- **The round-trip is the validation.** Emitting a file proves nothing;
  running a planner and getting `[step(cut_fingernails),
  step(play_guitar)]` back proves the neutral form carries enough. This
  is why 0.0.4 does the whole loop rather than stopping at emit.

PyHOP is the first backend because it is ~150 lines and shell-runnable
today — not because it is strong. It is a *total-order forward
decomposition* planner with depth-first search and no optimisation.
For anything needing real search, a Lilotane (SAT/HDDL) backend is the
next step; it is sketched in `flp_planner.pl` Section 3 and reuses
`to_hddl/2` with no new emitter. PyHOP fits a vendored-script +
`process_create` model; Lilotane, being file-based HDDL, fits
`planutils`. The two packaging stories are genuinely different.



0.0.2 dropped Inform's for-rules on the grounds that a planner has no
"doing" to wrap. That reasoning holds *only for a pure advisor*. If the
rulebook is paired with an execution system (SPSE4, or an executor on
SPAMI), there *is* a doing phase, and a for-rule becomes the natural
seam to it: a for-rule would wrap, monitor, gate, or substitute a
fallback for the execution of an activity.

This is deliberately not coded in 0.0.3, because the seam's interface
depends on which executor it pairs with, and that is undecided. What is
fixed is the *shape*: a fourth activity rulebook, `for_rule/4`, whose
consequence is not a `task`/`note` but an execution directive
(`run(...)`, `monitor(...)`, `fallback(...)`). The during-rulebook
stays — passive check-ins remain useful even with an executor; the
for-rulebook is the active counterpart, added when the executor is
known.

## Open questions for the planner stack

- **SPSE4 as the executor.** Modelling the prereq-decomposition as
  something SPSE4 can execute looks sound; the neutral `plan_fragment`
  is a candidate contract between rulebook and executor. Unconfirmed.
- **HTN planner: build or borrow.** The export targets HDDL precisely
  so an existing solver (SHOP-lineage, PANDA / pyhddl-style) can be
  used rather than writing an HTN planner on SPAMI. Build-on-SPAMI
  should be revisited only if those solvers' semantics do not fit.
- **HDDL as the long-term interchange format.** If HDDL export proves
  faithful in practice, it is the natural standard interface and the
  Peleus emitter becomes a convenience, not the primary path.


## Known rough edges in 0.0.2

- **Time granularity is whole days.** Julian Day Numbers are integers,
  so `activity_elapsed/2` and `since/2` count days. A real focus block
  is minutes long, so the during-rulebook's elapsed-time conditions are
  coarse. Sub-day timestamps are a 0.0.3 concern; the *structure*
  (a during-rule reading elapsed time) is correct and will not change
  when the unit gets finer.

## A design principle: structural invariants must not run conditions

`verify_rulebase`'s invariants inspect rules via `clause/2`, never by
calling `rule/4` as a goal. Calling `rule/4` as a goal executes the
rule's *condition*, so a rule whose condition is currently false would
be invisible to verification — and the rulebase would appear "clean"
only because of today's world state. A structural property (two rules
share a priority; a prereq is unanchored) must hold or fail
independently of what is true in the world right now. This was a real
bug caught by the test suite in 0.0.1 and is worth not reintroducing.

## Known rough edges in 0.0.1

- `months/2` approximates a month as 30 days. Fine for "every 5 months";
  swap for exact Gregorian month arithmetic if a rule needs precision.
- `verify_rulebase` flags `cut_fingernails` and `empty_trash` as
  `unanchored_prereq`. That is advisory, not a bug — those tasks are
  expanded elsewhere in FLP — but it means the first call won't return
  `[]`. Suppress known-good tasks once you've reviewed them.
- The decay boundary is inclusive: `decay(7)` keeps a fact fresh
  *through* day 7, firing on day 8. Deliberate, but check it matches
  your intuition for each rule.
