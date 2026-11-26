#!/bin/sh
# Roadstorm Racer! - handling fixture validator test suite.
#
# Ownership: schemas/handling/** (PLAN.md M0.9 handling-contract slice, job
# b20cb153-94a8-4997-be00-1f8335daa1a0). Standard library only: no test
# framework dependency, matching docs/TECHNICAL_DESIGN.md ("Verification
# matrix"). A failing check exits nonzero.
#
# Usage: schemas/handling/run_tests.sh

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"

python3 "$HERE/tests/test_handling_fixtures.py" -v
