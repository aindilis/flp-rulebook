% ============================================================
%  flp_activities.pl
%  Activities layer for the FLP rulebook engine.
%  Version 0.0.2
%
%  An ACTIVITY is a process with duration — a focus block, a
%  guitar practice session, cooking dinner — as opposed to the
%  discrete actions handled by flp_rulebook.pl's rule/4.
%
%  Following Inform 7, an activity has THREE rulebooks:
%    before_rule/4  — set-up, evaluated as the activity begins
%    during_rule/4  — evaluated at a check-in WHILE it runs
%    after_rule/4   — clean-up, evaluated as it ends
%
%  Design choices (see DESIGN.md):
%   - Inform's "for-rules" (replace default behavior) have no
%     referent in a planner: FLP does not PERFORM your activity.
%     They are replaced by `during_rule`s, which fire on a
%     check-in and can consult how long the activity has run.
%     This is planner-native and has no Inform analogue.
%   - Decomposition of an activity into sub-activities is HTN
%     and is deferred to the planner-integration work.
%   - An activity's running state is tracked through a clean
%     lifecycle (start_activity/1, end_activity/1) but is stored
%     underneath as ordinary fact/3 entries, so it reuses the
%     core's staleness and observation machinery unchanged.
%
%  Depends on: flp_rulebook.pl (load it first).
% ============================================================

:- module(flp_activities,
          [ start_activity/1     % start_activity(+Activity)
          , end_activity/1       % end_activity(+Activity)
          , activity_running/1   % activity_running(?Activity)
          , activity_elapsed/2   % activity_elapsed(+Activity,-Days)
          , begin/1              % begin(+Activity)   — print before
          , check_in/1           % check_in(+Activity) — print during
          , conclude/1           % conclude(+Activity) — print after
          , consider_activity/3  % (+Phase,+Activity,-Outcomes)
          , verify_activities/1  % verify_activities(-Problems)
          ]).

:- use_module(flp_rulebook).
:- use_module(library(lists)).

% The three activity rulebooks. multifile so FLP domain files
% (and the example domains) contribute their own activity rules.
:- multifile before_rule/4.
:- multifile during_rule/4.
:- multifile after_rule/4.
:- discontiguous before_rule/4.
:- discontiguous during_rule/4.
:- discontiguous after_rule/4.


% ============================================================
%  SECTION 1.  ACTIVITY LIFECYCLE
% ============================================================
%  Running state is just a fact in the core's world:
%      fact(activity(Name), running, StartedJDN)
%  Storing it this way means it flows through assert_observation/3
%  and could even carry a staleness model if a future version
%  wanted activities to "time out". For now activities are
%  explicitly ended.

% start_activity(+Activity)
%   Record that the activity is now running, stamped today.
%   Fails (does not double-start) if it is already running.
start_activity(Activity) :-
    ( activity_running(Activity)
    -> throw(error(activity_already_running(Activity), _))
    ;  now_jdn(Now),
       assert_observation(activity(Activity), running, Now)
    ).

% end_activity(+Activity)
%   Clear the running state. Fails loudly if it was not running,
%   so a mismatched begin/conclude pair cannot pass silently.
end_activity(Activity) :-
    ( activity_running(Activity)
    -> retract_activity_fact(Activity)
    ;  throw(error(activity_not_running(Activity), _))
    ).

% activity_running(?Activity) — currently-running activities.
activity_running(Activity) :-
    flp_rulebook:fact(activity(Activity), running, _).

% activity_elapsed(+Activity, -Days)
%   Whole days since the activity started. The during-rulebook's
%   reason for existing: a during_rule can branch on this.
activity_elapsed(Activity, Days) :-
    flp_rulebook:fact(activity(Activity), running, Started),
    now_jdn(Now),
    Days is Now - Started.

% retract the running fact (kept separate so the module boundary
% to the core's dynamic predicate is in exactly one place)
retract_activity_fact(Activity) :-
    retractall(flp_rulebook:fact(activity(Activity), running, _)).


% ============================================================
%  SECTION 2.  EVALUATING THE THREE RULEBOOKS
% ============================================================
%  Each phase reuses the core's evaluate_rulebook/3, just with a
%  different rulebook predicate. The outcome list and its four
%  classes (block/prereq/advise/warn) are exactly as in the core,
%  so every downstream consumer already understands the result.

% consider_activity(+Phase, +Activity, -Outcomes)
%   Phase ∈ before | during | after
consider_activity(before, Activity, Outcomes) :-
    evaluate_rulebook(flp_activities:before_rule, Activity, Outcomes).
consider_activity(during, Activity, Outcomes) :-
    evaluate_rulebook(flp_activities:during_rule, Activity, Outcomes).
consider_activity(after, Activity, Outcomes) :-
    evaluate_rulebook(flp_activities:after_rule, Activity, Outcomes).


% ============================================================
%  SECTION 3.  THE LIFECYCLE-PLUS-PRESENTATION ENTRY POINTS
% ============================================================
%  begin/1, check_in/1, conclude/1 are what FLP (or you, at the
%  REPL) actually call. They tie the lifecycle to the rulebooks:
%   - begin/1    starts the activity AND prints before-outcomes
%   - check_in/1 prints during-outcomes for a running activity
%   - conclude/1 prints after-outcomes AND ends the activity

begin(Activity) :-
    consider_activity(before, Activity, Outcomes),
    format("~n>> BEGIN ~w~n", [Activity]),
    print_outcomes(Outcomes),
    start_activity(Activity).

check_in(Activity) :-
    ( activity_running(Activity)
    -> activity_elapsed(Activity, Days),
       consider_activity(during, Activity, Outcomes),
       format("~n.. CHECK-IN ~w (running ~w day(s))~n", [Activity, Days]),
       print_outcomes(Outcomes)
    ;  format("~n.. ~w is not running — nothing to check in on.~n",
              [Activity]) ).

conclude(Activity) :-
    consider_activity(after, Activity, Outcomes),
    format("~n<< CONCLUDE ~w~n", [Activity]),
    print_outcomes(Outcomes),
    ( activity_running(Activity)
    -> end_activity(Activity)
    ;  format("   (note: ~w was not running)~n", [Activity]) ).

print_outcomes([]) :-
    format("   (nothing for this phase)~n").
print_outcomes([O|Os]) :-
    forall(member(X, [O|Os]), show_activity_outcome(X)).

show_activity_outcome(outcome(block,  C, _)) :- format("   [BLOCK]   ~p~n", [C]).
show_activity_outcome(outcome(prereq, C, _)) :- format("   [DO 1ST]  ~p~n", [C]).
show_activity_outcome(outcome(advise, C, _)) :- format("   [SUGGEST] ~p~n", [C]).
show_activity_outcome(outcome(warn,   C, _)) :- format("   [HEADS-UP]~p~n", [C]).


% ============================================================
%  SECTION 4.  VERIFICATION
% ============================================================
%  Like the core's verify_rulebase/1, but for activity rulebooks.
%  Structural — inspects clauses via clause/2, never runs a
%  rule's condition (the lesson recorded in DESIGN.md).

verify_activities(Problems) :-
    findall(P, activity_problem(P), P0),
    sort(P0, Problems).

% A during-rule or after-rule that is a `block` is almost
% certainly an authoring mistake: you cannot "block" an activity
% that has already begun or ended. Blocks belong in before-rules.
activity_problem(block_outside_before(during, Activity)) :-
    clause(during_rule(Activity, _, block, _), _).
activity_problem(block_outside_before(after, Activity)) :-
    clause(after_rule(Activity, _, block, _), _).

% Two rules in the same phase+activity sharing a priority.
% Compared by clause reference, as in the core (see flp_rulebook.pl):
% a computed consequence must not make one clause look like two.
activity_problem(duplicate_priority(Phase, Activity, Pri)) :-
    phase_rule(Phase, RuleHead),
    G1 =.. [RuleHead, Activity, Pri, _, _], clause(G1, _, R1),
    G2 =.. [RuleHead, Activity, Pri, _, _], clause(G2, _, R2),
    R1 @< R2.

phase_rule(before, before_rule).
phase_rule(during, during_rule).
phase_rule(after,  after_rule).
