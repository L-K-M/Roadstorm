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
#      Pass --skip-windowed to run probe 1 only (no window is ever opened).
#
# Usage:
#   launch_macos_app.sh --app <path.app|path.zip> [--out <dir>]
#                       [--quit-after N] [--windowed-seconds N] [--skip-windowed]
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
SKIP_WINDOWED=0
LAUNCH_TIMEOUT=120
SIG_RESULT="not-checked"
EXECUTABLE_EXECUTED=false
WINDOWED_RESULT="not-requested"
SCREENSHOT_RESULT="not-attempted"

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
	--skip-windowed) SKIP_WINDOWED=1; shift ;;
	--timeout) [ $# -ge 2 ] || die 2 "--timeout needs seconds"; LAUNCH_TIMEOUT="$2"; shift 2 ;;
	--timeout=*) LAUNCH_TIMEOUT="${1#--timeout=}"; shift ;;
	-h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) die 2 "unknown argument: $1" ;;
	esac
done

[ -n "$APP_IN" ] || die 2 "--app <path.app|path.zip> is required"
[ -e "$APP_IN" ] || die 2 "package not found: $APP_IN"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rs-maclaunch.XXXXXX")" || die 2 "could not create a temp dir"
# WORK is intentionally NOT deleted on exit. A recursive delete through a
# mutable pathname could remove a concurrently replaced foreign tree; the
# bounded extraction is left for inspection (see README). The tool prints its
# location before exiting.

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
if ! _es_create_exclusive "$SIG_LOG" ""; then
	die 2 "cannot create $SIG_LOG exclusively (refusing to overwrite an existing path)"
fi
rc=0
sig_rc=0
codesign -dv --verbose=2 "$APP" >>"$SIG_LOG" 2>&1 || sig_rc=$?
if [ "$sig_rc" -ne 0 ]; then
	SIG_RESULT="check-failed"
	rc=1
	log "codesign check FAILED (exit $sig_rc); signature is NOT verified; see $SIG_LOG"
elif grep -qi 'adhoc' "$SIG_LOG"; then
	SIG_RESULT="ad-hoc"
	log "signature: AD-HOC (unnotarized) - observed in $SIG_LOG"
else
	SIG_RESULT="unexpected"
	rc=1
	log "signature: no adhoc marker in $SIG_LOG; NOT claimed as verified"
fi

# --- 1. headless launch (validates signature on exec; boots the shell) -------
HEAD_LOG="$OUT_DIR/macos-launch-headless.txt"
log "headless launch: $EXE --headless --quit-after $QUIT_AFTER"
es_run_bounded "$LAUNCH_TIMEOUT" "$HEAD_LOG" -- "$EXE" --headless --quit-after "$QUIT_AFTER"
hstatus=$?
if [ "$hstatus" -eq 0 ]; then EXECUTABLE_EXECUTED=true; fi
log "headless exit status: $hstatus (executable executed: $EXECUTABLE_EXECUTED)"
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
if [ "$SKIP_WINDOWED" -eq 1 ]; then
	log "windowed launch SKIPPED (--skip-windowed): the headless probe above is the"
	log "launch evidence for this run; no GUI window is opened"
	WINDOWED_RESULT="skipped"
	SCREENSHOT_RESULT="not-attempted (headless-only probe)"
	WIN_LOG="$OUT_DIR/macos-launch-windowed.txt"
	if ! _es_create_exclusive "$WIN_LOG" ""; then
		die 2 "cannot create $WIN_LOG exclusively"
	fi
	printf 'windowed launch skipped (--skip-windowed); headless probe is the launch evidence\n' >>"$WIN_LOG"
else
WIN_LOG="$OUT_DIR/macos-launch-windowed.txt"
if ! _es_create_exclusive "$WIN_LOG" ""; then
	die 2 "cannot create $WIN_LOG exclusively"
fi
SHOT="$OUT_DIR/macos-launch-windowed.png"
if [ -e "$SHOT" ] || [ -L "$SHOT" ]; then
	die 2 "screenshot path already exists (refusing to overwrite): $SHOT"
fi
log "windowed launch: $EXE (bounded ${WINDOWED_SECONDS}s, timeout ${LAUNCH_TIMEOUT}s)"
"$EXE" >>"$WIN_LOG" 2>&1 &
wpid=$!
alive=0
i=0
while [ "$i" -lt "$WINDOWED_SECONDS" ]; do
	sleep 1
	i=$((i + 1))
	if kill -0 "$wpid" 2>/dev/null; then alive=1; else break; fi
done
if [ "$alive" -eq 1 ]; then
	WINDOWED_RESULT="ran"
	log "windowed GUI running after ${WINDOWED_SECONDS}s"
	if command -v screencapture >/dev/null 2>&1; then
		if screencapture -x "$SHOT" 2>/dev/null && [ -s "$SHOT" ]; then
			SCREENSHOT_RESULT="captured"
			log "screenshot captured: $SHOT ($(wc -c <"$SHOT" | tr -d ' ') bytes)"
		else
			SCREENSHOT_RESULT="missing"
			log "screenshot was NOT produced; the full probe cannot pass"
			rc=1
		fi
	else
		SCREENSHOT_RESULT="tool-unavailable"
		log "screencapture is unavailable; the full probe cannot pass"
		rc=1
	fi
else
	WINDOWED_RESULT="failed"
	SCREENSHOT_RESULT="not-attempted (windowed failed)"
	log "windowed GUI exited before ${WINDOWED_SECONDS}s; the full probe cannot pass"
	rc=1
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
fi

# Evidence block consumed by run_export_smoke.sh. Claims are made only from
# these observed fields; nothing below is inferred from the probe name alone.
if [ "$SKIP_WINDOWED" -eq 1 ]; then _lp=headless; else _lp=full; fi
printf 'LAUNCH_PROBE=%s\n' "$_lp"
printf 'HEADLESS_EXIT=%s\n' "$hstatus"
printf 'WINDOWED=%s\n' "$WINDOWED_RESULT"
printf 'SCREENSHOT=%s\n' "$SCREENSHOT_RESULT"
printf 'SIGNATURE=%s\n' "$SIG_RESULT"
printf 'EXECUTABLE_EXECUTED=%s\n' "$EXECUTABLE_EXECUTED"
if [ "$rc" -eq 0 ]; then
	printf 'VERDICT=PASS\n'
else
	printf 'VERDICT=FAIL\n'
fi
log "temporary extraction retained for inspection: $WORK"
exit "$rc"
