#!/bin/sh
# Roadstorm Racer! - provisional M1.7 hairpin calibration-path laboratory runner.
#
# Usage:
#   run_validation.sh [--source DIR] [--sha SHA] [--expect-sha SHA]
#       [--godot BIN] [--lock FILE] [--timeout SECONDS]
#       [--log FILE] [--keep-scratch]
#
# Freezes the tracked source with `git archive <sha>` (default: current HEAD of
# --source), overlays only this owned tools/calibration_hairpin_path_lab
# directory, stages a private project/cache/config/data/home/tmp tree, imports
# it, then runs the hairpin conversion validator and a deliberate failing-check
# probe under pinned Godot. The live working tree is never imported.
#
# Engine invocations are serialized on the coordinator lock and each is bounded
# by an outer watchdog. --timeout is the outer bound in seconds and may not
# exceed 300.
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
TIMEOUT_S=${ROADSTORM_OUTER_TIMEOUT:-300}
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
stages a private project/cache/tmp tree, then runs the provisional hairpin
calibration-path validator and deliberate failure probe under pinned Godot.
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
[ "$TIMEOUT_S" -le 300 ] || die_usage "--timeout must be <= 300 (bounded outer watchdog)"

[ -f "$SOURCE/project.godot" ] || {
	echo "run_calibration_hairpin_path_lab: not a project root: $SOURCE" >&2
	exit 2
}
[ -d "$SOURCE/.git" ] || {
	echo "run_calibration_hairpin_path_lab: --source is not a git checkout: $SOURCE" >&2
	exit 2
}
for required in \
	src/calibration/calibration_driver.gd \
	src/laboratory/handling_lab_builder.gd \
	src/laboratory/handling_lab_data.gd \
	src/simulation/motor_body_adapter.gd \
	fixtures/handling/hairpin.json \
	tools/toolchain/pin/engine.txt; do
	[ -e "$SOURCE/$required" ] || {
		echo "run_calibration_hairpin_path_lab: missing source path: $SOURCE/$required" >&2
		exit 2
	}
done
[ -f "$SCRIPT_DIR/calibration_hairpin_path_source.gd" ] || {
	echo "run_calibration_hairpin_path_lab: owned source is incomplete" >&2
	exit 2
}
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "run_calibration_hairpin_path_lab: Godot binary not found: $GODOT_BIN" >&2
	exit 2
fi
[ -d "$(dirname -- "$LOCK_FILE")" ] || {
	echo "run_calibration_hairpin_path_lab: lock directory missing: $(dirname -- "$LOCK_FILE")" >&2
	exit 2
}
touch "$LOCK_FILE" 2>/dev/null || {
	echo "run_calibration_hairpin_path_lab: cannot create lock file: $LOCK_FILE" >&2
	exit 2
}

if [ -n "$SHA_ARG" ]; then
	SHA=$SHA_ARG
else
	SHA=$(git -C "$SOURCE" rev-parse HEAD 2>/dev/null) || {
		echo "run_calibration_hairpin_path_lab: cannot resolve HEAD of $SOURCE" >&2
		exit 2
	}
fi
git -C "$SOURCE" cat-file -e "$SHA^{commit}" 2>/dev/null || {
	echo "run_calibration_hairpin_path_lab: not a commit: $SHA" >&2
	exit 2
}
if [ -n "$EXPECT_SHA" ] && [ "$SHA" != "$EXPECT_SHA" ]; then
	echo "run_calibration_hairpin_path_lab: frozen SHA $SHA does not match expected $EXPECT_SHA" >&2
	exit 2
fi
echo "[run-calibration-hairpin-path] frozen source SHA $SHA"
echo "[run-calibration-hairpin-path] source checkout $SOURCE"

PINNED="4.7.2.stable.official.ed1daf0bf"

error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'
stage=""

stop_exact_child() {
	[ -n "$stage" ] || return 0
	_child=$(cat "$stage/godot.pid" 2>/dev/null || true)
	if [ -n "$_child" ] && kill -0 "$_child" 2>/dev/null; then
		kill -TERM "$_child" 2>/dev/null || true
		sleep 1
		kill -KILL "$_child" 2>/dev/null || true
		echo "[run-calibration-hairpin-path] stopped stranded exact Godot child $_child" >&2
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
		sleep "$TIMEOUT_S" 2>/dev/null
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

stage=$(mktemp -d "${TMPDIR:-/tmp}/calibration-hairpin-path-lab-stage.XXXXXX" 2>/dev/null) || {
	echo "run_calibration_hairpin_path_lab: cannot create staging directory" >&2
	exit 2
}
stage=$(CDPATH= cd -- "$stage" 2>/dev/null && pwd) || {
	echo "run_calibration_hairpin_path_lab: cannot resolve staging directory" >&2
	exit 2
}
cleanup() {
	stop_exact_child
	if [ "$KEEP_SCRATCH" -eq 0 ] && [ -n "$stage" ] && [ -d "$stage" ]; then
		rm -rf "$stage"
	fi
}
trap cleanup EXIT HUP INT TERM

PROJECT_STAGE="$stage/project"
mkdir -p "$PROJECT_STAGE" || exit 2
echo "[run-calibration-hairpin-path] extracting git archive $SHA"
git -C "$SOURCE" archive --format=tar "$SHA" | tar -x -C "$PROJECT_STAGE" || {
	echo "run_calibration_hairpin_path_lab: git archive extraction failed" >&2
	exit 2
}
rm -rf "$PROJECT_STAGE/tools/calibration_hairpin_path_lab"
cp -R "$SCRIPT_DIR" "$PROJECT_STAGE/tools/" || {
	echo "run_calibration_hairpin_path_lab: cannot overlay owned lab directory" >&2
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
echo "[run-calibration-hairpin-path] checking engine version"
run_godot "$version_log" "$GODOT_BIN" --version || {
	echo "run_calibration_hairpin_path_lab: engine --version failed or timed out" >&2
	tail -n 20 "$version_log" >&2
	exit 2
}
actual_version=$(tail -n 1 "$version_log")
case "$actual_version" in
*"$PINNED"*) ;;
*)
	echo "run_calibration_hairpin_path_lab: engine is not the pinned $PINNED (got: $actual_version)" >&2
	exit 2
;;
esac
echo "[run-calibration-hairpin-path] engine $actual_version"

import_log="$stage/import.log"
: >"$import_log"
echo "[run-calibration-hairpin-path] importing frozen staged project"
run_godot "$import_log" "$GODOT_BIN" --headless --path "$PROJECT_STAGE" --import || {
	echo "run_calibration_hairpin_path_lab: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
}
if grep -nE "$error_re" "$import_log"; then
	echo "run_calibration_hairpin_path_lab: import log reported engine errors" >&2
	exit 1
fi

status=0
validator_log="$stage/validator.log"
: >"$validator_log"
echo "[run-calibration-hairpin-path] running hairpin calibration-path validator"
run_godot "$validator_log" "$GODOT_BIN" --headless --fixed-fps 60 \
	--path "$PROJECT_STAGE" \
	--script res://tools/calibration_hairpin_path_lab/validate_calibration_hairpin_path_lab.gd \
	-- --summary-out="$PROJECT_STAGE/calibration_hairpin_path_summary.json"
validator_rc=$?
probe_allowed=1
[ "$validator_rc" -eq 0 ] || {
	status=1
	probe_allowed=0
}
if grep -nE "$error_re" "$validator_log"; then
	echo "run_calibration_hairpin_path_lab: validator log reported engine errors" >&2
	status=1
	probe_allowed=0
fi
validator_summary=$(grep '^CALIBRATION_HAIRPIN_PATH_LAB_SUMMARY ' "$validator_log" | tail -n 1)
if [ -z "$validator_summary" ]; then
	echo "run_calibration_hairpin_path_lab: validator produced no CALIBRATION_HAIRPIN_PATH_LAB_SUMMARY" >&2
	status=1
	probe_allowed=0
fi
case "$validator_summary" in
*'"pass":true'*) ;;
*)
	echo "run_calibration_hairpin_path_lab: validator did not report pass=true" >&2
	status=1
	probe_allowed=0
;;
esac
validator_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$validator_log" | tail -n 1)
if [ "$validator_failed" != "0" ]; then
	echo "run_calibration_hairpin_path_lab: validator reported CHECKS_FAILED=$validator_failed" >&2
	status=1
	probe_allowed=0
fi
validator_total=$(sed -n 's/.*CHECKS_TOTAL=//p' "$validator_log" | tail -n 1)
echo "[run-calibration-hairpin-path] validator rc=$validator_rc checks_total=${validator_total:-?} checks_failed=${validator_failed:-?}"
tail -n 80 "$validator_log"

if [ "$probe_allowed" -eq 1 ]; then
	probe_log="$stage/failure_probe.log"
	: >"$probe_log"
	echo "[run-calibration-hairpin-path] running deliberate failure probe (nonzero exit expected)"
	run_godot "$probe_log" "$GODOT_BIN" --headless --fixed-fps 60 \
		--path "$PROJECT_STAGE" \
		--script res://tools/calibration_hairpin_path_lab/failure_probe.gd
	probe_rc=$?
	if [ "$probe_rc" -eq 0 ]; then
		echo "run_calibration_hairpin_path_lab: failure probe exited 0; failing checks are not detectable" >&2
		status=1
	fi
	probe_result=$(grep '^CALIBRATION_HAIRPIN_FAILURE_PROBE ' "$probe_log" | tail -n 1)
	case "$probe_result" in
	*'"pass":false'*) ;;
	*)
		echo "run_calibration_hairpin_path_lab: failure probe did not report pass=false" >&2
		status=1
		;;
	esac
	echo "[run-calibration-hairpin-path] failure probe rc=$probe_rc"
	tail -n 20 "$probe_log"
else
	echo "[run-calibration-hairpin-path] skipping deliberate failure probe: validator did not pass" >&2
fi

if [ -n "$LOG_FILE" ]; then
	tail -c 2097152 "$validator_log" >"$LOG_FILE" || status=1
	echo "[run-calibration-hairpin-path] validator log copied to $LOG_FILE (bounded to 2 MiB)"
fi

if [ "$KEEP_SCRATCH" -eq 1 ]; then
	echo "[run-calibration-hairpin-path] logs kept in $stage"
fi

if [ "$status" -eq 0 ]; then
	echo "[run-calibration-hairpin-path] PASS (isolated project: $PROJECT_STAGE)"
else
	echo "[run-calibration-hairpin-path] FAIL (isolated project: $PROJECT_STAGE)" >&2
fi
exit "$status"
