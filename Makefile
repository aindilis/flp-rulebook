# Makefile for flp-rulebook
#
# Convenience targets. The real loading mechanism is load.pl;
# this just wraps common actions.
#
#   make test    — run all test suites
#   make check   — same as make test
#   make release — run the tests, then build the .deb (into ~/debs/public)
#   make demo    — run the morning-routine worked example
#   make repl    — start swipl with everything loaded
#   make clean   — remove generated Python bytecode caches

SWIPL ?= swipl

.PHONY: test check release test-core test-activities test-export test-planner \
        demo repl clean help

help:
	@echo "flp-rulebook make targets:"
	@echo "  make test    - run all test suites"
	@echo "  make check   - same as make test"
	@echo "  make release - run the tests, then build the .deb (debrelease)"
	@echo "  make demo    - run the morning-routine example"
	@echo "  make repl    - start swipl with everything loaded"
	@echo "  make clean   - remove Python __pycache__ directories"

# --- tests --------------------------------------------------
test: test-core test-activities test-export test-planner

check: test

# --- release: tests first, then the Debian package, filed by debrelease
#     in ~/debs/public or ~/debs/private according to the repo label ---
release: check
	debrelease

test-core:
	$(SWIPL) -g run_tests -t halt flp_rulebook.pl test_flp_rulebook.pl

test-activities:
	$(SWIPL) -g run_tests -t halt \
		flp_rulebook.pl flp_activities.pl test_flp_activities.pl

test-export:
	$(SWIPL) -g run_tests -t halt \
		flp_rulebook.pl flp_export.pl test_flp_export.pl

test-planner:
	$(SWIPL) -g run_tests -t halt \
		flp_rulebook.pl flp_export.pl flp_planner.pl test_flp_planner.pl

# --- demos --------------------------------------------------
demo:
	$(SWIPL) -g "[flp(morning_domain)], morning_demo" -t halt load.pl

repl:
	$(SWIPL) load.pl

# --- housekeeping -------------------------------------------
clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	@echo "removed __pycache__ directories"
