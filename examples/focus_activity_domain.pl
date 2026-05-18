% ============================================================
%  examples/focus_activity_domain.pl
%  A WORKED, TEACHING DOMAIN for the activities layer (v0.0.2).
%
%  Read top to bottom. Companion to examples/morning_domain.pl,
%  which covers discrete rules; this one covers ACTIVITIES —
%  processes with a beginning, a middle, and an end.
%
%  To run it:
%      ?- [flp_rulebook].
%      ?- [flp_activities].
%      ?- ['examples/focus_activity_domain.pl'].
%      ?- focus_demo.
% ============================================================
%
%  THE SCENARIO
%  ------------
%  A "focus block" — a stretch of deliberate, undistracted work.
%  Unlike making coffee (a discrete action), a focus block has
%  duration, and that changes what preparation means:
%
%    BEFORE it begins : silence the phone, so it can't interrupt.
%    DURING it runs   : after a while, a break is worth taking —
%                       this can only be judged with reference to
%                       how long the block has been going.
%    AFTER it ends    : log what got done, while it is fresh.
%
%  A discrete rule cannot express the DURING phase at all: there
%  is no "moment of doing" for it to attach to. That is exactly
%  why activities need their own three-rulebook structure.
% ============================================================

% Establish the flp_root path alias from this file's own
% location, so the engine loads however this example is consulted.
:- ( user:file_search_path(flp_root, _)
   -> true
   ;  prolog_load_context(directory, ExDir),
      file_directory_name(ExDir, RepoDir),
      asserta(user:file_search_path(flp_root, RepoDir))
   ).
:- use_module(flp_root(flp_rulebook)).
:- use_module(flp_root(flp_activities)).

:- multifile flp_activities:before_rule/4.
:- multifile flp_activities:during_rule/4.
:- multifile flp_activities:after_rule/4.
:- multifile flp_rulebook:staleness/2.


% ============================================================
%  STEP 1.  STALENESS FOR THE FACTS THIS DOMAIN USES
% ============================================================
%  WHY `live` for phone_silenced:
%  "the phone is silenced" is undone constantly — a call comes
%  in, the phone restarts, someone toggles it. So it is only
%  trustworthy if confirmed TODAY. A focus block starting
%  tomorrow cannot lean on today's confirmation.

flp_rulebook:staleness(phone_silenced, live).


% ============================================================
%  STEP 2.  THE BEFORE-RULEBOOK
% ============================================================
%  WHY `advise` and not `prereq`:
%  a focus block with an un-silenced phone is still a focus
%  block — degraded, not impossible. `advise` surfaces the
%  suggestion without making it a hard gate. Compare the table
%  saw in the core domain, which IS a `block`: that is a genuine
%  safety stop, and the contrast is the whole point of having
%  four outcome classes.

flp_activities:before_rule(focus_block, 10, advise, task(silence_phone)) :-
    \+ flp_rulebook:fresh(phone_silenced, true).

%  A second before-rule, higher priority, showing ordering:
%  closing chat apps is also set-up, and we want it mentioned
%  before the phone tip (priority 5 < 10).
flp_activities:before_rule(focus_block, 5, advise, task(close_chat_apps)).


% ============================================================
%  STEP 3.  THE DURING-RULEBOOK
% ============================================================
%  WHY this rule consults activity_elapsed/2:
%  this is the planner-native idea that has no Inform analogue.
%  A during-rule fires at a CHECK-IN, and its condition can ask
%  how long the activity has run. Here: once the block has been
%  going at least a day's granularity, suggest a break.
%
%  HONEST LIMITATION: v0.0.2 time granularity is whole days
%  (Julian Day Numbers). A real focus block is measured in
%  minutes. So `D >= 1` here is a stand-in. The fix — sub-day
%  timestamps — is noted in DESIGN.md as a known rough edge.
%  The STRUCTURE (during-rule reads elapsed time) is what this
%  domain is teaching; the unit is a v0.0.3 concern.

flp_activities:during_rule(focus_block, 10, advise,
                           note('been at this a while — a short break helps')) :-
    flp_activities:activity_elapsed(focus_block, D),
    D >= 1.


% ============================================================
%  STEP 4.  THE AFTER-RULEBOOK
% ============================================================
%  WHY this rule has no condition:
%  logging the session should happen every time, so the rule is
%  unconditional — it always fires. A rule with no body is the
%  natural way to say "always".

flp_activities:after_rule(focus_block, 10, advise, task(log_session)).


% ============================================================
%  STEP 5.  THE GUIDED DEMO
% ============================================================
%  focus_demo/0 walks one whole activity lifecycle and prints
%  what each phase's rulebook decides, with the reasoning.

focus_demo :-
    % fresh world: no phone_silenced fact, clock at 2026-05-17.
    % retractall below also clears any activity-running fact, so
    % no separate end_activity cleanup is needed.
    retractall(flp_rulebook:today(_,_,_)),
    assertz(flp_rulebook:today(2026,5,17)),
    retractall(flp_rulebook:fact(_,_,_)),

    nl,
    writeln('=================================================='),
    writeln(' FLP ACTIVITIES -- a focus block, worked example'),
    writeln('=================================================='),

    writeln('\n--- phase 1: BEGIN -------------------------------'),
    writeln('expectation: phone is not silenced and chat apps are'),
    writeln('open, so TWO advice outcomes, close_chat_apps (pri 5)'),
    writeln('listed before silence_phone (pri 10).'),
    begin(focus_block),

    writeln('\n--- phase 2: CHECK-IN (same day) -----------------'),
    writeln('expectation: the block started today, so elapsed is 0;'),
    writeln('the break rule needs D >= 1, so nothing fires yet.'),
    check_in(focus_block),

    writeln('\n--- phase 2 again: CHECK-IN (clock advanced) -----'),
    writeln('expectation: advance the clock 2 days; now elapsed is'),
    writeln('2, the break rule fires.'),
    retractall(flp_rulebook:today(_,_,_)),
    assertz(flp_rulebook:today(2026,5,19)),
    check_in(focus_block),

    writeln('\n--- phase 3: CONCLUDE ----------------------------'),
    writeln('expectation: the log_session rule is unconditional,'),
    writeln('so it always fires; concluding also ends the activity.'),
    conclude(focus_block),

    writeln('\n--- after conclude -------------------------------'),
    ( activity_running(focus_block)
    -> writeln('focus_block still running -- UNEXPECTED.')
    ;  writeln('focus_block is no longer running -- as expected.') ),

    writeln('\n--- activity rulebase self-check -----------------'),
    verify_activities(Problems),
    ( Problems == []
    -> writeln('clean.')
    ;  ( writeln('reported:'),
         forall(member(P, Problems), format('  ~w~n', [P])) ) ),
    nl.

% ------------------------------------------------------------
%  SUGGESTED EXERCISES
%
%  1. Silence the phone today, then re-run begin:
%       ?- now_jdn(T), assert_observation(phone_silenced, true, T).
%       ?- begin(focus_block).
%     Only close_chat_apps should remain.
%
%  2. Add an after_rule with a `block` outcome, then run
%     verify_activities/1 — it should report block_outside_before,
%     because you cannot block an activity that has already ended.
%
%  3. Add a during_rule for a different activity of your own
%     (say `cooking`) that warns when elapsed time gets large.
% ------------------------------------------------------------
