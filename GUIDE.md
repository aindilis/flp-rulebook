# FLP Rulebook Engine — Guide

Version 0.0.1.

This is the practical guide: how to author rules, what the engine does
with them, and how to read its output. For *why* the design is shaped
this way, see `DESIGN.md`. For a fully worked, commented example, load
`examples/morning_domain.pl` and read along.

---

## 1. The mental model

You are describing **preparation**. For some activity you are about to
do — play guitar, make coffee, use the table saw — there are things
that should be true first, or things worth knowing about. You write
each of those as an independent **rule**. You never sequence the rules
by hand; the engine collects every rule that applies and orders them.

This is the Inform 7 *rulebook* idea, adapted: a game world is fully
known, but your planner's world is only partly known, so every fact the
engine relies on also carries a notion of how long it stays trustworthy.

Three moving parts:

- **Facts** — what the engine believes about the world, each stamped
  with the day it was last confirmed.
- **Rules** — "before activity X, given condition C, do/say Y."
- **The engine** — given an activity, gathers the rules that fire and
  returns an ordered list of things to do or know.

---

## 2. Authoring a rule

A rule is one Prolog clause:

```prolog
rule(Trigger, Priority, Outcome, Consequence) :- Condition.
```

| Part | What it is |
|------|------------|
| `Trigger` | the activity name, e.g. `play_guitar` |
| `Priority` | an integer; lower numbers are handled first |
| `Outcome` | one of `block`, `prereq`, `advise`, `warn` |
| `Consequence` | `task(Name)` or `note(Text)` |
| `Condition` | any Prolog goal; the rule fires when it succeeds |

The four **outcomes**, from hardest to softest:

- **`block`** — do not proceed. Reserve this for genuine safety
  (`use_table_saw` without glasses). It is the only outcome that means
  "stop."
- **`prereq`** — a task that should be done first. The engine can hand
  this to a planner as an ordering constraint.
- **`advise`** — a suggested task, freely skippable.
- **`warn`** — no task, just a heads-up about a downstream annoyance.

Worked example — "before playing guitar, cut nails":

```prolog
rule(play_guitar, 10, prereq, task(cut_fingernails)) :-
    \+ fresh(fingernails_cut, true).
```

Read it as: *for the activity `play_guitar`, with priority 10, if it is
not currently true-and-fresh that fingernails are cut, then the prereq
is the task `cut_fingernails`.*

You can have several rules on one trigger. The two coffee rules fire at
different trash thresholds and at different priorities:

```prolog
rule(make_coffee, 20, warn,   note('trash will overflow with grounds')) :-
    value(trash_fullness, F), F > 0.80.

rule(make_coffee, 10, prereq, task(empty_trash)) :-
    value(trash_fullness, F), F > 0.95.
```

At 85% full, only the warning fires. Past 95%, both fire, and the
prereq (priority 10) is listed before the warning (priority 20).

---

## 3. Facts and freshness

A fact is `fact(Name, Value, VerifiedJDN)` — the last component is the
Julian Day Number on which the fact was last confirmed. You rarely
write facts by hand; sensors, your own confirmations, and task
completions call `assert_observation/3`:

```prolog
?- now_jdn(Today), assert_observation(trash_fullness, 0.4, Today).
```

Every fact has a **staleness model** declared by `staleness/2`:

- **`sticky`** (the default) — never goes stale.
- **`live`** — trustworthy only if confirmed *today*.
- **`decay(Days)`** — trustworthy for `Days` after confirmation,
  inclusive of the last day.

```prolog
staleness(fingernails_cut, decay(7)).   % good for a week
staleness(trash_fullness,  live).       % must be checked now
```

Three predicates read freshness, and they are what your rule
*conditions* should use:

- `fresh(Fact, Value)` — the fact holds *and* is still trustworthy.
- `stale(Fact)` — the engine knows the fact but no longer trusts it.
- `since(Fact, Days)` — how many days since it was confirmed.

`since/2` is also the basis of **maintenance goals** — see §5.

---

## 4. Running the engine

`consider/2` is the engine. It returns structured data:

```prolog
?- consider(make_coffee, Outcomes).
Outcomes = [ outcome(prereq, task(empty_trash), 10),
             outcome(warn,   note('trash will overflow...'), 20) ].
```

That list is the integration point — a pretty-printer, a PDDL
exporter, or a Peleus method-builder all just fold over it.
`consider/1` is the human-readable version and also prints **stale
warnings**: if a rule for the trigger depends on a fact that has gone
stale, you are asked to re-confirm it rather than have the engine guess.

`ordering_constraints/2` gives the planner-facing view directly:

```prolog
?- ordering_constraints(play_guitar, C).
C = [before(cut_fingernails, play_guitar)].
```

---

## 5. Maintenance goals

A maintenance goal is the dual of decay: decay says a fact silently
becomes untrustworthy; maintenance says *when it does, spawn a task*.

```prolog
maintenance(fire_alarm_battery, Days, task(change_fire_alarm_battery)) :-
    months(5, Days).
```

`due_maintenance/1` returns everything currently overdue, with how far
overdue each is:

```prolog
?- due_maintenance(D).
D = [due(fire_alarm_battery, 47, task(change_fire_alarm_battery))].
```

---

## 6. Checking your rulebase

`verify_rulebase/1` treats the rulebase as data and runs invariants
over it:

| Problem reported | Meaning |
|------------------|---------|
| `conflicting_outcome(T,C)` | a trigger both blocks and advises the same thing |
| `duplicate_priority(T,P)` | two rules share a priority — ordering is fragile |
| `unanchored_prereq(T,Task)` | prereq task has no fact/maintenance anchor (often fine) |
| `opaque_fact_reference(T)` | a rule consults a fact named at runtime — stale-warnings for it will be incomplete |

A clean rulebase returns `[]`. The shipped sample rulebase intentionally
reports two `unanchored_prereq` entries, because `cut_fingernails` and
`empty_trash` are tasks FLP expands elsewhere — see `DESIGN.md`.

---

## 7. Activities (v0.0.2)

A **rule** attaches to a discrete action — a single moment. An
**activity** is a process with duration: a focus block, a practice
session, cooking. Load `flp_activities.pl` (on top of `flp_rulebook.pl`)
to use them.

An activity has *three* rulebooks, evaluated at three points in its
life:

| Rulebook | Authored as | Evaluated |
|----------|-------------|-----------|
| before | `before_rule/4` | as the activity begins |
| during | `during_rule/4` | at a check-in while it runs |
| after | `after_rule/4` | as it ends |

Each is authored exactly like `rule/4` — same priority, same four
outcome classes, same `task(...)`/`note(...)` consequences:

```prolog
before_rule(focus_block, 10, advise, task(silence_phone)) :-
    \+ fresh(phone_silenced, true).

during_rule(focus_block, 10, advise, note('a short break helps')) :-
    activity_elapsed(focus_block, D), D >= 1.

after_rule(focus_block, 10, advise, task(log_session)).
```

The during-rulebook is the one with no Inform 7 equivalent: a
during-rule can consult `activity_elapsed/2`, so its condition can
depend on *how long the activity has been running*. That is the whole
reason activities are not just rules.

You drive an activity through its lifecycle:

```prolog
?- begin(focus_block).      % evaluates before-rules, marks it running
?- check_in(focus_block).   % evaluates during-rules
?- conclude(focus_block).   % evaluates after-rules, marks it ended
```

`begin/1` and `conclude/1` are the lifecycle plus printing;
`start_activity/1` and `end_activity/1` are the lifecycle alone if you
want to manage presentation yourself. `verify_activities/1` is the
activity-rulebook counterpart of `verify_rulebase/1` — notably it flags
a `block` outcome in a during- or after-rule, since you cannot block an
activity that has already begun.

Worked example: load `examples/focus_activity_domain.pl` and run
`focus_demo`.

---

## 8. Exporting to a planner (v0.0.3)

`flp_export.pl` turns the engine's prereq decisions into planner input.
Load it on top of `flp_rulebook.pl`. It first extracts a neutral form,
`plan_fragment(Trigger, PrereqTasks, Orderings)`, then offers three
emitters over it:

```prolog
?- to_hddl(play_guitar, H).      % HTN method (the faithful target)
?- to_pddl(play_guitar, P).      % flat action (loses prereq ordering)
?- to_peleus(play_guitar, Terms).% Prolog terms for Peleus on ai2
?- write_export(hddl, play_guitar, '/tmp/play_guitar.hddl').
```

HDDL is the target to prefer: a prereq is a decomposition, which is
exactly an HTN method, and HDDL expresses that directly. PDDL is for
tool compatibility — with several prereqs it cannot represent their
order. See `examples/export_demo.pl` (`export_demo`) for the same
decision rendered all three ways side by side.

---

## 9. Running a planner (v0.0.4)

`flp_planner.pl` does the full round-trip: it takes a rulebook
decision, runs an actual HTN planner on it, and parses the plan back
into Prolog. Load it on top of `flp_rulebook.pl` and `flp_export.pl`.

```prolog
?- run_planner(pyhop, play_guitar, Plan).
Plan = [step(cut_fingernails), step(play_guitar)].
```

The plan is a list of `step/1` terms in execution order — here: cut
your fingernails, then play guitar.

A planner is a **backend**, described by four multifile hooks
(`planner_backend/1`, `backend_emit/3`, `backend_invoke/3`,
`backend_parse/3`). `run_planner/3` is completely backend-agnostic, so
adding a planner never touches it. PyHOP is the first backend; a
Lilotane (HDDL/SAT) backend is sketched in `flp_planner.pl` Section 3
and would reuse `to_hddl/2` unchanged.

PyHOP itself has no input file format — operators and methods are
ordinary Python — so the PyHOP backend emits a complete Python program.
It requires `python3` with `pyhop` importable; without it,
`run_planner/3` throws a clear error and `pyhop_program/2` still lets
you inspect the generated program. See `examples/planner_demo.pl`.

---

## 10. Running the tests

From SWI-Prolog, in this directory:

```prolog
?- [flp_rulebook], [test_flp_rulebook].
?- run_tests.
```

For the activities layer:

```prolog
?- [flp_rulebook], [flp_activities], [test_flp_activities].
?- run_tests.
```

For the planner-export layer:

```prolog
?- [flp_rulebook], [flp_export], [test_flp_export].
?- run_tests.
```

For the planner-backend layer:

```prolog
?- [flp_rulebook], [flp_export], [flp_planner], [test_flp_planner].
?- run_tests.
```

The planner suite's round-trip group runs PyHOP only if `python3` with
`pyhop` is installed; otherwise that group is skipped (reported as
blocked), not failed, so the suite stays green either way.

Each suite installs its own deterministic world, so results do not
depend on any shipped sample fixture.

---

## 11. A common authoring mistake

The decay boundary is **inclusive**: `decay(7)` keeps a fact fresh
through day 7 and a rule that needs it fires on day 8. If you mean
"strictly less than a week," use `decay(6)`. The test
`decay_inclusive_boundary` pins this behaviour down — if you change it,
that test should change with it.
