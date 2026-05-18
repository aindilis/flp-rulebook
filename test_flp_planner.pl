% ============================================================
%  test_flp_planner.pl
%  Test suite for the planner-backend layer (v0.0.4).
%
%  Run from SWI-Prolog:
%      ?- [flp_rulebook], [flp_export], [flp_planner],
%         [test_flp_planner].
%      ?- run_tests.
%
%  TWO KINDS OF TEST:
%   - The `emitter` and `backend_iface` groups are pure Prolog
%     and always run — they check the generated Python text and
%     the generic backend interface without invoking anything.
%   - The `roundtrip` group actually runs PyHOP. It is GATED:
%     if `python3` with an importable `pyhop` is not found, the
%     group is skipped with a message rather than failing. This
%     keeps the suite green on machines without PyHOP installed.
% ============================================================

:- use_module(library(plunit)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(flp_rulebook).
:- use_module(flp_export).
:- use_module(flp_planner).

% --- helpers -----------------------------------------------
set_today(Y,M,D) :-
    retractall(flp_rulebook:today(_,_,_)),
    assertz(flp_rulebook:today(Y,M,D)).

% world where play_guitar's prereq fires.
world_guitar_prereq :-
    retractall(flp_rulebook:fact(_,_,_)),
    set_today(2026,5,30),
    gregorian_to_jdn(2026,5,1,J),
    assertz(flp_rulebook:fact(fingernails_cut, true, J)).

% Probe: is python3 with an importable pyhop available?
% Used to gate the roundtrip group. Checks the VENDORED pyhop
% (vendor/ beside the modules), matching how flp_planner invokes
% it — so the gate and the real run agree.
pyhop_available :-
    catch(
        ( vendor_dir(Vendor),
          process_create(path(python3), ['-c', 'import pyhop'],
                          [ stdout(null), stderr(null),
                            environment(['PYTHONPATH'=Vendor]),
                            process(PID) ]),
          process_wait(PID, exit(0)) ),
        _,
        fail).

% vendor_dir(-Dir) — vendor/ beside the test file.
vendor_dir(Dir) :-
    ( source_file(pyhop_available, SelfFile)
    -> true
    ;  SelfFile = 'test_flp_planner.pl'
    ),
    file_directory_name(SelfFile, RepoDir),
    atomic_list_concat([RepoDir, vendor], '/', Dir).


% ============================================================
%  GROUP 1.  The PyHOP emitter (pure Prolog, always runs)
% ============================================================
:- begin_tests(emitter).

% has_sub(+String, +Sub) — deterministic substring check.
% sub_string/5 is nondeterministic (a substring may occur many
% times); once/1 commits to the first match so tests do not
% succeed-with-choicepoint.
has_sub(String, Sub) :-
    once(sub_string(String, _, _, _, Sub)).

% the generated program imports pyhop.
test(emits_import,
     setup(world_guitar_prereq)) :-
    pyhop_program(play_guitar, Src),
    assertion(has_sub(Src, "import pyhop")).

% there is an operator def for the prereq and the trigger.
test(emits_operators,
     setup(world_guitar_prereq)) :-
    pyhop_program(play_guitar, Src),
    assertion(has_sub(Src, "def cut_fingernails(state):")),
    assertion(has_sub(Src, "def play_guitar(state):")).

% operators are declared to pyhop.
test(emits_declare_operators,
     setup(world_guitar_prereq)) :-
    pyhop_program(play_guitar, Src),
    assertion(has_sub(Src, "declare_operators(cut_fingernails, play_guitar)")).

% the method decomposes do_play_guitar in prereq-then-trigger order.
test(emits_method_in_order,
     setup(world_guitar_prereq)) :-
    pyhop_program(play_guitar, Src),
    assertion(has_sub(Src, "return [('cut_fingernails',), ('play_guitar',)]")),
    assertion(has_sub(Src, "declare_methods('do_play_guitar', m_play_guitar)")).

% the program runs the planner on the do_ task.
test(emits_planner_call,
     setup(world_guitar_prereq)) :-
    pyhop_program(play_guitar, Src),
    assertion(has_sub(Src, "pyhop.plan(state, [('do_play_guitar',)]")).

% the program prints steps in the parseable FLP-STEP format.
test(emits_parseable_output,
     setup(world_guitar_prereq)) :-
    pyhop_program(play_guitar, Src),
    assertion(has_sub(Src, "FLP-STEP")),
    assertion(has_sub(Src, "FLP-PLAN-END")).

:- end_tests(emitter).


% ============================================================
%  GROUP 2.  The generic backend interface (pure Prolog)
% ============================================================
:- begin_tests(backend_iface).

% pyhop is a declared backend.
test(pyhop_is_a_backend) :-
    assertion(planner_backend(pyhop)).

% available_backends lists it.
test(available_lists_pyhop) :-
    available_backends(Names),
    assertion(memberchk(pyhop, Names)).

% an unknown backend throws a clear error.
test(unknown_backend_throws,
     [ setup(world_guitar_prereq),
       throws(error(unknown_planner_backend(no_such_planner), _)) ]) :-
    run_planner(no_such_planner, play_guitar, _).

% the pyhop parser turns FLP-STEP lines into step/1 terms.
test(parser_reads_steps) :-
    flp_planner:backend_parse(pyhop,
        "FLP-STEP cut_fingernails\nFLP-STEP play_guitar\nFLP-PLAN-END",
        Plan),
    assertion(Plan == [step(cut_fingernails), step(play_guitar)]).

% the pyhop parser recognises a planning failure.
test(parser_reads_failure) :-
    flp_planner:backend_parse(pyhop, "FLP-PLAN-FAIL", Plan),
    assertion(Plan == plan_failed).

:- end_tests(backend_iface).


% ============================================================
%  GROUP 3.  The PyHOP round-trip (GATED on pyhop_available)
% ============================================================
%  Every test here is conditioned on pyhop_available/0. When
%  PyHOP is not installed the condition fails and plunit reports
%  the test as skipped (a "blocked" test), not as a failure.

:- begin_tests(roundtrip,
               [ condition(pyhop_available) ]).

% the full round-trip yields the expected ordered plan.
test(roundtrip_guitar,
     setup(world_guitar_prereq)) :-
    run_planner(pyhop, play_guitar, Plan),
    assertion(Plan == [step(cut_fingernails), step(play_guitar)]).

% a quiet trigger (no prereq) plans to just itself.
test(roundtrip_quiet,
     setup(( retractall(flp_rulebook:fact(_,_,_)),
             set_today(2026,5,17),
             gregorian_to_jdn(2026,5,16,J),
             assertz(flp_rulebook:fact(fingernails_cut, true, J)) ))) :-
    run_planner(pyhop, play_guitar, Plan),
    assertion(Plan == [step(play_guitar)]).

:- end_tests(roundtrip).
