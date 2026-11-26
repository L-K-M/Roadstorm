#!/bin/sh
# Roadstorm Racer! - boot smoke test runner (wrapper).
#
# Ownership: tools/smoke/**. This is the supported entry point for the M0
# headless boot smoke check (PLAN.md M0.2/M0.4, verification matrix T01).
#
# Why a wrapper: tools/smoke/boot_smoke.gd can only observe the engine from
# inside its own process. A runtime script error (an exception thrown from a
# script that still parses) prints SCRIPT ERROR / ERROR: lines but otherwise
# leaves the shell running, so the smoke check used to exit 0 while the log
# showed the error (Opus review finding 3). This wrapper therefore:
#   1. checks that the Godot binary is the exact pinned official build
#      (`godot --version` vs the version string recorded in
#      tools/toolchain/pin/engine.txt, mirrored below as a fallback);
#   2. runs the smoke check headless and captures stdout and stderr;
#   3. fails if the smoke check exits nonzero OR if the engine reported a
#      script error in its output.
#
# tools/smoke/fault_injection.sh proves the failing paths (parse error,
# runtime errors, detached script) on isolated snapshot copies.
#
# Usage:
#   tools/smoke/run_boot_smoke.sh                    run the check
#   tools/smoke/run_boot_smoke.sh --expect-failure   pass a user flag through
#   tools/smoke/run_boot_smoke.sh --project <dir>    check another checkout/snapshot
#   GODOT_BIN=/path/to/godot tools/smoke/run_boot_smoke.sh
#
# Arguments other than --project/--help are forwarded to the smoke script as
# user arguments (after godot's `--` separator).
#
# Exit codes: 0 = passed, 1 = a check failed, 2 = the wrapper could not run.
# Original project code under the Unlicense.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PROJECT_DIR="${PROJECT_DIR:-$DEFAULT_PROJECT_DIR}"
GODOT_BIN="${GODOT_BIN:-}"

# Mirrored from tools/toolchain/pin/engine.txt (version_string=...). The pin
# file is owned by tools/toolchain/** and is only read here, never written.
PINNED_VERSION_STRING="4.7.2.stable.official.ed1daf0bf"

# Engine-reported script errors. A clean run of this check prints none of
# these; tools/smoke/fault_injection.sh verifies that on every case.
ERROR_PATTERN='SCRIPT ERROR|Failed to load script|Parse Error|^ERROR:|^USER ERROR:'

log() {
	echo "[run-boot-smoke] $*"
}

die() {
	# die <exit-code> <message...>
	code="$1"
	shift
	log "FAIL: $*" >&2
	exit "$code"
}

# --- argument handling ------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
	--project)
		[ $# -ge 2 ] || die 2 "--project needs a directory argument"
		PROJECT_DIR="$2"
		shift 2
		;;
	--project=*)
		PROJECT_DIR="${1#--project=}"
		shift
		;;
	-h|--help)
		sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		# Everything else is a user argument for the smoke script.
		break
		;;
	esac
done

[ -n "$GODOT_BIN" ] || GODOT_BIN="$(command -v godot 2>/dev/null || true)"
[ -n "$GODOT_BIN" ] || die 2 "no Godot binary found; set GODOT_BIN"
[ -x "$GODOT_BIN" ] || [ "$GODOT_BIN" = "godot" ] || die 2 "'$GODOT_BIN' is not executable"
[ -d "$PROJECT_DIR" ] || die 2 "project directory '$PROJECT_DIR' does not exist"
[ -f "$PROJECT_DIR/project.godot" ] || die 2 "'$PROJECT_DIR' has no project.godot"
[ -f "$PROJECT_DIR/tools/smoke/boot_smoke.gd" ] || die 2 "'$PROJECT_DIR' has no tools/smoke/boot_smoke.gd"

LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/roadstorm-boot-smoke.XXXXXX" 2>/dev/null)" || die 2 "could not create a temporary log file"
trap 'rm -f "$LOG_FILE"' EXIT

# --- 1. exact pinned official build check -----------------------------------
actual_version="$("$GODOT_BIN" --version 2>/dev/null)" || actual_version=""
[ -n "$actual_version" ] || die 2 "could not run '$GODOT_BIN --version'"

PIN_FILE="$PROJECT_DIR/tools/toolchain/pin/engine.txt"
if [ -f "$PIN_FILE" ]; then
	recorded="$(sed -n 's/^version_string=//p' "$PIN_FILE" | head -n 1)"
	[ -n "$recorded" ] && PINNED_VERSION_STRING="$recorded"
fi
if [ "$actual_version" != "$PINNED_VERSION_STRING" ]; then
	log "engine reports version '$actual_version'" >&2
	die 1 "engine is not the pinned build '$PINNED_VERSION_STRING'"
fi
log "engine is the pinned build: $PINNED_VERSION_STRING"

# --- 2. run the smoke check headless ----------------------------------------
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --script res://tools/smoke/boot_smoke.gd -- "$@" >"$LOG_FILE" 2>&1
status=$?
cat "$LOG_FILE"

# --- 3. engine-reported script errors fail the check even on exit 0 ---------
if grep -Eq "$ERROR_PATTERN" "$LOG_FILE"; then
	log "the engine reported script errors:" >&2
	grep -En "$ERROR_PATTERN" "$LOG_FILE" >&2
	die 1 "engine output contains script errors (see above)"
fi

if [ "$status" -ne 0 ]; then
	die 1 "smoke check exited with status $status"
fi

log "PASS: boot smoke check passed with no script errors in the engine output"
exit 0
