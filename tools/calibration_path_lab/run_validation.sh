#!/bin/sh
# Roadstorm Racer! - provisional M1.7 calibration-path laboratory runner.
#
# Usage:
#   run_validation.sh [--project DIR] [--godot BIN] [--lock FILE]
#       [--timeout SECONDS] [--outer-timeout SECONDS] [--log FILE] [--keep-scratch]
#
# Stages a private project copy plus private Godot cache/config/data/home/tmp
# directories, imports it, then runs the calibration-path validator and a
# deliberate failing-check probe under pinned Godot. Engine invocations are
# serialized on the coordinator lock and bounded by an outer watchdog.
#
# Exit codes: 0 = every phase passed; 1 = a phase failed; 2 = unsafe input or
# an unusable engine.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=${ROADSTORM_PROJECT:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
DEFAULT_GODOT="$PROJECT/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
GODOT_BIN=${ROADSTORM_GODOT:-$DEFAULT_GODOT}
DEFAULT_LOCK="$PROJECT/work/agents/coordinator/godot-test.lock"
LOCK_FILE=${ROADSTORM_GODOT_LOCK:-$DEFAULT_LOCK}
TIMEOUT_S=${ROADSTORM_TEST_TIMEOUT:-120}
OUTER_TIMEOUT_S=${ROADSTORM_OUTER_TIMEOUT:-600}
LOG_FILE=""
KEEP_SCRATCH=0

usage() {
	cat <<'USAGE'
Usage: run_validation.sh [--project DIR] [--godot BIN] [--lock FILE]
       [--timeout SECONDS] [--outer-timeout SECONDS] [--log FILE] [--keep-scratch]

Stages a private project/cache/tmp copy, imports it, then runs the provisional
sweeper calibration-path validator and deliberate failure probe under pinned Godot.
USAGE
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
		PROJECT=$2; shift 2 ;;
	--project=*)
		PROJECT=${1#*=}; shift ;;
	--godot)
		[ $# -ge 2 ] || die_usage "--godot needs a value"
		GODOT_BIN=$2; shift 2 ;;
	--godot=*)
		GODOT_BIN=${1#*=}; shift ;;
	--lock)
		[ $# -ge 2 ] || die_usage "--lock needs a value"
		LOCK_FILE=$2; shift 2 ;;
	--lock=*)
		LOCK_FILE=${1#*=}; shift ;;
	--timeout)
		[ $# -ge 2 ] || die_usage "--timeout needs a value"
		TIMEOUT_S=$2; shift 2 ;;
	--timeout=*)
		TIMEOUT_S=${1#*=}; shift ;;
	--outer-timeout)
		[ $# -ge 2 ] || die_usage "--outer-timeout needs a value"
		OUTER_TIMEOUT_S=$2; shift 2 ;;
	--outer-timeout=*)
		OUTER_TIMEOUT_S=${1#*=}; shift ;;
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

case "$TIMEOUT_S" in
'' | *[!0-9]*) die_usage "--timeout must be a positive integer" ;;
esac
[ "$TIMEOUT_S" -gt 0 ] || die_usage "--timeout must be a positive integer"
case "$OUTER_TIMEOUT_S" in
'' | *[!0-9]*) die_usage "--outer-timeout must be a positive integer" ;;
esac
[ "$OUTER_TIMEOUT_S" -gt 0 ] || die_usage "--outer-timeout must be a positive integer"
[ "$OUTER_TIMEOUT_S" -ge "$TIMEOUT_S" ] || {
	echo "run_calibration_path_lab: --outer-timeout must be >= --timeout" >&2
	exit 2
}

[ -f "$PROJECT/project.godot" ] || {
	echo "run_calibration_path_lab: not a project root: $PROJECT" >&2
	exit 2
}
for required in src scenes assets fixtures src/calibration/calibration_driver.gd src/laboratory/handling_lab_builder.gd tools/calibration_path_lab; do
	[ -e "$PROJECT/$required" ] || {
		echo "run_calibration_path_lab: missing staged path: $PROJECT/$required" >&2
		exit 2
	}
done
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "run_calibration_path_lab: Godot binary not found: $GODOT_BIN" >&2
	exit 2
fi
[ -d "$(dirname -- "$LOCK_FILE")" ] || {
	echo "run_calibration_path_lab: lock directory missing: $(dirname -- "$LOCK_FILE")" >&2
	exit 2
}
touch "$LOCK_FILE" 2>/dev/null || {
	echo "run_calibration_path_lab: cannot create lock file: $LOCK_FILE" >&2
	exit 2
}

PINNED="4.7.2.stable.official.ed1daf0bf"
if [ -r "$PROJECT/tools/toolchain/pin/engine.txt" ]; then
	PINNED_FROM_FILE=$(sed -n 's/^version_string=//p' "$PROJECT/tools/toolchain/pin/engine.txt" | head -n 1)
	[ -n "$PINNED_FROM_FILE" ] && PINNED=$PINNED_FROM_FILE
fi

error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'
stage=""

stop_exact_child() {
	[ -n "$stage" ] || return 0
	_child=$(cat "$stage/godot.pid" 2>/dev/null || true)
	if [ -n "$_child" ] && kill -0 "$_child" 2>/dev/null; then
		kill -TERM "$_child" 2>/dev/null || true
		sleep 1
		kill -KILL "$_child" 2>/dev/null || true
		echo "[run-calibration-path] stopped stranded exact Godot child $_child" >&2
	fi
}

# run_godot <logfile> <command...>: one serialized, outer-bounded engine call.
run_godot() {
	_out=$1
	shift
	: >"$stage/godot.pid"
	lockf -k -w -t 600 "$LOCK_FILE" \
		sh -c 'echo $$ > "$1"; shift; exec "$@"' _ "$stage/godot.pid" "$@" >>"$_out" 2>&1 &
	_wrapper=$!
	(
		sleep "$OUTER_TIMEOUT_S" 2>/dev/null
		if kill -0 "$_wrapper" 2>/dev/null; then
			stop_exact_child
			kill -TERM "$_wrapper" 2>/dev/null || true
			sleep 1
			kill -KILL "$_wrapper" 2>/dev/null || true
		fi
	) >/dev/null 2>&1 &
	_watch=$!
	wait "$_wrapper" 2>/dev/null
	_rc=$?
	kill "$_watch" 2>/dev/null || true
	wait "$_watch" 2>/dev/null || true
	stop_exact_child
	return "$_rc"
}

stage=$(mktemp -d "${TMPDIR:-/tmp}/calibration-path-lab-stage.XXXXXX" 2>/dev/null) || {
	echo "run_calibration_path_lab: cannot create staging directory" >&2
	exit 2
}
stage=$(CDPATH= cd -- "$stage" 2>/dev/null && pwd) || {
	echo "run_calibration_path_lab: cannot resolve staging directory" >&2
	exit 2
}
cleanup() {
	stop_exact_child
	if [ "$KEEP_SCRATCH" -eq 0 ] && [ -n "$stage" ] && [ -d "$stage" ]; then
		rm -rf "$stage"
	fi
}
trap cleanup EXIT HUP INT TERM

echo "[run-calibration-path] staging isolated project/cache in $stage"
cp "$PROJECT/project.godot" "$stage/" || exit 2
for path in src scenes assets fixtures; do
	cp -R "$PROJECT/$path" "$stage/$path" || exit 2
done
mkdir -p "$stage/tools" || exit 2
cp -R "$PROJECT/tools/calibration_path_lab" "$stage/tools/calibration_path_lab" || exit 2
find "$stage" -type d -name .godot -prune -exec rm -rf {} + 2>/dev/null
mkdir -p "$stage/cache" "$stage/config" "$stage/data" "$stage/home" "$stage/tmp" || exit 2
export TMPDIR="$stage/tmp"
export HOME="$stage/home"
export XDG_CACHE_HOME="$stage/cache"
export XDG_CONFIG_HOME="$stage/config"
export XDG_DATA_HOME="$stage/data"

version_log="$stage/version.log"
: >"$version_log"
echo "[run-calibration-path] checking engine version"
run_godot "$version_log" "$GODOT_BIN" --version || {
	echo "run_calibration_path_lab: engine --version failed or timed out" >&2
	tail -n 20 "$version_log" >&2
	exit 2
}
actual_version=$(tail -n 1 "$version_log")
case "$actual_version" in
*"$PINNED"*) ;;
*)
	echo "run_calibration_path_lab: engine is not the pinned $PINNED (got: $actual_version)" >&2
	exit 2
;;
esac
echo "[run-calibration-path] engine $actual_version"

import_log="$stage/import.log"
: >"$import_log"
echo "[run-calibration-path] importing staged project"
run_godot "$import_log" "$GODOT_BIN" --headless --path "$stage" --import || {
	echo "run_calibration_path_lab: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
}
if grep -nE "$error_re" "$import_log"; then
	echo "run_calibration_path_lab: import log reported engine errors" >&2
	exit 1
fi

status=0
validator_log="$stage/validator.log"
: >"$validator_log"
echo "[run-calibration-path] running calibration-path validator"
run_godot "$validator_log" "$GODOT_BIN" --headless --fixed-fps 60 \
	--path "$stage" --script res://tools/calibration_path_lab/validate_calibration_path_lab.gd \
	-- --summary-out="$stage/calibration_path_summary.json"
validator_rc=$?
probe_allowed=1
[ "$validator_rc" -eq 0 ] || {
	status=1
	probe_allowed=0
}
if grep -nE "$error_re" "$validator_log"; then
	echo "run_calibration_path_lab: validator log reported engine errors" >&2
	status=1
	probe_allowed=0
fi
validator_summary=$(grep '^CALIBRATION_PATH_LAB_SUMMARY ' "$validator_log" | tail -n 1)
if [ -z "$validator_summary" ]; then
	echo "run_calibration_path_lab: validator produced no CALIBRATION_PATH_LAB_SUMMARY" >&2
	status=1
	probe_allowed=0
fi
case "$validator_summary" in
*'"pass":true'*) ;;
*)
	echo "run_calibration_path_lab: validator did not report pass=true" >&2
	status=1
	probe_allowed=0
;;
esac
validator_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$validator_log" | tail -n 1)
if [ "$validator_failed" != "0" ]; then
	echo "run_calibration_path_lab: validator reported CHECKS_FAILED=$validator_failed" >&2
	status=1
	probe_allowed=0
fi
validator_total=$(sed -n 's/.*CHECKS_TOTAL=//p' "$validator_log" | tail -n 1)
echo "[run-calibration-path] validator rc=$validator_rc checks_total=${validator_total:-?} checks_failed=${validator_failed:-?}"
tail -n 80 "$validator_log"

if [ "$probe_allowed" -eq 1 ]; then
	probe_log="$stage/failure_probe.log"
	: >"$probe_log"
	echo "[run-calibration-path] running deliberate failure probe (nonzero exit expected)"
	run_godot "$probe_log" "$GODOT_BIN" --headless --fixed-fps 60 \
		--path "$stage" --script res://tools/calibration_path_lab/failure_probe.gd
	probe_rc=$?
	if [ "$probe_rc" -eq 0 ]; then
		echo "run_calibration_path_lab: failure probe exited 0; failing checks are not detectable" >&2
		status=1
	fi
	probe_result=$(grep '^CALIBRATION_PATH_FAILURE_PROBE ' "$probe_log" | tail -n 1)
	case "$probe_result" in
	*'"pass":false'*) ;;
	*)
		echo "run_calibration_path_lab: failure probe did not report pass=false" >&2
		status=1
	;;
	esac
	echo "[run-calibration-path] failure probe rc=$probe_rc"
	tail -n 20 "$probe_log"
else
	echo "[run-calibration-path] skipping deliberate failure probe: validator did not pass" >&2
fi

if [ -n "$LOG_FILE" ]; then
	tail -c 2097152 "$validator_log" >"$LOG_FILE" || status=1
	echo "[run-calibration-path] validator log copied to $LOG_FILE (bounded to 2 MiB)"
fi

if [ "$KEEP_SCRATCH" -eq 1 ]; then
	echo "[run-calibration-path] logs kept in $stage"
fi

if [ "$status" -eq 0 ]; then
	echo "[run-calibration-path] PASS (isolated project: $stage)"
else
	echo "[run-calibration-path] FAIL (isolated project: $stage)" >&2
fi
exit "$status"
