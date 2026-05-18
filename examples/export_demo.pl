% ============================================================
%  examples/export_demo.pl
%  A WORKED demonstration of the planner-export layer (v0.0.3).
%
%  To run it:
%      ?- [flp_rulebook].
%      ?- [flp_export].
%      ?- ['examples/export_demo.pl'].
%      ?- export_demo.
% ============================================================
%
%  WHAT THIS SHOWS
%  ---------------
%  The same rulebook decision — "before play_guitar, cut your
%  fingernails" — rendered three ways:
%
%    1. the NEUTRAL FORM the engine extracts internally
%    2. HDDL    : the prereq as an HTN method decomposition
%    3. PDDL    : the prereq flattened into an action precondition
%    4. Peleus  : the prereq as Prolog terms for ai2
%
%  Reading the three side by side is the point: HDDL keeps the
%  decomposition structure, PDDL loses the prereq ordering, and
%  Peleus is the same structure as HDDL but as native terms.
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

export_demo :-
    % a world where play_guitar's prereq fires (nails long stale)
    retractall(flp_rulebook:today(_,_,_)),
    assertz(flp_rulebook:today(2026,5,30)),
    retractall(flp_rulebook:fact(_,_,_)),
    gregorian_to_jdn(2026,5,1,J),
    assertz(flp_rulebook:fact(fingernails_cut, true, J)),

    nl,
    writeln('=================================================='),
    writeln(' FLP EXPORT -- one rulebook decision, three forms'),
    writeln('=================================================='),

    writeln('\n--- 1. the neutral intermediate form -------------'),
    writeln('what the engine extracts before any emitter runs:'),
    plan_fragment(play_guitar, Fragment),
    format("  ~p~n", [Fragment]),

    writeln('\n--- 2. HDDL (HTN-native, the faithful target) ----'),
    writeln('the prereq becomes a method decomposition; the'),
    writeln('ordering t1 < t2 is preserved:'),
    to_hddl(play_guitar, HDDL),
    nl, writeln(HDDL), nl,

    writeln('\n--- 3. PDDL (flat actions, ordering is lost) -----'),
    writeln('the prereq becomes a (done ...) precondition; with'),
    writeln('one prereq nothing is lost here, but with several'),
    writeln('PDDL cannot order them -- see DESIGN.md:'),
    to_pddl(play_guitar, PDDL),
    nl, writeln(PDDL), nl,

    writeln('\n--- 4. Peleus (Prolog terms, usable on ai2) ------'),
    writeln('the same decomposition as HDDL, as native terms:'),
    to_peleus(play_guitar, Terms),
    forall(member(T, Terms), format("  ~p~n", [T])),

    writeln('\n--- writing to files -----------------------------'),
    write_export(hddl,   play_guitar, '/tmp/play_guitar.hddl'),
    write_export(pddl,   play_guitar, '/tmp/play_guitar.pddl'),
    write_export(peleus, play_guitar, '/tmp/play_guitar.pl'),
    writeln('wrote /tmp/play_guitar.{hddl,pddl,pl}'),
    nl.

% ------------------------------------------------------------
%  SUGGESTED EXERCISES
%
%  1. Define a trigger of your own with two or three prereq
%     rules at different priorities, then run to_hddl/2 on it
%     and read the :ordering block -- the priority order of the
%     rules becomes the subtask ordering.
%
%  2. Run to_pddl/2 on that same multi-prereq trigger and notice
%     the precondition is an unordered (and ...) -- this is the
%     structural information PDDL cannot carry.
%
%  3. Once Peleus is integrated on ai2, load the generated
%     /tmp/play_guitar.pl and try planning do(play_guitar).
% ------------------------------------------------------------
