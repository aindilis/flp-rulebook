% ============================================================
%  flp_export.pl
%  Planner-export layer for the FLP rulebook engine.
%  Version 0.0.3
%
%  PURPOSE
%  -------
%  The rulebook engine decides, for an activity, what must be
%  done first (prereq outcomes) and in what order. That is
%  planning information. This module turns it into input for an
%  external planner.
%
%  THE CENTRAL DESIGN CHOICE: a neutral intermediate form.
%  Rather than emit one planner's format directly, the engine's
%  decisions are first collected into a single neutral term:
%
%      plan_fragment(Trigger, PrereqTasks, Orderings)
%
%  Every emitter (HDDL, PDDL, Peleus) is then a thin fold over
%  that term. This is the same principle the core uses for
%  outcomes: produce structured data once, let many consumers
%  read it. Adding a fourth target never touches the extraction.
%
%  WHAT IS BUILT IN 0.0.3
%   - plan_fragment/2          : extract the neutral form
%   - to_hddl/2                : full emitter (HTN-native; a
%                                prereq IS a method decomposition)
%   - to_pddl/2, to_peleus/2   : working emitters against the
%                                same neutral form
%
%  Depends on: flp_rulebook.pl (load it first).
% ============================================================

:- module(flp_export,
          [ plan_fragment/2     % plan_fragment(+Trigger,-Fragment)
          , to_hddl/2           % to_hddl(+Trigger,-HDDLString)
          , to_pddl/2           % to_pddl(+Trigger,-PDDLString)
          , to_peleus/2         % to_peleus(+Trigger,-PeleusTerms)
          , write_export/3      % write_export(+Fmt,+Trigger,+File)
          ]).

:- use_module(flp_rulebook).
:- use_module(library(lists)).


% ============================================================
%  SECTION 1.  THE NEUTRAL INTERMEDIATE FORM
% ============================================================
%  plan_fragment(Trigger, PrereqTasks, Orderings)
%    Trigger      : the activity name
%    PrereqTasks  : list of task names that must precede it
%    Orderings    : list of before(Earlier, Later) constraints
%
%  This is deliberately small. It captures exactly what a
%  rulebook knows about planning — "these tasks come first, in
%  this order" — and nothing a planner would need to be told
%  some other way (durations, costs, numeric fluents). If a
%  later version wants those, they extend this term; the
%  emitters extend with them. The form is the contract.

% plan_fragment(+Trigger, -Fragment)
plan_fragment(Trigger, plan_fragment(Trigger, PrereqTasks, Orderings)) :-
    consider(Trigger, Outcomes),
    findall(T, member(outcome(prereq, task(T), _), Outcomes), PrereqTasks),
    % every prereq must precede the trigger
    findall(before(T, Trigger), member(T, PrereqTasks), TrigOrderings),
    % prereqs are themselves ordered by their rule priority:
    % the outcome list is already priority-sorted, so a prereq
    % earlier in it precedes a later one.
    prereq_chain(PrereqTasks, ChainOrderings),
    append(TrigOrderings, ChainOrderings, Orderings).

% prereq_chain(+TasksInPriorityOrder, -Orderings)
%   Consecutive prereqs get a before/2 link, so a planner
%   respects the priority order the rulebook chose.
%   The cuts make this deterministic: the three clauses are
%   mutually exclusive, but [_] and [A,B|_] share the list
%   functor so first-argument indexing alone cannot tell them
%   apart, which would otherwise leave a stray choicepoint.
prereq_chain([], []) :- !.
prereq_chain([_], []) :- !.
prereq_chain([A,B|Rest], [before(A,B)|More]) :-
    prereq_chain([B|Rest], More).


% ============================================================
%  SECTION 2.  HDDL EMITTER  (the HTN-native target)
% ============================================================
%  WHY HDDL is the primary target:
%  a prereq is not a flat action — it is a decomposition. "To do
%  Trigger, first achieve these subtasks." That is precisely an
%  HTN method. HDDL (the HTN extension of PDDL, with real solver
%  support) can express it directly; flat PDDL cannot without
%  losing the structure. So HDDL gets the full, faithful emitter.
%
%  The emitted fragment is a single HTN METHOD: a decomposition
%  of an abstract task `do_Trigger` into its prereq subtasks
%  followed by the primitive `Trigger`, with ordering.

% to_hddl(+Trigger, -HDDLString)
to_hddl(Trigger, HDDL) :-
    plan_fragment(Trigger, plan_fragment(Trigger, Prereqs, Orderings)),
    hddl_method(Trigger, Prereqs, Orderings, HDDL).

hddl_method(Trigger, Prereqs, Orderings, HDDL) :-
    % the ordered subtask list: each prereq, then the trigger itself
    append(Prereqs, [Trigger], AllSubtasks),
    number_subtasks(AllSubtasks, 1, Numbered),
    subtask_lines(Numbered, SubtaskLines),
    ordering_lines(Orderings, Numbered, OrderLines),
    format(atom(HDDL),
"(:method m_do_~w
  :parameters ()
  :task (do_~w)
  :subtasks (and
~w  )
  :ordering (and
~w  )
)",
           [Trigger, Trigger, SubtaskLines, OrderLines]).

% number_subtasks(+Tasks,+StartN,-Pairs) : pair each task with a
% subtask label tN, used for both the subtask list and ordering.
number_subtasks([], _, []).
number_subtasks([T|Ts], N, [n(N,T)|Rest]) :-
    N1 is N + 1,
    number_subtasks(Ts, N1, Rest).

subtask_lines([], '').
subtask_lines([n(N,T)|Rest], Lines) :-
    format(atom(Line), "    (t~w (~w))~n", [N, T]),
    subtask_lines(Rest, More),
    atom_concat(Line, More, Lines).

% ordering_lines: turn before/2 terms into (tI < tJ) using the
% subtask numbering. A before/2 whose endpoints are not both in
% the numbered set is skipped (defensive).
ordering_lines([], _, '').
ordering_lines([before(A,B)|Rest], Numbered, Lines) :-
    ( member(n(I,A), Numbered), member(n(J,B), Numbered)
    -> format(atom(Line), "    (t~w t~w)~n", [I, J])
    ;  Line = ''
    ),
    ordering_lines(Rest, Numbered, More),
    atom_concat(Line, More, Lines).


% ============================================================
%  SECTION 3.  PDDL EMITTER  (flat-action target)
% ============================================================
%  PDDL cannot express decomposition, so the fragment is
%  flattened: the trigger becomes an action whose precondition
%  is that every prereq task is `done`. This LOSES the ordering
%  among prereqs (flat PDDL has no partial order inside one
%  action's precondition) — an honest limitation, noted here and
%  in DESIGN.md. PDDL is offered for tool compatibility, not as
%  the faithful target.

% to_pddl(+Trigger, -PDDLString)
to_pddl(Trigger, PDDL) :-
    plan_fragment(Trigger, plan_fragment(Trigger, Prereqs, _Orderings)),
    precondition_lines(Prereqs, PreLines),
    format(atom(PDDL),
"(:action ~w
  :parameters ()
  :precondition (and
~w  )
  :effect (done ~w)
)",
           [Trigger, PreLines, Trigger]).

precondition_lines([], '').
precondition_lines([T|Ts], Lines) :-
    format(atom(Line), "    (done ~w)~n", [T]),
    precondition_lines(Ts, More),
    atom_concat(Line, More, Lines).


% ============================================================
%  SECTION 4.  PELEUS EMITTER  (Prolog-term target)
% ============================================================
%  Peleus consumes Prolog terms directly, so this emitter does
%  not produce a string — it produces a list of terms that can
%  be asserted or written to a Peleus knowledge file. The shape
%  mirrors the HDDL method: a decomposition of do(Trigger).
%
%  This is the target most immediately usable on ai2, since
%  Peleus is installed there. It is the LEAST portable, which is
%  exactly why it is an emitter over the neutral form and not
%  the form itself.

% to_peleus(+Trigger, -Terms)
%   Terms is a list:
%     peleus_method(do(Trigger), OrderedSubtaskList)
%     peleus_ordering(before(A,B))   for each ordering
to_peleus(Trigger, Terms) :-
    plan_fragment(Trigger, plan_fragment(Trigger, Prereqs, Orderings)),
    append(Prereqs, [Trigger], Subtasks),
    findall(peleus_ordering(O), member(O, Orderings), OrderTerms),
    Terms = [ peleus_method(do(Trigger), Subtasks) | OrderTerms ].


% ============================================================
%  SECTION 5.  WRITING EXPORTS TO FILE
% ============================================================
%  write_export(+Format, +Trigger, +File)
%    Format ∈ hddl | pddl | peleus

write_export(hddl, Trigger, File) :-
    to_hddl(Trigger, HDDL),
    setup_call_cleanup(open(File, write, S),
                       write(S, HDDL),
                       close(S)).
write_export(pddl, Trigger, File) :-
    to_pddl(Trigger, PDDL),
    setup_call_cleanup(open(File, write, S),
                       write(S, PDDL),
                       close(S)).
write_export(peleus, Trigger, File) :-
    to_peleus(Trigger, Terms),
    setup_call_cleanup(open(File, write, S),
                       forall(member(T, Terms),
                              ( print_term(T, [output(S), fullstop(true),
                                                nl(true)]) )),
                       close(S)).
