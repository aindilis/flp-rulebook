% ============================================================
%  flp_rulebook.pl
%  An Inform7-inspired rulebook engine for the Free Life Planner
%  Version 0.0.1
%
%  Design commitments (see DESIGN.md for rationale):
%   - The rulebase is plain data. Rules are terms; nothing about
%     a rule is hidden inside control flow. This is what makes
%     the engine homoiconic, verifiable, and portable to other
%     planners (SPAMI / PDDL / Peleus).
%   - The engine's real output is a list of structured
%     OUTCOME terms (ordering constraints + advisories), NOT text.
%     Pretty-printing is just one consumer of that output.
%   - Every precondition carries a staleness model, because an
%     FLP world is only partially observable.
%   - Per-rule outcome class: each rule states its own severity.
%
%  Dependencies: SWI-Prolog (lists, apply). No others.
% ============================================================

:- module(flp_rulebook,
          [ % --- core API -----------------------------------
            consider/2          % consider(+Trigger, -Outcomes)
          , consider/1          % consider(+Trigger)  — prints
          , verify_rulebase/1   % verify_rulebase(-Problems)
          , due_maintenance/1   % due_maintenance(-Tasks)
          , ordering_constraints/2 % (+Trigger,-before/2 terms)
          , evaluate_rulebook/3 % (+RuleHead,+Trigger,-Outcomes)
          , assert_observation/3% assert_observation(+Fact,+Val,+JDN)
            % --- time ---------------------------------------
          , now_jdn/1           % now_jdn(-JulianDayNumber)
          , gregorian_to_jdn/4  % gregorian_to_jdn(+Y,+M,+D,-JDN)
            % --- duration helpers for rule authors ----------
            %     Domain files (in their own modules) write
            %     rules like `... :- months(5, D)`, so these
            %     authoring helpers must be on the public API.
          , days/2              % days(+N,-Days)
          , weeks/2             % weeks(+N,-Days)
          , months/2            % months(+N,-Days)  (~30-day month)
            % --- introspection surface ----------------------
            %     Useful to FLP at large, and exercised by the
            %     test suite. These expose the engine's view of
            %     the world and of its own rules.
          , since/2             % since(+Fact,-DaysElapsed)
          , fresh/2             % fresh(+Fact,?Value)
          , stale/1             % stale(+Fact)
          , value/2             % value(+Fact,-Value)
          , blocked/1           % blocked(+Outcomes)
          , rule_mentions_fact/2% rule_mentions_fact(?Trig,?Fact)
          , body_facts/2        % body_facts(+BodyTerm,-Facts)
          ]).

% today/3 and fact/3 are dynamic and module-local. The test
% suite manipulates them via the flp_rulebook: qualifier; FLP
% production code should prefer assert_observation/3 for facts.

:- use_module(library(lists)).


% ============================================================
%  SECTION 1.  TIME  —  Julian Day Numbers
% ============================================================
%  A JDN is a plain integer. Intervals are integer subtraction.
%  This is the whole reason `since/1` and decay are trivial.

% gregorian_to_jdn(+Year,+Month,+Day,-JDN)
% Standard Fliegel-Van Flandern algorithm (integer arithmetic).
gregorian_to_jdn(Y, M, D, JDN) :-
    A is (14 - M) // 12,
    Y2 is Y + 4800 - A,
    M2 is M + 12*A - 3,
    JDN is D + (153*M2 + 2)//5 + 365*Y2
              + Y2//4 - Y2//100 + Y2//400 - 32045.

% now_jdn(-JDN) — today's Julian Day Number.
% In production, wire this to FLP's clock. For now it reads the
% configured `today/3` fact so test runs are deterministic.
now_jdn(JDN) :-
    today(Y, M, D),
    gregorian_to_jdn(Y, M, D, JDN).

% --- configurable "today" (replace with real clock in FLP) ---
:- dynamic today/3.
today(2026, 5, 17).

% Convenience for authoring rules: a duration in days.
days(N, N).
months(N, D) :- D is N * 30.      % rough; refine if you need exact
weeks(N, D)  :- D is N * 7.


% ============================================================
%  SECTION 2.  WORLD STATE
% ============================================================
%  fact(Name, Value, VerifiedJDN)
%    VerifiedJDN = the Julian day the fact was last confirmed,
%    whether by you, by a sensor, or by task completion.
%
%  Sensors / FLP task-completion hooks call assert_observation/3,
%  which is the ONLY supported way to mutate the world. Keeping a
%  single mutation entry point keeps the system cohesive and makes
%  the world auditable.

:- dynamic fact/3.

assert_observation(Name, Value, JDN) :-
    retractall(fact(Name, _, _)),
    assertz(fact(Name, Value, JDN)).

% value(+Name, -Value) — current believed value, ignoring freshness.
value(Name, Value) :- fact(Name, Value, _).

% The engine ships with an EMPTY world. Facts come from sensors,
% from task completion, or from a domain file — via
% assert_observation/3. (Earlier versions baked in a few sample
% facts here; they were stale-dated and made a REPL
% verify_rulebase look noisy, so they were removed. Worked
% domains in examples/ install their own worlds explicitly.)


% ============================================================
%  SECTION 3.  STALENESS  —  how long a fact stays trustworthy
% ============================================================
%  staleness(Fact, Model)
%    sticky        : never decays (default)
%    live          : trustworthy only if verified today
%    decay(Days)   : trustworthy for Days after verification
%
%  `since(Fact, Days)` is the primitive both decay and
%  maintenance goals are built on: it is just the integer
%  interval between a fact's verification and today.

% multifile: FLP domain files (and the example domains) add
% their own staleness models in their own files.
:- multifile staleness/2.
:- discontiguous staleness/2.

% Sample staleness models, paired with the sample rules below.
% NOTE: there is deliberately NO catch-all staleness(_, sticky)
% clause here. A catch-all in a multifile predicate is a trap:
% it loads with the engine, so it sits BEFORE any domain file's
% clauses, and once/1 would take it first — silently shadowing
% every domain-specific model. The `sticky` default is instead
% supplied by staleness_model/2 below, only when no clause
% matches. (This was a real bug.)
staleness(fingernails_cut,   decay(7)).
staleness(trash_fullness,    live).
staleness(safety_glasses_on, live).

% staleness_model(+Fact, -Model)
%   The model for Fact: a matching staleness/2 clause if one
%   exists, otherwise the default `sticky`. This is the ONLY
%   predicate that should be consulted for a fact's model —
%   never staleness/2 directly — because only this one applies
%   the default correctly regardless of clause load order.
staleness_model(Fact, Model) :-
    ( staleness(Fact, M)
    -> Model = M
    ;  Model = sticky
    ).

% since(+Fact, -Days) — days elapsed since the fact was verified.
since(Fact, Days) :-
    fact(Fact, _, Verified),
    now_jdn(Now),
    Days is Now - Verified.

% fresh(+Fact, ?Value) — is the fact CURRENTLY trustworthy?
fresh(Fact, Value) :-
    fact(Fact, Value, Verified),
    staleness_model(Fact, Model),
    fresh_under(Model, Verified).

fresh_under(sticky, _).
fresh_under(live,   Verified) :- now_jdn(Verified).
fresh_under(decay(Days), Verified) :-
    now_jdn(Now),
    Now - Verified =< Days.

% stale(+Fact) — known to the planner, but no longer trustworthy.
stale(Fact) :-
    fact(Fact, V, _),
    \+ fresh(Fact, V).


% ============================================================
%  SECTION 4.  THE RULEBASE
% ============================================================
%  rule(Trigger, Priority, Outcome, Consequence) :- Condition.
%
%    Trigger      : an activity/action name (atom or compound)
%    Priority     : integer; lower fires earlier
%    Outcome      : block | prereq | advise | warn   (per-rule)
%    Consequence  : task(Name) | note(Text)
%    Condition    : ordinary Prolog goal; rule fires if it holds
%
%  Because rules are plain clauses, the rulebase is data: other
%  rules, verifiers, and planner exporters can all read it.

% multifile: the whole point of a rulebook engine is that FLP
% deployments add their own rules and maintenance goals from
% their own files. See examples/morning_domain.pl.
:- multifile rule/4.
:- multifile maintenance/3.
:- discontiguous rule/4.
:- discontiguous maintenance/3.

% --- sample rules -------------------------------------
rule(play_guitar, 10, prereq, task(cut_fingernails)) :-
    \+ fresh(fingernails_cut, true).

rule(make_coffee, 20, warn, note('trash will overflow with coffee grounds')) :-
    value(trash_fullness, F), F > 0.80.

rule(make_coffee, 10, prereq, task(empty_trash)) :-
    value(trash_fullness, F), F > 0.95.

% --- a hard safety rule (the one case block/1 is appropriate) ---
rule(use_table_saw, 1, block, note('put on safety glasses first')) :-
    \+ fresh(safety_glasses_on, true).


% ============================================================
%  SECTION 5.  MAINTENANCE GOALS
% ============================================================
%  maintenance(Fact, EveryDays, Task)
%    "Fact should be re-established every EveryDays days;
%     when it falls due, spawn Task."
%
%  This is the DUAL of decay. Decay says a fact silently becomes
%  false. Maintenance says: when it goes stale, do something.
%  Same `since/1` primitive underneath.

maintenance(fire_alarm_battery, Days, task(change_fire_alarm_battery)) :-
    months(5, Days).

% due_maintenance(-Tasks) — all maintenance tasks currently due.
due_maintenance(Tasks) :-
    findall(due(Fact, OverdueBy, Task),
            ( maintenance(Fact, Every, Task),
              since(Fact, Elapsed),
              Elapsed >= Every,
              OverdueBy is Elapsed - Every ),
            Tasks).


% ============================================================
%  SECTION 6.  THE ENGINE
% ============================================================
%  consider(+Trigger, -Outcomes)
%    Outcomes is an ordered list of outcome/3 terms:
%      outcome(Class, Consequence, Priority)
%    sorted by Priority (Inform-style: earlier = more urgent).
%
%  This list IS the integration surface. A pretty-printer, a
%  PDDL exporter, or a Peleus method-builder are all just
%  different folds over this same list.

consider(Trigger, Outcomes) :-
    evaluate_rulebook(rule, Trigger, Outcomes).

% evaluate_rulebook(+RuleHead, +Trigger, -Outcomes)
%   The shared evaluation core: gather every clause of the named
%   4-arity rule predicate for Trigger, sort by priority, present
%   as outcome/3 terms. consider/2 uses rule/4; the activities
%   layer (flp_activities.pl) reuses this with its own rulebook
%   predicates (before_rule/4, during_rule/4, after_rule/4).
%
%   RuleHead may be a bare name (resolved in this module) or a
%   Module:Name pair, so a layer in another module can pass its
%   own rulebook predicate. The goal is built and called with
%   that qualification intact.
evaluate_rulebook(RuleHead, Trigger, Outcomes) :-
    ( RuleHead = Mod:Name
    -> Goal0 =.. [Name, Trigger, Pri, Class, Cons],
       Goal = Mod:Goal0
    ;  Goal =.. [RuleHead, Trigger, Pri, Class, Cons]
    ),
    findall(o(Pri, Class, Cons), Goal, Raw),
    sort(Raw, Sorted),                       % stable sort by Pri
    maplist(to_outcome, Sorted, Outcomes).

to_outcome(o(Pri, Class, Cons), outcome(Class, Cons, Pri)).

% --- helper views over the outcome list --------------------
blocked(Outcomes)  :- memberchk(outcome(block, _, _), Outcomes).

prereq_tasks(Outcomes, Tasks) :-
    findall(T, member(outcome(prereq, task(T), _), Outcomes), Tasks).

% ordering_constraints(+Trigger, -Constraints)
%   The planner-facing export. Each prereq becomes a
%   before/2 ordering constraint that PDDL or Peleus can ingest.
ordering_constraints(Trigger, Constraints) :-
    consider(Trigger, Outcomes),
    findall(before(T, Trigger),
            member(outcome(prereq, task(T), _), Outcomes),
            Constraints).


% ============================================================
%  SECTION 7.  PRESENTATION  (one consumer of the engine)
% ============================================================

consider(Trigger) :-
    consider(Trigger, Outcomes),
    format("~n== ~w ==~n", [Trigger]),
    ( Outcomes == []
    -> format("   (nothing to prepare \u2014 go ahead)~n")
    ;  forall(member(O, Outcomes), show_outcome(O))
    ),
    show_stale_warnings(Trigger).

% ~@ runs text(C) to print the consequence; ~w would print the
% literal term text(note(...)).
show_outcome(outcome(block,  C, _)) :- format("   [BLOCK]   ~@~n", [text(C)]).
show_outcome(outcome(prereq, C, _)) :- format("   [DO 1ST]  ~@~n", [text(C)]).
show_outcome(outcome(advise, C, _)) :- format("   [SUGGEST] ~@~n", [text(C)]).
show_outcome(outcome(warn,   C, _)) :- format("   [HEADS-UP]~@~n", [text(C)]).

text(task(T))  :- format("~w", [T]).
text(note(N))  :- format("~w", [N]).

% Surface preconditions the planner is no longer sure about.
show_stale_warnings(Trigger) :-
    findall(F,
            ( rule_mentions_fact(Trigger, F), stale(F) ),
            Stale0),
    sort(Stale0, Stale),
    ( Stale == [] -> true
    ; format("   ----~n"),
      forall(member(F, Stale),
             ( since(F, D),
               format("   [STALE?]  ~w last confirmed ~w days ago \u2014 still true?~n",
                      [F, D]) )) ).

% rule_mentions_fact(?Trigger, ?Fact)
% DERIVED, not declared. We introspect the body of every rule/4
% clause and collect the fact named by any state-consulting goal
% (since/2, fresh/2, stale/1, value/2). Because this reads the
% actual clauses, it cannot drift out of sync with the rules.
%
% A fact name that is unbound at clause-inspection time (computed
% at runtime) is reported as the atom `unknown`, so the drift is
% visible rather than silently dropped.
rule_mentions_fact(Trigger, Fact) :-
    clause(rule(Trigger, _, _, _), Body),
    body_facts(Body, Facts),
    member(Fact, Facts).

% body_facts(+BodyTerm, -Facts) — walk a clause body tree,
% recursing through control constructs, collecting fact names.
body_facts(Var, [unknown]) :-
    var(Var), !.
body_facts((A, B), Facts) :- !,
    body_facts(A, FA), body_facts(B, FB), append(FA, FB, Facts).
body_facts((A ; B), Facts) :- !,
    body_facts(A, FA), body_facts(B, FB), append(FA, FB, Facts).
body_facts((A -> B), Facts) :- !,
    body_facts(A, FA), body_facts(B, FB), append(FA, FB, Facts).
body_facts(\+ A, Facts) :- !,
    body_facts(A, Facts).
body_facts(once(A), Facts) :- !,
    body_facts(A, Facts).
body_facts(_:Goal, Facts) :- !,        % strip module qualification
    body_facts(Goal, Facts).           % (domain rules are flp_rulebook:...)
body_facts(Goal, [Fact]) :-
    state_goal(Goal, Fact0), !,
    ( var(Fact0) -> Fact = unknown ; Fact = Fact0 ).
body_facts(_, []).            % any non-state goal mentions no fact

% state_goal(+Goal, -FactName) — the goals that consult the world.
% The fact name is the first argument of each.
state_goal(since(F, _), F).
state_goal(fresh(F, _), F).
state_goal(stale(F),    F).
state_goal(value(F, _), F).


% ============================================================
%  SECTION 8.  VERIFICATION  (rulebase invariants as queries)
% ============================================================
%  Because the rulebase is data, its invariants are just goals.
%  verify_rulebase(-Problems) returns [] for a clean rulebase.

verify_rulebase(Problems) :-
    findall(P, rulebase_problem(P), Problems0),
    sort(Problems0, Problems).

% Invariant 1: no trigger both blocks and merely advises on the
% same consequence (a likely authoring mistake).
% Structural — inspect via clause/2, do not run conditions.
rulebase_problem(conflicting_outcome(Trigger, Cons)) :-
    clause(rule(Trigger, _, block,  Cons), _),
    clause(rule(Trigger, _, advise, Cons), _).

% Invariant 2: two rules on the same trigger sharing a priority
% (ordering then depends on clause order — fragile).
% Structural — inspect via clause/3, do not run conditions.
% Distinct clauses are told apart by clause REFERENCE, not by
% comparing consequences: a rule whose consequence is computed in
% its body (e.g. note(Text)) has a variable there, and two copies
% of the SAME clause would otherwise compare as different.
% (This was a real bug, found when flp-verification added such a rule.)
rulebase_problem(duplicate_priority(Trigger, Pri)) :-
    clause(rule(Trigger, Pri, _, _), _, R1),
    clause(rule(Trigger, Pri, _, _), _, R2),
    R1 @< R2.

% Invariant 3: a prereq names a task with no known way to be
% verified/completed (no fact, no maintenance entry). Advisory
% only — it may simply be a task FLP expands elsewhere.
%
% NOTE: this inspects rule STRUCTURE via clause/2, deliberately
% NOT via rule/4 as a goal. Calling rule/4 as a goal would run
% the rule's condition, so the invariant would depend on today's
% world — a structural check must not. (This was a real bug.)
rulebase_problem(unanchored_prereq(Trigger, Task)) :-
    clause(rule(Trigger, _, prereq, task(Task)), _),
    \+ fact(Task, _, _),
    \+ clause(maintenance(Task, _, _), _),
    \+ clause(maintenance(_, _, task(Task)), _).

% Invariant 4: a rule consults a fact whose name is computed at
% runtime, so the derived rule_mentions_fact/2 cannot see it and
% stale-warnings for that rule will be silently incomplete.
% (Surfaced by the `unknown` sentinel from body_facts/2.)
rulebase_problem(opaque_fact_reference(Trigger)) :-
    rule_mentions_fact(Trigger, unknown).
