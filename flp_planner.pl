% ============================================================
%  flp_planner.pl
%  Planner-backend layer for the FLP rulebook engine.
%  Version 0.0.4
%
%  PURPOSE
%  -------
%  flp_export.pl turns a rulebook decision into a neutral
%  plan_fragment and emits planner-input formats. This module
%  goes one step further: it actually RUNS a planner and parses
%  the resulting plan back into Prolog terms — the round-trip.
%
%  THE BACKEND INTERFACE
%  ---------------------
%  A planner backend is described by three multifile hooks:
%
%    planner_backend(Name)
%        — declares that Name is an available backend.
%
%    backend_emit(Name, Fragment, File)
%        — write planner input for Fragment to File.
%
%    backend_invoke(Name, InFile, RawOutput)
%        — run the planner on InFile, unify RawOutput with its
%          stdout as a string.
%
%    backend_parse(Name, RawOutput, Plan)
%        — parse RawOutput into Plan, a list of step/1 terms.
%
%  PyHOP is the first concrete backend (Section 2). Lilotane is
%  a documented stub (Section 3) showing the interface accepts a
%  beefier HDDL planner with no change to the generic core.
%
%  Depends on: flp_rulebook.pl, flp_export.pl.
% ============================================================

:- module(flp_planner,
          [ run_planner/3       % run_planner(+Backend,+Trigger,-Plan)
          , available_backends/1% available_backends(-Names)
          , planner_backend/1   % planner_backend(?Name)
          , pyhop_program/2     % pyhop_program(+Trigger,-PythonSource)
          ]).

:- use_module(flp_rulebook).
:- use_module(flp_export).
:- use_module(library(lists)).
:- use_module(library(process)).
:- use_module(library(readutil)).

% The backend hooks are multifile so new backends can be added
% from other files without editing this module.
:- multifile planner_backend/1.
:- multifile backend_emit/3.
:- multifile backend_invoke/3.
:- multifile backend_parse/3.
:- discontiguous planner_backend/1.
:- discontiguous backend_emit/3.
:- discontiguous backend_invoke/3.
:- discontiguous backend_parse/3.


% ============================================================
%  SECTION 1.  THE GENERIC RUNNER
% ============================================================
%  run_planner(+Backend, +Trigger, -Plan)
%    The whole round-trip: extract the neutral fragment, emit it
%    in the backend's format, invoke the planner, parse the plan.
%    Plan is a list of step(TaskName) terms in execution order.
%
%  The runner is completely backend-agnostic — it only calls the
%  four hooks. Adding a planner never touches this predicate.

run_planner(Backend, Trigger, Plan) :-
    ( planner_backend(Backend)
    -> true
    ;  throw(error(unknown_planner_backend(Backend), _))
    ),
    plan_fragment(Trigger, Fragment),
    tmp_file_stream(text, InFile, S0), close(S0),
    setup_call_cleanup(
        true,
        ( backend_emit(Backend, Fragment, InFile),
          backend_invoke(Backend, InFile, Raw),
          backend_parse(Backend, Raw, Plan) ),
        catch(delete_file(InFile), _, true)
    ).

% available_backends(-Names) — every declared backend.
available_backends(Names) :-
    findall(N, planner_backend(N), Names0),
    sort(Names0, Names).


% ============================================================
%  SECTION 2.  THE PyHOP BACKEND
% ============================================================
%  PyHOP has NO input file format — operators, methods and state
%  are ordinary Python. So the "emit" step writes a complete,
%  self-contained Python PROGRAM that imports pyhop, declares the
%  decomposition, runs the planner, and prints the plan in a
%  fixed line format this module can parse back.
%
%  ASSUMPTION: `pyhop` is importable by the `python3` on PATH
%  (e.g. pip-installed, or vendored next to the run directory).
%  If not, backend_invoke fails loudly with the Python error.

planner_backend(pyhop).

% --- the emitter -------------------------------------------
backend_emit(pyhop, Fragment, File) :-
    pyhop_program_from_fragment(Fragment, Source),
    setup_call_cleanup(open(File, write, S),
                       write(S, Source),
                       close(S)).

% pyhop_program(+Trigger, -PythonSource)
%   Public convenience: get the Python program for a trigger
%   without running anything (useful for inspection / tests).
pyhop_program(Trigger, Source) :-
    plan_fragment(Trigger, Fragment),
    pyhop_program_from_fragment(Fragment, Source).

% pyhop_program_from_fragment(+plan_fragment(...), -Source)
%   The heart of the PyHOP backend. Maps the neutral form to a
%   PyHOP program:
%     - each prereq task  -> an operator that records it done
%     - the trigger       -> an operator (the primitive act)
%     - the trigger's task-> a method decomposing into
%                            [prereq1, ..., prereqN, trigger]
%   The method's subtask order IS the fragment's total order.
pyhop_program_from_fragment(plan_fragment(Trigger, Prereqs, _Ord),
                            Source) :-
    append(Prereqs, [Trigger], AllTasks),
    maplist(operator_def, AllTasks, OpDefs),
    atomic_list_concat(OpDefs, OpBlock),
    operator_names(AllTasks, OpNames),
    method_subtasks(AllTasks, SubtaskList),
    format(atom(Source),
"#!/usr/bin/env python3
# Auto-generated by flp_planner.pl — PyHOP program for ~w
import pyhop

# --- operators: one per task, each records itself 'done' -----
~w
pyhop.declare_operators(~w)

# --- method: decompose do_~w into its ordered subtasks -------
def m_~w(state):
    return [~w]
pyhop.declare_methods('do_~w', m_~w)

# --- initial state: nothing done yet -------------------------
# pyhop.State requires a name argument (canonical PyHOP 2.0).
state = pyhop.State('flp_state')
state.done = {}

# --- run and print the plan in a parseable form --------------
# This PyHOP's entry point is plan(state, tasks, operators,
# methods, verbose) — operators and methods are passed
# explicitly (unlike the older module-global pyhop() form).
result = pyhop.plan(state, [('do_~w',)],
                    pyhop.get_operators(), pyhop.get_methods(),
                    verbose=0)
if result == False:
    print('FLP-PLAN-FAIL')
else:
    for step in result:
        print('FLP-STEP', step[0])
    print('FLP-PLAN-END')
",
           [ Trigger,
             OpBlock, OpNames,
             Trigger, Trigger, SubtaskList,
             Trigger, Trigger,
             Trigger ]).

% operator_def(+Task, -PythonDef)
%   An operator that marks Task done in state.done and returns
%   the state (PyHOP requires the operator to return the state).
operator_def(Task, Def) :-
    format(atom(Def),
"def ~w(state):
    state.done['~w'] = True
    return state
",
           [Task, Task]).

% operator_names(+Tasks, -CommaSeparatedNames)
operator_names(Tasks, Names) :-
    atomic_list_concat(Tasks, ', ', Names).

% method_subtasks(+Tasks, -PyhopSubtaskListBody)
%   Render [t1, t2, ...] as PyHOP 1-tuples: ('t1',), ('t2',), ...
method_subtasks(Tasks, Body) :-
    maplist(as_tuple, Tasks, Tuples),
    atomic_list_concat(Tuples, ', ', Body).

as_tuple(Task, Tuple) :-
    format(atom(Tuple), "('~w',)", [Task]).

% --- the invoker -------------------------------------------
%  Run `python3 <File>` and capture stdout. A non-zero exit or a
%  Python traceback surfaces as a thrown error with the stderr.
%
%  PYTHONPATH is set to the repo's vendor/ directory so the
%  vendored single-file pyhop.py is importable regardless of
%  conda env or system site-packages. This makes the round-trip
%  self-contained: no `pip install` required.
backend_invoke(pyhop, File, Raw) :-
    pyhop_vendor_dir(Vendor),
    ( getenv('PYTHONPATH', Existing)
    -> atomic_list_concat([Vendor, Existing], ':', PyPath)
    ;  PyPath = Vendor
    ),
    setup_call_cleanup(
        process_create(path(python3), [File],
                       [ stdout(pipe(Out)),
                         stderr(pipe(Err)),
                         environment(['PYTHONPATH'=PyPath]),
                         process(PID) ]),
        ( read_string(Out, _, Raw),
          read_string(Err, _, ErrStr),
          process_wait(PID, Status) ),
        ( close(Out), close(Err) )
    ),
    ( Status == exit(0)
    -> true
    ;  throw(error(planner_failed(pyhop, Status, ErrStr), _))
    ).

% pyhop_vendor_dir(-Dir) — absolute path to the vendor/ directory,
% located beside this module's source file.
pyhop_vendor_dir(Dir) :-
    module_property(flp_planner, file(SelfFile)),
    file_directory_name(SelfFile, RepoDir),
    atomic_list_concat([RepoDir, vendor], '/', Dir).

% --- the parser --------------------------------------------
%  PyHOP stdout looks like:
%      FLP-STEP cut_fingernails
%      FLP-STEP play_guitar
%      FLP-PLAN-END
%  or the single line FLP-PLAN-FAIL. Parse to a list of step/1.
backend_parse(pyhop, Raw, Plan) :-
    split_string(Raw, "\n", "\r ", Lines),
    ( memberchk("FLP-PLAN-FAIL", Lines)
    -> Plan = plan_failed
    ;  findall(step(Task),
               ( member(Line, Lines),
                 string_concat("FLP-STEP ", TaskStr, Line),
                 atom_string(Task, TaskStr) ),
               Plan)
    ).


% ============================================================
%  SECTION 3.  LILOTANE BACKEND  (documented stub)
% ============================================================
%  Lilotane is a SAT-based HDDL planner — a far stronger engine
%  than PyHOP. It is a STUB here, not because the interface
%  cannot hold it, but to show that it can: a Lilotane backend
%  is exactly the same four hooks.
%
%  - backend_emit(lilotane, ...) would reuse flp_export's
%    to_hddl/2 (Lilotane reads HDDL natively — no new emitter).
%  - backend_invoke(lilotane, ...) would shell out to the
%    `lilotane` binary, or to `planutils run lilotane ...`
%    (Lilotane, being file-based HDDL, fits planutils cleanly —
%    unlike PyHOP, which has no file format).
%  - backend_parse(lilotane, ...) would parse Lilotane's plan
%    output (its own line format).
%
%  Deliberately not implemented in 0.0.4: it needs the binary
%  installed to test honestly, and PyHOP is enough to validate
%  the round-trip and the neutral form. Enabling Lilotane later
%  is additive — this module's generic runner does not change.

% planner_backend(lilotane).        % <- uncomment when implemented
