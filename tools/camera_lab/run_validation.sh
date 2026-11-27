#!/bin/sh
# Roadstorm Racer! - M1.5 camera-rig validation runner.
#
# Ownership: tools/camera_lab/**. Runs the headless CameraRig validator from an
# isolated copy of the project so the live checkout's .godot cache is never
# written. Every Godot invocation, including the version probe and the resource
# import, is bounded by --timeout. The runner runs two bounded cases:
#   * the normal pass case (exit 0, CHECKS_FAILED=0);
#   * the deliberate-failure proof (`--expect-failure`, nonzero exit and
#     CHECKS_FAILED greater than zero).
#
# It fails when Godot logs SCRIPT ERROR / Parse Error / ERROR: / USER ERROR:
# even if the engine exit status is zero, when CHECKS_TOTAL is absent, or when
# the reported failure count does not match the expected case.
#
# Explicit --private-dir handling is create-only and side-effect-free on
# refusal:
#   * an existing file, directory, symlink or dangling symlink is refused
#     before any copy, and is left untouched;
#   * the destination's parent must already exist and is never created, so an
#     unsafe destination under --project cannot leave a partially created path;
#   * the destination itself is reserved with an atomic mkdir;
#   * staging never uses --delete and never removes a caller supplied path;
#   * a destination inside --project is rejected unless it lies under the
#     repository's ignored work/ scratch root; the destination's own relative
#     path is excluded from the copy as well.
#
# Usage:
#   tools/camera_lab/run_validation.sh
#   tools/camera_lab/run_validation.sh --project DIR --private-dir FRESH_DIR
#                         [--godot BIN] [--timeout SECONDS] [--log FILE]
#
# Exit codes: 0 = every case passed, 1 = a case failed or output was invalid,
# 2 = the runner refused unsafe inputs or could not execute the pinned engine.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_PROJECT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

PROJECT_DIR="$DEFAULT_PROJECT"
GODOT_BIN="godot"
PRIVATE_DIR=""
TIMEOUT="120"
LOG_FILE=""
KEEP_SCRATCH="${KEEP_SCRATCH:-0}"

SCRATCH=""
RUN_CACHE=""
RUN_OUTPUT=""
COMBINED_LOG=""
PROJECT_CANON=""
PRIVATE_CANON=""
PRIVATE_REL=""
CASES_RUN=0
CASES_FAIL=0

usage() {
	cat <<'EOF'
Usage: run_validation.sh [--project DIR] [--godot BIN]
                         [--private-dir FRESH_DIR] [--timeout SECONDS]
                         [--log FILE]

Runs the CameraRig pass case and the --expect-failure proof from an isolated
copy. --private-dir must not already exist, and its parent directory must
already exist (the parent is never created); the runner reserves the
destination with an atomic mkdir and stages the project into it. Omit it to use
an auto-created, auto-cleaned temporary copy.
EOF
}

cleanup() {
	if [ -n "$RUN_CACHE" ]; then
		rm -rf "$RUN_CACHE"
	fi
	if [ -n "$RUN_OUTPUT" ]; then
		rm -f "$RUN_OUTPUT"
	fi
	if [ -n "$COMBINED_LOG" ]; then
		rm -f "$COMBINED_LOG"
	fi
	if [ "${KEEP_SCRATCH:-0}" != "1" ] && [ -n "$SCRATCH" ]; then
		rm -rf "$SCRATCH"
	fi
}
trap cleanup EXIT HUP INT TERM

while [ $# -gt 0 ]; do
	case "$1" in
		--project)
			if [ $# -lt 2 ]; then echo "missing value for $1" >&2; exit 2; fi
			PROJECT_DIR="$2"; shift 2 ;;
		--godot)
			if [ $# -lt 2 ]; then echo "missing value for $1" >&2; exit 2; fi
			GODOT_BIN="$2"; shift 2 ;;
		--private-dir)
			if [ $# -lt 2 ]; then echo "missing value for $1" >&2; exit 2; fi
			PRIVATE_DIR="$2"; shift 2 ;;
		--timeout)
			if [ $# -lt 2 ]; then echo "missing value for $1" >&2; exit 2; fi
			TIMEOUT="$2"; shift 2 ;;
		--log)
			if [ $# -lt 2 ]; then echo "missing value for $1" >&2; exit 2; fi
			LOG_FILE="$2"; shift 2 ;;
		-h|--help)
			usage; exit 0 ;;
		*)
			echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
	esac
done

if [ ! -d "$PROJECT_DIR" ]; then
	echo "FAIL: --project is not a directory: $PROJECT_DIR" >&2
	exit 2
fi
if [ ! -r "$PROJECT_DIR/project.godot" ]; then
	echo "FAIL: no readable project.godot under $PROJECT_DIR" >&2
	exit 2
fi

PINNED_VERSION_STRING="4.7.2.stable.official.ed1daf0bf"
if [ -r "$PROJECT_DIR/tools/toolchain/pin/engine.txt" ]; then
	PINNED_FROM_FILE=$(sed -n 's/^version_string=//p' "$PROJECT_DIR/tools/toolchain/pin/engine.txt" | head -n 1)
	if [ -n "$PINNED_FROM_FILE" ]; then
		PINNED_VERSION_STRING="$PINNED_FROM_FILE"
	fi
fi

canonical_dir() {
	( CDPATH= cd -- "$1" 2>/dev/null && pwd -P )
}

reserve_private_dir() {
	PROJECT_CANON=$(canonical_dir "$1") || {
		echo "FAIL: cannot resolve --project $1" >&2
		exit 2
	}
	if [ -n "$2" ]; then
		if [ -e "$2" ] || [ -L "$2" ]; then
			echo "FAIL: --private-dir already exists; refusing to modify it: $2" >&2
			exit 2
		fi
		parent=$(dirname -- "$2")
		base=$(basename -- "$2")
		# Require an existing parent: no parent directory is ever created here,
		# so a refused containment check cannot leave anything behind.
		parent_canon=$(canonical_dir "$parent") || {
			echo "FAIL: --private-dir parent does not exist or is not a directory: $parent" >&2
			exit 2
		}
		PRIVATE_DIR="$2"
		PRIVATE_CANON="$parent_canon/$base"
	else
		SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/camera-lab-XXXXXX") || {
			echo "FAIL: cannot create default scratch directory" >&2
			exit 2
		}
		PRIVATE_DIR="$SCRATCH/project"
		PRIVATE_CANON="$(canonical_dir "$SCRATCH")/project"
	fi

	case "$PRIVATE_CANON" in
		"$PROJECT_CANON"|"$PROJECT_CANON"/*)
			PRIVATE_REL=${PRIVATE_CANON#"$PROJECT_CANON"/}
			case "$PRIVATE_REL" in
				work|work/*) ;;
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

	if [ -n "$2" ]; then
		if ! mkdir "$PRIVATE_DIR" 2>/dev/null; then
			echo "FAIL: cannot atomically reserve fresh --private-dir: $PRIVATE_DIR" >&2
			exit 2
		fi
	else
		mkdir "$PRIVATE_DIR" 2>/dev/null || {
			echo "FAIL: cannot create default private dir: $PRIVATE_DIR" >&2
			exit 2
		}
	fi
}

reserve_private_dir "$PROJECT_DIR" "$PRIVATE_DIR"

PROBE_STATUS=0
VERSION_OUTPUT=$(timeout "$TIMEOUT" "$GODOT_BIN" --version 2>&1) || PROBE_STATUS=$?
ACTUAL_VERSION=$(printf '%s\n' "$VERSION_OUTPUT" | tail -n 1)
if [ "$PROBE_STATUS" -ne 0 ]; then
	echo "FAIL: engine --version failed or timed out (status $PROBE_STATUS)" >&2
	exit 2
fi
case "$ACTUAL_VERSION" in
	*"$PINNED_VERSION_STRING"*) ;;
	*)
		echo "FAIL: engine $GODOT_BIN is not the pinned $PINNED_VERSION_STRING (got: $ACTUAL_VERSION)" >&2
		exit 2 ;;
esac

extra_rsync=""
extra_tar=""
case "${PRIVATE_REL}" in
	*" "*|*"$(printf '\t')") ;;
	?*) extra_rsync="--exclude=$PRIVATE_REL"; extra_tar="--exclude=./$PRIVATE_REL" ;;
esac

echo "[run-validation] staging isolated copy in $PRIVATE_DIR"
if command -v rsync >/dev/null 2>&1; then
	# shellcheck disable=SC2086
	rsync -a $extra_rsync \
		--exclude='.git' \
		--exclude='.godot' \
		--exclude='work' \
		--exclude='__pycache__' \
		--exclude='*.pyc' \
		"$PROJECT_DIR"/ "$PRIVATE_DIR"/ || { echo "FAIL: rsync staging failed" >&2; exit 2; }
else
	# shellcheck disable=SC2086
	( cd "$PROJECT_DIR" && tar --exclude=./.git --exclude=./.godot --exclude=./work \
		--exclude=__pycache__ $extra_tar -cf - . ) | ( cd "$PRIVATE_DIR" && tar -xf - ) \
		|| { echo "FAIL: tar staging failed" >&2; exit 2; }
fi

RUN_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/camera-lab-cache-XXXXXX") || exit 2
# Normalise the cache path: a TMPDIR with a trailing slash yields duplicate
# separators that make the pinned engine fail to resolve its user-data path.
RUN_CACHE=$(CDPATH= cd -- "$RUN_CACHE" 2>/dev/null && pwd -P) || exit 2
mkdir -p "$RUN_CACHE/cache" "$RUN_CACHE/config" "$RUN_CACHE/data" "$RUN_CACHE/tmp"
RUN_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/camera-lab-output-XXXXXX") || exit 2
COMBINED_LOG=$(mktemp "${TMPDIR:-/tmp}/camera-lab-log-XXXXXX") || exit 2

IMPORT_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/camera-lab-import-XXXXXX") || exit 2
IMPORT_STATUS=0
env \
	XDG_CACHE_HOME="$RUN_CACHE/cache" \
	XDG_CONFIG_HOME="$RUN_CACHE/config" \
	XDG_DATA_HOME="$RUN_CACHE/data" \
	TMPDIR="$RUN_CACHE/tmp" \
	timeout "$TIMEOUT" "$GODOT_BIN" --headless --path "$PRIVATE_DIR" --import \
	>"$IMPORT_OUTPUT" 2>&1 || IMPORT_STATUS=$?
cat "$IMPORT_OUTPUT"
if [ "$IMPORT_STATUS" -ne 0 ]; then
	echo "FAIL: resource import exited $IMPORT_STATUS" >&2
	exit 1
fi
if grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:|USER ERROR' "$IMPORT_OUTPUT"; then
	echo "FAIL: resource import reported a script error" >&2
	exit 1
fi
rm -f "$IMPORT_OUTPUT"

run_case() {
	_label="$1"
	_expect_failure="$2"
	_status=0
	if [ "$_expect_failure" -eq 1 ]; then
		env \
			XDG_CACHE_HOME="$RUN_CACHE/cache" \
			XDG_CONFIG_HOME="$RUN_CACHE/config" \
			XDG_DATA_HOME="$RUN_CACHE/data" \
			TMPDIR="$RUN_CACHE/tmp" \
			timeout "$TIMEOUT" "$GODOT_BIN" --headless --fixed-fps 60 \
			--path "$PRIVATE_DIR" \
			--script res://tools/camera_lab/validate_camera_rig.gd -- --expect-failure \
			>"$RUN_OUTPUT" 2>&1 || _status=$?
	else
		env \
			XDG_CACHE_HOME="$RUN_CACHE/cache" \
			XDG_CONFIG_HOME="$RUN_CACHE/config" \
			XDG_DATA_HOME="$RUN_CACHE/data" \
			TMPDIR="$RUN_CACHE/tmp" \
			timeout "$TIMEOUT" "$GODOT_BIN" --headless --fixed-fps 60 \
			--path "$PRIVATE_DIR" \
			--script res://tools/camera_lab/validate_camera_rig.gd \
			>"$RUN_OUTPUT" 2>&1 || _status=$?
	fi

	CASES_RUN=$((CASES_RUN + 1))
	cat "$RUN_OUTPUT"
	cat "$RUN_OUTPUT" >>"$COMBINED_LOG"

	_case_fail=""
	if grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:|USER ERROR' "$RUN_OUTPUT"; then
		_case_fail="engine reported a script error"
	fi
	if ! grep -q '^CHECKS_TOTAL=' "$RUN_OUTPUT"; then
		_case_fail="${_case_fail:+$_case_fail; }missing CHECKS_TOTAL line"
	fi
	_checks_total=$(sed -n 's/^CHECKS_TOTAL=\([0-9][0-9]*\).*/\1/p' "$RUN_OUTPUT" | tail -n 1)
	_checks_failed=$(sed -n 's/.*CHECKS_FAILED=\([0-9][0-9]*\).*/\1/p' "$RUN_OUTPUT" | tail -n 1)
	if [ -z "$_checks_total" ] || [ -z "$_checks_failed" ]; then
		_case_fail="${_case_fail:+$_case_fail; }unparseable CHECKS_TOTAL/CHECKS_FAILED"
	fi

	if [ "$_expect_failure" -eq 1 ]; then
		if [ "$_status" -eq 0 ]; then
			_case_fail="${_case_fail:+$_case_fail; }expected nonzero exit, got 0"
		fi
		if [ -n "$_checks_failed" ] && [ "$_checks_failed" -eq 0 ]; then
			_case_fail="${_case_fail:+$_case_fail; }expected CHECKS_FAILED>0, got 0"
		fi
	else
		if [ "$_status" -ne 0 ]; then
			_case_fail="${_case_fail:+$_case_fail; }engine exited $_status"
		fi
		if [ -n "$_checks_failed" ] && [ "$_checks_failed" -ne 0 ]; then
			_case_fail="${_case_fail:+$_case_fail; }validator reported FAILED=$_checks_failed"
		fi
	fi

	if [ -n "$_case_fail" ]; then
		CASES_FAIL=$((CASES_FAIL + 1))
		printf '[run-validation] %s: FAIL (%s)\n' "$_label" "$_case_fail" >&2
		return 1
	fi
	printf '[run-validation] %s: PASS (status=%s checks=%s failed=%s)\n' \
		"$_label" "$_status" "$_checks_total" "$_checks_failed"
	return 0
}

run_case "pass" 0
run_case "expect-failure" 1

if [ -n "$LOG_FILE" ]; then
	log_parent=$(dirname -- "$LOG_FILE")
	if [ ! -d "$log_parent" ]; then
		mkdir -p "$log_parent" || { echo "FAIL: cannot create log directory $log_parent" >&2; exit 1; }
	fi
	cp "$COMBINED_LOG" "$LOG_FILE" || { echo "FAIL: cannot write log $LOG_FILE" >&2; exit 1; }
fi

if [ "$CASES_FAIL" -ne 0 ]; then
	echo "[run-validation] FAIL ($CASES_FAIL of $CASES_RUN cases failed; isolated project: $PRIVATE_DIR)" >&2
	exit 1
fi
echo "[run-validation] PASS ($CASES_RUN cases; isolated project: $PRIVATE_DIR)"
exit 0
