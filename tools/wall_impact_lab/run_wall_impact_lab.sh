#!/bin/sh
# Roadstorm Racer! - M1.8 wall-impact publication laboratory runner.
#
# Usage:
#   run_wall_impact_lab.sh [--project DIR] [--godot BIN] [--lock FILE]
#                          [--timeout SECONDS] [--outer-timeout SECONDS]
#                          [--log FILE] [--keep-scratch]
#
# Stages a private copy of the project into a temporary directory (never the
# live checkout), runs the required headless import there, then runs the pure
# producer validator and the deliberate failing-check probe under the pinned
# Godot 4.7.2 build. Every engine invocation is serialized on the coordinator
# godot-test lock and wrapped in an outer timeout.
#
# Exit codes: 0 = every phase passed; 1 = a phase failed; 2 = unsafe input or
# an unusable engine.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=${ROADSTORM_PROJECT:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
DEFAULT_GODOT="$PROJECT/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
GODOT_BIN=${ROADSTORM_GODOT:-$DEFAULT_GODOT}
DEFAULT_LOCK="$PROJECT/work/agents/coordinator/godot-test.lock"
LOCK_FILE=${ROADSTORM_GODOT_LOCK:-$DEFAULT_LOCK}
TIMEOUT_S=${ROADSTORM_TEST_TIMEOUT:-120}
OUTER_TIMEOUT_S=${ROADSTORM_OUTER_TIMEOUT:-600}
LOG_FILE=""
KEEP_SCRATCH=0

usage() {
	cat <<'EOF'
Usage: run_wall_impact_lab.sh [--project DIR] [--godot BIN] [--lock FILE]
                              [--timeout SECONDS] [--outer-timeout SECONDS]
                              [--log FILE] [--keep-scratch]

Stages a private copy of the project, imports it, then runs the wall-impact
producer validator and the deliberate failure probe under the pinned engine.
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
	--timeout)
		[ $# -ge 2 ] || die_usage "--timeout needs a value"
		TIMEOUT_S=$2; shift 2 ;;
	--timeout=*)
		TIMEOUT_S=${1#*=}; shift ;;
	--outer-timeout)
		[ $# -ge 2 ] || die_usage "--outer-timeout needs a value"
		OUTER_TIMEOUT_S=$2; shift 2 ;;
	--outer-timeout=*)
		OUTER_TIMEOUT_S=${1#*=}; shift ;;
	--log)
		[ $# -ge 2 ] || die_usage "--log needs a value"
		LOG_FILE=$2; shift 2 ;;
	--log=*)
		LOG_FILE=${1#*=}; shift ;;
	--keep-scratch)
		KEEP_SCRATCH=1; shift ;;
	-h | --help)
		usage; exit 0 ;;
	*)
		die_usage "unknown option: $1" ;;
	esac
done

case "$TIMEOUT_S" in
'' | *[!0-9]*)
	die_usage "--timeout must be a positive integer" ;;
esac
[ "$TIMEOUT_S" -gt 0 ] || die_usage "--timeout must be a positive integer"
case "$OUTER_TIMEOUT_S" in
'' | *[!0-9]*)
	die_usage "--outer-timeout must be a positive integer" ;;
esac
[ "$OUTER_TIMEOUT_S" -gt 0 ] || die_usage "--outer-timeout must be a positive integer"
[ "$OUTER_TIMEOUT_S" -ge "$TIMEOUT_S" ] || {
	echo "run_wall_impact_lab: --outer-timeout must be >= --timeout" >&2
	exit 2
}

[ -f "$PROJECT/project.godot" ] || {
	echo "run_wall_impact_lab: not a project root: $PROJECT" >&2
	exit 2
}
for required in src scenes tools/wall_impact_lab tools/body_lab; do
	[ -e "$PROJECT/$required" ] || {
		echo "run_wall_impact_lab: missing staged path: $PROJECT/$required" >&2
		exit 2
	}
done
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "run_wall_impact_lab: Godot binary not found: $GODOT_BIN" >&2
	exit 2
fi
[ -d "$(dirname -- "$LOCK_FILE")" ] || {
	echo "run_wall_impact_lab: lock directory missing: $(dirname -- "$LOCK_FILE")" >&2
	exit 2
}
touch "$LOCK_FILE" 2>/dev/null || {
	echo "run_wall_impact_lab: cannot create lock file: $LOCK_FILE" >&2
	exit 2
}

PINNED="4.7.2.stable.official.ed1daf0bf"
if [ -r "$PROJECT/tools/toolchain/pin/engine.txt" ]; then
	PINNED_FROM_FILE=$(sed -n 's/^version_string=//p' "$PROJECT/tools/toolchain/pin/engine.txt" | head -n 1)
	[ -n "$PINNED_FROM_FILE" ] && PINNED=$PINNED_FROM_FILE
fi

error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

# run_godot <logfile> <command...>: one serialized, outer-bounded engine call.
# Uses coreutils timeout when present and the portable background watchdog
# otherwise, so the shared lock and the outer bound hold on stock macOS.
run_godot() {
	_out=$1
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout -k 10 "$OUTER_TIMEOUT_S" lockf -k -w -t 600 "$LOCK_FILE" "$@" >>"$_out" 2>&1
		return $?
	fi
	lockf -k -w -t 600 "$LOCK_FILE" "$@" >>"$_out" 2>&1 &
	_pid=$!
	(
		sleep "$OUTER_TIMEOUT_S" 2>/dev/null
		kill -TERM "$_pid" 2>/dev/null
		sleep 3 2>/dev/null
		kill -KILL "$_pid" 2>/dev/null
	) >/dev/null 2>&1 &
	_watch=$!
	wait "$_pid" 2>/dev/null
	_rc=$?
	kill "$_watch" 2>/dev/null
	wait "$_watch" 2>/dev/null
	return "$_rc"
}

stage=$(mktemp -d "${TMPDIR:-/tmp}/wall-impact-lab-stage.XXXXXX" 2>/dev/null) || {
	echo "run_wall_impact_lab: cannot create staging directory" >&2
	exit 2
}
cleanup() {
	if [ "$KEEP_SCRATCH" -eq 0 ] && [ -n "$stage" ] && [ -d "$stage" ]; then
		rm -rf "$stage"
	fi
}
trap cleanup EXIT HUP INT TERM

echo "[run-wall-impact] staging isolated copy in $stage"
cp "$PROJECT/project.godot" "$stage/" || exit 2
for path in src scenes assets; do
	cp -R "$PROJECT/$path" "$stage/$path" || exit 2
done
mkdir -p "$stage/tools" || exit 2
cp -R "$PROJECT/tools/wall_impact_lab" "$stage/tools/wall_impact_lab" || exit 2
cp -R "$PROJECT/tools/body_lab" "$stage/tools/body_lab" || exit 2
find "$stage" -type d -name .godot -prune -exec rm -rf {} + 2>/dev/null

version_log="$stage/version.log"
: >"$version_log"
echo "[run-wall-impact] checking engine version"
run_godot "$version_log" "$GODOT_BIN" --version || {
	echo "run_wall_impact_lab: engine --version failed or timed out" >&2
	tail -n 20 "$version_log" >&2
	exit 2
}
actual_version=$(tail -n 1 "$version_log")
case "$actual_version" in
*"$PINNED"*) ;;
*)
	echo "run_wall_impact_lab: engine is not the pinned $PINNED (got: $actual_version)" >&2
	exit 2
;;
esac
echo "[run-wall-impact] engine $actual_version"

import_log="$stage/import.log"
: >"$import_log"
echo "[run-wall-impact] importing staged project"
run_godot "$import_log" "$GODOT_BIN" --headless --path "$stage" --import || {
	echo "run_wall_impact_lab: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
}
if grep -nE "$error_re" "$import_log"; then
	echo "run_wall_impact_lab: import log reported engine errors" >&2
	exit 1
fi

status=0

validator_log="$stage/validator.log"
: >"$validator_log"
echo "[run-wall-impact] running wall-impact producer validator"
run_godot "$validator_log" "$GODOT_BIN" --headless --fixed-fps 60 \
	--path "$stage" --script res://tools/wall_impact_lab/validate_wall_impact_lab.gd
validator_rc=$?
[ "$validator_rc" -eq 0 ] || status=1
if grep -nE "$error_re" "$validator_log"; then
	echo "run_wall_impact_lab: validator log reported engine errors" >&2
	status=1
fi
validator_summary=$(grep '^WALL_IMPACT_LAB_SUMMARY ' "$validator_log" | tail -n 1)
if [ -z "$validator_summary" ]; then
	echo "run_wall_impact_lab: validator produced no WALL_IMPACT_LAB_SUMMARY" >&2
	status=1
fi
case "$validator_summary" in
*'"pass":true'*) ;;
*)
	echo "run_wall_impact_lab: validator did not report pass=true" >&2
	status=1 ;;
esac
validator_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$validator_log" | tail -n 1)
if [ "$validator_failed" != "0" ]; then
	echo "run_wall_impact_lab: validator reported CHECKS_FAILED=$validator_failed" >&2
	status=1
fi
echo "[run-wall-impact] validator rc=$validator_rc"
tail -n 80 "$validator_log"

probe_log="$stage/failure_probe.log"
: >"$probe_log"
echo "[run-wall-impact] running deliberate failure probe (nonzero exit expected)"
run_godot "$probe_log" "$GODOT_BIN" --headless --fixed-fps 60 \
	--path "$stage" --script res://tools/wall_impact_lab/failure_probe.gd
probe_rc=$?
if [ "$probe_rc" -eq 0 ]; then
	echo "run_wall_impact_lab: failure probe exited 0; failing checks are not detectable" >&2
	status=1
fi
probe_result=$(grep '^WALL_IMPACT_PROBE_RESULT ' "$probe_log" | tail -n 1)
case "$probe_result" in
*'"pass":false'*) ;;
*)
	echo "run_wall_impact_lab: failure probe did not report pass=false" >&2
	status=1
;;
esac
echo "[run-wall-impact] failure probe rc=$probe_rc"
tail -n 20 "$probe_log"

if [ -n "$LOG_FILE" ]; then
	tail -c 2097152 "$validator_log" >"$LOG_FILE" || status=1
	echo "[run-wall-impact] validator log copied to $LOG_FILE (bounded to 2 MiB)"
fi

if [ "$KEEP_SCRATCH" -eq 1 ]; then
	echo "[run-wall-impact] logs kept in $stage"
fi

if [ "$status" -eq 0 ]; then
	echo "[run-wall-impact] PASS (isolated project: $stage)"
else
	echo "[run-wall-impact] FAIL (isolated project: $stage)" >&2
fi
exit "$status"
