% ============================================================
%  examples/morning_domain.pl
%  A WORKED, TEACHING DOMAIN for the FLP rulebook engine.
%
%  Read this file top to bottom. It is meant to be read as much
%  as run. Every section has a "WHY" comment explaining the
%  design choice, not just a "WHAT".
%
%  To run it:
%      ?- [flp_rulebook].
%      ?- ['examples/morning_domain.pl'].
%      ?- morning_demo.
%
%  morning_demo/0 walks the whole domain and prints what the
%  engine decides, step by step.
% ============================================================
%
%  THE SCENARIO
%  ------------
%  It is the morning. Over the next hour you intend to:
%     1. make coffee
%     2. play guitar for a while
%     3. do a focused work block
%  None of these is hard to *start*. But each has preparation
%  that, skipped, leads to friction later: grounds with nowhere
%  to go, sore fingertips from un-cut nails, a work block
%  derailed by a buzzing phone.
%
%  A rulebook is the right tool because the preparation is
%  CONDITIONAL (only cut nails if they need it) and the planner's
%  knowledge of the world is PARTIAL (it cannot see your nails;
%  it only remembers when you last told it).
% ============================================================

% This file ADDS rules and facts to the engine already loaded.
% In a real FLP deployment these would live in their own module;
% for teaching we keep everything in one readable place.

% A domain file depends on the engine: importing it makes the
% engine's exported authoring helpers (months/2, days/2, etc.)
% visible in this file's rule bodies.
% Establish the flp_root path alias from this file's own
% location (examples/ sits one level below the repo root), so
% the engine loads correctly however this example is consulted.
:- ( user:file_search_path(flp_root, _)
   -> true
   ;  prolog_load_context(directory, ExDir),
      file_directory_name(ExDir, RepoDir),
      asserta(user:file_search_path(flp_root, RepoDir))
   ).
:- use_module(flp_root(flp_rulebook)).

:- multifile flp_rulebook:rule/4.
:- multifile flp_rulebook:maintenance/3.
:- multifile flp_rulebook:staleness/2.


% ============================================================
%  STEP 1.  THE WORLD
% ============================================================
%  WHY a setup predicate instead of bare facts:
%  the engine's freshness logic depends on "today". A teaching
%  file that hard-codes facts would silently rot as the real
%  date moved past it. So we pin BOTH today and the facts
%  together, relative to each other, in one predicate you call.
%
%  The story the numbers tell:
%   - nails last cut 9 days ago  -> STALE (decay model is 7 days)
%   - trash checked today at 0.88 -> fresh, and over the warn line
%   - phone-silenced last confirmed yesterday -> STALE (live model)
%   - air filter changed 100 days ago -> maintenance not yet due

install_morning_world :-
    % pin "today"
    retractall(flp_rulebook:today(_,_,_)),
    assertz(flp_rulebook:today(2026, 5, 17)),
    % clear and rebuild the world
    retractall(flp_rulebook:fact(_,_,_)),
    add_fact(nails_trimmed, true,        2026, 5,  8),
    add_fact(bin_fullness,  0.88,        2026, 5, 17),
    add_fact(phone_silenced,  true,        2026, 5, 16),
    add_fact(air_filter,      changed,     2026, 2,  6).

% helper: assert a fact stamped with a Gregorian verification date
add_fact(Name, Value, Y, M, D) :-
    gregorian_to_jdn(Y, M, D, JDN),
    assertz(flp_rulebook:fact(Name, Value, JDN)).


% ============================================================
%  STEP 2.  STALENESS MODELS
% ============================================================
%  WHY each fact gets its own model:
%  "nails are cut" stays true for about a week of normal wear,
%  so decay(7) — the engine trusts it for 7 days then asks again.
%  "phone is silenced" is the kind of thing that gets undone
%  constantly (a call, a restart), so `live` — only trust it if
%  confirmed today. Choosing the model honestly is most of the
%  craft of authoring a domain.

flp_rulebook:staleness(nails_trimmed, decay(7)).
flp_rulebook:staleness(bin_fullness,  live).
flp_rulebook:staleness(phone_silenced,  live).
% air_filter needs no model: maintenance goals use since/2
% directly, not freshness, so it can stay sticky (the default).


% ============================================================
%  STEP 3.  THE RULES
% ============================================================

% --- making coffee -----------------------------------------
%  WHY two rules, not one with an if-then:
%  separate rules at separate thresholds keep each rule simple
%  and independently testable, and let them carry DIFFERENT
%  outcomes. Below 0.80 nothing fires. Past 0.80 you get a
%  warning. Past 0.95 the warning is replaced in importance by
%  an actual prereq task. Each rule states only its own case.

flp_rulebook:rule(brew_coffee, 20, warn,
                  note('trash is getting full - grounds may not fit')) :-
    flp_rulebook:value(bin_fullness, F), F > 0.80.

flp_rulebook:rule(brew_coffee, 10, prereq, task(empty_bin)) :-
    flp_rulebook:value(bin_fullness, F), F > 0.95.

% --- playing guitar ----------------------------------------
%  WHY `\+ fresh(...)` rather than `stale(...)`:
%  the rule should fire both when nails are KNOWN long (stale)
%  and when the engine has no record at all. `\+ fresh` covers
%  both; `stale` would miss the no-record case. Subtle, and
%  worth getting right.

flp_rulebook:rule(practice_guitar, 10, prereq, task(trim_nails)) :-
    \+ flp_rulebook:fresh(nails_trimmed, true).

% --- a focused work block ----------------------------------
%  WHY `advise`, not `prereq`:
%  silencing the phone genuinely helps, but a work block with a
%  buzzing phone is still a work block. `advise` says "suggested,
%  skippable" — the engine will surface it without nagging it to
%  the top as a blocking step.

flp_rulebook:rule(focus_block, 30, advise, task(silence_phone)) :-
    \+ flp_rulebook:fresh(phone_silenced, true).


% ============================================================
%  STEP 4.  A MAINTENANCE GOAL
% ============================================================
%  WHY this is not a rule:
%  a rule fires when you are ABOUT TO DO an activity. Changing an
%  air filter is not triggered by an activity at all — it is
%  triggered purely by elapsed time. That is a maintenance goal:
%  "re-establish this fact every N days; when overdue, spawn the
%  task." due_maintenance/1 finds these independently of consider/2.

flp_rulebook:maintenance(air_filter, Days, task(change_air_filter)) :-
    months(3, Days).        % every ~90 days


% ============================================================
%  STEP 5.  THE GUIDED DEMO
% ============================================================
%  Calling morning_demo/0 installs the world and walks the
%  domain, printing what the engine concludes and a short note
%  on WHY, so you can check the engine against your own reasoning.

morning_demo :-
    install_morning_world,
    nl,
    writeln('=================================================='),
    writeln(' FLP RULEBOOK -- morning routine, worked example'),
    writeln('=================================================='),

    demo_step(brew_coffee,
              'trash is at 0.88: over the 0.80 warn line but under\n   the 0.95 prereq line, so expect ONE outcome, a warning.'),

    demo_step(practice_guitar,
              'nails were cut 9 days ago; decay model is 7 days, so\n   the fact is stale -> expect a trim_nails prereq.'),

    demo_step(focus_block,
              'phone_silenced is `live` and was confirmed yesterday,\n   so it is stale today -> expect a silence_phone ADVICE.'),

    nl,
    writeln('-- maintenance check (time-triggered, not activity) --'),
    due_maintenance(Due),
    ( Due == []
    -> writeln('   nothing overdue.')
    ;  forall(member(due(F,Over,task(T)), Due),
              format('   ~w is overdue by ~w days -> do: ~w~n',
                     [F, Over, T])) ),
    format('   (air filter changed 2026-02-06; ~~90-day cycle.)~n'),

    nl,
    writeln('-- rulebase self-check --'),
    verify_rulebase(Problems),
    ( Problems == []
    -> writeln('   clean.')
    ;  ( writeln('   reported:'),
         forall(member(P, Problems), format('     ~w~n', [P])),
         writeln('   (unanchored_prereq here is EXPECTED -- those'),
         writeln('    tasks are expanded elsewhere in FLP.)') ) ),
    nl.

% demo_step(+Trigger, +WhyText) — run one activity and explain it.
demo_step(Trigger, Why) :-
    nl,
    format('ACTIVITY: ~w~n', [Trigger]),
    format('  expectation: ~w~n', [Why]),
    write('  engine says:'), nl,
    consider(Trigger).

% ------------------------------------------------------------
%  SUGGESTED EXERCISES (try these at the REPL after morning_demo)
%
%  1. Re-confirm the nails as cut TODAY, then re-run practice_guitar:
%       ?- now_jdn(T), assert_observation(nails_trimmed, true, T).
%       ?- consider(practice_guitar).
%     The prereq should vanish.
%
%  2. Push the trash past 0.95 and re-run brew_coffee:
%       ?- now_jdn(T), assert_observation(bin_fullness, 0.97, T).
%       ?- consider(brew_coffee).
%     Now BOTH a prereq and a warning should appear, prereq first.
%
%  3. Add a rule of your own for `brew_coffee` that, with priority
%     5, blocks if a `kettle_working` fact is not fresh. Re-run
%     verify_rulebase/1 and notice it stays clean.
% ------------------------------------------------------------
