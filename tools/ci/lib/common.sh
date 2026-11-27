#!/bin/sh
# Shared helpers for the Roadstorm Racer! command-line tooling.
#
# Sourced by tools/ci/ci.sh. Everything here is POSIX shell so the same
# commands run on macOS, Linux and any host with a Bourne-compatible /bin/sh
# (Git Bash, WSL, busybox ash). No project-specific paths are hardcoded: the
# project root, Godot binary and output directory are all overridable.
#
# Ownership: tools/ci/** only (PLAN.md "How agents execute the plan").
# This file is original project code under the Unlicense.

# ---------------------------------------------------------------------------
# Exit codes used across the tooling
# ---------------------------------------------------------------------------
# 0  check passed / command completed
# 1  check failed (a real, reported problem)
# 2  the command could not run at all (usage error, missing tool, bad path)
CI_OK=0
CI_FAIL=1
CI_USAGE=2

# ---------------------------------------------------------------------------
# Warning policy. 0 = engine WARNING lines are surfaced and counted but do not
# fail a check (the default: a warning is not an error, and the accepted ones
# are recorded in tools/ci/warnings.allow rather than hidden); 1 = an unexpected
# WARNING line fails the check (--strict-warnings, or CI_STRICT_WARNINGS=1 in
# the environment).
# ---------------------------------------------------------------------------
CI_STRICT_WARNINGS="${CI_STRICT_WARNINGS:-0}"
case "$CI_STRICT_WARNINGS" in
0 | 1) : ;;
*) CI_STRICT_WARNINGS=0 ;;
esac

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
CI_C_RESET=""
CI_C_RED=""
CI_C_GREEN=""
CI_C_YELLOW=""
CI_C_BLUE=""
CI_C_BOLD=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	CI_C_RESET="$(printf '\033[0m')"
	CI_C_RED="$(printf '\033[31m')"
	CI_C_GREEN="$(printf '\033[32m')"
	CI_C_YELLOW="$(printf '\033[33m')"
	CI_C_BLUE="$(printf '\033[34m')"
	CI_C_BOLD="$(printf '\033[1m')"
fi

ci_info() { printf '%s[ci]%s %s\n' "$CI_C_BLUE" "$CI_C_RESET" "$*"; }
ci_ok() { printf '%s[ci:ok]%s %s\n' "$CI_C_GREEN" "$CI_C_RESET" "$*"; }
ci_warn() { printf '%s[ci:warn]%s %s\n' "$CI_C_YELLOW" "$CI_C_RESET" "$*" >&2; }
ci_fail() { printf '%s[ci:fail]%s %s\n' "$CI_C_RED" "$CI_C_RESET" "$*" >&2; }
ci_step() { printf '%s==>%s %s\n' "$CI_C_BOLD" "$CI_C_RESET" "$*"; }
ci_note() { printf '    %s\n' "$*"; }

# ci_die <message> : the command itself is unusable (not a check failure).
ci_die() {
	ci_fail "$*"
	ci_fail "this is a tooling/usage error (exit $CI_USAGE), not a check result"
	exit "$CI_USAGE"
}

# ---------------------------------------------------------------------------
# Logging of engine invocations. Every Godot run is captured so a failure can
# be inspected without re-running it.
# ---------------------------------------------------------------------------
CI_LOG_DIR=""
CI_LOG_SEQ=0

ci_init_logs() {
	CI_LOG_DIR="$CI_OUT/logs"
	mkdir -p "$CI_LOG_DIR" || ci_die "cannot create log directory: $CI_LOG_DIR"
}

# ci_run_bounded <seconds> <command...>
# Runs a short command with a wall-clock limit, without capturing its output.
# Used where a full engine run is not needed (the `--version` probe) but a hung
# or wedged binary must not hang the tooling with it. Same supervision shape as
# ci_run_godot, and for the same reason: POSIX has no `timeout`.
ci_run_bounded() {
	_limit="$1"
	shift
	( "$@" ) &
	_pid=$!
	(
		sleep "$_limit" 2>/dev/null
		kill -TERM "$_pid" 2>/dev/null
		sleep 2 2>/dev/null
		kill -KILL "$_pid" 2>/dev/null
	) >/dev/null 2>&1 &
	_watch=$!
	wait "$_pid" 2>/dev/null
	_rc=$?
	kill "$_watch" 2>/dev/null
	wait "$_watch" 2>/dev/null
	return "$_rc"
}

# ci_run_godot <label> <godot args...>
# Runs Godot with a wall-clock timeout, capturing combined stdout/stderr.
# Sets CI_LAST_EXIT and CI_LAST_LOG. Set CI_RUN_TIMEOUT before the call to
# override the limit for one invocation; assign it as a normal variable rather
# than a command prefix, because prefixed assignments to shell functions do not
# behave the same way in every /bin/sh.
CI_LAST_EXIT=0
CI_LAST_LOG=""
CI_TIMEOUT_DEFAULT="${CI_TIMEOUT_DEFAULT:-300}"

ci_run_godot() {
	_label="$1"
	shift
	CI_LOG_SEQ=$((CI_LOG_SEQ + 1))
	CI_LAST_LOG="$CI_LOG_DIR/${CI_RUN_NAME}-${CI_LOG_SEQ}-${_label}.log"
	_timeout="${CI_RUN_TIMEOUT:-$CI_TIMEOUT_DEFAULT}"

	ci_info "godot $_label: $GODOT_BIN $*"
	ci_info "  log: $CI_LAST_LOG (timeout ${_timeout}s)"

	# Portable timeout: `timeout` is not part of POSIX and is missing from a
	# stock macOS install, so supervise the child ourselves. Both background
	# processes must not inherit this script's stdout, or a caller piping our
	# output would wait for them before seeing end-of-file.
	(
		"$GODOT_BIN" "$@"
	) >"$CI_LAST_LOG" 2>&1 &
	_pid=$!
	(
		sleep "$_timeout" 2>/dev/null
		kill -TERM "$_pid" 2>/dev/null
		sleep 3 2>/dev/null
		kill -KILL "$_pid" 2>/dev/null
	) >/dev/null 2>&1 &
	_watch=$!
	wait "$_pid" 2>/dev/null
	CI_LAST_EXIT=$?
	kill "$_watch" 2>/dev/null
	wait "$_watch" 2>/dev/null

	if [ "$CI_LAST_EXIT" -ge 124 ] && [ "$CI_LAST_EXIT" -le 137 ]; then
		# 128+signal, or the 124/137 conventions of coreutils' timeout.
		if grep -q . "$CI_LAST_LOG" 2>/dev/null; then :; fi
		ci_warn "godot $_label exited with $CI_LAST_EXIT (timeout or signal?)"
	fi
	return "$CI_LAST_EXIT"
}

# ci_log_error_lines <logfile>
# Prints engine error lines. Godot prefixes them at the start of a line, so
# anchor the match: mid-line mentions of "ERROR" in ordinary output are not
# engine errors. Verified against the pinned engine: a scene referencing a
# missing script still loads and instantiates (exit 0) while printing
# "ERROR: ..." lines, so log inspection is the only reliable signal.
#
# The pattern deliberately covers the same shapes as the supported smoke
# wrapper tools/smoke/run_boot_smoke.sh, because Opus recheck finding N1 is
# exactly that a bare `--script` run reports these as informational while the
# wrapper fails on them. Measured against the pinned engine
# 4.7.2.stable.official.ed1daf0bf:
#   SCRIPT ERROR: Invalid access to property or key 'missing_key' ...
#   ERROR: Failed to load script "res://..." with error "Parse error".
#   ERROR: injected runtime error ...      <- push_error() from GDScript
# USER ERROR: is kept for parity with the wrapper even though push_error() was
# measured to print the plain "ERROR:" prefix on this build.
ci_log_error_lines() {
	_file="$1"
	[ -f "$_file" ] || return 0
	grep -nE '^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error' "$_file" 2>/dev/null
}

# ci_log_warning_lines <logfile>
# Prints engine warning lines, with the same anchoring rule as the error lines
# above. Warnings are not errors: the pinned engine prints them for conditions
# that do not fail a check, and this project already emits a benign one
# (measured: "WARNING: Detected another project.godot at
# res://tools/tick_probe." during a headless --import). They are surfaced and
# counted on every run anyway, because the open R7 item is precisely a warning
# that used to pass unnoticed ("Jolt Physics job system exceeded the maximum
# number of jobs ...").
ci_log_warning_lines() {
	_file="$1"
	[ -f "$_file" ] || return 0
	grep -nE '^(WARNING|USER WARNING):' "$_file" 2>/dev/null
}

# ci_warning_allow_file : the accepted-warning list (tools/ci/**), or empty
# when the tooling is relocated without it. An accepted warning is still
# printed on every run; it is recorded here rather than hidden, so a reviewer
# can see what the project has decided to live with.
CI_WARNINGS_ALLOW="warnings.allow"
ci_warning_allow_file() {
	if [ -n "${CI_TOOLS_DIR:-}" ] && [ -f "$CI_TOOLS_DIR/$CI_WARNINGS_ALLOW" ]; then
		printf '%s\n' "$CI_TOOLS_DIR/$CI_WARNINGS_ALLOW"
	fi
}

# ci_warning_is_accepted <log-line> : true when the line matches an entry in
# the accepted-warning list. Entries are POSIX EREs; `#` starts a comment. A
# pattern may match the line exactly as this tooling prints it (with the
# `grep -n` line-number prefix) or the engine's own message without that prefix,
# so the list reads the way the engine printed the warning.
ci_warning_is_accepted() {
	_file="$(ci_warning_allow_file)"
	[ -n "$_file" ] || return 1
	_message="$(printf '%s\n' "$1" | sed 's/^[[:space:]]*[0-9]\{1,\}://')"
	while IFS= read -r _pattern || [ -n "$_pattern" ]; do
		case "$_pattern" in
			'' | \#*) continue ;;
		esac
		if printf '%s\n' "$1" | grep -qE "$_pattern" 2>/dev/null; then
			return 0
		fi
		if printf '%s\n' "$_message" | grep -qE "$_pattern" 2>/dev/null; then
			return 0
		fi
	done <"$_file"
	return 1
}

# ci_log_unexpected_warning_lines <logfile> : warning lines that are NOT in the
# accepted list. These are the ones strict mode fails on.
ci_log_unexpected_warning_lines() {
	ci_log_warning_lines "$1" | while IFS= read -r _line || [ -n "$_line" ]; do
		ci_warning_is_accepted "$_line" || printf '%s\n' "$_line"
	done
}

# ci_log_warning_count <logfile> : number of warning lines, normalised.
ci_log_warning_count() {
	ci_log_warning_lines "$1" | ci_count_lines
}

# ci_log_unexpected_warning_count <logfile>
ci_log_unexpected_warning_count() {
	ci_log_unexpected_warning_lines "$1" | ci_count_lines
}

# ci_is_jolt_physics_warning <log-line> : true only for one of the five Jolt
# physics warnings the pinned engine (4.7.2.stable.official.ed1daf0bf) emits,
# verified in its source:
#   modules/jolt_physics/spaces/jolt_job_system.cpp:123
#     "Jolt Physics job system exceeded the maximum number of jobs. ..."
#   modules/jolt_physics/spaces/jolt_space_3d.cpp:199,206,213
#     "Jolt Physics manifold cache exceeded capacity and contacts were ignored. ..."
#     "Jolt Physics body pair cache exceeded capacity and contacts were ignored. ..."
#     "Jolt Physics contact constraint buffer exceeded capacity and contacts were ignored. ..."
#   modules/jolt_physics/spaces/jolt_temp_allocator.cpp:89
#     "Jolt Physics temporary memory allocator exceeded capacity of %d MiB. ..."
# Each one reports a simulation limit being exceeded -- contacts were ignored or
# a slower allocator was used -- so a run that printed one must not be reported
# as a clean pass (Opus recheck finding R7'). The match is on those message
# shapes, NOT on the substring "jolt": a benign warning about a nested project
# path such as res://tools/jolt_inventory mentions Jolt without being a physics
# failure, and failing for that reason is exactly the false positive hosted run
# 45921573623 hit. A Jolt warning the project has decided to accept belongs in
# tools/ci/warnings.allow, which keeps the acceptance explicit instead of hidden.
ci_is_jolt_physics_warning() {
	case "$1" in
		*"Jolt Physics job system exceeded"* | *"Jolt Physics manifold cache exceeded"* | *"Jolt Physics body pair cache exceeded"* | *"Jolt Physics contact constraint buffer exceeded"* | *"Jolt Physics temporary memory allocator exceeded"*)
			return 0
			;;
	esac
	return 1
}

# ci_log_jolt_warning_lines <logfile>
# The unexpected WARNING lines that are one of the five known Jolt physics
# warnings above -- not every line containing "jolt".
ci_log_jolt_warning_lines() {
	ci_log_unexpected_warning_lines "$1" |
		while IFS= read -r _ijw_line || [ -n "$_ijw_line" ]; do
			ci_is_jolt_physics_warning "$_ijw_line" && printf '%s\n' "$_ijw_line"
		done
}

# ci_log_jolt_warning_count <logfile>
ci_log_jolt_warning_count() {
	ci_log_jolt_warning_lines "$1" | ci_count_lines
}

# ci_log_warning_gate <logfile> [context]
# Surfaces engine warnings: never silent, and fatal only when strict warnings
# are requested (--strict-warnings / CI_STRICT_WARNINGS=1). Strict is opt-in
# because a warning is not an error: failing a check for a warning the project
# has not decided about would be failing for the wrong reason, which is the
# defect this tooling avoids elsewhere. Every warning line is printed either
# way, and the ones the project has accepted are labelled as accepted, so a
# warning can be tolerated without being invisible.
ci_log_warning_gate() {
	_file="$1"
	_context="${2:-}"
	_total="$(ci_log_warning_count "$_file")"
	[ "$_total" = "0" ] && return "$CI_OK"
	_unexpected="$(ci_log_unexpected_warning_count "$_file")"
	_accepted=$((_total - _unexpected))
	_note=""
	[ "$_accepted" -gt 0 ] && _note=" ($_accepted accepted in $CI_WARNINGS_ALLOW)"
	if [ "${CI_STRICT_WARNINGS:-0}" -eq 1 ] && [ "$_unexpected" != "0" ]; then
		ci_fail "$_unexpected unexpected engine warning line(s) in $(ci_relpath "$_file")${_context:+ ($_context)}; strict warnings are on:$_note"
		ci_log_unexpected_warning_lines "$_file" | sed 's/^/    /'
		return "$CI_FAIL"
	fi
	if [ "${CI_STRICT_WARNINGS:-0}" -eq 1 ]; then
		ci_warn "$_total engine warning line(s) in $(ci_relpath "$_file")${_context:+ ($_context)}; all accepted:$_note"
	else
		ci_warn "$_total engine warning line(s) in $(ci_relpath "$_file")${_context:+ ($_context)} (surfaced, not fatal; --strict-warnings fails on unexpected ones):$_note"
	fi
	ci_log_warning_lines "$_file" | sed 's/^/    /'
	return "$CI_OK"
}

# ci_count_lines <stdin-text> : number of non-empty lines, normalised to a
# bare integer. `grep -c` prints 0 *and* exits 1 when nothing matches, so the
# `|| printf 0` idiom would otherwise produce "0\n0".
ci_count_lines() {
	_n="$(grep -c . 2>/dev/null)"
	case "$_n" in
		'' | *[!0-9]*) _n=0 ;;
	esac
	printf '%s\n' "$_n"
}

ci_log_error_count() {
	ci_log_error_lines "$1" | ci_count_lines
}

# ci_log_gate <logfile> : CI_OK when the captured engine log has no error lines.
# Essential because the pinned engine exits 0 even when a script fails to load
# or a scene references a missing resource; the log is the only signal.
ci_log_gate() {
	_n="$(ci_log_error_count "$1")"
	if [ "$_n" != "0" ]; then
		ci_fail "$_n engine error line(s) in $(ci_relpath "$1"):"
		ci_log_error_lines "$1" | sed 's/^/    /'
		return "$CI_FAIL"
	fi
	return "$CI_OK"
}

ci_prune_logs() {
	# Keep the newest 20 logs; `out/` is local scratch and gitignored.
	[ -d "$CI_LOG_DIR" ] || return 0
	_count="$(ls -1 "$CI_LOG_DIR" 2>/dev/null | ci_count_lines)"
	if [ "$_count" -gt 20 ]; then
		ls -1t "$CI_LOG_DIR" 2>/dev/null | tail -n +21 | while read -r _old; do
			rm -f "$CI_LOG_DIR/$_old" 2>/dev/null
		done
	fi
}

# ---------------------------------------------------------------------------
# Godot discovery and the engine pin (PLAN.md M0.1)
# ---------------------------------------------------------------------------
GODOT_BIN="${GODOT_BIN:-}"
GODOT_VERSION_FULL=""

# ci_find_godot : resolves $GODOT_BIN and verifies it runs.
ci_find_godot() {
	if [ -n "$GODOT_BIN" ]; then
		[ -x "$GODOT_BIN" ] || ci_die "GODOT_BIN is set but not executable: $GODOT_BIN"
	else
		for candidate in \
			"$(command -v godot 2>/dev/null)" \
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
	[ -n "$GODOT_BIN" ] || ci_die "no Godot editor binary found. Set GODOT_BIN=/path/to/godot (see tools/ci/README.md)."

	GODOT_VERSION_FULL="$(ci_run_bounded 30 "$GODOT_BIN" --version 2>/dev/null | head -n 1)"
	[ -n "$GODOT_VERSION_FULL" ] || ci_die "cannot read the engine version from: $GODOT_BIN"
	# Example: 4.7.2.stable.official.ed1daf0bf
	case "$GODOT_VERSION_FULL" in
		*.*.*) : ;;
		*) ci_die "unexpected engine version string from $GODOT_BIN: $GODOT_VERSION_FULL" ;;
	esac
}

# ci_pin_load : reads the pinned engine version into CI_PIN_* variables.
#
# Precedence: tools/toolchain/pin/engine.txt when the project carries it, because
# that is the M0.1 record (PLAN.md M0.1) and holds the upstream-verification
# status; tools/ci/pin/engine.txt is the fallback for a standalone checkout of
# this tooling. Both files use the same fields, so a single source of truth is
# kept even though the files live in different owned directories.
# ci_pin_load : reads the pinned engine version into CI_PIN_* variables.
#
# Two pin files with two different jobs, so neither can silently win:
#
#   tools/toolchain/pin/engine.txt  the M0.1 record for the INSTALLED toolchain
#                                   (version, official sources, local digests,
#                                   upstream-verification status). Authoritative
#                                   for the version fields when the project
#                                   carries it, so the two files cannot drift
#                                   apart on what version is required.
#   tools/ci/pin/engine.txt         owned by tools/ci/**. Always supplies the
#                                   RELEASE ARTIFACT fields: the official
#                                   archive CI downloads and verifies before
#                                   extraction and execution. The toolchain
#                                   record deliberately does not carry them: a
#                                   digest recorded on one host for an installed
#                                   file is not a portable expectation, but a
#                                   published release archive is the same bytes
#                                   everywhere.
#
# Both files use `key=value` lines, so a single parser reads either.
CI_PIN_SOURCE=""
CI_PIN_VERSION_STRING=""
CI_PIN_UPSTREAM_VERIFIED=""
# Official release artifact that CI downloads and verifies before use. Empty
# means "not recorded"; ci_verify_digest refuses an empty expectation.
CI_PIN_RELEASE_URL=""
CI_PIN_RELEASE_CHECKSUMS_URL=""
CI_PIN_RELEASE_SHA512=""
CI_PIN_RELEASE_SHA256=""
CI_PIN_RELEASE_BINARY_SHA256=""
# Official export-template archive (the .tpz) that CI downloads and verifies
# before extraction, plus the publisher's SHA-512 of it. Same rule as the editor
# archive: a published release artifact is the same bytes everywhere, so its
# digest IS a portable expectation (Opus recheck finding E1).
CI_PIN_TEMPLATES_URL=""
CI_PIN_TEMPLATES_SHA512=""

# ci_pin_parse_version <file> : version/authority fields.
ci_pin_parse_version() {
	while IFS='=' read -r _key _value; do
		case "$_key" in
			'' | \#*) continue ;;
			major) CI_PIN_MAJOR="$_value" ;;
			minor) CI_PIN_MINOR="$_value" ;;
			patch) CI_PIN_PATCH="$_value" ;;
			tag) CI_PIN_TAG="$_value" ;;
			version_string) CI_PIN_VERSION_STRING="$_value" ;;
			upstream_verified) CI_PIN_UPSTREAM_VERIFIED="$_value" ;;
		esac
	done <"$1"
}

# ci_pin_parse_release <file> : release-artifact fields (tools/ci's own pin).
ci_pin_parse_release() {
	while IFS='=' read -r _key _value; do
		case "$_key" in
			'' | \#*) continue ;;
			release_archive_url) CI_PIN_RELEASE_URL="$_value" ;;
			release_checksums_url) CI_PIN_RELEASE_CHECKSUMS_URL="$_value" ;;
			release_archive_sha512) CI_PIN_RELEASE_SHA512="$_value" ;;
			release_archive_sha256) CI_PIN_RELEASE_SHA256="$_value" ;;
			release_binary_sha256) CI_PIN_RELEASE_BINARY_SHA256="$_value" ;;
			templates_url) CI_PIN_TEMPLATES_URL="$_value" ;;
			templates_archive_sha512) CI_PIN_TEMPLATES_SHA512="$_value" ;;
		esac
	done <"$1"
}

ci_pin_load() {
	_own="$CI_TOOLS_DIR/pin/engine.txt"
	[ -f "$_own" ] || ci_die "missing engine pin file: $_own"
	_toolchain="$CI_PROJECT/tools/toolchain/pin/engine.txt"

	_pin="$_own"
	CI_PIN_SOURCE="$(ci_relpath "$_own")"
	if [ -f "$_toolchain" ]; then
		_pin="$_toolchain"
		CI_PIN_SOURCE="$(ci_relpath "$_toolchain") (M0.1 record)"
	fi

	ci_pin_parse_version "$_pin"
	# The release artifact block always comes from tools/ci's own pin file.
	ci_pin_parse_release "$_own"

	[ -n "$CI_PIN_MAJOR$CI_PIN_MINOR$CI_PIN_PATCH" ] || ci_die "engine pin file is incomplete: $_pin"
	return 0
}

# ci_check_engine_pin : prints one line per fact, returns CI_OK/CI_FAIL.
ci_check_engine_pin() {
	_rc="$CI_OK"
	_major="${GODOT_VERSION_FULL%%.*}"
	_rest="${GODOT_VERSION_FULL#*.}"
	_minor="${_rest%%.*}"
	_rest="${_rest#*.}"
	_patch="${_rest%%.*}"

	if [ "$_major" = "$CI_PIN_MAJOR" ] && [ "$_minor" = "$CI_PIN_MINOR" ] && [ "$_patch" = "$CI_PIN_PATCH" ]; then
		ci_ok "engine pin: $GODOT_VERSION_FULL matches pinned ${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH} (from $CI_PIN_SOURCE)"
	else
		ci_fail "engine pin: expected Godot ${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}, found $GODOT_VERSION_FULL ($GODOT_BIN); pin source: $CI_PIN_SOURCE"
		_rc="$CI_FAIL"
	fi

	# Advisory: the pinned build's exact --version string. A different official
	# build of the same version (another platform, another commit) prints a
	# different string, so this is a warning rather than a failure.
	if [ -n "$CI_PIN_VERSION_STRING" ] && [ "$CI_PIN_VERSION_STRING" != "$GODOT_VERSION_FULL" ]; then
		ci_warn "engine build string: pinned '$CI_PIN_VERSION_STRING', found '$GODOT_VERSION_FULL' (same version, different build)"
	fi

	case "$CI_PIN_UPSTREAM_VERIFIED" in
		yes)
			ci_ok "engine checksum: the pin records upstream verification (selected artifacts only; see tools/ci/pin/engine.txt for scope and tools/toolchain/pin/engine.txt for the M0.1 record)"
			;;
		no)
			ci_warn "engine checksum: pin records upstream_verified=no; the version is checked, the artifact digests are not verified here"
			;;
		*)
			ci_warn "engine checksum: pin does not record an upstream-verification status"
			;;
	esac

	# The release artifact CI downloads is pinned separately from the installed
	# editor: 'ci.sh verify-engine' compares it against the publisher's digest
	# BEFORE extraction and before execution (PLAN.md M0.1).
	if [ -n "$CI_PIN_RELEASE_SHA512" ]; then
		ci_ok "release artifact: pinned sha512 digest recorded for the official editor archive ($CI_PIN_RELEASE_URL)"
	else
		ci_warn "release artifact: no release_archive_sha512 recorded; 'ci.sh verify-engine' would refuse the download"
	fi

	# Export templates (needed by export preparation only). The engine reads
	# them from its own user-data directory; see ci_templates_engine_dir.
	_tdir="$(ci_templates_engine_dir || true)"
	_envdir="$(ci_templates_env_dir || true)"
	if [ -n "$_envdir" ] && [ "$_envdir" != "$_tdir" ]; then
		ci_warn "export templates: GODOT_TEMPLATES_DIR=$_envdir is NOT read by the engine (measured); the engine reads $_tdir"
	fi
	if [ -n "$_tdir" ] && [ -d "$_tdir/${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}.stable" ]; then
		_tver="$(head -n 1 "$_tdir/${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}.stable/version.txt" 2>/dev/null)"
		if [ "$_tver" = "${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}.stable" ]; then
			ci_ok "export templates: ${_tver} installed in $_tdir"
		else
			ci_fail "export templates: version.txt reports '$_tver' in $_tdir"
			_rc="$CI_FAIL"
		fi
	elif [ -n "$_tdir" ]; then
		ci_warn "export templates: no ${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}.stable directory in $_tdir (only needed by 'ci.sh export')"
	else
		ci_warn "export templates: template directory not found (only needed by 'ci.sh export')"
	fi

	ci_note "local artifact digests are checked by tools/toolchain/verify.sh on the machine that recorded them, not here: a digest from one host is not a portable expectation for another."
	return "$_rc"
}

# ci_templates_engine_dir : prints the directory the engine itself reads export
# templates from, following the engine's own user-data rules.
#
# MEASURED against the pinned engine (4.7.2.stable.official.ed1daf0bf), because
# Opus recheck finding E1 is exactly a check that looked in the wrong place:
# the engine reads <user data dir>/export_templates/<version>.stable and does
# NOT read $GODOT_TEMPLATES_DIR. The variable name does not appear in the engine
# binary at all, and an export with GODOT_TEMPLATES_DIR pointing at a complete
# template tree while the user-data directory is empty fails with
#   "No export template found at the expected path:
#    <HOME>/Library/Application Support/Godot/export_templates/4.7.2.stable/..."
# A presence check that honoured the variable could therefore pass a tree whose
# export then fails, which is the false green this function exists to prevent.
#
# Prints nothing and returns 1 when the user-data directory cannot be derived
# (no HOME on a Unix host, no APPDATA on Windows).
ci_templates_engine_dir() {
	[ -n "${HOME:-}" ] || return 1
	case "$(uname -s 2>/dev/null)" in
		Darwin) printf '%s/Library/Application Support/Godot/export_templates\n' "$HOME" ;;
		Linux)
			if [ -n "${XDG_DATA_HOME:-}" ]; then
				printf '%s/godot/export_templates\n' "$XDG_DATA_HOME"
			else
				printf '%s/.local/share/godot/export_templates\n' "$HOME"
			fi
			;;
		MINGW* | MSYS* | CYGWIN*)
			[ -n "${APPDATA:-}" ] || return 1
			printf '%s/Godot/export_templates\n' "$APPDATA"
			;;
		*) return 1 ;;
	esac
	return 0
}

# ci_templates_env_dir : prints $GODOT_TEMPLATES_DIR when it names an existing
# directory. The pinned engine does NOT read it (see ci_templates_engine_dir), so
# this is reported for information only -- never used to pass the export check.
ci_templates_env_dir() {
	if [ -n "${GODOT_TEMPLATES_DIR:-}" ] && [ -d "$GODOT_TEMPLATES_DIR" ]; then
		printf '%s\n' "$GODOT_TEMPLATES_DIR"
		return 0
	fi
	return 1
}

# ci_templates_version_dir <templates-root> : prints the pinned version's
# template directory (<root>/<major>.<minor>.<patch>.stable), which is the name
# the engine looks for regardless of where the root is.
ci_templates_version_dir() {
	_rtv_root="$1"
	[ -n "$_rtv_root" ] || return 1
	printf '%s/%s.%s.%s.stable\n' "$_rtv_root" "$CI_PIN_MAJOR" "$CI_PIN_MINOR" "$CI_PIN_PATCH"
	return 0
}

# ---------------------------------------------------------------------------
# Project copy
# ---------------------------------------------------------------------------
# Every engine run happens in a scratch copy of the project so the shared
# checkout's .godot/ import cache is never written by CI tooling. Reviewers
# get the same behaviour for their immutable source snapshots
# (plan/IMPLEMENTATION.md: "isolated .godot/import caches and output paths").
CI_PROJECT_COPY=""

ci_copy_project() {
	_src="$1"
	_dst="$2"
	rm -rf "$_dst" || ci_die "cannot clear scratch copy: $_dst"
	mkdir -p "$_dst" || ci_die "cannot create scratch copy: $_dst"

	_excludes=""
	if [ -n "${CI_OUT_REL_PATTERN:-}" ]; then
		_excludes="--exclude=$CI_OUT_REL_PATTERN"
	fi

	# ./build is CI export output (root .gitignore ignores /build/), not a
	# project resource. Excluding it keeps earlier presets' packages out of
	# later presets' scratch copies: without this, the Windows copy carries the
	# macOS zip and the Linux copy carries both, so each preset's input tree
	# depends on build order and tools/ci/out/project-copy bloats with packages.
	#
	# tar with --exclude works with both bsdtar (macOS) and GNU tar (Linux).
	if tar -cf - -C "$_src" --exclude=./.git --exclude=./.godot --exclude=./work --exclude=./build $_excludes . 2>/dev/null |
		(cd "$_dst" && tar -xf - 2>/dev/null); then
		:
	else
		ci_warn "tar copy failed; falling back to cp -R"
		cp -R "$_src/." "$_dst/" 2>/dev/null || ci_die "cannot copy project to $_dst"
		rm -rf "$_dst/.git" "$_dst/.godot" "$_dst/work" "$_dst/build" 2>/dev/null
	fi

	if [ ! -f "$_dst/project.godot" ]; then
		# Belt and braces: a silently empty copy would make later checks lie.
		ci_die "scratch copy has no project.godot ($_dst); refusing to run checks against it"
	fi
	# Remove the nested output directory if it survived the copy.
	if [ -n "${CI_OUT_REL_PATH:-}" ]; then
		rm -rf "$_dst/$CI_OUT_REL_PATH" 2>/dev/null
	fi
	return 0
}

# ci_tools_fingerprint : cheap content hash of the tooling itself, so a reused
# scratch copy can never run a stale copy of these scripts.
ci_tools_fingerprint() {
	( cd "$CI_TOOLS_DIR" 2>/dev/null && find . -type f ! -path './out/*' ! -path './out' -exec cat {} + 2>/dev/null ) |
		ci_sha256_stdin
}

# ci_prepare_copy : creates a fresh scratch copy and imports it once.
ci_prepare_copy() {
	CI_PROJECT_COPY="$CI_OUT/project-copy"
	_stamp="$CI_OUT/project-copy/.ci-tools-fingerprint"
	_fingerprint="$(ci_tools_fingerprint)"
	if [ "${CI_REUSE_COPY:-0}" -eq 1 ] && [ -f "$CI_PROJECT_COPY/project.godot" ] &&
		[ -f "$_stamp" ] && [ "$(cat "$_stamp" 2>/dev/null)" = "$_fingerprint" ]; then
		ci_info "reusing scratch copy: $CI_PROJECT_COPY"
		return "$CI_OK"
	fi
	if [ "${CI_REUSE_COPY:-0}" -eq 1 ] && [ -f "$CI_PROJECT_COPY/project.godot" ]; then
		ci_warn "the tooling changed since the scratch copy was made; refreshing it"
	fi
	ci_step "preparing scratch project copy (shared .godot/ cache is not touched)"
	ci_copy_project "$CI_PROJECT" "$CI_PROJECT_COPY"
	# Overlay this checkout's tooling into the copy. Without it, a project
	# snapshot that carries an older tools/ci/ (or none at all) would run stale
	# scripts and report results for code that is not the one being tested.
	if ! tar -cf - -C "$CI_TOOLS_DIR" --exclude=./out . 2>/dev/null |
		(cd "$CI_PROJECT_COPY/tools/ci" 2>/dev/null && tar -xf - 2>/dev/null); then
		ci_warn "could not overlay tools/ci into the scratch copy; using the project's own tooling"
	fi
	printf '%s\n' "$_fingerprint" >"$_stamp" 2>/dev/null
	ci_info "scratch copy: $CI_PROJECT_COPY"

	if [ -d "$CI_PROJECT_COPY/.godot" ]; then
		ci_info "scratch copy already has an import cache"
	else
		ci_step "importing the scratch copy (headless --import)"
		ci_run_godot import --headless --path "$CI_PROJECT_COPY" --import
		if [ "$CI_LAST_EXIT" -ne 0 ]; then
			ci_fail "headless import exited $CI_LAST_EXIT (log: $CI_LAST_LOG)"
			ci_log_error_lines "$CI_LAST_LOG" | sed 's/^/    /'
			return "$CI_FAIL"
		fi
	fi
	_errs="$(ci_log_error_count "$CI_LAST_LOG")"
	if [ "$_errs" != "0" ]; then
		ci_fail "import log contains $_errs engine error line(s) (log: $CI_LAST_LOG)"
		ci_log_error_lines "$CI_LAST_LOG" | sed 's/^/    /'
		return "$CI_FAIL"
	fi
	ci_ok "import: no engine errors in the scratch copy"
	# Warnings are surfaced here too, so the one this project is known to emit
	# (the nested tools/tick_probe/project.godot) is visible on every run rather
	# than only when someone greps the log by hand. Fatal only in strict mode.
	ci_log_warning_gate "$CI_LAST_LOG" "headless import" || return "$CI_FAIL"
	return "$CI_OK"
}

# ---------------------------------------------------------------------------
# Project viewport size (used by the capture path)
# ---------------------------------------------------------------------------
# Godot's movie writer records the PROJECT VIEWPORT size, not the window size.
# `--resolution <W>x<H>` only requests a window size (verified against the
# pinned engine: it changes DisplayServer.window_get_size() while
# `--write-movie` still reports and records the project's viewport size). A
# capture therefore has to set the viewport size in the scratch copy's
# project.godot to record at the requested resolution. The shared checkout's
# project.godot is never touched.

# ci_project_viewport_size <project.godot> : prints "<w>x<h>" or nothing.
#
# Godot writes section-relative keys, so the viewport size appears as
# `window/size/viewport_width=1920` under `[display]`; a full
# `display/window/size/viewport_width=` form is accepted too.
ci_project_viewport_size() {
	_cfg="$1"
	[ -f "$_cfg" ] || return 1
	_out="$(awk '
		/^window\/size\/viewport_width=/ { v = $0; sub(/^[^=]*=/, "", v); w = v; next }
		/^display\/window\/size\/viewport_width=/ { v = $0; sub(/^[^=]*=/, "", v); w = v; next }
		/^window\/size\/viewport_height=/ { v = $0; sub(/^[^=]*=/, "", v); h = v; next }
		/^display\/window\/size\/viewport_height=/ { v = $0; sub(/^[^=]*=/, "", v); h = v; next }
		END { if (w != "" && h != "") printf "%sx%s\n", w, h }
	' "$_cfg" 2>/dev/null)"
	case "$_out" in
		'' | *[!0-9x]*) return 1 ;;
	esac
	printf '%s\n' "$_out"
}

# ci_set_project_viewport_size <project.godot> <w> <h> : rewrites the viewport
# (and any explicit window-size overrides) in place. Returns CI_FAIL when the
# file has no viewport_width/viewport_height keys to rewrite, so a silent
# no-op cannot be reported as a successful override.
ci_set_project_viewport_size() {
	_cfg="$1"
	_w="$2"
	_h="$3"
	[ -f "$_cfg" ] || return "$CI_FAIL"
	_tmp="$_cfg.ci-viewport.tmp"
	awk -v w="$_w" -v h="$_h" '
		/^window\/size\/viewport_width=/ { print "window/size/viewport_width=" w; seen++; next }
		/^display\/window\/size\/viewport_width=/ { print "display/window/size/viewport_width=" w; seen++; next }
		/^window\/size\/viewport_height=/ { print "window/size/viewport_height=" h; seen++; next }
		/^display\/window\/size\/viewport_height=/ { print "display/window/size/viewport_height=" h; seen++; next }
		/^window\/size\/window_width_override=/ { print "window/size/window_width_override=" w; next }
		/^display\/window\/size\/window_width_override=/ { print "display/window/size/window_width_override=" w; next }
		/^window\/size\/window_height_override=/ { print "window/size/window_height_override=" h; next }
		/^display\/window\/size\/window_height_override=/ { print "display/window/size/window_height_override=" h; next }
		{ print }
		END { if (seen < 2) exit 1 }
	' "$_cfg" >"$_tmp" 2>/dev/null || {
		rm -f "$_tmp" 2>/dev/null
		return "$CI_FAIL"
	}
	mv "$_tmp" "$_cfg" 2>/dev/null || {
		rm -f "$_tmp" 2>/dev/null
		return "$CI_FAIL"
	}
	return "$CI_OK"
}

# ---------------------------------------------------------------------------
# Export presets (export_presets.cfg)
# ---------------------------------------------------------------------------
# The required native targets from docs/TECHNICAL_DESIGN.md ("Packaging and
# operations"): macOS Apple Silicon, Windows x86-64, Linux x86-64. These are the
# plan's short names for those targets.
CI_EXPORT_PLATFORMS="macOS Windows Linux"

# ci_preset_table <export_presets.cfg> : prints one
# "<preset.N>\t<name>\t<platform>" line per [preset.N] section, with the name
# and platform exactly as written in the file (empty when a key is absent).
# Variables are prefixed so calling it never clobbers the caller's state.
ci_preset_table() {
	_tbl_cfg="$1"
	[ -f "$_tbl_cfg" ] || return 1
	awk '
		/^\[/ {
			if (inpreset) printf "%s\t%s\t%s\n", idx, name, platform
			inpreset = ($0 ~ /^\[preset\.[0-9]+\]$/)
			idx = ""; name = ""; platform = ""
			if (inpreset) { idx = $0; sub(/^\[/, "", idx); sub(/\]$/, "", idx) }
			next
		}
		inpreset && /^name=/ { v = $0; sub(/^name="/, "", v); sub(/"$/, "", v); name = v }
		inpreset && /^platform=/ { v = $0; sub(/^platform="/, "", v); sub(/"$/, "", v); platform = v }
		END { if (inpreset) printf "%s\t%s\t%s\n", idx, name, platform }
	' "$_tbl_cfg" 2>/dev/null
}

# ci_preset_platform_for <requirement> : prints the value Godot writes in a
# preset's `platform=` line for that required target; fails for an unknown
# requirement.
#
# The requirement names are the plan's; the preset values are Godot's, and they
# are NOT the same strings. Comparing a requirement against the preset file
# directly reported a covered platform as missing: Godot writes
# `platform="Windows Desktop"` for the Windows desktop target, not
# `platform="Windows"` ("Windows" names the template files
# windows_<mode>_x86_64.exe and the CI platform list, never a preset). The
# false "preset platform missing: Windows" that mapping fixes is why this
# function exists instead of a direct string comparison.
ci_preset_platform_for() {
	case "$1" in
		macOS) printf 'macOS\n' ;;
		Windows) printf 'Windows Desktop\n' ;;
		Linux) printf 'Linux\n' ;;
		*) return 1 ;;
	esac
	return 0
}

# ci_preset_platform_coverage <export_presets.cfg> : verifies every required
# native target has a preset whose platform value maps to it. Prints one
# ci_ok/ci_fail line per requirement and returns CI_OK/CI_FAIL, so a preset
# declared with a platform Godot does not use (or a missing preset) fails
# instead of being waved through.
#
# Every variable is prefixed (_cov_*): a plain _rc here would clobber the
# caller's result -- which is how a template failure earlier in
# `ci.sh export --check` could be forgotten by the time it returns.
ci_preset_platform_coverage() {
	_cov_cfg="$1"
	_cov_rc="$CI_OK"
	_cov_table="$(ci_preset_table "$_cov_cfg" 2>/dev/null)"
	for _cov_req in $CI_EXPORT_PLATFORMS; do
		_cov_want="$(ci_preset_platform_for "$_cov_req")"
		if printf '%s\n' "$_cov_table" | cut -f3 | grep -qxF -- "$_cov_want"; then
			ci_ok "preset platform covered: $_cov_req (platform=\"$_cov_want\")"
		else
			ci_fail "preset platform missing: $_cov_req (no preset with platform=\"$_cov_want\")"
			_cov_rc="$CI_FAIL"
		fi
	done
	return "$_cov_rc"
}

# ci_preset_field <export_presets.cfg> <preset.N> <key> : prints the value of
# <key> as written in that preset's own section or in its [preset.N.options]
# section, with surrounding quotes stripped. Prints nothing and returns 1 when
# the key is absent, so a caller can never mistake an empty line for a value.
ci_preset_field() {
	_pf_cfg="$1"
	_pf_idx="$2"
	_pf_key="$3"
	[ -f "$_pf_cfg" ] || return 1
	_pf_out="$(awk -v idx="$_pf_idx" -v key="$_pf_key" '
		/^\[/ { insec = ($0 == "[" idx "]" || $0 == "[" idx ".options]"); next }
		insec && index($0, key "=") == 1 {
			v = $0; sub(/^[^=]*=/, "", v); gsub(/^"|"$/, "", v); out = v
		}
		END { if (out != "") print out }
	' "$_pf_cfg" 2>/dev/null)"
	[ -n "$_pf_out" ] || return 1
	printf '%s\n' "$_pf_out"
	return 0
}

# ci_preset_index_for <export_presets.cfg> <preset name> : prints "preset.N"
# for the preset with that exact name, so the field reader above can be driven
# from a name the way `export --export <name>` is.
ci_preset_index_for() {
	_pi_cfg="$1"
	_pi_name="$2"
	[ -f "$_pi_cfg" ] || return 1
	_pi_out="$(ci_preset_table "$_pi_cfg" 2>/dev/null | awk -F'\t' -v n="$_pi_name" '$2 == n { print $1; exit }')"
	[ -n "$_pi_out" ] || return 1
	printf '%s\n' "$_pi_out"
	return 0
}

# ci_preset_architecture <export_presets.cfg> <preset.N> : prints the preset's
# binary_format/architecture, or fails when it is not declared. Opus recheck
# finding E2 is that a presence check accepting ANY architecture reported a
# green check for a build that cannot be produced: an export uses the
# architecture the preset declares, and a missing or different template fails
# at export time. Refusing to guess keeps the check honest.
ci_preset_architecture() {
	_pa_cfg="$1"
	_pa_idx="$2"
	_pa_arch="$(ci_preset_field "$_pa_cfg" "$_pa_idx" binary_format/architecture 2>/dev/null)" || return 1
	[ -n "$_pa_arch" ] || return 1
	printf '%s\n' "$_pa_arch"
	return 0
}

# ---------------------------------------------------------------------------
# Export template files
# ---------------------------------------------------------------------------
# The template file names the pinned official release ships, measured from
# export_templates/4.7.2.stable/ in that release (not invented):
#   macos.zip                     one universal archive for every architecture
#   windows_<mode>_<arch>.exe     x86_64 | x86_32 | arm64
#   linux_<mode>.<arch>           x86_64 | x86_32 | arm64 | arm32
# The Windows *_console.exe variants are accepted alternatives: Godot selects
# them when the preset enables the console wrapper, and the release ships both.

# ci_template_architectures <platform> : the architecture values Godot accepts
# for that platform, space separated. Fails for an unknown platform.
ci_template_architectures() {
	case "$1" in
		macOS) printf 'universal arm64 x86_64\n' ;;
		Windows) printf 'x86_64 x86_32 arm64\n' ;;
		Linux) printf 'x86_64 x86_32 arm64 arm32\n' ;;
		*) return 1 ;;
	esac
	return 0
}

# ci_template_files_for <platform> <architecture> <mode> : prints the template
# file name(s) the engine looks for, one per line. Fails for an architecture
# Godot does not accept on that platform, for an unknown platform, or for an
# unknown export mode, so a caller cannot fall back to "any file will do".
ci_template_files_for() {
	_tf_platform="$1"
	_tf_arch="$2"
	_tf_mode="$3"
	case "$_tf_mode" in
		debug | release) : ;;
		*) return 1 ;;
	esac
	_tf_known=no
	for _tf_a in $(ci_template_architectures "$_tf_platform" 2>/dev/null); do
		if [ "$_tf_a" = "$_tf_arch" ]; then
			_tf_known=yes
			break
		fi
	done
	[ "$_tf_known" = yes ] || return 1
	case "$_tf_platform" in
		macOS) printf 'macos.zip\n' ;;
		Windows)
			printf 'windows_%s_%s.exe\n' "$_tf_mode" "$_tf_arch"
			printf 'windows_%s_%s_console.exe\n' "$_tf_mode" "$_tf_arch"
			;;
		Linux) printf 'linux_%s.%s\n' "$_tf_mode" "$_tf_arch" ;;
		*) return 1 ;;
	esac
	return 0
}

# ci_is_positive_int <value> : true for a non-empty run of digits that is not
# zero. Used for --frames/--fps: `--quit-after 0` tells Godot to never quit, so
# accepting 0 would turn a bounded probe into an unbounded one.
ci_is_positive_int() {
	case "$1" in
		'' | *[!0-9]*) return 1 ;;
	esac
	case "$1" in
		*[!0]*) return 0 ;;
		*) return 1 ;;
	esac
}

# ci_is_wxh <value> : true for exactly "<positive int>x<positive int>".
ci_is_wxh() {
	case "$1" in
		'' | *x*x*) return 1 ;;
	esac
	case "$1" in
		*x*) : ;;
		*) return 1 ;;
	esac
	_w="${1%%x*}"
	_h="${1##*x}"
	ci_is_positive_int "$_w" || return 1
	ci_is_positive_int "$_h" || return 1
	return 0
}

# ci_probe_video_size <file> : prints "<w>x<h>" of the first video stream, or
# nothing when ffprobe is unavailable or the file has no video stream. Used to
# confirm what a capture ACTUALLY recorded instead of what was requested.
ci_probe_video_size() {
	_file="$1"
	[ -s "$_file" ] || return 1
	command -v ffprobe >/dev/null 2>&1 || return 1
	_out="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
		-of default=noprint_wrappers=1:nokey=1 "$_file" 2>/dev/null | tr '\n' ' ')"
	_w="$(printf '%s' "$_out" | awk '{print $1}')"
	_h="$(printf '%s' "$_out" | awk '{print $2}')"
	case "$_w$_h" in
		'' | *[!0-9\ ]*) return 1 ;;
	esac
	printf '%sx%s\n' "$_w" "$_h"
}

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------
CI_RUN_NAME="${CI_RUN_NAME:-run}"
CI_REPORT=""

ci_init_report() {
	mkdir -p "$CI_OUT/reports" 2>/dev/null
	_stamp="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date -u +%s)"
	CI_REPORT="$CI_OUT/reports/${CI_RUN_NAME}-${_stamp}.txt"
	{
		printf 'command: %s\n' "$CI_RUN_NAME"
		printf 'utc: %s\n' "$_stamp"
		printf 'project: %s\n' "$CI_PROJECT"
		printf 'godot: %s (%s)\n' "${GODOT_VERSION_FULL:-not resolved}" "${GODOT_BIN:-not resolved}"
		printf 'os: %s %s\n' "$(uname -s 2>/dev/null)" "$(uname -r 2>/dev/null)"
		printf 'source-sha: %s\n' "${ROADSTORM_SOURCE_SHA:-not recorded}"
	} >"$CI_REPORT" 2>/dev/null
}

ci_report() {
	[ -n "$CI_REPORT" ] || return 0
	printf '%s\n' "$*" >>"$CI_REPORT" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------
# ci_yes_no <value> : normalises truthy strings.
ci_is_true() {
	case "$1" in
		1 | true | TRUE | True | yes | YES | on | ON) return 0 ;;
		*) return 1 ;;
	esac
}

# ci_sha256 <file> : portable sha256 (macOS has shasum, Linux usually sha256sum).
ci_sha256() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" 2>/dev/null | awk '{print $1}'
	else
		printf 'unavailable'
	fi
}

# ci_sha512 <file> : portable sha512. Needed because the publisher's
# SHA512-SUMS.txt is SHA-512, so the pinned artifact digest is compared with the
# same algorithm the publisher used rather than a re-derived one.
ci_sha512() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 512 "$1" 2>/dev/null | awk '{print $1}'
	elif command -v sha512sum >/dev/null 2>&1; then
		sha512sum "$1" 2>/dev/null | awk '{print $1}'
	else
		printf 'unavailable'
	fi
}

# ci_sha256_tool : prints the name of an available sha256 utility, or nothing.
ci_sha256_tool() {
	if command -v shasum >/dev/null 2>&1; then
		printf 'shasum'
	elif command -v sha256sum >/dev/null 2>&1; then
		printf 'sha256sum'
	fi
}

# ci_sha512_tool : prints the name of an available sha512 utility, or nothing.
ci_sha512_tool() {
	if command -v shasum >/dev/null 2>&1; then
		printf 'shasum'
	elif command -v sha512sum >/dev/null 2>&1; then
		printf 'sha512sum'
	fi
}

# ci_verify_digest <label> <file> <expected> <sha256|sha512>
# Returns CI_OK when the file's digest equals <expected>, CI_FAIL otherwise.
# An empty <expected> is a FAIL, not a pass: an unrecorded pin must never let an
# artifact through (PLAN.md M0.1: "never invent ... a digest").
ci_verify_digest() {
	_label="$1"
	_file="$2"
	_expected="$3"
	_algo="$4"

	[ -n "$_expected" ] || {
		ci_fail "$_label: no pinned digest recorded; refusing to accept the artifact unverified"
		return "$CI_FAIL"
	}
	case "$_algo" in
		sha256) _observed="$(ci_sha256 "$_file")" ;;
		sha512) _observed="$(ci_sha512 "$_file")" ;;
		*) ci_die "ci_verify_digest: unknown algorithm '$_algo'" ;;
	esac
	case "$_observed" in
		'' | unavailable)
			ci_fail "$_label: cannot compute a $_algo digest of $_file (file unreadable or no $_algo utility on PATH)"
			return "$CI_FAIL"
			;;
	esac
	if [ "$_observed" = "$_expected" ]; then
		ci_ok "$_label: $_algo matches the pinned digest ($_observed)"
		return "$CI_OK"
	fi
	ci_fail "$_label: $_algo MISMATCH"
	ci_fail "  expected: $_expected"
	ci_fail "  observed: $_observed"
	ci_fail "  file:     $_file"
	return "$CI_FAIL"
}

# ci_sha256_stdin : portable sha256 of standard input.
ci_sha256_stdin() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 2>/dev/null | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum 2>/dev/null | awk '{print $1}'
	else
		printf 'unavailable'
	fi
}

# ci_relpath <abs> : path relative to the project root, for reporting.
ci_relpath() {
	case "$1" in
		"$CI_PROJECT"/*) printf '%s\n' "${1#$CI_PROJECT/}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}

# ci_tracked_output_paths <project-root> <rel-out-dir> : prints paths tracked
# in the Git index under <rel-out-dir>, one per line, EXCLUDING the exact
# sentinel "<rel-out-dir>/.gitignore" that keeps the scratch directory ignored
# while itself staying tracked. Every other tracked path is build output and is
# a failure: exempting the whole directory, or every dotfile, would defeat the
# check this function exists for. Prints nothing when Git or an index is not
# available; the caller decides whether that case is testable. Returns 1 only
# for a malformed invocation.
ci_tracked_output_paths() {
	_top_root="$1"
	_top_rel="$2"
	[ -n "$_top_root" ] && [ -n "$_top_rel" ] || return 1
	command -v git >/dev/null 2>&1 || return 0
	if [ ! -d "$_top_root/.git" ] && [ ! -f "$_top_root/.git" ]; then
		return 0
	fi
	(cd "$_top_root" && git ls-files -- "$_top_rel" 2>/dev/null) |
		while IFS= read -r _top_path || [ -n "$_top_path" ]; do
			[ -n "$_top_path" ] || continue
			[ "$_top_path" = "$_top_rel/.gitignore" ] && continue
			printf '%s\n' "$_top_path"
		done
	return 0
}

# ci_preset_slug <preset-name> : lowercase, dash-separated token safe for log
# and report file names.
ci_preset_slug() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]-' '-' | tr -s '-'
}

# ci_abs_path <path> : prints <path> made absolute against the current working
# directory and resolved with FILESYSTEM semantics: a ".." following a
# symlinked component follows the target's parent, exactly as opening the
# caller's path would. Lexically collapsing ".." first is wrong --
# `caller/via/../package` with `via -> elsewhere/inner` reaches
# `elsewhere/package`, not `caller/package` (reproduced by Sol at 245ee1d).
# Even `cd` cannot be used on the whole path for this: shells apply ".."
# logically to the textual prefix, which reproduces the same error. Each
# component is therefore resolved step by step: symlinks are followed by the
# kernel, and ".." moves up from the PHYSICAL parent. The first component that
# does not exist (and everything after it) is appended unchanged, which is the
# best available answer for a path that cannot exist yet.
#
# A relative export --out must be canonicalised against the CALLER's directory
# before Godot sees it: Godot resolves a relative export path against --path
# (the scratch project), which is the hosted-run defect where the package
# landed in tools/ci/out/project-copy and the wrapper reported "export produced
# no output". Returns 1 on an empty argument.
ci_abs_path() {
	_cap_in="$1"
	[ -n "$_cap_in" ] || return 1
	case "$_cap_in" in
		/*) : ;;
		*) _cap_in="${PWD:-$(pwd)}/$_cap_in" ;;
	esac
	# Remove "." and duplicate separators ONLY. ".." must stay: whether it
	# cancels the previous component depends on whether that component is a
	# symlink, which only stepwise filesystem resolution can honour.
	_cap_comps="$(printf '%s\n' "$_cap_in" | awk '
		BEGIN { RS = "/" }
		$0 == "" || $0 == "." { next }
		{ print }
	')"
	_cap_cur="/"
	_cap_tail=""
	_cap_missing=0
	while IFS= read -r _cap_comp; do
		[ -n "$_cap_comp" ] || continue
		if [ "$_cap_missing" -eq 1 ]; then
			_cap_tail="$_cap_tail/$_cap_comp"
			continue
		fi
		if [ "$_cap_comp" = ".." ]; then
			_cap_cur="${_cap_cur%/*}"
			[ -n "$_cap_cur" ] || _cap_cur="/"
			continue
		fi
		case "$_cap_cur" in
			/) _cap_next="/$_cap_comp" ;;
			*) _cap_next="$_cap_cur/$_cap_comp" ;;
		esac
		if [ -d "$_cap_next" ]; then
			_cap_resolved="$(cd "$_cap_next" 2>/dev/null && { pwd -P 2>/dev/null || pwd; })" || {
				_cap_tail="$_cap_comp"
				_cap_missing=1
				continue
			}
			_cap_cur="$_cap_resolved"
		else
			_cap_tail="$_cap_comp"
			_cap_missing=1
		fi
	done <<EOF
$_cap_comps
EOF
	if [ -n "$_cap_tail" ]; then
		case "$_cap_cur" in
			/) _cap_cur="/$_cap_tail" ;;
			*/) _cap_cur="${_cap_cur}${_cap_tail}" ;;
			*) _cap_cur="$_cap_cur/$_cap_tail" ;;
		esac
	fi
	printf '%s\n' "$_cap_cur"
}
