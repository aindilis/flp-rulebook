% ============================================================
%  test_flp_activities.pl
%  Test suite for the activities layer (v0.0.2).
%
%  Run from SWI-Prolog:
%      ?- [flp_rulebook], [flp_activities], [test_flp_activities].
%      ?- run_tests.
%
%  These tests define their own activity rules (the engine ships
%  none) and install their own deterministic world, so they do
%  not depend on any sample fixture.
% ============================================================

:- use_module(library(plunit)).
:- use_module(flp_rulebook).
:- use_module(flp_activities).

% --- test-only activity rules ------------------------------
% before a focus_block: silence the phone if not already silent.
flp_activities:before_rule(focus_block, 10, advise, task(silence_phone)) :-
    \+ flp_rulebook:fresh(phone_silenced, true).

% during a focus_block: past 0 days running, suggest a break.
% (Day granularity is coarse; see DESIGN.md note on sub-day time.)
flp_activities:during_rule(focus_block, 10, advise, note('consider a short break')) :-
    flp_activities:activity_elapsed(focus_block, D), D >= 0.

% after a focus_block: always log what was done.
flp_activities:after_rule(focus_block, 10, advise, task(log_session)).

% an intentionally bad rule for verification tests:
flp_activities:after_rule(bad_activity, 10, block, note('cannot block an ended activity')).

% --- helpers -----------------------------------------------
set_today(Y,M,D) :-
    retractall(flp_rulebook:today(_,_,_)),
    assertz(flp_rulebook:today(Y,M,D)).

clear_world :-
    retractall(flp_rulebook:fact(_,_,_)).


% ============================================================
%  GROUP 1.  Activity lifecycle
% ============================================================
:- begin_tests(lifecycle).

test(start_then_running,
     setup(( set_today(2026,5,17), clear_world ))) :-
    start_activity(focus_block),
    assertion(activity_running(focus_block)).

test(not_running_before_start,
     setup(( set_today(2026,5,17), clear_world ))) :-
    assertion(\+ activity_running(focus_block)).

test(end_clears_running,
     setup(( set_today(2026,5,17), clear_world ))) :-
    start_activity(focus_block),
    end_activity(focus_block),
    assertion(\+ activity_running(focus_block)).

test(double_start_throws,
     setup(( set_today(2026,5,17), clear_world )),
     throws(error(activity_already_running(focus_block), _))) :-
    start_activity(focus_block),
    start_activity(focus_block).

test(end_when_not_running_throws,
     setup(( set_today(2026,5,17), clear_world )),
     throws(error(activity_not_running(focus_block), _))) :-
    end_activity(focus_block).

test(elapsed_counts_days,
     setup(( set_today(2026,5,17), clear_world ))) :-
    start_activity(focus_block),
    set_today(2026,5,20),               % advance the clock 3 days
    activity_elapsed(focus_block, Days),
    assertion(Days =:= 3).

:- end_tests(lifecycle).


% ============================================================
%  GROUP 2.  The three rulebooks
% ============================================================
:- begin_tests(rulebooks).

% before: with no phone_silenced fact, the advise rule fires.
test(before_fires_advice,
     setup(( set_today(2026,5,17), clear_world ))) :-
    consider_activity(before, focus_block, Outcomes),
    assertion(Outcomes == [outcome(advise, task(silence_phone), 10)]).

% before: with phone freshly silenced, nothing fires.
test(before_quiet_when_silenced,
     setup(( set_today(2026,5,17), clear_world,
             assertz(flp_rulebook:fact(phone_silenced, true, 0)) ))) :-
    % phone_silenced has no staleness model -> sticky -> fresh
    consider_activity(before, focus_block, Outcomes),
    assertion(Outcomes == []).

% during: only meaningful while the activity runs.
test(during_fires_while_running,
     setup(( set_today(2026,5,17), clear_world ))) :-
    start_activity(focus_block),
    consider_activity(during, focus_block, Outcomes),
    assertion(Outcomes == [outcome(advise, note('consider a short break'), 10)]).

% after: the log rule always fires.
test(after_fires_log,
     setup(( set_today(2026,5,17), clear_world ))) :-
    consider_activity(after, focus_block, Outcomes),
    assertion(Outcomes == [outcome(advise, task(log_session), 10)]).

:- end_tests(rulebooks).


% ============================================================
%  GROUP 3.  check_in / begin / conclude wiring
% ============================================================
:- begin_tests(wiring).

% check_in on a non-running activity does not throw, just reports.
test(check_in_not_running_is_safe,
     setup(( set_today(2026,5,17), clear_world ))) :-
    catch(check_in(focus_block), E, (E = none)),
    assertion(var(E) ; E == none).

% begin starts the activity as a side effect.
test(begin_starts_activity,
     setup(( set_today(2026,5,17), clear_world ))) :-
    begin(focus_block),
    assertion(activity_running(focus_block)).

% conclude ends a running activity as a side effect.
test(conclude_ends_activity,
     setup(( set_today(2026,5,17), clear_world ))) :-
    start_activity(focus_block),
    conclude(focus_block),
    assertion(\+ activity_running(focus_block)).

% conclude on a not-running activity still prints, does not throw.
test(conclude_not_running_is_safe,
     setup(( set_today(2026,5,17), clear_world ))) :-
    catch(conclude(focus_block), _, fail).

:- end_tests(wiring).


% ============================================================
%  GROUP 4.  Activity verification
% ============================================================
:- begin_tests(activity_verification).

% the deliberately-bad after_rule with a block outcome is caught.
test(catches_block_outside_before) :-
    verify_activities(Problems),
    assertion(memberchk(block_outside_before(after, bad_activity), Problems)).

% the well-formed focus_block rules raise no block_outside_before.
test(focus_block_has_no_block_problem) :-
    verify_activities(Problems),
    assertion(\+ memberchk(block_outside_before(_, focus_block), Problems)).

:- end_tests(activity_verification).
