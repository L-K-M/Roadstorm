#!/bin/sh
# Roadstorm Racer! - bounded isolated runner for the practice-flow lab.
#
# Ownership: tools/practice_flow_lab/**.
#
# Stages a private copy of the project (project.godot, src/, scenes/, this
# tool and the engine pin), imports it headless, then runs:
#   * the normal boot -> menu -> practice flow (exit 0 expected);
#   * the deliberate failure proof (`--expect-failure`, nonzero exit and a
#     recorded CHECKS_FAILED greater than zero).
#
# Every engine invocation is bounded by `timeout -k 5 <seconds>`, runs with a
# private HOME/TMPDIR/XDG cache set, and is checked for engine error lines even
# when its exit status is zero. The live checkout's .godot cache is never
# written.
#
# Usage:
#   tools/practice_flow_lab/run_practice_flow_lab.sh [--project DIR]
#       [--godot BIN] [--timeout SECONDS] [--log FILE] [--keep-scratch]
#
# Exit codes: 0 = every case behaved as expected, 1 = a case failed,
# 2 = unsafe inputs or an unusable engine.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
GODOT_BIN=${ROADSTORM_GODOT:-}
TIMEOUT=${ROADSTORM_TEST_TIMEOUT:-120}
LOG_FILE=""
KEEP_SCRATCH=0
STAGE=""
RUN_CACHE=""

usage() {
	cat <<'EOF'
Usage: run_practice_flow_lab.sh [--project DIR] [--godot BIN]
                               [--timeout SECONDS] [--log FILE] [--keep-scratch]

Stages a private copy, imports it, and runs the headless practice-flow lab
pass case plus the --expect-failure proof.
EOF
}

die_usage() {
	echo "$1" >&2
	usage >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--project)
		[ $# -ge 2 ] || die_usage "--project needs a value"
		PROJECT_DIR=$2; shift 2 ;;
	--project=*)
		PROJECT_DIR=${1#*=}; shift ;;
	--godot)
		[ $# -ge 2 ] || die_usage "--godot needs a value"
		GODOT_BIN=$2; shift 2 ;;
	--godot=*)
		GODOT_BIN=${1#*=}; shift ;;
	--timeout)
		[ $# -ge 2 ] || die_usage "--timeout needs a value"
		TIMEOUT=$2; shift 2 ;;
	--timeout=*)
		TIMEOUT=${1#*=}; shift ;;
	--log)
		[ $# -ge 2 ] || die_usage "--log needs a value"
		LOG_FILE=$2; shift 2 ;;
	--log=*)
		LOG_FILE=${1#*=}; shift ;;
	--keep-scratch)
		KEEP_SCRATCH=1; shift ;;
	-h | --help)
		usage; exit 0 ;;
	*)
		die_usage "unknown option: $1" ;;
	esac
done

case "$TIMEOUT" in
'' | *[!0-9]*) die_usage "--timeout must be a positive integer" ;;
esac
[ "$TIMEOUT" -gt 0 ] || die_usage "--timeout must be a positive integer"

[ -f "$PROJECT_DIR/project.godot" ] || {
	echo "[practice-flow-lab] not a project root: $PROJECT_DIR" >&2
	exit 2
}
for required in src scenes tools/practice_flow_lab; do
	[ -e "$PROJECT_DIR/$required" ] || {
		echo "[practice-flow-lab] missing staged path: $PROJECT_DIR/$required" >&2
		exit 2
	}
done
if [ -z "$GODOT_BIN" ]; then
	GODOT_BIN="$PROJECT_DIR/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
fi
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "[practice-flow-lab] Godot binary not found: $GODOT_BIN" >&2
	exit 2
fi

PINNED_VERSION_STRING="4.7.2.stable.official.ed1daf0bf"
if [ -r "$PROJECT_DIR/tools/toolchain/pin/engine.txt" ]; then
	recorded=$(sed -n 's/^version_string=//p' "$PROJECT_DIR/tools/toolchain/pin/engine.txt" | head -n 1)
	[ -n "$recorded" ] && PINNED_VERSION_STRING="$recorded"
fi

ERROR_RE='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

cleanup() {
	[ "$KEEP_SCRATCH" -eq 1 ] && [ -n "$STAGE" ] && [ -d "$STAGE" ] && {
		echo "[practice-flow-lab] scratch kept at $STAGE"
		return
	}
	[ -n "$RUN_CACHE" ] && rm -rf "$RUN_CACHE"
	[ -n "$STAGE" ] && rm -rf "$STAGE"
}
trap cleanup EXIT HUP INT TERM

SCRATCH_PARENT="$PROJECT_DIR/work/agents"
mkdir -p "$SCRATCH_PARENT" || exit 2
STAGE=$(mktemp -d "$SCRATCH_PARENT/practice-flow-stage.XXXXXX" 2>/dev/null) || {
	echo "[practice-flow-lab] cannot create staging directory" >&2
	exit 2
}
RUN_CACHE=$(mktemp -d "$SCRATCH_PARENT/practice-flow-cache.XXXXXX" 2>/dev/null) || {
	echo "[practice-flow-lab] cannot create private cache directory" >&2
	exit 2
}

echo "[practice-flow-lab] staging isolated project copy in $STAGE"
cp "$PROJECT_DIR/project.godot" "$STAGE/" || exit 2
cp -R "$PROJECT_DIR/src" "$STAGE/src" || exit 2
cp -R "$PROJECT_DIR/scenes" "$STAGE/scenes" || exit 2
mkdir -p "$STAGE/tools" || exit 2
cp -R "$PROJECT_DIR/tools/practice_flow_lab" "$STAGE/tools/practice_flow_lab" || exit 2
if [ -f "$PROJECT_DIR/tools/toolchain/pin/engine.txt" ]; then
	mkdir -p "$STAGE/tools/toolchain/pin" || exit 2
	cp "$PROJECT_DIR/tools/toolchain/pin/engine.txt" "$STAGE/tools/toolchain/pin/" || exit 2
fi
find "$STAGE" -type d -name .godot -prune -exec rm -rf {} + 2>/dev/null

run_engine() {
	# run_engine <log-file> <args...>
	_log=$1
	shift
	env \
		PATH="$PATH" \
		HOME="$RUN_CACHE/home" \
		TMPDIR="$RUN_CACHE/tmp" \
		XDG_CACHE_HOME="$RUN_CACHE/cache" \
		XDG_CONFIG_HOME="$RUN_CACHE/config" \
		XDG_DATA_HOME="$RUN_CACHE/data" \
		timeout -k 5 "$TIMEOUT" "$GODOT_BIN" "$@"
}

mkdir -p "$RUN_CACHE/home" "$RUN_CACHE/tmp" "$RUN_CACHE/cache" \
	"$RUN_CACHE/config" "$RUN_CACHE/data"

VERSION_LOG="$RUN_CACHE/version.log"
: >"$VERSION_LOG"
run_engine "$VERSION_LOG" --version >>"$VERSION_LOG" 2>&1
version_status=$?
actual_version=$(tail -n 1 "$VERSION_LOG")
if [ "$version_status" -ne 0 ] || [ -z "$actual_version" ]; then
	echo "[practice-flow-lab] engine --version failed or timed out" >&2
	tail -n 20 "$VERSION_LOG" >&2
	exit 2
fi
case "$actual_version" in
*"$PINNED_VERSION_STRING"*) ;;
*)
	echo "[practice-flow-lab] engine is not the pinned $PINNED_VERSION_STRING (got: $actual_version)" >&2
	exit 2
;;
esac
echo "[practice-flow-lab] engine $actual_version"

IMPORT_LOG="$RUN_CACHE/import.log"
: >"$IMPORT_LOG"
echo "[practice-flow-lab] importing staged project"
run_engine "$IMPORT_LOG" --headless --path "$STAGE" --import >>"$IMPORT_LOG" 2>&1
import_status=$?
if [ "$import_status" -ne 0 ]; then
	echo "[practice-flow-lab] headless import failed (status $import_status)" >&2
	tail -n 40 "$IMPORT_LOG" >&2
	exit 1
fi
if grep -nE "$ERROR_RE" "$IMPORT_LOG"; then
	echo "[practice-flow-lab] import log reported engine errors" >&2
	exit 1
fi

status=0
PASS_LOG="$RUN_CACHE/pass.log"
FAIL_LOG="$RUN_CACHE/failure.log"

echo "[practice-flow-lab] running practice flow (pass case)"
: >"$PASS_LOG"
run_engine "$PASS_LOG" --headless --fixed-fps 60 --path "$STAGE" \
	--script res://tools/practice_flow_lab/practice_flow_lab.gd >>"$PASS_LOG" 2>&1
pass_status=$?
cat "$PASS_LOG"
if grep -nE "$ERROR_RE" "$PASS_LOG"; then
	echo "[practice-flow-lab] pass log reported engine errors" >&2
	status=1
fi
if [ "$pass_status" -ne 0 ]; then
	echo "[practice-flow-lab] pass case exited $pass_status" >&2
	status=1
fi
if ! grep -q '^PRACTICE_RESULT ' "$PASS_LOG"; then
	echo "[practice-flow-lab] pass case produced no PRACTICE_RESULT" >&2
	status=1
fi
pass_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$PASS_LOG" | tail -n 1)
if [ "$pass_failed" != "0" ]; then
	echo "[practice-flow-lab] pass case CHECKS_FAILED=$pass_failed" >&2
	status=1
fi

echo "[practice-flow-lab] running deliberate failure proof (--expect-failure)"
: >"$FAIL_LOG"
run_engine "$FAIL_LOG" --headless --fixed-fps 60 --path "$STAGE" \
	--script res://tools/practice_flow_lab/practice_flow_lab.gd -- --expect-failure >>"$FAIL_LOG" 2>&1
failure_status=$?
cat "$FAIL_LOG"
if [ "$failure_status" -eq 0 ]; then
	echo "[practice-flow-lab] --expect-failure exited 0; failing checks are not detectable" >&2
	status=1
fi
failure_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$FAIL_LOG" | tail -n 1)
case "$failure_failed" in
'' | 0 | *[!0-9]*)
	echo "[practice-flow-lab] --expect-failure CHECKS_FAILED is not greater than zero" >&2
	status=1
	;;
esac
if grep -nE "$ERROR_RE" "$FAIL_LOG"; then
	echo "[practice-flow-lab] failure-proof log reported unexpected engine errors" >&2
	status=1
fi

if [ -n "$LOG_FILE" ]; then
	cat "$PASS_LOG" "$FAIL_LOG" >"$LOG_FILE" 2>/dev/null || status=1
	echo "[practice-flow-lab] combined log copied to $LOG_FILE"
fi

if [ "$status" -eq 0 ]; then
	echo "[practice-flow-lab] PASS (isolated project: $STAGE)"
else
	echo "[practice-flow-lab] FAIL" >&2
fi
exit "$status"
