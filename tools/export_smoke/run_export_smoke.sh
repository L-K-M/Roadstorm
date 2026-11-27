#!/bin/sh
# Roadstorm Racer! - export smoke build runner (PLAN.md M0.4/M0.5, M9, T16).
# Ownership: tools/export_smoke/** (PLAN.md "How agents execute the plan").
#
# Builds native smoke packages for the three committed desktop targets
# (docs/TECHNICAL_DESIGN.md "Packaging and operations") from a FROZEN, ISOLATED
# source candidate and - for macOS only - launches the package.
#
# WHAT THIS PROVES AND WHAT IT DOES NOT
#   * The source candidate is a frozen snapshot: `git archive HEAD` plus ONLY
#     the owned export_presets.cfg. No concurrent uncommitted file enters it.
#   * A successful cross-export is NOT a platform launch. Windows and Linux
#     packages are produced but NOT launched (no target host); an untested
#     platform never becomes verified through a successful export (M0/M9.2).
#   * The macOS package is launched here (the only host available). It is
#     AD-HOC signed and UNNOTARIZED (no Developer ID credentials exist); it is
#     NOT a notarized release and NOT claimed as such.
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
#   the top-level artifacts), and the macOS launch logs.
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

# --- engine -----------------------------------------------------------------
GODOT_BIN="$(es_default_godot)" || die 2 "no Godot binary found; set GODOT_BIN"
[ -x "$GODOT_BIN" ] || [ "$GODOT_BIN" = "godot" ] || die 2 "'$GODOT_BIN' is not executable"
_ver="$("$GODOT_BIN" --version 2>/dev/null)" || _ver=""
[ -n "$_ver" ] || die 2 "could not run '$GODOT_BIN --version'"
if [ "$_ver" != "$PINNED_VERSION_STRING" ]; then
	die 2 "engine is '$_ver', not the pinned '$PINNED_VERSION_STRING'"
fi
log "engine: $GODOT_BIN ($_ver) matches pin"

# --- output dir -------------------------------------------------------------
if [ -z "$OUT_DIR" ]; then
	OUT_DIR="$PROJECT_DIR/work/agents/export-smoke/outputs"
fi
mkdir -p "$OUT_DIR" 2>/dev/null || die 2 "cannot create output dir $OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# --- frozen snapshot --------------------------------------------------------
SNAP="$OUT_DIR/candidate-snapshot"
log "building frozen snapshot: git archive HEAD + export_presets.cfg only"
es_make_frozen_snapshot "$PROJECT_DIR" "$SNAP" || die 2 "could not build the frozen snapshot"
[ -f "$SNAP/project.godot" ] || die 2 "snapshot has no project.godot"

HEAD_SHA="$(cd "$PROJECT_DIR" && git rev-parse HEAD 2>/dev/null)"
HEAD_TREE="$(cd "$PROJECT_DIR" && git rev-parse 'HEAD^{tree}' 2>/dev/null)"
ARCHIVE_SHA="$( cd "$PROJECT_DIR" && git archive HEAD | shasum -a 256 2>/dev/null | awk '{print $1}' )"
PRESETS_SHA="$(es_sha256 "$PROJECT_DIR/export_presets.cfg")"
if [ -n "$ARCHIVE_SHA" ]; then
	CANDIDATE_SHA="$(printf '%s\n%s\n' "$ARCHIVE_SHA" "$PRESETS_SHA" | shasum -a 256 2>/dev/null | awk '{print $1}')"
else
	CANDIDATE_SHA="(sha256 utility unavailable)"
fi

log "candidate HEAD commit: $HEAD_SHA"
log "candidate HEAD tree:   $HEAD_TREE"
log "candidate archive sha256: $ARCHIVE_SHA"
log "candidate presets sha256: $PRESETS_SHA"
log "candidate digest:         $CANDIDATE_SHA"

# --- optional diagnostic project-setting patch (snapshot only) -------------
if [ "$DIAG_ETC2" -eq 1 ]; then
	warn "DIAGNOSTIC: enabling import_etc2_astc in the SNAPSHOT project.godot only"
	warn "DIAGNOSTIC: the tracked project.godot is NOT modified; this proves the"
	warn "DIAGNOSTIC: macOS preset is otherwise correct and the package launches."
	if grep -q 'import_etc2_astc' "$SNAP/project.godot"; then
		:
	else
		python3 - "$SNAP/project.godot" <<'PY' 2>/dev/null || \
			sed -i '' 's/^\[rendering\]$/[rendering]\ntextures\/vram_compression\/import_etc2_astc=true/' "$SNAP/project.godot" 2>/dev/null || \
			die 2 "could not apply the diagnostic project-setting patch"
import sys
p = sys.argv[1]
s = open(p).read()
if 'import_etc2_astc' not in s:
    s = s.replace('[rendering]\n', '[rendering]\ntextures/vram_compression/import_etc2_astc=true\n', 1)
open(p, 'w').write(s)
PY
	fi
fi

# --- per-platform export ----------------------------------------------------
REPORT="$OUT_DIR/export-smoke-report.txt"
SUMS="$OUT_DIR/SHA256SUMS.txt"
: >"$REPORT"
{
	printf '# Roadstorm Racer! export smoke component checksums (E3).\n'
	printf '# Every produced package component is listed, including the .pck.\n'
	printf '# macOS .app component paths are relative to the extracted bundle,\n'
	printf '# so `shasum -c SHA256SUMS.txt` only verifies the top-level artifacts.\n'
} >"$SUMS"

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
		warn "python3 not found: skipping the package inventory/MD-5 checks for $_plat"
		printf '  package_inventory=SKIPPED (python3 unavailable; top-level artifacts checksummed only)\n' >>"$REPORT"
		for _f in "$_main" "${_main%.*}.pck"; do
			[ -e "$_f" ] || continue
			_sum="$(es_sha256 "$_f")"
			_bytes="$(wc -c <"$_f" | tr -d ' ')"
			printf '  artifact=%s sha256=%s bytes=%s\n' "$(basename "$_f")" "$_sum" "$_bytes" >>"$REPORT"
			printf '%s  %s\n' "$_sum" "$(basename "$_f")" >>"$SUMS"
		done
		return 0
	fi
	_summary="$(python3 "$PACK_INVENTORY" check --platform "$_plat" --main "$_main" \
		--snapshot "$SNAP" --report "$_inv" --json "$_json" --sums "$SUMS" --quiet 2>>"$OUT_DIR/package-inventory-$_plat.log")"
	_pstatus=$?
	if [ -n "$_summary" ]; then
		printf '  %s\n' "$_summary" >>"$REPORT"
	fi
	if [ "$_pstatus" -ne 0 ]; then
		log "package inventory check FAILED for $_plat (see $_inv)"
		FAILED=1
	else
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
	printf 'head_commit=%s\n' "$HEAD_SHA"
	printf 'head_tree=%s\n' "$HEAD_TREE"
	printf 'archive_sha256=%s\n' "$ARCHIVE_SHA"
	printf 'presets_sha256=%s\n' "$PRESETS_SHA"
	printf 'candidate_digest=%s\n' "$CANDIDATE_SHA"
	printf 'diagnostic_enable_etc2_astc=%s\n' "$DIAG_ETC2"
	printf 'launch_probe=%s\n' "$LAUNCH_PROBE"
	printf 'requested_platforms=%s\n' "$PLATFORMS"
	printf 'presets_exclude_filter=%s\n' "$(sed -n 's/^exclude_filter="\(.*\)"$/\1/p' "$SNAP/export_presets.cfg" 2>/dev/null | head -n 1)"
	printf '\n'
} >>"$REPORT"

for plat in $PLATFORMS; do
	case "$plat" in
	macOS|Windows|Linux) : ;;
	*) warn "ignoring unknown platform '$plat'"; continue ;;
	esac
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
		# E3/E4: checksum every produced component and policy-check the pack.
		es_check_package "$plat" "$out"
	else
		FAILED=1
	fi

	# macOS launch test, only when a package was actually produced.
	if [ "$plat" = "macOS" ] && [ "$status" = "EXPORTED" ]; then
		log "macOS package exported; running the $LAUNCH_PROBE launch test"
		if [ "$LAUNCH_PROBE" = "full" ]; then
			"$SCRIPT_DIR/launch_macos_app.sh" --app "$out" --out "$OUT_DIR" --quit-after 40 --windowed-seconds 8 \
				>>"$OUT_DIR/macos-launch.log" 2>&1
		else
			"$SCRIPT_DIR/launch_macos_app.sh" --app "$out" --out "$OUT_DIR" --quit-after 40 --skip-windowed \
				>>"$OUT_DIR/macos-launch.log" 2>&1
		fi
		lstatus=$?
		printf '  macos_launch=%s\n' "$([ "$lstatus" -eq 0 ] && printf PASS || printf FAIL)" >>"$REPORT"
		if [ "$lstatus" -ne 0 ]; then
			log "macOS launch test FAILED (see macos-launch.log)"
			FAILED=1
		else
			log "macOS launch test PASSED"
		fi
		printf '  macos_launch_note=probe=%s; ad-hoc signed, UNNOTARIZED; arm64 slice launched on this Apple Silicon host; x86_64 (Intel) slice UNTESTED\n' "$LAUNCH_PROBE" >>"$REPORT"
	fi
	if [ "$plat" = "macOS" ] && [ "$status" = "BLOCKED" ]; then
		printf '  macos_launch=NOT_RUN (no package: export blocked)\n' >>"$REPORT"
	fi
	if [ "$plat" = "Windows" ] || [ "$plat" = "Linux" ]; then
		printf '  note=cross-export only; NOT launched (no %s host). A successful export does not verify the platform.\n' "$plat" >>"$REPORT"
	fi
done

{
	printf '\n# Honest status\n'
	printf 'm0_smoke_only=true  # placeholder shell; NOT final M0, NOT gameplay\n'
	printf 'notarized=false     # ad-hoc signed; no Developer ID/notarization credentials\n'
	printf 'windows_launched=false\n'
	printf 'linux_launched=false\n'
	printf 'dev_tooling_packaged=false  # enforced by tools/export_smoke/lib/pack_inventory.py\n'
	printf 'all_package_components_checksummed=true  # E3: zip/exe/binary, .pck and macOS .app files\n'
	printf 'packaging_verifies=component checksums, pack MD-5s, no dev-only content, required runtime resources\n'
	printf 'packaging_does_not_verify=target-OS launch (except macOS, headless by default), signature/notarization, gameplay, M9 notices\n'
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
