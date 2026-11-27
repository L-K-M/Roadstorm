#!/bin/sh
# Roadstorm Racer! - M1.2 handling laboratory validation runner.
#
# Ownership: tools/handling_lab/**. Runs the headless validator from an
# isolated copy of the project so the live checkout's .godot cache is never
# written. Every Godot invocation, including the --version probe, is bounded by
# --timeout.
#
# Explicit --private-dir handling is create-only:
#   * an existing file, directory, symlink or dangling symlink is refused
#     before any copy, and is left untouched;
#   * the destination is reserved with an atomic mkdir, so a concurrent creator
#     cannot turn it into an occupied path;
#   * staging never uses --delete and never removes a caller supplied path;
#   * a destination inside --project is rejected unless it lies under the
#     repository's ignored work/ scratch root, which staging excludes anyway;
#     the destination's own relative path is additionally excluded from the
#     copy so recursion is structurally impossible.
#
# Usage:
#   tools/handling_lab/run_validation.sh
#   tools/handling_lab/run_validation.sh --project DIR --private-dir FRESH_DIR
#                         [--godot BIN] [--timeout SECONDS] [--log FILE]
#
# Exit codes: 0 = all checks passed, 1 = a check failed or output was invalid,
# 2 = the runner refused unsafe inputs or could not execute the pinned engine.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_PROJECT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

PROJECT_DIR="$DEFAULT_PROJECT"
GODOT_BIN="godot"
PRIVATE_DIR=""
TIMEOUT="90"
LOG_FILE=""
KEEP_SCRATCH="${KEEP_SCRATCH:-0}"

SCRATCH=""
RUN_CACHE=""
RUN_OUTPUT=""
PROJECT_CANON=""
PRIVATE_CANON=""
PRIVATE_REL=""

usage() {
	cat <<'EOF'
Usage: run_validation.sh [--project DIR] [--godot BIN]
                         [--private-dir FRESH_DIR] [--timeout SECONDS]
                         [--log FILE]

--private-dir must not already exist. The runner reserves it with an atomic
mkdir and stages the project into it. Omit it to use an auto-created,
auto-cleaned temporary copy.
EOF
}

cleanup() {
	if [ -n "$RUN_CACHE" ]; then
		rm -rf "$RUN_CACHE"
	fi
	if [ -n "$RUN_OUTPUT" ]; then
		rm -f "$RUN_OUTPUT"
	fi
	if [ "${KEEP_SCRATCH:-0}" != "1" ] && [ -n "$SCRATCH" ]; then
		rm -rf "$SCRATCH"
	fi
}
trap cleanup EXIT HUP INT TERM

while [ $# -gt 0 ]; do
	case "$1" in
		--project)
			if [ $# -lt 2 ]; then
				echo "missing value for $1" >&2
				exit 2
			fi
			PROJECT_DIR="$2"; shift 2 ;;
		--godot)
			if [ $# -lt 2 ]; then
				echo "missing value for $1" >&2
				exit 2
			fi
			GODOT_BIN="$2"; shift 2 ;;
		--private-dir)
			if [ $# -lt 2 ]; then
				echo "missing value for $1" >&2
				exit 2
			fi
			PRIVATE_DIR="$2"; shift 2 ;;
		--timeout)
			if [ $# -lt 2 ]; then
				echo "missing value for $1" >&2
				exit 2
			fi
			TIMEOUT="$2"; shift 2 ;;
		--log)
			if [ $# -lt 2 ]; then
				echo "missing value for $1" >&2
				exit 2
			fi
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
	# Run in a subshell so resolving a path never changes the runner cwd.
	( CDPATH= cd -- "$1" 2>/dev/null && pwd -P )
}

reserve_private_dir() {
	# $1 = project directory, $2 = requested private directory ("" = default)
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
		PRIVATE_DIR="$2"
		PRIVATE_CANON="$parent_canon/$base"
	else
		SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/handling-lab-XXXXXX") || {
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
				work|work/*)
					# The repository's ignored scratch root. Staging excludes
					# it, and the destination path is excluded again below.
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

# Bound the version probe like every other Godot invocation.
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

RUN_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/handling-lab-cache-XXXXXX") || exit 2
mkdir -p "$RUN_CACHE/cache" "$RUN_CACHE/config" "$RUN_CACHE/data" "$RUN_CACHE/tmp"
RUN_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/handling-lab-output-XXXXXX") || exit 2

status=0
env \
	XDG_CACHE_HOME="$RUN_CACHE/cache" \
	XDG_CONFIG_HOME="$RUN_CACHE/config" \
	XDG_DATA_HOME="$RUN_CACHE/data" \
	TMPDIR="$RUN_CACHE/tmp" \
	timeout "$TIMEOUT" "$GODOT_BIN" --headless --fixed-fps 60 \
	--path "$PRIVATE_DIR" \
	--script res://tools/handling_lab/validate_handling_lab.gd \
	>"$RUN_OUTPUT" 2>&1 || status=$?

cat "$RUN_OUTPUT"
if [ -n "$LOG_FILE" ]; then
	cp "$RUN_OUTPUT" "$LOG_FILE" || status=1
fi

if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|^ERROR:|^USER ERROR:' "$RUN_OUTPUT"; then
	echo "FAIL: engine reported a script error" >&2
	status=1
fi

if ! grep -q '^CHECKS_TOTAL=' "$RUN_OUTPUT"; then
	echo "FAIL: validator produced no CHECKS_TOTAL line" >&2
	status=1
fi

FAILED_COUNT=$(sed -n 's/.*CHECKS_FAILED=//p' "$RUN_OUTPUT" | tail -n 1)
if [ "$FAILED_COUNT" != "0" ]; then
	echo "FAIL: validator reported FAILED=$FAILED_COUNT" >&2
	status=1
fi

if [ "$status" -eq 0 ]; then
	echo "[run-validation] PASS (isolated project: $PRIVATE_DIR)"
else
	echo "[run-validation] FAIL (isolated project: $PRIVATE_DIR)" >&2
fi

exit "$status"
