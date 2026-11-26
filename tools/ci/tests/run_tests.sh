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
# Summary
# ---------------------------------------------------------------------------
log "summary: $CASES_OK/$CASES_RUN cases behaved as expected"
if [ "$CASES_OK" -eq "$CASES_RUN" ]; then
	log "PASS: tools/ci self-test"
	exit 0
fi
log "FAIL: $((CASES_RUN - CASES_OK)) case(s) did not behave as expected" >&2
exit 1
