#!/bin/sh
# Roadstorm Racer! - macOS export package launch test.
# Ownership: tools/export_smoke/** (PLAN.md "How agents execute the plan").
#
# Launches an exported macOS package CLEANLY and NONINTERACTIVELY and records
# whether it starts, runs the shell and exits without crashing. This is the
# only supported-platform launch test this host can perform: it is the macOS
# package. Windows and Linux packages are cross-exports that are NOT launched
# here (no target host); see run_export_smoke.sh.
#
# Two bounded probes, both killed by this tool (desktop hygiene: nothing is
# left running):
#   1. HEADLESS: run the .app's executable with --headless --quit-after N.
#      macOS validates the (ad-hoc) code signature on exec, so this proves the
#      signed bundle launches and the shell boots. Exits 0 on success.
#   2. WINDOWED: run the .app's executable for a few seconds so the GUI opens,
#      take a screenshot, then terminate it. Proves the graphical path renders.
#
# Usage:
#   launch_macos_app.sh --app <path.app|path.zip> [--out <dir>]
#                       [--quit-after N] [--windowed-seconds N]
#   GODOT-less: this only needs the exported package.
#
# Exit codes: 0 = package launched (headless clean exit AND windowed ran),
#             1 = the launch test failed, 2 = the tool could not run.
# Original project code under the Unlicense.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

APP_IN=""
OUT_DIR=""
QUIT_AFTER=40
WINDOWED_SECONDS=8

log() { printf '[launch-macos] %s\n' "$*"; }
die() { c="$1"; shift; log "FAIL: $*" >&2; exit "$c"; }

while [ $# -gt 0 ]; do
	case "$1" in
	--app) [ $# -ge 2 ] || die 2 "--app needs a path"; APP_IN="$2"; shift 2 ;;
	--app=*) APP_IN="${1#--app=}"; shift ;;
	--out) [ $# -ge 2 ] || die 2 "--out needs a directory"; OUT_DIR="$2"; shift 2 ;;
	--out=*) OUT_DIR="${1#--out=}"; shift ;;
	--quit-after) [ $# -ge 2 ] || die 2 "--quit-after needs a number"; QUIT_AFTER="$2"; shift 2 ;;
	--quit-after=*) QUIT_AFTER="${1#--quit-after=}"; shift ;;
	--windowed-seconds) [ $# -ge 2 ] || die 2 "--windowed-seconds needs a number"; WINDOWED_SECONDS="$2"; shift 2 ;;
	--windowed-seconds=*) WINDOWED_SECONDS="${1#--windowed-seconds=}"; shift ;;
	-h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) die 2 "unknown argument: $1" ;;
	esac
done

[ -n "$APP_IN" ] || die 2 "--app <path.app|path.zip> is required"
[ -e "$APP_IN" ] || die 2 "package not found: $APP_IN"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rs-maclaunch.XXXXXX")" || die 2 "could not create a temp dir"
trap 'rm -rf "$WORK"' EXIT

# Resolve a .app directory from either a .app or a .zip that contains one.
APP=""
case "$APP_IN" in
*.app) APP="$APP_IN" ;;
*.zip)
	unzip -q "$APP_IN" -d "$WORK/x" 2>/dev/null || die 1 "could not unzip $APP_IN"
	APP="$(find "$WORK/x" -maxdepth 2 -type d -name '*.app' | head -n 1)"
	;;
*) die 2 "expected a .app or a .zip, got: $APP_IN" ;;
esac
[ -n "$APP" ] && [ -d "$APP" ] || die 1 "no .app found in $APP_IN"

EXE="$(find "$APP/Contents/MacOS" -maxdepth 1 -type f | head -n 1)"
[ -n "$EXE" ] && [ -x "$EXE" ] || die 1 "no executable under $APP/Contents/MacOS"

if [ -z "$OUT_DIR" ]; then
	OUT_DIR="$(cd "$(dirname "$APP_IN")" && pwd)"
fi
mkdir -p "$OUT_DIR" 2>/dev/null || die 2 "cannot create output dir $OUT_DIR"

log "app:    $APP"
log "exe:    $EXE"

# Report the code signature (ad-hoc is expected; no Developer ID here).
SIG_LOG="$OUT_DIR/macos-codesign.txt"
codesign -dv --verbose=2 "$APP" >"$SIG_LOG" 2>&1
if grep -qi 'adhoc' "$SIG_LOG"; then
	log "signature: AD-HOC (unnotarized) - expected without Developer ID credentials"
else
	log "signature: see $SIG_LOG"
fi

rc=0

# --- 1. headless launch (validates signature on exec; boots the shell) -------
HEAD_LOG="$OUT_DIR/macos-launch-headless.txt"
log "headless launch: $EXE --headless --quit-after $QUIT_AFTER"
es_run_bounded 120 "$HEAD_LOG" -- "$EXE" --headless --quit-after "$QUIT_AFTER"
hstatus=$?
log "headless exit status: $hstatus"
if [ "$hstatus" -ne 0 ]; then
	log "headless launch did not exit cleanly; see $HEAD_LOG"
	rc=1
fi
if grep -Eqi 'SCRIPT ERROR|Parse Error|Failed to load script' "$HEAD_LOG"; then
	log "engine reported script errors during headless launch"
	rc=1
fi
if grep -q '\[boot\]' "$HEAD_LOG" && grep -q '\[menu\]' "$HEAD_LOG"; then
	log "headless launch booted the M0 shell and reached the menu"
else
	log "headless launch did not show the expected boot/menu handoff; see $HEAD_LOG"
	rc=1
fi

# --- 2. windowed launch (bounded; GUI render path) --------------------------
WIN_LOG="$OUT_DIR/macos-launch-windowed.txt"
SHOT="$OUT_DIR/macos-launch-windowed.png"
log "windowed launch: $EXE (bounded ${WINDOWED_SECONDS}s)"
"$EXE" >"$WIN_LOG" 2>&1 &
wpid=$!
alive=0
i=0
while [ "$i" -lt "$WINDOWED_SECONDS" ]; do
	sleep 1
	i=$((i + 1))
	if kill -0 "$wpid" 2>/dev/null; then alive=1; else break; fi
done
if [ "$alive" -eq 1 ]; then
	log "windowed GUI running after ${WINDOWED_SECONDS}s"
	if command -v screencapture >/dev/null 2>&1; then
		screencapture -x "$SHOT" 2>/dev/null && log "screenshot: $SHOT ($(es_sha256 "$SHOT" >/dev/null 2>&1; wc -c <"$SHOT" | tr -d ' ') bytes)"
	fi
else
	log "windowed GUI exited before ${WINDOWED_SECONDS}s (may still be fine for a headless CI host)"
fi
# Always terminate the GUI we launched (desktop hygiene).
kill "$wpid" 2>/dev/null
sleep 2
if kill -0 "$wpid" 2>/dev/null; then kill -9 "$wpid" 2>/dev/null; sleep 1; fi
if kill -0 "$wpid" 2>/dev/null; then log "WARNING: windowed process still alive"; else log "windowed process terminated"; fi
if pgrep -f "$(basename "$EXE")" >/dev/null 2>&1; then
	log "WARNING: a matching process is still running; leaving it for the operator"
else
	log "no leftover process for $(basename "$EXE")"
fi

if [ "$rc" -eq 0 ]; then
	log "PASS: macOS package launched cleanly"
else
	log "FAIL: macOS launch test did not pass"
fi
exit "$rc"
