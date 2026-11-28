#!/bin/sh
# Roadstorm Racer! - bounded 30/60/120 FPS numerical frame-trace preflight.
#
# Usage:
#   tools/frame_trace_lab/run_frame_trace_lab.sh [--project DIR] [--godot BIN]
#       [--lock FILE] [--work-root DIR] [--timeout SECONDS]
#       [--lock-wait SECONDS] [--outer-timeout SECONDS]
#
# The runner exports a plain frozen `git archive HEAD` source tree into a fresh
# ignored scratch directory, overlays the current tools/frame_trace_lab files,
# imports that private copy, and runs the committed DriveLab scene once for each
# nominal --fixed-fps mode. It also runs the driver's drop and short negative
# control variants and checks that the comparator rejects them plus missing,
# corrupt and deliberately deviating inputs.
#
# Exit 0 means the positive comparison passed and every negative control was
# rejected. Exit 1 means a validation/comparison failure. Exit 2 means unsafe
# input, missing tools or an unusable engine. Scratch, logs, private HOME/TMPDIR
# and XDG directories stay under the selected ignored work root for inspection.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=${ROADSTORM_PROJECT:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
DEFAULT_GODOT="$PROJECT/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
GODOT_BIN=${ROADSTORM_GODOT:-$DEFAULT_GODOT}
DEFAULT_LOCK="$PROJECT/work/agents/coordinator/godot-test.lock"
LOCK_FILE=${ROADSTORM_GODOT_LOCK:-$DEFAULT_LOCK}
WORK_ROOT=${FRAME_TRACE_WORK_ROOT:-$PROJECT/work/frame_trace_lab}
TIMEOUT_S=${ROADSTORM_TEST_TIMEOUT:-120}
LOCK_WAIT_S=${ROADSTORM_LOCK_WAIT:-600}
OUTER_TIMEOUT_S=${ROADSTORM_OUTER_TIMEOUT:-760}

usage() {
	cat <<'EOF'
Usage: run_frame_trace_lab.sh [--project DIR] [--godot BIN] [--lock FILE]
       [--work-root DIR] [--timeout SECONDS] [--lock-wait SECONDS]
       [--outer-timeout SECONDS]

Runs a frozen-source DriveLab frame trace at nominal --fixed-fps 30, 60 and
120, compares the three traces, and proves the comparator rejects negative
controls. --work-root must resolve under the repository's ignored work/ tree.
EOF
}

die_usage() {
	echo "$1" >&2
	usage >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--project)
		[ $# -ge 2 ] || die_usage "--project needs a value"
		PROJECT=$2; shift 2 ;;
	--project=*)
		PROJECT=${1#*=}; shift ;;
	--godot)
		[ $# -ge 2 ] || die_usage "--godot needs a value"
		GODOT_BIN=$2; shift 2 ;;
	--godot=*)
		GODOT_BIN=${1#*=}; shift ;;
	--lock)
		[ $# -ge 2 ] || die_usage "--lock needs a value"
		LOCK_FILE=$2; shift 2 ;;
	--lock=*)
		LOCK_FILE=${1#*=}; shift ;;
	--work-root)
		[ $# -ge 2 ] || die_usage "--work-root needs a value"
		WORK_ROOT=$2; shift 2 ;;
	--work-root=*)
		WORK_ROOT=${1#*=}; shift ;;
	--timeout)
		[ $# -ge 2 ] || die_usage "--timeout needs a value"
		TIMEOUT_S=$2; shift 2 ;;
	--timeout=*)
		TIMEOUT_S=${1#*=}; shift ;;
	--lock-wait)
		[ $# -ge 2 ] || die_usage "--lock-wait needs a value"
		LOCK_WAIT_S=$2; shift 2 ;;
	--lock-wait=*)
		LOCK_WAIT_S=${1#*=}; shift ;;
	--outer-timeout)
		[ $# -ge 2 ] || die_usage "--outer-timeout needs a value"
		OUTER_TIMEOUT_S=$2; shift 2 ;;
	--outer-timeout=*)
		OUTER_TIMEOUT_S=${1#*=}; shift ;;
	-h | --help)
		usage; exit 0 ;;
	*)
		die_usage "unknown option: $1" ;;
	esac
done

positive_integer() {
	case "$1" in
	'' | *[!0-9]*) return 1 ;;
	esac
	[ "$1" -gt 0 ]
}

positive_integer "$TIMEOUT_S" || die_usage "--timeout must be a positive integer"
positive_integer "$LOCK_WAIT_S" || die_usage "--lock-wait must be a positive integer"
positive_integer "$OUTER_TIMEOUT_S" || die_usage "--outer-timeout must be a positive integer"
if [ "$OUTER_TIMEOUT_S" -lt $((LOCK_WAIT_S + TIMEOUT_S + 10)) ]; then
	echo "run_frame_trace_lab: --outer-timeout must be at least lock-wait + timeout + 10 seconds" >&2
	exit 2
fi

for tool in git tar timeout lockf python3 shasum; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "run_frame_trace_lab: required tool missing from PATH: $tool" >&2
		exit 2
	}
done
[ -f "$PROJECT/project.godot" ] || {
	echo "run_frame_trace_lab: not a project root: $PROJECT" >&2
	exit 2
}
[ -d "$PROJECT/tools/frame_trace_lab" ] || {
	echo "run_frame_trace_lab: missing tools/frame_trace_lab under $PROJECT" >&2
	exit 2
}
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "run_frame_trace_lab: Godot binary not found: $GODOT_BIN" >&2
	exit 2
fi
[ -d "$(dirname -- "$LOCK_FILE")" ] || {
	echo "run_frame_trace_lab: lock directory missing: $(dirname -- "$LOCK_FILE")" >&2
	exit 2
}
touch "$LOCK_FILE" 2>/dev/null || {
	echo "run_frame_trace_lab: cannot create shared lock file: $LOCK_FILE" >&2
	exit 2
}

mkdir -p "$WORK_ROOT" 2>/dev/null || {
	echo "run_frame_trace_lab: cannot create work root: $WORK_ROOT" >&2
	exit 2
}
PROJECT_CANON=$(CDPATH= cd -- "$PROJECT" 2>/dev/null && pwd -P) || {
	echo "run_frame_trace_lab: cannot resolve project root: $PROJECT" >&2
	exit 2
}
WORK_CANON=$(CDPATH= cd -- "$WORK_ROOT" 2>/dev/null && pwd -P) || {
	echo "run_frame_trace_lab: cannot resolve work root: $WORK_ROOT" >&2
	exit 2
}
case "$WORK_CANON" in
"$PROJECT_CANON/work" | "$PROJECT_CANON/work"/*) ;;
*)
	echo "run_frame_trace_lab: --work-root must stay under ignored $PROJECT_CANON/work" >&2
	exit 2
;;
esac

RUN_DIR=$(mktemp -d "$WORK_CANON/run.XXXXXX" 2>/dev/null) || {
	echo "run_frame_trace_lab: cannot create a fresh run directory under $WORK_CANON" >&2
	exit 2
}
RUN_DIR=$(CDPATH= cd -- "$RUN_DIR" 2>/dev/null && pwd -P) || exit 2
STAGE="$RUN_DIR/stage"
RESULTS="$RUN_DIR/results"
LOGS="$RUN_DIR/logs"
SUMMARY="$RUN_DIR/summary.txt"
CURRENT_PIDFILE=""

mkdir -p "$STAGE" "$RESULTS" "$LOGS" \
	"$RUN_DIR/home" "$RUN_DIR/tmp" "$RUN_DIR/xdg-cache" "$RUN_DIR/xdg-config" "$RUN_DIR/xdg-data" || exit 2
: >"$SUMMARY"

export HOME="$RUN_DIR/home"
export TMPDIR="$RUN_DIR/tmp"
export XDG_CACHE_HOME="$RUN_DIR/xdg-cache"
export XDG_CONFIG_HOME="$RUN_DIR/xdg-config"
export XDG_DATA_HOME="$RUN_DIR/xdg-data"
export PYTHONDONTWRITEBYTECODE=1

# Stop only the one engine child whose exact PID this runner's exec wrapper
# wrote. Never signals processes by name or pattern.
stop_exact_child() {
	_pidfile=$1
	_child=$(cat "$_pidfile" 2>/dev/null || true)
	case "$_child" in
	'' | *[!0-9]*) return 0 ;;
	esac
	if kill -0 "$_child" 2>/dev/null; then
		kill -TERM "$_child" 2>/dev/null || true
		sleep 1
		kill -KILL "$_child" 2>/dev/null || true
		echo "[frame-trace] stopped stranded exact Godot child $_child" >&2
	fi
}

stop_current_child() {
	if [ -n "$CURRENT_PIDFILE" ]; then
		stop_exact_child "$CURRENT_PIDFILE"
	fi
}
trap stop_current_child EXIT HUP INT TERM

fatal() {
	_code=$1
	shift
	echo "run_frame_trace_lab: $*" >&2
	echo "runner_error=$*" >>"$SUMMARY"
	exit "$_code"
}

# run_godot <pidfile> <logfile> <command...>: one serialized, outer-bounded
# engine invocation. The inner shell records its PID and execs the command, so
# the watchdog can terminate exactly that process rather than pattern-matching.
run_godot() {
	_pidfile=$1
	_out=$2
	shift 2
	: >"$_pidfile"
	CURRENT_PIDFILE=$_pidfile
	timeout -k 5 "$TIMEOUT_S" \
		sh -c 'echo $$ > "$1"; shift; exec "$@"' _ "$_pidfile" "$@" >>"$_out" 2>&1 &
	_wrapper=$!
	(
		exec 9>&-
		sleep "$OUTER_TIMEOUT_S" 2>/dev/null
		if kill -0 "$_wrapper" 2>/dev/null; then
			stop_exact_child "$_pidfile"
			kill -TERM "$_wrapper" 2>/dev/null || true
			sleep 1
			kill -KILL "$_wrapper" 2>/dev/null || true
		fi
	) >/dev/null 2>&1 &
	_watch=$!
	wait "$_wrapper" 2>/dev/null
	_rc=$?
	kill "$_watch" 2>/dev/null || true
	wait "$_watch" 2>/dev/null || true
	stop_exact_child "$_pidfile"
	CURRENT_PIDFILE=""
	return "$_rc"
}

engine_log_clean() {
	_log=$1
	if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|^ERROR:|^USER ERROR:|^FATAL' "$_log"; then
		return 1
	fi
	return 0
}

echo "[frame-trace] run directory: $RUN_DIR"
echo "run_dir=$RUN_DIR" >>"$SUMMARY"

# Freeze the committed source with the required plain archive. Git is used only
# for read-only source export; no branch, worktree, index or repository state is
# changed.
HEAD_SHA=$(timeout -k 3 30 git -C "$PROJECT" rev-parse HEAD 2>"$LOGS/git-revparse.log") || \
	fatal 2 "git rev-parse HEAD failed; see $LOGS/git-revparse.log"
echo "source_head_sha=$HEAD_SHA" >>"$SUMMARY"
ARCHIVE="$RUN_DIR/source.tar"
timeout -k 3 60 git -C "$PROJECT" archive --format=tar HEAD >"$ARCHIVE" 2>"$LOGS/git-archive.log" || \
	fatal 2 "git archive HEAD failed; see $LOGS/git-archive.log"
timeout -k 3 60 tar -xf "$ARCHIVE" -C "$STAGE" 2>"$LOGS/tar-extract.log" || \
	fatal 2 "archive extraction failed; see $LOGS/tar-extract.log"
[ -f "$STAGE/project.godot" ] || fatal 2 "frozen archive did not contain project.godot"
[ ! -e "$STAGE/.git" ] || fatal 2 "frozen archive unexpectedly contains .git"

OVERLAY_FILES="frame_trace_driver.gd frame_trace_entry.gd compare_frame_traces.py run_frame_trace_lab.sh README.md"
mkdir -p "$STAGE/tools/frame_trace_lab" || exit 2
for _file in $OVERLAY_FILES; do
	[ -f "$PROJECT/tools/frame_trace_lab/$_file" ] || fatal 2 "missing overlay file tools/frame_trace_lab/$_file"
	cp "$PROJECT/tools/frame_trace_lab/$_file" "$STAGE/tools/frame_trace_lab/$_file" || \
		fatal 2 "could not overlay tools/frame_trace_lab/$_file"
done
(
	cd "$PROJECT/tools/frame_trace_lab" && timeout -k 3 30 shasum -a 256 $OVERLAY_FILES
) >"$RUN_DIR/frame_trace_lab.sha256" 2>"$LOGS/shasum.log" || \
	fatal 2 "could not hash frame_trace_lab files; see $LOGS/shasum.log"

# Hold the shared lock once for the bounded version/import/trace sequence.
# Reacquiring it for every short launch would make this multi-run preflight
# depend on unrelated queue timing; holding it never widens the critical section
# beyond this runner's bounded commands. Descriptor locks are released by the
# kernel if this shell exits or is killed.
exec 9<>"$LOCK_FILE" 2>"$LOGS/lock-open.log" || \
	fatal 2 "cannot open shared lock file: $LOCK_FILE"
if ! lockf -s -t "$LOCK_WAIT_S" 9 2>"$LOGS/lock-acquire.log"; then
	fatal 2 "timed out after ${LOCK_WAIT_S}s waiting for shared lock: $LOCK_FILE"
fi
echo "shared_lock_acquired=$LOCK_FILE" >>"$SUMMARY"

PINNED="4.7.2.stable.official.ed1daf0bf"
if [ -r "$STAGE/tools/toolchain/pin/engine.txt" ]; then
	PINNED_FROM_FILE=$(sed -n 's/^version_string=//p' "$STAGE/tools/toolchain/pin/engine.txt" | head -n 1)
	[ -n "$PINNED_FROM_FILE" ] && PINNED=$PINNED_FROM_FILE
fi

echo "[frame-trace] checking pinned engine"
VERSION_LOG="$LOGS/godot-version.log"
: >"$VERSION_LOG"
run_godot "$RUN_DIR/version.pid" "$VERSION_LOG" "$GODOT_BIN" --version || \
	fatal 2 "engine --version failed or timed out; see $VERSION_LOG"
ACTUAL_VERSION=$(tail -n 1 "$VERSION_LOG")
case "$ACTUAL_VERSION" in
*"$PINNED"*) ;;
*)
	fatal 2 "engine is not pinned $PINNED (got: $ACTUAL_VERSION)"
;;
esac
echo "godot_version=$ACTUAL_VERSION" >>"$SUMMARY"

echo "[frame-trace] importing frozen private project"
IMPORT_LOG="$LOGS/godot-import.log"
: >"$IMPORT_LOG"
run_godot "$RUN_DIR/import.pid" "$IMPORT_LOG" "$GODOT_BIN" --headless --path "$STAGE" --import || \
	fatal 1 "headless import failed or timed out; see $IMPORT_LOG"
engine_log_clean "$IMPORT_LOG" || fatal 1 "headless import reported engine errors; see $IMPORT_LOG"
echo "import_rc=0" >>"$SUMMARY"

run_trace() {
	_variant=$1
	_fps=$2
	_label=${3:-$_fps}
	_name=${4:-"${_variant}-${_fps}"}
	_result="$RESULTS/$_name.json"
	_log="$LOGS/godot-$_name.log"
	: >"$_result"
	: >"$_log"
	echo "[frame-trace] running variant=$_variant fixed-fps=$_fps label=$_label"
	run_godot "$RUN_DIR/$_name.pid" "$_log" \
		env FTP_FPS="$_label" FTP_VARIANT="$_variant" FTP_RESULT="$_result" \
		"$GODOT_BIN" --headless --fixed-fps "$_fps" --path "$STAGE" \
		--script res://tools/frame_trace_lab/frame_trace_entry.gd
	_rc=$?
	echo "godot_${_name}_rc=$_rc" >>"$SUMMARY"
	if [ "$_rc" -ne 0 ]; then
		fatal 1 "Godot $_name exited $_rc; see $_log"
	fi
	if ! engine_log_clean "$_log"; then
		fatal 1 "Godot $_name reported engine errors; see $_log"
	fi
	if [ ! -s "$_result" ]; then
		fatal 1 "Godot $_name wrote no result JSON; see $_log"
	fi
	if ! grep -q '^FRAME_TRACE_RESULT ' "$_log"; then
		fatal 1 "Godot $_name produced no FRAME_TRACE_RESULT line; see $_log"
	fi
	timeout -k 3 30 python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$_result" \
		>/dev/null 2>"$LOGS/json-$_name.log" || \
		fatal 1 "Godot $_name wrote corrupt JSON; see $LOGS/json-$_name.log"
}

for _fps in 30 60 120; do
	run_trace full "$_fps"
done
run_trace drop 60
run_trace short 60
# Deliberate cadence substitution: the engine is actually launched at
# --fixed-fps 30 while the harness label and recorded argument claim 60.
run_trace full 30 60 wrong-cadence-30-as-60

run_comparator() {
	_name=$1
	shift
	_log="$LOGS/compare-$_name.log"
	: >"$_log"
	timeout -k 3 30 env PYTHONDONTWRITEBYTECODE=1 \
		python3 "$STAGE/tools/frame_trace_lab/compare_frame_traces.py" "$@" >"$_log" 2>&1
	_rc=$?
	echo "compare_${_name}_rc=$_rc" >>"$SUMMARY"
	return "$_rc"
}

echo "[frame-trace] comparing full 30/60/120 traces"
run_comparator positive \
	"$RESULTS/full-30.json" "$RESULTS/full-60.json" "$RESULTS/full-120.json"
POSITIVE_RC=$?

echo "[frame-trace] preparing negative-control inputs"
CONTROL_PY_LOG="$LOGS/control-fixtures.log"
: >"$CONTROL_PY_LOG"
timeout -k 3 30 python3 - "$RESULTS" <<'PY' >"$CONTROL_PY_LOG" 2>&1
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])

def load(name):
    with (root / name).open("r", encoding="utf-8") as handle:
        return json.load(handle)

def write(name, data):
    with (root / name).open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")

def strip_control(src, dst):
    data = load(src)
    data["mode"]["variant"] = "full"
    data["mode"]["control"] = False
    data["mode"]["control_note"] = ""
    write(dst, data)

strip_control("drop-60.json", "drop-as-full-60.json")
strip_control("short-60.json", "short-as-full-60.json")

deviating = load("full-60.json")
deviating["endpoint"]["position_m"][1] += 0.5
deviating["endpoint"]["road_station_m"] += 0.5
deviating["endpoint"]["trace_station_m"] += 0.5
for entry in deviating["tick_trace"]:
    entry["road_station_m"] += 0.5
for entry in deviating["tick_trace"]:
    if entry["road_station_m"] >= 100.0:
        deviating["gate"]["first_committed_tick"] = entry["tick"]
        break
write("deviation-as-full-60.json", deviating)

hidden_gate = load("full-60.json")
for entry in hidden_gate["tick_trace"]:
    if entry["tick"] in (357, 358):
        entry["road_station_m"] = 99.99
write("hidden-gate-as-full-60.json", hidden_gate)

stale_gate = load("full-60.json")
stale_gate["gate"]["first_committed_tick"] += 1
write("stale-gate-as-full-60.json", stale_gate)

bad_type = load("full-60.json")
bad_type["mode"]["nominal_fixed_fps"] = []
write("bad-type-as-full-60.json", bad_type)

float_gate = load("full-60.json")
float_gate["tick_trace"][356]["tick"] = 357.0
float_gate["gate"]["first_committed_tick"] = 358
write("float-gate-as-full-60.json", float_gate)

impossible_counters = load("full-60.json")
impossible_counters["timing"]["physics_frames"] = 1
impossible_counters["timing"]["process_frames"] = 1
write("impossible-counters-as-full-60.json", impossible_counters)

overflow_counter = load("full-60.json")
overflow_counter["timing"]["physics_frames"] = 10**400
write("overflow-counter-as-full-60.json", overflow_counter)

host_mismatch = load("full-60.json")
host_mismatch["host"]["processor_count"] += 1
write("host-mismatch-as-full-60.json", host_mismatch)

engine_version_mismatch = load("full-60.json")
engine_version_mismatch["engine"]["version"]["patch"] += 1
write("engine-version-as-full-60.json", engine_version_mismatch)

engine_backend_mismatch = load("full-60.json")
engine_backend_mismatch["engine"]["backend"] = "wrong backend"
write("engine-backend-as-full-60.json", engine_backend_mismatch)

with (root / "corrupt-60.json").open("w", encoding="utf-8") as handle:
    handle.write('{"schema":')
print("control fixtures written")
PY
_control_fixture_rc=$?
echo "control_fixture_rc=$_control_fixture_rc" >>"$SUMMARY"
[ "$_control_fixture_rc" -eq 0 ] || fatal 1 "could not create negative-control inputs; see $CONTROL_PY_LOG"

CONTROLS_OK=1
expect_compare_failure() {
	_name=$1
	_reason=$2
	shift 2
	echo "[frame-trace] negative control: $_name"
	run_comparator "$_name" "$@"
	_rc=$?
	if [ "$_rc" -eq 1 ] \
		&& grep -q '^COMPARISON_RESULT .*"pass":false' "$LOGS/compare-$_name.log" \
		&& grep -q '^COMPARISON FAIL$' "$LOGS/compare-$_name.log" \
		&& grep -Fq "$_reason" "$LOGS/compare-$_name.log"; then
		if grep -q 'Traceback (most recent call last)' "$LOGS/compare-$_name.log"; then
			echo "compare_${_name}_rejected=no_traceback" >>"$SUMMARY"
			CONTROLS_OK=0
		else
			echo "compare_${_name}_rejected=yes" >>"$SUMMARY"
		fi
	else
		echo "compare_${_name}_rejected=no_rc$_rc" >>"$SUMMARY"
		CONTROLS_OK=0
	fi
}

expect_compare_failure missing "missing input file:" \
	"$RESULTS/full-30.json" "$RESULTS/missing-60.json" "$RESULTS/full-120.json"
expect_compare_failure corrupt "corrupt input file" \
	"$RESULTS/full-30.json" "$RESULTS/corrupt-60.json" "$RESULTS/full-120.json"
expect_compare_failure drop "command does not match the fixed full schedule" \
	"$RESULTS/full-30.json" "$RESULTS/drop-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure short "ticks_committed is 1199, expected 1200" \
	"$RESULTS/full-30.json" "$RESULTS/short-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure deviation "endpoint position differs by 0.5 m" \
	"$RESULTS/full-30.json" "$RESULTS/deviation-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure wrong-cadence "observed physics/process frame ratio" \
	"$RESULTS/full-30.json" "$RESULTS/wrong-cadence-30-as-60.json" "$RESULTS/full-120.json"
expect_compare_failure hidden-gate \
	"gate.first_committed_tick is 357, but committed tick_trace first reaches 100.0 m at tick 359" \
	"$RESULTS/full-30.json" "$RESULTS/hidden-gate-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure stale-gate \
	"gate.first_committed_tick is 358, but committed tick_trace first reaches 100.0 m at tick 357" \
	"$RESULTS/full-30.json" "$RESULTS/stale-gate-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure bad-type "nominal_fixed_fps is [], expected one of" \
	"$RESULTS/full-30.json" "$RESULTS/bad-type-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure float-gate "tick field is 357.0, expected integer 357" \
	"$RESULTS/full-30.json" "$RESULTS/float-gate-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure impossible-counters \
	"timing.physics_frames is outside the plausible full-run range [1200, 1208]" \
	"$RESULTS/full-30.json" "$RESULTS/impossible-counters-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure overflow-counter \
	"timing.physics_frames is outside the plausible full-run range [1200, 1208]" \
	"$RESULTS/full-30.json" "$RESULTS/overflow-counter-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure host-cohort "host cohort differs between inputs" \
	"$RESULTS/full-30.json" "$RESULTS/host-mismatch-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure engine-version "engine version is" \
	"$RESULTS/full-30.json" "$RESULTS/engine-version-as-full-60.json" "$RESULTS/full-120.json"
expect_compare_failure engine-backend "engine backend is" \
	"$RESULTS/full-30.json" "$RESULTS/engine-backend-as-full-60.json" "$RESULTS/full-120.json"

if [ "$POSITIVE_RC" -eq 0 ]; then
	echo "positive_comparison=pass" >>"$SUMMARY"
else
	echo "positive_comparison=fail_rc$POSITIVE_RC" >>"$SUMMARY"
fi
if [ "$CONTROLS_OK" -eq 1 ]; then
	echo "negative_controls=all_rejected" >>"$SUMMARY"
else
	echo "negative_controls=not_all_rejected" >>"$SUMMARY"
fi

(
	cd "$RESULTS" && timeout -k 3 30 shasum -a 256 *.json
) >"$RUN_DIR/result-hashes.sha256" 2>"$LOGS/result-shasum.log" || true

echo "[frame-trace] positive comparator output:"
cat "$LOGS/compare-positive.log"
echo "[frame-trace] summary: $SUMMARY"

if [ "$POSITIVE_RC" -eq 0 ] && [ "$CONTROLS_OK" -eq 1 ]; then
	echo "FRAME_TRACE_LAB PASS run_dir=$RUN_DIR"
	exit 0
fi

echo "FRAME_TRACE_LAB FAIL run_dir=$RUN_DIR" >&2
exit 1
