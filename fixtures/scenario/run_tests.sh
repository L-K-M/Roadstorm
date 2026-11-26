#!/bin/sh
# Roadstorm Racer! - scenario/reference contract test runner.
#
# Ownership: fixtures/scenario/** together with schemas/scenario/** (PLAN.md
# M0.9, job 847d8664-1028-4233-a67c-39f1465b4964). Runs the standard-library
# unittest suite for the scenario contract validator, then the validator
# itself over the shipped positive and negative fixtures. No third-party
# packages, no network, no writes outside a temporary directory.
#
# Usage:
#   fixtures/scenario/run_tests.sh            run the suite and the validator
#   fixtures/scenario/run_tests.sh -v         verbose (one line per test)
#   fixtures/scenario/run_tests.sh <pattern>  run tests matching <pattern>
#
# <pattern> is passed to unittest as a -k filter, not as a positional start
# directory (same convention as fixtures/intent/run_tests.sh).
#
# Exit codes: 0 = all tests passed and all fixtures behave as contracted;
# 1 = a test failed or a fixture deviated; 2 = the suite could not run.
#
# Original project code under the Unlicense.

set -u

FIXTURES_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$FIXTURES_DIR/../.." && pwd)"

PYTHON="${PYTHON:-}"
if [ -z "$PYTHON" ]; then
	for candidate in python3 python; do
		if command -v "$candidate" >/dev/null 2>&1; then
			PYTHON="$candidate"
			break
		fi
	done
fi
if [ -z "$PYTHON" ]; then
	printf '[error] no python3 interpreter found (set PYTHON=/path/to/python3)\n' >&2
	exit 2
fi

# Translate the documented <pattern> form into a unittest -k filter.
PATTERN=""
if [ "$#" -gt 0 ]; then
	case "$1" in
	-*)
		;;
	*)
		PATTERN="$1"
		shift
		;;
	esac
fi

# The suite imports validate_scenario_contract from the fixtures directory and
# reads the schemas by absolute path; run from the repository root so relative
# paths behave the same everywhere.
cd "$REPO_ROOT" || exit 2

printf 'scenario/reference contract tests (python: %s)\n' "$("$PYTHON" --version 2>&1)"
printf 'fixtures directory: %s\n' "$FIXTURES_DIR"
printf ''

if [ -n "$PATTERN" ]; then
	set -- "$PYTHON" -m unittest discover -s "$FIXTURES_DIR/tests" -t "$FIXTURES_DIR" -k "$PATTERN" "$@"
else
	set -- "$PYTHON" -m unittest discover -s "$FIXTURES_DIR/tests" -t "$FIXTURES_DIR" "$@"
fi
"$@"
_rc=$?

if [ "$_rc" -eq 0 ]; then
	printf '\n[ok]   scenario/reference contract tests: PASS\n'
	printf 'validator over shipped fixtures:\n'
	"$PYTHON" "$FIXTURES_DIR/validate_scenario_contract.py"
	_validator_rc=$?
	if [ "$_validator_rc" -ne 0 ]; then
		printf '\n[fail] scenario/reference contract validator: FAIL (exit %s)\n' "$_validator_rc" >&2
		exit "$_validator_rc"
	fi
	printf '\n[ok]   scenario/reference contract validator: PASS\n'
else
	printf '\n[fail] scenario/reference contract tests: FAIL (exit %s)\n' "$_rc" >&2
fi
exit "$_rc"
