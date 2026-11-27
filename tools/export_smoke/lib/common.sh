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
	# Never truncate an existing path: create the log exclusively, then append.
	if ! _es_create_exclusive "$_log" ""; then
		printf '[export-smoke] FAIL: cannot create run log exclusively: %s\n' "$_log" >&2
		return 1
	fi
	( "$@" ) >>"$_log" 2>&1 &
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
# Intentionally does NOT delete. A recursive delete through a mutable pathname
# could remove a concurrently replaced foreign tree, so private staging is
# left in place as bounded failure evidence (one archived candidate plus a
# few small text files). See the README "Failure evidence and cleanup". The
# arguments are kept so call sites read clearly and so a future safe cleanup
# method has the identity available.
_es_cleanup_stage() {
	_cs_stage="$1"; _cs_stage_ids="$2"
	[ -n "$_cs_stage" ] || return 0
	return 0
}

# es_require_python : python3 is the pinned stdlib used for atomic opens.
es_require_python() {
	command -v python3 >/dev/null 2>&1 && return 0
	printf '[export-smoke] FAIL: python3 is required for atomic exclusive writes\n' >&2
	return 1
}

# _es_create_exclusive <file> <content>
# Creates <file> with <content> (empty = zero bytes) using a single atomic
# O_CREAT|O_EXCL|O_WRONLY open and writes the bytes through that held
# descriptor. There is NO temp path and NO second open of <file>, so a
# concurrent symlink swap cannot be followed or truncated. A partial file is
# intentionally retained if a later write fails. Returns nonzero if the
# destination exists/symlink or cannot be created.
_es_create_exclusive() {
	_file="$1"; _content="$2"
	case "$(basename "$_file")" in
	""|"."|"..") return 1 ;;
	esac
	es_require_python || return 1
	if [ -n "$_content" ]; then
		printf '%s\n' "$_content" | python3 -c '
import os,sys
p=sys.argv[1]
try:
    fd=os.open(p,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
except OSError:
    sys.exit(3)
data=sys.stdin.buffer.read()
try:
    with os.fdopen(fd,"wb") as f:
        f.write(data)
except OSError:
    sys.exit(4)
' "$_file" 2>/dev/null
	else
		printf '' | python3 -c '
import os,sys
p=sys.argv[1]
try:
    fd=os.open(p,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
except OSError:
    sys.exit(3)
os.close(fd)
' "$_file" 2>/dev/null
	fi
}

# es_run_exclusive <workdir> <outfile> <errfile-or-empty> -- <cmd...>
# Runs <cmd...> with cwd <workdir>, creating <outfile> and (unless empty)
# <errfile> atomically and streaming the child's stdout/stderr through those
# held descriptors. Returns the child's exit status; nonzero if either output
# already exists. Partial outputs are retained on failure. This is how archive
# capture and tar listings avoid any shell redirection through a pathname.
# Note: python3 must exist; this is the repo's pinned stdlib.
es_run_exclusive() {
	_rx_wd="$1"; _rx_out="$2"; _rx_err="$3"; shift 3
	[ "$1" = "--" ] && shift
	es_require_python || return 1
	python3 -c '
import os,subprocess,sys
wd,out,err=sys.argv[1],sys.argv[2],sys.argv[3]
cmd=sys.argv[4:]
def op(p):
    return os.open(p,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
try:
    fd_o=op(out)
except OSError:
    sys.exit(3)
fd_e=None
if err:
    try:
        fd_e=op(err)
    except OSError:
        os.close(fd_o)
        sys.exit(3)
try:
    p=subprocess.Popen(cmd,cwd=wd or None,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
except OSError as e:
    sys.stderr.write("exec failed: %s\n"%e)
    sys.exit(127)
while True:
    c=p.stdout.read(65536)
    if not c: break
    os.write(fd_o,c)
p.stdout.close()
if fd_e is not None:
    while True:
        c=p.stderr.read(65536)
        if not c: break
        os.write(fd_e,c)
else:
    p.stderr.read()
p.stderr.close()
os.close(fd_o)
if fd_e is not None:
    os.close(fd_e)
sys.exit(p.wait())
' "$_rx_wd" "$_rx_out" "$_rx_err" "$@" 2>/dev/null
}

# _es_copy_exclusive <src> <dst> <errfile-or-empty>
# Copies <src> to a newly created <dst> through an atomic O_EXCL open, so a
# pre-existing or swapped destination is never truncated/followed. Bytes read
# are exactly the bytes hashed afterwards. Partial dst is retained on error.
_es_copy_exclusive() {
	_cp_src="$1"; _cp_dst="$2"; _cp_err="$3"
	es_require_python || return 1
	python3 -c '
import os,sys
src,dst,err=sys.argv[1],sys.argv[2],sys.argv[3]
def op(p):
    return os.open(p,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
fd_e=None
if err:
    try:
        fd_e=op(err)
    except OSError:
        sys.exit(3)
def fail(msg,code):
    if fd_e is not None:
        try: os.write(fd_e,msg.encode())
        except OSError: pass
    sys.exit(code)
try:
    fs=os.open(src,os.O_RDONLY)
except OSError as e:
    fail("cannot open source: %s\n"%e,1)
try:
    fd=dst and op(dst)
except OSError as e:
    os.close(fs); fail("destination exists or uncreatable: %s\n"%e,3)
try:
    while True:
        c=os.read(fs,65536)
        if not c: break
        os.write(fd,c)
finally:
    os.close(fs); os.close(fd)
if fd_e is not None:
    os.close(fd_e)
' "$_cp_src" "$_cp_dst" "$_cp_err" 2>/dev/null
}

# es_validate_archive <archive> <workdir>
# Fails closed unless every archive member is a regular file or directory
# whose stored path stays inside the extraction root. Rejects symlinks, hard
# links, devices, fifos and absolute/upward-traversing paths BEFORE anything
# is extracted. Writes listing files under <workdir>; prints reasons itself.
es_validate_archive() {
	_va_arc="$1"; _va_w="$2"
	_va_list="$_va_w/tar-list.txt"
	_va_names="$_va_w/tar-names.txt"
	if ! es_run_exclusive "$_va_w" "$_va_list" "$_va_w/tar-list.err" -- tar -tvf "$_va_arc"; then
		printf '[export-smoke] FAIL: could not list the frozen archive\n' >&2
		return 1
	fi
	while IFS= read -r _va_line; do
		[ -n "$_va_line" ] || continue
		_va_perm="$(printf '%s' "$_va_line" | cut -c1)"
		case "$_va_perm" in
		-|d) ;;
		*)
			printf '[export-smoke] FAIL: unsafe archive entry type "%s"; only regular files and directories are accepted: %s\n' "$_va_perm" "$_va_line" >&2
			return 1
			;;
		esac
	done <"$_va_list"
	if ! es_run_exclusive "$_va_w" "$_va_names" "$_va_w/tar-names.err" -- tar -tf "$_va_arc"; then
		printf '[export-smoke] FAIL: could not enumerate archive paths\n' >&2
		return 1
	fi
	while IFS= read -r _va_name; do
		case "$_va_name" in
		""|/|/*|..|../*|*/..|*/../*)
			printf '[export-smoke] FAIL: unsafe archive path: %s\n' "$_va_name" >&2
			return 1
			;;
		esac
	done <"$_va_names"
	return 0
}

# es_build_reserved <snap-abs> <res-ids> <archive> <errfile> <stage> <proj-abs>
# Extracts and overlays INSIDE an already-reserved directory while holding it
# as cwd. The first action after cd verifies that the process current directory
# (.) still has the reserved device:inode, so a pathname swapped before cd is
# detected before any write; a later swap cannot redirect writes because cwd
# stays bound to the original inode. Re-verified immediately before preset temp
# creation. Returns nonzero with diagnostics on stderr.
es_build_reserved() {
	_br_snap="$1"; _br_ids="$2"; _br_archive="$3"; _br_err="$4"; _br_stage="$5"; _br_proj="$6"
	(
		if ! cd "$_br_snap" 2>/dev/null; then
			printf '[export-smoke] FAIL: cannot enter the reserved snapshot dir\n' >&2
			exit 1
		fi
		_cwd_ids="$(_es_path_ids ".")" || {
			printf '[export-smoke] FAIL: cannot identify the entered snapshot dir\n' >&2
			exit 1
		}
		if [ "$_cwd_ids" != "$_br_ids" ]; then
			printf '[export-smoke] FAIL: the reserved snapshot dir was replaced before it was entered; refusing to write\n' >&2
			exit 1
		fi
		if ! tar -x -f "$_br_archive" -C . 2>"$_br_err"; then
			printf '[export-smoke] FAIL: extracting the frozen archive failed\n' >&2
			sed -n '1,5p' "$_br_err" 2>/dev/null | sed 's/^/[export-smoke]   /' >&2
			exit 1
		fi
		if [ ! -f "$_br_proj/export_presets.cfg" ]; then
			printf '[export-smoke] FAIL: project has no export_presets.cfg to overlay\n' >&2
			exit 1
		fi
		_cwd_ids="$(_es_path_ids ".")" || {
			printf '[export-smoke] FAIL: cannot identify the held snapshot dir before overlay\n' >&2
			exit 1
		}
		if [ "$_cwd_ids" != "$_br_ids" ]; then
			printf '[export-smoke] FAIL: the held snapshot dir changed before overlay; refusing to write\n' >&2
			exit 1
		fi
		# Copy through an atomic O_EXCL open of a deterministic name in the
		# held directory; a swapped or pre-existing destination fails closed.
		_ptmp="./.roadstorm-presets.$$"
		if ! _es_copy_exclusive "$_br_proj/export_presets.cfg" "$_ptmp" "$_br_stage/presets.copy.err"; then
			printf '[export-smoke] FAIL: could not copy export_presets.cfg exclusively\n' >&2
			exit 1
		fi
		_pdigest="$(es_sha256 "$_ptmp")" || _pdigest=""
		if ! es_is_hex_sha256 "$_pdigest"; then
			printf '[export-smoke] FAIL: could not hash the copied export_presets.cfg\n' >&2
			exit 1
		fi
		if ! _es_create_exclusive "$_br_stage/presets.sha256" "$_pdigest"; then
			printf '[export-smoke] FAIL: could not record the copied presets digest\n' >&2
			exit 1
		fi
		if [ -d "./export_presets.cfg" ] && [ ! -L "./export_presets.cfg" ]; then
			printf '[export-smoke] FAIL: export_presets.cfg is a directory in the candidate\n' >&2
			exit 1
		fi
		if ! mv -f "$_ptmp" "./export_presets.cfg" 2>/dev/null; then
			printf '[export-smoke] FAIL: could not overlay export_presets.cfg\n' >&2
			exit 1
		fi
		if [ ! -f "./project.godot" ] || [ -L "./project.godot" ] || [ ! -s "./project.godot" ]; then
			printf '[export-smoke] FAIL: the frozen archive has no usable project.godot\n' >&2
			exit 1
		fi
		exit 0
	)
}

# es_make_frozen_snapshot <project-dir> <snapshot-dir> [archive-digest-file]
#                            [commit-sha]
# Builds the FROZEN, ISOLATED source candidate:
#   * `git archive <commit-sha>` of the project (committed state only),
#     extracted to <snapshot-dir>. With no commit-sha it archives HEAD. The
#     SHA must be an immutable 40-digit hex commit, so a moving shared HEAD
#     cannot change what gets archived between resolution and extraction.
#   * Overlay ONLY the owned export presets (export_presets.cfg), written
#     through a private temporary file and renamed into place, so a symlink at
#     the destination (from the archive or a concurrent replacement) is never
#     followed.
#   * With the optional <archive-digest-file>, writes two labelled lines with
#     the SHA-256 of the exact archive bytes extracted and of the exact copied
#     preset bytes (no second live read). That file must not already exist; it
#     is created, never truncated.
#
# Adversarial hardening:
#   * The archive is listed before extraction. Entry types other than regular
#     files and directories (symlinks, hard links, devices, fifos) and paths
#     that are absolute or traverse upward are rejected before anything is
#     extracted.
#   * Extraction runs inside a subshell that first chdir()s into the reserved
#     directory and then writes only relative paths. If the caller-visible
#     path is replaced by a symlink while tar runs, writes still land in the
#     held directory inode, never through the link.
#   * A pre-extraction and a post-build identity check fail closed if the
#     reservation was replaced.
#
# Preservation contract (M0 export-smoke repair):
#   * <snapshot-dir> is NEVER moved, replaced, overwritten or recursively
#     deleted. A pre-existing destination in ANY form makes the call fail
#     closed with an explanation.
#   * An absent destination is RESERVED with an exclusive mkdir. On failure the
#     partial reservation is LEFT IN PLACE for inspection; only the private
#     staging directory is removed, and only while provably still this call's.
#   * Prints nothing on success; failures go to stderr. Returns nonzero on
#     failure.
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

	if ! ( cd "$_proj_abs" && git rev-parse --is-inside-work-tree ) >/dev/null 2>&1; then
		printf '[export-smoke] FAIL: %s is not a Git working tree; a frozen candidate cannot be built from it\n' "$_proj_abs" >&2
		return 1
	fi
	# A subdirectory archives only its own subtree in current Git while the
	# report claims the root tree; refuse instead of producing a misleading
	# partial candidate.
	_toplevel="$(cd "$_proj_abs" && git rev-parse --show-toplevel 2>/dev/null)" || {
		printf '[export-smoke] FAIL: could not resolve the repository root of %s\n' "$_proj_abs" >&2
		return 1
	}
	_toplevel="$(cd "$_toplevel" && pwd -P 2>/dev/null)" || {
		printf '[export-smoke] FAIL: cannot resolve repository root: %s\n' "$_toplevel" >&2
		return 1
	}
	if [ "$_toplevel" != "$_proj_abs" ]; then
		printf '[export-smoke] FAIL: project dir is a repository subdirectory, not its root (%s); refusing to archive a subtree\n' "$_toplevel" >&2
		return 1
	fi

	# Pin an immutable revision before reserving or writing anything.
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

	# Advisory occupancy report; the exclusive mkdir below is authoritative.
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
		if [ -n "$_stage" ]; then
			printf '[export-smoke] NOTE: private staging retained (not deleted): %s\n' "$_stage" >&2
		fi
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
	es_run_exclusive "$_proj_abs" "$_archive" "$_err" -- git archive --format=tar "$_archive_rev"
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		printf '[export-smoke] FAIL: git archive %s failed in %s (exit %s)\n' "$_archive_rev" "$_proj_abs" "$_rc" >&2
		sed -n '1,5p' "$_err" 2>/dev/null | sed 's/^/[export-smoke]   /' >&2
		_es_cleanup_stage "$_stage" "$_stage_ids"
		_note_left
		return 1
	fi

	# Stage 2a: reject unsafe archive content BEFORE extraction. Only regular
	# files and directories are accepted; symlinks, hard links, devices and
	# fifos could otherwise make later writes escape the private root.
	if ! es_validate_archive "$_archive" "$_stage"; then
		_es_cleanup_stage "$_stage" "$_stage_ids"
		_note_left
		return 1
	fi

	if ! _es_reservation_ok "$_snap_abs" "$_res_ids"; then
		printf '[export-smoke] FAIL: the reserved snapshot dir was replaced concurrently: %s\n' "$_snap_abs" >&2
		_es_cleanup_stage "$_stage" "$_stage_ids"
		return 1
	fi

	# Stage 2b: extract and overlay with the reservation held as cwd.
	if ! es_build_reserved "$_snap_abs" "$_res_ids" "$_archive" "$_err" "$_stage" "$_proj_abs"; then
		_es_cleanup_stage "$_stage" "$_stage_ids"
		_note_left
		return 1
	fi

	if ! _es_reservation_ok "$_snap_abs" "$_res_ids"; then
		printf '[export-smoke] FAIL: the reserved snapshot dir was replaced concurrently: %s\n' "$_snap_abs" >&2
		_es_cleanup_stage "$_stage" "$_stage_ids"
		return 1
	fi

	# Stage 3: evidence bound to the exact bytes. The archive digest comes
	# from the file that was extracted; the presets digest from the copied
	# temp file. Neither re-reads a live path.
	if [ -n "$_digest_file" ]; then
		_digest="$(es_sha256 "$_archive")" || _digest=""
		_pdigest="$(cat "$_stage/presets.sha256" 2>/dev/null)"
		if ! es_is_hex_sha256 "$_digest" || ! es_is_hex_sha256 "$_pdigest"; then
			printf '[export-smoke] FAIL: could not compute valid SHA-256 evidence\n' >&2
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
		if ! _es_create_exclusive "$_digest_file" "$(printf 'archive_sha256=%s\npresets_sha256=%s' "$_digest" "$_pdigest")"; then
			printf '[export-smoke] FAIL: could not create the archive digest file exclusively: %s (exists or parent unwritable)\n' "$_digest_file" >&2
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
	_es_cleanup_stage "$_stage" "$_stage_ids"
	return 0
}
