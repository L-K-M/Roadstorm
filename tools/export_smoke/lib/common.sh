#!/bin/sh
# Roadstorm Racer! - export smoke shared helpers.
# Ownership: tools/export_smoke/** (PLAN.md "How agents execute the plan").
#
# Sourced by run_export_smoke.sh and launch_macos_app.sh. Not executed directly.
# Original project code under the Unlicense.
#
# This library is deliberately self-contained: it does NOT source tools/ci/**
# (owned by another job). It only reads the pinned engine version string from
# tools/toolchain/pin/engine.txt when present, mirroring that value as a
# fallback, exactly like tools/smoke/run_boot_smoke.sh.

# es_default_godot : print the Godot binary to use.
#   $GODOT_BIN if set, else the first `godot` on PATH, else the Homebrew path.
es_default_godot() {
	if [ -n "${GODOT_BIN:-}" ]; then
		printf '%s\n' "$GODOT_BIN"
		return 0
	fi
	if command -v godot >/dev/null 2>&1; then
		command -v godot
		return 0
	fi
	if [ -x /opt/homebrew/bin/godot ]; then
		printf '%s\n' /opt/homebrew/bin/godot
		return 0
	fi
	return 1
}

# es_pinned_version <project-dir> : print the pinned engine --version string.
# Prefers tools/toolchain/pin/engine.txt (owned by tools/toolchain/**); falls
# back to the mirrored constant below.
es_pinned_version() {
	_proj="$1"
	_pin="$_proj/tools/toolchain/pin/engine.txt"
	if [ -f "$_pin" ]; then
		_rec="$(sed -n 's/^version_string=//p' "$_pin" | head -n 1)"
		if [ -n "$_rec" ]; then
			printf '%s\n' "$_rec"
			return 0
		fi
	fi
	printf '%s\n' "4.7.2.stable.official.ed1daf0bf"
}

# es_sha256 <file> : portable sha256 (shasum, sha256sum or openssl).
es_sha256() {
	_f="$1"
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$_f" | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$_f" | awk '{print $1}'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 "$_f" | awk '{print $NF}'
	else
		printf '%s\n' "NO_SHA256_UTILITY"
	fi
}

# es_run_bounded <seconds> <logfile> -- <cmd...>
# Runs <cmd> with output to <logfile>, supervising it ourselves so the tool
# works even where the coreutils `timeout` binary is absent (stock macOS).
# Prints the child's exit status. A status of 124 means the time limit hit.
es_run_bounded() {
	_secs="$1"; shift
	_log="$1"; shift
	[ "$1" = "--" ] && shift
	( "$@" ) >"$_log" 2>&1 &
	_pid=$!
	(
		sleep "$_secs" 2>/dev/null
		kill -TERM "$_pid" 2>/dev/null
		sleep 3 2>/dev/null
		kill -KILL "$_pid" 2>/dev/null
	) >/dev/null 2>&1 &
	_watch=$!
	wait "$_pid" 2>/dev/null
	_rc=$?
	kill "$_watch" 2>/dev/null
	wait "$_watch" 2>/dev/null
	# 128+15 (TERM) or 128+9 (KILL) from our supervisor => treat as a timeout.
	if [ "$_rc" -ge 124 ] && [ "$_rc" -le 137 ]; then
		return 124
	fi
	return "$_rc"
}

# es_make_frozen_snapshot <project-dir> <snapshot-dir>
# Builds the FROZEN, ISOLATED source candidate:
#   * `git archive HEAD` of the project (committed state only), extracted to
#     <snapshot-dir>. No working-tree file that is not committed is copied.
#   * Overlay ONLY the owned export presets (export_presets.cfg). No other
#     concurrent uncommitted file (schemas, fixtures, other jobs' WIP) enters
#     the candidate.
# Prints nothing; returns nonzero on failure.
es_make_frozen_snapshot() {
	_proj="$1"
	_snap="$2"
	rm -rf "$_snap"
	mkdir -p "$_snap" || return 1
	if ! ( cd "$_proj" && git archive HEAD ) | tar -x -C "$_snap" 2>/dev/null; then
		return 1
	fi
	if [ -f "$_proj/export_presets.cfg" ]; then
		cp "$_proj/export_presets.cfg" "$_snap/export_presets.cfg" || return 1
	fi
	return 0
}

# es_candidate_digest <project-dir> : print a single content digest for the
# frozen candidate = sha256( archive_sha256 \n presets_sha256 ). Also echoes the
# component digests to stderr for the report.
es_candidate_digest() {
	_proj="$1"
	_archive_sha="$( cd "$_proj" && git archive HEAD | es_sha256 /dev/stdin 2>/dev/null )"
	# es_sha256 on a pipe needs a real file; recompute via a temp stream.
	_archive_sha="$( cd "$_proj" && git archive HEAD | shasum -a 256 2>/dev/null | awk '{print $1}' )"
	if [ -z "$_archive_sha" ] && command -v sha256sum >/dev/null 2>&1; then
		_archive_sha="$( cd "$_proj" && git archive HEAD | sha256sum 2>/dev/null | awk '{print $1}' )"
	fi
	_presets_sha="$(es_sha256 "$_proj/export_presets.cfg")"
	printf 'archive_sha256=%s\n' "$_archive_sha" >&2
	printf 'presets_sha256=%s\n' "$_presets_sha" >&2
	printf '%s\n%s\n' "$_archive_sha" "$_presets_sha" | shasum -a 256 2>/dev/null | awk '{print $1}'
}
