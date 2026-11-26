#!/bin/sh
# Roadstorm Racer! - Jolt settings inventory runner (M0.1 evidence).
#
# Ownership: tools/jolt_inventory/**. Evidence: docs/evidence/jolt-settings.md.
#
# What it does:
#   1. checks that the Godot binary is the exact pinned official build
#      (`godot --version` against tools/toolchain/pin/engine.txt, read only;
#      a mirrored fallback string is used if that file is absent), because the
#      recorded values are build-specific;
#   2. builds TWO throwaway Godot projects in a temporary directory:
#        - `defaults`: this tool's project.godot, which sets no physics
#          settings, so the Jolt settings read back as engine defaults;
#        - `main`: a copy of the game project's project.godot, so the Jolt
#          settings read back exactly as the game project sees them;
#   3. runs src/jolt_inventory.gd headless in each project under `timeout 30`
#      (the script always quits, and the timeout bounds it anyway);
#   4. compares the two runs and classifies every Jolt setting as an engine
#      default or an explicit game-project override;
#   5. writes the raw logs, the JSON reports and the comparison into an
#      evidence directory (default tools/jolt_inventory/evidence/<date>-<host>).
#
# The engine is never pointed at the game project, so this cannot write the
# game project's .godot/ cache, settings or any other file. It reads nothing
# but project.godot, the engine pin file and this tool's own files.
#
# Usage:
#   tools/jolt_inventory/run_inventory.sh
#   tools/jolt_inventory/run_inventory.sh --project <checkout> --out-dir <dir>
#   GODOT_BIN=/path/to/godot tools/jolt_inventory/run_inventory.sh
#
# Exit codes: 0 = inventory complete and consistent, 1 = a run failed or the
# two runs disagree, 2 = the wrapper could not run (no engine, no timeout
# utility, bad arguments).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PROJECT_DIR="${PROJECT_DIR:-$REPO_ROOT}"
GODOT_BIN="${GODOT_BIN:-}"
OUT_DIR="${OUT_DIR:-}"

# Mirrored from tools/toolchain/pin/engine.txt (version_string=...). That pin
# file is owned by tools/toolchain/** and is only read here, never written.
PINNED_VERSION_STRING="4.7.2.stable.official.ed1daf0bf"

# Hard bound on every engine command, as required by the owning job.
ENGINE_TIMEOUT=30

# Engine-reported script errors. A clean inventory run prints none of these.
ERROR_PATTERN='SCRIPT ERROR|Failed to load script|Parse Error|^ERROR:|^USER ERROR:'

# The intermittent Jolt warning recorded as R7 in
# review/implementation/m0-five-jobs-opus-recheck-929c4082-0280-464e-830a-00dd35c164e1.md.
# It is recorded, never treated as a failure: no cause is claimed and no
# handling change is made here.
JOB_WARNING_PATTERN='exceeded the maximum number of jobs'

log() {
	echo "[run-inventory] $*"
}

die() {
	# die <exit-code> <message...>
	code="$1"
	shift
	log "FAIL: $*" >&2
	exit "$code"
}

usage() {
	sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
}

# --- argument handling ------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
	--project)
		[ $# -ge 2 ] || die 2 "--project needs a directory argument"
		PROJECT_DIR="$2"
		shift 2
		;;
	--project=*)
		PROJECT_DIR="${1#--project=}"
		shift
		;;
	--out-dir)
		[ $# -ge 2 ] || die 2 "--out-dir needs a directory argument"
		OUT_DIR="$2"
		shift 2
		;;
	--out-dir=*)
		OUT_DIR="${1#--out-dir=}"
		shift
		;;
	-h|--help)
		usage
		exit 0
		;;
	*)
		die 2 "unknown argument '$1' (see --help)"
		;;
	esac
done

[ -d "$PROJECT_DIR" ] || die 2 "project directory '$PROJECT_DIR' does not exist"
[ -f "$PROJECT_DIR/project.godot" ] || die 2 "'$PROJECT_DIR' has no project.godot"

[ -n "$GODOT_BIN" ] || GODOT_BIN="$(command -v godot 2>/dev/null || true)"
[ -n "$GODOT_BIN" ] || die 2 "no Godot binary found; set GODOT_BIN"

# Every engine command below is bounded by this utility. Without one the
# 30-second bound could not be honoured, so the wrapper refuses to run.
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
	TIMEOUT_BIN="gtimeout"
else
	die 2 "no 'timeout' utility found; the engine runs could not be time-bounded"
fi

host_tag() {
	# Short, stable host label for the evidence directory name, in the style
	# of tools/tick_probe/evidence/<date>-<host>.
	brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
	if [ -n "$brand" ]; then
		echo "$brand" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -d ','
	else
		uname -m
	fi
}

if [ -z "$OUT_DIR" ]; then
	OUT_DIR="$SCRIPT_DIR/evidence/$(date +%F)-$(host_tag)"
fi

PIN_FILE="$PROJECT_DIR/tools/toolchain/pin/engine.txt"
if [ -f "$PIN_FILE" ]; then
	recorded="$(sed -n 's/^version_string=//p' "$PIN_FILE" | head -n 1)"
	[ -n "$recorded" ] && PINNED_VERSION_STRING="$recorded"
fi

# --- isolated temporary projects -------------------------------------------
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roadstorm-jolt-inventory.XXXXXX")" || die 2 "could not create a temporary directory"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/defaults/src" "$WORK_DIR/main/src" || die 2 "could not populate the temporary directory"

# Run 1: engine defaults (this tool's project.godot sets no physics settings).
cp "$SCRIPT_DIR/project.godot" "$WORK_DIR/defaults/project.godot" || die 2 "could not copy the inventory project template"
# Run 2: the game project's own settings.
cp "$PROJECT_DIR/project.godot" "$WORK_DIR/main/project.godot" || die 2 "could not copy '$PROJECT_DIR/project.godot'"
cp "$SCRIPT_DIR/src/jolt_inventory.gd" "$WORK_DIR/defaults/src/jolt_inventory.gd" || die 2 "could not copy the inventory script"
cp "$SCRIPT_DIR/src/jolt_inventory.gd" "$WORK_DIR/main/src/jolt_inventory.gd" || die 2 "could not copy the inventory script"

mkdir -p "$OUT_DIR" || die 2 "could not create the evidence directory '$OUT_DIR'"

# --- run the engine twice, each bounded by ENGINE_TIMEOUT --------------------
actual_version="$("$TIMEOUT_BIN" "$ENGINE_TIMEOUT" "$GODOT_BIN" --version 2>/dev/null)" || actual_version=""
[ -n "$actual_version" ] || die 2 "could not run '$GODOT_BIN --version'"
if [ "$actual_version" != "$PINNED_VERSION_STRING" ]; then
	log "engine reports version '$actual_version'" >&2
	die 1 "engine is not the pinned build '$PINNED_VERSION_STRING'; recorded values are build-specific"
fi
log "engine is the pinned build: $PINNED_VERSION_STRING"

run_inventory() {
	# run_inventory <project-dir> <label> <log-file> <json-file>
	"$TIMEOUT_BIN" "$ENGINE_TIMEOUT" "$GODOT_BIN" --headless --path "$1" \
		--script res://src/jolt_inventory.gd -- "label=$2" "out=$4" >"$3" 2>&1
}

log "run 1/2: engine defaults in an isolated temporary project"
run_inventory "$WORK_DIR/defaults" "engine-defaults" "$OUT_DIR/defaults.log" "$OUT_DIR/inventory-defaults.json"
status_defaults=$?
log "run 1/2 exit status $status_defaults (timeout bound ${ENGINE_TIMEOUT}s)"

log "run 2/2: game project settings in an isolated temporary project"
run_inventory "$WORK_DIR/main" "main-project" "$OUT_DIR/main.log" "$OUT_DIR/inventory-main.json"
status_main=$?
log "run 2/2 exit status $status_main (timeout bound ${ENGINE_TIMEOUT}s)"

failed=0
for entry in "defaults:$status_defaults:$OUT_DIR/defaults.log" "main:$status_main:$OUT_DIR/main.log"; do
	name="${entry%%:*}"
	rest="${entry#*:}"
	status="${rest%%:*}"
	log_file="${rest#*:}"
	if [ "$status" -ne 0 ]; then
		log "the $name run exited with status $status" >&2
		failed=1
	fi
	if grep -Eq "$ERROR_PATTERN" "$log_file"; then
		log "the $name run reported script errors:" >&2
		grep -En "$ERROR_PATTERN" "$log_file" >&2
		failed=1
	fi
done
[ "$failed" -eq 0 ] || die 1 "an inventory run failed (see the logs in '$OUT_DIR')"

# --- compare the two runs ----------------------------------------------------
# Normalised `name value` pairs for every Jolt setting and for the physics
# context settings that select and pace the backend. Sorted so the diff is
# stable between runs.
extract_pairs() {
	{
		grep '^setting ' "$1" | awk '{print $2, $4}'
		grep '^context_setting ' "$1" | sed 's/^context_setting //'
	} | sort
}
extract_pairs "$OUT_DIR/defaults.log" >"$WORK_DIR/defaults.pairs"
extract_pairs "$OUT_DIR/main.log" >"$WORK_DIR/main.pairs"

count_defaults="$(grep '^setting_count ' "$OUT_DIR/defaults.log" | awk '{print $2}')"
count_main="$(grep '^setting_count ' "$OUT_DIR/main.log" | awk '{print $2}')"
[ -n "$count_defaults" ] || die 1 "the defaults run printed no setting_count line"
[ -n "$count_main" ] || die 1 "the main run printed no setting_count line"
if [ "$count_defaults" != "$count_main" ]; then
	die 1 "setting counts differ between the runs ($count_defaults vs $count_main)"
fi
log "both runs read $count_defaults physics/jolt_physics_3d/* settings"

diff -u "$WORK_DIR/defaults.pairs" "$WORK_DIR/main.pairs" >"$OUT_DIR/overrides.diff" || true

# Explicit physics settings in the game project's own project.godot (a text
# scan of the copied file; the engine itself is never pointed at the project).
# Inside the [physics] section the keys carry no `physics/` prefix, so the
# Jolt block appears as `jolt_physics_3d/...`.
grep -E '^(common|2d|3d|jolt_physics_3d)/' "$PROJECT_DIR/project.godot" >"$OUT_DIR/main-project-explicit-physics.txt" || true

: >"$OUT_DIR/classification.txt"
overridden=0
context_overridden=0
while read -r name value; do
	[ -n "$name" ] || continue
	main_value="$(awk -v n="$name" '$1 == n {sub(/^[^ ]+ /, ""); print; exit}' "$WORK_DIR/main.pairs")"
	if [ "$value" = "$main_value" ]; then
		echo "$name = $value  (engine default: not set by $PROJECT_DIR/project.godot)" >>"$OUT_DIR/classification.txt"
	else
		echo "$name = $main_value  (EXPLICIT OVERRIDE: engine default is $value)" >>"$OUT_DIR/classification.txt"
		case "$name" in
		physics/jolt_physics_3d/*) overridden=$((overridden + 1)) ;;
		*) context_overridden=$((context_overridden + 1)) ;;
		esac
	fi
done <"$WORK_DIR/defaults.pairs"

# The JSON reports must be readable by anything that consumes them later.
if command -v python3 >/dev/null 2>&1; then
	for json_file in "$OUT_DIR/inventory-defaults.json" "$OUT_DIR/inventory-main.json"; do
		if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$json_file" 2>/dev/null; then
			die 1 "the JSON report '$json_file' is missing or not valid JSON"
		fi
	done
	log "both JSON reports parsed as valid JSON"
else
	log "NOTE: python3 not found; the JSON reports were not parse-checked"
fi

# --- record engine warnings, including the intermittent Jolt job warning ----
grep -h 'WARNING:' "$OUT_DIR/defaults.log" "$OUT_DIR/main.log" >"$OUT_DIR/warnings.txt" || true
job_warning_count="$(grep -ci "$JOB_WARNING_PATTERN" "$OUT_DIR/warnings.txt" || true)"
[ -n "$job_warning_count" ] || job_warning_count=0

# --- summary -----------------------------------------------------------------
log "jolt settings explicitly overridden by the game project: $overridden of $count_defaults"
log "physics context settings overridden by the game project: $context_overridden"
if [ "$overridden" -gt 0 ] || [ "$context_overridden" -gt 0 ]; then
	grep 'EXPLICIT OVERRIDE' "$OUT_DIR/classification.txt" >&2
fi
if [ -s "$OUT_DIR/main-project-explicit-physics.txt" ]; then
	log "explicit physics settings in $PROJECT_DIR/project.godot:"
	sed 's/^/    /' "$OUT_DIR/main-project-explicit-physics.txt"
else
	log "no explicit physics settings found in $PROJECT_DIR/project.godot"
fi
if [ "$job_warning_count" -gt 0 ]; then
	log "NOTE: the intermittent Jolt job-system warning appeared $job_warning_count time(s); recorded in warnings.txt, not diagnosed and not fixed here"
else
	log "the intermittent Jolt job-system warning (R7) did not appear in either run"
fi
log "engine warnings captured: $(wc -l <"$OUT_DIR/warnings.txt" | tr -d ' ') line(s)"
log "evidence written to $OUT_DIR:"
for evidence_file in "$OUT_DIR"/*; do
	[ -f "$evidence_file" ] || continue
	log "    ${evidence_file##*/}"
done

if [ "$failed" -ne 0 ]; then
	exit 1
fi
log "PASS: Jolt settings inventory recorded for $actual_version on $(host_tag)"
exit 0
