#!/bin/sh
# Focused regressions for tools/export_smoke/lib/common.sh, especially the
# frozen-snapshot builder (PLAN.md M0.4/M0.5).
#
# Hermetic: no network, no engine, no display, and no mutation of any shared
# repository. Every fixture lives in one private temporary work dir that is
# removed on exit. The tiny Git repository is a throwaway `git init` inside
# that work dir; no branch, worktree or clone is created anywhere else. The
# injected failing `git`/`tar` are private scripts earlier on PATH.
#
# Run:
#   sh tools/export_smoke/tests/test_common.sh
#   EXPORT_SMOKE_TEST_WORK=/private/scratch sh tools/export_smoke/tests/test_common.sh
#
# Exit: 0 = every assertion passed, 1 = at least one failed, 2 = harness error.
# Original project code under the Unlicense.

set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMON="$TESTS_DIR/../lib/common.sh"
[ -f "$COMMON" ] || { printf 'missing %s\n' "$COMMON" >&2; exit 2; }
# shellcheck source=../lib/common.sh
. "$COMMON"

# Scratch layout: EXPORT_SMOKE_TEST_WORK, when set, is an existing PARENT that
# the caller owns. The suite creates a fresh unique mktemp directory INSIDE it
# and removes only that child. It never deletes or modifies the parent, its
# pre-existing entries, or any sibling.
PARENT="${EXPORT_SMOKE_TEST_WORK:-}"
if [ -n "$PARENT" ]; then
	if [ ! -d "$PARENT" ] || [ -L "$PARENT" ] || [ ! -w "$PARENT" ]; then
		printf 'EXPORT_SMOKE_TEST_WORK is not a usable scratch parent: %s\n' "$PARENT" >&2
		exit 2
	fi
	PARENT="$(cd "$PARENT" && pwd -P)"
fi

# Names of the caller's pre-existing parent entries, captured BEFORE the
# suite creates anything. Compared again at the end (excluding this run's own
# private child) to prove the parent and its contents were preserved.
_parent_names() { # <dir> <skip-name>
	_pn_dir="$1"; _pn_skip="$2"
	(
		cd "$_pn_dir" || exit 1
		for _pn_e in * .[!.]* ..?*; do
			[ -e "$_pn_e" ] || continue
			[ "$_pn_e" = "$_pn_skip" ] && continue
			printf '%s\n' "$_pn_e"
		done
	) | sort | tr '\n' ','
}
if [ -n "$PARENT" ]; then
	PARENT_BEFORE="$(_parent_names "$PARENT" "")"
else
	PARENT_BEFORE=""
fi

# Create the unique private child INSIDE the caller's parent (or TMPDIR).
if [ -n "$PARENT" ]; then
	WORK="$(mktemp -d "$PARENT/roadstorm-export-smoke-tests.XXXXXX" 2>/dev/null)" || {
		printf 'cannot create a private work dir inside %s\n' "$PARENT" >&2
		exit 2
	}
else
	WORK="$(mktemp -d "${TMPDIR:-/tmp}/roadstorm-export-smoke-tests.XXXXXX" 2>/dev/null)" || {
		printf 'cannot create a private work dir\n' >&2
		exit 2
	}
fi
WORK="$(cd "$WORK" && pwd -P)"
_work_ids="$(_es_path_ids "$WORK")" || {
	printf 'cannot identify the private work dir %s\n' "$WORK" >&2
	exit 2
}

# Remove ONLY the exact private child this suite created (unique mktemp name),
# and only while it is still that same non-symlink directory.
_exit_cleanup() {
	if [ ! -L "$WORK" ] && [ -d "$WORK" ]; then
		_now="$(_es_path_ids "$WORK")" || _now=""
		if [ "$_now" = "$_work_ids" ]; then
			rm -rf "$WORK"
		fi
	fi
}
trap '_exit_cleanup' EXIT
trap 'exit 130' INT TERM HUP

_REAL_GIT="$(command -v git)"
_REAL_TAR="$(command -v tar)"
[ -n "$_REAL_GIT" ] && [ -n "$_REAL_TAR" ] || { printf 'git and tar are required\n' >&2; exit 2; }
if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then
	printf 'a SHA-256 utility (shasum, sha256sum or openssl) is required\n' >&2
	exit 2
fi

PASS=0
FAIL=0
FAILURE_LIST=""

ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() {
	FAIL=$((FAIL + 1))
	FAILURE_LIST="$FAILURE_LIST
  - $1"
	printf 'FAIL %s\n' "$1"
}
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi; }
assert_rc_zero() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1 (expected rc 0, got $2)"; fi; }
assert_rc_nonzero() { if [ "$2" -ne 0 ]; then ok "$1"; else bad "$1 (expected nonzero rc, got 0)"; fi; }
assert_contains() {
	case "$2" in
	*"$3"*) ok "$1" ;;
	*) bad "$1 (missing [$3] in [$2])" ;;
	esac
}
assert_exists() { if [ -e "$2" ]; then ok "$1"; else bad "$1 (missing $2)"; fi; }
assert_absent() { if [ ! -e "$2" ]; then ok "$1"; else bad "$1 (unexpected $2)"; fi; }
assert_real_dir() { if [ -d "$2" ] && [ ! -L "$2" ]; then ok "$1"; else bad "$1 (not a real directory: $2)"; fi; }
assert_file_eq() {
	_want="$2"; _path="$3"
	_got="$(cat "$_path" 2>/dev/null)"
	if [ "$_want" = "$_got" ]; then ok "$1"; else bad "$1 (expected [$_want], got [$_got])"; fi
}

make_tiny_repo() { # <dir> [with-project-godot: yes|no]
	_d="$1"; _with_gd="${2:-yes}"
	mkdir -p "$_d/src" "$_d/docs" || return 1
	if [ "$_with_gd" = "yes" ]; then
		printf '[application]\nconfig/name="Tiny"\n' >"$_d/project.godot" || return 1
	fi
	printf 'preset-tiny\n' >"$_d/export_presets.cfg" || return 1
	printf 'tracked\n' >"$_d/src/main.gd" || return 1
	printf 'tracked-doc\n' >"$_d/docs/note.txt" || return 1
	(
		cd "$_d" &&
		git init -q &&
		git config user.email test@example.invalid &&
		git config user.name Test &&
		git add -A &&
		git -c commit.gpgsign=false commit -qm tiny
	) || return 1
	return 0
}

REPO="$WORK/repo-ok"
make_tiny_repo "$REPO" yes || { printf 'fixture repo failed\n' >&2; exit 2; }
# A dirty tracked file and an untracked file must not enter the frozen candidate.
printf 'dirty\n' >>"$REPO/src/main.gd"
printf 'uncommitted\n' >"$REPO/src/extra.txt"

REPO_NOGODOT="$WORK/repo-nogodot"
make_tiny_repo "$REPO_NOGODOT" no || { printf 'fixture repo failed\n' >&2; exit 2; }

REPO_EMPTYGD="$WORK/repo-emptygd"
mkdir -p "$REPO_EMPTYGD" || exit 2
: >"$REPO_EMPTYGD/project.godot"
(
	cd "$REPO_EMPTYGD" &&
	git init -q &&
	git config user.email test@example.invalid &&
	git config user.name Test &&
	git add -A &&
	git -c commit.gpgsign=false commit -qm empty
) || { printf 'fixture repo failed\n' >&2; exit 2; }

NOGIT="$WORK/no-repo/fixture"
mkdir -p "$NOGIT"
printf 'preset-nogit\n' >"$NOGIT/export_presets.cfg"

# Private PATH shims: delegate everything except the deliberately broken stage.
FAKEBIN="$WORK/fake-bin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/git" <<EOF
#!/bin/sh
if [ "\$1" = "archive" ]; then
	echo "fatal: injected archive failure" >&2
	exit 1
fi
exec "$_REAL_GIT" "\$@"
EOF
chmod +x "$FAKEBIN/git"

FAKETAR="$WORK/fake-tar-bin"
mkdir -p "$FAKETAR"
cat >"$FAKETAR/tar" <<EOF
#!/bin/sh
if [ "\$1" = "-x" ]; then
	echo "injected extraction failure" >&2
	exit 1
fi
exec "$_REAL_TAR" "\$@"
EOF
chmod +x "$FAKETAR/tar"

# --- 1. valid archive into an absent destination -----------------------------
OUT1="$WORK/out-absent"
SNAP1="$OUT1/candidate-snapshot"
_out="$( ( es_make_frozen_snapshot "$REPO" "$SNAP1" ) 2>&1 )"; _rc=$?
assert_rc_zero "valid archive publishes into an absent destination" "$_rc"
assert_eq "success prints nothing" "" "$_out"
assert_real_dir "published snapshot is a real directory" "$SNAP1"
assert_contains "committed project.godot extracted" "$(cat "$SNAP1/project.godot" 2>/dev/null)" 'config/name="Tiny"'
assert_file_eq "committed tracked file extracted" "tracked" "$SNAP1/src/main.gd"
assert_file_eq "committed doc extracted" "tracked-doc" "$SNAP1/docs/note.txt"
assert_file_eq "owned presets overlaid" "preset-tiny" "$SNAP1/export_presets.cfg"
assert_absent "dirty tracked content excluded" "$SNAP1/src/main.gd.dirty"
assert_absent "untracked file excluded" "$SNAP1/src/extra.txt"
assert_absent ".git excluded from candidate" "$SNAP1/.git"
_leftovers="$(find "$OUT1" -maxdepth 1 -name '.candidate-snapshot.stage.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "no private staging leftovers after success" "0" "$_leftovers"

# --- 2. pre-existing nonempty directory: refuse, preserve --------------------
OCC="$WORK/occupied-dir"
mkdir -p "$OCC/sub"
printf 'keep\n' >"$OCC/sentinel.txt"
printf 'deep\n' >"$OCC/sub/deep.txt"
_before="$(cd "$OCC" && find . -type f | sort | tr '\n' ',')"
_out="$( ( es_make_frozen_snapshot "$REPO" "$OCC" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "existing nonempty directory refused" "$_rc"
assert_contains "occupied-directory reason reported" "$_out" "already exists as a directory"
assert_file_eq "occupied sentinel untouched" "keep" "$OCC/sentinel.txt"
assert_file_eq "occupied nested sentinel untouched" "deep" "$OCC/sub/deep.txt"
_after="$(cd "$OCC" && find . -type f | sort | tr '\n' ',')"
assert_eq "occupied directory contents unchanged" "$_before" "$_after"

# --- 3. pre-existing regular file: refuse, preserve --------------------------
FILE_DEST="$WORK/occupied-file"
printf 'precious\n' >"$FILE_DEST"
_out="$( ( es_make_frozen_snapshot "$REPO" "$FILE_DEST" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "existing file refused" "$_rc"
assert_contains "occupied-file reason reported" "$_out" "already exists as a file"
assert_file_eq "existing file untouched" "precious" "$FILE_DEST"

# --- 4. dangling symlink: refuse, never followed -----------------------------
DANG="$WORK/dangling-link"
ln -s "$WORK/no-such-target" "$DANG"
_out="$( ( es_make_frozen_snapshot "$REPO" "$DANG" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "dangling symlink refused" "$_rc"
assert_contains "symlink reason reported" "$_out" "exists as a symlink"
if [ -L "$DANG" ]; then ok "dangling symlink left in place"; else bad "dangling symlink was removed"; fi
assert_absent "dangling symlink target not created" "$WORK/no-such-target"

# --- 5. symlink to a directory: refuse, target untouched ---------------------
SYMTARGET="$WORK/symlink-target"
mkdir -p "$SYMTARGET"
printf 'target-keep\n' >"$SYMTARGET/keep.txt"
SYMLINKDEST="$WORK/symlink-dir"
ln -s "$SYMTARGET" "$SYMLINKDEST"
_out="$( ( es_make_frozen_snapshot "$REPO" "$SYMLINKDEST" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "directory symlink refused" "$_rc"
assert_contains "directory symlink reason reported" "$_out" "exists as a symlink"
assert_file_eq "symlink target sentinel untouched" "target-keep" "$SYMTARGET/keep.txt"
_tc="$(find "$SYMTARGET" -type f | wc -l | tr -d ' ')"
assert_eq "nothing written through the symlink" "1" "$_tc"

# --- 6. injected archive failure with a successful tar -----------------------
MASKT="$WORK/mask-target"
mkdir -p "$MASKT"
( cd "$REPO" && PATH="$FAKEBIN:$PATH" git archive --format=tar HEAD ) >"$WORK/mask.tar" 2>/dev/null
_arch_rc=$?
assert_rc_nonzero "injected git archive fails on its own" "$_arch_rc"
tar -x -f "$WORK/mask.tar" -C "$MASKT" >/dev/null 2>&1
_tar_alone=$?
( cd "$REPO" && PATH="$FAKEBIN:$PATH" git archive --format=tar HEAD ) | tar -x -C "$MASKT" >/dev/null 2>&1
_pipe_rc=$?
assert_eq "old pipeline reports tar status, hiding the archive failure" "$_tar_alone" "$_pipe_rc"

FA_OUT="$WORK/out-fakearchive"
mkdir -p "$FA_OUT"
printf 'sibling-keep\n' >"$FA_OUT/sibling.txt"
FA_SNAP="$FA_OUT/candidate-snapshot"
_out="$( ( export PATH="$FAKEBIN:$PATH"; es_make_frozen_snapshot "$REPO" "$FA_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "injected archive failure fails closed" "$_rc"
assert_contains "archive-stage failure named" "$_out" "git archive HEAD failed"
assert_contains "git stderr surfaced" "$_out" "injected archive failure"
assert_real_dir "failed archive leaves the reservation for inspection" "$FA_SNAP"
assert_absent "failed archive publishes no project.godot" "$FA_SNAP/project.godot"
assert_contains "partial-output note reported (archive)" "$_out" "left in place"
_leftovers="$(find "$FA_OUT" -maxdepth 1 -name '.candidate-snapshot.stage.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "no staging leftover after archive failure" "0" "$_leftovers"
assert_file_eq "sibling sentinel preserved across archive failure" "sibling-keep" "$FA_OUT/sibling.txt"

OCC_FA="$WORK/occupied-fakearchive"
mkdir -p "$OCC_FA"
printf 'keep-occ\n' >"$OCC_FA/sentinel.txt"
_out="$( ( export PATH="$FAKEBIN:$PATH"; es_make_frozen_snapshot "$REPO" "$OCC_FA" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "occupied destination still refused with failing archive" "$_rc"
assert_contains "occupancy checked before archive" "$_out" "already exists"
assert_file_eq "occupied sentinel preserved across archive failure" "keep-occ" "$OCC_FA/sentinel.txt"

# --- 7. injected extraction failure -----------------------------------------
EX_OUT="$WORK/out-faketar"
EX_SNAP="$EX_OUT/candidate-snapshot"
_out="$( ( export PATH="$FAKETAR:$PATH"; es_make_frozen_snapshot "$REPO" "$EX_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "injected extraction failure fails closed" "$_rc"
assert_contains "extraction-stage failure named" "$_out" "extracting the frozen archive failed"
assert_real_dir "failed extraction leaves the reservation for inspection" "$EX_SNAP"
assert_absent "failed extraction publishes no project.godot" "$EX_SNAP/project.godot"
assert_contains "partial-output note reported (extraction)" "$_out" "left in place"
_leftovers="$(find "$EX_OUT" -maxdepth 1 -name '.candidate-snapshot.stage.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "no staging leftover after extraction failure" "0" "$_leftovers"

# --- 8. archive without a usable project.godot ------------------------------
NG_OUT="$WORK/out-nogodot"
NG_SNAP="$NG_OUT/candidate-snapshot"
_out="$( ( es_make_frozen_snapshot "$REPO_NOGODOT" "$NG_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "archive without project.godot fails closed" "$_rc"
assert_contains "missing project.godot reported" "$_out" "has no project.godot"
assert_real_dir "missing project.godot leaves the reservation for inspection" "$NG_SNAP"
assert_contains "partial-output note reported (no project.godot)" "$_out" "left in place"

EG_OUT="$WORK/out-emptygd"
EG_SNAP="$EG_OUT/candidate-snapshot"
_out="$( ( es_make_frozen_snapshot "$REPO_EMPTYGD" "$EG_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "archive with empty project.godot fails closed" "$_rc"
assert_contains "empty project.godot reported" "$_out" "empty project.godot"
assert_real_dir "empty project.godot leaves the reservation for inspection" "$EG_SNAP"
assert_contains "partial-output note reported (empty project.godot)" "$_out" "left in place"

# --- 9. non-Git source: prompt, accurate rejection ---------------------------
# GIT_CEILING_DIRECTORIES keeps the enclosing checkout from being discovered,
# so this fixture really is outside any Git repository.
NGIT_OUT="$WORK/out-nogit"
NGIT_SNAP="$NGIT_OUT/candidate-snapshot"
_out="$( ( export GIT_CEILING_DIRECTORIES="$WORK/no-repo"; es_make_frozen_snapshot "$NOGIT" "$NGIT_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "non-Git source fails closed" "$_rc"
assert_contains "non-Git reason reported accurately" "$_out" "not a Git working tree"
assert_absent "non-Git source publishes nothing" "$NGIT_SNAP"

# --- 10. argument guards -----------------------------------------------------
_out="$( ( es_make_frozen_snapshot "$WORK/does-not-exist" "$WORK/out-missing/snap" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "missing project dir fails closed" "$_rc"
assert_contains "missing project dir reported" "$_out" "project dir not found"
_out="$( ( es_make_frozen_snapshot "$REPO" "$REPO" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "destination equal to project dir refused" "$_rc"
assert_contains "same-path refusal reported" "$_out" "must differ"
assert_file_eq "project dir not replaced" "preset-tiny" "$REPO/export_presets.cfg"
assert_exists "project working tree untouched" "$REPO/src/extra.txt"

# --- 11. cleanup lets a later attempt use the same absent destination --------
RETRY_OUT="$WORK/out-retry"
RETRY_SNAP="$RETRY_OUT/candidate-snapshot"
_out="$( ( export PATH="$FAKETAR:$PATH"; es_make_frozen_snapshot "$REPO" "$RETRY_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "first attempt fails" "$_rc"
assert_real_dir "failed attempt leaves the reservation behind" "$RETRY_SNAP"
assert_absent "failed attempt left no packaged candidate" "$RETRY_SNAP/project.godot"
_out="$( ( es_make_frozen_snapshot "$REPO" "$RETRY_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "retry into the failed reservation refuses" "$_rc"
assert_contains "retry refusal is occupancy" "$_out" "already exists as a directory"
RETRY2_SNAP="$WORK/out-retry2/candidate-snapshot"
_out="$( ( es_make_frozen_snapshot "$REPO" "$RETRY2_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_zero "a fresh destination succeeds after the failure" "$_rc"
assert_exists "fresh destination published project.godot" "$RETRY2_SNAP/project.godot"

# --- 12. a published destination is never overwritten ------------------------
_out="$( ( es_make_frozen_snapshot "$REPO" "$SNAP1" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "second publish into an occupied destination refuses" "$_rc"
assert_contains "rerun refusal explained" "$_out" "already exists as a directory"
assert_file_eq "first snapshot still intact after refusal" "tracked" "$SNAP1/src/main.gd"
_leftovers="$(find "$OUT1" -maxdepth 1 -name '.candidate-snapshot.stage.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "no staging leftover after refusal" "0" "$_leftovers"

# --- 13. caller-supplied scratch parent preserved ---------------------------
if [ -n "$PARENT" ]; then
	assert_real_dir "caller scratch parent survives the suite" "$PARENT"
	_parent_after="$(_parent_names "$PARENT" "$(basename "$WORK")")"
	assert_eq "preexisting parent entries untouched by the suite" "$PARENT_BEFORE" "$_parent_after"
else
	printf 'note no EXPORT_SMOKE_TEST_WORK parent supplied; parent preservation not exercised\n'
fi

# --- 14. archive digest evidence -------------------------------------------
DIG_OUT="$WORK/out-digest"
DIG_SNAP="$DIG_OUT/candidate-snapshot"
DIG_FILE="$DIG_OUT/archive.sha256"
_out="$( ( es_make_frozen_snapshot "$REPO" "$DIG_SNAP" "$DIG_FILE" ) 2>&1 )"; _rc=$?
assert_rc_zero "snapshot build with digest evidence succeeds" "$_rc"
( cd "$REPO" && git archive --format=tar HEAD ) >"$WORK/expected-archive.tar" 2>/dev/null
_expected_digest="$(es_sha256 "$WORK/expected-archive.tar")"
assert_file_eq "digest file binds to the exact archived bytes" "$_expected_digest" "$DIG_FILE"
assert_eq "digest is 64 characters" "64" "${#_expected_digest}"

DIGX_OUT="$WORK/out-digest-exist"
mkdir -p "$DIGX_OUT"
printf 'keep-digest\n' >"$DIGX_OUT/archive.sha256"
_out="$( ( es_make_frozen_snapshot "$REPO" "$DIGX_OUT/candidate-snapshot" "$DIGX_OUT/archive.sha256" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "pre-existing digest destination refused" "$_rc"
assert_contains "digest no-clobber reason reported" "$_out" "already exists"
assert_file_eq "pre-existing digest destination untouched" "keep-digest" "$DIGX_OUT/archive.sha256"
assert_real_dir "failed digest call leaves its reservation for inspection" "$DIGX_OUT/candidate-snapshot"

# --- 15. digest validator accepts only 64 lowercase hex --------------------
GOOD_SHA="$_expected_digest"
es_is_hex_sha256 "$GOOD_SHA"; assert_eq "valid 64-hex digest accepted" "0" "$?"
_z64=""; _i=0; while [ "$_i" -lt 64 ]; do _z64="${_z64}z"; _i=$((_i + 1)); done
es_is_hex_sha256 "$_z64"; assert_eq "injected 64-char non-hex digest rejected" "1" "$?"
_a63=""; _i=0; while [ "$_i" -lt 63 ]; do _a63="${_a63}a"; _i=$((_i + 1)); done
es_is_hex_sha256 "$_a63"; assert_eq "short digest rejected" "1" "$?"
_A64=""; _i=0; while [ "$_i" -lt 64 ]; do _A64="${_A64}A"; _i=$((_i + 1)); done
es_is_hex_sha256 "$_A64"; assert_eq "uppercase digest rejected (lowercase policy)" "1" "$?"
es_is_hex_sha256 ""; assert_eq "empty digest rejected" "1" "$?"
es_is_commit_sha ""; assert_eq "commit validator rejects empty value" "1" "$?"
_c40=""; _i=0; while [ "$_i" -lt 40 ]; do _c40="${_c40}a"; _i=$((_i + 1)); done
es_is_commit_sha "$_c40"; assert_eq "valid 40-char commit SHA accepted" "0" "$?"
_c40z=""; _i=0; while [ "$_i" -lt 40 ]; do _c40z="${_c40z}z"; _i=$((_i + 1)); done
es_is_commit_sha "$_c40z"; assert_eq "non-hex 40-char commit SHA rejected" "1" "$?"

# --- 16. archive, SHA and tree stay bound to one immutable commit -----------
META_REPO="$WORK/meta-repo"
make_tiny_repo "$META_REPO" yes || { printf 'fixture repo failed\n' >&2; exit 2; }
META_C1="$(es_resolve_head "$META_REPO")"
assert_eq "resolved HEAD is a 40-char SHA" "40" "${#META_C1}"
META_C1_TREE="$(cd "$META_REPO" && git rev-parse --verify --quiet "$META_C1^{tree}")"
assert_eq "tree of C1 is a 40-char SHA" "40" "${#META_C1_TREE}"

# Move HEAD after resolution: modify tracked content and add a new file.
printf 'tracked-v2\n' >"$META_REPO/src/main.gd"
printf 'v2-only\n' >"$META_REPO/src/v2.txt"
(
	cd "$META_REPO" &&
	git add -A &&
	git -c commit.gpgsign=false commit -qm two
) || { printf 'fixture follow-up commit failed\n' >&2; exit 2; }
META_HEAD2="$(es_resolve_head "$META_REPO")"
if [ "$META_C1" != "$META_HEAD2" ]; then ok "fixture HEAD moved after resolution"; else bad "fixture HEAD did not move"; fi

# Archive the ORIGINAL SHA, then derive metadata from that SHA afterwards.
META_SNAP="$WORK/out-meta/candidate-snapshot"
META_DIGEST="$WORK/out-meta/archive.sha256"
_out="$( ( es_make_frozen_snapshot "$META_REPO" "$META_SNAP" "$META_DIGEST" "$META_C1" ) 2>&1 )"; _rc=$?
assert_rc_zero "archive pinned to the original commit succeeds" "$_rc"
assert_file_eq "snapshot content comes from the original commit" "tracked" "$META_SNAP/src/main.gd"
assert_absent "file added by the second commit excluded" "$META_SNAP/src/v2.txt"
( cd "$META_REPO" && git archive --format=tar "$META_C1" ) >"$WORK/meta-expected.tar" 2>/dev/null
assert_file_eq "digest equals sha256(git archive <original SHA>)" "$(es_sha256 "$WORK/meta-expected.tar")" "$META_DIGEST"
META_C1_TREE_AFTER="$(cd "$META_REPO" && git rev-parse --verify --quiet "$META_C1^{tree}")"
assert_eq "tree derived from the original SHA after archiving" "$META_C1_TREE" "$META_C1_TREE_AFTER"

_n40="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
_out="$( ( es_make_frozen_snapshot "$META_REPO" "$WORK/out-badrev-hex/candidate-snapshot" "" "$_z64" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "non-hex 40-char revision rejected" "$_rc"
assert_contains "revision format reason reported" "$_out" "40 lowercase hex"
_out="$( ( es_make_frozen_snapshot "$META_REPO" "$WORK/out-badrev-short/candidate-snapshot" "" "deadbeef" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "short revision rejected" "$_rc"
_out="$( ( es_make_frozen_snapshot "$META_REPO" "$WORK/out-badrev-missing/candidate-snapshot" "" "$_n40" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "well-formed but unknown revision rejected" "$_rc"
assert_contains "unknown revision reason reported" "$_out" "does not resolve"
assert_absent "rejected revisions reserve nothing" "$WORK/out-badrev-hex/candidate-snapshot"

# --- 17. runner preserves a pre-existing output tree -------------------------
RUNNER="$TESTS_DIR/../run_export_smoke.sh"
[ -f "$RUNNER" ] || { printf 'missing %s\n' "$RUNNER" >&2; exit 2; }
PINNED="$(sed -n 's/^version_string=//p' "$TESTS_DIR/../../toolchain/pin/engine.txt" 2>/dev/null | head -n 1)"
[ -n "$PINNED" ] || PINNED="4.7.2.stable.official.ed1daf0bf"
FAKEGODOT_DIR="$WORK/fake-godot-bin"
mkdir -p "$FAKEGODOT_DIR"
cat >"$FAKEGODOT_DIR/godot" <<EOF
#!/bin/sh
if [ "\$1" = "--version" ]; then printf '%s\\n' "$PINNED"; exit 0; fi
exit 1
EOF
chmod +x "$FAKEGODOT_DIR/godot"
ROUT="$WORK/runner-out"
mkdir -p "$ROUT"
printf 'report-keep\n' >"$ROUT/export-smoke-report.txt"
printf 'sums-keep\n' >"$ROUT/SHA256SUMS.txt"
printf 'package-keep\n' >"$ROUT/Roadstorm-Linux-x86_64"
printf 'pck-keep\n' >"$ROUT/Roadstorm-Linux-x86_64.pck"
printf 'log-keep\n' >"$ROUT/export-Linux.log"
printf 'link-target-keep\n' >"$WORK/runner-link-sentinel.txt"
ln -s "$WORK/runner-link-sentinel.txt" "$ROUT/output-link"
_runner_before="$(cd "$ROUT" && find . -mindepth 1 | sort | tr '\n' ',')"
_out="$( GODOT_BIN="$FAKEGODOT_DIR/godot" sh "$RUNNER" --platform Linux --out "$ROUT" 2>&1 )"; _rc=$?
assert_rc_nonzero "runner refuses a pre-existing output directory" "$_rc"
assert_contains "runner refusal names preservation" "$_out" "already exists"
assert_absent "runner created no candidate-snapshot" "$ROUT/candidate-snapshot"
assert_absent "runner wrote no archive digest" "$ROUT/.candidate-snapshot.archive-sha256"
assert_file_eq "existing report untouched" "report-keep" "$ROUT/export-smoke-report.txt"
assert_file_eq "existing SHA256SUMS untouched" "sums-keep" "$ROUT/SHA256SUMS.txt"
assert_file_eq "existing package untouched" "package-keep" "$ROUT/Roadstorm-Linux-x86_64"
assert_file_eq "existing pack untouched" "pck-keep" "$ROUT/Roadstorm-Linux-x86_64.pck"
assert_file_eq "existing log untouched" "log-keep" "$ROUT/export-Linux.log"
if [ -L "$ROUT/output-link" ]; then ok "existing symlink left as a symlink"; else bad "existing symlink was replaced"; fi
assert_file_eq "symlink still resolves to its target" "link-target-keep" "$ROUT/output-link"
_runner_after="$(cd "$ROUT" && find . -mindepth 1 | sort | tr '\n' ',')"
assert_eq "output tree contents unchanged" "$_runner_before" "$_runner_after"

# A fresh output dir is reserved and the report must bind to one SHA even
# when the engine export fails (the fake godot exits 1).
RF_OUT="$WORK/runner-fresh-out"
RUN_SHA="$(es_resolve_head "$REPO")"
assert_eq "runner fixture HEAD resolved" "40" "${#RUN_SHA}"
_out="$( PROJECT_DIR="$REPO" GODOT_BIN="$FAKEGODOT_DIR/godot" sh "$RUNNER" --platform Linux --out "$RF_OUT" 2>&1 )"; _rc=$?
assert_eq "failed export makes the runner exit 1" "1" "$_rc"
RREP="$RF_OUT/export-smoke-report.txt"
assert_exists "report written before the export attempt" "$RREP"
_rep_sha="$(sed -n 's/^head_commit=//p' "$RREP" | head -n 1)"
assert_eq "report source commit = resolved SHA" "$RUN_SHA" "$_rep_sha"
_rep_tree="$(sed -n 's/^head_tree=//p' "$RREP" | head -n 1)"
_exp_tree="$(cd "$REPO" && git rev-parse --verify --quiet "$RUN_SHA^{tree}")"
assert_eq "report tree = tree(resolved SHA)" "$_exp_tree" "$_rep_tree"
_rep_arch="$(sed -n 's/^archive_sha256=//p' "$RREP" | head -n 1)"
( cd "$REPO" && git archive --format=tar "$RUN_SHA" ) >"$WORK/report-expected.tar" 2>/dev/null
assert_eq "report archive digest = sha256(git archive <resolved SHA>)" "$(es_sha256 "$WORK/report-expected.tar")" "$_rep_arch"
_rep_cand="$(sed -n 's/^candidate_digest=//p' "$RREP" | head -n 1)"
printf '%s\n%s\n' "$_rep_arch" "$(es_sha256 "$REPO/export_presets.cfg")" >"$WORK/cand-input.txt"
assert_eq "report candidate digest consistent" "$(es_sha256 "$WORK/cand-input.txt")" "$_rep_cand"
assert_absent "private digest evidence cleaned up" "$RF_OUT/.candidate-snapshot.archive-sha256"

printf '[export-smoke-tests] summary pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
	printf '%s\n' "$FAILURE_LIST"
	exit 1
fi
exit 0
