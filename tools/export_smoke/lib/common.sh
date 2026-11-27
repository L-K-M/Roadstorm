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

# es_resolve_head <project-dir> : print the current HEAD commit as one
# immutable full SHA, resolved exactly once. Fails closed if HEAD is missing
# or does not resolve to a 40-digit lowercase hex commit.
es_resolve_head() {
	_proj="$1"
	[ -d "$_proj" ] || return 1
	_sha="$( cd "$_proj" && git rev-parse --verify --quiet HEAD )" || return 1
	es_is_commit_sha "$_sha" || return 1
	printf '%s\n' "$_sha"
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

# es_is_hex <string> <length> : true iff <string> is exactly <length>
# lowercase hex digits. The glob class must stay UNQUOTED; quoting it would
# test for the literal substring and let non-hex values through.
es_is_hex() {
	_v="$1"; _n="$2"
	[ "${#_v}" -eq "$_n" ] || return 1
	case "$_v" in
	*[!0-9a-f]*) return 1 ;;
	esac
	return 0
}

# es_is_hex_sha256 <string> : exactly 64 lowercase hex digits.
es_is_hex_sha256() { es_is_hex "$1" 64; }

# es_is_commit_sha <string> : exactly 40 lowercase hex digits (SHA-1 commit).
es_is_commit_sha() { es_is_hex "$1" 40; }

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

# _es_path_ids <path> : print "<device> <inode>" for an existing path.
# Used only to prove a path is still the exact object this invocation created
# before removing it; it never resolves symlinks.
_es_path_ids() {
	_p="$1"
	# GNU stat takes -c, BSD stat takes -f. Do NOT let a BSD-style -f call
	# fall through to GNU's "file system status" mode: that reports fs-wide
	# values and would make the identity guard useless.
	if stat --version >/dev/null 2>&1; then
		_out="$(stat -c '%d %i' "$_p" 2>/dev/null)" && [ -n "$_out" ] && {
			printf '%s\n' "$_out"
			return 0
		}
	elif stat -f '%d %i' "$_p" >/dev/null 2>&1; then
		_out="$(stat -f '%d %i' "$_p" 2>/dev/null)" && [ -n "$_out" ] && {
			printf '%s\n' "$_out"
			return 0
		}
	fi
	# Last resort: inode only. Weaker than device+inode, but still proves the
	# exact directory object and never follows symlinks.
	# shellcheck disable=SC2012  # inode of one fixed path we just created
	_out="$(ls -di "$_p" 2>/dev/null | awk '{print $1}')" && [ -n "$_out" ] && {
		printf 'inode:%s\n' "$_out"
		return 0
	}
	return 1
}

# _es_reservation_ok <snap-abs> <ids> : true while the destination is still the
# exact non-symlink directory this invocation reserved.
_es_reservation_ok() {
	[ -n "$2" ] || return 1
	[ -L "$1" ] && return 1
	_now="$(_es_path_ids "$1")" || return 1
	[ "$_now" = "$2" ]
}

# _es_cleanup_stage <staging> <staging-ids>
# Removes ONLY the private mktemp staging directory this invocation created,
# and only while it is still that exact non-symlink directory. Nothing else is
# ever deleted here: a failed run leaves its (possibly partial) reservation in
# place with a diagnostic instead of risking another process's files.
_es_cleanup_stage() {
	_cs_stage="$1"; _cs_stage_ids="$2"
	[ -n "$_cs_stage" ] || return 0
	[ -L "$_cs_stage" ] && return 0
	[ -d "$_cs_stage" ] || return 0
	_cs_now="$(_es_path_ids "$_cs_stage")" || _cs_now=""
	[ -n "$_cs_stage_ids" ] || return 0
	[ "$_cs_now" = "$_cs_stage_ids" ] || return 0
	rm -rf "$_cs_stage"
	return 0
}

# es_make_frozen_snapshot <project-dir> <snapshot-dir> [archive-digest-file]
#                            [commit-sha]
# Builds the FROZEN, ISOLATED source candidate:
#   * `git archive <commit-sha>` of the project (committed state only),
#     extracted to <snapshot-dir>. With no commit-sha it archives HEAD. The
#     SHA must be an immutable 40-digit hex commit, so a moving shared HEAD
#     cannot change what gets archived between resolution and extraction.
#   * Overlay ONLY the owned export presets (export_presets.cfg). No other
#     concurrent uncommitted file (schemas, fixtures, other jobs' WIP) enters
#     the candidate.
#   * With the optional <archive-digest-file>, writes the SHA-256 of the exact
#     archive bytes that were extracted (no second, unchecked `git archive`
#     invocation). That file must not already exist; it is created, never
#     truncated.
#
# Preservation contract (M0 export-smoke repair):
#   * <snapshot-dir> is NEVER moved, replaced, overwritten or recursively
#     deleted. A pre-existing destination in ANY form -- directory (empty or
#     not), regular file, symlink, dangling symlink, or a path another process
#     creates first -- makes the call fail closed with an explanation.
#   * An absent destination is RESERVED with an exclusive mkdir, so there is
#     no check-then-clobber race: whoever creates the name first owns it. Only
#     after that reservation is anything written under it.
#   * On failure the partial reservation is LEFT IN PLACE for inspection (with
#     a NOTE in the diagnostic). Only the private staging directory is
#     removed, and only while it is provably still the directory this call
#     created. Unrelated or concurrently added paths are never deleted.
#   * The archive and extraction stages are checked SEPARATELY. A shell
#     pipeline would report tar's exit status, which is 0 even when
#     `git archive HEAD` produced nothing -- that used to publish an empty
#     one-file candidate and hide the real cause.
#   * A missing project dir, a non-Git source, a failed `git archive HEAD`, a
#     failed extraction, or an archive with no usable project.godot returns
#     nonzero. This tool takes no --source/--commit input: a source tree that
#     is not a Git working tree is rejected rather than silently accepted.
# Prints nothing on success; failures go to stderr. Returns nonzero on failure.
es_make_frozen_snapshot() {
	_proj="$1"
	_snap_arg="$2"
	_digest_file="${3:-}"
	_rev_arg="${4:-}"
	_archive_rev="HEAD"
	_snap="$2"
	_stage=""
	_stage_ids=""
	_res_ids=""

	while [ "$_snap" != "/" ] && [ "${_snap%/}" != "$_snap" ]; do
		_snap="${_snap%/}"
	done
	case "$_snap" in
	""|"/") printf '[export-smoke] FAIL: invalid snapshot dir: %s\n' "$_snap_arg" >&2; return 1 ;;
	esac
	_snap_dir="$(dirname "$_snap")"
	_snap_base="$(basename "$_snap")"
	case "$_snap_base" in
	""|"."|"..") printf '[export-smoke] FAIL: invalid snapshot dir: %s\n' "$_snap_arg" >&2; return 1 ;;
	esac

	if [ ! -d "$_proj" ]; then
		printf '[export-smoke] FAIL: project dir not found: %s\n' "$_proj" >&2
		return 1
	fi
	if ! mkdir -p "$_snap_dir" 2>/dev/null; then
		printf '[export-smoke] FAIL: cannot create snapshot parent: %s\n' "$_snap_dir" >&2
		return 1
	fi
	if ! _snap_dir="$(cd "$_snap_dir" && pwd -P 2>/dev/null)"; then
		printf '[export-smoke] FAIL: cannot resolve snapshot parent: %s\n' "$_snap_arg" >&2
		return 1
	fi
	if ! _proj_abs="$(cd "$_proj" && pwd -P 2>/dev/null)"; then
		printf '[export-smoke] FAIL: cannot resolve project dir: %s\n' "$_proj" >&2
		return 1
	fi
	_snap_abs="$_snap_dir/$_snap_base"
	if [ "$_snap_abs" = "$_proj_abs" ]; then
		printf '[export-smoke] FAIL: snapshot dir must differ from the project dir: %s\n' "$_snap_abs" >&2
		return 1
	fi

	# Reject unsupported input explicitly instead of letting a failed archive
	# masquerade as an extraction problem.
	if ! ( cd "$_proj_abs" && git rev-parse --is-inside-work-tree ) >/dev/null 2>&1; then
		printf '[export-smoke] FAIL: %s is not a Git working tree; a frozen candidate cannot be built from it\n' "$_proj_abs" >&2
		return 1
	fi

	# When an immutable commit is supplied, validate and pin it BEFORE any
	# output is reserved or written.
	if [ -n "$_rev_arg" ]; then
		es_is_commit_sha "$_rev_arg" || {
			printf '[export-smoke] FAIL: commit must be exactly 40 lowercase hex digits: %s\n' "$_rev_arg" >&2
			return 1
		}
		if ! ( cd "$_proj_abs" && git rev-parse --verify --quiet "$_rev_arg^{commit}" ) >/dev/null 2>&1; then
			printf '[export-smoke] FAIL: commit does not resolve in %s: %s\n' "$_proj_abs" "$_rev_arg" >&2
			return 1
		fi
		_archive_rev="$_rev_arg"
	fi

	# Advisory occupancy report; the exclusive mkdir below is authoritative
	# and closes the check-then-clobber race.
	if [ -L "$_snap_abs" ]; then
		printf '[export-smoke] FAIL: snapshot destination exists as a symlink: %s\n' "$_snap_abs" >&2
		return 1
	elif [ -d "$_snap_abs" ]; then
		printf '[export-smoke] FAIL: snapshot destination already exists as a directory: %s\n' "$_snap_abs" >&2
		return 1
	elif [ -e "$_snap_abs" ]; then
		printf '[export-smoke] FAIL: snapshot destination already exists as a file: %s\n' "$_snap_abs" >&2
		return 1
	fi
	if ! mkdir "$_snap_abs" 2>/dev/null; then
		printf '[export-smoke] FAIL: snapshot destination is occupied or cannot be reserved: %s\n' "$_snap_abs" >&2
		return 1
	fi
	_res_ids="$(_es_path_ids "$_snap_abs")" || {
		printf '[export-smoke] FAIL: cannot identify the reserved snapshot dir: %s\n' "$_snap_abs" >&2
		return 1
	}
	_note_left() {
		printf '[export-smoke] NOTE: partial snapshot left in place for inspection: %s\n' "$_snap_abs" >&2
	}

	_stage="$(mktemp -d "$_snap_dir/.${_snap_base}.stage.XXXXXX" 2>/dev/null)" || {
		printf '[export-smoke] FAIL: cannot create a private staging dir in %s\n' "$_snap_dir" >&2
		_note_left
		return 1
	}
	_stage_ids="$(_es_path_ids "$_stage")" || {
		printf '[export-smoke] FAIL: cannot identify the private staging dir\n' >&2
		_es_cleanup_stage "$_stage" ""
		_note_left
		return 1
	}
	_archive="$_stage/candidate.tar"
	_err="$_stage/stage.err"

	# Stage 1: build the archive. Its exit status is captured directly; the
	# output is a real file, so tar cannot mask its failure.
	( cd "$_proj_abs" && git archive --format=tar "$_archive_rev" ) >"$_archive" 2>"$_err"
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		printf '[export-smoke] FAIL: git archive HEAD failed in %s (exit %s)\n' "$_proj_abs" "$_rc" >&2
		sed -n '1,5p' "$_err" 2>/dev/null | sed 's/^/[export-smoke]   /' >&2
		_es_cleanup_stage "$_stage" "$_stage_ids"
		_note_left
		return 1
	fi

	# Evidence binding: hash the exact archive file that will be extracted.
	# Never re-invoke `git archive` for the digest.
	if [ -n "$_digest_file" ]; then
		_digest="$(es_sha256 "$_archive")" || _digest=""
		if ! es_is_hex_sha256 "$_digest"; then
			printf '[export-smoke] FAIL: could not compute a SHA-256 of the frozen archive\n' >&2
			_es_cleanup_stage "$_stage" "$_stage_ids"
			_note_left
			return 1
		fi
		if [ -e "$_digest_file" ] || [ -L "$_digest_file" ]; then
			printf '[export-smoke] FAIL: archive digest destination already exists (refusing to overwrite): %s\n' "$_digest_file" >&2
			_es_cleanup_stage "$_stage" "$_stage_ids"
			_note_left
			return 1
		fi
		if ! printf '%s\n' "$_digest" >"$_digest_file" 2>/dev/null; then
			printf '[export-smoke] FAIL: could not write the archive digest to %s\n' "$_digest_file" >&2
			_es_cleanup_stage "$_stage" "$_stage_ids"
			_note_left
			return 1
		fi
	fi

	if ! _es_reservation_ok "$_snap_abs" "$_res_ids"; then
		printf '[export-smoke] FAIL: the reserved snapshot dir was replaced concurrently: %s\n' "$_snap_abs" >&2
		_es_cleanup_stage "$_stage" "$_stage_ids"
		return 1
	fi

	# Stage 2: extract into the reserved destination. An archive that cannot
	# be extracted fails closed; the partial reservation is left in place.
	tar -x -f "$_archive" -C "$_snap_abs" 2>"$_err"
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		printf '[export-smoke] FAIL: extracting the frozen archive failed (exit %s)\n' "$_rc" >&2
		sed -n '1,5p' "$_err" 2>/dev/null | sed 's/^/[export-smoke]   /' >&2
		_es_cleanup_stage "$_stage" "$_stage_ids"
		_note_left
		return 1
	fi
	rm -f "$_archive" "$_err"

	# Overlay ONLY the owned export presets.
	if [ -f "$_proj_abs/export_presets.cfg" ]; then
		if ! cp "$_proj_abs/export_presets.cfg" "$_snap_abs/export_presets.cfg" 2>"$_err"; then
			printf '[export-smoke] FAIL: could not overlay export_presets.cfg\n' >&2
			sed -n '1,5p' "$_err" 2>/dev/null | sed 's/^/[export-smoke]   /' >&2
			_es_cleanup_stage "$_stage" "$_stage_ids"
			_note_left
			return 1
		fi
	fi

	# Stage 3: the candidate must actually be a Godot project.
	if [ ! -f "$_snap_abs/project.godot" ]; then
		printf '[export-smoke] FAIL: the frozen archive from %s has no project.godot; refusing to publish an unusable candidate\n' "$_proj_abs" >&2
		_es_cleanup_stage "$_stage" "$_stage_ids"
		_note_left
		return 1
	fi
	if [ ! -s "$_snap_abs/project.godot" ]; then
		printf '[export-smoke] FAIL: the frozen archive from %s has an empty project.godot; refusing to publish it\n' "$_proj_abs" >&2
		_es_cleanup_stage "$_stage" "$_stage_ids"
		_note_left
		return 1
	fi

	if ! _es_reservation_ok "$_snap_abs" "$_res_ids"; then
		printf '[export-smoke] FAIL: the reserved snapshot dir was replaced concurrently: %s\n' "$_snap_abs" >&2
		_es_cleanup_stage "$_stage" "$_stage_ids"
		return 1
	fi

	_es_cleanup_stage "$_stage" "$_stage_ids"
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
