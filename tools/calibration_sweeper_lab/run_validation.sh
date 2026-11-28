#!/bin/sh
# Roadstorm Racer! - M1.7 physical sweeper bridge laboratory runner.
#
# Usage:
#   run_validation.sh [--project DIR] [--godot BIN] [--lock FILE]
#       [--timeout SECONDS] [--outer-timeout SECONDS] [--log FILE]
#       [--summary-out FILE] [--full-arc-exit] [--exit-log FILE]
#       [--exit-summary-out FILE] [--keep-scratch]
#
# Stages a private copy of the project and a private Godot cache/config/data
# directory into a temporary directory (never the live checkout), imports it,
# then runs the physical bridge validator and the deliberate failing-check probe
# under the pinned Godot 4.7.2 build. Every engine invocation is serialized on
# the coordinator godot-test lock, wrapped in an outer timeout, and reports the
# exact PID of the one Godot child it started so a stranded parse-error child
# can be stopped without touching any other process.
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
SUMMARY_OUT=""
FULL_ARC_EXIT=0
EXIT_LOG_FILE=""
EXIT_SUMMARY_OUT=""
KEEP_SCRATCH=0
CLEANUP_DONE=0

usage() {
	cat <<'EOF'
Usage: run_validation.sh [--project DIR] [--godot BIN] [--lock FILE]
       [--timeout SECONDS] [--outer-timeout SECONDS] [--log FILE]
       [--summary-out FILE] [--full-arc-exit] [--exit-log FILE]
       [--exit-summary-out FILE] [--keep-scratch]

Stages a private project/cache/tmp copy, imports it, then runs the physical
CalibrationDriver/DriveLab bridge validator and deliberate failure probe under
pinned Godot. With --full-arc-exit it additionally runs the separate bounded
full-arc-exit witness (hard 1800 committed ticks, station >=245 m threshold).
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
	--summary-out)
		[ $# -ge 2 ] || die_usage "--summary-out needs a value"
		SUMMARY_OUT=$2; shift 2 ;;
	--summary-out=*)
		SUMMARY_OUT=${1#*=}; shift ;;
	--full-arc-exit)
		FULL_ARC_EXIT=1; shift ;;
	--exit-log)
		[ $# -ge 2 ] || die_usage "--exit-log needs a value"
		EXIT_LOG_FILE=$2; shift 2 ;;
	--exit-log=*)
		EXIT_LOG_FILE=${1#*=}; shift ;;
	--exit-summary-out)
		[ $# -ge 2 ] || die_usage "--exit-summary-out needs a value"
		EXIT_SUMMARY_OUT=$2; shift 2 ;;
	--exit-summary-out=*)
		EXIT_SUMMARY_OUT=${1#*=}; shift ;;
	--keep-scratch)
		KEEP_SCRATCH=1; shift ;;
	-h | --help)
		usage; exit 0 ;;
	*)
		die_usage "unknown option: $1" ;;
	esac
done

case "$TIMEOUT_S" in
'' | *[!0-9]*)
	die_usage "--timeout must be a positive integer" ;;
esac
[ "$TIMEOUT_S" -gt 0 ] || die_usage "--timeout must be a positive integer"
case "$OUTER_TIMEOUT_S" in
'' | *[!0-9]*)
	die_usage "--outer-timeout must be a positive integer" ;;
esac
[ "$OUTER_TIMEOUT_S" -gt 0 ] || die_usage "--outer-timeout must be a positive integer"
[ "$OUTER_TIMEOUT_S" -ge "$TIMEOUT_S" ] || {
	echo "run_validation: --outer-timeout must be >= --timeout" >&2
	exit 2
}

[ -f "$PROJECT/project.godot" ] || {
	echo "run_validation: not a project root: $PROJECT" >&2
	exit 2
}
for required in src scenes assets src/calibration/calibration_driver.gd fixtures/handling/sweeper.json tools/calibration_path_lab/calibration_path_source.gd tools/calibration_sweeper_lab; do
	[ -e "$PROJECT/$required" ] || {
		echo "run_validation: missing staged path: $PROJECT/$required" >&2
		exit 2
	}
done
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "run_validation: Godot binary not found: $GODOT_BIN" >&2
	exit 2
fi
[ -d "$(dirname -- "$LOCK_FILE")" ] || {
	echo "run_validation: lock directory missing: $(dirname -- "$LOCK_FILE")" >&2
	exit 2
}
touch "$LOCK_FILE" 2>/dev/null || {
	echo "run_validation: cannot create lock file: $LOCK_FILE" >&2
	exit 2
}

if [ "$FULL_ARC_EXIT" -eq 1 ]; then
	if [ -z "$EXIT_LOG_FILE" ] && [ -n "$LOG_FILE" ]; then
		case "$LOG_FILE" in
		*.log) EXIT_LOG_FILE=${LOG_FILE%.log}.exit.log ;;
		*) EXIT_LOG_FILE=$LOG_FILE.exit ;;
		esac
	fi
	if [ -z "$EXIT_SUMMARY_OUT" ] && [ -n "$SUMMARY_OUT" ]; then
		case "$SUMMARY_OUT" in
		*.json) EXIT_SUMMARY_OUT=${SUMMARY_OUT%.json}.exit.json ;;
		*) EXIT_SUMMARY_OUT=$SUMMARY_OUT.exit ;;
		esac
	fi
fi

PINNED="4.7.2.stable.official.ed1daf0bf"
if [ -r "$PROJECT/tools/toolchain/pin/engine.txt" ]; then
	PINNED_FROM_FILE=$(sed -n 's/^version_string=//p' "$PROJECT/tools/toolchain/pin/engine.txt" | head -n 1)
	[ -n "$PINNED_FROM_FILE" ] && PINNED=$PINNED_FROM_FILE
fi

error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

# Stop only the one Godot child this runner started, identified by the PID its
# exec wrapper wrote. Never signals another process by pattern.
stop_exact_child() {
	_child=$(cat "$stage/godot.pid" 2>/dev/null || true)
	if [ -n "$_child" ] && kill -0 "$_child" 2>/dev/null; then
		kill -TERM "$_child" 2>/dev/null || true
		sleep 1
		kill -KILL "$_child" 2>/dev/null || true
		echo "[run-calibration-sweeper] stopped stranded exact Godot child $_child" >&2
	fi
}

# The scratch root is created fresh by this runner. These helpers never accept
# a user-supplied cleanup path, never follow symlinks during permission repair,
# and remove only the exact mktemp child named calibration-sweeper-lab-stage.*.
stage_is_safe_scratch() {
	[ -n "${stage:-}" ] || return 1
	[ -d "$stage" ] || return 1
	[ ! -L "$stage" ] || return 1
	case "$stage" in
	*/calibration-sweeper-lab-stage.*) return 0 ;;
	esac
	return 1
}

make_scratch_writable() {
	stage_is_safe_scratch || return 1
	_chmod_output=$(find "$stage" \( -type d -o -type f \) -exec chmod u+rwX {} + 2>&1)
	_chmod_rc=$?
	if [ "$_chmod_rc" -ne 0 ]; then
		echo "run_validation: cannot make private scratch copy writable: $stage" >&2
		if [ -n "$_chmod_output" ]; then
			printf '%s\n' "$_chmod_output" | sed -n '1,20p' >&2
		fi
		return 1
	fi
	return 0
}

cleanup_scratch() {
	[ "$KEEP_SCRATCH" -eq 0 ] || return 0
	[ -n "${stage:-}" ] || return 0
	if [ ! -e "$stage" ] && [ ! -L "$stage" ]; then
		return 0
	fi
	if ! stage_is_safe_scratch; then
		echo "run_validation: refusing unsafe scratch cleanup path: $stage" >&2
		return 1
	fi
	make_scratch_writable
	_chmod_rc=$?
	_rm_output=$(rm -rf -- "$stage" 2>&1)
	_rm_rc=$?
	if [ "$_chmod_rc" -ne 0 ] || [ "$_rm_rc" -ne 0 ] || [ -e "$stage" ] || [ -L "$stage" ]; then
		echo "run_validation: scratch cleanup failed for $stage" >&2
		if [ -n "$_rm_output" ]; then
			printf '%s\n' "$_rm_output" | sed -n '1,20p' >&2
		fi
		return 1
	fi
	return 0
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

stage=$(mktemp -d "${TMPDIR:-/tmp}/calibration-sweeper-lab-stage.XXXXXX" 2>/dev/null) || {
	echo "run_validation: cannot create staging directory" >&2
	exit 2
}
# macOS commonly ends TMPDIR with '/'. Normalise the scratch path before
# handing it to Godot as a project path and as HOME/XDG roots; the pinned
# editor otherwise fails to create its ObjectDB Snapshots directory.
stage=$(CDPATH= cd -- "$stage" 2>/dev/null && pwd) || {
	echo "run_validation: cannot resolve staging directory" >&2
	exit 2
}
cleanup() {
	stop_exact_child
	if [ "$CLEANUP_DONE" -eq 0 ]; then
		CLEANUP_DONE=1
		cleanup_scratch || true
	fi
}
trap cleanup EXIT HUP INT TERM

echo "[run-calibration-sweeper] staging isolated project/cache in $stage"
cp "$PROJECT/project.godot" "$stage/" || exit 2
for path in src scenes assets; do
	cp -R "$PROJECT/$path" "$stage/$path" || exit 2
done
mkdir -p "$stage/fixtures/handling" || exit 2
cp "$PROJECT/fixtures/handling/sweeper.json" "$stage/fixtures/handling/sweeper.json" || exit 2
mkdir -p "$stage/tools" || exit 2
cp -R "$PROJECT/tools/calibration_path_lab" "$stage/tools/calibration_path_lab" || exit 2
cp -R "$PROJECT/tools/calibration_sweeper_lab" "$stage/tools/calibration_sweeper_lab" || exit 2
find "$stage" -type d -name .godot -prune -exec rm -rf {} + 2>/dev/null
if ! make_scratch_writable; then
	echo "run_validation: unsafe or unwritable private scratch copy" >&2
	exit 2
fi
mkdir -p "$stage/cache" "$stage/config" "$stage/data" "$stage/home" "$stage/tmp" || exit 2
export TMPDIR="$stage/tmp"
export HOME="$stage/home"
export XDG_CACHE_HOME="$stage/cache"
export XDG_CONFIG_HOME="$stage/config"
export XDG_DATA_HOME="$stage/data"

version_log="$stage/version.log"
: >"$version_log"
echo "[run-calibration-sweeper] checking engine version"
run_godot "$version_log" "$GODOT_BIN" --version || {
	echo "run_validation: engine --version failed or timed out" >&2
	tail -n 20 "$version_log" >&2
	exit 2
}
actual_version=$(tail -n 1 "$version_log")
case "$actual_version" in
*"$PINNED"*) ;;
*)
	echo "run_validation: engine is not the pinned $PINNED (got: $actual_version)" >&2
	exit 2
;;
esac
echo "[run-calibration-sweeper] engine $actual_version"

import_log="$stage/import.log"
: >"$import_log"
echo "[run-calibration-sweeper] importing staged project"
run_godot "$import_log" "$GODOT_BIN" --headless --path "$stage" --import || {
	echo "run_validation: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
}
if grep -nE "$error_re" "$import_log"; then
	echo "run_validation: import log reported engine errors" >&2
	exit 1
fi

status=0

validator_log="$stage/validator.log"
: >"$validator_log"
echo "[run-calibration-sweeper] running CalibrationDriver physical sweeper bridge validator"
if [ -n "$SUMMARY_OUT" ]; then
	run_godot "$validator_log" "$GODOT_BIN" --headless --fixed-fps 60 \
		--path "$stage" --script res://tools/calibration_sweeper_lab/validate_calibration_sweeper_lab.gd \
		-- --summary-out="$stage/summary.json"
else
	run_godot "$validator_log" "$GODOT_BIN" --headless --fixed-fps 60 \
		--path "$stage" --script res://tools/calibration_sweeper_lab/validate_calibration_sweeper_lab.gd
fi
validator_rc=$?
# The deliberate-failure probe is only meaningful after a fully passing
# validator. Skip it when the validator failed so a parse-error hang or a
# broken script cannot spawn another stranded engine child.
probe_allowed=1
[ "$validator_rc" -eq 0 ] || {
	status=1
	probe_allowed=0
}
if grep -nE "$error_re" "$validator_log"; then
	echo "run_validation: validator log reported engine errors" >&2
	status=1
	probe_allowed=0
fi
validator_summary=$(grep '^CALIBRATION_SWEEPER_SUMMARY ' "$validator_log" | tail -n 1)
if [ -z "$validator_summary" ]; then
	echo "run_validation: validator produced no CALIBRATION_SWEEPER_SUMMARY" >&2
	status=1
	probe_allowed=0
fi
case "$validator_summary" in
*'"pass":true'*) ;;
*)
	echo "run_validation: validator did not report pass=true" >&2
	status=1
	probe_allowed=0
;;
esac
validator_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$validator_log" | tail -n 1)
if [ "$validator_failed" != "0" ]; then
	echo "run_validation: validator reported CHECKS_FAILED=$validator_failed" >&2
	status=1
	probe_allowed=0
fi
validator_total=$(sed -n 's/.*CHECKS_TOTAL=//p' "$validator_log" | tail -n 1)
echo "[run-calibration-sweeper] validator rc=$validator_rc checks_total=${validator_total:-?} checks_failed=${validator_failed:-?}"
# Keep the console bounded: per-tick trace lines are single huge JSON lines
# and stay available in the full log file instead.
grep -v '^CALIBRATION_SWEEPER_TRACE ' "$validator_log" | tail -n 60

if [ "$probe_allowed" -eq 1 ]; then
	probe_log="$stage/failure_probe.log"
	: >"$probe_log"
	echo "[run-calibration-sweeper] running deliberate failure probe (nonzero exit expected)"
	run_godot "$probe_log" "$GODOT_BIN" --headless --fixed-fps 60 \
		--path "$stage" --script res://tools/calibration_sweeper_lab/failure_probe.gd
	probe_rc=$?
	if [ "$probe_rc" -eq 0 ]; then
		echo "run_validation: failure probe exited 0; failing checks are not detectable" >&2
		status=1
	fi
	probe_result=$(grep '^CALIBRATION_SWEEPER_FAILURE_PROBE ' "$probe_log" | tail -n 1)
	case "$probe_result" in
	*'"pass":false'*) ;;
	*)
		echo "run_validation: failure probe did not report pass=false" >&2
		status=1
	;;
	esac
	echo "[run-calibration-sweeper] failure probe rc=$probe_rc"
	tail -n 20 "$probe_log"
else
	echo "[run-calibration-sweeper] skipping deliberate failure probe: validator did not pass" >&2
fi

# Separate opt-in full-arc-exit witness. It runs only after the original
# validator passed, so a broken primary path cannot hide behind this extra
# case. The primary validation and its deliberate probe are still required.
if [ "$FULL_ARC_EXIT" -eq 1 ]; then
	if [ "$probe_allowed" -eq 1 ]; then
		exit_log="$stage/exit_validator.log"
		: >"$exit_log"
		echo "[run-calibration-sweeper] running separate full-arc-exit physical witness (hard 1800-tick budget)"
		run_godot "$exit_log" "$GODOT_BIN" --headless --fixed-fps 60 \
			--path "$stage" --script res://tools/calibration_sweeper_lab/validate_calibration_sweeper_lab.gd \
			-- --full-arc-exit --summary-out="$stage/exit_summary.json"
		exit_rc=$?
		if grep -nE "$error_re" "$exit_log"; then
			echo "run_validation: exit validator log reported engine errors" >&2
			status=1
		fi
		exit_summary=$(grep '^CALIBRATION_SWEEPER_EXIT_SUMMARY ' "$exit_log" | tail -n 1)
		if [ -z "$exit_summary" ]; then
			echo "run_validation: exit validator produced no CALIBRATION_SWEEPER_EXIT_SUMMARY" >&2
			status=1
		fi
		case "$exit_summary" in
		*'"pass":true'*) ;;
		*)
			echo "run_validation: exit validator did not report pass=true" >&2
			status=1
			;;
		esac
		exit_total=$(sed -n 's/.*CHECKS_TOTAL=//p' "$exit_log" | tail -n 1)
		exit_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$exit_log" | tail -n 1)
		echo "[run-calibration-sweeper] exit validator rc=$exit_rc checks_total=${exit_total:-?} checks_failed=${exit_failed:-?}"
		# Bounded console view: compact per-run selected-sample lines stay in
		# the log; the console shows only the surrounding evidence.
		grep -v '^CALIBRATION_SWEEPER_EXIT_TRACE ' "$exit_log" | tail -n 40
		if [ "$exit_rc" -ne 0 ]; then
			status=1
		fi
		if [ -n "$EXIT_LOG_FILE" ]; then
			tail -c 2097152 "$exit_log" >"$EXIT_LOG_FILE" || status=1
			echo "[run-calibration-sweeper] exit validator log copied to $EXIT_LOG_FILE (bounded to 2 MiB)"
		fi
		if [ -n "$EXIT_SUMMARY_OUT" ]; then
			if [ -r "$stage/exit_summary.json" ]; then
				tail -c 4194304 "$stage/exit_summary.json" >"$EXIT_SUMMARY_OUT" || status=1
				echo "[run-calibration-sweeper] structured exit summary written to $EXIT_SUMMARY_OUT"
			else
				echo "run_validation: exit validator wrote no structured summary" >&2
				status=1
			fi
		fi
	else
		echo "[run-calibration-sweeper] skipping full-arc-exit witness: primary validator did not pass" >&2
	fi
fi

if [ -n "$LOG_FILE" ]; then
	tail -c 2097152 "$validator_log" >"$LOG_FILE" || status=1
	echo "[run-calibration-sweeper] validator log copied to $LOG_FILE (bounded to 2 MiB)"
fi

if [ -n "$SUMMARY_OUT" ]; then
	if [ -r "$stage/summary.json" ]; then
		tail -c 4194304 "$stage/summary.json" >"$SUMMARY_OUT" || status=1
		echo "[run-calibration-sweeper] structured summary written to $SUMMARY_OUT"
	else
		echo "run_validation: validator wrote no structured summary" >&2
		status=1
	fi
fi

if [ "$KEEP_SCRATCH" -eq 1 ]; then
	echo "[run-calibration-sweeper] logs kept in $stage"
fi

# Verify removal of this runner's own scratch before reporting success. A
# read-only archived source must not leave a false PASS behind a failed rm.
if [ "$CLEANUP_DONE" -eq 0 ]; then
	CLEANUP_DONE=1
	stop_exact_child
	cleanup_scratch || status=1
fi

if [ "$status" -eq 0 ]; then
	echo "[run-calibration-sweeper] PASS (isolated project: $stage)"
else
	echo "[run-calibration-sweeper] FAIL (isolated project: $stage)" >&2
fi
exit "$status"
