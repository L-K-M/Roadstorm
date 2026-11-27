#!/bin/sh
# Roadstorm Racer! - M1.5 one-car feedback playback laboratory runner.
#
# Ownership: tools/audio_playback_lab/**. Stages an isolated copy of the
# project, runs a headless import, then runs the node-level validator under a
# wall-clock limit and proves that a deliberately failing case exits nonzero.
# Never imports or writes the live checkout's .godot cache. Every Godot
# invocation is bounded by both a per-engine timeout (<=180 s here) and one
# outer deadline (<=300 s here).
#
# Usage:
#   tools/audio_playback_lab/run_validation.sh [--project DIR] [--godot BIN]
#       [--private-dir FRESH_DIR] [--timeout SECONDS]
#       [--overall-timeout SECONDS] [--log FILE] [--case <id>|all|intentional_failure]
#
# Exit codes: 0 = every check passed and the deliberate failure proof exited
# nonzero, 1 = a check/output gate failed, 2 = unsafe inputs or unusable engine.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_PROJECT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

PROJECT_DIR="$DEFAULT_PROJECT"
GODOT_BIN="$DEFAULT_PROJECT/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
PRIVATE_DIR=""
TIMEOUT="180"
OVERALL_TIMEOUT="300"
LOG_FILE=""
CASE_ID="all"
KEEP_SCRATCH="${KEEP_SCRATCH:-0}"

SCRATCH=""
RUN_CACHE=""
IMPORT_LOG=""
MAIN_LOG=""
PROOF_LOG=""
PROJECT_CANON=""
PRIVATE_CANON=""
PRIVATE_REL=""

usage() {
	cat <<'EOF'
Usage: run_validation.sh [--project DIR] [--godot BIN]
                         [--private-dir FRESH_DIR] [--timeout SECONDS]
                         [--overall-timeout SECONDS] [--log FILE]
                         [--case <id>|all|intentional_failure]

--private-dir must not already exist. It is reserved with an atomic mkdir and
the project is staged into it. Omit it for an auto-created temporary copy.
The per-engine timeout is capped at 180 s and the outer deadline at 300 s.
EOF
}

cleanup() {
	if [ -n "$RUN_CACHE" ]; then
		rm -rf "$RUN_CACHE"
	fi
	for _f in "$IMPORT_LOG" "$MAIN_LOG" "$PROOF_LOG"; do
		[ -n "$_f" ] && rm -f "$_f"
	done
	if [ "${KEEP_SCRATCH:-0}" != "1" ] && [ -n "$SCRATCH" ]; then
		rm -rf "$SCRATCH"
	fi
}
trap cleanup EXIT HUP INT TERM

while [ $# -gt 0 ]; do
	case "$1" in
		--project)
			[ $# -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }
			PROJECT_DIR="$2"; shift 2 ;;
		--godot)
			[ $# -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }
			GODOT_BIN="$2"; shift 2 ;;
		--private-dir)
			[ $# -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }
			PRIVATE_DIR="$2"; shift 2 ;;
		--timeout)
			[ $# -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }
			TIMEOUT="$2"; shift 2 ;;
		--overall-timeout)
			[ $# -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }
			OVERALL_TIMEOUT="$2"; shift 2 ;;
		--log)
			[ $# -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }
			LOG_FILE="$2"; shift 2 ;;
		--case)
			[ $# -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }
			CASE_ID="$2"; shift 2 ;;
		-h|--help)
			usage; exit 0 ;;
		*)
			echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
	esac
done

case "$TIMEOUT" in
	'' | *[!0-9]*)
		echo "FAIL: --timeout must be a positive integer" >&2
		exit 2
		;;
esac
case "$OVERALL_TIMEOUT" in
	'' | *[!0-9]*)
		echo "FAIL: --overall-timeout must be a positive integer" >&2
		exit 2
		;;
esac
[ "$TIMEOUT" -gt 0 ] && [ "$TIMEOUT" -le 180 ] || {
	echo "FAIL: --timeout must be between 1 and 180 seconds" >&2
	exit 2
}
[ "$OVERALL_TIMEOUT" -gt 0 ] && [ "$OVERALL_TIMEOUT" -le 300 ] || {
	echo "FAIL: --overall-timeout must be between 1 and 300 seconds" >&2
	exit 2
}
[ "$OVERALL_TIMEOUT" -ge "$TIMEOUT" ] || {
	echo "FAIL: --overall-timeout must not be smaller than --timeout" >&2
	exit 2
}

if [ ! -d "$PROJECT_DIR" ]; then
	echo "FAIL: --project is not a directory: $PROJECT_DIR" >&2
	exit 2
fi
if [ ! -r "$PROJECT_DIR/project.godot" ]; then
	echo "FAIL: no readable project.godot under $PROJECT_DIR" >&2
	exit 2
fi
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "FAIL: Godot binary not found or not executable: $GODOT_BIN" >&2
	exit 2
fi

canonical_dir() {
	( CDPATH= cd -- "$1" 2>/dev/null && pwd -P )
}

PROJECT_CANON=$(canonical_dir "$PROJECT_DIR") || {
	echo "FAIL: cannot resolve --project $PROJECT_DIR" >&2
	exit 2
}

reserve_private_dir() {
	if [ -n "$PRIVATE_DIR" ]; then
		if [ -e "$PRIVATE_DIR" ] || [ -L "$PRIVATE_DIR" ]; then
			echo "FAIL: --private-dir already exists; refusing to modify it: $PRIVATE_DIR" >&2
			exit 2
		fi
		parent=$(dirname -- "$PRIVATE_DIR")
		base=$(basename -- "$PRIVATE_DIR")
		if ! canonical_dir "$parent" >/dev/null 2>&1; then
			mkdir -p "$parent" || {
				echo "FAIL: cannot create --private-dir parent: $parent" >&2
				exit 2
			}
		fi
		parent_canon=$(canonical_dir "$parent") || {
			echo "FAIL: cannot resolve --private-dir parent: $parent" >&2
			exit 2
		}
		PRIVATE_CANON="$parent_canon/$base"
		if ! mkdir "$PRIVATE_CANON" 2>/dev/null; then
			echo "FAIL: cannot atomically reserve fresh --private-dir: $PRIVATE_CANON" >&2
			exit 2
		fi
	else
		SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/audio-playback-lab-XXXXXX") || {
			echo "FAIL: cannot create temporary scratch directory" >&2
			exit 2
		}
		PRIVATE_CANON="$SCRATCH/project"
		mkdir "$PRIVATE_CANON" 2>/dev/null || {
			echo "FAIL: cannot create private project directory" >&2
			exit 2
		}
	fi

	case "$PRIVATE_CANON" in
		"$PROJECT_CANON"|"$PROJECT_CANON"/*)
			PRIVATE_REL=${PRIVATE_CANON#"$PROJECT_CANON"/}
			case "$PRIVATE_REL" in
				work|work/*)
					# Ignored scratch root; staging excludes it and the
					# destination path is excluded again below.
					;;
				*)
					echo "FAIL: --private-dir resolves inside --project ($PRIVATE_REL); refusing unsafe containment" >&2
					exit 2
					;;
			esac
			;;
		*)
			PRIVATE_REL=""
			;;
	esac
	case "$PROJECT_CANON" in
		"$PRIVATE_CANON"|"$PRIVATE_CANON"/*)
			echo "FAIL: --project resolves inside --private-dir; refusing unsafe containment" >&2
			exit 2
			;;
	esac
}

reserve_private_dir

PINNED_VERSION_STRING="4.7.2.stable.official.ed1daf0bf"
if [ -r "$PROJECT_DIR/tools/toolchain/pin/engine.txt" ]; then
	PINNED_FROM_FILE=$(sed -n 's/^version_string=//p' "$PROJECT_DIR/tools/toolchain/pin/engine.txt" | head -n 1)
	if [ -n "$PINNED_FROM_FILE" ]; then
		PINNED_VERSION_STRING="$PINNED_FROM_FILE"
	fi
fi

# Logs and scratch stay next to --log when one is supplied, so a run can keep
# all of its evidence inside an ignored job directory.
if [ -n "$LOG_FILE" ]; then
	LOG_DIR=$(dirname -- "$LOG_FILE")
	mkdir -p "$LOG_DIR" 2>/dev/null || {
		echo "FAIL: cannot create --log directory: $LOG_DIR" >&2
		exit 2
	}
	RUN_CACHE=$(mktemp -d "$LOG_DIR/.audio-playback-cache-XXXXXX") || exit 2
	IMPORT_LOG=$(mktemp "$LOG_DIR/audio-playback-import-XXXXXX") || exit 2
	MAIN_LOG=$(mktemp "$LOG_DIR/audio-playback-main-XXXXXX") || exit 2
	PROOF_LOG=$(mktemp "$LOG_DIR/audio-playback-proof-XXXXXX") || exit 2
else
	SCRATCH_BASE=$(mktemp -d "${TMPDIR:-/tmp}/audio-playback-lab-logs-XXXXXX") || exit 2
	RUN_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/audio-playback-lab-cache-XXXXXX") || exit 2
	IMPORT_LOG="$SCRATCH_BASE/import.log"
	MAIN_LOG="$SCRATCH_BASE/main.log"
	PROOF_LOG="$SCRATCH_BASE/proof.log"
	SCRATCH="$SCRATCH_BASE"
	touch "$IMPORT_LOG" "$MAIN_LOG" "$PROOF_LOG" || exit 2
fi
mkdir -p "$RUN_CACHE/cache" "$RUN_CACHE/config" "$RUN_CACHE/data" "$RUN_CACHE/tmp" || exit 2

OVERALL_DEADLINE=$(( $(date +%s) + OVERALL_TIMEOUT ))

# Portable watchdog: stock macOS has no coreutils timeout.
run_bounded() {
	_limit=$1
	_out=$2
	shift 2
	"$@" >>"$_out" 2>&1 &
	_pid=$!
	(
		sleep "$_limit" 2>/dev/null
		kill -TERM "$_pid" 2>/dev/null
		sleep 3 2>/dev/null
		kill -KILL "$_pid" 2>/dev/null
	) >/dev/null 2>&1 &
	_watch=$!
	wait "$_pid" 2>/dev/null
	_rc=$?
	kill "$_watch" 2>/dev/null
	wait "$_watch" 2>/dev/null
	return "$_rc"
}

# Pick the smaller of the per-engine cap and the remaining outer budget.
remaining_limit() {
	_now=$(date +%s)
	_remaining=$(( OVERALL_DEADLINE - _now ))
	if [ "$_remaining" -le 0 ]; then
		return 1
	fi
	if [ "$_remaining" -lt "$TIMEOUT" ]; then
		echo "$_remaining"
	else
		echo "$TIMEOUT"
	fi
	return 0
}

error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

echo "[audio-playback] engine probe: $GODOT_BIN"
: >"$IMPORT_LOG"
_limit=$(remaining_limit) || {
	echo "FAIL: outer ${OVERALL_TIMEOUT}s budget exhausted before engine probe" >&2
	exit 1
}
run_bounded "$_limit" "$IMPORT_LOG" "$GODOT_BIN" --version
probe_status=$?
version_output=$(cat "$IMPORT_LOG")
actual_version=$(printf '%s\n' "$version_output" | tail -n 1)
if [ "$probe_status" -ne 0 ]; then
	echo "FAIL: engine --version failed or timed out (status $probe_status)" >&2
	cat "$IMPORT_LOG" >&2
	exit 2
fi
case "$actual_version" in
	*"$PINNED_VERSION_STRING"*) ;;
	*)
	echo "FAIL: engine is not the pinned $PINNED_VERSION_STRING (got: $actual_version)" >&2
	exit 2 ;;
esac

extra_rsync=""
extra_tar=""
case "${PRIVATE_REL}" in
	*" "*|*"$(printf '\t')") ;;
	?*) extra_rsync="--exclude=$PRIVATE_REL"; extra_tar="--exclude=./$PRIVATE_REL" ;;
esac

echo "[audio-playback] staging isolated copy in $PRIVATE_CANON"
if command -v rsync >/dev/null 2>&1; then
	# shellcheck disable=SC2086
	rsync -a $extra_rsync \
		--exclude='.git' \
		--exclude='.godot' \
		--exclude='work' \
		--exclude='tools/ci/out' \
		--exclude='__pycache__' \
		--exclude='*.pyc' \
		"$PROJECT_DIR"/ "$PRIVATE_CANON"/ || { echo "FAIL: rsync staging failed" >&2; exit 2; }
else
	# shellcheck disable=SC2086
	( cd "$PROJECT_DIR" && tar --exclude=./.git --exclude=./.godot --exclude=./work \
		--exclude=./tools/ci/out --exclude=__pycache__ $extra_tar -cf - . ) \
		| ( cd "$PRIVATE_CANON" && tar -xf - ) \
		|| { echo "FAIL: tar staging failed" >&2; exit 2; }
fi

status=0
note_log() {
	if [ -n "$LOG_FILE" ]; then
		cp "$1" "$LOG_FILE" 2>/dev/null || true
	fi
}

echo "[audio-playback] headless import"
: >"$IMPORT_LOG"
_limit=$(remaining_limit) || {
	echo "FAIL: outer ${OVERALL_TIMEOUT}s budget exhausted before import" >&2
	exit 1
}
run_bounded "$_limit" "$IMPORT_LOG" env \
	XDG_CACHE_HOME="$RUN_CACHE/cache" \
	XDG_CONFIG_HOME="$RUN_CACHE/config" \
	XDG_DATA_HOME="$RUN_CACHE/data" \
	TMPDIR="$RUN_CACHE/tmp" \
	"$GODOT_BIN" --headless --path "$PRIVATE_CANON" --import
import_status=$?
cat "$IMPORT_LOG"
if [ "$import_status" -ne 0 ]; then
	echo "FAIL: headless import failed (status $import_status)" >&2
	exit 1
fi
if grep -nE "$error_re" "$IMPORT_LOG"; then
	echo "FAIL: import log reported engine errors" >&2
	exit 1
fi

echo "[audio-playback] running validator (case: $CASE_ID)"
: >"$MAIN_LOG"
_limit=$(remaining_limit) || {
	echo "FAIL: outer ${OVERALL_TIMEOUT}s budget exhausted before validator" >&2
	exit 1
}
run_bounded "$_limit" "$MAIN_LOG" env \
	XDG_CACHE_HOME="$RUN_CACHE/cache" \
	XDG_CONFIG_HOME="$RUN_CACHE/config" \
	XDG_DATA_HOME="$RUN_CACHE/data" \
	TMPDIR="$RUN_CACHE/tmp" \
	"$GODOT_BIN" --headless --fixed-fps 60 \
	--path "$PRIVATE_CANON" \
	--script res://tools/audio_playback_lab/validate_audio_playback.gd "--case=$CASE_ID"
main_status=$?
cat "$MAIN_LOG"
note_log "$MAIN_LOG"
if grep -nE "$error_re" "$MAIN_LOG"; then
	echo "FAIL: engine reported a script error" >&2
	status=1
fi
if ! grep -q '^CHECKS_TOTAL=' "$MAIN_LOG"; then
	echo "FAIL: validator produced no CHECKS_TOTAL line" >&2
	status=1
fi
failed_count=$(sed -n 's/.*CHECKS_FAILED=//p' "$MAIN_LOG" | tail -n 1)
if [ "$failed_count" != "0" ]; then
	echo "FAIL: validator reported CHECKS_FAILED=$failed_count" >&2
	status=1
fi
if [ "$main_status" -ne 0 ]; then
	echo "FAIL: validator exited $main_status" >&2
	status=1
fi

echo "[audio-playback] deliberate failure proof"
: >"$PROOF_LOG"
_limit=$(remaining_limit) || {
	echo "FAIL: outer ${OVERALL_TIMEOUT}s budget exhausted before failure proof" >&2
	exit 1
}
run_bounded "$_limit" "$PROOF_LOG" env \
	XDG_CACHE_HOME="$RUN_CACHE/cache" \
	XDG_CONFIG_HOME="$RUN_CACHE/config" \
	XDG_DATA_HOME="$RUN_CACHE/data" \
	TMPDIR="$RUN_CACHE/tmp" \
	"$GODOT_BIN" --headless --fixed-fps 60 \
	--path "$PRIVATE_CANON" \
	--script res://tools/audio_playback_lab/validate_audio_playback.gd "--case=intentional_failure"
proof_status=$?
cat "$PROOF_LOG"
if [ "$proof_status" -eq 0 ]; then
	echo "FAIL: intentional-failure case exited 0; failure detection is not proven" >&2
	status=1
fi
if ! grep -q '^INTENTIONAL_FAILURE_PROOF ' "$PROOF_LOG"; then
	echo "FAIL: intentional-failure proof printed no proof line" >&2
	status=1
else
	proof_line=$(grep '^INTENTIONAL_FAILURE_PROOF ' "$PROOF_LOG" | tail -n 1)
	case "$proof_line" in
		*'"pass":false'*) ;;
		*)
			echo "FAIL: intentional-failure proof did not report pass=false" >&2
			status=1
			;;
	esac
fi

if [ "$status" -eq 0 ]; then
	echo "[audio-playback] PASS (isolated project: $PRIVATE_CANON)"
else
	echo "[audio-playback] FAIL (isolated project: $PRIVATE_CANON)" >&2
fi
exit "$status"
