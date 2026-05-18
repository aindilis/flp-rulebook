# flp-rulebook — Future Directions

A map, not a to-do list. The point of this document is to hold the
known directions so they do not have to be held in your head — and to
sequence them, so "what next" has a single answer at any moment rather
than a cloud of competing ones.

Read the **You Are Here** line first. Then the **next phase only**. The
later phases are written down so they are safe to forget until their
turn.

---

## You Are Here

**v0.0.4 is complete.** The system has four layers — core engine,
activities, planner export, planner round-trip — all tested (58 tests
green) and documented. The PyHOP round-trip is validated end to end.

The system **already does its core job today**: conditional
preparation, staleness, maintenance goals, activities. The morning
domain runs. Everything below is amplification, not repair.

**The single next action** is Phase 1. Nothing else.

---

## The sequencing principle

Each phase has a *definite endpoint* — a point where it is provably
done and the system is in a clean, releasable state. Phases are ordered
so that each one closes a loop before the next opens. This is
deliberate: the failure mode for this project is not lack of ideas, it
is opening many loops at once. One open loop at a time.

A phase is not started until the previous phase's endpoint is reached.

---

## Phase 1 — Ship it (smallest, do this first)

**Goal:** flp-rulebook is a public, self-contained GitHub repository.

**Why first:** the system works and is tested. The gap between "works
on the dev machine" and "exists in the world" is small and worth
closing now, while the system is in a known-good state. A shipped 0.0.4
is worth more than an unshipped 0.0.7.

**Tasks:**
- Vendor `pyhop.py` into `vendor/` with a short `vendor/README`
  recording its source and Apache license, so a fresh clone runs the
  round-trip with no `pip install`.
- Add a `LICENSE` file (GPL, per FRDCSA convention).
- Add a loader file or `Makefile` so `examples/` placement is not a
  manual step after unzip.
- Optionally: module-declare the four test files to silence the
  cosmetic `set_today/3` redefinition warning. Low priority.
- Push to `github.com/aindilis/flp-rulebook`.

**Endpoint:** `git clone` + run the test suites + run a demo, on a
fresh machine, with nothing but SWI-Prolog and Python 3.

---

## Phase 2 — Sub-day time

**Goal:** activities and `since/2` work in minutes, not whole days.

**Why second:** it is the one *known limitation* in shipped code
(flagged in DESIGN.md). Julian Day Numbers are integers; an activity's
during-rules can only branch on whole-day granularity, which is too
coarse for a focus block. Fixing it is self-contained — it touches the
time section of the core and the `activity_elapsed/2` predicate — and
it makes the activities layer genuinely useful rather than a
demonstrated structure.

**Shape:** Julian Date with a fractional part (a float), or a separate
seconds component. Decide which; the `since/2` and `decay` machinery
generalises cleanly either way.

**Endpoint:** a during-rule can say "this focus block has run 25
minutes" and the activities test suite covers sub-day intervals.

---

## Phase 3 — A second planner backend (Lilotane)

**Goal:** a real, strong HTN planner behind the same backend interface.

**Why third:** PyHOP is a teaching planner — depth-first, no
optimisation. The backend interface (`flp_planner.pl`) was built to
hold a stronger one, and `flp_export.pl` already emits HDDL. Lilotane
reads HDDL natively and was an IPC-2020 contender. This phase proves
the backend abstraction was real and gives the system a planner worth
trusting on hard problems.

**Tasks:**
- Implement the four hooks for `lilotane`: `backend_emit` reuses
  `to_hddl/2` unchanged; `backend_invoke` shells out to the `lilotane`
  binary (or `planutils run lilotane`); `backend_parse` reads
  Lilotane's plan format.
- Package: Lilotane, being file-based HDDL, fits `planutils` cleanly —
  unlike PyHOP. This is where the `planutils` path belongs.

**Endpoint:** `run_planner(lilotane, Trigger, Plan)` works, and the
generic runner is unchanged — proving backends are truly additive.

**Note:** "beefy planners / multi-planner integration" was an explicit
goal. This phase is its first real instalment; further backends (PANDA,
SHOP3) are then trivial repeats of the same four-hook pattern.

---

## Phase 4 — The task taxonomy

**Goal:** rules can attach to *types* of task, not only literal task
names, with `genls`-style subsumption.

**Why fourth:** this is the SPSE4-adjacent idea — `genls(guitar_practice,
preparatory_task)`, instances inheriting qualities. It is genuinely
valuable: today a rule about `play_guitar` says nothing about
`practice_guitar` or about "musical activities" in general. But it is
fourth, not first, because it is a new *layer* and the system is more
valuable shipped-and-flat than unshipped-and-hierarchical.

**The key architectural decision (already made, recorded here so it
stays made):** the taxonomy is reached through a **seam, not a
dependency**. A multifile `subsumes/2` hook the rulebook calls to ask
"is trigger T a kind of type X?". Default implementation is flat
(`subsumes(X, X)`). An *optional* binding connects it to FLP's
`genls/2`, or to Cyc's TCP interface, or to nothing. **The rulebook
never imports FLP and never depends on SPSE4.** FLP will not release
for years; flp-rulebook is releasable now and must stay that way.

**Shape:** rule lookup in `evaluate_rulebook/3` generalises so a rule
for type T also fires for any trigger that `subsumes`-resolves under T.
This is, in effect, Inform 7's specificity-ordering — set aside in
0.0.1 for explicit priorities — returning, but grounded in a real
ontology rather than a built-in kind-lattice.

**Endpoint:** a rule written for `preparatory_task` fires for a
`play_guitar` instance, with the taxonomy supplied by a pluggable hook
and a flat default.

---

## Phase 5 — The execution seam (for-rules)

**Goal:** the rulebook can hand intentions to an executor.

**Why fifth:** it depends on a decision not yet made — *which*
executor. 0.0.2 dropped Inform's for-rules because a pure advisor has
no "doing" to wrap. With an executor there is one, and `for_rule/4`
becomes the seam: a fourth activity rulebook whose consequence is an
execution directive (`run`, `monitor`, `fallback`) rather than a task.

**Blocked on:** deciding the executor. Candidates discussed: an
AgentSpeak(L)-family system (DALI, IndiGolog), possibly paired with a
behavior tree for PLEXIL-style execution monitoring; or something
SPAMI-native. This is a separate project with its own 0.0.1 — the
rulebook's job is only to *emit* intentions cleanly through the seam.

**Endpoint:** not defined yet — defined once the executor is chosen.

---

## Phase 6 and beyond — held, not scheduled

These are real and recorded so they need not be re-derived. They are
explicitly *not* scheduled — they are held until a phase above makes
one of them the obvious next thing.

- **A rulebook authoring UI** — an SPSE4-style HTTPS editor for rules.
  Fits the executive-dysfunction goal directly (low-friction
  authoring). A UI project, parallel to the engine work; should not
  jump the queue.
- **SPeleus** — a SPAMI-native HTN planner. Only if the borrowed
  planners (Phase 3) prove insufficient. Building a planner before the
  requirements are known is the expensive mistake; defer until
  Phase 3's planners have been *used*.
- **Cyc integration proper** — via the TCP interface or Cyc-RL's Java
  API, as the taxonomy backend behind Phase 4's `subsumes/2` hook.
- **Multi-agent / blackboard / semantic digital twin** — real-time
  world-sync with sensors and softbots. This belongs to the *executor*
  project, not flp-rulebook. Named here only so it is not lost.
- **A faithful Inform 7 rulebook reimplementation** — the sibling
  module noted since 0.0.1: specificity sort, succeed/fail/stop
  semantics, for-rules. A distinct artifact with fidelity as its goal.
- **`.deb` packaging of PyHOP** — `python3-pyhop`. Small, finite, fits
  the autopackager pipeline. A FRDCSA infra task, orthogonal to
  rulebook versioning; do it whenever a small satisfying task is
  wanted.

### Inform 7 features not yet adopted

flp-rulebook took Inform 7's *rulebook* idea and the before/during/after
phase structure. Inform 7's rule system has more, recorded here so the
borrowing is a deliberate choice rather than a forgotten one. None of
these is scheduled; each is held until a phase above makes it the
obvious next thing.

- **An after-phase for discrete rules.** Activities have a full
  before/during/after structure (v0.0.2); discrete `rule/4` rules have
  only a before-phase. So "after brewing coffee, discard the grounds"
  is expressible if `brew_coffee` is an *activity*, but not if it is a
  discrete rule. This asymmetry is mild but real. The likely resolution
  is a documented rule of thumb — *anything with meaningful
  after-effects should be modelled as an activity* — rather than
  bolting an after-phase onto discrete rules. A GUIDE note, when
  touched.
- **Scenes.** Inform 7 *scenes* are condition-bounded periods of time,
  each with its own begins/ends rulebooks. A life planner has scenes —
  a workday, a flare-up day, a travel day — and rules that should apply
  only within one. This is judged the *most valuable* untaken Inform 7
  idea: it would let rules be scoped to a context rather than always
  active. A natural successor to the Phase 4 taxonomy.
- **Instead-rules.** Inform 7 lets a rule wholly *replace* a default
  action. For a planner this is substitution: "instead of brewing
  coffee when out of beans, add beans to the shopping list." Modest
  effort, clear value.
- **Every-turn rules.** Rules that fire each tick regardless of the
  action. Partly already covered by maintenance goals; a fuller
  version would generalise them.
- **The procedural rulebook (rules about rules).** Inform 7 can skip,
  defer to, or reorder other rules at runtime. Powerful and
  correspondingly risky; lowest priority, noted only for completeness.

A *faithful* reimplementation of Inform 7's rule semantics as a whole
is already listed above as a separate sibling-module idea; this list is
about features worth selectively adopting into flp-rulebook itself.

---

## What to deliberately NOT do

This section is as important as the phases.

- **Do not tie flp-rulebook to FLP or SPSE4.** Both are reached through
  hooks. The rulebook ships independently. This is decided.
- **Do not design the executor before Phase 5.** Naming candidates is
  fine; committing architecture now is premature.
- **Do not build SPeleus before Phase 3's planners are used.**
- **Do not start a phase before the previous one's endpoint is
  reached.** One open loop at a time.
- **Do not let this document grow into a backlog.** It is a map. If a
  new idea arrives, it goes in "held, not scheduled" — it does not
  reorder the phases.

The core system already helps with the actual problem. Every phase is
an amplifier. Shipping and stability beat scope.
