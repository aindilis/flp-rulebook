# flp-rulebook

An Inform 7-inspired **rulebook engine** in Prolog, for life planning.

flp-rulebook is a standalone component of [FRDCSA](https://frdcsa.org)
(the Formalized Research Database: Cluster, Study and Apply), a
long-running free-software AI infrastructure project. Its eventual home
is the Free Life Planner (FLP), FRDCSA's life-management application —
but flp-rulebook depends on nothing from FRDCSA and runs entirely on
its own.

You describe *preparation*: for an activity you are about to do, what
should be true first, and what is worth knowing. The engine collects
every rule that applies, orders them, and tells you what to do — it can
also hand that decision to an HTN planner.

```prolog
?- consider(play_guitar).

== play_guitar ==
   [DO 1ST]  cut_fingernails
```

Built as a deliberative layer for the Free Life Planner (FLP), but it
is **standalone** — it depends on nothing but SWI-Prolog.

## Why

A rule is a conditional preparation step:

```prolog
rule(play_guitar, 10, prereq, task(cut_fingernails)) :-
    \+ fresh(fingernails_cut, true).
```

"Before playing guitar, if it is not currently true-and-fresh that your
fingernails are cut, the prerequisite is to cut them." You never
sequence rules by hand; the engine gathers and orders them. Every fact
the engine relies on carries a **staleness model**, because a planner's
knowledge of the world — unlike a game's — is only partial.

## What is here

| Module | Purpose |
|--------|---------|
| `flp_rulebook.pl` | core engine: rules, staleness, maintenance goals, verification |
| `flp_activities.pl` | activities — processes with before / during / after rulebooks |
| `flp_export.pl` | export a rule decision to HDDL / PDDL / Peleus |
| `flp_planner.pl` | run an HTN planner (PyHOP) and parse the plan back |

Each layer is optional and loads on top of the one before it. Every
module has a matching `test_*.pl` suite and most have a worked,
commented example domain in `examples/`.

## Requirements

- **SWI-Prolog** 9.x — all you need for the core engine, activities,
  export, and the great majority of the tests.
- **Python 3** — only for the *live* planner round-trip
  (`flp_planner.pl`). No package installation is required: the HTN
  planner (PyHOP) is vendored in `vendor/`, and `flp_planner.pl` puts
  it on `PYTHONPATH` itself. A plain `python3` interpreter is enough.
  Without Python, the planner round-trip tests skip cleanly; nothing
  else is affected.

## Quick start

```sh
swipl load.pl
```

`load.pl` consults the engine and every layer and sets up the path
aliases. Then, at the prompt:

```prolog
?- [flp(morning_domain)].
?- morning_demo.
```

`morning_demo` walks a worked domain — coffee, guitar, a maintenance
goal — printing what the engine decides and why.

Prefer `make`? `make demo` does the same in one step, and `make repl`
starts an interactive session with everything loaded.

## Running the tests

```sh
make test
```

runs all four suites. To run them individually, or by hand:

```prolog
?- [flp_rulebook], [test_flp_rulebook].                            ?- run_tests.
?- [flp_rulebook], [flp_activities], [test_flp_activities].        ?- run_tests.
?- [flp_rulebook], [flp_export], [test_flp_export].                ?- run_tests.
?- [flp_rulebook], [flp_export], [flp_planner], [test_flp_planner].?- run_tests.
```

Each suite installs its own deterministic world. The planner suite's
round-trip group runs only if `python3` can import the vendored
`pyhop`; otherwise it is reported as skipped, not failed.

## Documentation

- `GUIDE.md` — how to author rules, activities, exports, and planner
  runs. Start here.
- `DESIGN.md` — why the system is shaped the way it is, and the design
  principles behind it.

## Layout note

The `examples/` directory must sit beside the `.pl` modules, since the
demos load with paths like `['examples/morning_domain.pl']`. If you
unpack a flat archive, recreate it: `mkdir -p examples && mv *_demo.pl
*_domain.pl examples/`.

## Credit

The rulebook concept — an ordered, declaratively-sorted set of
condition-action rules, with before / for / after phases for activities
— is taken, with admiration, from Graham Nelson's **Inform 7**. This is
an independent Prolog implementation adapted for life planning; it
shares no Inform source. Inform 7's design simply got a great deal
right, and this project is one attempt to carry some of that into a
different domain.

## License

GPL (see `LICENSE`). Part of the FRDCSA project.
