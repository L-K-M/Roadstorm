#!/bin/sh
# Roadstorm Racer! - provisional M1.7 hairpin physical first-tick laboratory.
#
# Usage:
#   run_validation.sh [--source DIR] [--sha SHA] [--expect-sha SHA]
#       [--godot BIN] [--lock FILE] [--timeout SECONDS]
#       [--log FILE] [--keep-scratch]
#
# Freezes tracked source with `git archive <sha>` (default: current HEAD of
# --source), overlays only this owned tools/calibration_hairpin_physical_lab
# directory, stages a private project/cache/config/data/home/tmp tree, imports
# it, then runs the hairpin physical first-tick probe scene and a deliberate
# failing-check probe under pinned Godot. The live working tree is never
# imported.
#
# Engine invocations are serialized on the coordinator lock. Each invocation
# is bounded by `timeout -k 5 SECONDS` (default 120, maximum 120). The
# deliberate whole-run bound is at most 6 minutes.
#
# Exit codes: 0 = every phase passed; 1 = a phase failed; 2 = unsafe input or
# an unusable engine.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE=${ROADSTORM_SOURCE:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
DEFAULT_GODOT="$SOURCE/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
GODOT_BIN=${ROADSTORM_GODOT:-$DEFAULT_GODOT}
DEFAULT_LOCK="$SOURCE/work/agents/coordinator/godot-test.lock"
LOCK_FILE=${ROADSTORM_GODOT_LOCK:-$DEFAULT_LOCK}
TIMEOUT_S=${ROADSTORM_TIMEOUT:-120}
LOG_FILE=""
KEEP_SCRATCH=0
SHA_ARG=""
EXPECT_SHA=""

usage() {
	cat <<'USAGE'
Usage: run_validation.sh [--source DIR] [--sha SHA] [--expect-sha SHA]
       [--godot BIN] [--lock FILE] [--timeout SECONDS]
       [--log FILE] [--keep-scratch]

Freezes tracked source with git archive, overlays this owned lab directory,
stages a private project/cache/tmp tree, then runs the hairpin physical
first-tick probe scene and deliberate failure probe under pinned Godot.
USAGE
}

die_usage() {
	echo "$1" >&2
	usage >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--source)
		[ $# -ge 2 ] || die_usage "--source needs a value"
		SOURCE=$2; shift 2 ;;
	--source=*)
		SOURCE=${1#*=}; shift ;;
	--sha)
		[ $# -ge 2 ] || die_usage "--sha needs a value"
		SHA_ARG=$2; shift 2 ;;
	--sha=*)
		SHA_ARG=${1#*=}; shift ;;
	--expect-sha)
		[ $# -ge 2 ] || die_usage "--expect-sha needs a value"
		EXPECT_SHA=$2; shift 2 ;;
	--expect-sha=*)
		EXPECT_SHA=${1#*=}; shift ;;
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
[ "$TIMEOUT_S" -le 120 ] || die_usage "--timeout must be <= 120 (per-call bound)"

[ -f "$SOURCE/project.godot" ] || {
	echo "run_calibration_hairpin_physical_lab: not a project root: $SOURCE" >&2
	exit 2
}
[ -d "$SOURCE/.git" ] || {
	echo "run_calibration_hairpin_physical_lab: --source is not a git checkout: $SOURCE" >&2
	exit 2
}
[ -f "$SCRIPT_DIR/hairpin_first_tick_probe.gd" ] || {
	echo "run_calibration_hairpin_physical_lab: owned probe is incomplete" >&2
	exit 2
}
[ -f "$SCRIPT_DIR/hairpin_first_tick_probe.tscn" ] || {
	echo "run_calibration_hairpin_physical_lab: owned scene is incomplete" >&2
	exit 2
}
[ -f "$SCRIPT_DIR/failure_probe.gd" ] || {
	echo "run_calibration_hairpin_physical_lab: owned failure probe is incomplete" >&2
	exit 2
}
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "run_calibration_hairpin_physical_lab: Godot binary not found: $GODOT_BIN" >&2
	exit 2
fi
[ -d "$(dirname -- "$LOCK_FILE")" ] || {
	echo "run_calibration_hairpin_physical_lab: lock directory missing: $(dirname -- "$LOCK_FILE")" >&2
	exit 2
}
touch "$LOCK_FILE" 2>/dev/null || {
	echo "run_calibration_hairpin_physical_lab: cannot create lock file: $LOCK_FILE" >&2
	exit 2
}

if [ -n "$SHA_ARG" ]; then
	SHA=$SHA_ARG
else
	SHA=$(git -C "$SOURCE" rev-parse HEAD 2>/dev/null) || {
		echo "run_calibration_hairpin_physical_lab: cannot resolve HEAD of $SOURCE" >&2
		exit 2
	}
fi
git -C "$SOURCE" cat-file -e "$SHA^{commit}" 2>/dev/null || {
	echo "run_calibration_hairpin_physical_lab: not a commit: $SHA" >&2
	exit 2
}
if [ -n "$EXPECT_SHA" ] && [ "$SHA" != "$EXPECT_SHA" ]; then
	echo "run_calibration_hairpin_physical_lab: frozen SHA $SHA does not match expected $EXPECT_SHA" >&2
	exit 2
fi
echo "[run-calibration-hairpin-physical] frozen source SHA $SHA"
echo "[run-calibration-hairpin-physical] source checkout $SOURCE"

PINNED="4.7.2.stable.official.ed1daf0bf"
if [ -r "$SOURCE/tools/toolchain/pin/engine.txt" ]; then
	PINNED_FROM_FILE=$(sed -n 's/^version_string=//p' "$SOURCE/tools/toolchain/pin/engine.txt" | head -n 1)
	[ -n "$PINNED_FROM_FILE" ] && PINNED=$PINNED_FROM_FILE
fi

error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

if [ -d "$SOURCE/work/agents" ]; then
	SCRATCH_PARENT="$SOURCE/work/agents"
else
	SCRATCH_PARENT="${TMPDIR:-/tmp}"
fi

stage=""
stop_exact_child() {
	[ -n "$stage" ] || return 0
	_child=$(cat "$stage/godot.pid" 2>/dev/null || true)
	if [ -n "$_child" ] && kill -0 "$_child" 2>/dev/null; then
		kill -TERM "$_child" 2>/dev/null || true
		sleep 1
		kill -KILL "$_child" 2>/dev/null || true
		echo "[run-calibration-hairpin-physical] stopped stranded exact Godot child $_child" >&2
	fi
}

stage_is_safe_scratch() {
	[ -n "${stage:-}" ] || return 1
	[ -d "$stage" ] || return 1
	[ ! -L "$stage" ] || return 1
	case "$stage" in
	*/calibration-hairpin-physical-lab-stage.*) return 0 ;;
	esac
	return 1
}

cleanup_scratch() {
	[ "$KEEP_SCRATCH" -eq 0 ] || return 0
	[ -n "${stage:-}" ] || return 0
	if [ ! -e "$stage" ] && [ ! -L "$stage" ]; then
		return 0
	fi
	if ! stage_is_safe_scratch; then
		echo "run_calibration_hairpin_physical_lab: refusing unsafe scratch cleanup path: $stage" >&2
		return 1
	fi
	_rm_output=$(rm -rf -- "$stage" 2>&1)
	_rm_rc=$?
	if [ "$_rm_rc" -ne 0 ] || [ -e "$stage" ] || [ -L "$stage" ]; then
		echo "run_calibration_hairpin_physical_lab: scratch cleanup failed for $stage" >&2
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
	timeout -k 5 "$TIMEOUT_S" /usr/bin/lockf -k "$LOCK_FILE" \
		sh -c 'echo $$ > "$1"; shift; exec "$@"' _ "$stage/godot.pid" "$@" >>"$_out" 2>&1 &
	_wrapper=$!
	wait "$_wrapper" 2>/dev/null
	_rc=$?
	stop_exact_child
	return "$_rc"
}

stage=$(mktemp -d "$SCRATCH_PARENT/calibration-hairpin-physical-lab-stage.XXXXXX" 2>/dev/null) || {
	echo "run_calibration_hairpin_physical_lab: cannot create staging directory" >&2
	exit 2
}
stage=$(CDPATH= cd -- "$stage" 2>/dev/null && pwd) || {
	echo "run_calibration_hairpin_physical_lab: cannot resolve staging directory" >&2
	exit 2
}
cleanup_done=0
cleanup() {
	stop_exact_child
	if [ "$cleanup_done" -eq 0 ]; then
		cleanup_done=1
		cleanup_scratch || true
	fi
}
trap cleanup EXIT HUP INT TERM

echo "[run-calibration-hairpin-physical] staging isolated project/cache in $stage"
PROJECT_STAGE="$stage/project"
mkdir -p "$PROJECT_STAGE" || exit 2
echo "[run-calibration-hairpin-physical] extracting git archive $SHA"
git -C "$SOURCE" archive --format=tar "$SHA" | tar -x -C "$PROJECT_STAGE" || {
	echo "run_calibration_hairpin_physical_lab: git archive extraction failed" >&2
	exit 2
}
rm -rf "$PROJECT_STAGE/tools/calibration_hairpin_physical_lab"
mkdir -p "$PROJECT_STAGE/tools" || exit 2
cp -R "$SCRIPT_DIR" "$PROJECT_STAGE/tools/" || {
	echo "run_calibration_hairpin_physical_lab: cannot overlay owned lab directory" >&2
	exit 2
}
find "$PROJECT_STAGE" -type d -name .godot -prune -exec rm -rf {} + 2>/dev/null
printf '%s\n' "$SHA" >"$stage/frozen_source_sha.txt"

mkdir -p "$stage/cache" "$stage/config" "$stage/data" "$stage/home" "$stage/tmp" || exit 2
export TMPDIR="$stage/tmp"
export HOME="$stage/home"
export XDG_CACHE_HOME="$stage/cache"
export XDG_CONFIG_HOME="$stage/config"
export XDG_DATA_HOME="$stage/data"

version_log="$stage/version.log"
: >"$version_log"
echo "[run-calibration-hairpin-physical] checking engine version"
run_godot "$version_log" "$GODOT_BIN" --version || {
	echo "run_calibration_hairpin_physical_lab: engine --version failed or timed out" >&2
	tail -n 20 "$version_log" >&2
	exit 2
}
actual_version=$(tail -n 1 "$version_log")
case "$actual_version" in
*"$PINNED"*) ;;
*)
	echo "run_calibration_hairpin_physical_lab: engine is not the pinned $PINNED (got: $actual_version)" >&2
	exit 2
;;
esac
echo "[run-calibration-hairpin-physical] engine $actual_version"

import_log="$stage/import.log"
: >"$import_log"
echo "[run-calibration-hairpin-physical] importing frozen staged project"
run_godot "$import_log" "$GODOT_BIN" --headless --path "$PROJECT_STAGE" --import || {
	echo "run_calibration_hairpin_physical_lab: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
}
if grep -nE "$error_re" "$import_log"; then
	echo "run_calibration_hairpin_physical_lab: import log reported engine errors" >&2
	exit 1
fi

status=0

probe_log="$stage/probe.log"
: >"$probe_log"
echo "[run-calibration-hairpin-physical] running hairpin physical first-tick probe scene"
run_godot "$probe_log" "$GODOT_BIN" --headless --fixed-fps 60 \
	--path "$PROJECT_STAGE" \
	--scene "res://tools/calibration_hairpin_physical_lab/hairpin_first_tick_probe.tscn" \
	--quit-after 300
probe_rc=$?
probe_allowed=1
[ "$probe_rc" -eq 0 ] || {
	status=1
	probe_allowed=0
}
if grep -nE "$error_re" "$probe_log"; then
	echo "run_calibration_hairpin_physical_lab: probe log reported engine errors" >&2
	status=1
	probe_allowed=0
fi
probe_summary=$(grep '^M17_HAIRPIN_FIRST_TICK ' "$probe_log" | tail -n 1)
if [ -z "$probe_summary" ]; then
	echo "run_calibration_hairpin_physical_lab: probe produced no M17_HAIRPIN_FIRST_TICK summary" >&2
	status=1
	probe_allowed=0
fi
case "$probe_summary" in
*'"pass":true'*) ;;
*)
	echo "run_calibration_hairpin_physical_lab: probe did not report pass=true" >&2
	status=1
	probe_allowed=0
;;
esac
probe_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$probe_log" | tail -n 1)
if [ "$probe_failed" != "0" ]; then
	echo "run_calibration_hairpin_physical_lab: probe reported CHECKS_FAILED=${probe_failed:-?}" >&2
	status=1
	probe_allowed=0
fi
probe_total=$(sed -n 's/.*CHECKS_TOTAL=//p' "$probe_log" | tail -n 1)
echo "[run-calibration-hairpin-physical] probe rc=$probe_rc checks_total=${probe_total:-?} checks_failed=${probe_failed:-?}"
grep -v '^M17_HAIRPIN_FIRST_TICK ' "$probe_log" | tail -n 40

if [ "$probe_allowed" -eq 1 ]; then
	failure_log="$stage/failure_probe.log"
	: >"$failure_log"
	echo "[run-calibration-hairpin-physical] running deliberate failure probe (nonzero exit expected)"
	run_godot "$failure_log" "$GODOT_BIN" --headless --fixed-fps 60 \
		--path "$PROJECT_STAGE" \
		--script "res://tools/calibration_hairpin_physical_lab/failure_probe.gd"
	failure_rc=$?
	if [ "$failure_rc" -eq 0 ]; then
		echo "run_calibration_hairpin_physical_lab: failure probe exited 0; failing checks are not detectable" >&2
		status=1
	fi
	if grep -nE "$error_re" "$failure_log"; then
		echo "run_calibration_hairpin_physical_lab: failure probe log reported engine errors" >&2
		status=1
	fi
	failure_summary=$(grep '^CALIBRATION_HAIRPIN_PHYSICAL_FAILURE_PROBE ' "$failure_log" | tail -n 1)
	case "$failure_summary" in
	*'"pass":false'*) ;;
	*)
		echo "run_calibration_hairpin_physical_lab: failure probe did not report pass=false" >&2
		status=1
		;;
	esac
	failure_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$failure_log" | tail -n 1)
	if [ "${failure_failed:-0}" = "0" ]; then
		echo "run_calibration_hairpin_physical_lab: failure probe did not report a failing check" >&2
		status=1
	fi
	echo "[run-calibration-hairpin-physical] failure probe rc=$failure_rc checks_failed=${failure_failed:-?}"
	tail -n 20 "$failure_log"
else
	echo "[run-calibration-hairpin-physical] skipping deliberate failure probe: probe did not pass" >&2
fi

if [ -n "$LOG_FILE" ]; then
	tail -c 2097152 "$probe_log" >"$LOG_FILE" || status=1
	echo "[run-calibration-hairpin-physical] probe log copied to $LOG_FILE (bounded to 2 MiB)"
fi

if [ "$KEEP_SCRATCH" -eq 1 ]; then
	echo "[run-calibration-hairpin-physical] logs kept in $stage"
fi

if [ "$cleanup_done" -eq 0 ]; then
	cleanup_done=1
	stop_exact_child
	cleanup_scratch || status=1
fi

if [ "$status" -eq 0 ]; then
	echo "[run-calibration-hairpin-physical] PASS (isolated project: $PROJECT_STAGE)"
else
	echo "[run-calibration-hairpin-physical] FAIL (isolated project: $PROJECT_STAGE)" >&2
fi
exit "$status"
