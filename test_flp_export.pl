% ============================================================
%  test_flp_export.pl
%  Test suite for the planner-export layer (v0.0.3).
%
%  Run from SWI-Prolog:
%      ?- [flp_rulebook], [flp_export], [test_flp_export].
%      ?- run_tests.
%
%  Tests install their own world so the prereq rules fire
%  deterministically, then check the neutral form and each
%  emitter. String emitters are checked by sub_string/5 for
%  required fragments rather than by exact match, so cosmetic
%  whitespace changes do not break the suite.
% ============================================================

:- use_module(library(plunit)).
:- use_module(flp_rulebook).
:- use_module(flp_export).

% --- helpers -----------------------------------------------
set_today(Y,M,D) :-
    retractall(flp_rulebook:today(_,_,_)),
    assertz(flp_rulebook:today(Y,M,D)).

% world where play_guitar's prereq fires (nails long stale) and
% make_coffee's prereq fires (trash over 0.95).
world_prereqs_fire :-
    retractall(flp_rulebook:fact(_,_,_)),
    set_today(2026,5,30),
    gregorian_to_jdn(2026,5,1,J1),
    assertz(flp_rulebook:fact(fingernails_cut, true, J1)),
    gregorian_to_jdn(2026,5,30,J2),
    assertz(flp_rulebook:fact(trash_fullness, 0.97, J2)).

% world where no prereq fires.
world_quiet :-
    retractall(flp_rulebook:fact(_,_,_)),
    set_today(2026,5,17),
    gregorian_to_jdn(2026,5,15,J1),
    assertz(flp_rulebook:fact(fingernails_cut, true, J1)),
    gregorian_to_jdn(2026,5,17,J2),
    assertz(flp_rulebook:fact(trash_fullness, 0.20, J2)).


% ============================================================
%  GROUP 1.  The neutral intermediate form
% ============================================================
:- begin_tests(neutral_form).

% play_guitar with stale nails: one prereq, one ordering.
test(fragment_guitar_with_prereq,
     setup(world_prereqs_fire)) :-
    plan_fragment(play_guitar, F),
    F = plan_fragment(play_guitar, Prereqs, Orderings),
    assertion(Prereqs == [cut_fingernails]),
    assertion(Orderings == [before(cut_fingernails, play_guitar)]).

% a quiet trigger: no prereqs, no orderings.
test(fragment_quiet_trigger,
     setup(world_quiet)) :-
    plan_fragment(play_guitar, F),
    assertion(F == plan_fragment(play_guitar, [], [])).

% prereq_chain links consecutive tasks (tested directly).
test(prereq_chain_links_consecutive) :-
    flp_export:prereq_chain([a,b,c], Chain),
    assertion(Chain == [before(a,b), before(b,c)]).

test(prereq_chain_empty) :-
    flp_export:prereq_chain([], C),
    assertion(C == []).

test(prereq_chain_singleton) :-
    flp_export:prereq_chain([only], C),
    assertion(C == []).

:- end_tests(neutral_form).


% ============================================================
%  GROUP 2.  HDDL emitter
% ============================================================
:- begin_tests(hddl).

% the HDDL output is a :method for the trigger.
test(hddl_emits_method,
     setup(world_prereqs_fire)) :-
    to_hddl(play_guitar, H),
    assertion(sub_string(H, _, _, _, ":method m_do_play_guitar")),
    assertion(sub_string(H, _, _, _, ":task (do_play_guitar)")).

% the prereq task appears as a subtask.
test(hddl_includes_prereq_subtask,
     setup(world_prereqs_fire)) :-
    to_hddl(play_guitar, H),
    assertion(sub_string(H, _, _, _, "(cut_fingernails)")),
    assertion(sub_string(H, _, _, _, "(play_guitar)")).

% the ordering between subtask 1 and 2 appears.
test(hddl_includes_ordering,
     setup(world_prereqs_fire)) :-
    to_hddl(play_guitar, H),
    assertion(sub_string(H, _, _, _, "(t1 t2)")).

:- end_tests(hddl).


% ============================================================
%  GROUP 3.  PDDL emitter
% ============================================================
:- begin_tests(pddl).

% the PDDL output is an :action for the trigger.
test(pddl_emits_action,
     setup(world_prereqs_fire)) :-
    to_pddl(play_guitar, P),
    assertion(sub_string(P, _, _, _, "(:action play_guitar")).

% the prereq appears as a (done ...) precondition.
test(pddl_prereq_in_precondition,
     setup(world_prereqs_fire)) :-
    to_pddl(play_guitar, P),
    assertion(sub_string(P, _, _, _, "(done cut_fingernails)")).

% the effect marks the trigger done.
test(pddl_effect_marks_done,
     setup(world_prereqs_fire)) :-
    to_pddl(play_guitar, P),
    assertion(sub_string(P, _, _, _, "(done play_guitar)")).

:- end_tests(pddl).


% ============================================================
%  GROUP 4.  Peleus emitter
% ============================================================
:- begin_tests(peleus).

% the Peleus output is a list headed by a peleus_method term.
test(peleus_emits_method,
     setup(world_prereqs_fire)) :-
    to_peleus(play_guitar, Terms),
    Terms = [Method|_],
    assertion(Method == peleus_method(do(play_guitar),
                                      [cut_fingernails, play_guitar])).

% each ordering becomes a peleus_ordering term.
test(peleus_emits_ordering,
     setup(world_prereqs_fire)) :-
    to_peleus(play_guitar, Terms),
    assertion(memberchk(peleus_ordering(before(cut_fingernails, play_guitar)),
                        Terms)).

% a quiet trigger: method with just the trigger, no orderings.
test(peleus_quiet_trigger,
     setup(world_quiet)) :-
    to_peleus(play_guitar, Terms),
    assertion(Terms == [peleus_method(do(play_guitar), [play_guitar])]).

:- end_tests(peleus).


% ============================================================
%  GROUP 5.  multi-prereq ordering (make_coffee has one prereq;
%  we synthesize a two-prereq trigger to exercise the chain)
% ============================================================
:- begin_tests(multi_prereq).

% a test-only trigger with two prereq rules at different
% priorities, to confirm the priority order becomes a chain.
% NOTE: these clauses are added to flp_rulebook:rule/4 at load
% time and persist for the SWI session. Harmless — they only
% add an extra trigger — but run this suite in its own swipl
% process if you want flp_rulebook's rulebase pristine.
flp_rulebook:rule(test_trigger, 10, prereq, task(first_task)).
flp_rulebook:rule(test_trigger, 20, prereq, task(second_task)).

test(two_prereqs_chained,
     setup(retractall(flp_rulebook:fact(_,_,_)))) :-
    plan_fragment(test_trigger, plan_fragment(_, Prereqs, Orderings)),
    assertion(Prereqs == [first_task, second_task]),
    % first_task before second_task (priority chain) AND
    % both before the trigger
    assertion(memberchk(before(first_task, second_task), Orderings)),
    assertion(memberchk(before(first_task, test_trigger), Orderings)),
    assertion(memberchk(before(second_task, test_trigger), Orderings)).

% the HDDL for it orders t1 < t2 < t3.
test(two_prereqs_hddl_ordering,
     setup(retractall(flp_rulebook:fact(_,_,_)))) :-
    to_hddl(test_trigger, H),
    assertion(sub_string(H, _, _, _, "(t1 t2)")),
    assertion(sub_string(H, _, _, _, "(t1 t3)")),
    assertion(sub_string(H, _, _, _, "(t2 t3)")).

:- end_tests(multi_prereq).
