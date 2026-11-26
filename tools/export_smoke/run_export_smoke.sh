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
# Usage:
#   run_export_smoke.sh [--out <dir>] [--platform macOS|Windows|Linux]...
#                       [--diagnostic-enable-etc2-astc]
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
EXPORT_TIMEOUT=120
LAUNCH_TIMEOUT=120

log()  { printf '[export-smoke] %s\n' "$*"; }
warn() { printf '[export-smoke] WARN: %s\n' "$*" >&2; }
die()  { c="$1"; shift; printf '[export-smoke] FAIL: %s\n' "$*" >&2; exit "$c"; }

while [ $# -gt 0 ]; do
	case "$1" in
	--out) [ $# -ge 2 ] || die 2 "--out needs a directory"; OUT_DIR="$2"; shift 2 ;;
	--out=*) OUT_DIR="${1#--out=}"; shift ;;
	--platform) [ $# -ge 2 ] || die 2 "--platform needs macOS|Windows|Linux"; PLATFORMS="$PLATFORMS $2"; shift 2 ;;
	--platform=*) PLATFORMS="$PLATFORMS ${1#--platform=}"; shift ;;
	--diagnostic-enable-etc2-astc) DIAG_ETC2=1; shift ;;
	--export-timeout) [ $# -ge 2 ] || die 2 "--export-timeout needs seconds"; EXPORT_TIMEOUT="$2"; shift 2 ;;
	--export-timeout=*) EXPORT_TIMEOUT="${1#--export-timeout=}"; shift ;;
	--launch-timeout) [ $# -ge 2 ] || die 2 "--launch-timeout needs seconds"; LAUNCH_TIMEOUT="$2"; shift 2 ;;
	--launch-timeout=*) LAUNCH_TIMEOUT="${1#--launch-timeout=}"; shift ;;
	-h|--help) sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) die 2 "unknown argument: $1" ;;
	esac
done

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
: >"$SUMS"

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
	printf 'requested_platforms=%s\n' "$PLATFORMS"
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
		# Record the primary artifact and any sidecar .pck.
		for f in "$out" "${out%.*}.pck"; do
			if [ -e "$f" ]; then
				_sum="$(es_sha256 "$f")"
				_bytes="$(wc -c <"$f" | tr -d ' ')"
				printf '  artifact=%s sha256=%s bytes=%s\n' "$(basename "$f")" "$_sum" "$_bytes" >>"$REPORT"
				printf '%s  %s\n' "$_sum" "$(basename "$f")" >>"$SUMS"
			fi
		done
	else
		FAILED=1
	fi

	# macOS launch test, only when a package was actually produced.
	if [ "$plat" = "macOS" ] && [ "$status" = "EXPORTED" ]; then
		log "macOS package exported; running launch test"
		"$SCRIPT_DIR/launch_macos_app.sh" --app "$out" --out "$OUT_DIR" --quit-after 40 --windowed-seconds 8 \
			>>"$OUT_DIR/macos-launch.log" 2>&1
		lstatus=$?
		printf '  macos_launch=%s\n' "$([ "$lstatus" -eq 0 ] && printf PASS || printf FAIL)" >>"$REPORT"
		if [ "$lstatus" -ne 0 ]; then
			log "macOS launch test FAILED (see macos-launch.log)"
			FAILED=1
		else
			log "macOS launch test PASSED"
		fi
		printf '  macos_launch_note=ad-hoc signed, UNNOTARIZED; arm64 slice launched on this Apple Silicon host; x86_64 (Intel) slice UNTESTED\n' >>"$REPORT"
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
} >>"$REPORT"

log "report: $REPORT"
log "checksums: $SUMS"

if [ "$FAILED" -eq 0 ]; then
	log "PASS: every requested platform exported (macOS launched if requested)"
	exit 0
fi
log "one or more requested platforms were blocked/failed; see $REPORT"
exit 1
