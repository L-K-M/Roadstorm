#!/bin/sh
# Roadstorm Racer! - export smoke build runner (PLAN.md M0.4/M0.5, M9, T16).
# Ownership: tools/export_smoke/** (PLAN.md "How agents execute the plan").
#
# Builds native smoke packages for the three committed desktop targets
# (docs/TECHNICAL_DESIGN.md "Packaging and operations") from a FROZEN, ISOLATED
# source candidate and - for macOS only - launches the package.
#
# WHAT THIS PROVES AND WHAT IT DOES NOT
#   * The source candidate is a frozen snapshot: `git archive <one resolved
#     commit SHA>` plus ONLY the owned export_presets.cfg. No concurrent
#     uncommitted file enters it, and HEAD is never re-read after resolution.
#   * A successful cross-export is NOT a platform launch. Windows and Linux
#     packages are produced but NOT launched (no target host); an untested
#     platform never becomes verified through a successful export (M0/M9.2).
#   * The macOS package is launched here (the only host available). No
#     Developer ID/notarization credentials exist; any signature or launch
#     claim is made only from the observed evidence fields the launch test
#     prints, never assumed from the probe name.
#   * This is an M0 smoke build of a placeholder shell. It is NOT final M0, NOT
#     gameplay, and NOT a verified release package.
#
# PACKAGING CHECKS (Opus recheck 4803d848 findings E3 and E4)
#   E3 - every produced package component is checksummed, including the .pck
#        (sidecar for Windows/Linux, embedded in the .app for macOS). For Linux
#        the main binary is the untouched pinned stock template, so its digest
#        says nothing about the game content; the .pck carries all of it.
#   E4 - the presets exclude development-only tooling (tools/, fixtures/,
#        schemas/, docs/, plan/, review/, work/, .github/, tests/, *.py, *.sh,
#        assets/manifest.json) while leaving every runtime dependency in.
#        tools/export_smoke/lib/pack_inventory.py re-reads the res:// tree inside
#        each produced .pck and FAILS the run if a development-only path is
#        packaged, if a required runtime resource is missing, or if any pack
#        entry's MD-5 does not match the bytes stored for it. The exclusion is
#        therefore VERIFIED, not assumed.
#   What packaging does NOT verify: that the package launches on its target OS
#   (only macOS is launched, and only as this tool launches it), the code
#   signature/notarization chain, gameplay or final M0 content, and the M9
#   release notices (licenses/ and provenance/ are not packed today because
#   Godot packs only recognised resource types).
#
# Usage:
#   run_export_smoke.sh [--out <dir>] [--platform macOS|Windows|Linux]...
#                       [--diagnostic-enable-etc2-astc]
#                       [--launch-probe headless|full]
#                       [--export-timeout N] [--launch-timeout N]
#   Repeat --platform to choose a subset; default is all three.
#
#   --out <dir>
#       The output directory must NOT already exist (not as a directory, file
#       or symlink, dangling or not): it is reserved with an exclusive mkdir
#       and every pre-existing path is preserved. Without --out, a unique
#       fresh directory is created per invocation under
#       <project>/work/agents/export-smoke/outputs/, so repeated runs never
#       touch an earlier run's outputs. All reports, logs and packages are
#       created inside that reserved directory; existing files there are
#       never truncated or replaced.
#
#   --launch-timeout N
#       Seconds the headless launch may run before being terminated
#       (default 120). The flag is passed through to the launch test; an
#       overrun fails the launch rather than hanging the smoke run.
#
#   --diagnostic-enable-etc2-astc
#       DIAGNOSTIC ONLY, off by default. Patches the SNAPSHOT copy of
#       project.godot to set rendering/textures/vram_compression/import_etc2_astc
#       =true so the arm64/universal macOS export is permitted. The tracked
#       project.godot is NEVER modified. This flag exists only to prove that
#       the macOS preset is otherwise correct and that the package launches;
#       without it, the frozen candidate's macOS export is BLOCKED by that
#       project setting, which is owned outside this tool.
#
#   --launch-probe headless|full
#       How far the macOS launch test goes. "headless" (the default) runs the
#       .app executable with --headless, which validates the ad-hoc code
#       signature on exec and boots the shell to the menu, and opens no window.
#       "full" additionally runs the GUI for a few seconds and takes a
#       screenshot, which proves the render path. Nothing this tool launches is
#       left running.
#
# Outputs (in --out): export-<platform>.log, export-smoke-report.txt,
#   package-inventory-<platform>.txt and .json (every component's SHA-256 and
#   the full res:// tree of the pack), SHA256SUMS.txt (every component; macOS
#   .app paths are relative to the extracted bundle, so `shasum -c` only checks
#   top-level artifacts), and the macOS launch logs. Exclusive files are opened
#   once with O_CREAT|O_EXCL and written through that descriptor; no output is
#   truncated or recursively deleted after creation. Private staging
#   (.candidate-snapshot.stage.*) and the evidence/digest inputs are retained
#   for inspection (see README "Failure evidence and cleanup").
#
# Environment: GODOT_BIN, OUT_DIR. NO_COLOR.
# Exit codes: 0 = every requested platform exported (and macOS launched),
#             1 = a requested platform was blocked/failed,
#             2 = the tool could not run.
# Original project code under the Unlicense.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

PROJECT_DIR="${PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PINNED_VERSION_STRING="$(es_pinned_version "$PROJECT_DIR")"

OUT_DIR="${OUT_DIR:-}"
PLATFORMS=""
DIAG_ETC2=0
LAUNCH_PROBE="headless"
EXPORT_TIMEOUT=120
LAUNCH_TIMEOUT=120
PACK_INVENTORY="$SCRIPT_DIR/lib/pack_inventory.py"

log()  { printf '[export-smoke] %s
' "$*"; }
warn() { printf '[export-smoke] WARN: %s\n' "$*" >&2; }
die()  { c="$1"; shift; printf '[export-smoke] FAIL: %s\n' "$*" >&2; exit "$c"; }

while [ $# -gt 0 ]; do
	case "$1" in
	--out) [ $# -ge 2 ] || die 2 "--out needs a directory"; OUT_DIR="$2"; shift 2 ;;
	--out=*) OUT_DIR="${1#--out=}"; shift ;;
	--platform) [ $# -ge 2 ] || die 2 "--platform needs macOS|Windows|Linux"; PLATFORMS="$PLATFORMS $2"; shift 2 ;;
	--platform=*) PLATFORMS="$PLATFORMS ${1#--platform=}"; shift ;;
	--diagnostic-enable-etc2-astc) DIAG_ETC2=1; shift ;;
	--launch-probe) [ $# -ge 2 ] || die 2 "--launch-probe needs headless|full"; LAUNCH_PROBE="$2"; shift 2 ;;
	--launch-probe=*) LAUNCH_PROBE="${1#--launch-probe=}"; shift ;;
	--export-timeout) [ $# -ge 2 ] || die 2 "--export-timeout needs seconds"; EXPORT_TIMEOUT="$2"; shift 2 ;;
	--export-timeout=*) EXPORT_TIMEOUT="${1#--export-timeout=}"; shift ;;
	--launch-timeout) [ $# -ge 2 ] || die 2 "--launch-timeout needs seconds"; LAUNCH_TIMEOUT="$2"; shift 2 ;;
	--launch-timeout=*) LAUNCH_TIMEOUT="${1#--launch-timeout=}"; shift ;;
	-h|--help) sed -n '2,75p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) die 2 "unknown argument: $1" ;;
	esac
done

case "$LAUNCH_PROBE" in
headless|full) : ;;
*) die 2 "--launch-probe needs headless|full, got '$LAUNCH_PROBE'" ;;
esac
[ -f "$PACK_INVENTORY" ] || die 2 "missing $PACK_INVENTORY"

[ -n "$PLATFORMS" ] || PLATFORMS="macOS Windows Linux"
# Validate every requested platform and de-duplicate deterministically (first
# occurrence wins) BEFORE the engine is discovered or any output is reserved.
_VALID_PLATFORMS=""
for _p in $PLATFORMS; do
	case "$_p" in
	macOS|Windows|Linux) : ;;
	*) die 2 "unknown --platform value '$_p' (expected macOS|Windows|Linux)" ;;
	esac
	case " $_VALID_PLATFORMS " in
	*" $_p "*) : ;;
	*) _VALID_PLATFORMS="$_VALID_PLATFORMS $_p" ;;
	esac
done
PLATFORMS="$_VALID_PLATFORMS"
unset _p

# --- engine -----------------------------------------------------------------
GODOT_BIN="$(es_default_godot)" || die 2 "no Godot binary found; set GODOT_BIN"
[ -x "$GODOT_BIN" ] || [ "$GODOT_BIN" = "godot" ] || die 2 "'$GODOT_BIN' is not executable"
_ver="$("$GODOT_BIN" --version 2>/dev/null)" || _ver=""
[ -n "$_ver" ] || die 2 "could not run '$GODOT_BIN --version'"
if [ "$_ver" != "$PINNED_VERSION_STRING" ]; then
	die 2 "engine is '$_ver', not the pinned '$PINNED_VERSION_STRING'"
fi
log "engine: $GODOT_BIN ($_ver) matches pin"

# --- immutable source -------------------------------------------------------
# Resolve ONE commit SHA now and use it for the archive, the tree and every
# later claim. HEAD is never looked up again, so a concurrent commit while the
# exports run cannot desynchronize the archived bytes from the reported SHA.
SRC_SHA="$(es_resolve_head "$PROJECT_DIR")" || die 2 "could not resolve an immutable HEAD commit in $PROJECT_DIR"
SRC_TREE="$(cd "$PROJECT_DIR" && git rev-parse --verify --quiet "$SRC_SHA^{tree}")" || die 2 "could not derive the tree of $SRC_SHA"
es_is_commit_sha "$SRC_TREE" || die 2 "tree of $SRC_SHA is not a full SHA: '$SRC_TREE'"
log "candidate source commit: $SRC_SHA"
log "candidate source tree:   $SRC_TREE"

# --- output dir -------------------------------------------------------------
# Preserve EVERY existing user path.
#   * Explicit --out: the exact directory must be ABSENT. It is reserved with
#     an exclusive mkdir; any pre-existing directory/file/symlink (including a
#     dangling one) is refused before anything is written, truncated or
#     followed.
#   * No --out: reserve a UNIQUE fresh directory per invocation under
#     work/agents/export-smoke/outputs/, so ordinary repeated runs never touch
#     a previous run's outputs.
if [ -n "$OUT_DIR" ]; then
	while [ "$OUT_DIR" != "/" ] && [ "${OUT_DIR%/}" != "$OUT_DIR" ]; do
		OUT_DIR="${OUT_DIR%/}"
	done
	_out_parent="$(dirname "$OUT_DIR")"
	_out_base="$(basename "$OUT_DIR")"
	case "$_out_base" in
	""|"."|"..") die 2 "invalid output dir: $OUT_DIR" ;;
	esac
	if ! mkdir -p "$_out_parent" 2>/dev/null; then
		die 2 "cannot create output parent (file in the way or permission denied): $_out_parent"
	fi
	if ! _out_parent="$(cd "$_out_parent" && pwd -P)"; then
		die 2 "cannot resolve output parent: $_out_parent"
	fi
	if [ -e "$_out_parent/$_out_base" ] || [ -L "$_out_parent/$_out_base" ]; then
		die 2 "output destination already exists; refusing to overwrite or truncate any existing path: $_out_parent/$_out_base (choose a fresh --out)"
	fi
	if ! mkdir "$_out_parent/$_out_base" 2>/dev/null; then
		if [ -e "$_out_parent/$_out_base" ] || [ -L "$_out_parent/$_out_base" ]; then
			die 2 "output destination appeared; refusing to overwrite it: $_out_parent/$_out_base"
		fi
		die 2 "cannot create output dir (permission denied or invalid name): $_out_parent/$_out_base"
	fi
	OUT_DIR="$_out_parent/$_out_base"
else
	_def_base="$PROJECT_DIR/work/agents/export-smoke/outputs"
	if [ -L "$_def_base" ]; then
		die 2 "refusing to follow a symlink at the default output base: $_def_base"
	fi
	if [ -e "$_def_base" ] && [ ! -d "$_def_base" ]; then
		die 2 "default output base is not a directory: $_def_base"
	fi
	mkdir -p "$_def_base" 2>/dev/null || die 2 "cannot create the default output base (permission denied): $_def_base"
	_def_base="$(cd "$_def_base" && pwd -P)" || die 2 "cannot resolve the default output base: $_def_base"
	OUT_DIR="$(mktemp -d "$_def_base/run.XXXXXX" 2>/dev/null)" || die 2 "cannot reserve a unique default output directory in $_def_base"
fi

# --- frozen snapshot --------------------------------------------------------
SNAP="$OUT_DIR/candidate-snapshot"
ARCHIVE_SHA_FILE="$OUT_DIR/.candidate-snapshot.archive-sha256"
# The snapshot destination and its evidence file are created, never replaced.
# The whole --out directory was reserved fresh above, so no user path can be
# truncated. On failure the partial snapshot is left in place for inspection.
log "building frozen snapshot: git archive $SRC_SHA + export_presets.cfg only"
es_make_frozen_snapshot "$PROJECT_DIR" "$SNAP" "$ARCHIVE_SHA_FILE" "$SRC_SHA" || die 2 "could not build the frozen snapshot from $PROJECT_DIR (see above)"
[ -s "$SNAP/project.godot" ] || die 2 "built snapshot has no usable project.godot: $SNAP"
# The digest comes from the exact archive bytes that were extracted; there is
# no second, unchecked `git archive` invocation.
_digest_text="$(cat "$ARCHIVE_SHA_FILE" 2>/dev/null)"
ARCHIVE_SHA="$(printf '%s\n' "$_digest_text" | sed -n 's/^archive_sha256=//p' | head -n 1)"
PRESETS_SHA="$(printf '%s\n' "$_digest_text" | sed -n 's/^presets_sha256=//p' | head -n 1)"
if ! es_is_hex_sha256 "$ARCHIVE_SHA"; then
	die 2 "frozen archive SHA-256 is missing or invalid: '$ARCHIVE_SHA'"
fi
if ! es_is_hex_sha256 "$PRESETS_SHA"; then
	die 2 "frozen presets SHA-256 is missing or invalid: '$PRESETS_SHA'"
fi
# Presets are commit-bound. Diagnose (but do not use) a differing live copy.
LIVE_PRE_SHA="$(es_sha256 "$PROJECT_DIR/export_presets.cfg" 2>/dev/null)"
if [ -n "$LIVE_PRE_SHA" ] && [ "$LIVE_PRE_SHA" = "$PRESETS_SHA" ]; then
	PRESETS_LIVE_MATCH=true
else
	PRESETS_LIVE_MATCH=false
	if [ -n "$LIVE_PRE_SHA" ]; then
		warn "live export_presets.cfg differs from $SRC_SHA:export_presets.cfg; the committed bytes were built and reported"
	fi
fi
# The evidence file is left in place: deleting it through a mutable pathname
# could remove a concurrently planted foreign file. It is a small dotfile in
# the reserved output directory.

# --- optional diagnostic project-setting patch (snapshot only) -------------
if [ "$DIAG_ETC2" -eq 1 ]; then
	warn "DIAGNOSTIC: enabling import_etc2_astc in the SNAPSHOT project.godot only"
	warn "DIAGNOSTIC: the tracked project.godot is NOT modified; this proves the"
	warn "DIAGNOSTIC: macOS preset is otherwise correct and the package launches."
	if [ -L "$SNAP/project.godot" ] || [ ! -f "$SNAP/project.godot" ]; then
		die 2 "snapshot project.godot is missing or not a regular file; refusing the diagnostic patch"
	fi
	# Patch only when the setting is not already true: a =false line must be
	# replaced, not skipped. Only $SNAP is ever written; the live checkout and
	# the tracked file stay untouched.
	if grep -Eq '(^|[[:space:]])textures/vram_compression/import_etc2_astc[[:space:]]*=[[:space:]]*true([[:space:]]|$)' "$SNAP/project.godot"; then
		:
	else
		python3 - "$SNAP/project.godot" <<'PY' 2>/dev/null || \
			sed -i '' 's/^\(.*import_etc2_astc.*\)=.*/\1=true/' "$SNAP/project.godot" 2>/dev/null || \
			die 2 "could not apply the diagnostic project-setting patch"
import re, sys
line = "textures/vram_compression/import_etc2_astc"
p = sys.argv[1]
s = open(p).read()
pattern = r"(?m)^([ \t]*" + re.escape(line) + r"[ \t]*=[ \t]*).*$"
if re.search(pattern, s):
    s = re.sub(pattern, r"\1true", s)
elif "[rendering]\n" in s:
    s = s.replace("[rendering]\n", "[rendering]\n" + line + "=true\n", 1)
else:
    if not s.endswith("\n"):
        s += "\n"
    s += "\n[rendering]\n" + line + "=true\n"
open(p, "w").write(s)
PY
	fi
fi

# Candidate evidence binds every exported input: the archive bytes, the frozen
# presets and the frozen project.godot as actually used (after any diagnostic
# patch). Missing/unreadable/symlinked/invalid inputs fail closed before PASS.
_ev="$(es_candidate_evidence "$ARCHIVE_SHA" "$PRESETS_SHA" "$SNAP")" || \
	die 2 "candidate evidence validation failed (see above)"
PROJECT_GODOT_SHA="$(printf '%s\n' "$_ev" | sed -n 's/^project_godot_sha256=//p')"
_cand_input="$OUT_DIR/.candidate-digest-input"
if ! _es_create_exclusive "$_cand_input" "$(printf '%s' "$_ev")"; then
	die 2 "could not create the candidate-digest input exclusively: $_cand_input"
fi
CANDIDATE_SHA="$(es_sha256 "$_cand_input")"
if ! es_is_hex_sha256 "$CANDIDATE_SHA"; then
	die 2 "could not compute the candidate digest: '$CANDIDATE_SHA'"
fi

log "candidate archive sha256: $ARCHIVE_SHA"
log "candidate presets sha256: $PRESETS_SHA"
log "candidate project.godot sha256: $PROJECT_GODOT_SHA"
log "candidate digest:         $CANDIDATE_SHA"

# --- per-platform export ----------------------------------------------------
REPORT="$OUT_DIR/export-smoke-report.txt"
SUMS="$OUT_DIR/SHA256SUMS.txt"
# Create exclusively; never truncate an existing path. Later appends go
# through the pathname (the reserved output dir is guarded at creation), so a
# concurrent swap after this point could redirect appended text; no removal or
# truncation of a replaced path is performed after this line.
if ! _es_create_exclusive "$REPORT" ""; then
	die 2 "cannot create the report exclusively: $REPORT"
fi
if ! _es_create_exclusive "$SUMS" ""; then
	die 2 "cannot create SHA256SUMS exclusively: $SUMS"
fi
{
	printf '# Roadstorm Racer! export smoke component checksums (E3).\n'
	printf '# Every produced package component is listed, including the .pck.\n'
	printf '# macOS .app component paths are relative to the extracted bundle,\n'
	printf '# so `shasum -c SHA256SUMS.txt` only verifies the top-level artifacts.\n'
} >>"$SUMS"

preset_for() {
	case "$1" in
	macOS) printf '%s\n' "macOS Apple Silicon" ;;
	Windows) printf '%s\n' "Windows x86-64" ;;
	Linux) printf '%s\n' "Linux x86-64" ;;
	esac
}
outfile_for() {
	case "$1" in
	macOS) printf '%s\n' "Roadstorm-macOS-universal.zip" ;;
	Windows) printf '%s\n' "Roadstorm-Windows-x86_64.exe" ;;
	Linux) printf '%s\n' "Roadstorm-Linux-x86_64" ;;
	esac
}

FAILED=0

# es_check_package <platform> <main-file>
# Checksums and policy-checks a produced package with lib/pack_inventory.py
# (E3: every component, including the .pck; E4: no development-only content,
# no missing runtime dependency, every pack entry's MD-5 verified). Appends the
# per-platform inventory report and JSON, appends every component checksum to
# SHA256SUMS.txt, records the verdict in the report and fails the run on a
# FAIL. Without python3 the deep checks are skipped loudly and only the
# top-level artifacts are checksummed with the shell helper.
es_check_package() {
	_plat="$1"
	_main="$2"
	_inv="$OUT_DIR/package-inventory-$_plat.txt"
	_json="$OUT_DIR/package-inventory-$_plat.json"
	if ! command -v python3 >/dev/null 2>&1; then
		warn "python3 not found: the deep package inventory is REQUIRED for $_plat"
		printf '  package_inventory=NOT_RUN (python3 unavailable)\n' >>"$REPORT"
		FAILED=1
		return 0
	fi
	if ! _es_create_exclusive "$OUT_DIR/package-inventory-$_plat.log" ""; then
		warn "cannot create the package inventory log exclusively for $_plat"
		printf '  package_inventory=NOT_RUN (log creation refused)\n' >>"$REPORT"
		FAILED=1
		return 0
	fi
	_summary="$(python3 "$PACK_INVENTORY" check --platform "$_plat" --main "$_main" \
		--snapshot "$SNAP" --report "$_inv" --json "$_json" --sums "$SUMS" --quiet 2>>"$OUT_DIR/package-inventory-$_plat.log")"
	_pstatus=$?
	if [ -n "$_summary" ]; then
		printf '  %s\n' "$_summary" >>"$REPORT"
	fi
	if [ "$_pstatus" -ne 0 ]; then
		printf '  package_inventory=FAIL (exit %s)\n' "$_pstatus" >>"$REPORT"
		log "package inventory check FAILED for $_plat (see $_inv)"
		FAILED=1
	else
		printf '  package_inventory=PASS\n' >>"$REPORT"
		INV_OK="$INV_OK $_plat"
		log "package inventory check passed for $_plat (see $_inv)"
	fi
	return 0
}

{
	printf '# Roadstorm Racer! export smoke report\n'
	printf '# generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
	printf 'engine_bin=%s\n' "$GODOT_BIN"
	printf 'engine_version=%s\n' "$_ver"
	printf 'pinned_version=%s\n' "$PINNED_VERSION_STRING"
	printf 'head_commit=%s\n' "$SRC_SHA"
	printf 'head_tree=%s\n' "$SRC_TREE"
	printf 'archive_sha256=%s\n' "$ARCHIVE_SHA"
	printf 'presets_sha256=%s\n' "$PRESETS_SHA"
	printf 'project_godot_sha256=%s\n' "$PROJECT_GODOT_SHA"
	printf 'presets_source=head-commit\n'
	printf 'presets_live_matches_commit=%s\n' "$PRESETS_LIVE_MATCH"
	printf 'candidate_digest=%s\n' "$CANDIDATE_SHA"
	printf 'diagnostic_enable_etc2_astc=%s\n' "$DIAG_ETC2"
	printf 'launch_probe=%s\n' "$LAUNCH_PROBE"
	printf 'requested_platforms=%s\n' "$PLATFORMS"
	printf 'presets_exclude_filter=%s\n' "$(sed -n 's/^exclude_filter="\(.*\)"$/\1/p' "$SNAP/export_presets.cfg" 2>/dev/null | head -n 1)"
	printf '\n'
} >>"$REPORT"

EXPORTED_OK=""
INV_OK=""
_req_n=0
for _p in $PLATFORMS; do _req_n=$((_req_n + 1)); done
unset _p

for plat in $PLATFORMS; do
	preset="$(preset_for "$plat")"
	outname="$(outfile_for "$plat")"
	out="$OUT_DIR/$outname"
	elog="$OUT_DIR/export-$plat.log"

	log "export $plat: preset '$preset' -> $outname"
	es_run_bounded "$EXPORT_TIMEOUT" "$elog" -- "$GODOT_BIN" --headless --path "$SNAP" --export-release "$preset" "$out"
	estatus=$?

	status="FAILED"
	reason=""
	if [ "$estatus" -eq 0 ] && [ -e "$out" ]; then
		status="EXPORTED"
	elif [ "$estatus" -eq 124 ]; then
		reason="export timed out after ${EXPORT_TIMEOUT}s"
	elif grep -qi 'ETC2 ASTC texture format is disabled' "$elog"; then
		status="BLOCKED"
		reason="project.godot rendering/textures/vram_compression/import_etc2_astc is false; \
arm64/universal macOS export requires it true. Owned outside this tool (project.godot). \
Re-run with --diagnostic-enable-etc2-astc to prove the preset otherwise works."
	elif grep -qi 'not found. It might be missing' "$elog"; then
		reason="export template binary missing for the requested architecture"
	else
		reason="godot --export-release exited $estatus (see export-$plat.log)"
	fi

	printf 'platform=%s preset="%s" status=%s out=%s\n' "$plat" "$preset" "$status" "$outname" >>"$REPORT"
	if [ -n "$reason" ]; then
		printf '  reason=%s\n' "$reason" >>"$REPORT"
	fi

	if [ "$status" = "EXPORTED" ]; then
		EXPORTED_OK="$EXPORTED_OK $plat"
		# E3/E4: checksum every produced component and policy-check the pack.
		es_check_package "$plat" "$out"
	else
		FAILED=1
	fi

	# macOS launch test, only when a package was actually produced.
	if [ "$plat" = "macOS" ] && [ "$status" = "EXPORTED" ]; then
		log "macOS package exported; running the $LAUNCH_PROBE launch test"
		if ! _es_create_exclusive "$OUT_DIR/macos-launch.log" ""; then
			warn "cannot create macos-launch.log exclusively; skipping the launch test"
			printf '  macos_launch=SKIPPED (log creation refused)\n' >>"$REPORT"
			FAILED=1
		else
			if [ "$LAUNCH_PROBE" = "full" ]; then
				"$SCRIPT_DIR/launch_macos_app.sh" --app "$out" --out "$OUT_DIR" --quit-after 40 --timeout "$LAUNCH_TIMEOUT" --windowed-seconds 8 \
					>>"$OUT_DIR/macos-launch.log" 2>&1
			else
				"$SCRIPT_DIR/launch_macos_app.sh" --app "$out" --out "$OUT_DIR" --quit-after 40 --timeout "$LAUNCH_TIMEOUT" --skip-windowed \
					>>"$OUT_DIR/macos-launch.log" 2>&1
			fi
			lstatus=$?
			_llog="$OUT_DIR/macos-launch.log"
			_lv="$(grep '^VERDICT=' "$_llog" | tail -n 1 | cut -d= -f2-)"
			_ls="$(grep '^SIGNATURE=' "$_llog" | tail -n 1 | cut -d= -f2-)"
			_lw="$(grep '^WINDOWED=' "$_llog" | tail -n 1 | cut -d= -f2-)"
			_lsh="$(grep '^SCREENSHOT=' "$_llog" | tail -n 1 | cut -d= -f2-)"
			_le="$(grep '^EXECUTABLE_EXECUTED=' "$_llog" | tail -n 1 | cut -d= -f2-)"
			[ -n "$_lv" ] || _lv=FAIL
			_launch_ok=false
			if [ "$lstatus" -ne 0 ]; then
				if [ "$_lv" = PASS ]; then
					warn "launcher printed VERDICT=PASS but exited $lstatus; refusing the marker alone"
				fi
			elif [ "$_lv" != PASS ]; then
				_launch_ok=false
			else
				_launch_ok=true
			fi
			printf '  macos_launch=%s\n' "$( [ "$_launch_ok" = true ] && printf PASS || printf FAIL)" >>"$REPORT"
			printf '  macos_signature=%s\n' "${_ls:-NOT_CHECKED}" >>"$REPORT"
			printf '  macos_windowed=%s\n' "${_lw:-UNKNOWN}" >>"$REPORT"
			printf '  macos_screenshot=%s\n' "${_lsh:-UNKNOWN}" >>"$REPORT"
			printf '  macos_executable_executed=%s\n' "${_le:-false}" >>"$REPORT"
			if [ "$_launch_ok" != "true" ]; then
				log "macOS launch test FAILED (exit=$lstatus verdict=$_lv; see macos-launch.log)"
				FAILED=1
			else
				log "macOS launch test PASSED (exit=0, VERDICT=PASS observed)"
			fi
			if [ "$_ls" = "ad-hoc" ]; then
				printf '  ad_hoc_signature_observed=true\n' >>"$REPORT"
			else
				printf '  ad_hoc_signature_observed=false\n' >>"$REPORT"
			fi
			if [ "$_le" = "true" ]; then
				printf '  target_executable_executed=true\n' >>"$REPORT"
			else
				printf '  target_executable_executed=false\n' >>"$REPORT"
			fi
			if [ "$LAUNCH_PROBE" = "full" ]; then
				printf '  macos_launch_note=probe=full; windowed=%s; screenshot=%s; signature=%s; x86_64 slice NOT claimed\n' "$_lw" "$_lsh" "$_ls" >>"$REPORT"
			else
				printf '  macos_launch_note=probe=headless; windowed NOT_RUN (--skip-windowed); screenshot NOT_RUN; arm64/x86_64 slices NOT claimed\n' >>"$REPORT"
			fi
		fi
	fi
	if [ "$plat" = "macOS" ] && [ "$status" = "BLOCKED" ]; then
		printf '  macos_launch=NOT_RUN (no package: export blocked)\n' >>"$REPORT"
	fi
	if [ "$plat" = "Windows" ] || [ "$plat" = "Linux" ]; then
		printf '  note=cross-export only; NOT launched (no %s host). A successful export does not verify the platform.\n' "$plat" >>"$REPORT"
	fi
done

{
	_exp_n=0
	for _x in $EXPORTED_OK; do _exp_n=$((_exp_n + 1)); done
	unset _x
	_inv_n=0
	for _x in $INV_OK; do _inv_n=$((_inv_n + 1)); done
	unset _x
	packaging_complete=false
	if [ "$FAILED" -eq 0 ] && [ "$_req_n" -gt 0 ] && [ "$_exp_n" -eq "$_req_n" ] && [ "$_inv_n" -eq "$_req_n" ]; then
		packaging_complete=true
	fi
	printf '\n# Honest status\n'
	printf 'm0_smoke_only=true  # placeholder shell; NOT final M0, NOT gameplay\n'
	printf 'notarized=false  # no Developer ID/notarization credentials exist; not claimed as a release\n'
	printf 'windows_launched=false\n'
	printf 'linux_launched=false\n'
	if [ "$packaging_complete" = true ]; then
		printf 'dev_tooling_packaged=false  # verified by tools/export_smoke/lib/pack_inventory.py on every requested platform\n'
		printf 'all_package_components_checksummed=true  # verified for every requested platform\n'
	else
		printf 'dev_tooling_packaged=NOT_VERIFIED  # inventory passes %s/%s requested platforms\n' "$_inv_n" "$_req_n"
		printf 'all_package_components_checksummed=NOT_VERIFIED  # exports %s/%s requested platforms\n' "$_exp_n" "$_req_n"
	fi
	printf 'packaging_checks_complete=%s\n' "$packaging_complete"
	printf 'packaging_verifies=component checksums, pack MD-5s, no dev-only content, required runtime resources (when complete)\n'
	printf 'packaging_does_not_verify=target-OS launch (only what the recorded probe observed), signature/notarization, gameplay, M9 notices\n'
} >>"$REPORT"

log "report: $REPORT"
log "checksums: $SUMS"
log "package inventories: $OUT_DIR/package-inventory-<platform>.txt/.json"

if [ "$FAILED" -eq 0 ]; then
	log "PASS: every requested platform exported (macOS launched if requested)"
	exit 0
fi
log "one or more requested platforms were blocked/failed; see $REPORT"
exit 1
