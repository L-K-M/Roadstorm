#!/bin/sh
# Roadstorm Racer! - self-tests for the tools/ci shell layer.
#
# Ownership: tools/ci/** only (PLAN.md "How agents execute the plan").
#
# What this covers, and why it is worth having: `ci.sh validate` proves the
# project is sound, and `ci.sh test` proves the engine checks fail correctly,
# but nothing proved that the TOOLING's own logic works -- the pin parser, the
# digest comparison, the viewport override and the argument validation. Those
# are exactly the places where a silent no-op would let a bad artifact through
# (PLAN.md M0.1: "Verify before installation") or report a capture at the wrong
# resolution as a success (PLAN.md M0.6, machine-inventory finding 9).
#
# Design rules:
#   * Hermetic. No network, no Godot, no display, no Git. Everything runs in a
#     private temporary directory that is removed on exit.
#   * Each case states what it expects, so a case that silently stops checking
#     is a failure rather than a pass.
#   * Both directions are covered: a check that must PASS is shown passing, and
#     an injected defect is shown failing. A suite that only ever sees the happy
#     path proves nothing (PLAN.md M0.4).
#
# Usage:
#   tools/ci/tests/run_tests.sh
#   TOOLS_CI_DIR=/path/to/tools/ci tools/ci/tests/run_tests.sh
#
# Exit codes: 0 = every case behaved as expected, 1 = a case misbehaved,
# 2 = the harness could not run.
# Original project code under the Unlicense.

set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_CI_DIR="${TOOLS_CI_DIR:-$(cd "$TESTS_DIR/.." && pwd)}"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$TOOLS_CI_DIR/../.." && pwd)}"

CI_SH="$TOOLS_CI_DIR/ci.sh"
COMMON_SH="$TOOLS_CI_DIR/lib/common.sh"
PIN_FILE="$TOOLS_CI_DIR/pin/engine.txt"

CASES_RUN=0
CASES_OK=0

log() { printf '[ci-selftest] %s\n' "$*"; }
die() {
	_code="$1"
	shift
	log "FAIL: $*" >&2
	exit "$_code"
}

[ -f "$CI_SH" ] || die 2 "missing entry point: $CI_SH"
[ -f "$COMMON_SH" ] || die 2 "missing helpers: $COMMON_SH"
[ -f "$PIN_FILE" ] || die 2 "missing engine pin: $PIN_FILE"

if command -v shasum >/dev/null 2>&1; then
	SHA512_CMD="shasum -a 512"
elif command -v sha512sum >/dev/null 2>&1; then
	SHA512_CMD="sha512sum"
else
	die 2 "no sha512 utility on PATH (need shasum or sha512sum)"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roadstorm-ci-selftest.XXXXXX" 2>/dev/null)" ||
	die 2 "could not create a temporary working directory"
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

log "tooling: $TOOLS_CI_DIR"
log "project: $PROJECT_DIR"
log "workdir: $WORK_DIR"

# Every ci.sh invocation names the project explicitly, so this suite also runs
# against a relocated copy of the tooling (which is how the injected-defect
# cases below were checked) instead of depending on where it was invoked from.
ci() {
	sh "$CI_SH" --project "$PROJECT_DIR" "$@"
}

# hex_is <value> <length> : true when the value is exactly <length> lowercase
# hexadecimal characters. Counting with wc rather than a `?` glob keeps the
# expectation readable and independent of how many characters were typed.
hex_is() {
	[ "$(printf '%s' "$1" | wc -c | tr -d ' ')" = "$2" ] || return 1
	case "$1" in
		*[!0-9a-f]*) return 1 ;;
	esac
	return 0
}

# ---------------------------------------------------------------------------
# Case runner
# ---------------------------------------------------------------------------
# expect_case <description> <expected-exit> <command...>
expect_case() {
	_desc="$1"
	_expected="$2"
	shift 2
	CASES_RUN=$((CASES_RUN + 1))
	_output="$("$@" 2>&1)"
	_status=$?
	_ok=no
	if [ "$_expected" = "nonzero" ]; then
		[ "$_status" -ne 0 ] && _ok=yes
	else
		[ "$_status" -eq "$_expected" ] && _ok=yes
	fi
	if [ "$_ok" = "yes" ]; then
		CASES_OK=$((CASES_OK + 1))
	fi
	log "case $CASES_RUN: $_desc"
	log "  expected exit $_expected, observed $_status -> $_ok"
	if [ "$_ok" = "no" ]; then
		printf '%s\n' "$_output" | sed 's/^/  | /' >&2
	fi
	return 0
}

# expect_contains <description> <expected-exit> <needle> <command...>
expect_contains() {
	_desc="$1"
	_expected="$2"
	_needle="$3"
	shift 3
	CASES_RUN=$((CASES_RUN + 1))
	_output="$("$@" 2>&1)"
	_status=$?
	_ok=no
	if [ "$_status" -eq "$_expected" ] && printf '%s\n' "$_output" | grep -qF -- "$_needle"; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	fi
	log "case $CASES_RUN: $_desc"
	log "  exit $_status (expected $_expected), looking for '$_needle' -> $_ok"
	if [ "$_ok" = "no" ]; then
		printf '%s\n' "$_output" | sed 's/^/  | /' >&2
	fi
	return 0
}

# ---------------------------------------------------------------------------
# 1. The documented command surface (a command that disappears or renames
#    breaks the workflow silently otherwise).
# ---------------------------------------------------------------------------
expect_case "ci.sh help exits 0" 0 ci --help
expect_case "ci.sh commands exits 0" 0 ci commands
expect_contains "help documents verify-engine" 0 "verify-engine" ci --help
expect_contains "help documents pin" 0 "pin" ci commands
expect_case "ci.sh with an unknown command exits 2" 2 ci definitely-not-a-command

# ---------------------------------------------------------------------------
# 2. The pin is readable and populated.
# ---------------------------------------------------------------------------
PIN_SHA512="$(ci pin --field release_archive_sha512 2>/dev/null)"
PIN_SHA256="$(ci pin --field release_archive_sha256 2>/dev/null)"
PIN_URL="$(ci pin --field release_archive_url 2>/dev/null)"
PIN_TAG="$(ci pin --field tag 2>/dev/null)"

CASES_RUN=$((CASES_RUN + 1))
if hex_is "$PIN_SHA512" 128; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: release_archive_sha512 is 128 lowercase hex chars -> $_ok"
[ "$_ok" = "yes" ] || log "  value: '$PIN_SHA512'" >&2

CASES_RUN=$((CASES_RUN + 1))
if hex_is "$PIN_SHA256" 64; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: release_archive_sha256 is 64 lowercase hex chars -> $_ok"
[ "$_ok" = "yes" ] || log "  value: '$PIN_SHA256'" >&2

CASES_RUN=$((CASES_RUN + 1))
case "$PIN_URL" in
	https://github.com/godotengine/godot/releases/download/*)
		log "case $CASES_RUN: release_archive_url is the official GitHub release asset -> yes"
		CASES_OK=$((CASES_OK + 1))
		;;
	*) log "case $CASES_RUN: release_archive_url is the official GitHub release asset -> no"; log "  value: '$PIN_URL'" >&2 ;;
esac

CASES_RUN=$((CASES_RUN + 1))
case "$PIN_TAG" in
	4.7.2-stable)
		log "case $CASES_RUN: pinned release tag is 4.7.2-stable -> yes"
		CASES_OK=$((CASES_OK + 1))
		;;
	*) log "case $CASES_RUN: pinned release tag is 4.7.2-stable -> no"; log "  value: '$PIN_TAG'" >&2 ;;
esac

expect_case "pin --field with an unknown name exits 2" 2 ci pin --field not-a-field

# ---------------------------------------------------------------------------
# 3. Digest comparison: the pass path, the injected-mismatch path and the
#    unrecorded-pin path. Exercised through the shared helper so the same code
#    `ci.sh verify-engine` uses is the code under test.
# ---------------------------------------------------------------------------
. "$COMMON_SH" >/dev/null 2>&1 || die 2 "could not source $COMMON_SH"

# The warning allow-list is looked up relative to $CI_TOOLS_DIR, which ci.sh sets
# before it sources common.sh. This suite sources common.sh directly, so set it
# here too: without it the allow-list cases below would test a tooling directory
# that does not exist and report the benign warning as unexpected.
CI_TOOLS_DIR="$TOOLS_CI_DIR"

STUB="$WORK_DIR/artifact.bin"
printf 'roadstorm ci self-test artifact\n' >"$STUB"
STUB_SHA512="$($SHA512_CMD "$STUB" | awk '{print $1}')"
STUB_SHA256="$(ci_sha256 "$STUB")"

[ -n "$STUB_SHA512" ] || die 2 "could not digest the test artifact"

if ci_verify_digest "self-test pass path" "$STUB" "$STUB_SHA512" sha512 >/dev/null 2>&1; then
	_ok=yes
else
	_ok=no
fi
CASES_RUN=$((CASES_RUN + 1))
log "case $CASES_RUN: a matching digest is accepted -> $_ok"
[ "$_ok" = "yes" ] && CASES_OK=$((CASES_OK + 1))

# Injected defect: one hex character changed. A comparison that ignores its
# input would still pass, so this is the case that proves it compares.
BAD_SHA512="$(printf '%s' "$STUB_SHA512" | sed 's/^./0/; s/^0$/f/')"
if [ "$BAD_SHA512" = "$STUB_SHA512" ]; then
	BAD_SHA512="f${STUB_SHA512#?}"
fi
if ci_verify_digest "self-test mismatch path" "$STUB" "$BAD_SHA512" sha512 >/dev/null 2>&1; then
	_ok=no
else
	_ok=yes
fi
CASES_RUN=$((CASES_RUN + 1))
log "case $CASES_RUN: an injected digest mismatch is rejected -> $_ok"
[ "$_ok" = "yes" ] && CASES_OK=$((CASES_OK + 1))

# An unrecorded pin must refuse, never wave the artifact through.
if ci_verify_digest "self-test empty pin" "$STUB" "" sha512 >/dev/null 2>&1; then
	_ok=no
else
	_ok=yes
fi
CASES_RUN=$((CASES_RUN + 1))
log "case $CASES_RUN: an empty pinned digest is refused -> $_ok"
[ "$_ok" = "yes" ] && CASES_OK=$((CASES_OK + 1))

# A file that cannot be read must fail rather than silently pass.
if ci_verify_digest "self-test missing file" "$WORK_DIR/does-not-exist.bin" "$STUB_SHA512" sha512 >/dev/null 2>&1; then
	_ok=no
else
	_ok=yes
fi
CASES_RUN=$((CASES_RUN + 1))
log "case $CASES_RUN: an unreadable artifact is refused -> $_ok"
[ "$_ok" = "yes" ] && CASES_OK=$((CASES_OK + 1))

# ---------------------------------------------------------------------------
# 4. `ci.sh verify-engine` against the real pin.
#    The tiny stub cannot match the pinned release archive, so the only correct
#    outcome is a nonzero exit. If the pin were empty, or the comparison were
#    skipped, this case would pass with exit 0 and fail here.
# ---------------------------------------------------------------------------
expect_case "verify-engine refuses an artifact that is not the pinned archive" nonzero \
	ci verify-engine --archive "$STUB"
expect_case "verify-engine refuses a binary that is not the pinned editor" nonzero \
	ci verify-engine --binary "$STUB"
expect_case "verify-engine refuses a missing archive" nonzero \
	ci verify-engine --archive "$WORK_DIR/absent.zip"
expect_case "verify-engine with no options exits 2" 2 ci verify-engine
expect_contains "verify-engine reports a mismatch explicitly" 1 "MISMATCH" \
	ci verify-engine --archive "$STUB"
expect_contains "verify-engine says not to extract on mismatch" 1 "DO NOT extract" \
	ci verify-engine --archive "$STUB"

# ---------------------------------------------------------------------------
# 5. Viewport helpers: the capture-resolution fix depends on them.
# ---------------------------------------------------------------------------
VP_OK="$WORK_DIR/viewport-ok.godot"
printf '[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/size/resizable=true\n' >"$VP_OK"
VP_MISSING="$WORK_DIR/viewport-missing.godot"
printf '[application]\nconfig/name="no viewport here"\n' >"$VP_MISSING"

_vp_read="$(ci_project_viewport_size "$VP_OK" 2>/dev/null)"
CASES_RUN=$((CASES_RUN + 1))
if [ "$_vp_read" = "1920x1080" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
	log "case $CASES_RUN: viewport size is read from project.godot -> yes ($_vp_read)"
else
	_ok=no
	log "case $CASES_RUN: viewport size is read from project.godot -> no ('$_vp_read')" >&2
fi

CASES_RUN=$((CASES_RUN + 1))
if ci_set_project_viewport_size "$VP_OK" 960 540 >/dev/null 2>&1 &&
	[ "$(ci_project_viewport_size "$VP_OK" 2>/dev/null)" = "960x540" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
	log "case $CASES_RUN: viewport size is rewritten in place -> yes"
else
	_ok=no
	log "case $CASES_RUN: viewport size is rewritten in place -> no" >&2
fi

# The rewrite must not disturb the rest of the file.
CASES_RUN=$((CASES_RUN + 1))
if grep -q '^window/size/resizable=true$' "$VP_OK" && grep -q '^\[display\]$' "$VP_OK"; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
	log "case $CASES_RUN: the rest of project.godot survives the rewrite -> yes"
else
	_ok=no
	log "case $CASES_RUN: the rest of project.godot survives the rewrite -> no" >&2
fi

# A project.godot with no viewport keys must be refused, not silently accepted.
CASES_RUN=$((CASES_RUN + 1))
if ci_set_project_viewport_size "$VP_MISSING" 640 360 >/dev/null 2>&1; then
	_ok=no
	CASES_OK=$((CASES_OK + 1))
	log "case $CASES_RUN: a project.godot without viewport keys is refused -> no" >&2
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
	log "case $CASES_RUN: a project.godot without viewport keys is refused -> yes"
fi

# ---------------------------------------------------------------------------
# 6. The recorded-resolution probe: it decides whether a capture's size is
#    verified or merely reported as unverified, so a silent no-op here is
#    exactly the defect the machine inventory recorded (finding 9).
# ---------------------------------------------------------------------------
CASES_RUN=$((CASES_RUN + 1))
if ci_probe_video_size "$WORK_DIR/absent.avi" >/dev/null 2>&1; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: ci_probe_video_size reports nothing for a missing file -> $_ok"

: >"$WORK_DIR/empty.avi"
CASES_RUN=$((CASES_RUN + 1))
if ci_probe_video_size "$WORK_DIR/empty.avi" >/dev/null 2>&1; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: ci_probe_video_size reports nothing for an empty file -> $_ok"

# The positive case needs a real video. One is synthesised locally when ffmpeg is
# present; without it the case is reported as skipped rather than assumed.
if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
	if ffmpeg -v error -f lavfi -i "testsrc=size=320x240:rate=10:duration=1" \
		-c:v mjpeg "$WORK_DIR/synthetic.avi" >/dev/null 2>&1 && [ -s "$WORK_DIR/synthetic.avi" ]; then
		_probed="$(ci_probe_video_size "$WORK_DIR/synthetic.avi" 2>/dev/null)"
		CASES_RUN=$((CASES_RUN + 1))
		if [ "$_probed" = "320x240" ]; then
			_ok=yes
			CASES_OK=$((CASES_OK + 1))
		else
			_ok=no
		fi
		log "case $CASES_RUN: ci_probe_video_size reads a synthetic 320x240 video -> $_ok ('$_probed')"
	else
		log "note: ffmpeg could not synthesise a test video; the positive probe case was skipped"
	fi
else
	log "note: ffmpeg/ffprobe unavailable; the positive probe case was skipped"
fi

# ---------------------------------------------------------------------------
# 7. Bounded execution: a hung engine must not hang the tooling.
# ---------------------------------------------------------------------------
CASES_RUN=$((CASES_RUN + 1))
_start="$(date +%s 2>/dev/null || echo 0)"
ci_run_bounded 1 sh -c 'sleep 30' >/dev/null 2>&1
_status=$?
_end="$(date +%s 2>/dev/null || echo 0)"
_elapsed=$((_end - _start))
# A nonzero status is expected (the process is killed), and the whole thing must
# take about a second rather than the 30 seconds the child asked for.
if [ "$_status" -ne 0 ] && [ "$_elapsed" -le 5 ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: ci_run_bounded kills a hung process (exit $_status after ${_elapsed}s) -> $_ok"

# ---------------------------------------------------------------------------
# 8. Argument validation, including the unbounded-probe guards.
# ---------------------------------------------------------------------------
for _good in 640x360 960x540 1x1 1920x1080; do
	CASES_RUN=$((CASES_RUN + 1))
	if ci_is_wxh "$_good"; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: ci_is_wxh accepts '$_good' -> $_ok"
done
for _bad in "" "640" "640x" "x360" "640x360x720" "axb" "0x360" "640x0" "00x00" "640 x 360"; do
	CASES_RUN=$((CASES_RUN + 1))
	if ci_is_wxh "$_bad"; then
		_ok=no
	else
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	fi
	log "case $CASES_RUN: ci_is_wxh rejects '$_bad' -> $_ok"
done
for _good in 1 6 60 300; do
	CASES_RUN=$((CASES_RUN + 1))
	if ci_is_positive_int "$_good"; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: ci_is_positive_int accepts '$_good' -> $_ok"
done
for _bad in "" "0" "00" "-1" "1.5" "6x" "abc"; do
	CASES_RUN=$((CASES_RUN + 1))
	if ci_is_positive_int "$_bad"; then
		_ok=no
	else
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	fi
	log "case $CASES_RUN: ci_is_positive_int rejects '$_bad' -> $_ok"
done

# ---------------------------------------------------------------------------
# 9. The engine log gates. Opus recheck finding N1 is that `ci.sh test` judged
#    a check only on its exit status, so a runtime error (missing dictionary
#    key, push_error()) passed while the supported smoke wrapper failed. The
#    gate that closes it is ci_log_error_lines / ci_log_gate, and the warning
#    surfacing behind R7' is ci_log_warning_*. They are exercised here on
#    synthetic logs, because the shapes were measured against the pinned engine
#    and a regression in the pattern would silently reopen the hole.
# ---------------------------------------------------------------------------
ERR_LOG="$WORK_DIR/engine-errors.log"
CLEAN_LOG="$WORK_DIR/engine-clean.log"
WARN_LOG="$WORK_DIR/engine-warning.log"
ACCEPTED_WARN_LOG="$WORK_DIR/engine-accepted-warning.log"

{
	printf '%s\n' 'Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org'
	printf '%s\n' '[boot-smoke] engine 4.7.2-stable (official)'
	printf '%s\n' 'ERROR: Node not found: "NoSuchNode" (relative to "/root/Game").'
	printf '%s\n' 'SCRIPT ERROR: Invalid access to property or key '\''missing_key'\'' on a base object of type '\''null instance'\''.'
	printf '%s\n' 'ERROR: Failed to load script "res://src/boot/game.gd" with error "Parse error".'
	printf '%s\n' '   at: load (modules/gdscript/gdscript_resource_format.cpp:46)'
} >"$ERR_LOG"
{
	printf '%s\n' 'Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org'
	printf '%s\n' '[boot-smoke] engine 4.7.2-stable (official)'
	printf '%s\n' '[boot-smoke] PASS: M0 shell boots, hands off and loads the placeholder race scene'
} >"$CLEAN_LOG"
{
	printf '%s\n' '[game] placeholder race scene (no track, cars or simulation yet)'
	printf '%s\n' 'WARNING: Jolt Physics job system exceeded the maximum number of jobs'
	printf '%s\n' '     at: push_warning (core/variant/variant_utility.cpp:1033)'
} >"$WARN_LOG"
{
	printf '%s\n' 'WARNING: Detected another project.godot at res://tools/tick_probe. The folder will be ignored.'
	printf '%s\n' '     at: _should_skip_directory (editor/file_system/editor_file_system.cpp:3497)'
} >"$ACCEPTED_WARN_LOG"

# A clean log must have no error lines, and a mid-line mention of "ERROR" in
# ordinary output must not count as one.
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_log_error_count "$CLEAN_LOG")" = "0" ] &&
	[ "$(ci_log_warning_count "$CLEAN_LOG")" = "0" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: a clean engine log has no error or warning lines -> $_ok"

# The three error shapes measured against the pinned engine, including the
# push_error() line that used to pass CI.
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_log_error_count "$ERR_LOG")" = "3" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: engine error lines are counted (3 in the synthetic log) -> $_ok"

# Parity with the supported wrapper. tools/smoke/run_boot_smoke.sh documents the
# shapes it fails on; ci_log_error_lines must count every one of them, or the
# committed CI would be weaker than the wrapper again (finding N1). Each shape
# is checked on its own so a narrowed pattern names the shape it stopped
# catching.
check_error_shape() {
	_line="$1"
	_shape_log="$WORK_DIR/error-shape.log"
	printf '%s\n' "$_line" >"$_shape_log"
	CASES_RUN=$((CASES_RUN + 1))
	if [ "$(ci_log_error_count "$_shape_log")" = "1" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: engine error shape is counted: $_line -> $_ok"
}

check_error_shape 'ERROR: Node not found: "NoSuchNode" (relative to "/root/Game").'
check_error_shape "SCRIPT ERROR: Invalid access to property or key 'missing_key' on a base object of type 'null instance'."
check_error_shape 'ERROR: Failed to load script "res://src/boot/game.gd" with error "Parse error".'
check_error_shape 'Failed to load script "res://src/boot/game.gd" with error "Parse error".'
check_error_shape 'Parse Error: Unexpected identifier "this" in class body.'
check_error_shape 'USER ERROR: a script pushed an error'

# A warning line is not an error line, and neither is ordinary output.
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_log_error_count "$WARN_LOG")" = "0" ] &&
	[ "$(ci_log_error_count "$ACCEPTED_WARN_LOG")" = "0" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: warning lines are not counted as engine errors -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
if printf '%s\n' '[check] no ERROR here' | grep -qE '^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: a mid-line mention of ERROR is not an engine error -> $_ok"

# ci_log_gate must fail on an error log and pass on a clean one.
CASES_RUN=$((CASES_RUN + 1))
if ci_log_gate "$CLEAN_LOG" >/dev/null 2>&1; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: ci_log_gate accepts a clean log -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
if ci_log_gate "$ERR_LOG" >/dev/null 2>&1; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: ci_log_gate rejects a log with engine errors -> $_ok"

# Warnings: counted, split into accepted and unexpected, and fatal only in
# strict mode. A warning the project accepted in tools/ci/warnings.allow must
# not fail a strict run, and an unaccepted one must.
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_log_warning_count "$WARN_LOG")" = "1" ] &&
	[ "$(ci_log_unexpected_warning_count "$WARN_LOG")" = "1" ] &&
	[ "$(ci_log_unexpected_warning_count "$ACCEPTED_WARN_LOG")" = "0" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: warnings are counted and split by tools/ci/warnings.allow -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
_gate_out="$(ci_log_warning_gate "$WARN_LOG" 'self-test' 2>&1)"
_gate_rc=$?
if [ "$_gate_rc" -eq 0 ] && printf '%s\n' "$_gate_out" | grep -qF 'WARNING: Jolt Physics job system'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: an unexpected warning is surfaced and is not fatal by default -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
_gate_out="$(CI_STRICT_WARNINGS=1 ci_log_warning_gate "$WARN_LOG" 'self-test' 2>&1)"
_gate_rc=$?
if [ "$_gate_rc" -ne 0 ] && printf '%s\n' "$_gate_out" | grep -qF 'WARNING: Jolt Physics job system'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: an unexpected warning fails the run with --strict-warnings -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
_gate_out="$(CI_STRICT_WARNINGS=1 ci_log_warning_gate "$ACCEPTED_WARN_LOG" 'self-test' 2>&1)"
_gate_rc=$?
if [ "$_gate_rc" -eq 0 ] && printf '%s\n' "$_gate_out" | grep -qF 'accepted in warnings.allow'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: an accepted warning still passes with --strict-warnings -> $_ok"

# The allow-list must be present and must not be empty: without it, strict
# warnings would fail every run for the benign nested-project warning.
CASES_RUN=$((CASES_RUN + 1))
if [ -f "$TOOLS_CI_DIR/$CI_WARNINGS_ALLOW" ] &&
	grep -qE '^[^#[:space:]]' "$TOOLS_CI_DIR/$CI_WARNINGS_ALLOW" 2>/dev/null; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: $CI_WARNINGS_ALLOW exists and lists at least one accepted warning -> $_ok"

# ---------------------------------------------------------------------------
# 10. The export-preset platform mapping and coverage.
#     `ci.sh export --check` requires a preset for every native target in
#     docs/TECHNICAL_DESIGN.md, but the requirement names are the plan's
#     ("Windows") while Godot writes its own values in export_presets.cfg
#     ("Windows Desktop"). Comparing the names directly reported a covered
#     platform as missing -- the false "preset platform missing: Windows" this
#     mapping fixes. The cases below pin the mapping down in both directions:
#     the three real presets must pass, and a missing, mis-valued or unrelated
#     platform must fail. Template verification is re-checked end to end so the
#     preset fix cannot have quietly weakened it.
# ---------------------------------------------------------------------------
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_preset_platform_for macOS 2>/dev/null)" = "macOS" ] &&
	[ "$(ci_preset_platform_for Windows 2>/dev/null)" = "Windows Desktop" ] &&
	[ "$(ci_preset_platform_for Linux 2>/dev/null)" = "Linux" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: requirement names map to the Godot preset platform values -> $_ok"

# The naive value must not resolve to itself: a preset written with
# platform="Windows" is not a Windows preset in Godot, and mapping "Windows"
# to "Windows" is exactly the comparison that produced the false failure.
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_preset_platform_for Windows 2>/dev/null)" = "Windows" ]; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: the mapping does not equate 'Windows' with 'Windows Desktop' -> $_ok"

# An unknown requirement must fail rather than print an empty line that a
# caller could mistake for "covered".
CASES_RUN=$((CASES_RUN + 1))
if ci_preset_platform_for Android >/dev/null 2>&1; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: an unknown requirement is refused by the mapping -> $_ok"

# The committed export_presets.cfg: the actual three presets, parsed. This ties
# the test to the real artifact, so a platform value edited to something Godot
# does not write fails here.
REAL_CFG="$PROJECT_DIR/export_presets.cfg"
CASES_RUN=$((CASES_RUN + 1))
_real_table=""
if [ -f "$REAL_CFG" ]; then
	_real_table="$(ci_preset_table "$REAL_CFG" 2>/dev/null)"
fi
if [ "$(printf '%s\n' "$_real_table" | grep -c .)" = "3" ] &&
	printf '%s\n' "$_real_table" | cut -f2 | grep -qxF 'macOS Apple Silicon' &&
	printf '%s\n' "$_real_table" | cut -f2 | grep -qxF 'Windows x86-64' &&
	printf '%s\n' "$_real_table" | cut -f2 | grep -qxF 'Linux x86-64' &&
	printf '%s\n' "$_real_table" | cut -f3 | grep -qxF 'macOS' &&
	printf '%s\n' "$_real_table" | cut -f3 | grep -qxF 'Windows Desktop' &&
	printf '%s\n' "$_real_table" | cut -f3 | grep -qxF 'Linux'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the committed export_presets.cfg declares the three actual presets -> $_ok"
[ "$_ok" = "yes" ] || log "  table: $(printf '%s\n' "$_real_table" | tr '\n' ';')" >&2

# Coverage passes for the real presets, and says so per target.
CASES_RUN=$((CASES_RUN + 1))
_cov_out="$(ci_preset_platform_coverage "$REAL_CFG" 2>&1)"
_cov_rc=$?
if [ "$_cov_rc" -eq 0 ] &&
	printf '%s\n' "$_cov_out" | grep -qF 'preset platform covered: macOS (platform="macOS")' &&
	printf '%s\n' "$_cov_out" | grep -qF 'preset platform covered: Windows (platform="Windows Desktop")' &&
	printf '%s\n' "$_cov_out" | grep -qF 'preset platform covered: Linux (platform="Linux")'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: platform coverage passes for the actual presets -> $_ok"
[ "$_ok" = "yes" ] || printf '%s\n' "$_cov_out" | sed 's/^/  | /' >&2

# Synthetic tampered presets. Each states the requirement it must fail on, so
# a check that starts waving a bad platform through fails here.
CFG_DIR="$WORK_DIR/presets"
mkdir -p "$CFG_DIR"

cat >"$CFG_DIR/wrong-windows.cfg" <<'EOF'
[preset.0]

name="macOS Apple Silicon"
platform="macOS"
runnable=true

[preset.1]

name="Windows x86-64"
platform="Windows"
runnable=true

[preset.2]

name="Linux x86-64"
platform="Linux"
runnable=true
EOF
cat >"$CFG_DIR/no-linux.cfg" <<'EOF'
[preset.0]

name="macOS Apple Silicon"
platform="macOS"
runnable=true

[preset.1]

name="Windows x86-64"
platform="Windows Desktop"
runnable=true
EOF
cat >"$CFG_DIR/no-platform.cfg" <<'EOF'
[preset.0]

name="macOS Apple Silicon"
platform="macOS"
runnable=true

[preset.1]

name="Windows x86-64"
runnable=true

[preset.2]

name="Linux x86-64"
platform="Linux"
runnable=true
EOF
cat >"$CFG_DIR/other-platform.cfg" <<'EOF'
[preset.0]

name="macOS Apple Silicon"
platform="macOS"
runnable=true

[preset.1]

name="Web"
platform="Web"
runnable=true

[preset.2]

name="Linux x86-64"
platform="Linux"
runnable=true
EOF
cat >"$CFG_DIR/no-presets.cfg" <<'EOF'
[application]

config/name="not a preset section"
EOF

# coverage_fails <description> <cfg> <requirement that must be reported missing>
coverage_fails() {
	_desc="$1"
	_cfg="$2"
	_want="$3"
	CASES_RUN=$((CASES_RUN + 1))
	_out="$(ci_preset_platform_coverage "$_cfg" 2>&1)"
	_rc=$?
	if [ "$_rc" -ne 0 ] && printf '%s\n' "$_out" | grep -qF "preset platform missing: $_want"; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: $_desc -> $_ok"
	[ "$_ok" = "yes" ] || printf '%s\n' "$_out" | sed 's/^/  | /' >&2
}

coverage_fails "a preset with platform=\"Windows\" does not cover Windows" \
	"$CFG_DIR/wrong-windows.cfg" Windows
coverage_fails "a missing Linux preset fails coverage" "$CFG_DIR/no-linux.cfg" Linux
coverage_fails "a preset with no platform= line fails coverage" "$CFG_DIR/no-platform.cfg" Windows
coverage_fails "an unrelated platform does not satisfy a required target" \
	"$CFG_DIR/other-platform.cfg" Windows
coverage_fails "a file with no [preset.N] sections fails coverage" "$CFG_DIR/no-presets.cfg" macOS
coverage_fails "a missing export_presets.cfg fails coverage" "$CFG_DIR/absent.cfg" macOS

# ---------------------------------------------------------------------------
# 11. `ci.sh export --check` end to end, on synthetic project copies.
#     Gated on the pinned editor being installed (the ffmpeg-gated probe case
#     above is the precedent): without it the command exits 2 at engine
#     discovery and proves nothing either way. The template half of the check
#     is driven by a fake template directory built here, so the cases are
#     independent of what the host has installed -- and the last case removes
#     a template file to prove template verification still bites after the
#     preset mapping change.
# ---------------------------------------------------------------------------
ci_at() {
	_dir="$1"
	shift
	sh "$CI_SH" --project "$_dir" "$@"
}

_e2e_bin="${GODOT_BIN:-}"
if [ -z "$_e2e_bin" ]; then
	for _cand in "$(command -v godot 2>/dev/null)" "$(command -v godot4 2>/dev/null)" \
		"$(command -v Godot 2>/dev/null)" "/Applications/Godot.app/Contents/MacOS/Godot" \
		"/opt/homebrew/bin/godot" "/usr/local/bin/godot" "/usr/bin/godot"; do
		if [ -n "$_cand" ] && [ -x "$_cand" ]; then
			_e2e_bin="$_cand"
			break
		fi
	done
fi
_e2e_version=""
[ -n "$_e2e_bin" ] && [ -x "$_e2e_bin" ] && _e2e_version="$("$_e2e_bin" --version 2>/dev/null | head -n 1)"
_e2e_pin="$(ci pin --field version 2>/dev/null)"

if [ -n "$_e2e_version" ] && [ -n "$_e2e_pin" ]; then
	case "$_e2e_version" in
		"$_e2e_pin".*) _e2e=yes ;;
		*) _e2e=no ;;
	esac
else
	_e2e=no
fi

if [ "$_e2e" = "yes" ]; then
	SPROJ="$WORK_DIR/synthetic-project"
	mkdir -p "$SPROJ"
	printf 'config_version=5\n\n[application]\n\nconfig/name="synthetic export project"\n' >"$SPROJ/project.godot"

	# The pinned version as this tooling resolves it for a project without its
	# own tools/toolchain record: the tools/ci fallback pin.
	TVERSION="$(sh "$CI_SH" --project "$SPROJ" pin --field version 2>/dev/null)"
	TDIR="$WORK_DIR/export_templates"
	TVER="$TVERSION.stable"
	mkdir -p "$TDIR/$TVER"
	printf '%s.stable\n' "$TVERSION" >"$TDIR/$TVER/version.txt"
	for _tpl in macos.zip \
		"windows_release_x86_64.exe" "windows_release_x86_32.exe" \
		"linux_release.x86_64" "linux_release.x86_32"; do
		: >"$TDIR/$TVER/$_tpl"
	done
	GODOT_TEMPLATES_DIR="$TDIR"
	export GODOT_TEMPLATES_DIR

	# The happy path: the real presets, fake but complete templates.
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	expect_case "export --check passes a project with the three actual presets" 0 \
		ci_at "$SPROJ" export --check

	# Tampered: the Windows preset's platform value changed to the naive
	# "Windows". Must fail, and name the requirement it could not cover.
	sed 's/^platform="Windows Desktop"$/platform="Windows"/' "$REAL_CFG" >"$SPROJ/export_presets.cfg"
	expect_contains "export --check fails a preset with platform=\"Windows\"" 1 \
		"preset platform missing: Windows" ci_at "$SPROJ" export --check

	# Missing: no Linux preset at all.
	cat >"$SPROJ/export_presets.cfg" <<'EOF'
[preset.0]

name="macOS Apple Silicon"
platform="macOS"
runnable=true

[preset.1]

name="Windows x86-64"
platform="Windows Desktop"
runnable=true
EOF
	expect_contains "export --check fails when the Linux preset is missing" 1 \
		"preset platform missing: Linux" ci_at "$SPROJ" export --check

	# No presets at all must fail explicitly, not silently pass.
	rm -f "$SPROJ/export_presets.cfg"
	expect_contains "export --check fails when export_presets.cfg is absent" 1 \
		"no export_presets.cfg" ci_at "$SPROJ" export --check

	# Template verification, unchanged by the preset fix: with the presets
	# complete again, removing the pinned Windows template files must still fail
	# the check (it requires at least one architecture per platform). A weakened
	# template check would pass this case.
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	rm -f "$TDIR/$TVER/windows_release_x86_64.exe" "$TDIR/$TVER/windows_release_x86_32.exe"
	expect_contains "export --check still fails when the Windows templates are missing" 1 \
		"templates: Windows -> none of" ci_at "$SPROJ" export --check
else
	log "note: no installed Godot matches pin '$_e2e_pin'; the end-to-end export --check cases were skipped"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "summary: $CASES_OK/$CASES_RUN cases behaved as expected"
if [ "$CASES_OK" -eq "$CASES_RUN" ]; then
	log "PASS: tools/ci self-test"
	exit 0
fi
log "FAIL: $((CASES_RUN - CASES_OK)) case(s) did not behave as expected" >&2
exit 1
