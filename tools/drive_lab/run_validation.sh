#!/bin/sh
# Bounded isolated runner for the M1 one-car drive laboratory.
#
# Usage:
#   tools/drive_lab/run_validation.sh [--project DIR] [--godot BIN]
#       [--timeout SECONDS] [--log FILE] [--keep-scratch]
#
# Stages a private copy of the project, imports it, then runs the headless
# validator, the separate bad-config atomic-refusal fixture, and the
# deliberate failing-check probe. Every engine invocation has a wall-clock
# watchdog, engine error lines are gated, and only a bounded log tail is
# printed. Exit 0 means every check passed and the failure probe failed as
# expected; 1 means a check or gate failed; 2 means unsafe inputs or an
# unusable engine.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=${ROADSTORM_PROJECT:-$(CDPATH= cd -- "$script_dir/../.." && pwd)}
default_godot="$project/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
godot_bin=${ROADSTORM_GODOT:-$default_godot}
timeout_s=${ROADSTORM_TEST_TIMEOUT:-240}
keep_scratch=0
log_file=""

usage() {
	cat <<'EOF'
Usage: run_validation.sh [--project DIR] [--godot BIN]
                         [--timeout SECONDS] [--log FILE] [--keep-scratch]

Stages a private copy of the project, imports it, and runs the drive-lab
validator, bad-config atomicity fixture and deliberate failure probe under a
wall-clock watchdog.
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
		project=$2; shift 2 ;;
	--project=*)
		project=${1#*=}; shift ;;
	--godot)
		[ $# -ge 2 ] || die_usage "--godot needs a value"
		godot_bin=$2; shift 2 ;;
	--godot=*)
		godot_bin=${1#*=}; shift ;;
	--timeout)
		[ $# -ge 2 ] || die_usage "--timeout needs a value"
		timeout_s=$2; shift 2 ;;
	--timeout=*)
		timeout_s=${1#*=}; shift ;;
	--log)
		[ $# -ge 2 ] || die_usage "--log needs a value"
		log_file=$2; shift 2 ;;
	--log=*)
		log_file=${1#*=}; shift ;;
	--keep-scratch)
		keep_scratch=1; shift ;;
	-h | --help)
		usage; exit 0 ;;
	*)
		die_usage "unknown option: $1" ;;
	esac
done

case "$timeout_s" in
'' | *[!0-9]*)
	die_usage "--timeout must be a positive integer" ;;
esac
[ "$timeout_s" -gt 0 ] || die_usage "--timeout must be a positive integer"

[ -f "$project/project.godot" ] || {
	echo "run_validation: not a project root: $project" >&2
	exit 2
}
for required in src scenes tools/drive_lab; do
	[ -e "$project/$required" ] || {
		echo "run_validation: missing staged path: $project/$required" >&2
		exit 2
	}
done
if [ ! -x "$godot_bin" ] && ! command -v "$godot_bin" >/dev/null 2>&1; then
	echo "run_validation: Godot binary not found: $godot_bin" >&2
	exit 2
fi

pinned="4.7.2.stable.official.ed1daf0bf"
if [ -r "$project/tools/toolchain/pin/engine.txt" ]; then
	pinned_from_file=$(sed -n 's/^version_string=//p' "$project/tools/toolchain/pin/engine.txt" | head -n 1)
	[ -n "$pinned_from_file" ] && pinned=$pinned_from_file
fi

error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

# Portable bounded watchdog: macOS has no coreutils timeout.
run_bounded() {
	_limit=$1
	_out=$2
	shift 2
	"$@" >>"$_out" 2>&1 &
	_pid=$!
	(
		sleep "$_limit" 2>/dev/null
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

stage=$(mktemp -d "${TMPDIR:-/tmp}/drive-lab-stage.XXXXXX" 2>/dev/null) || {
	echo "run_validation: cannot create staging directory" >&2
	exit 2
}
cleanup() {
	if [ "$keep_scratch" -eq 0 ] && [ -n "$stage" ] && [ -d "$stage" ]; then
		rm -rf "$stage"
	fi
}
trap cleanup EXIT HUP INT TERM

echo "[run-validation] staging isolated copy in $stage"
cp "$project/project.godot" "$stage/" || exit 2
cp -R "$project/src" "$stage/src" || exit 2
cp -R "$project/scenes" "$stage/scenes" || exit 2
mkdir -p "$stage/tools" || exit 2
cp -R "$project/tools/drive_lab" "$stage/tools/drive_lab" || exit 2
find "$stage" -type d -name .godot -prune -exec rm -rf {} + 2>/dev/null

version_log="$stage/version.log"
: >"$version_log"
run_bounded 60 "$version_log" "$godot_bin" --version || {
	echo "run_validation: engine --version failed or timed out" >&2
	tail -n 20 "$version_log" >&2
	exit 2
}
actual_version=$(tail -n 1 "$version_log")
case "$actual_version" in
*"$pinned"*) ;;
*)
	echo "run_validation: engine is not the pinned $pinned (got: $actual_version)" >&2
	exit 2 ;;
esac
echo "[run-validation] engine $actual_version"

import_log="$stage/import.log"
: >"$import_log"
echo "[run-validation] importing staged project"
run_bounded "$timeout_s" "$import_log" "$godot_bin" --headless --path "$stage" --import || {
	echo "run_validation: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
}
if grep -nE "$error_re" "$import_log"; then
	echo "run_validation: import log reported engine errors" >&2
	exit 1
fi

status=0

validator_log="$stage/validator.log"
: >"$validator_log"
echo "[run-validation] running drive-lab validator"
run_bounded "$timeout_s" "$validator_log" "$godot_bin" --headless --fixed-fps 60 \
	--path "$stage" --script res://tools/drive_lab/validate_drive_lab.gd
validator_rc=$?
[ "$validator_rc" -eq 0 ] || status=1
if grep -nE "$error_re" "$validator_log"; then
	echo "run_validation: validator log reported engine errors" >&2
	status=1
fi
validator_summary=$(grep '^DRIVE_LAB_SUMMARY ' "$validator_log" | tail -n 1)
if [ -z "$validator_summary" ]; then
	echo "run_validation: validator produced no DRIVE_LAB_SUMMARY" >&2
	status=1
fi
case "$validator_summary" in
*'"pass":true'*) ;;
*)
	echo "run_validation: validator did not report pass=true" >&2
	status=1 ;;
esac
validator_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$validator_log" | tail -n 1)
if [ "$validator_failed" != "0" ]; then
	echo "run_validation: validator reported CHECKS_FAILED=$validator_failed" >&2
	status=1
fi
echo "[run-validation] validator tail:"
tail -n 80 "$validator_log"

fixture_log="$stage/bad_config_fixture.log"
: >"$fixture_log"
echo "[run-validation] running bad-config atomicity fixture"
run_bounded "$timeout_s" "$fixture_log" "$godot_bin" --headless --fixed-fps 60 \
	--path "$stage" --script res://tools/drive_lab/bad_config_fixture.gd
fixture_rc=$?
[ "$fixture_rc" -eq 0 ] || status=1
if grep -nE "$error_re" "$fixture_log"; then
	echo "run_validation: bad-config fixture reported engine errors" >&2
	status=1
fi
fixture_result=$(grep '^BAD_CONFIG_RESULT ' "$fixture_log" | tail -n 1)
if [ -z "$fixture_result" ]; then
	echo "run_validation: fixture produced no BAD_CONFIG_RESULT" >&2
	status=1
fi
case "$fixture_result" in
*'"pass":true'*) ;;
*)
	echo "run_validation: bad-config fixture did not report pass=true" >&2
	status=1 ;;
esac
fixture_failed=$(sed -n 's/.*CHECKS_FAILED=//p' "$fixture_log" | tail -n 1)
if [ "$fixture_failed" != "0" ]; then
	echo "run_validation: bad-config fixture reported CHECKS_FAILED=$fixture_failed" >&2
	status=1
fi
echo "[run-validation] bad-config fixture tail:"
tail -n 40 "$fixture_log"

probe_log="$stage/failure_probe.log"
: >"$probe_log"
echo "[run-validation] running deliberate failure probe (nonzero exit expected)"
run_bounded 60 "$probe_log" "$godot_bin" --headless --fixed-fps 60 \
	--path "$stage" --script res://tools/drive_lab/failure_probe.gd
probe_rc=$?
if [ "$probe_rc" -eq 0 ]; then
	echo "run_validation: failure probe exited 0; failing checks are not detectable" >&2
	status=1
fi
probe_result=$(grep '^PROBE_RESULT ' "$probe_log" | tail -n 1)
case "$probe_result" in
*'"pass":false'*) ;;
*)
	echo "run_validation: failure probe did not report pass=false" >&2
	status=1
	esac
echo "[run-validation] failure probe rc=$probe_rc"
tail -n 20 "$probe_log"

if [ -n "$log_file" ]; then
	tail -c 2097152 "$validator_log" >"$log_file" || status=1
	echo "[run-validation] validator log copied to $log_file (bounded to 2 MiB)"
fi

if [ "$keep_scratch" -eq 1 ]; then
	echo "[run-validation] logs kept in $stage"
fi

if [ "$status" -eq 0 ]; then
	echo "[run-validation] PASS (isolated project: $stage)"
else
	echo "[run-validation] FAIL (isolated project: $stage)" >&2
fi
exit "$status"
