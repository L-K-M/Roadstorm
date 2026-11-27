#!/bin/sh
# Bounded negative control for the M1.1 DriveLab gearbox integration.
#
# Proves the drive-lab validator actually detects removal of the gear mirror
# (and the gearbox refusal path) instead of passing vacuously. Stages a private
# project copy, applies exactly one textual mutation to the owned laboratory,
# imports, runs the validator, and requires a behavioral failure in the
# `gearbox_integration` case with no parse/script errors. Exit 0 means the
# mutation was detected; 1 means it was not; 2 means unsafe inputs or an
# unusable engine.
#
# Usage:
#   tools/drive_lab/run_gearbox_mutant_control.sh \
#       [--project DIR] [--godot BIN] [--timeout SECONDS] \
#       [--mutation mirror_removed|proposal_refused] [--log FILE] [--keep-scratch]

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=${ROADSTORM_PROJECT:-$(CDPATH= cd -- "$script_dir/../.." && pwd)}
default_godot="$project/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
godot_bin=${ROADSTORM_GODOT:-$default_godot}
timeout_s=${ROADSTORM_TEST_TIMEOUT:-240}
mutation=${ROADSTORM_MUTATION:-mirror_removed}
keep_scratch=0
log_file=""

usage() {
	cat <<'EOF'
Usage: run_gearbox_mutant_control.sh [--project DIR] [--godot BIN]
       [--timeout SECONDS] [--mutation mirror_removed|proposal_refused]
       [--log FILE] [--keep-scratch]

Stages a private copy, mutates the DriveLab gearbox integration, and requires
the drive-lab validator to fail behaviourally in gearbox_integration.
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
	--mutation)
		[ $# -ge 2 ] || die_usage "--mutation needs a value"
		mutation=$2; shift 2 ;;
	--mutation=*)
		mutation=${1#*=}; shift ;;
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
case "$mutation" in
mirror_removed | proposal_refused) ;;
*) die_usage "--mutation must be mirror_removed or proposal_refused" ;;
esac

[ -f "$project/project.godot" ] || {
	echo "mutant-control: not a project root: $project" >&2
	exit 2
}
for required in src scenes tools/drive_lab; do
	[ -e "$project/$required" ] || {
		echo "mutant-control: missing staged path: $project/$required" >&2
		exit 2
	}
done
if [ ! -x "$godot_bin" ] && ! command -v "$godot_bin" >/dev/null 2>&1; then
	echo "mutant-control: Godot binary not found: $godot_bin" >&2
	exit 2
fi

pinned="4.7.2.stable.official.ed1daf0bf"
if [ -r "$project/tools/toolchain/pin/engine.txt" ]; then
	pinned_from_file=$(sed -n 's/^version_string=//p' "$project/tools/toolchain/pin/engine.txt" | head -n 1)
	[ -n "$pinned_from_file" ] && pinned=$pinned_from_file
fi

error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

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

stage=$(mktemp -d "${TMPDIR:-/tmp}/gearbox-mutant-stage.XXXXXX" 2>/dev/null) || {
	echo "mutant-control: cannot create staging directory" >&2
	exit 2
}
cleanup() {
	if [ "$keep_scratch" -eq 0 ] && [ -n "$stage" ] && [ -d "$stage" ]; then
		rm -rf "$stage"
	fi
}
trap cleanup EXIT HUP INT TERM

echo "[mutant-control] staging isolated copy in $stage"
cp "$project/project.godot" "$stage/" || exit 2
cp -R "$project/src" "$stage/src" || exit 2
cp -R "$project/scenes" "$stage/scenes" || exit 2
mkdir -p "$stage/tools" || exit 2
cp -R "$project/tools/drive_lab" "$stage/tools/drive_lab" || exit 2
find "$stage" -type d -name .godot -prune -exec rm -rf {} + 2>/dev/null

target="$stage/src/laboratory/drive_lab.gd"
if ! python3 "$script_dir/apply_gearbox_mutation.py" --target "$target" --mutation "$mutation"; then
	echo "mutant-control: mutation anchor not found exactly once" >&2
	exit 1
fi
echo "[mutant-control] mutation=$mutation applied to $target"

version_log="$stage/version.log"
: >"$version_log"
run_bounded 60 "$version_log" "$godot_bin" --version || {
	echo "mutant-control: engine --version failed or timed out" >&2
	tail -n 20 "$version_log" >&2
	exit 2
}
actual_version=$(tail -n 1 "$version_log")
case "$actual_version" in
*"$pinned"*) ;;
*)
	echo "mutant-control: engine is not the pinned $pinned (got: $actual_version)" >&2
	exit 2
;;
esac

import_log="$stage/import.log"
: >"$import_log"
echo "[mutant-control] importing staged project"
run_bounded "$timeout_s" "$import_log" "$godot_bin" --headless --path "$stage" --import || {
	echo "mutant-control: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
}
if grep -nE "$error_re" "$import_log"; then
	echo "mutant-control: import log reported engine errors" >&2
	exit 1
fi

validator_log="$stage/validator.log"
: >"$validator_log"
echo "[mutant-control] running drive-lab validator against the mutated source"
run_bounded "$timeout_s" "$validator_log" "$godot_bin" --headless --fixed-fps 60 \
	--path "$stage" --script res://tools/drive_lab/validate_drive_lab.gd
validator_rc=$?
status=0
if grep -nE "$error_re" "$validator_log"; then
	echo "mutant-control: validator reported parse/script errors, not a behavioral failure" >&2
	status=1
fi
summary=$(grep '^DRIVE_LAB_SUMMARY ' "$validator_log" | tail -n 1)
case "$summary" in
*'"pass":false'*) ;;
*)
	echo "mutant-control: validator did not report pass=false (rc=$validator_rc)" >&2
	status=1
	;;
esac
gearbox_result=$(grep '"case":"gearbox_integration"' "$validator_log" | tail -n 1)
case "$gearbox_result" in
*'"pass":false'*) ;;
*)
	echo "mutant-control: gearbox_integration did not fail under the mutation" >&2
	status=1
	;;
esac
if [ "$validator_rc" -eq 0 ]; then
	echo "mutant-control: validator exited 0 under the mutation" >&2
	status=1
fi
echo "[mutant-control] mutation=$mutation validator rc=$validator_rc"
grep '"case":"gearbox_integration"' "$validator_log" | tail -n 1

if [ -n "$log_file" ]; then
	tail -c 2097152 "$validator_log" >"$log_file" || status=1
	echo "[mutant-control] validator log copied to $log_file (bounded to 2 MiB)"
fi
if [ "$keep_scratch" -eq 1 ]; then
	echo "[mutant-control] logs kept in $stage"
fi

if [ "$status" -eq 0 ]; then
	echo "[mutant-control] DETECTED (mutation $mutation is caught by the validator)"
else
	echo "[mutant-control] NOT DETECTED (mutation $mutation was not caught)" >&2
fi
exit "$status"
