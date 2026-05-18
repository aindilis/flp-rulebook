% ============================================================
%  load.pl — one-step loader for flp-rulebook
%
%  Usage:
%      swipl load.pl
%
%  This consults the engine and all optional layers, and sets up
%  a file_search_path alias `flp` so that example domains can be
%  loaded by a stable name regardless of the working directory:
%
%      ?- [flp(morning_domain)].
%      ?- morning_demo.
%
%  Loading this file does NOT run the planner or the tests; it
%  just makes everything available. See the Makefile for
%  `make test` and `make demo` convenience targets.
% ============================================================

% Resolve the repository root from this file's own location, so
% the loader works no matter where swipl was started.
:- prolog_load_context(directory, Dir),
   asserta(user:file_search_path(flp_root, Dir)),
   atom_concat(Dir, '/examples', ExDir),
   asserta(user:file_search_path(flp, ExDir)).

% --- the engine and its optional layers --------------------
:- use_module(flp_root(flp_rulebook)).
:- use_module(flp_root(flp_activities)).
:- use_module(flp_root(flp_export)).
:- use_module(flp_root(flp_planner)).

:- initialization(
     ( format("~n flp-rulebook loaded.~n"),
       format(" Engine, activities, export, and planner layers are ready.~n"),
       format(" Try:  ?- [flp(morning_domain)].  then  ?- morning_demo.~n~n")
     )).
