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
#   * Hermetic. No network and no display. The base suite uses no engine and
#     does not read the checkout's Git index; the tracked-output cases create
#     their own throwaway Git repository/index in the private temporary
#     directory, and the export end-to-end cases run only when a matching Godot
#     and the pinned templates are installed. Everything runs in a private
#     temporary directory that is removed on exit.
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

# Normalise the working directory to a clean absolute path. A TMPDIR that ends
# in a slash (macOS sets TMPDIR=/var/folders/.../T/, so the template above
# yields a path containing "//") makes the pinned engine fail to resolve its
# user-data path: measured, the import then exits with
#   "ERROR: Could not create ObjectDB Snapshots directory:
#     user://private/var/.../<project copy>"
# which would fail the engine-backed cases for a reason that has nothing to do
# with the tooling. `cd` + `pwd` collapses the duplicate separators and resolves
# the /var -> /private/var symlink; the same normalisation is why
# scripts/runtime_error_gate.sh does it too.
WORK_DIR="$(cd "$WORK_DIR" 2>/dev/null && pwd)" ||
	die 2 "could not resolve the temporary working directory to an absolute path"
[ -d "$WORK_DIR" ] || die 2 "temporary working directory disappeared: $WORK_DIR"

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
expect_contains "help documents install-templates" 0 "install-templates" ci --help
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
# 9b. The shared Jolt classifier, the tracked-output sentinel and relative
#     --out canonicalisation. These three are the independently reproduced
#     hosted-run 45921573623 causes: a substring match on "jolt" failed the
#     job for res://tools/jolt_inventory (C2); the self-check counted its own
#     tracked .gitignore as forbidden build output (C1); and a relative export
#     --out landed in the scratch project copy (M1).
# ---------------------------------------------------------------------------
JOLT_TRUE_LOG="$WORK_DIR/jolt-true.log"
{
	printf '%s\n' 'WARNING: Jolt Physics job system exceeded the maximum number of jobs. This should not happen. Please report this. Waiting for jobs to become available...'
	printf '%s\n' 'WARNING: Jolt Physics manifold cache exceeded capacity and contacts were ignored. Consider increasing maximum number of contact constraints in project settings.'
	printf '%s\n' 'WARNING: Jolt Physics body pair cache exceeded capacity and contacts were ignored. Consider increasing maximum number of body pairs in project settings.'
	printf '%s\n' 'WARNING: Jolt Physics contact constraint buffer exceeded capacity and contacts were ignored. Consider increasing maximum number of contact constraints in project settings.'
	printf '%s\n' 'WARNING: Jolt Physics temporary memory allocator exceeded capacity of 64 MiB. Falling back to slower general-purpose allocator.'
} >"$JOLT_TRUE_LOG"

CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_log_jolt_warning_count "$JOLT_TRUE_LOG" 2>/dev/null)" = "5" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: all five pinned-engine Jolt physics warnings are classified -> $_ok"

# Real-path false positive: the nested project's warning contains "jolt" but is
# not a physics message. Both the raw helper and the shared line filter must
# reject it.
JOLT_FALSE_LINE='WARNING: Detected another project.godot at res://tools/jolt_inventory. The folder will be ignored.'
JOLT_FALSE_LOG="$WORK_DIR/jolt-false.log"
printf '%s\n' "$JOLT_FALSE_LINE" >"$JOLT_FALSE_LOG"
CASES_RUN=$((CASES_RUN + 1))
if ci_is_jolt_physics_warning "$JOLT_FALSE_LINE"; then
	_ok=no
elif [ "$(ci_log_jolt_warning_count "$JOLT_FALSE_LOG" 2>/dev/null)" != "0" ]; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: a nested-project warning naming res://tools/jolt_inventory is NOT a Jolt physics warning -> $_ok"

# A line-number-prefixed real warning (the shape ci_log_* actually filters)
# must still be recognised.
CASES_RUN=$((CASES_RUN + 1))
if ci_is_jolt_physics_warning "17:WARNING: Jolt Physics manifold cache exceeded capacity and contacts were ignored."; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: a line-number-prefixed Jolt physics warning is recognised -> $_ok"

# An ordinary unexpected warning containing "jolt" nowhere near a physics
# message is not fatal, either.
CASES_RUN=$((CASES_RUN + 1))
if ci_is_jolt_physics_warning 'WARNING: something about JoltFish asset import'; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: an unrelated warning mentioning Jolt is not fatal -> $_ok"

# The tracked-output check: isolated temporary Git repository/index. Only the
# exact "<out>/.gitignore" sentinel may be exempt; a real tracked build file,
# and even another dotfile, must still fail.
GITCHECK="$WORK_DIR/git-tracked-output"
if command -v git >/dev/null 2>&1; then
	rm -rf "$GITCHECK"
	mkdir -p "$GITCHECK/tools/ci/out"
	(
		cd "$GITCHECK" || exit 1
		git init -q
		printf '*\n!.gitignore\n' >tools/ci/out/.gitignore
		git add tools/ci/out/.gitignore
	) || die 2 "could not create the isolated Git index for the tracked-output case"

	CASES_RUN=$((CASES_RUN + 1))
	if [ "$(ci_tracked_output_paths "$GITCHECK" tools/ci/out 2>/dev/null | ci_count_lines)" = "0" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: the out directory's own .gitignore sentinel is exempt -> $_ok"

	(
		cd "$GITCHECK" || exit 1
		printf 'engine log\n' >tools/ci/out/run.log
		# The sentinel's `*` rule ignores this file, exactly as it would in the
		# real tree; -f stages it anyway, which is what makes it a TRACKED build
		# output the check must reject.
		git add -f tools/ci/out/run.log
	) || die 2 "could not stage a build log in the isolated Git index"
	CASES_RUN=$((CASES_RUN + 1))
	if [ "$(ci_tracked_output_paths "$GITCHECK" tools/ci/out 2>/dev/null | ci_count_lines)" = "1" ] &&
		[ "$(ci_tracked_output_paths "$GITCHECK" tools/ci/out 2>/dev/null)" = "tools/ci/out/run.log" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: a tracked build log under the out directory is still rejected -> $_ok"

	# Another dotfile is not the sentinel and must not inherit the exemption.
	(
		cd "$GITCHECK" || exit 1
		printf 'notes\n' >tools/ci/out/other.gitignore
		git add -f tools/ci/out/other.gitignore
	) || die 2 "could not stage another dotfile in the isolated Git index"
	CASES_RUN=$((CASES_RUN + 1))
	if printf '%s\n' "$(ci_tracked_output_paths "$GITCHECK" tools/ci/out 2>/dev/null)" |
		grep -qxF 'tools/ci/out/other.gitignore'; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: a non-sentinel dotfile does not inherit the exemption -> $_ok"

	# Sol 8c6c928: a truncated/unreadable index makes git ls-files exit 128.
	# The helper must propagate that status, never report an empty list as
	# clean. This is the same corruption shape the reviewer used in a throwaway
	# repository; nothing outside this suite's private directory is touched.
	printf 'invalid Git index\n' >"$GITCHECK/.git/index"
	CASES_RUN=$((CASES_RUN + 1))
	if ci_tracked_output_paths "$GITCHECK" tools/ci/out >/dev/null 2>&1; then
		_ok=no
	else
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	fi
	log "case $CASES_RUN: a truncated/unreadable Git index fails closed, not clean -> $_ok"
else
	log "note: git is not installed; the tracked-output sentinel cases were skipped"
fi

# Relative/absolute --out canonicalisation: resolve against the caller's
# directory with FILESYSTEM semantics (".." after a symlink follows the
# target's parent), never lexical collapsing.
ABS_CWD="$WORK_DIR/abs-cwd"
mkdir -p "$ABS_CWD/build" "$ABS_CWD/pkg"
_abs_base="$(cd "$ABS_CWD" && pwd -P)"
CASES_RUN=$((CASES_RUN + 1))
_abs_got="$(cd "$ABS_CWD" && ci_abs_path './build/../pkg/app.zip' 2>/dev/null)"
if [ "$_abs_got" = "$_abs_base/pkg/app.zip" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: a relative --out resolves against the caller and drops ./ and ../ -> $_ok"
[ "$_ok" = "yes" ] || log "  expected '$_abs_base/pkg/app.zip', got '$_abs_got'" >&2

CASES_RUN=$((CASES_RUN + 1))
_abs_got="$(cd "$ABS_CWD" && ci_abs_path 'deep/new/dir/app.zip' 2>/dev/null)"
if [ "$_abs_got" = "$_abs_base/deep/new/dir/app.zip" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: a relative --out through directories that do not exist yet is made absolute -> $_ok"
[ "$_ok" = "yes" ] || log "  expected '$_abs_base/deep/new/dir/app.zip', got '$_abs_got'" >&2

ABS_REAL="$WORK_DIR/abs-real"
ABS_LINK="$WORK_DIR/abs-link"
mkdir -p "$ABS_REAL"
rm -f "$ABS_LINK"
ln -s "$ABS_REAL" "$ABS_LINK" 2>/dev/null || true
if [ -L "$ABS_LINK" ]; then
	_abs_real="$(cd "$ABS_REAL" && pwd -P)"
	CASES_RUN=$((CASES_RUN + 1))
	_abs_got="$(cd "$ABS_CWD" && ci_abs_path "$ABS_LINK/file.zip" 2>/dev/null)"
	if [ "$_abs_got" = "$_abs_real/file.zip" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: an absolute --out through a symlinked parent follows filesystem semantics -> $_ok"
	[ "$_ok" = "yes" ] || log "  expected '$_abs_real/file.zip', got '$_abs_got'" >&2
else
	log "note: symlinks are unavailable; the symlinked-parent --out case was skipped"
fi

# Sol recheck at 245ee1d: `via -> elsewhere/inner`, input `via/../package`
# from `caller`. Opening that path reaches `elsewhere/package`; lexically
# collapsing ".." wrote to `caller/package` instead.
PATH_CALLER="$WORK_DIR/pathcaller"
PATH_ELSE="$WORK_DIR/pathelsewhere"
rm -rf "$PATH_CALLER" "$PATH_ELSE"
mkdir -p "$PATH_CALLER" "$PATH_ELSE/inner"
ln -s "$PATH_ELSE/inner" "$PATH_CALLER/via" 2>/dev/null || true
if [ -L "$PATH_CALLER/via" ]; then
	_else_base="$(cd "$PATH_ELSE" && pwd -P)"
	CASES_RUN=$((CASES_RUN + 1))
	_abs_got="$(cd "$PATH_CALLER" && ci_abs_path 'via/../package.zip' 2>/dev/null)"
	if [ "$_abs_got" = "$_else_base/package.zip" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: '..' after a symlinked component follows the target's parent (Sol 245ee1d) -> $_ok"
	[ "$_ok" = "yes" ] || log "  expected '$_else_base/package.zip', got '$_abs_got'" >&2
else
	log "note: symlinks are unavailable; the symlink+parent-traversal case was skipped"
fi

# Preset slugs name per-preset logs/reports without spaces or slashes.
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_preset_slug 'macOS Apple Silicon')" = "macos-apple-silicon" ] &&
	[ "$(ci_preset_slug 'Windows x86-64')" = "windows-x86-64" ] &&
	[ "$(ci_preset_slug 'Linux x86-64')" = "linux-x86-64" ] &&
	[ "$(ci_preset_slug 'A/B C')" = "a-b-c" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: preset names map to safe distinct log/report slugs -> $_ok"

# The scratch project copy must not inherit a previously built ./build tree
# (F2): earlier presets' packages would otherwise land in later presets'
# inputs and in tools/ci/out/project-copy, bloating the upload.
COPY_SRC="$WORK_DIR/copy-src"
COPY_DST="$WORK_DIR/copy-dst"
rm -rf "$COPY_SRC" "$COPY_DST"
mkdir -p "$COPY_SRC/build" "$COPY_SRC/assets"
printf 'config_version=5\n' >"$COPY_SRC/project.godot"
printf 'stale package\n' >"$COPY_SRC/build/stale-package.bin"
printf 'shipped asset\n' >"$COPY_SRC/assets/keep.txt"
CI_OUT_REL_PATTERN=""
ci_copy_project "$COPY_SRC" "$COPY_DST"
CASES_RUN=$((CASES_RUN + 1))
if [ -f "$COPY_DST/project.godot" ] &&
	[ -f "$COPY_DST/assets/keep.txt" ] &&
	[ ! -e "$COPY_DST/build/stale-package.bin" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the scratch copy excludes ./build but preserves project resources -> $_ok"

# R1: report files are named per process (PID) so two invocations started in
# the same UTC second -- export --check, --list-presets and the first preset
# build all run within one second on a fast runner -- cannot truncate each
# other's evidence.
COLL_OUT="$WORK_DIR/report-collision"
rm -rf "$COLL_OUT"
mkdir -p "$COLL_OUT/reports"
(
	CI_OUT="$COLL_OUT"
	CI_RUN_NAME=export-check
	export CI_OUT CI_RUN_NAME
	. "$COMMON_SH" >/dev/null 2>&1
	ci_init_report
	printf '%s\n' "$CI_REPORT" >"$COLL_OUT/name-a"
) &
_coll_a=$!
(
	CI_OUT="$COLL_OUT"
	CI_RUN_NAME=export-check
	export CI_OUT CI_RUN_NAME
	. "$COMMON_SH" >/dev/null 2>&1
	ci_init_report
	printf '%s\n' "$CI_REPORT" >"$COLL_OUT/name-b"
) &
_coll_b=$!
wait "$_coll_a" "$_coll_b" 2>/dev/null
_coll_r1="$(cat "$COLL_OUT/name-a" 2>/dev/null)"
_coll_r2="$(cat "$COLL_OUT/name-b" 2>/dev/null)"
CASES_RUN=$((CASES_RUN + 1))
if [ -n "$_coll_r1" ] && [ -n "$_coll_r2" ] &&
	[ "$_coll_r1" != "$_coll_r2" ] && [ -s "$_coll_r1" ] && [ -s "$_coll_r2" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: two report inits in the same process window leave distinct non-empty reports -> $_ok"
[ "$_ok" = "yes" ] || log "  a='$_coll_r1' b='$_coll_r2'" >&2

# Same-process repeat: the existence probe must pick a fresh name instead of
# opening (and emptying) the report just written.
(
	CI_OUT="$COLL_OUT"
	CI_RUN_NAME=repeat
	export CI_OUT CI_RUN_NAME
	. "$COMMON_SH" >/dev/null 2>&1
	ci_init_report
	printf '%s\n' "$CI_REPORT" >"$COLL_OUT/name-c"
	ci_init_report
	printf '%s\n' "$CI_REPORT" >"$COLL_OUT/name-d"
) >/dev/null 2>&1
_coll_r3="$(cat "$COLL_OUT/name-c" 2>/dev/null)"
_coll_r4="$(cat "$COLL_OUT/name-d" 2>/dev/null)"
CASES_RUN=$((CASES_RUN + 1))
if [ -n "$_coll_r3" ] && [ -n "$_coll_r4" ] &&
	[ "$_coll_r3" != "$_coll_r4" ] && [ -s "$_coll_r3" ] && [ -s "$_coll_r4" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: a repeated report init never truncates the first report -> $_ok"

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
#     discovery and proves nothing either way.
#
#     The template half of the check is driven by a sandbox HOME whose ENGINE
#     template directory (ci_templates_engine_dir) holds the tree under test.
#     That is deliberate (Opus recheck finding E1): the engine reads templates
#     from its own user-data directory and does NOT read $GODOT_TEMPLATES_DIR,
#     so a check that looked at the variable passed trees the engine then
#     refused to export. The last group of cases proves that regression: a
#     COMPLETE template tree in $GODOT_TEMPLATES_DIR must not turn a red check
#     green while the engine's own directory is empty.
# ---------------------------------------------------------------------------
ci_at() {
	_dir="$1"
	shift
	sh "$CI_SH" --project "$_dir" "$@"
}

# ci_at_home <home> <project> [args...] : run ci.sh against a project with an
# isolated HOME (so the engine template directory is a sandbox) and with
# GODOT_TEMPLATES_DIR unset, which is the state a clean runner is in.
ci_at_home() {
	_ch_home="$1"
	_ch_proj="$2"
	shift 2
	(
		HOME="$_ch_home"
		export HOME
		unset GODOT_TEMPLATES_DIR
		sh "$CI_SH" --project "$_ch_proj" "$@"
	)
}

# ci_at_home_tpl <home> <templates-dir> <project> [args...] : the same, but with
# GODOT_TEMPLATES_DIR pointing at <templates-dir>.
ci_at_home_tpl() {
	_ch_home="$1"
	_ch_tpl="$2"
	_ch_proj="$3"
	shift 3
	(
		HOME="$_ch_home"
		export HOME
		GODOT_TEMPLATES_DIR="$_ch_tpl"
		export GODOT_TEMPLATES_DIR
		sh "$CI_SH" --project "$_ch_proj" "$@"
	)
}

# ci_rel_at_home <cwd> <home> <project> [args...] : like ci_at_home, but runs
# from a caller-specified working directory. This is how the workflow invokes
# the export (a relative build/<name> path), so it is the only way to prove the
# --out value is resolved against the CALLER rather than Godot's --path scratch
# project copy.
ci_rel_at_home() {
	_crh_cwd="$1"
	_crh_home="$2"
	_crh_proj="$3"
	shift 3
	(
		cd "$_crh_cwd" || exit 2
		HOME="$_crh_home"
		export HOME
		unset GODOT_TEMPLATES_DIR
		sh "$CI_SH" --project "$_crh_proj" "$@"
	)
}

# seed_templates <templates-root> : version.txt plus a complete, NON-EMPTY
# template tree for the three required targets at the architectures the
# committed presets declare (macos.zip, windows_release_x86_64.exe,
# linux_release.x86_64). Non-empty matters: a zero-byte template is corrupt and
# the check must refuse it, which is one of the cases below.
#
# The version directory is REMOVED first, so a file left over by an earlier
# case cannot make a later case pass for the wrong reason -- and every file is
# written fresh inside this suite's private temporary directory, never through
# a link to an installed template tree.
seed_templates() {
	_st_root="$1"
	case "$_st_root" in
		"$WORK_DIR"/*) : ;;
		*) die 2 "seed_templates refuses to write outside the suite's temporary directory: $_st_root" ;;
	esac
	rm -rf "$_st_root/$TVER"
	mkdir -p "$_st_root/$TVER"
	printf '%s\n' "$TVER" >"$_st_root/$TVER/version.txt"
	for _st_f in macos.zip windows_release_x86_64.exe linux_release.x86_64; do
		printf 'synthetic export template payload for %s\n' "$_st_f" >"$_st_root/$TVER/$_st_f"
	done
}

# preset_arch <cfg> <preset-index> <architecture> : rewrite one preset's
# binary_format/architecture, leaving the other presets alone.
preset_arch() {
	_pa_cfg="$1"
	_pa_idx="$2"
	_pa_arch="$3"
	awk -v idx="$_pa_idx" -v arch="$_pa_arch" '
		/^\[/ { inopts = ($0 == "[" idx ".options]") }
		inopts && /^binary_format\/architecture=/ { print "binary_format/architecture=\"" arch "\""; next }
		{ print }
	' "$_pa_cfg"
}

# preset_no_arch <cfg> <preset-index> : drop one preset's
# binary_format/architecture line entirely.
preset_no_arch() {
	_pna_cfg="$1"
	_pna_idx="$2"
	awk -v idx="$_pna_idx" '
		/^\[/ { inopts = ($0 == "[" idx ".options]") }
		inopts && /^binary_format\/architecture=/ { next }
		{ print }
	' "$_pna_cfg"
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
TVERSION="$_e2e_pin"
TVER="$_e2e_pin.stable"

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
	# Minimal but REAL content: an engine refuses to export a project with no
	# files at all ("Must select at least one file to export"), so the export
	# cases below need a scene and a script of their own. Everything is synthetic
	# and lives in this suite's temporary directory.
	{
		printf 'config_version=5\n\n'
		printf '[application]\n\n'
		printf 'config/name="synthetic export project"\n'
		printf 'run/main_scene="res://scenes/boot.tscn"\n'
		# macOS universal/arm64 exports require ETC2 ASTC import support; without
		# this setting the engine refuses the preset before any path is written.
		printf '\n[rendering]\n\n'
		printf 'textures/vram_compression/import_etc2_astc=true\n'
	} >"$SPROJ/project.godot"
	# The committed pack-inventory policy (E4) requires the three boot scenes
	# and scripts, plus .godot/exported and remap/gdc entries, so the synthetic
	# project mirrors that minimal runtime shape instead of an arbitrary file.
	mkdir -p "$SPROJ/scenes" "$SPROJ/src/boot"
	for _fx in boot game main_menu; do
		printf 'extends Node\n' >"$SPROJ/src/boot/$_fx.gd"
		printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://src/boot/%s.gd" id="1"]\n\n[node name="%s" type="Node"]\nscript = ExtResource("1")\n' \
			"$_fx" "$_fx" >"$SPROJ/scenes/$_fx.tscn"
	done

	# The engine's own template directory, under an isolated HOME.
	SANDBOX_HOME="$WORK_DIR/sandbox-home"
	mkdir -p "$SANDBOX_HOME"
	ENGINE_DIR="$(HOME="$SANDBOX_HOME"; export HOME; ci_templates_engine_dir)"
	[ -n "$ENGINE_DIR" ] || die 2 "could not derive the engine template directory"

	# The happy path: the real presets, a complete template tree where the
	# engine reads it.
	seed_templates "$ENGINE_DIR"
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	expect_case "export --check passes a project with the three actual presets" 0 \
		ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

	# Tampered: the Windows preset's platform value changed to the naive
	# "Windows". Must fail, and name the requirement it could not cover.
	sed 's/^platform="Windows Desktop"$/platform="Windows"/' "$REAL_CFG" >"$SPROJ/export_presets.cfg"
	expect_contains "export --check fails a preset with platform=\"Windows\"" 1 \
		"preset platform missing: Windows" ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

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
		"preset platform missing: Linux" ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

	# No presets at all must fail explicitly, not silently pass.
	rm -f "$SPROJ/export_presets.cfg"
	expect_contains "export --check fails when export_presets.cfg is absent" 1 \
		"no export_presets.cfg" ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

	# --- Templates: the architecture each preset declares (Opus recheck E2) ---
	# Every case below sets up BOTH inputs from scratch -- the committed presets
	# and a freshly seeded template tree -- so a leftover from an earlier case
	# cannot make a later one pass (or fail) for the wrong reason. A check that
	# accepted any architecture would pass the first one; one that looked at
	# $GODOT_TEMPLATES_DIR instead of the engine directory would pass the last.

	# Only the 32-bit Windows template is installed while the preset declares
	# x86_64: the presence check must fail and name the file it needed.
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	seed_templates "$ENGINE_DIR"
	rm -f "$ENGINE_DIR/$TVER/windows_release_x86_64.exe"
	printf 'synthetic export template payload for windows_release_x86_32.exe\n' \
		>"$ENGINE_DIR/$TVER/windows_release_x86_32.exe"
	expect_contains "export --check fails when only the 32-bit Windows template is installed" 1 \
		"none of [windows_release_x86_64.exe" ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

	# The reverse substitution: the preset asks for x86_32, only x86_64 is there.
	seed_templates "$ENGINE_DIR"
	preset_arch "$REAL_CFG" preset.1 x86_32 >"$SPROJ/export_presets.cfg"
	expect_contains "export --check fails a Windows preset that declares x86_32" 1 \
		"none of [windows_release_x86_32.exe" ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

	# The same substitution on the Linux target.
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	seed_templates "$ENGINE_DIR"
	preset_arch "$REAL_CFG" preset.2 x86_32 >"$SPROJ/export_presets.cfg"
	expect_contains "export --check fails a Linux preset that declares x86_32" 1 \
		"none of [linux_release.x86_32" ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

	# A corrupt (zero-byte) template is refused rather than counted as present.
	# The file is REMOVED and re-created as a new, empty, regular file inside this
	# suite's private temporary directory: a truncation must never be able to
	# follow a link into an installed template tree, so nothing is ever written
	# through an existing path.
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	seed_templates "$ENGINE_DIR"
	rm -f "$ENGINE_DIR/$TVER/linux_release.x86_64"
	: >"$ENGINE_DIR/$TVER/linux_release.x86_64"
	if [ -L "$ENGINE_DIR/$TVER/linux_release.x86_64" ]; then
		die 2 "refusing to write through a symlinked template path"
	fi
	expect_contains "export --check fails a corrupt (empty) template" 1 \
		"none of [linux_release.x86_64" ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

	# A version.txt that does not report the pinned version is refused.
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	seed_templates "$ENGINE_DIR"
	printf '4.7.1.stable\n' >"$ENGINE_DIR/$TVER/version.txt"
	expect_contains "export --check fails when version.txt reports another version" 1 \
		"version.txt reports" ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

	# A preset that declares no architecture cannot have its required template
	# determined, and must fail instead of defaulting silently.
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	seed_templates "$ENGINE_DIR"
	preset_no_arch "$REAL_CFG" preset.1 >"$SPROJ/export_presets.cfg"
	expect_contains "export --check fails a preset that declares no architecture" 1 \
		"declares no binary_format/architecture" ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check

	# --- The engine's directory is the one that counts (Opus recheck E1) ---
	# A COMPLETE template tree in $GODOT_TEMPLATES_DIR, with the engine's own
	# directory empty, must still fail -- and must say why. Before the fix this
	# was a green check followed by "No export template found at the expected
	# path" from the engine itself.
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	seed_templates "$ENGINE_DIR"
	ENV_TPL="$WORK_DIR/env-templates"
	seed_templates "$ENV_TPL"
	rm -rf "$ENGINE_DIR"
	expect_contains "export --check fails when only GODOT_TEMPLATES_DIR has templates" 1 \
		"NOT read by the engine" ci_at_home_tpl "$SANDBOX_HOME" "$ENV_TPL" "$SPROJ" export --check

	# ... and with the engine directory populated again the same tree passes,
	# which is what keeps the case above from being a blanket failure.
	seed_templates "$ENGINE_DIR"
	cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
	expect_case "export --check passes again once the engine directory has templates" 0 \
		ci_at_home "$SANDBOX_HOME" "$SPROJ" export --check
else
	log "note: no installed Godot matches pin '$_e2e_pin'; the end-to-end export --check cases were skipped"
fi

# ---------------------------------------------------------------------------
# 12. The export-template file mapping and the preset field reader (E2).
#     The required template file is derived from the preset's
#     binary_format/architecture, so these cases pin the mapping down in both
#     directions: the right file for a declared architecture, and a refusal for
#     an architecture Godot does not accept. A mapping that accepted any
#     architecture is what let a 32-bit-only tree pass.
# ---------------------------------------------------------------------------
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_template_files_for Windows x86_64 release 2>/dev/null | head -n 1)" = "windows_release_x86_64.exe" ] &&
	[ "$(ci_template_files_for Windows x86_32 release 2>/dev/null | head -n 1)" = "windows_release_x86_32.exe" ] &&
	[ "$(ci_template_files_for Windows arm64 release 2>/dev/null | head -n 1)" = "windows_release_arm64.exe" ] &&
	[ "$(ci_template_files_for Linux x86_64 release 2>/dev/null)" = "linux_release.x86_64" ] &&
	[ "$(ci_template_files_for Linux x86_32 release 2>/dev/null)" = "linux_release.x86_32" ] &&
	[ "$(ci_template_files_for Linux arm64 release 2>/dev/null)" = "linux_release.arm64" ] &&
	[ "$(ci_template_files_for Linux arm32 release 2>/dev/null)" = "linux_release.arm32" ] &&
	[ "$(ci_template_files_for macOS universal release 2>/dev/null)" = "macos.zip" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the required template file follows the preset architecture -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_template_files_for Windows x86_64 debug 2>/dev/null | head -n 1)" = "windows_debug_x86_64.exe" ] &&
	[ "$(ci_template_files_for Linux x86_64 debug 2>/dev/null)" = "linux_debug.x86_64" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the export mode selects the debug or release template -> $_ok"

# The Windows console-wrapper variant is an accepted alternative, not the
# primary file: Godot selects it when the preset enables the console wrapper.
CASES_RUN=$((CASES_RUN + 1))
if ci_template_files_for Windows x86_64 release 2>/dev/null | grep -qxF 'windows_release_x86_64_console.exe'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the Windows console-wrapper template is an accepted alternative -> $_ok"

for _bad_arch in x86_128 arm "" riscv; do
	CASES_RUN=$((CASES_RUN + 1))
	if ci_template_files_for Windows "$_bad_arch" release >/dev/null 2>&1; then
		_ok=no
	else
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	fi
	log "case $CASES_RUN: an architecture Godot does not accept is refused ('$_bad_arch') -> $_ok"
done

CASES_RUN=$((CASES_RUN + 1))
if ci_template_files_for Android x86_64 release >/dev/null 2>&1; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: an unknown platform is refused by the template mapping -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
if ci_template_files_for Linux x86_64 something >/dev/null 2>&1; then
	_ok=no
else
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
fi
log "case $CASES_RUN: an unknown export mode is refused by the template mapping -> $_ok"

# The accepted architecture lists, per platform.
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_template_architectures macOS)" = "universal arm64 x86_64" ] &&
	[ "$(ci_template_architectures Windows)" = "x86_64 x86_32 arm64" ] &&
	[ "$(ci_template_architectures Linux)" = "x86_64 x86_32 arm64 arm32" ] &&
	! ci_template_architectures Web >/dev/null 2>&1; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the accepted architectures are listed per platform -> $_ok"

# The preset field reader against the committed presets: the architectures and
# the Linux embed_pck=false that decides whether a sidecar .pck is required.
CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_preset_architecture "$REAL_CFG" preset.0 2>/dev/null)" = "universal" ] &&
	[ "$(ci_preset_architecture "$REAL_CFG" preset.1 2>/dev/null)" = "x86_64" ] &&
	[ "$(ci_preset_architecture "$REAL_CFG" preset.2 2>/dev/null)" = "x86_64" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the committed presets declare the architectures they export -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_preset_field "$REAL_CFG" preset.2 binary_format/embed_pck 2>/dev/null)" = "false" ] &&
	! ci_preset_field "$REAL_CFG" preset.1 binary_format/embed_pck >/dev/null 2>&1 &&
	! ci_preset_field "$REAL_CFG" preset.0 not/a/real/key >/dev/null 2>&1; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the preset field reader reads a key and refuses an absent one -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_preset_index_for "$REAL_CFG" 'Linux x86-64' 2>/dev/null)" = "preset.2" ] &&
	! ci_preset_index_for "$REAL_CFG" 'No Such Preset' >/dev/null 2>&1; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: a preset name resolves to its preset.N index -> $_ok"

# The macOS preset must use Godot's built-in ad-hoc signer (codesign=1), not
# Xcode codesign (codesign=3). Verified against the pinned engine source
# (platform/macos/export/export_plugin.cpp at ed1daf0bf): mode 3 requires
# /usr/bin/codesign or /bin/codesign and fails preset validation on the hosted
# Linux runner, while mode 1 is implemented in editor/export/codesign.cpp,
# which has no MACOS_ENABLED guard, so it cross-exports. Notarization must
# remain disabled: the package is ad-hoc signed and UNNOTARIZED.
CASES_RUN=$((CASES_RUN + 1))
_cs_idx="$(ci_preset_index_for "$REAL_CFG" 'macOS Apple Silicon' 2>/dev/null)"
if [ "$_cs_idx" = "preset.0" ] &&
	[ "$(ci_preset_field "$REAL_CFG" "$_cs_idx" codesign/codesign 2>/dev/null)" = "1" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the macOS preset uses built-in ad-hoc signing (codesign=1), not Xcode codesign -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
if [ "$(ci_preset_field "$REAL_CFG" "$_cs_idx" notarization/notarization 2>/dev/null)" = "0" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the macOS preset remains accurately unnotarized (notarization=0) -> $_ok"

# ---------------------------------------------------------------------------
# 13. `ci.sh verify-templates`: the publisher digest before extraction, and an
#     installed tree afterwards (M0.1, Opus recheck finding E1). The committed
#     pin cannot match a synthetic archive, so the PASS path is exercised
#     against a copy of the tooling whose pin records the stub's digest -- the
#     same shape as the mismatch path, with the expectation changed.
# ---------------------------------------------------------------------------
TPL_URL="$(ci pin --field templates_url 2>/dev/null)"
TPL_SHA512="$(ci pin --field templates_archive_sha512 2>/dev/null)"

CASES_RUN=$((CASES_RUN + 1))
if hex_is "$TPL_SHA512" 128; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: templates_archive_sha512 is 128 lowercase hex chars -> $_ok"
[ "$_ok" = "yes" ] || log "  value: '$TPL_SHA512'" >&2

CASES_RUN=$((CASES_RUN + 1))
case "$TPL_URL" in
	https://github.com/godotengine/godot/releases/download/*)
		log "case $CASES_RUN: templates_url is the official GitHub release asset -> yes"
		CASES_OK=$((CASES_OK + 1))
		;;
	*)
		log "case $CASES_RUN: templates_url is the official GitHub release asset -> no"
		log "  value: '$TPL_URL'" >&2
		;;
esac

TPL_STUB="$WORK_DIR/templates.tpz"
printf 'roadstorm ci self-test export templates archive\n' >"$TPL_STUB"
TPL_STUB_SHA512="$($SHA512_CMD "$TPL_STUB" | awk '{print $1}')"
[ -n "$TPL_STUB_SHA512" ] || die 2 "could not digest the template test artifact"

# The committed pin must refuse anything that is not the pinned archive, and
# must say so before anything is extracted.
expect_case "verify-templates refuses an artifact that is not the pinned archive" nonzero \
	ci verify-templates --archive "$TPL_STUB"
expect_contains "verify-templates reports a mismatch explicitly" 1 "MISMATCH" \
	ci verify-templates --archive "$TPL_STUB"
expect_contains "verify-templates says not to extract on mismatch" 1 "DO NOT extract" \
	ci verify-templates --archive "$TPL_STUB"
expect_case "verify-templates refuses a missing archive" nonzero \
	ci verify-templates --archive "$WORK_DIR/absent.tpz"
expect_case "verify-templates with no options exits 2" 2 ci verify-templates
expect_case "verify-templates with an unknown option exits 2" 2 ci verify-templates --nope

# make_tools_copy <dir> <templates_archive_sha512 value> : a copy of the
# tooling whose pin records the given template digest, so the PASS path and the
# unrecorded-pin path can be exercised without touching the real pin.
make_tools_copy() {
	_mtc_dir="$1"
	_mtc_value="$2"
	rm -rf "$_mtc_dir"
	mkdir -p "$_mtc_dir"
	( cd "$TOOLS_CI_DIR" && tar -cf - --exclude=./out . ) | ( cd "$_mtc_dir" && tar -xf - ) ||
		die 2 "could not copy the tooling to $_mtc_dir"
	sed "s|^templates_archive_sha512=.*|templates_archive_sha512=$_mtc_value|" \
		"$_mtc_dir/pin/engine.txt" >"$_mtc_dir/pin/engine.txt.tmp" ||
		die 2 "could not rewrite the copied pin"
	mv "$_mtc_dir/pin/engine.txt.tmp" "$_mtc_dir/pin/engine.txt"
}

ci_copy_at() {
	_cca_dir="$1"
	shift
	sh "$_cca_dir/ci.sh" --project "$PROJECT_DIR" "$@"
}

TOOLS_PASS="$WORK_DIR/tools-ci-tpl-pass"
make_tools_copy "$TOOLS_PASS" "$TPL_STUB_SHA512"
expect_case "verify-templates accepts an archive that matches the recorded digest" 0 \
	ci_copy_at "$TOOLS_PASS" verify-templates --archive "$TPL_STUB"
expect_contains "verify-templates says the archive may be extracted" 0 "may be extracted" \
	ci_copy_at "$TOOLS_PASS" verify-templates --archive "$TPL_STUB"

# An unrecorded digest must refuse, never wave the artifact through: the pin
# records what the publisher published, and "not recorded" is not a match.
TOOLS_BLANK="$WORK_DIR/tools-ci-tpl-blank"
make_tools_copy "$TOOLS_BLANK" ""
expect_contains "verify-templates refuses an unrecorded template digest" 1 \
	"no pinned digest recorded" ci_copy_at "$TOOLS_BLANK" verify-templates --archive "$TPL_STUB"

# --dir : an installed tree is verified for its version and for the templates
# this project's presets require.
DIR_TREE="$WORK_DIR/dir-templates"
BAD_TREE="$WORK_DIR/bad-dir-templates"
seed_templates "$DIR_TREE"
seed_templates "$BAD_TREE"
printf '4.7.1.stable\n' >"$BAD_TREE/$TVER/version.txt"

expect_case "verify-templates accepts a complete installed tree" 0 \
	ci_copy_at "$TOOLS_PASS" verify-templates --dir "$DIR_TREE" --mode release
expect_contains "verify-templates fails a tree with the wrong version.txt" 1 "version.txt reports" \
	ci_copy_at "$TOOLS_PASS" verify-templates --dir "$BAD_TREE" --mode release
expect_case "verify-templates refuses a missing tree" nonzero \
	ci_copy_at "$TOOLS_PASS" verify-templates --dir "$WORK_DIR/absent-templates"

# A tree that has the right version but none of the required templates: the
# version check alone must not pass it.
EMPTY_TREE="$WORK_DIR/empty-tree"
mkdir -p "$EMPTY_TREE/$TVER"
printf '%s\n' "$TVER" >"$EMPTY_TREE/$TVER/version.txt"
expect_contains "verify-templates refuses a tree with no required template" 1 \
	"none of [macos.zip" ci_copy_at "$TOOLS_PASS" verify-templates --dir "$EMPTY_TREE" --mode release

# --- install-templates: the publisher's actual .tpz layout -----------------
# The official Godot release packages templates/* at the archive root
# (godot-build-scripts build-release.sh runs `zip ... templates/*` from the
# parent of ${templatesdir}), so there is NO <version>.stable directory inside
# the .tpz. Build a synthetic archive with that layout and exercise the ACTUAL
# install operation end to end against a synthetic destination under this
# suite's private temporary directory -- never the host's installed templates.
if command -v zip >/dev/null 2>&1; then
	TPL_PUB_SRC="$WORK_DIR/publisher-layout"
	rm -rf "$TPL_PUB_SRC"
	mkdir -p "$TPL_PUB_SRC/templates"
	printf '%s\n' "$TVER" >"$TPL_PUB_SRC/templates/version.txt"
	for _tpl_f in macos.zip windows_release_x86_64.exe linux_release.x86_64; do
		printf 'synthetic export template payload for %s\n' "$_tpl_f" \
			>"$TPL_PUB_SRC/templates/$_tpl_f"
	done
	TPL_PUB="$WORK_DIR/publisher-layout.tpz"
	( cd "$TPL_PUB_SRC" && zip -q -r "$TPL_PUB" templates ) ||
		die 2 "could not build the synthetic publisher-layout template archive"
	TPL_PUB_SHA512="$($SHA512_CMD "$TPL_PUB" | awk '{print $1}')"
	[ -n "$TPL_PUB_SHA512" ] || die 2 "could not digest the synthetic publisher-layout archive"

	TOOLS_INSTALL="$WORK_DIR/tools-ci-tpl-install"
	make_tools_copy "$TOOLS_INSTALL" "$TPL_PUB_SHA512"

	INSTALL_DEST="$WORK_DIR/install-dest"
	rm -rf "$INSTALL_DEST"
	mkdir -p "$INSTALL_DEST"
	expect_case "install-templates installs an archive laid out like the publisher's .tpz" 0 \
		ci_copy_at "$TOOLS_INSTALL" --out "$WORK_DIR/install-out" install-templates \
		--archive "$TPL_PUB" --dest "$INSTALL_DEST" --mode release

	CASES_RUN=$((CASES_RUN + 1))
	if [ "$(head -n 1 "$INSTALL_DEST/$TVER/version.txt" 2>/dev/null)" = "$TVER" ] &&
		[ -s "$INSTALL_DEST/$TVER/macos.zip" ] &&
		[ -s "$INSTALL_DEST/$TVER/windows_release_x86_64.exe" ] &&
		[ -s "$INSTALL_DEST/$TVER/linux_release.x86_64" ] &&
		[ ! -e "$INSTALL_DEST/$TVER/templates" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: install-templates places templates/* at <dest>/<version>.stable -> $_ok"

	expect_case "verify-templates accepts the tree install-templates produced" 0 \
		ci_copy_at "$TOOLS_PASS" verify-templates --dir "$INSTALL_DEST" --mode release

	# A payload whose version.txt names another version must be refused BEFORE
	# anything is placed in the destination.
	TPL_BADVER_SRC="$WORK_DIR/bad-version-layout"
	rm -rf "$TPL_BADVER_SRC"
	mkdir -p "$TPL_BADVER_SRC/templates"
	printf '4.7.1.stable\n' >"$TPL_BADVER_SRC/templates/version.txt"
	for _tpl_f in macos.zip windows_release_x86_64.exe linux_release.x86_64; do
		printf 'synthetic export template payload for %s\n' "$_tpl_f" \
			>"$TPL_BADVER_SRC/templates/$_tpl_f"
	done
	TPL_BADVER="$WORK_DIR/bad-version-layout.tpz"
	( cd "$TPL_BADVER_SRC" && zip -q -r "$TPL_BADVER" templates ) ||
		die 2 "could not build the wrong-version template archive"
	TPL_BADVER_SHA512="$($SHA512_CMD "$TPL_BADVER" | awk '{print $1}')"
	TOOLS_BADVER="$WORK_DIR/tools-ci-tpl-badver"
	make_tools_copy "$TOOLS_BADVER" "$TPL_BADVER_SHA512"
	BADVER_DEST="$WORK_DIR/install-badver"
	rm -rf "$BADVER_DEST"
	mkdir -p "$BADVER_DEST"
	expect_case "install-templates refuses a payload whose version.txt is wrong" nonzero \
		ci_copy_at "$TOOLS_BADVER" --out "$WORK_DIR/install-badver-out" install-templates \
		--archive "$TPL_BADVER" --dest "$BADVER_DEST" --mode release
	CASES_RUN=$((CASES_RUN + 1))
	if [ -z "$(ls -A "$BADVER_DEST" 2>/dev/null)" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: a refused install leaves the destination empty -> $_ok"

	# An EXISTING installed tree must be preserved: the command refuses to
	# replace it rather than deleting it. Build a synthetic pre-existing tree
	# and prove two different failures (a valid archive against an existing
	# target, and a wrong-version payload) leave every byte of it alone.
	install_dest_manifest() {
		( cd "$1" && find . -type f | sort | while IFS= read -r _idm_f; do
			printf '%s ' "$_idm_f"
			$SHA512_CMD "$_idm_f" 2>/dev/null | awk '{print $1}'
		done )
	}
	EXIST_DEST="$WORK_DIR/install-existing"
	rm -rf "$EXIST_DEST"
	mkdir -p "$EXIST_DEST/$TVER"
	printf '%s\n' "$TVER" >"$EXIST_DEST/$TVER/version.txt"
	for _tpl_f in macos.zip windows_release_x86_64.exe linux_release.x86_64; do
		printf 'pre-existing synthetic payload for %s\n' "$_tpl_f" \
			>"$EXIST_DEST/$TVER/$_tpl_f"
	done
	printf 'preserve-me\n' >"$EXIST_DEST/$TVER/marker.txt"
	EXIST_BEFORE="$(install_dest_manifest "$EXIST_DEST")"

	expect_case "install-templates refuses to replace an existing target" nonzero \
		ci_copy_at "$TOOLS_INSTALL" --out "$WORK_DIR/install-existing-out" install-templates \
		--archive "$TPL_PUB" --dest "$EXIST_DEST" --mode release
	expect_contains "the refusal names the existing target" 1 \
		"already exists" ci_copy_at "$TOOLS_INSTALL" --out "$WORK_DIR/install-existing-out" \
		install-templates --archive "$TPL_PUB" --dest "$EXIST_DEST" --mode release
	# A different failure (wrong version) must also leave the existing tree
	# untouched, not just the destination-policy refusal.
	expect_case "a wrong-version install leaves an existing target untouched" nonzero \
		ci_copy_at "$TOOLS_BADVER" --out "$WORK_DIR/install-existing-badver-out" \
		install-templates --archive "$TPL_BADVER" --dest "$EXIST_DEST" --mode release
	CASES_RUN=$((CASES_RUN + 1))
	if [ "$EXIST_BEFORE" = "$(install_dest_manifest "$EXIST_DEST")" ] &&
		[ "$(cat "$EXIST_DEST/$TVER/marker.txt" 2>/dev/null)" = "preserve-me" ] &&
		[ "$(find "$EXIST_DEST" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: an existing target survives every failed install -> $_ok"

	# The archive must match the pinned digest before extraction (M0.1).
	TAMPER_DEST="$WORK_DIR/install-tampered"
	rm -rf "$TAMPER_DEST"
	mkdir -p "$TAMPER_DEST"
	expect_case "install-templates refuses an archive that fails the pinned digest" nonzero \
		ci_copy_at "$TOOLS_INSTALL" --out "$WORK_DIR/install-tampered-out" install-templates \
		--archive "$TPL_STUB" --dest "$TAMPER_DEST" --mode release
	CASES_RUN=$((CASES_RUN + 1))
	if [ -z "$(ls -A "$TAMPER_DEST" 2>/dev/null)" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: a digest-refused install leaves the destination empty -> $_ok"

	expect_case "install-templates requires --archive and --dest" 2 \
		ci_copy_at "$TOOLS_INSTALL" install-templates --archive "$TPL_PUB"
else
	log "note: zip is not installed; the install-templates publisher-layout regression was skipped"
fi

# ---------------------------------------------------------------------------
# 14. The workflow's warning watch. The policy lives in
#     tools/ci/scripts/warning_watch.sh, on top of the same classification code
#     `ci.sh` uses, so the workflow and the tooling cannot disagree about which
#     warnings are fatal (Opus recheck W2) and the summary is produced even
#     when an earlier step failed (Sol recheck finding 5, W1).
# ---------------------------------------------------------------------------
WW="$TOOLS_CI_DIR/scripts/warning_watch.sh"
WW_LOGS="$WORK_DIR/ww-logs"
mkdir -p "$WW_LOGS"
WW_SUMMARY="$WORK_DIR/ww-summary.md"

[ -x "$WW" ] || die 2 "missing or non-executable warning watch: $WW"

expect_case "warning_watch exits 0 when there are no captured logs" 0 sh "$WW" "$WORK_DIR/ww-absent"

: >"$WW_LOGS/clean.log"
expect_case "warning_watch exits 0 on a log with no warnings" 0 sh "$WW" "$WW_LOGS"

printf 'WARNING: plain unexpected warning\n' >"$WW_LOGS/plain.log"
expect_contains "warning_watch surfaces a plain warning without failing" 0 \
	"WARNING: plain unexpected warning" sh "$WW" "$WW_LOGS"

printf 'WARNING: Detected another project.godot at res://tools/tick_probe. The folder will be ignored.\n' \
	>"$WW_LOGS/accepted.log"
expect_contains "warning_watch labels an accepted warning" 0 "[accepted]" sh "$WW" "$WW_LOGS"

printf 'WARNING: Jolt Physics job system exceeded the maximum number of jobs. This should not happen.\n' \
	>"$WW_LOGS/jolt.log"
expect_contains "warning_watch fails on a Jolt physics warning" 1 \
	"Jolt Physics job system exceeded" sh "$WW" "$WW_LOGS"
expect_contains "warning_watch prints every warning line, not only the fatal one" 1 \
	"WARNING: plain unexpected warning" sh "$WW" "$WW_LOGS"

rm -f "$WW_LOGS/jolt.log"

# The run summary is written when the environment asks for one, which is what
# makes the step useful after a failure.
: >"$WW_SUMMARY"
GITHUB_STEP_SUMMARY="$WW_SUMMARY" sh "$WW" "$WW_LOGS" >/dev/null 2>&1
CASES_RUN=$((CASES_RUN + 1))
if grep -q '### Engine warnings' "$WW_SUMMARY" &&
	grep -qF 'WARNING: plain unexpected warning' "$WW_SUMMARY"; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: warning_watch writes the markdown run summary -> $_ok"
[ "$_ok" = "yes" ] || sed 's/^/  | /' "$WW_SUMMARY" >&2

# ---------------------------------------------------------------------------
# 15. The workflow file itself. Sol recheck finding 1 is that the committed
#     workflow was INVALID: `hashFiles` is a step-level function and actionlint
#     rejects it in a job-level `if`, which failed the whole workflow including
#     the checks job. The regression case is the absence of that expression; the
#     lint case runs when actionlint is installed (it is not on GitHub runners,
#     so it is reported as skipped there rather than assumed).
# ---------------------------------------------------------------------------
WORKFLOW="$PROJECT_DIR/.github/workflows/ci.yml"

CASES_RUN=$((CASES_RUN + 1))
if [ -f "$WORKFLOW" ] &&
	! grep -nE '^[[:space:]]*if:.*hashFiles' "$WORKFLOW" >/dev/null 2>&1; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: no job-level if: uses the step-level hashFiles function -> $_ok"
[ "$_ok" = "yes" ] || grep -nE '^[[:space:]]*if:.*hashFiles' "$WORKFLOW" >&2

# The export job must always run: a skipped job is a silent green, and the
# presets being absent is a failure `ci.sh export --check` reports explicitly.
CASES_RUN=$((CASES_RUN + 1))
if [ -f "$WORKFLOW" ] &&
	grep -q 'name: export preparation' "$WORKFLOW" &&
	! awk '/^  export-preparation:/{f=1} f && /^    if:/{print; exit}' "$WORKFLOW" | grep -q .; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the export-preparation job carries no job-level condition -> $_ok"

# The warning watch step must run even when an earlier step failed, or the
# summary is skipped exactly when it matters (Sol recheck finding 5).
CASES_RUN=$((CASES_RUN + 1))
if [ -f "$WORKFLOW" ] &&
	grep -A3 'Warning watch - surface engine warnings' "$WORKFLOW" | grep -q 'if: always()'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the warning watch step runs with if: always() -> $_ok"

# The export job must install templates with the command that handles the
# publisher's templates/* layout; searching the archive for a <version>.stable
# directory fails on the official .tpz (coordinator follow-up).
CASES_RUN=$((CASES_RUN + 1))
if [ -f "$WORKFLOW" ] &&
	grep -q 'install-templates --archive' "$WORKFLOW" &&
	! grep -q 'find .* -name "$tver"' "$WORKFLOW"; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the export job installs via install-templates, not a version-directory search -> $_ok"

# The export-logs artifact must be scoped to actual evidence. Uploading all of
# tools/ci/out/ carried the scratch project copy (~100 MB with earlier preset
# packages) into the artifact (Sol/Opus F2).
CASES_RUN=$((CASES_RUN + 1))
_up_block=""
if [ -f "$WORKFLOW" ]; then
	_up_block="$(awk '/name: Upload export logs and reports/{f=1} f{print} f && /name: Upload built packages/{exit}' "$WORKFLOW")"
fi
if [ -n "$_up_block" ] &&
	printf '%s\n' "$_up_block" | grep -q 'tools/ci/out/logs/' &&
	printf '%s\n' "$_up_block" | grep -q 'tools/ci/out/reports/' &&
	! printf '%s\n' "$_up_block" | grep -q 'path:[[:space:]]*tools/ci/out/[[:space:]]*$' &&
	! printf '%s\n' "$_up_block" | grep -q 'project-copy'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the export-logs artifact uploads only logs/ and reports/, not the scratch copy -> $_ok"
[ "$_ok" = "yes" ] || printf '%s\n' "$_up_block" | sed 's/^/  | /' >&2

# A failed or inventory-rejected build must never be uploaded as a successful
# package set. The package upload therefore runs only when every prior step
# succeeded; failure evidence still uploads via the always() logs step.
CASES_RUN=$((CASES_RUN + 1))
_pkg_block=""
if [ -f "$WORKFLOW" ]; then
	_pkg_block="$(awk '/name: Upload built packages/{f=1} f{print}' "$WORKFLOW")"
fi
if [ -n "$_pkg_block" ] && printf '%s\n' "$_pkg_block" | grep -q 'if: success()'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the package upload is skipped unless all prior steps succeeded -> $_ok"
[ "$_ok" = "yes" ] || printf '%s\n' "$_pkg_block" | sed 's/^/  | /' >&2

# M0.5: the contract suites must run from the checked-out candidate in a
# headless standard-library job. It must need no editor/templates, cover all
# five suites, and fail explicitly on a missing or failing suite.
_contract_block=""
if [ -f "$WORKFLOW" ]; then
	_contract_block="$(awk '/^  contract-suites:/{f=1} f{print}' "$WORKFLOW")"
fi

CASES_RUN=$((CASES_RUN + 1))
if [ -n "$_contract_block" ] &&
	printf '%s\n' "$_contract_block" | grep -q '^  contract-suites:' &&
	printf '%s\n' "$_contract_block" | grep -q 'runs-on: ubuntu-latest' &&
	! printf '%s\n' "$_contract_block" | grep -q 'ci.sh' &&
	! printf '%s\n' "$_contract_block" | grep -q 'install-templates'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the contract-suites job is headless and needs no editor/templates -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
_missing_suite=no
for _need_suite in schemas/handling/run_tests.sh fixtures/observation/run_tests.sh \
	fixtures/intent/run_tests.sh fixtures/scenario/run_tests.sh tools/python_pin/tests/test_verify.sh; do
	if ! printf '%s\n' "$_contract_block" | grep -qF -- "$_need_suite"; then
		_missing_suite=yes
	fi
done
if [ "$_missing_suite" = "no" ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the contract-suites job runs all five required suites -> $_ok"

CASES_RUN=$((CASES_RUN + 1))
if printf '%s\n' "$_contract_block" | grep -q 'required contract suite is missing' &&
	printf '%s\n' "$_contract_block" | grep -q 'failed=1' &&
	printf '%s\n' "$_contract_block" | grep -q 'exit 1' &&
	printf '%s\n' "$_contract_block" | grep -q 'bash is unavailable' &&
	printf '%s\n' "$_contract_block" | grep -q 'python3 is unavailable'; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: the contract-suites job fails closed on missing/failing suites and checks bash+python3 -> $_ok"

# Every build/check invocation in the export job must bind its evidence to the
# exact source revision (R3): export --check and each preset export.
CASES_RUN=$((CASES_RUN + 1))
_exp_block=""
if [ -f "$WORKFLOW" ]; then
	_exp_block="$(awk '/^  export-preparation:/{f=1} f{print}' "$WORKFLOW")"
fi
_src_count=0
if [ -n "$_exp_block" ]; then
	_src_count="$(printf '%s\n' "$_exp_block" | grep -Fc -- '--source-sha "${{ github.sha }}"')"
fi
if [ "$_src_count" -ge 2 ]; then
	_ok=yes
	CASES_OK=$((CASES_OK + 1))
else
	_ok=no
fi
log "case $CASES_RUN: every export-job check/build call records the source SHA ($_src_count) -> $_ok"
[ "$_ok" = "yes" ] || printf '%s\n' "$_exp_block" | sed 's/^/  | /' >&2

if command -v actionlint >/dev/null 2>&1; then
	expect_case "actionlint accepts the committed workflow" 0 actionlint "$WORKFLOW"
else
	log "note: actionlint is not installed; the workflow lint case was skipped"
fi

# ---------------------------------------------------------------------------
# 16. A package is more than its main file (Opus recheck finding E3). The Linux
#     preset declares binary_format/embed_pck=false, so the export must write a
#     sidecar .pck next to the output and the tooling must report its digest:
#     the main Linux binary IS the pinned stock template, so its digest
#     identifies no game content at all. Engine-backed and needs the pinned
#     templates installed where the engine reads them, so the case is skipped
#     (and reported as skipped) on a host without them -- a GitHub checks runner
#     has none.
# ---------------------------------------------------------------------------
if [ "$_e2e" = "yes" ]; then
	_real_edir="$(ci_templates_engine_dir 2>/dev/null || true)"
	if [ -n "$_real_edir" ] &&
		[ -s "$_real_edir/$TVER/macos.zip" ] &&
		[ -s "$_real_edir/$TVER/windows_release_x86_64.exe" ] &&
		[ -s "$_real_edir/$TVER/linux_release.x86_64" ]; then
		REALHOME="$WORK_DIR/realhome"
		mkdir -p "$REALHOME"
		_rdir="$(HOME="$REALHOME"; export HOME; ci_templates_engine_dir)"
		mkdir -p "$_rdir/$TVER"
		# The engine needs REAL template binaries to export, so this case copies
		# the three files it needs out of the host's installed tree into the
		# sandbox. They are COPIES, never links: nothing the suite writes can
		# reach an installed template through this path, and the originals are
		# only ever read.
		cp "$_real_edir/$TVER/version.txt" "$_rdir/$TVER/version.txt"
		for _rt in macos.zip windows_release_x86_64.exe linux_release.x86_64; do
			cp "$_real_edir/$TVER/$_rt" "$_rdir/$TVER/$_rt" ||
				die 2 "could not copy the installed template $_rt into the sandbox"
		done
		cp "$REAL_CFG" "$SPROJ/export_presets.cfg"
		PKG="$WORK_DIR/pkg"
		mkdir -p "$PKG"
		# ci_abs_path resolves existing prefixes physically, so the report names
		# the real path even when TMPDIR itself is a symlink (macOS /var).
		_pkg_dir="$(cd "$PKG" && pwd -P)"
		expect_case "export builds the Linux preset with the pinned templates" 0 \
			ci_at_home "$REALHOME" "$SPROJ" --source-sha "deadbeefcafe1234" \
			export --export "Linux x86-64" --out "$PKG/linux"
		# The report the run wrote must carry the sidecar's path and digest: the
		# main Linux binary is the pinned stock template, so its digest alone
		# says nothing about the game content that was packaged.
		expect_contains "export reports the sidecar .pck path and digest (E3)" 0 \
			"pck=$_pkg_dir/linux.pck" grep -h "export result=pass" \
			"$SPROJ/tools/ci/out/reports/"export-*.txt
		CASES_RUN=$((CASES_RUN + 1))
		if [ -s "$PKG/linux.pck" ] &&
			grep -qh "pck_sha256=[0-9a-f]\{64\}" "$SPROJ/tools/ci/out/reports/"export-*.txt; then
			_ok=yes
			CASES_OK=$((CASES_OK + 1))
		else
			_ok=no
		fi
		log "case $CASES_RUN: the Linux package's sidecar .pck exists, is non-empty and is hashed -> $_ok"

	# The inventory report filename carries the supplied source SHA, so a
	# downloaded artifact names its source revision (R3). Without a SHA it keeps
	# the plain per-preset name used by the other cases.
		CASES_RUN=$((CASES_RUN + 1))
		if [ -s "$SPROJ/tools/ci/out/reports/export-package-inventory-linux-x86-64-deadbeefcafe.txt" ]; then
			_ok=yes
			CASES_OK=$((CASES_OK + 1))
		else
			_ok=no
		fi
		log "case $CASES_RUN: the inventory report filename carries the supplied source SHA -> $_ok"

	# Relative --out for every preset, from a caller-specified working
	# directory, exactly as the workflow invokes it. Before canonicalisation,
	# Godot resolved the relative path against --path (the scratch project),
	# so the wrapper reported "export produced no output" while the package sat
	# in tools/ci/out/project-copy/. Each preset gets its own caller directory
	# and its own output name; the checks below run immediately after that
	# preset's export, before the next run replaces the scratch copy.
	while IFS='|' read -r _rp_name _rp_ext; do
		[ -n "$_rp_name" ] || continue
		_rp_cwd="$WORK_DIR/relcwd-$(printf '%s' "$_rp_name" | tr ' ' '-')"
		rm -rf "$_rp_cwd"
		mkdir -p "$_rp_cwd"
		_rp_out="build/${_rp_name}${_rp_ext:+.$_rp_ext}"
		expect_case "relative --out exports preset '$_rp_name'" 0 \
			ci_rel_at_home "$_rp_cwd" "$REALHOME" "$SPROJ" export --export "$_rp_name" --out "$_rp_out"
		_rp_expected="$_rp_cwd/build/${_rp_name}${_rp_ext:+.$_rp_ext}"
		CASES_RUN=$((CASES_RUN + 1))
		if [ -s "$_rp_expected" ]; then
			_ok=yes
			CASES_OK=$((CASES_OK + 1))
		else
			_ok=no
		fi
		log "case $CASES_RUN: preset '$_rp_name' wrote its package at the caller-relative path -> $_ok"
		[ "$_ok" = "yes" ] || log "  expected a non-empty file at '$_rp_expected'" >&2

		CASES_RUN=$((CASES_RUN + 1))
		if [ ! -e "$SPROJ/tools/ci/out/project-copy/$_rp_out" ]; then
			_ok=yes
			CASES_OK=$((CASES_OK + 1))
		else
			_ok=no
		fi
		log "case $CASES_RUN: preset '$_rp_name' did NOT write into the scratch project copy -> $_ok"

		# F1: per-preset engine logs must survive, not be overwritten by the
		# next invocation's identical export-2-export.log name.
		_rp_slug="$(ci_preset_slug "$_rp_name")"
		CASES_RUN=$((CASES_RUN + 1))
		if [ -s "$SPROJ/tools/ci/out/logs/export-${_rp_slug}-2-export.log" ]; then
			_ok=yes
			CASES_OK=$((CASES_OK + 1))
		else
			_ok=no
		fi
		log "case $CASES_RUN: preset '$_rp_name' kept its own engine export log -> $_ok"

		# F3: ci.sh runs the pack inventory on every built package and leaves a
		# report under reports/ for the narrowed upload.
		CASES_RUN=$((CASES_RUN + 1))
		if [ -s "$SPROJ/tools/ci/out/reports/export-package-inventory-${_rp_slug}.txt" ]; then
			_ok=yes
			CASES_OK=$((CASES_OK + 1))
		else
			_ok=no
		fi
		log "case $CASES_RUN: preset '$_rp_name' produced a package inventory report -> $_ok"

		# The per-run report must carry the same preset slug as the logs.
		_rp_report_found=no
		for _rp_f in "$SPROJ/tools/ci/out/reports/export-${_rp_slug}"-*.txt; do
			if [ -s "$_rp_f" ]; then
				_rp_report_found=yes
				break
			fi
		done
		CASES_RUN=$((CASES_RUN + 1))
		if [ "$_rp_report_found" = "yes" ]; then
			_ok=yes
			CASES_OK=$((CASES_OK + 1))
		else
			_ok=no
			fi
		log "case $CASES_RUN: preset '$_rp_name' kept its own named run report -> $_ok"
	done <<EOF
macOS Apple Silicon|zip
Windows x86-64|exe
Linux x86-64|
EOF

	# R2: a pre-existing output or sidecar must be REFUSED, never silently
	# reused by a later engine run that writes nothing, and never deleted or
	# overwritten by ci.sh. Both files stay byte-identical.
	REFUSE_CWD="$WORK_DIR/refuse-cwd"
	rm -rf "$REFUSE_CWD"
	mkdir -p "$REFUSE_CWD/build"
	printf 'STALE MAIN\n' >"$REFUSE_CWD/build/stale-package"
	printf 'STALE PCK\n' >"$REFUSE_CWD/build/stale-package.pck"
	REFUSE_LOG="$WORK_DIR/refuse-export.log"
	ci_rel_at_home "$REFUSE_CWD" "$REALHOME" "$SPROJ" --godot "$_e2e_bin" \
		export --export "Linux x86-64" --out "build/stale-package" \
		>"$REFUSE_LOG" 2>&1
	_refuse_rc=$?
	CASES_RUN=$((CASES_RUN + 1))
	if [ "$_refuse_rc" -ne 0 ] &&
		grep -q "refusing to overwrite existing output" "$REFUSE_LOG" &&
		! grep -q "export result=pass" "$REFUSE_LOG" &&
		[ "$(cat "$REFUSE_CWD/build/stale-package")" = "STALE MAIN" ] &&
		[ "$(cat "$REFUSE_CWD/build/stale-package.pck")" = "STALE PCK" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: an existing main+sidecar target is refused and left byte-identical -> $_ok"
	[ "$_ok" = "yes" ] || sed 's/^/  | /' "$REFUSE_LOG" >&2

	# A leftover sidecar alone must also refuse: otherwise an engine run that
	# wrote no main file could still be validated against old pack bytes.
	rm -f "$REFUSE_CWD/build/stale-package"
	REFUSE_LOG2="$WORK_DIR/refuse-export-2.log"
	ci_rel_at_home "$REFUSE_CWD" "$REALHOME" "$SPROJ" --godot "$_e2e_bin" \
		export --export "Linux x86-64" --out "build/stale-package" \
		>"$REFUSE_LOG2" 2>&1
	_refuse_rc2=$?
	CASES_RUN=$((CASES_RUN + 1))
	if [ "$_refuse_rc2" -ne 0 ] &&
		grep -q "refusing to overwrite existing output" "$REFUSE_LOG2" &&
		[ "$(cat "$REFUSE_CWD/build/stale-package.pck")" = "STALE PCK" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: a pre-existing sidecar alone is refused, not treated as the package -> $_ok"

	# A dangling symlink at the target is an existing path too: ci.sh must
	# never write through a link.
	ln -s "$REFUSE_CWD/does-not-exist" "$REFUSE_CWD/build/broken-package"
	REFUSE_LOG3="$WORK_DIR/refuse-export-3.log"
	ci_rel_at_home "$REFUSE_CWD" "$REALHOME" "$SPROJ" --godot "$_e2e_bin" \
		export --export "Linux x86-64" --out "build/broken-package" \
		>"$REFUSE_LOG3" 2>&1
	_refuse_rc3=$?
	CASES_RUN=$((CASES_RUN + 1))
	if [ "$_refuse_rc3" -ne 0 ] &&
		grep -q "refusing to overwrite existing output" "$REFUSE_LOG3" &&
		[ ! -e "$REFUSE_CWD/build/broken-package" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: a dangling symlink target is refused and never written through -> $_ok"

	# End-to-end Sol 245ee1d reproduction: `via -> elsewhere/inner` and a
	# caller-relative --out of `via/../package`. Filesystem semantics put the
	# package in elsewhere/, not beside the symlink.
	SYM_CWD="$WORK_DIR/symcwd"
	SYM_ELSE="$WORK_DIR/symelsewhere"
	rm -rf "$SYM_CWD" "$SYM_ELSE"
	mkdir -p "$SYM_CWD" "$SYM_ELSE/inner"
	ln -s "$SYM_ELSE/inner" "$SYM_CWD/via"
	if [ -L "$SYM_CWD/via" ]; then
		expect_case "a symlink+'..' --out exports at the filesystem-resolved path" 0 \
			ci_rel_at_home "$SYM_CWD" "$REALHOME" "$SPROJ" export --export "Linux x86-64" --out "via/../package"
		_sym_else_real="$(cd "$SYM_ELSE" && pwd -P)"
		CASES_RUN=$((CASES_RUN + 1))
		if [ -s "$_sym_else_real/package" ] && [ ! -e "$SYM_CWD/package" ]; then
			_ok=yes
			CASES_OK=$((CASES_OK + 1))
		else
			_ok=no
		fi
		log "case $CASES_RUN: the exported package is at the resolved target parent, not the symlink parent -> $_ok"
		[ "$_ok" = "yes" ] || log "  expected '$_sym_else_real/package', found no such file or found '$SYM_CWD/package'" >&2
	else
		log "note: symlinks are unavailable; the end-to-end symlink+'..' export case was skipped"
	fi

	# All three presets ran in separate processes; their export logs must all
	# still exist with distinct names.
	CASES_RUN=$((CASES_RUN + 1))
	if [ "$(ls -1 "$SPROJ/tools/ci/out/logs/"export-*-2-export.log 2>/dev/null | wc -l | tr -d ' ')" = "3" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: all three preset export logs survived with distinct names -> $_ok"

	# Sol 8c6c928 fault injection: delegate to the real pinned editor, then
	# replace the freshly written sidecar .pck with garbage after a successful
	# --export-release call. The wrapper lives only in this suite's private
	# temporary directory; it links nothing and writes no installed tool.
	CORRUPT_GODOT="$WORK_DIR/godot-corrupt-pck"
	cat >"$CORRUPT_GODOT" <<EOF
#!/bin/sh
_real="$_e2e_bin"
"\$_real" "\$@"
_rc=\$?
case " \$* " in
	*" --export-"*)
		[ "\$_rc" -eq 0 ] || exit "\$_rc"
		_last=""
		for _a in "\$@"; do _last="\$_a"; done
		_dir="\$(dirname "\$_last")"
		_base="\$(basename "\$_last")"
		_stem="\${_base%%.*}"
		[ -n "\$_stem" ] || _stem="\$_base"
		printf 'corrupt pack\n' >"\$_dir/\$_stem.pck" 2>/dev/null
		;;
esac
exit "\$_rc"
EOF
	chmod +x "$CORRUPT_GODOT"
	CORRUPT_CWD="$WORK_DIR/corrupt-cwd"
	rm -rf "$CORRUPT_CWD"
	mkdir -p "$CORRUPT_CWD"
	CORRUPT_LOG="$WORK_DIR/corrupt-export.log"
	ci_rel_at_home "$CORRUPT_CWD" "$REALHOME" "$SPROJ" --godot "$CORRUPT_GODOT" \
		export --export "Linux x86-64" --out "build/corrupt-package" \
		>"$CORRUPT_LOG" 2>&1
	_corrupt_rc=$?
	CASES_RUN=$((CASES_RUN + 1))
	if [ "$_corrupt_rc" -ne 0 ] &&
		grep -q "package inventory check FAILED" "$CORRUPT_LOG" &&
		! grep -q "export: PASS" "$CORRUPT_LOG" &&
		! grep -q "export result=pass" "$CORRUPT_LOG"; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: a corrupted package exits nonzero, prints no PASS and names the inventory failure -> $_ok"
	[ "$_ok" = "yes" ] || sed 's/^/  | /' "$CORRUPT_LOG" >&2

	# The per-run report must carry exactly one verdict, and it must be the
	# failing one. A stale or premature pass line would leave a rejected build
	# looking successful to any consumer of the report.
	_corrupt_rep="$(ls -1t "$SPROJ/tools/ci/out/reports/"export-linux-x86-64-*.txt 2>/dev/null | head -n 1)"
	CASES_RUN=$((CASES_RUN + 1))
	if [ -n "$_corrupt_rep" ] &&
		[ "$(grep -c '^export result=' "$_corrupt_rep" 2>/dev/null)" = "1" ] &&
		grep -q '^export result=fail .*reason=pack-inventory' "$_corrupt_rep"; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: the rejected export report carries one fail verdict and no pass verdict -> $_ok"

	# A failed inventory run must not leave an older PASS report at the same
	# per-preset path behind it.
	CASES_RUN=$((CASES_RUN + 1))
	if [ ! -s "$SPROJ/tools/ci/out/reports/export-package-inventory-linux-x86-64.txt" ]; then
		_ok=yes
		CASES_OK=$((CASES_OK + 1))
	else
		_ok=no
	fi
	log "case $CASES_RUN: a rejected run leaves no stale passing inventory report -> $_ok"
	else
		log "note: the pinned export templates are not installed on this host; the sidecar .pck export case was skipped"
	fi
else
	log "note: no installed Godot matches pin '$_e2e_pin'; the sidecar .pck export case was skipped"
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
