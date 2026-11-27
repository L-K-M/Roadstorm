#!/bin/sh
# Roadstorm Racer! - warning watch for the CI workflow.
#
# Ownership: tools/ci/** only (PLAN.md "How agents execute the plan").
#
# Why this script exists: the workflow's warning step used to re-implement the
# warning policy inline, and it drifted from `ci.sh` in three measured ways:
#   * it ran under the default success condition, so the test stage that failed
#     on a Jolt warning skipped the summary meant to surface it (Sol recheck
#     finding 5, Opus recheck W1);
#   * it failed on ANY line containing "jolt", including one the project had
#     accepted in tools/ci/warnings.allow, so the workflow and `ci.sh` disagreed
#     about what was fatal (Opus recheck W2);
#   * after a Jolt warning had already failed a check it still printed the
#     "surfaced, not fatal" summary (Opus recheck W3).
#
# This script is the workflow's warning policy, implemented once, on top of the
# SAME classification code `ci.sh` uses (lib/common.sh's ci_log_* helpers and
# tools/ci/warnings.allow), so the two cannot drift apart again:
#   * every WARNING/USER WARNING line found in the captured engine logs is
#     printed, never filtered;
#   * a line the project has accepted is labelled as accepted;
#   * an unaccepted line matching one of the five known Jolt physics warnings
#     fails (exit 1): every one means contacts were ignored or a slower
#     allocator was used, so such a run is not a clean pass (the open R7 item
#     is the job-system one). The match is on those message shapes, not on the
#     substring "jolt": a benign nested-project path such as
#     res://tools/jolt_inventory is reported, not failed;
#   * any other warning is reported, not fatal -- a warning is not an error, and
#     failing for the wrong reason is the defect this tooling avoids elsewhere.
#
# Usage:
#   tools/ci/scripts/warning_watch.sh [logdir]
#   logdir defaults to <project>/tools/ci/out/logs
#
# Environment:
#   GITHUB_STEP_SUMMARY  when set, a markdown summary is appended to it
#   GITHUB_ACTIONS       when "true", the failure is also emitted as a
#                        GitHub ::error:: annotation
#
# Exit codes: 0 = no Jolt warning, 1 = a Jolt warning appeared, 2 = the harness
# could not run.
# Original project code under the Unlicense.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_CI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$TOOLS_CI_DIR/../.." && pwd)}"

# shellcheck source=lib/common.sh
. "$TOOLS_CI_DIR/lib/common.sh"

# common.sh looks the accepted-warning list up relative to $CI_TOOLS_DIR, which
# ci.sh sets before sourcing it. This script is also run directly by the
# workflow, so set it here too: without it the allow-list would resolve to
# nothing and every warning, including an accepted one, would look unexpected.
CI_TOOLS_DIR="$TOOLS_CI_DIR"

LOG_DIR="${1:-}"
[ -n "$LOG_DIR" ] || LOG_DIR="$PROJECT_DIR/tools/ci/out/logs"

# No captured logs is not a warning problem: whatever failed earlier already
# failed the job. Report it and exit 0 rather than inventing a failure here.
if [ ! -d "$LOG_DIR" ]; then
	printf '[warning-watch] no captured engine logs at %s; nothing to watch\n' "$LOG_DIR"
	exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/roadstorm-warning-watch.XXXXXX" 2>/dev/null)" || {
	printf '[warning-watch] FAIL: could not create a temporary directory\n' >&2
	exit 2
}
trap 'rm -rf "$WORK"' EXIT INT TERM

# The run summary is GitHub-specific; without it the script still prints
# everything to stdout and only the markdown copy is skipped.
SUMMARY="${GITHUB_STEP_SUMMARY:-}"
[ -n "$SUMMARY" ] || SUMMARY="/dev/null"

ALL="$WORK/all.txt"
UNEXPECTED="$WORK/unexpected.txt"
LABELLED="$WORK/labelled.txt"
: >"$ALL"
: >"$UNEXPECTED"
: >"$LABELLED"

# Every warning line the captured logs contain, deduplicated. The classification
# below then decides what each one means; nothing is dropped before that.
find "$LOG_DIR" -type f -name '*.log' 2>/dev/null | LC_ALL=C sort | while IFS= read -r _f; do
	[ -f "$_f" ] || continue
	grep -hE '^(WARNING|USER WARNING):' "$_f" 2>/dev/null || true
done | LC_ALL=C sort -u >"$ALL"

_total="$(ci_count_lines <"$ALL")"

if [ "$_total" = "0" ]; then
	printf '[warning-watch] no WARNING: lines in the captured engine logs\n'
	{
		echo "### Engine warnings"
		echo ""
		echo "No \`WARNING:\` lines in the captured engine logs."
	} >>"$SUMMARY"
	exit 0
fi

while IFS= read -r _line || [ -n "$_line" ]; do
	[ -n "$_line" ] || continue
	if ci_warning_is_accepted "$_line"; then
		printf '%s\taccepted\n' "$_line" >>"$LABELLED"
	else
		printf '%s\n' "$_line" >>"$UNEXPECTED"
		printf '%s\tunexpected\n' "$_line" >>"$LABELLED"
	fi
done <"$ALL"

_unexpected="$(ci_count_lines <"$UNEXPECTED")"
_accepted=$((_total - _unexpected))

# Shared classification: ci_is_jolt_physics_warning (lib/common.sh) decides this,
# so the workflow and `ci.sh` cannot disagree about what a physics warning is.
# A grep for the substring "jolt" classified the benign nested-project warning
# for res://tools/jolt_inventory as a physics failure in hosted run
# 45921573623.
_JOLT_LINES="$WORK/jolt-lines.txt"
: >"$_JOLT_LINES"
while IFS= read -r _ww_line || [ -n "$_ww_line" ]; do
	[ -n "$_ww_line" ] || continue
	ci_is_jolt_physics_warning "$_ww_line" && printf '%s\n' "$_ww_line" >>"$_JOLT_LINES"
done <"$UNEXPECTED"
_jolt="$(cat "$_JOLT_LINES" 2>/dev/null || true)"

# Printed first, so the verdict can never hide the lines it was reached from.
printf '[warning-watch] %s warning line(s) in %s, %s not accepted in %s\n' \
	"$_total" "$LOG_DIR" "$_unexpected" "$CI_WARNINGS_ALLOW"
while IFS="$(printf '\t')" read -r _line _label || [ -n "$_line" ]; do
	[ -n "$_line" ] || continue
	printf '  %s [%s]\n' "$_line" "$_label"
done <"$LABELLED"

{
	echo "### Engine warnings"
	echo ""
	echo '```'
	cat "$ALL"
	echo '```'
	echo ""
	echo "$_total warning line(s) in the captured engine logs; $_unexpected not"
	echo "accepted in \`$CI_WARNINGS_ALLOW\`. Every line is printed here rather"
	echo "than filtered, and an accepted one is labelled above."
	if [ "$_accepted" -gt 0 ]; then
		echo ""
		echo "$_accepted line(s) are listed in \`tools/ci/warnings.allow\` as"
		echo "recorded acceptances; they are still printed on every run."
	fi
} >>"$SUMMARY"

if [ -n "$_jolt" ]; then
	printf '[warning-watch] FAIL: a Jolt physics warning appeared in the engine logs.\n' >&2
	printf '  the pinned engine Jolt warnings all mean contacts were ignored\n' >&2
	printf '  or a slower allocator was used, so this run is not a clean pass\n' >&2
	printf '  (the open R7 item is the job-system one).\n' >&2
	if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
		echo "::error::a Jolt physics warning appeared in the engine logs. The pinned engine's Jolt warnings all mean contacts were ignored or a slower allocator was used, so this run is not a clean pass."
	fi
	printf '%s\n' "$_jolt" | sed 's/^/  /' >&2
	exit 1
fi

printf '[warning-watch] PASS: no physics-backend (Jolt) warnings in the captured engine logs\n'
exit 0
