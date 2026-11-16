% ============================================================
%  test_flp_rulebook.pl
%  Test suite for the FLP rulebook engine (v0.0.1).
%
%  Run from SWI-Prolog:
%      ?- [flp_rulebook], [test_flp_rulebook].
%      ?- run_tests.
%
%  Uses the plunit framework that ships with SWI-Prolog.
%
%  NOTE ON ISOLATION:
%  The engine loads a sample world (fact/3 entries) and a default
%  today/3 at consult time. Each test group below installs its own
%  deterministic world in a setup/1 goal and restores nothing — the
%  last group to run leaves its world in place, which is fine for a
%  test process. If you consult the engine fresh you get the sample
%  world back. Tests never depend on the engine's sample fixture.
% ============================================================

:- use_module(library(plunit)).
:- use_module(flp_rulebook).

% ---- shared helpers ---------------------------------------
% Install a known "today" (Gregorian) for deterministic time tests.
% today/3 and fact/3 are module-local dynamics in flp_rulebook,
% so we qualify the asserts/retracts explicitly.
set_today(Y, M, D) :-
    retractall(flp_rulebook:today(_,_,_)),
    assertz(flp_rulebook:today(Y, M, D)).

% Replace the whole world with an explicit list of fact/3 terms.
set_world(Facts) :-
    retractall(flp_rulebook:fact(_,_,_)),
    forall(member(F, Facts), assertz(flp_rulebook:F)).

% Build a fact/3 term from a Gregorian verification date.
mk_fact(Name, Val, Y-M-D, fact(Name, Val, JDN)) :-
    gregorian_to_jdn(Y, M, D, JDN).


% ============================================================
%  GROUP 1.  Julian Day arithmetic
% ============================================================
:- begin_tests(julian).

% A known anchor: 2000-01-01 is JDN 2451545.
test(epoch_2000) :-
    gregorian_to_jdn(2000, 1, 1, JDN),
    assertion(JDN =:= 2451545).

% Consecutive days differ by exactly 1.
test(consecutive_days) :-
    gregorian_to_jdn(2026, 5, 17, A),
    gregorian_to_jdn(2026, 5, 18, B),
    assertion(B - A =:= 1).

% Interval across a month boundary is plain subtraction.
test(month_boundary) :-
    gregorian_to_jdn(2026, 5, 31, A),
    gregorian_to_jdn(2026, 6, 1, B),
    assertion(B - A =:= 1).

% Leap-year span: 2024-02-28 -> 2024-03-01 is 2 days (Feb 29 exists).
test(leap_year) :-
    gregorian_to_jdn(2024, 2, 28, A),
    gregorian_to_jdn(2024, 3, 1, B),
    assertion(B - A =:= 2).

% Non-leap span: 2026-02-28 -> 2026-03-01 is 1 day.
test(non_leap_year) :-
    gregorian_to_jdn(2026, 2, 28, A),
    gregorian_to_jdn(2026, 3, 1, B),
    assertion(B - A =:= 1).

:- end_tests(julian).


% ============================================================
%  GROUP 2.  Staleness and `since/1`
% ============================================================
:- begin_tests(staleness).

% since/2 reports the integer day gap to the verification date.
test(since_counts_days,
     setup(( set_today(2026,5,17),
             mk_fact(fingernails_cut, true, 2026-5-10, F),
             set_world([F]) ))) :-
    since(fingernails_cut, D),
    assertion(D =:= 7).

% decay(7): a fact verified 7 days ago is STILL fresh (inclusive).
test(decay_inclusive_boundary,
     setup(( set_today(2026,5,17),
             mk_fact(fingernails_cut, true, 2026-5-10, F),
             set_world([F]) ))) :-
    assertion(fresh(fingernails_cut, true)).

% decay(7): a fact verified 8 days ago is stale.
test(decay_past_boundary,
     setup(( set_today(2026,5,18),
             mk_fact(fingernails_cut, true, 2026-5-10, F),
             set_world([F]) ))) :-
    assertion(stale(fingernails_cut)),
    assertion(\+ fresh(fingernails_cut, true)).

% live: a fact verified today is fresh.
test(live_fresh_today,
     setup(( set_today(2026,5,17),
             mk_fact(trash_fullness, 0.5, 2026-5-17, F),
             set_world([F]) ))) :-
    assertion(fresh(trash_fullness, 0.5)).

% live: a fact verified yesterday is already stale.
test(live_stale_yesterday,
     setup(( set_today(2026,5,17),
             mk_fact(trash_fullness, 0.5, 2026-5-16, F),
             set_world([F]) ))) :-
    assertion(stale(trash_fullness)).

% sticky (default): an unlisted fact never goes stale.
test(sticky_default_never_stale,
     setup(( set_today(2030,1,1),
             mk_fact(some_unmodelled_fact, true, 2026-5-17, F),
             set_world([F]) ))) :-
    assertion(fresh(some_unmodelled_fact, true)),
    assertion(\+ stale(some_unmodelled_fact)).

:- end_tests(staleness).


% ============================================================
%  GROUP 3.  The engine — consider/2
% ============================================================
:- begin_tests(engine).

% Trash at 0.70: neither coffee rule fires; outcomes empty.
test(coffee_quiet_below_threshold,
     setup(( set_today(2026,5,17),
             mk_fact(trash_fullness, 0.70, 2026-5-17, F),
             set_world([F]) ))) :-
    consider(make_coffee, Outcomes),
    assertion(Outcomes == []).

% Trash at 0.85: only the warn rule fires.
test(coffee_warns_at_85,
     setup(( set_today(2026,5,17),
             mk_fact(trash_fullness, 0.85, 2026-5-17, F),
             set_world([F]) ))) :-
    consider(make_coffee, Outcomes),
    assertion(Outcomes = [outcome(warn, _, _)]).

% Trash at 0.97: both rules fire; prereq (pri 10) sorts before
% warn (pri 20).
test(coffee_prereq_and_warn_ordered,
     setup(( set_today(2026,5,17),
             mk_fact(trash_fullness, 0.97, 2026-5-17, F),
             set_world([F]) ))) :-
    consider(make_coffee, Outcomes),
    assertion(Outcomes = [ outcome(prereq, task(empty_trash), 10),
                           outcome(warn,   _,                 20) ]).

% Guitar with fresh nails: nothing to prepare.
test(guitar_quiet_with_fresh_nails,
     setup(( set_today(2026,5,17),
             mk_fact(fingernails_cut, true, 2026-5-10, F),
             set_world([F]) ))) :-
    consider(play_guitar, Outcomes),
    assertion(Outcomes == []).

% Guitar with stale nails: the cut_fingernails prereq fires.
test(guitar_prereq_with_stale_nails,
     setup(( set_today(2026,5,20),
             mk_fact(fingernails_cut, true, 2026-5-10, F),
             set_world([F]) ))) :-
    consider(play_guitar, Outcomes),
    assertion(Outcomes = [outcome(prereq, task(cut_fingernails), _)]).

% blocked/1 view: a block outcome is detected.
test(blocked_view_detects_block,
     setup(( set_today(2026,5,17),
             set_world([]) ))) :-          % no safety_glasses_on fact
    consider(use_table_saw, Outcomes),
    assertion(blocked(Outcomes)).

% ordering_constraints/2 exports before/2 terms for planners.
test(ordering_constraints_exported,
     setup(( set_today(2026,5,20),
             mk_fact(fingernails_cut, true, 2026-5-10, F),
             set_world([F]) ))) :-
    ordering_constraints(play_guitar, Cs),
    assertion(Cs == [before(cut_fingernails, play_guitar)]).

:- end_tests(engine).


% ============================================================
%  GROUP 4.  Maintenance goals
% ============================================================
:- begin_tests(maintenance).

% Battery changed within the 5-month window: nothing due.
test(battery_not_yet_due,
     setup(( set_today(2026,2,1),
             mk_fact(fire_alarm_battery, changed, 2025-11-1, F),
             set_world([F]) ))) :-
    due_maintenance(Due),
    assertion(Due == []).

% Battery overdue: appears in due list with a positive overdue gap.
test(battery_overdue,
     setup(( set_today(2026,5,17),
             mk_fact(fire_alarm_battery, changed, 2025-11-1, F),
             set_world([F]) ))) :-
    due_maintenance(Due),
    % Unify in the test body itself — assertion/1 runs its goal in
    % a copy and discards bindings, so Over must be bound out here.
    Due = [due(fire_alarm_battery, Over, task(change_fire_alarm_battery))],
    assertion(integer(Over)),
    assertion(Over > 0).

:- end_tests(maintenance).


% ============================================================
%  GROUP 5.  Derived rule_mentions_fact/2  (the clean fix)
% ============================================================
:- begin_tests(introspection).

% The play_guitar rule consults fingernails_cut — derived, not declared.
test(derives_guitar_fact) :-
    assertion(rule_mentions_fact(play_guitar, fingernails_cut)).

% The make_coffee rules consult trash_fullness.
test(derives_coffee_fact) :-
    assertion(rule_mentions_fact(make_coffee, trash_fullness)).

% The table-saw rule consults safety_glasses_on.
test(derives_saw_fact) :-
    assertion(rule_mentions_fact(use_table_saw, safety_glasses_on)).

% A literal comparison (F > 0.80) contributes no fact.
test(comparison_contributes_no_fact) :-
    findall(Fact, rule_mentions_fact(make_coffee, Fact), Facts),
    sort(Facts, Sorted),
    assertion(Sorted == [trash_fullness]).

% body_facts walks a negation correctly.
test(body_facts_through_negation) :-
    body_facts(\+ fresh(some_fact, true), Facts),
    assertion(Facts == [some_fact]).

% body_facts walks a conjunction, dropping non-state goals.
test(body_facts_through_conjunction) :-
    body_facts((value(a, X), X > 1, fresh(b, true)), Facts),
    assertion(Facts == [a, b]).

% A runtime-computed fact name surfaces as the `unknown` sentinel.
test(body_facts_unknown_for_variable) :-
    body_facts(value(_SomeVar, _), Facts),
    assertion(Facts == [unknown]).

% body_facts strips module qualification (domain rules added from
% another file carry flp_rulebook: qualifiers on their goals).
test(body_facts_strips_module_qualifier) :-
    body_facts(flp_rulebook:fresh(some_fact, true), Facts),
    assertion(Facts == [some_fact]).

% ...even nested inside a negation, as multifile domain rules are.
test(body_facts_qualified_inside_negation) :-
    body_facts(\+ flp_rulebook:fresh(some_fact, true), Facts),
    assertion(Facts == [some_fact]).

:- end_tests(introspection).


% ============================================================
%  GROUP 6.  Rulebase verification
% ============================================================
% A rule whose consequence is computed in its body, the way
% flp-verification's execute_plan rule is. Used by two tests below.
:- multifile flp_rulebook:rule/4.
flp_rulebook:rule(test_computed_consequence, 5, warn, note(T)) :-
    atom_concat(comp, uted, T).

:- begin_tests(verification).

% Two copies of ONE clause with a variable consequence must not be
% reported as a duplicate priority (regression: compare clause refs).
test(computed_consequence_not_duplicate) :-
    verify_rulebase(Problems),
    assertion(\+ memberchk(duplicate_priority(test_computed_consequence, _), Problems)).

% consider/1 prints the consequence text, not the term text(note(...)).
test(consider_prints_consequence_text) :-
    with_output_to(string(S), consider(test_computed_consequence)),
    assertion(sub_string(S, _, _, _, "computed")),
    assertion(\+ sub_string(S, _, _, _, "text(")).

% The shipped rulebase has no conflicting_outcome or
% duplicate_priority or opaque_fact_reference problems.
test(no_serious_problems) :-
    verify_rulebase(Problems),
    assertion(\+ memberchk(conflicting_outcome(_,_),  Problems)),
    assertion(\+ memberchk(duplicate_priority(_,_),   Problems)),
    assertion(\+ memberchk(opaque_fact_reference(_),  Problems)).

% The shipped rulebase DOES (expectedly) report unanchored prereqs
% for tasks expanded elsewhere in FLP — documented behaviour.
test(expected_unanchored_prereqs,
     setup(set_world([]))) :-
    verify_rulebase(Problems),
    assertion(memberchk(unanchored_prereq(play_guitar, cut_fingernails), Problems)),
    assertion(memberchk(unanchored_prereq(make_coffee, empty_trash),     Problems)).

:- end_tests(verification).
