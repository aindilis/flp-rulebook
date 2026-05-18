% ============================================================
%  examples/planner_demo.pl
%  A WORKED demonstration of the PyHOP planner round-trip (0.0.4).
%
%  To run it:
%      ?- [flp_rulebook], [flp_export], [flp_planner].
%      ?- ['examples/planner_demo.pl'].
%      ?- planner_demo.
%
%  REQUIRES python3 with pyhop importable for the live round-trip
%  (pip install pyhop, or vendor pyhop.py on PYTHONPATH). Without
%  it, the demo still prints the generated Python program — only
%  the actual run step is skipped.
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
:- use_module(flp_root(flp_export)).
:- use_module(flp_root(flp_planner)).

planner_demo :-
    % a world where play_guitar's prereq fires
    retractall(flp_rulebook:today(_,_,_)),
    assertz(flp_rulebook:today(2026,5,30)),
    retractall(flp_rulebook:fact(_,_,_)),
    gregorian_to_jdn(2026,5,1,J),
    assertz(flp_rulebook:fact(fingernails_cut, true, J)),

    nl,
    writeln('=================================================='),
    writeln(' FLP PLANNER -- PyHOP round-trip, worked example'),
    writeln('=================================================='),

    writeln('\n--- step 1: the rulebook decision ----------------'),
    writeln('play_guitar needs cut_fingernails first (nails stale).'),
    plan_fragment(play_guitar, Fragment),
    format("  neutral form: ~p~n", [Fragment]),

    writeln('\n--- step 2: the generated PyHOP program ----------'),
    writeln('the neutral form rendered as a PyHOP program:'),
    pyhop_program(play_guitar, Source),
    nl, writeln(Source),

    writeln('--- step 3: run PyHOP and parse the plan back ----'),
    ( catch(run_planner(pyhop, play_guitar, Plan), Err, (Err = caught))
    -> ( Err == caught
       -> writeln('  (could not run PyHOP -- is python3 + pyhop'),
          writeln('   installed? the program above is still valid.)')
       ;  format("  plan returned: ~p~n", [Plan]),
          writeln('  i.e. cut your fingernails, then play guitar.') )
    ;  writeln('  run_planner failed.') ),
    nl.

% ------------------------------------------------------------
%  SUGGESTED EXERCISES
%
%  1. Define a trigger with two prereq rules at different
%     priorities, run pyhop_program/2 on it, and read the
%     generated method -- the subtask list is the priority order.
%
%  2. Run the round-trip on that trigger and confirm the plan
%     PyHOP returns matches the rule priority order.
%
%  3. Look at flp_planner.pl Section 3: sketch what a Lilotane
%     backend's four hooks would be. backend_emit could call
%     to_hddl/2 unchanged.
% ------------------------------------------------------------
