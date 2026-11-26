#!/bin/sh
# Roadstorm Racer! - runtime-error gate regression for `ci.sh test`.
#
# Ownership: tools/ci/** only (PLAN.md "How agents execute the plan").
#
# What this proves, and why it exists: Opus recheck finding N1 recorded that the
# committed CI ran tools/smoke/boot_smoke.gd directly with `--script`, judged it
# only on its exit status, and therefore reported PASS for a runtime script
# error -- while the supported entry point tools/smoke/run_boot_smoke.sh failed
# on the same tree. The fix lives in ci_run_one_test (ci.sh): every discovered
# check is judged on its exit status AND on its captured engine log. This
# harness proves that fix, and keeps proving it, by injecting the defects into
# isolated snapshot copies and checking the ACTUAL exit status of `ci.sh test`.
#
# Cases, each in its own throwaway snapshot copy. The expected exit status is the
# assertion; the needles additionally require the engine's own error/warning
# line to be in the output, so a case cannot pass because of an unrelated
# failure:
#   1. clean snapshot                     -> exit 0, and the deliberate-failure
#                                            exit-code proof still ran (M0.4)
#   2. missing dictionary key in _ready   -> exit 1, with the engine's
#                                            `SCRIPT ERROR: Invalid access to
#                                            property or key 'missing_key'`
#                                            line in the output (the N1 repro;
#                                            with the default target the log
#                                            gate is what catches it)
#   3. push_error() in _ready             -> exit 1, with the engine's
#                                            `ERROR: ...` line in the output
#                                            (the same hole, different engine
#                                            message)
#   4. push_warning() in _ready, default  -> exit 0 AND the warning is surfaced:
#                                            the negative control that shows the
#                                            gate fails on engine errors, not on
#                                            any stderr output
#   5. push_warning() in _ready, --strict-warnings
#                                         -> exit 1: a warning the project has
#                                            not accepted is not silently passed
#   6. a Jolt physics warning in _ready   -> exit 1: the pinned engine's Jolt
#                                            warnings all mean contacts were
#                                            ignored or a slower allocator was
#                                            used, so one must never pass
#                                            unnoticed (open item R7)
#
# The injected defects are runtime errors: the script still parses, the scene
# still loads, the boot handoff still completes and the engine exits 0. Only the
# log shows them, which is exactly why the exit status alone was not enough.
#
# Isolation (the same rules as tools/smoke/fault_injection.sh): the live
# checkout is only ever READ. Each case runs against a snapshot copy with no
# .git, no .godot and no work/, in a private temporary directory with its own
# HOME, TMPDIR and XDG tree, so no engine cache touches the live tree.
# Fingerprints of the files this harness injects into are taken before and
# after; a change in the live checkout fails the run instead of being ignored.
# Every engine invocation is bounded twice over: ci.sh's own per-invocation
# --timeout, and this harness's per-case wall-clock watchdog.
#
# Usage:
#   tools/ci/scripts/runtime_error_gate.sh
#   GODOT_BIN=/path/to/godot tools/ci/scripts/runtime_error_gate.sh
#   GATE_TARGET_SCRIPT=src/boot/main_menu.gd tools/ci/scripts/runtime_error_gate.sh
#   GATE_TIMEOUT=180 GATE_CASE_TIMEOUT=1200 tools/ci/scripts/runtime_error_gate.sh
#
# Environment:
#   GODOT_BIN           Godot editor binary (default: PATH, then common paths)
#   GATE_TARGET_SCRIPT  project-relative script to inject into
#                       (default: the first of src/boot/game.gd,
#                       src/boot/main_menu.gd, src/boot/boot.gd that exists)
#   GATE_TIMEOUT        per-engine-invocation limit passed to ci.sh (default 120)
#   GATE_CASE_TIMEOUT   per-case wall-clock limit for the whole ci.sh run
#                       (default 900)
#
# Exit codes: 0 = every case behaved as expected, 1 = a case misbehaved,
# 2 = the harness could not run.
# Original project code under the Unlicense.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_CI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$TOOLS_CI_DIR/../.." && pwd)}"
CI_SH="$TOOLS_CI_DIR/ci.sh"

GODOT_BIN="${GODOT_BIN:-}"
GATE_TIMEOUT="${GATE_TIMEOUT:-120}"
GATE_CASE_TIMEOUT="${GATE_CASE_TIMEOUT:-900}"
GATE_TARGET_SCRIPT="${GATE_TARGET_SCRIPT:-}"

CASES_RUN=0
CASES_OK=0

log() {
	printf '[runtime-error-gate] %s\n' "$*"
}

die() {
	_code="$1"
	shift
	log "FAIL: $*" >&2
	exit "$_code"
}

[ -f "$CI_SH" ] || die 2 "missing entry point: $CI_SH"
[ -f "$PROJECT_DIR/project.godot" ] || die 2 "'$PROJECT_DIR' has no project.godot"

# --- tool discovery ---------------------------------------------------------

[ -n "$GODOT_BIN" ] || GODOT_BIN="$(command -v godot 2>/dev/null || true)"
if [ -z "$GODOT_BIN" ]; then
	for candidate in \
		"$(command -v godot4 2>/dev/null)" \
		"$(command -v Godot 2>/dev/null)" \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"/opt/homebrew/bin/godot" \
		"/usr/local/bin/godot" \
		"/usr/bin/godot"
	do
		if [ -n "$candidate" ] && [ -x "$candidate" ]; then
			GODOT_BIN="$candidate"
			break
		fi
	done
fi
[ -n "$GODOT_BIN" ] || die 2 "no Godot binary found; set GODOT_BIN"
[ -x "$GODOT_BIN" ] || [ "$GODOT_BIN" = "godot" ] || die 2 "'$GODOT_BIN' is not executable"

command -v python3 >/dev/null 2>&1 || die 2 "python3 is required to inject the faults"
if command -v shasum >/dev/null 2>&1; then
	SHA_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
	SHA_CMD="sha256sum"
else
	die 2 "no sha256 tool found (shasum or sha256sum)"
fi

case "$GATE_TIMEOUT" in
	'' | *[!0-9]* | 0) die 2 "GATE_TIMEOUT must be a positive integer (got '$GATE_TIMEOUT')" ;;
esac
case "$GATE_CASE_TIMEOUT" in
	'' | *[!0-9]* | 0) die 2 "GATE_CASE_TIMEOUT must be a positive integer (got '$GATE_CASE_TIMEOUT')" ;;
esac

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roadstorm-runtime-error-gate.XXXXXX" 2>/dev/null)" ||
	die 2 "could not create a temporary working directory"
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

# Normalise the working directory to a clean absolute path. A TMPDIR that is
# relative or contains a `..` component would otherwise be inherited by the
# sandbox HOME, and the pinned engine refuses to create directories under a path
# it cannot resolve (measured: "ERROR: Could not create ObjectDB Snapshots
# directory" on a HEADless --import), which would fail the clean control case
# for a reason that has nothing to do with the gate.
WORK_DIR="$(cd "$WORK_DIR" 2>/dev/null && pwd)" ||
	die 2 "could not resolve the temporary working directory to an absolute path"
[ -d "$WORK_DIR" ] || die 2 "temporary working directory disappeared: $WORK_DIR"

SNAPSHOT="$WORK_DIR/snapshot"
SANDBOX_HOME="$WORK_DIR/home"
SANDBOX_TMP="$WORK_DIR/tmp"
SANDBOX_XDG_CACHE="$WORK_DIR/xdg-cache"
SANDBOX_XDG_DATA="$WORK_DIR/xdg-data"
SANDBOX_XDG_CONFIG="$WORK_DIR/xdg-config"
CASE_LOG="$WORK_DIR/case.log"

# TMPDIR may point inside the project. Excluding this harness's own scratch
# directory from the snapshot then matters: without it the snapshot would copy
# itself (nondeterministic case inputs, and a tar that fails on files that change
# as they are read), which would fail the clean control case for a reason that
# has nothing to do with the gate.
SNAPSHOT_EXCLUDES=""
case "$WORK_DIR" in
	"$PROJECT_DIR"/*) SNAPSHOT_EXCLUDES="--exclude=./${WORK_DIR#$PROJECT_DIR/}" ;;
esac

# --- helpers ----------------------------------------------------------------

# run_bounded <seconds> <command...>
# Wall-clock limit around a whole case. POSIX has no `timeout`, and a hung
# engine must not hang this harness (the same supervision shape as
# ci_run_godot in lib/common.sh).
run_bounded() {
	_limit="$1"
	shift
	( "$@" ) &
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

# Fingerprint of everything this harness could conceivably disturb in the live
# checkout: the boot scripts and scenes it reads from, and project.godot.
live_fingerprint() {
	(
		cd "$PROJECT_DIR" || exit 1
		find src/boot scenes -type f -exec $SHA_CMD {} + 2>/dev/null
		$SHA_CMD project.godot 2>/dev/null
	) | LC_ALL=C sort
}

# Throwaway snapshot: no VCS data, no engine cache, no agent work directory and
# no previous CI scratch output.
make_snapshot() {
	rm -rf "$SNAPSHOT"
	mkdir -p "$SNAPSHOT"
	(
		cd "$PROJECT_DIR" || exit 1
		tar -cf - --exclude=./.git --exclude=./.godot --exclude=./work \
			--exclude=./tools/ci/out $SNAPSHOT_EXCLUDES .
	) | (cd "$SNAPSHOT" && tar -xf -)
	[ -f "$SNAPSHOT/project.godot" ] || return 1
	[ -f "$SNAPSHOT/tools/ci/ci.sh" ] || return 1
	[ -f "$SNAPSHOT/$GATE_TARGET_SCRIPT" ] || return 1
	return 0
}

# Insert a statement at the top of the target script's _ready() in the SNAPSHOT.
# The statement is a runtime error, not a parse error: the script still compiles,
# the scene still instantiates and the engine still exits 0.
inject_statement() {
	# inject_statement <gdscript-statement>
	python3 - "$SNAPSHOT/$GATE_TARGET_SCRIPT" "$1" <<'PYEOF'
import sys

path, statement = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
	source = handle.read()
needle = "func _ready() -> void:\n"
if needle not in source:
	sys.exit("no 'func _ready() -> void:' found in %s" % path)
source = source.replace(needle, needle + "\t" + statement + "\n", 1)
with open(path, "w", encoding="utf-8") as handle:
	handle.write(source)
PYEOF
}

# newest test report written by the snapshot's ci.sh run
latest_report() {
	ls -1t "$SNAPSHOT/tools/ci/out/reports/test-"*.txt 2>/dev/null | head -n 1
}

# run_gate_case <description> <pass|fail> <stdout-needles> <report-needle>
#              [ci.sh arguments...]
#   stdout-needles  a ';'-separated list; EVERY needle must appear in the case
#                   output (an empty string checks nothing)
#   report-needle   must appear in the newest test report the run wrote (an
#                   empty string checks nothing)
# The snapshot state is the case input; the caller injects the defect first and
# restores a clean snapshot afterwards.
run_gate_case() {
	_desc="$1"
	_expect="$2"
	_needles="$3"
	_report_needle="$4"
	shift 4
	CASES_RUN=$((CASES_RUN + 1))

	rm -rf "$SNAPSHOT/tools/ci/out" "$SNAPSHOT/.godot"
	: >"$CASE_LOG"
	(
		cd "$SNAPSHOT" || exit 2
		PROJECT_DIR="$SNAPSHOT"; export PROJECT_DIR
		GODOT_BIN="$GODOT_BIN"; export GODOT_BIN
		HOME="$SANDBOX_HOME"; export HOME
		TMPDIR="$SANDBOX_TMP"; export TMPDIR
		XDG_CACHE_HOME="$SANDBOX_XDG_CACHE"; export XDG_CACHE_HOME
		XDG_DATA_HOME="$SANDBOX_XDG_DATA"; export XDG_DATA_HOME
		XDG_CONFIG_HOME="$SANDBOX_XDG_CONFIG"; export XDG_CONFIG_HOME
		PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
		NO_COLOR=1; export NO_COLOR
		run_bounded "$GATE_CASE_TIMEOUT" \
			sh "$SNAPSHOT/tools/ci/ci.sh" --project "$SNAPSHOT" --timeout "$GATE_TIMEOUT" "$@"
	) >"$CASE_LOG" 2>&1
	_status=$?

	_ok=no
	_reason=""
	if [ "$_expect" = "pass" ]; then
		[ "$_status" -eq 0 ] || _reason="expected exit 0, got $_status"
	else
		[ "$_status" -ne 0 ] || _reason="expected a nonzero exit, got 0"
	fi
	if [ -n "$_reason" ]; then
		:
	elif [ -n "$_needles" ]; then
		# An exit status alone does not prove the failure came from the engine
		# error rather than from something else, so every needle must be present.
		_remaining="$_needles"
		while [ -n "$_remaining" ]; do
			_needle="${_remaining%%;*}"
			if [ "$_needle" = "$_remaining" ]; then
				_remaining=""
			else
				_remaining="${_remaining#*;}"
			fi
			[ -n "$_needle" ] || continue
			if ! grep -qF -- "$_needle" "$CASE_LOG"; then
				_reason="output does not contain '$_needle'"
				break
			fi
		done
	fi
	if [ -z "$_reason" ] && [ -n "$_report_needle" ]; then
		_report="$(latest_report)"
		if [ -z "$_report" ]; then
			_reason="no test report was written under tools/ci/out/reports/"
		elif ! grep -qF -- "$_report_needle" "$_report"; then
			_reason="report $(basename "$_report") does not contain '$_report_needle'"
		fi
	fi
	[ -z "$_reason" ] && _ok=yes

	if [ "$_ok" = "yes" ]; then
		CASES_OK=$((CASES_OK + 1))
	fi
	log "case $CASES_RUN: $_desc"
	log "  expected: $_expect / observed exit: $_status -> $_ok"
	[ -n "$_reason" ] && log "  reason: $_reason"
	# The engine error / warning lines the case was built around, so a failure
	# can be read without re-running anything.
	grep -E 'SCRIPT ERROR|^ERROR:|^WARNING:|engine reported|result=(pass|fail)' "$CASE_LOG" 2>/dev/null |
		head -n 6 | sed 's/^/  | /'
	if [ "$_ok" != "yes" ]; then
		log "  --- case output ---"
		sed 's/^/  | /' "$CASE_LOG" >&2
		log "  --- end case output ---"
	fi
	return 0
}

# --- setup -------------------------------------------------------------------

if [ -z "$GATE_TARGET_SCRIPT" ]; then
	for _candidate in src/boot/game.gd src/boot/main_menu.gd src/boot/boot.gd; do
		if [ -f "$PROJECT_DIR/$_candidate" ]; then
			GATE_TARGET_SCRIPT="$_candidate"
			break
		fi
	done
fi
[ -n "$GATE_TARGET_SCRIPT" ] || die 2 "no boot script to inject into; set GATE_TARGET_SCRIPT"
case "$GATE_TARGET_SCRIPT" in
	/* | *..*) die 2 "GATE_TARGET_SCRIPT must be a project-relative path: $GATE_TARGET_SCRIPT" ;;
esac
[ -f "$PROJECT_DIR/$GATE_TARGET_SCRIPT" ] || die 2 "target script not found: $GATE_TARGET_SCRIPT"

log "project: $PROJECT_DIR"
log "tooling: $TOOLS_CI_DIR"
log "target:  $GATE_TARGET_SCRIPT"
log "godot:   $GODOT_BIN ($("$GODOT_BIN" --version 2>/dev/null || echo 'version unknown'))"
log "bounds:  ${GATE_TIMEOUT}s per engine invocation, ${GATE_CASE_TIMEOUT}s per case"

BEFORE="$(live_fingerprint)"
[ -n "$BEFORE" ] || die 2 "could not fingerprint the live checkout"
LIVE_GODOT_BEFORE=no
[ -e "$PROJECT_DIR/.godot" ] && LIVE_GODOT_BEFORE=yes
[ "$LIVE_GODOT_BEFORE" = yes ] && log "note: the live checkout already had a .godot cache directory before this run"

mkdir -p "$SANDBOX_HOME" "$SANDBOX_TMP" "$SANDBOX_XDG_CACHE" "$SANDBOX_XDG_DATA" "$SANDBOX_XDG_CONFIG"

# --- cases -------------------------------------------------------------------

# 1. Control: a clean snapshot must pass, and the exit-code proof must still
#    run. The gate must not fail a healthy tree.
make_snapshot || die 2 "could not prepare a snapshot of $PROJECT_DIR"
run_gate_case "clean snapshot passes ci.sh test" pass \
	"test: PASS;exit-code proof: a deliberately failing check exited" \
	"test result=pass" \
	test

# 2. The N1 repro: a missing dictionary key at the top of _ready(). The script
#    parses, the scene loads, the boot handoff completes, the engine exits 0.
#    Only the log shows the error, so this case is the one that used to pass.
#    The needles deliberately do not name which mechanism caught it -- with the
#    default target the log gate does, and a target the smoke check detects
#    itself still has to fail the run -- but the engine error line must be in
#    the output either way.
make_snapshot || die 2 "could not prepare a snapshot of $PROJECT_DIR"
inject_statement 'print(get_node_or_null("NoSuchNode")["missing_key"])' ||
	die 2 "could not inject the missing-key runtime error"
run_gate_case "missing dictionary key in _ready fails ci.sh test" fail \
	"test: FAIL;SCRIPT ERROR: Invalid access to property or key 'missing_key'" \
	"result=fail" \
	test

# 3. push_error(): the same hole through a different engine message. The exit
#    status is still 0, so only the log gate can catch it.
make_snapshot || die 2 "could not prepare a snapshot of $PROJECT_DIR"
inject_statement 'push_error("injected runtime error for the CI gate")' ||
	die 2 "could not inject the push_error runtime error"
run_gate_case "push_error() in _ready fails ci.sh test" fail \
	"test: FAIL;ERROR: injected runtime error for the CI gate" \
	"result=fail" \
	test

# 4. Negative control: a warning is not an error. The run must still pass, and
#    the warning must be visible in the output -- a gate that failed here would
#    be failing for the wrong reason, and one that stayed silent would be
#    repeating the R7 mistake of passing a warning unnoticed.
make_snapshot || die 2 "could not prepare a snapshot of $PROJECT_DIR"
inject_statement 'push_warning("injected warning for the CI gate control")' ||
	die 2 "could not inject the push_warning control"
run_gate_case "push_warning() in _ready passes but is surfaced" pass \
	"test: PASS;WARNING: injected warning for the CI gate control" \
	"result=pass" \
	test

# 5. The same warning with --strict-warnings: an unaccepted warning must not be
#    silently passed. tools/ci/warnings.allow records the warnings the project
#    has decided to live with, so this only fires for the unexpected ones.
make_snapshot || die 2 "could not prepare a snapshot of $PROJECT_DIR"
inject_statement 'push_warning("injected warning for the CI gate control")' ||
	die 2 "could not inject the push_warning control"
run_gate_case "push_warning() with --strict-warnings fails" fail \
	"test: FAIL;WARNING: injected warning for the CI gate control" \
	"result=fail" \
	--strict-warnings test

# 6. A warning that names the physics backend is a physics result, not noise: the
#    pinned engine emits exactly five Jolt warnings and every one means contacts
#    were ignored or a slower allocator was used (see ci_log_jolt_warning_lines).
#    The open R7 item is the job-system one, so it must never pass silently.
#    This uses the real engine message shape, injected through push_warning().
make_snapshot || die 2 "could not prepare a snapshot of $PROJECT_DIR"
inject_statement 'push_warning("Jolt Physics job system exceeded the maximum number of jobs. This should not happen. Please report this.")' ||
	die 2 "could not inject the Jolt warning control"
run_gate_case "a Jolt physics warning fails ci.sh test" fail \
	"test: FAIL;Jolt Physics job system exceeded the maximum number of jobs" \
	"result=fail" \
	test

# --- isolation verification ---------------------------------------------------

AFTER="$(live_fingerprint)"
if [ "$BEFORE" != "$AFTER" ]; then
	log "FAIL: the live checkout changed during this run" >&2
	printf '%s\n' "$BEFORE" >"$WORK_DIR/before.txt"
	printf '%s\n' "$AFTER" >"$WORK_DIR/after.txt"
	diff "$WORK_DIR/before.txt" "$WORK_DIR/after.txt" >&2 || true
	die 1 "live src/boot/, scenes/ or project.godot files were modified"
fi
LIVE_GODOT_AFTER=no
[ -e "$PROJECT_DIR/.godot" ] && LIVE_GODOT_AFTER=yes
if [ "$LIVE_GODOT_BEFORE" = no ] && [ "$LIVE_GODOT_AFTER" = yes ]; then
	die 1 "a .godot cache directory appeared in the live checkout"
fi
log "isolation verified: live $GATE_TARGET_SCRIPT, src/boot/, scenes/ and project.godot are unchanged and no cache leaked into the checkout"

# --- summary ------------------------------------------------------------------

log "summary: $CASES_OK/$CASES_RUN cases behaved as expected"
if [ "$CASES_OK" -eq "$CASES_RUN" ]; then
	log "PASS: the CI test stage fails on runtime engine errors as the smoke wrapper does"
	exit 0
fi
die 1 "$((CASES_RUN - CASES_OK)) case(s) did not behave as expected"
