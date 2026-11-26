#!/bin/sh
# Roadstorm Racer! - asset manifest validator test runner.
#
# Ownership: tools/asset_manifest/**. Runs the standard-library unittest suite
# for the manifest validator. No third-party packages, no network, no writes
# outside a temporary directory.
#
# Usage:
#   tools/asset_manifest/run_tests.sh            run the suite
#   tools/asset_manifest/run_tests.sh -v         verbose (one line per test)
#   tools/asset_manifest/run_tests.sh <pattern>  run tests matching <pattern>
#
# <pattern> is passed to unittest as a -k filter, not as a positional start
# directory: a positional argument would be treated as an importable package
# path ("Start directory is not importable"), which made the documented form
# fail. Any other flags are passed through to unittest unchanged.
#
# Exit codes: 0 = all tests passed, 1 = a test failed, 2 = the suite could not
# run (same convention as tools/ci/ci.sh and tools/toolchain/verify.sh).
#
# Original project code under the Unlicense.

set -u

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TOOLS_DIR/../.." && pwd)"

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

# Translate the documented <pattern> form into a unittest -k filter. A first
# argument that is not a flag is the pattern; everything else passes through.
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

# The suite imports manifest_validator from this directory and reads the
# shipped assets/manifest.json; run it from the repository root so relative
# paths behave the same everywhere.
cd "$REPO_ROOT" || exit 2

printf 'asset manifest validator tests (python: %s)\n' "$("$PYTHON" --version 2>&1)"
printf 'tool directory: %s\n' "$TOOLS_DIR"
printf ''

if [ -n "$PATTERN" ]; then
	set -- "$PYTHON" -m unittest discover -s "$TOOLS_DIR/tests" -t "$TOOLS_DIR" -k "$PATTERN" "$@"
else
	set -- "$PYTHON" -m unittest discover -s "$TOOLS_DIR/tests" -t "$TOOLS_DIR" "$@"
fi
"$@"
_rc=$?

if [ "$_rc" -eq 0 ]; then
	printf '\n[ok]   asset manifest validator tests: PASS\n'
else
	printf '\n[fail] asset manifest validator tests: FAIL (exit %s)\n' "$_rc" >&2
fi
exit "$_rc"
