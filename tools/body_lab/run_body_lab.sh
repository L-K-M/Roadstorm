#!/bin/sh
# Bounded runner for the M1.1 motor/body adapter laboratory.
#
# Usage:
#   run_body_lab.sh [--godot <bin>] [--project <dir>] [--timeout <seconds>]
#                   [--case <id>] [--keep-scratch]
#
# Stages a private copy of the project into a temporary directory (never the
# live checkout), runs the required headless import there, then runs
# tools/body_lab/body_lab_entry.gd under --fixed-fps 60 with a wall-clock
# watchdog. A bare engine exit code is not proof of success on this engine, so
# the runner also fails when:
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
keep_scratch=0

usage() {
	cat <<'EOF'
Usage: run_body_lab.sh [--godot <bin>] [--project <dir>]
                       [--timeout <seconds>] [--case <id>] [--keep-scratch]

Stages a private copy of the project, imports it, then runs the body_lab entry
under fixed 60 Hz pacing with a bounded watchdog.
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
	--keep-scratch)
		keep_scratch=1
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
	echo "run_body_lab: --timeout must be a positive integer" >&2
	exit 2
	;;
esac
[ "$timeout_s" -gt 0 ] || {
	echo "run_body_lab: --timeout must be a positive integer" >&2
	exit 2
}

[ -f "$project/project.godot" ] || {
	echo "run_body_lab: not a project root: $project" >&2
	exit 2
}
if [ ! -x "$godot_bin" ] && ! command -v "$godot_bin" >/dev/null 2>&1; then
	echo "run_body_lab: Godot binary not found: $godot_bin" >&2
	exit 2
fi

tmp_root=${TMPDIR:-/tmp}
mkdir -p "$tmp_root" || {
	echo "run_body_lab: cannot create TMPDIR: $tmp_root" >&2
	exit 2
}
stage=$(mktemp -d "$tmp_root/body_lab_stage.XXXXXX" 2>/dev/null) || {
	echo "run_body_lab: cannot create staging directory" >&2
	exit 2
}

cleanup() {
	if [ "$keep_scratch" -eq 0 ] && [ -n "$stage" ] && [ -d "$stage" ]; then
		rm -rf "$stage"
	fi
}
trap cleanup EXIT HUP INT TERM

# Stage only what the adapter laboratory imports. The live checkout's .godot
# cache is never read or written.
for path in project.godot src scenes assets; do
	if [ ! -e "$project/$path" ]; then
		echo "run_body_lab: missing staged path: $project/$path" >&2
		exit 2
	fi
	cp -R "$project/$path" "$stage/" || {
		echo "run_body_lab: failed to stage $path" >&2
		exit 2
	}
done
if [ ! -d "$project/tools/body_lab" ]; then
	echo "run_body_lab: missing staged path: $project/tools/body_lab" >&2
	exit 2
fi
mkdir -p "$stage/tools"
cp -R "$project/tools/body_lab" "$stage/tools/" || {
	echo "run_body_lab: failed to stage tools/body_lab" >&2
	exit 2
}
find "$stage" -type d -name .godot -prune -exec rm -rf {} + 2>/dev/null

import_log="$stage/import.log"
main_log="$stage/main.log"

# Same anchored error shapes tools/ci/lib/common.sh gates.
error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

# run_bounded <seconds> <logfile> <command...>: portable watchdog, because
# stock macOS has no coreutils `timeout`.
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

echo "run_body_lab: stage=$stage"
: >"$import_log"
if ! run_bounded "$timeout_s" "$import_log" "$godot_bin" --headless --path "$stage" --import; then
	echo "run_body_lab: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
fi
if grep -nE "$error_re" "$import_log"; then
	echo "run_body_lab: import log reported engine errors" >&2
	exit 1
fi

# `--case=` follows the script path directly on this engine: arguments placed
# after a bare `--` are not visible to OS.get_cmdline_args() here.
if [ -n "$case_id" ]; then
	set -- --headless --fixed-fps 60 --path "$stage" \
		--script res://tools/body_lab/body_lab_entry.gd "--case=$case_id"
else
	set -- --headless --fixed-fps 60 --path "$stage" \
		--script res://tools/body_lab/body_lab_entry.gd
fi
: >"$main_log"
run_bounded "$timeout_s" "$main_log" "$godot_bin" "$@"
status=$?

if grep -nE "$error_re" "$main_log"; then
	echo "run_body_lab: engine reported errors:" >&2
	grep -nE "$error_re" "$main_log" | sed 's/^/  /' >&2
	status=1
fi

summary=$(grep '^SLICE_SUMMARY ' "$main_log" | tail -n 1)
if [ -z "$summary" ]; then
	echo "run_body_lab: no SLICE_SUMMARY marker; runner did not complete" >&2
	exit 1
fi
printf '%s\n' "$summary"

case "$summary" in
*'"pass":true'*)
	;;
*)
	echo "run_body_lab: slice did not report pass=true" >&2
	status=1
	;;
esac

# Concise engine logs stay in the stage; --keep-scratch retains them.
if [ "$keep_scratch" -eq 1 ]; then
	echo "run_body_lab: logs kept in $stage"
fi

if [ "$status" -ne 0 ]; then
	exit "$status"
fi
exit 0
