#!/bin/sh
# Bounded direct runner for the M1.1 pure-motor black-box entry.
#
# Usage:
#   run_pure_motor_entry.sh [--godot <bin>] [--project <dir>]
#                           [--timeout <seconds>] [--case <id>]
#
# Godot's global script class cache requires a headless import before
# --script on a fresh project copy, so this runner imports first and then runs
# tests/handling/pure_motor_entry.gd under a wall-clock timeout. A bare exit
# code is not proof of success on this engine (it can exit 0 after a parse
# error), so the runner also fails when:
#   * the engine exits nonzero;
#   * the captured log contains an engine ERROR/SCRIPT ERROR/FATAL line or a
#     failed script load / parse error;
#   * no SLICE_SUMMARY line containing "pass":true is printed.
# Exit 0 means every selected case passed.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=${ROADSTORM_PROJECT:-$(CDPATH= cd -- "$script_dir/../.." && pwd)}
godot_bin=${GODOT_BIN:-godot}
timeout_s=${ROADSTORM_TEST_TIMEOUT:-120}
case_id=""

usage() {
	cat <<'EOF'
Usage: run_pure_motor_entry.sh [--godot <bin>] [--project <dir>]
                               [--timeout <seconds>] [--case <id>]

Runs the M1.1 pure-motor entry with the required --import first, then gates
the engine log and the SLICE_SUMMARY pass marker.
EOF
}

die_usage() {
	echo "$1" >&2
	usage >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--godot)
		[ $# -ge 2 ] || die_usage "--godot needs a value"
		godot_bin=$2
		shift 2
		;;
	--godot=*)
		godot_bin=${1#*=}
		shift
		;;
	--project)
		[ $# -ge 2 ] || die_usage "--project needs a value"
		project=$2
		shift 2
		;;
	--project=*)
		project=${1#*=}
		shift
		;;
	--timeout)
		[ $# -ge 2 ] || die_usage "--timeout needs a value"
		timeout_s=$2
		shift 2
		;;
	--timeout=*)
		timeout_s=${1#*=}
		shift
		;;
	--case)
		[ $# -ge 2 ] || die_usage "--case needs a value"
		case_id=$2
		shift 2
		;;
	--case=*)
		case_id=${1#*=}
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die_usage "unknown option: $1"
		;;
	esac
done

case "$timeout_s" in
'' | *[!0-9]*)
	echo "run_pure_motor_entry: --timeout must be a positive integer" >&2
	exit 2
	;;
esac
[ "$timeout_s" -gt 0 ] || {
	echo "run_pure_motor_entry: --timeout must be a positive integer" >&2
	exit 2
}

[ -f "$project/project.godot" ] || {
	echo "run_pure_motor_entry: not a project root: $project" >&2
	exit 2
}
if [ ! -x "$godot_bin" ] && ! command -v "$godot_bin" >/dev/null 2>&1; then
	echo "run_pure_motor_entry: Godot binary not found: $godot_bin" >&2
	exit 2
fi

tmp_root=${TMPDIR:-/tmp}
mkdir -p "$tmp_root" || {
	echo "run_pure_motor_entry: cannot create TMPDIR: $tmp_root" >&2
	exit 2
}
import_log=$tmp_root/pure_motor_import.$$.log
main_log=$tmp_root/pure_motor_entry.$$.log
trap 'rm -f "$import_log" "$main_log"' EXIT HUP INT TERM

# Same anchored error shapes tools/ci/lib/common.sh gates.
error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

# run_bounded <seconds> <logfile> <command...>: run with a portable watchdog,
# because stock macOS has no coreutils `timeout`.
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

# The import registers global class names; --script alone fails to resolve
# preloaded class members on a fresh copy.
: >"$import_log"
if ! run_bounded "$timeout_s" "$import_log" "$godot_bin" --headless --path "$project" --import; then
	echo "run_pure_motor_entry: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
fi
if grep -nE "$error_re" "$import_log"; then
	echo "run_pure_motor_entry: import log reported engine errors" >&2
	exit 1
fi

# `--case=` follows the script path directly on this engine: arguments placed
# after a bare `--` are not visible to OS.get_cmdline_args() here.
if [ -n "$case_id" ]; then
	set -- --headless --path "$project" --script res://tests/handling/pure_motor_entry.gd "--case=$case_id"
else
	set -- --headless --path "$project" --script res://tests/handling/pure_motor_entry.gd
fi
: >"$main_log"
run_bounded "$timeout_s" "$main_log" "$godot_bin" "$@"
status=$?

if grep -nE "$error_re" "$main_log"; then
	echo "run_pure_motor_entry: engine reported errors:" >&2
	grep -nE "$error_re" "$main_log" | sed 's/^/  /' >&2
	status=1
fi

summary=$(grep '^SLICE_SUMMARY ' "$main_log" | tail -n 1)
if [ -z "$summary" ]; then
	echo "run_pure_motor_entry: no SLICE_SUMMARY marker; runner did not complete" >&2
	exit 1
fi
printf '%s\n' "$summary"

case "$summary" in
*'"pass":true'*)
	;;
*)
	echo "run_pure_motor_entry: slice did not report pass=true" >&2
	status=1
	;;
esac

if [ "$status" -ne 0 ]; then
	exit "$status"
fi
exit 0
