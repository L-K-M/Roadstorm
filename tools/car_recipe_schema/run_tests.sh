#!/bin/sh
# Roadstorm Racer! - car handling source-recipe checker test suite.
#
# Ownership: tools/car_recipe_schema/** and fixtures/car_recipe/** (M0.2
# versioned handling-source contract job). Standard library only: no network,
# engine or third-party dependency.
#
# Usage:
#   sh tools/car_recipe_schema/run_tests.sh
#   CAR_RECIPE_WORK_DIR=/existing/dir sh tools/car_recipe_schema/run_tests.sh
#
# Writes nothing into the repository. Logs go to a uniquely mktemp-reserved
# private directory: under an existing caller-supplied CAR_RECIPE_WORK_DIR when
# given, otherwise under ${TMPDIR:-/tmp}. The caller's base is never created,
# moved or deleted; only its unique child is added and left as evidence.
# Printed output is bounded and a failing check exits nonzero.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${CAR_RECIPE_WORK_DIR:-}" ]; then
    WORK_BASE=$CAR_RECIPE_WORK_DIR
else
    WORK_BASE=${TMPDIR:-/tmp}
fi

if [ ! -d "$WORK_BASE" ]; then
    echo "run_tests.sh: output base is not an existing directory: $WORK_BASE" >&2
    exit 2
fi

OUT=$(mktemp -d "$WORK_BASE/car-recipe-tests.XXXXXX") || exit 2
LOG="$OUT/tests.log"

python3 "$HERE/tests/test_car_recipe_schema.py" -v >"$LOG" 2>&1
STATUS=$?

echo "private log: $LOG"
tail -n "${CAR_RECIPE_TAIL_LINES:-20}" "$LOG"
exit "$STATUS"
