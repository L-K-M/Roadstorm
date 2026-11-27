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

# Staging directories are intentionally retained (never recursively deleted
# through a mutable pathname); expect exactly one per helper run.
assert_stage_retained() { # <parent-dir> <description>
	_n="$(find "$1" -maxdepth 1 -type d -name '.candidate-snapshot.stage.*' 2>/dev/null | wc -l | tr -d ' ')"
	if [ "$_n" = "1" ]; then ok "$2"; else bad "$2 (expected 1 retained staging dir, got $_n)"; fi
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
: >"$REPO_EMPTYGD/export_presets.cfg"
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
assert_absent "untracked file excluded" "$SNAP1/src/extra.txt"
assert_absent ".git excluded from candidate" "$SNAP1/.git"
assert_stage_retained "$OUT1" "success retains one private staging dir for inspection"
_stage_dir="$(find "$OUT1" -maxdepth 1 -type d -name '.candidate-snapshot.stage.*' 2>/dev/null | head -n 1)"
assert_exists "retained staging holds the archived candidate" "$_stage_dir/candidate.tar"

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
_out="$( ( hash -r 2>/dev/null || :; export PATH="$FAKEBIN:$PATH"; es_make_frozen_snapshot "$REPO" "$FA_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "injected archive failure fails closed" "$_rc"
assert_contains "archive-stage failure named" "$_out" "git archive HEAD failed"
assert_contains "git stderr surfaced" "$_out" "injected archive failure"
assert_real_dir "failed archive leaves the reservation for inspection" "$FA_SNAP"
assert_absent "failed archive publishes no project.godot" "$FA_SNAP/project.godot"
assert_contains "partial-output note reported (archive)" "$_out" "left in place"
assert_stage_retained "$FA_OUT" "archive failure retains one private staging dir"
assert_file_eq "sibling sentinel preserved across archive failure" "sibling-keep" "$FA_OUT/sibling.txt"

OCC_FA="$WORK/occupied-fakearchive"
mkdir -p "$OCC_FA"
printf 'keep-occ\n' >"$OCC_FA/sentinel.txt"
_out="$( ( hash -r 2>/dev/null || :; export PATH="$FAKEBIN:$PATH"; es_make_frozen_snapshot "$REPO" "$OCC_FA" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "occupied destination still refused with failing archive" "$_rc"
assert_contains "occupancy checked before archive" "$_out" "already exists"
assert_file_eq "occupied sentinel preserved across archive failure" "keep-occ" "$OCC_FA/sentinel.txt"

# --- 7. injected extraction failure -----------------------------------------
EX_OUT="$WORK/out-faketar"
EX_SNAP="$EX_OUT/candidate-snapshot"
_out="$( ( hash -r 2>/dev/null || :; export PATH="$FAKETAR:$PATH"; es_make_frozen_snapshot "$REPO" "$EX_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "injected extraction failure fails closed" "$_rc"
assert_contains "extraction-stage failure named" "$_out" "extracting the frozen archive failed"
assert_real_dir "failed extraction leaves the reservation for inspection" "$EX_SNAP"
assert_absent "failed extraction publishes no project.godot" "$EX_SNAP/project.godot"
assert_contains "partial-output note reported (extraction)" "$_out" "left in place"
assert_stage_retained "$EX_OUT" "extraction failure retains one private staging dir"

# --- 8. archive without a usable project.godot ------------------------------
NG_OUT="$WORK/out-nogodot"
NG_SNAP="$NG_OUT/candidate-snapshot"
_out="$( ( es_make_frozen_snapshot "$REPO_NOGODOT" "$NG_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "archive without project.godot fails closed" "$_rc"
assert_contains "missing project.godot reported" "$_out" "no usable project.godot"
assert_real_dir "missing project.godot leaves the reservation for inspection" "$NG_SNAP"
assert_contains "partial-output note reported (no project.godot)" "$_out" "left in place"

EG_OUT="$WORK/out-emptygd"
EG_SNAP="$EG_OUT/candidate-snapshot"
_out="$( ( es_make_frozen_snapshot "$REPO_EMPTYGD" "$EG_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "archive with empty project.godot fails closed" "$_rc"
assert_contains "empty project.godot reported" "$_out" "no usable project.godot"
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
_out="$( ( hash -r 2>/dev/null || :; export PATH="$FAKETAR:$PATH"; es_make_frozen_snapshot "$REPO" "$RETRY_SNAP" ) 2>&1 )"; _rc=$?
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
_stages_before="$(find "$OUT1" -maxdepth 1 -type d -name '.candidate-snapshot.stage.*' 2>/dev/null | wc -l | tr -d ' ')"
_out="$( ( es_make_frozen_snapshot "$REPO" "$SNAP1" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "second publish into an occupied destination refuses" "$_rc"
assert_contains "rerun refusal explained" "$_out" "already exists as a directory"
assert_file_eq "first snapshot still intact after refusal" "tracked" "$SNAP1/src/main.gd"
_stages_after="$(find "$OUT1" -maxdepth 1 -type d -name '.candidate-snapshot.stage.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "pre-staging refusal creates no new staging dir" "$_stages_before" "$_stages_after"

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
assert_contains "digest file records the archive digest" "$(cat "$DIG_FILE")" "archive_sha256=$_expected_digest"
_exp_pre="$(es_sha256 "$REPO/export_presets.cfg")"
assert_contains "digest file records the copied presets digest" "$(cat "$DIG_FILE")" "presets_sha256=$_exp_pre"
assert_eq "digest is 64 characters" "64" "${#_expected_digest}"

DIGX_OUT="$WORK/out-digest-exist"
mkdir -p "$DIGX_OUT"
printf 'keep-digest\n' >"$DIGX_OUT/archive.sha256"
_out="$( ( es_make_frozen_snapshot "$REPO" "$DIGX_OUT/candidate-snapshot" "$DIGX_OUT/archive.sha256" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "pre-existing digest destination refused" "$_rc"
assert_contains "digest no-clobber reason reported" "$_out" "already exists"
assert_file_eq "pre-existing digest destination untouched" "keep-digest" "$DIGX_OUT/archive.sha256"
assert_real_dir "failed digest call leaves its reservation for inspection" "$DIGX_OUT/candidate-snapshot"

# A dangling symlink at the digest destination must also be refused untouched.
DIGL_OUT="$WORK/out-digest-dangling"
mkdir -p "$DIGL_OUT"
ln -s "$WORK/nowhere-digest-target" "$DIGL_OUT/archive.sha256"
_out="$( ( es_make_frozen_snapshot "$REPO" "$DIGL_OUT/candidate-snapshot" "$DIGL_OUT/archive.sha256" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "dangling digest destination refused" "$_rc"
assert_contains "dangling digest refusal reported" "$_out" "already exists"
if [ -L "$DIGL_OUT/archive.sha256" ]; then ok "dangling digest symlink left in place"; else bad "dangling digest symlink was replaced"; fi
assert_absent "digest symlink target not created" "$WORK/nowhere-digest-target"

# Exclusive-create semantics: the final path is opened once with O_EXCL and
# written through that held descriptor; there is no temp pathname to swap.
XC_OUT="$WORK/out-exclusive"
mkdir -p "$XC_OUT"
XC_SENT="$WORK/exclusive-sentinel.txt"
printf 'sentinel-keep\n' >"$XC_SENT"
ln -s "$XC_SENT" "$XC_OUT/dangling"
if _es_create_exclusive "$XC_OUT/dangling" "new-bytes"; then bad "dangling symlink destination accepted"; else ok "dangling symlink destination refused"; fi
assert_file_eq "dangling destination target untouched" "sentinel-keep" "$XC_SENT"
printf 'original\n' >"$XC_OUT/existing"
if _es_create_exclusive "$XC_OUT/existing" "new-bytes"; then bad "existing destination overwritten"; else ok "existing destination refused"; fi
assert_file_eq "existing destination not truncated" "original" "$XC_OUT/existing"
if _es_create_exclusive "$XC_OUT/new" "payload"; then ok "atomic exclusive create succeeds"; else bad "atomic exclusive create failed"; fi
assert_file_eq "atomic create wrote exact bytes" "payload" "$XC_OUT/new"
_xc_tmps="$(find "$XC_OUT" -maxdepth 1 -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "exclusive create leaves no temp files" "0" "$_xc_tmps"

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
assert_contains "digest records original-commit archive bytes" "$(cat "$META_DIGEST")" "archive_sha256=$(es_sha256 "$WORK/meta-expected.tar")"
( cd "$META_REPO" && git show "$META_C1:export_presets.cfg" ) >"$WORK/meta-presets-expected.txt" 2>/dev/null
assert_contains "digest records original-commit presets bytes" "$(cat "$META_DIGEST")" "presets_sha256=$(es_sha256 "$WORK/meta-presets-expected.txt")"
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
# Mirror what the runner will resolve with PROJECT_DIR=$REPO (fixture has no
# tools/toolchain/pin/engine.txt, so this is the fallback constant).
PINNED="$(es_pinned_version "$REPO")"
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
assert_exists "private digest evidence retained in the output" "$RF_OUT/.candidate-snapshot.archive-sha256"
_exp_pre_live="$(es_sha256 "$REPO/export_presets.cfg")"
assert_contains "retained evidence still records both digests" "$(cat "$RF_OUT/.candidate-snapshot.archive-sha256")" "presets_sha256=$_exp_pre_live"
_rep_live_match="$(sed -n 's/^presets_live_matches_commit=//p' "$RREP" | head -n 1)"
assert_eq "runner reports live presets match commit" "true" "$_rep_live_match"
_rep_src="$(sed -n 's/^presets_source=//p' "$RREP" | head -n 1)"
assert_eq "runner reports commit-bound presets source" "head-commit" "$_rep_src"

# --- 18. Sol adversarial repros ---------------------------------------------
# (a) An archive-provided symlink must be rejected before extraction.
ADV_REPO="$WORK/adv-symlink-repo"
make_tiny_repo "$ADV_REPO" yes || { printf 'fixture repo failed\n' >&2; exit 2; }
EXT_SENT="$WORK/external-presets-sentinel.txt"
printf 'external-keep\n' >"$EXT_SENT"
rm -f "$ADV_REPO/export_presets.cfg"
ln -s "$EXT_SENT" "$ADV_REPO/export_presets.cfg"
(
	cd "$ADV_REPO" &&
	git add -A &&
	git -c commit.gpgsign=false commit -qm adv-symlink
) || { printf 'fixture commit failed\n' >&2; exit 2; }
_out="$( ( es_make_frozen_snapshot "$ADV_REPO" "$WORK/out-adv-symlink/candidate-snapshot" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "archive-provided symlink fails closed" "$_rc"
assert_contains "unsafe archive entry type reported" "$_out" "unsafe archive entry type"
assert_file_eq "external sentinel untouched by archived symlink" "external-keep" "$EXT_SENT"

# (b) The presets digest binds to the copied bytes: after the snapshot is
# built, changing the live preset source must not alter the recorded digest.
TAMPER_REPO="$WORK/tamper-repo"
make_tiny_repo "$TAMPER_REPO" yes || { printf 'fixture repo failed\n' >&2; exit 2; }
ORIG_PRE_SHA="$(es_sha256 "$TAMPER_REPO/export_presets.cfg")"
T_SNAP="$WORK/out-tamper/candidate-snapshot"
T_DIGEST="$WORK/out-tamper/archive.sha256"
_out="$( ( es_make_frozen_snapshot "$TAMPER_REPO" "$T_SNAP" "$T_DIGEST" ) 2>&1 )"; _rc=$?
assert_rc_zero "snapshot build succeeds for the presets binding control" "$_rc"
printf '# changed after snapshot\n' >>"$TAMPER_REPO/export_presets.cfg"
LATER_PRE_SHA="$(es_sha256 "$TAMPER_REPO/export_presets.cfg")"
assert_contains "recorded presets digest still matches the copied bytes" "$(cat "$T_DIGEST")" "presets_sha256=$ORIG_PRE_SHA"
if [ "$ORIG_PRE_SHA" != "$LATER_PRE_SHA" ]; then
	ok "live preset source changed after the snapshot"
else
	bad "fixture did not change the live preset source"
fi

# (c) Replacing the reserved destination with a symlink just before tar must
# not redirect extraction into the external directory.
VICTIM="$WORK/victim-dir"
mkdir -p "$VICTIM"
printf 'victim-keep\n' >"$VICTIM/sentinel.txt"
SWAP_BACKUP="$WORK/reservation-backup"
FAKETARSWAP_DIR="$WORK/fake-tar-swap-bin"
mkdir -p "$FAKETARSWAP_DIR"
cat >"$FAKETARSWAP_DIR/tar" <<EOF
#!/bin/sh
if [ "\$1" = "-x" ]; then
	_d="\$PWD"
	cd /
	mv "\$_d" "$SWAP_BACKUP" 2>/dev/null || { rm -rf "$SWAP_BACKUP"; mv "\$_d" "$SWAP_BACKUP"; }
	ln -s "$VICTIM" "\$_d"
	cd "$SWAP_BACKUP"
fi
exec "$_REAL_TAR" "\$@"
EOF
chmod +x "$FAKETARSWAP_DIR/tar"
SWAP_SNAP="$WORK/out-swap/candidate-snapshot"
_out="$( ( hash -r 2>/dev/null || :; export PATH="$FAKETARSWAP_DIR:$PATH"; es_make_frozen_snapshot "$REPO" "$SWAP_SNAP" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "destination swap before tar fails closed" "$_rc"
assert_contains "concurrent replacement reported" "$_out" "replaced concurrently"
assert_file_eq "victim sentinel untouched" "victim-keep" "$VICTIM/sentinel.txt"
assert_absent "extraction did not write through the swapped symlink" "$VICTIM/project.godot"
assert_real_dir "extraction landed in the held reservation inode" "$SWAP_BACKUP"
assert_stage_retained "$WORK/out-swap" "destination swap retains one private staging dir"

# (d) Swap BEFORE the held-directory cd: es_build_reserved must detect the
# replacement at the process cwd and write nothing into the victim.
PRE_BASE="$WORK/out-preswap"
mkdir -p "$PRE_BASE"
PRE_DEST="$PRE_BASE/candidate-snapshot"
mkdir -p "$PRE_DEST"
PRE_IDS="$(_es_path_ids "$PRE_DEST")" || { printf 'cannot identify pre-swap fixture\n' >&2; exit 2; }
PRE_VICTIM="$WORK/preswap-victim"
mkdir -p "$PRE_VICTIM"
printf 'preswap-victim-keep\n' >"$PRE_VICTIM/sentinel.txt"
PRE_BACKUP="$WORK/preswap-backup"
mv "$PRE_DEST" "$PRE_BACKUP"
ln -s "$PRE_VICTIM" "$PRE_DEST"
( cd "$REPO" && git archive --format=tar HEAD ) >"$WORK/preswap.tar" 2>/dev/null
( cd "$REPO" && git show HEAD:export_presets.cfg ) >"$WORK/preswap-presrc.txt" 2>/dev/null
mkdir -p "$WORK/preswap-stage"
_out="$( es_build_reserved "$PRE_DEST" "$PRE_IDS" "$WORK/preswap.tar" "$WORK/preswap-stage" "$REPO" "$WORK/preswap-presrc.txt" 2>&1 )"; _rc=$?
assert_rc_nonzero "swap before cd refused before any write" "$_rc"
assert_contains "cwd identity rejection reported" "$_out" "replaced before it was entered"
assert_file_eq "pre-cd victim sentinel untouched" "preswap-victim-keep" "$PRE_VICTIM/sentinel.txt"
assert_absent "nothing written through the pre-cd symlink" "$PRE_VICTIM/project.godot"
_victim_entries="$(find "$PRE_VICTIM" -mindepth 1 | wc -l | tr -d ' ')"
assert_eq "victim directory still holds only its sentinel" "1" "$_victim_entries"

# Valid flow through the held-directory builder.
OKB_DEST="$WORK/out-heldok/candidate-snapshot"
mkdir -p "$OKB_DEST"
OKB_IDS="$(_es_path_ids "$OKB_DEST")" || { printf 'cannot identify held fixture\n' >&2; exit 2; }
mkdir -p "$WORK/heldok-stage"
_out="$( es_build_reserved "$OKB_DEST" "$OKB_IDS" "$WORK/preswap.tar" "$WORK/heldok-stage" "$REPO" "$WORK/preswap-presrc.txt" 2>&1 )"; _rc=$?
assert_rc_zero "held-directory build succeeds" "$_rc"
assert_exists "held build extracted project.godot" "$OKB_DEST/project.godot"
assert_file_eq "held build overlaid presets" "preset-tiny" "$OKB_DEST/export_presets.cfg"

# (e) Archive classification: only regular files/directories inside the root.
_vi=0
_val_work() { _vi=$((_vi + 1)); VAL_WORK="$WORK/classifier-work-$_vi"; mkdir -p "$VAL_WORK"; }
_val_work
V_OK="$WORK/val-ok"
mkdir -p "$V_OK/src"
printf 'hi\n' >"$V_OK/src/f.txt"
printf 'top\n' >"$V_OK/top.txt"
tar -cf "$WORK/val-ok.tar" -C "$V_OK" . 2>/dev/null
_val_work
_out="$( es_validate_archive "$WORK/val-ok.tar" "$VAL_WORK" 2>&1 )"; _rc=$?
assert_rc_zero "classifier accepts a regular-file/dir archive" "$_rc"
V_LINK="$WORK/val-link"
mkdir -p "$V_LINK"
printf 'x\n' >"$V_LINK/f.txt"
ln -s /etc/passwd "$V_LINK/link"
tar -cf "$WORK/val-link.tar" -C "$V_LINK" . 2>/dev/null
_val_work
_out="$( es_validate_archive "$WORK/val-link.tar" "$VAL_WORK" 2>&1 )"; _rc=$?
assert_rc_nonzero "classifier rejects a symlink member" "$_rc"
assert_contains "symlink type reason reported" "$_out" "unsafe archive entry type"
V_HARD="$WORK/val-hard"
mkdir -p "$V_HARD"
printf 'x\n' >"$V_HARD/a"
ln "$V_HARD/a" "$V_HARD/b"
tar -cf "$WORK/val-hard.tar" -C "$V_HARD" . 2>/dev/null
_val_work
_out="$( es_validate_archive "$WORK/val-hard.tar" "$VAL_WORK" 2>&1 )"; _rc=$?
assert_rc_nonzero "classifier rejects a hard-link member" "$_rc"
assert_contains "hard-link type reason reported" "$_out" "unsafe archive entry type"
V_TRAV="$WORK/val-trav"
mkdir -p "$V_TRAV/sub"
printf 'evil\n' >"$V_TRAV/evil.txt"
( cd "$V_TRAV/sub" && tar -cf "$WORK/val-trav.tar" ../evil.txt 2>/dev/null )
_val_work
_out="$( es_validate_archive "$WORK/val-trav.tar" "$VAL_WORK" 2>&1 )"; _rc=$?
assert_rc_nonzero "classifier rejects upward traversal" "$_rc"
assert_contains "traversal path reason reported" "$_out" "unsafe archive path"
if tar -Pcf "$WORK/val-abs.tar" -C / "$V_OK/top.txt" 2>/dev/null || tar --absolute-names -cf "$WORK/val-abs.tar" -C / "$V_OK/top.txt" 2>/dev/null; then
	_val_work
_out="$( es_validate_archive "$WORK/val-abs.tar" "$VAL_WORK" 2>&1 )"; _rc=$?
	assert_rc_nonzero "classifier rejects an absolute path" "$_rc"
	assert_contains "absolute path reason reported" "$_out" "unsafe archive path"
else
	printf 'note absolute-name archive creation unsupported here; skipped\n'
fi

# --- 19. project root, default output, diagnostics --------------------------
# A repository subdirectory must be refused rather than archived as a subtree.
_out="$( ( es_make_frozen_snapshot "$REPO/src" "$WORK/out-subdir/candidate-snapshot" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "repository subdirectory refused" "$_rc"
assert_contains "subdirectory reason reported" "$_out" "subdirectory"
assert_absent "subdirectory attempt publishes nothing" "$WORK/out-subdir/candidate-snapshot"

# Without --out, repeated runs each reserve a unique fresh directory.
DEF_BASE="$REPO/work/agents/export-smoke/outputs"
_out="$( PROJECT_DIR="$REPO" GODOT_BIN="$FAKEGODOT_DIR/godot" sh "$RUNNER" --platform Linux 2>&1 )"; _rc=$?
assert_eq "first default-output run reaches the export stage (rc 1)" "1" "$_rc"
_out="$( PROJECT_DIR="$REPO" GODOT_BIN="$FAKEGODOT_DIR/godot" sh "$RUNNER" --platform Linux 2>&1 )"; _rc=$?
assert_eq "second default-output run still runs (rc 1)" "1" "$_rc"
_def_runs="$(find "$DEF_BASE" -mindepth 1 -maxdepth 1 -type d -name 'run.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "two unique default output directories reserved" "2" "$_def_runs"
_def_reports="$(find "$DEF_BASE" -mindepth 2 -maxdepth 2 -name export-smoke-report.txt 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "both default runs wrote reports" "2" "$_def_reports"

# An explicit --out that now exists is still refused untouched.
printf 'default-base-keep\n' >"$DEF_BASE/base-sentinel.txt"
_out="$( PROJECT_DIR="$REPO" GODOT_BIN="$FAKEGODOT_DIR/godot" sh "$RUNNER" --platform Linux --out "$DEF_BASE" 2>&1 )"; _rc=$?
assert_rc_nonzero "explicit existing --out refused after default runs" "$_rc"
assert_contains "explicit refusal names the existing destination" "$_out" "already exists"
assert_file_eq "default output base sentinel untouched" "default-base-keep" "$DEF_BASE/base-sentinel.txt"

# Distinct diagnostics for creation failures vs an occupied destination.
RO_PARENT="$WORK/ro-parent"
mkdir -p "$RO_PARENT"
chmod 0555 "$RO_PARENT"
if [ "$(id -u 2>/dev/null || printf '0')" -eq 0 ]; then
	printf 'note permission-diagnostic control skipped (running as root)\n'
else
	_out="$( PROJECT_DIR="$REPO" GODOT_BIN="$FAKEGODOT_DIR/godot" sh "$RUNNER" --platform Linux --out "$RO_PARENT/no/out" 2>&1 )"; _rc=$?
	assert_rc_nonzero "uncreatable parent fails closed" "$_rc"
	case "$_out" in
	*"already exists"*) bad "uncreatable parent misreported as already exists" ;;
	*) ok "uncreatable parent not reported as already exists" ;;
	esac
	assert_contains "uncreatable parent diagnostic" "$_out" "cannot create output parent"
	_out="$( PROJECT_DIR="$REPO" GODOT_BIN="$FAKEGODOT_DIR/godot" sh "$RUNNER" --platform Linux --out "$RO_PARENT/out" 2>&1 )"; _rc=$?
	assert_rc_nonzero "uncreatable leaf fails closed" "$_rc"
	case "$_out" in
	*"already exists"*) bad "uncreatable leaf misreported as already exists" ;;
	*) ok "uncreatable leaf not reported as already exists" ;;
	esac
	assert_contains "uncreatable leaf diagnostic" "$_out" "cannot create output dir"
fi
chmod 0755 "$RO_PARENT"

# --- 20. no recursive deletion through a mutable pathname -------------------
# A cleanup call whose pathname was swapped for a foreign directory must leave
# that directory untouched (the function never deletes).
SW_STAGE="$WORK/sw-stage"
mkdir -p "$SW_STAGE"
printf 'stage-own-bytes\n' >"$SW_STAGE/candidate.tar"
SW_IDS="$(_es_path_ids "$SW_STAGE")" || { printf 'cannot identify stage fixture\n' >&2; exit 2; }
SW_FOREIGN="$WORK/sw-foreign"
mkdir -p "$SW_FOREIGN/sub"
printf 'foreign-keep\n' >"$SW_FOREIGN/sub/keep.txt"
mv "$SW_STAGE" "$WORK/sw-stage-backup"
ln -s "$SW_FOREIGN" "$SW_STAGE"
_es_cleanup_stage "$SW_STAGE" "$SW_IDS"
assert_file_eq "foreign tree at swapped stage path untouched" "foreign-keep" "$SW_FOREIGN/sub/keep.txt"
assert_absent "cleanup wrote nothing through the swapped path" "$SW_FOREIGN/candidate.tar"

# Failure paths must not invoke rm at all.
FAKERM_DIR="$WORK/fake-rm-bin"
mkdir -p "$FAKERM_DIR"
REAL_RM="$(command -v rm)"
cat >"$FAKERM_DIR/rm" <<EOF
#!/bin/sh
printf 'RM-CALLED\n' >> "$WORK/rm-marker"
exec "$REAL_RM" "\$@"
EOF
chmod +x "$FAKERM_DIR/rm"
NORM_OUT="$WORK/out-normorm"
_out="$( ( hash -r 2>/dev/null || :; export PATH="$FAKERM_DIR:$FAKETAR:$PATH"; es_make_frozen_snapshot "$REPO" "$NORM_OUT/candidate-snapshot" ) 2>&1 )"; _rc=$?
assert_rc_nonzero "failure path under rm shim still fails closed" "$_rc"
assert_absent "no rm invocation during snapshot failure handling" "$WORK/rm-marker"
assert_stage_retained "$NORM_OUT" "failure under rm shim retains its staging dir"

# --- 21. commit-bound presets, bounded capture, validated source copy -------
# (a) The live preset file differs from HEAD: the COMMITTED bytes are built.
LP_REPO="$WORK/live-preset-repo"
make_tiny_repo "$LP_REPO" yes || { printf 'fixture repo failed\n' >&2; exit 2; }
( cd "$LP_REPO" && git show HEAD:export_presets.cfg ) >"$WORK/lp-committed.txt" 2>/dev/null
LP_COMMITTED_SHA="$(es_sha256 "$WORK/lp-committed.txt")"
printf 'preset-LIVE-uncommitted\n' >"$LP_REPO/export_presets.cfg"
LP_LIVE_SHA="$(es_sha256 "$LP_REPO/export_presets.cfg")"
LP_C1_SHA="$(es_resolve_head "$LP_REPO")"
if [ "$LP_COMMITTED_SHA" != "$LP_LIVE_SHA" ]; then ok "fixture has live presets differing from HEAD"; else bad "fixture presets do not differ"; fi
LP_OUT="$WORK/out-live-preset"
LP_SNAP="$LP_OUT/candidate-snapshot"
LP_DIG="$LP_OUT/archive.sha256"
_out="$( es_make_frozen_snapshot "$LP_REPO" "$LP_SNAP" "$LP_DIG" 2>&1 )"; _rc=$?
assert_rc_zero "snapshot builds from committed presets when live differs" "$_rc"
assert_file_eq "candidate presets are the committed bytes" "preset-tiny" "$LP_SNAP/export_presets.cfg"
assert_contains "recorded presets digest is the committed-bytes digest" "$(cat "$LP_DIG")" "presets_sha256=$LP_COMMITTED_SHA"

# Runner-level diagnostic with a live preset differing from HEAD.
LP_RUN_OUT="$WORK/out-live-preset-runner"
_out="$( PROJECT_DIR="$LP_REPO" GODOT_BIN="$FAKEGODOT_DIR/godot" sh "$RUNNER" --platform Linux --out "$LP_RUN_OUT" 2>&1 )"; _rc=$?
assert_eq "live-preset runner still reaches the export stage (rc 1)" "1" "$_rc"
LP_REP="$LP_RUN_OUT/export-smoke-report.txt"
assert_exists "live-preset runner wrote a report" "$LP_REP"
assert_contains "runner warns about differing live presets" "$_out" "differs from $LP_C1_SHA:export_presets.cfg"
LP_MATCH="$(sed -n 's/^presets_live_matches_commit=//p' "$LP_REP" | head -n 1)"
assert_eq "runner reports live presets differ" "false" "$LP_MATCH"
LP_SRC="$(sed -n 's/^presets_source=//p' "$LP_REP" | head -n 1)"
assert_eq "runner reports commit-bound presets source" "head-commit" "$LP_SRC"
LP_ARCH="$(sed -n 's/^archive_sha256=//p' "$LP_REP" | head -n 1)"
LP_SHA="$(es_resolve_head "$LP_REPO")"
( cd "$LP_REPO" && git archive --format=tar "$LP_SHA" ) >"$WORK/lp-runner-expected.tar" 2>/dev/null
assert_eq "runner archive digest binds the exact commit" "$(es_sha256 "$WORK/lp-runner-expected.tar")" "$LP_ARCH"

# (b) >=1 MiB on stderr must not deadlock; direct descriptors and bounded run.
BIG="$WORK/out-bigrun"
mkdir -p "$BIG"
_bt0="$(date +%s)"
( export ES_EXCLUSIVE_TIMEOUT=5; es_run_exclusive . "$BIG/out.bin" "$BIG/err.bin" -- sh -c 'printf ok; head -c 1048576 /dev/zero >&2' ) 2>/dev/null; _brc=$?
_bt1="$(date +%s)"
assert_rc_zero "1 MiB stderr capture succeeds" "$_brc"
assert_file_eq "stdout captured exactly" "ok" "$BIG/out.bin"
_errsz="$(wc -c <"$BIG/err.bin" | tr -d ' ')"
assert_eq "full 1 MiB stderr captured" "1048576" "$_errsz"
if [ $((_bt1 - _bt0)) -le 5 ]; then ok "large capture stayed within its bound"; else bad "large capture exceeded its bound"; fi

# (c) A FIFO source is refused without blocking and creates no destination.
FIFO_SRC="$WORK/copy-fifo-src"
mkfifo "$FIFO_SRC"
FIFO_OUT="$WORK/out-fifo"
mkdir -p "$FIFO_OUT"
_ft0="$(date +%s)"
( export ES_EXCLUSIVE_TIMEOUT=3; _es_copy_exclusive "$FIFO_SRC" "$FIFO_OUT/dst" "$FIFO_OUT/err" ) 2>/dev/null; _frc=$?
_ft1="$(date +%s)"
assert_rc_nonzero "FIFO source refused" "$_frc"
assert_absent "no destination created from a FIFO" "$FIFO_OUT/dst"
if [ -p "$FIFO_SRC" ]; then ok "FIFO left intact"; else bad "FIFO was consumed or removed"; fi
if [ $((_ft1 - _ft0)) -le 3 ]; then ok "FIFO refusal stayed within its bound"; else bad "FIFO open exceeded its bound"; fi
assert_contains "non-regular source reason recorded" "$(cat "$FIFO_OUT/err" 2>/dev/null)" "not a regular file"

# (d) A symlinked source is refused without following it.
SL_TARGET="$WORK/link-src-target.txt"
printf 'target-keep\n' >"$SL_TARGET"
ln -s "$SL_TARGET" "$WORK/link-src"
_es_copy_exclusive "$WORK/link-src" "$FIFO_OUT/dst2" "$FIFO_OUT/err2" 2>/dev/null; _src=$?
assert_rc_nonzero "symlink source refused" "$_src"
assert_file_eq "symlink target untouched" "target-keep" "$SL_TARGET"
assert_absent "no destination created through a symlink source" "$FIFO_OUT/dst2"

printf '[export-smoke-tests] summary pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
	printf '%s\n' "$FAILURE_LIST"
	exit 1
fi
exit 0
