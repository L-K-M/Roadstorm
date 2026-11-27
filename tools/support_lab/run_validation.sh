#!/bin/sh
# Roadstorm Racer! - M1.4 ground-support sensing laboratory runner.
#
# Ownership: tools/support_lab/**. Stages a private copy of the project into
# a temporary directory, imports once, then runs the headless
# GroundSupportProbe validator under the pinned Godot 4.7.2 Jolt build. The
# live checkout's .godot cache is never read or written.
#
# Every engine invocation is bounded three ways: a wall-clock watchdog
# (default 120 s, never above 180 s), Godot's `--quit-after 6000` iteration
# guard, and an internal entry-point watchdog. The wrapper enforces an outer
# budget (default 300 s). A stalled await or even a failed script load
# therefore terminates deterministically.
#
# Default run phases:
#   1. full case suite: exit 0 and SLICE_SUMMARY "pass":true;
#   2. deliberate-failure proof: exit nonzero, proof line, "pass":false;
#   3. broken-behaviour mutants: each applies one literal mutation to a
#      private copy of the staged probe source, runs its mapped case, and
#      must exit nonzero with that case "pass":false. A mutant that is not
#      detected fails the runner.
#
# Options:
#   --project DIR       project root (default: repository checkout)
#   --godot BIN         engine binary (default: pinned coordinator toolchain)
#   --timeout SECONDS   per-engine-call cap, <=180 (default 120)
#   --outer-timeout SECONDS   wrapper budget (default 300)
#   --case ID           run only this case (all|intentional_failure|<case>)
#   --mutant NAME       run only this mutant's negative control
#   --skip-mutants      skip phase 3
#   --legacy-probe FILE run only the historical-source negative control
#   --legacy-case ID    case the legacy control must fail
#                      (default: coherent_cluster_three_plus_one)
#   --keep-scratch      retain the temporary stage and logs
#
# Exit codes: 0 = every required phase passed; 1 = a phase failed;
# 2 = unsafe input or missing tool.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=${ROADSTORM_PROJECT:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
PINNED_GODOT="$PROJECT/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
if [ -x "$PINNED_GODOT" ]; then
	GODOT_BIN=${GODOT_BIN:-$PINNED_GODOT}
else
	GODOT_BIN=${GODOT_BIN:-godot}
fi
TIMEOUT_S=${ROADSTORM_TEST_TIMEOUT:-120}
OUTER_LIMIT_S=${ROADSTORM_OUTER_TIMEOUT:-300}
CASE_ID=""
MUTANT_ONLY=""
LEGACY_PROBE=""
LEGACY_CASE="coherent_cluster_three_plus_one"
SKIP_MUTANTS=0
KEEP_SCRATCH=0

usage() {
	cat <<'EOF'
Usage: run_validation.sh [--project DIR] [--godot BIN]
                         [--timeout SECONDS] [--outer-timeout SECONDS]
                         [--case ID] [--mutant NAME] [--skip-mutants]
                         [--legacy-probe FILE] [--legacy-case ID] [--keep-scratch]

Stages a private copy, imports, then runs the support_lab suite, the
deliberate-failure proof and broken-behaviour mutants under pinned Godot.
With --legacy-probe, runs only the historical-source negative control:
the supplied older probe must fail the selected case (default: the
coherent-cluster case). When that case is support_identity, every reported
failure must be an identity assertion.
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
		PROJECT=$2
		shift 2
		;;
	--project=*)
		PROJECT=${1#*=}
		shift
		;;
	--godot)
		[ $# -ge 2 ] || die_usage "--godot needs a value"
		GODOT_BIN=$2
		shift 2
		;;
	--godot=*)
		GODOT_BIN=${1#*=}
		shift
		;;
	--timeout)
		[ $# -ge 2 ] || die_usage "--timeout needs a value"
		TIMEOUT_S=$2
		shift 2
		;;
	--timeout=*)
		TIMEOUT_S=${1#*=}
		shift
		;;
	--outer-timeout)
		[ $# -ge 2 ] || die_usage "--outer-timeout needs a value"
		OUTER_LIMIT_S=$2
		shift 2
		;;
	--outer-timeout=*)
		OUTER_LIMIT_S=${1#*=}
		shift
		;;
	--case)
		[ $# -ge 2 ] || die_usage "--case needs a value"
		CASE_ID=$2
		shift 2
		;;
	--case=*)
		CASE_ID=${1#*=}
		shift
		;;
	--mutant)
		[ $# -ge 2 ] || die_usage "--mutant needs a value"
		MUTANT_ONLY=$2
		shift 2
		;;
	--mutant=*)
		MUTANT_ONLY=${1#*=}
		shift
		;;
	--legacy-probe)
		[ $# -ge 2 ] || die_usage "--legacy-probe needs a value"
		LEGACY_PROBE=$2
		shift 2
		;;
	--legacy-probe=*)
		LEGACY_PROBE=${1#*=}
		shift
		;;
	--legacy-case)
		[ $# -ge 2 ] || die_usage "--legacy-case needs a value"
		LEGACY_CASE=$2
		shift 2
		;;
	--legacy-case=*)
		LEGACY_CASE=${1#*=}
		shift
		;;
	--skip-mutants)
		SKIP_MUTANTS=1
		shift
		;;
	--keep-scratch)
		KEEP_SCRATCH=1
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

case "$TIMEOUT_S" in
'' | *[!0-9]*) die_usage "--timeout must be a positive integer" ;;
esac
[ "$TIMEOUT_S" -gt 0 ] || die_usage "--timeout must be a positive integer"
[ "$TIMEOUT_S" -le 180 ] || die_usage "--timeout must be <=180 seconds"
case "$OUTER_LIMIT_S" in
'' | *[!0-9]*) die_usage "--outer-timeout must be a positive integer" ;;
esac
[ "$OUTER_LIMIT_S" -gt 0 ] || die_usage "--outer-timeout must be a positive integer"
[ "$OUTER_LIMIT_S" -le 300 ] || die_usage "--outer-timeout must be <=300 seconds"

[ -f "$PROJECT/project.godot" ] || die_usage "not a project root: $PROJECT"
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	die_usage "Godot binary not found: $GODOT_BIN"
fi
if ! command -v python3 >/dev/null 2>&1; then
	die_usage "python3 is required for the negative-control mutations"
fi

MUTANTS="upright_gate steep footprint distance probe_count spread mask direction"
if [ -n "$MUTANT_ONLY" ]; then
	case " $MUTANTS " in
	*" $MUTANT_ONLY "*) ;;
	*) die_usage "unknown mutant '$MUTANT_ONLY'; use one of: $MUTANTS" ;;
	esac
fi
if [ -n "$LEGACY_PROBE" ] && [ ! -f "$LEGACY_PROBE" ]; then
	die_usage "--legacy-probe file not found: $LEGACY_PROBE"
fi
case "$LEGACY_CASE" in
all | intentional_failure) ;;
*)
	case "$LEGACY_CASE" in
	flat_floor | bank_and_ramp | frame_orientation_gate | \
	center_gap_seam | near_edge_partial_support | ceiling_overpass_rejection | \
	distant_support | uneven_support_spread | coherent_cluster_three_plus_one | \
	too_steep_surface | \
	absent_floor | mask_exclusion | invalid_input_unchanged | \
	deterministic_repeat | exactly_five_queries | support_identity)
		;;
	*) die_usage "unknown legacy case '$LEGACY_CASE'" ;;
	esac
	;;
esac
if [ -n "$CASE_ID" ]; then
	case "$CASE_ID" in
	all | intentional_failure) ;;
	*)
		case "$CASE_ID" in
		flat_floor | bank_and_ramp | frame_orientation_gate | \
		center_gap_seam | near_edge_partial_support | ceiling_overpass_rejection | \
		distant_support | uneven_support_spread | coherent_cluster_three_plus_one | \
		too_steep_surface | \
		absent_floor | mask_exclusion | invalid_input_unchanged | \
		deterministic_repeat | exactly_five_queries | support_identity)
			;;
		*)
			die_usage "unknown case '$CASE_ID'"
			;;
		esac
		;;
	esac
fi

tmp_root=${TMPDIR:-/tmp}
mkdir -p "$tmp_root" || die_usage "cannot create TMPDIR: $tmp_root"
stage=$(mktemp -d "$tmp_root/support_lab_stage.XXXXXX" 2>/dev/null) \
	|| die_usage "cannot create staging directory"
mut_root=$(mktemp -d "$tmp_root/support_lab_mut.XXXXXX" 2>/dev/null) \
	|| die_usage "cannot create mutation directory"

cleanup() {
	if [ "$KEEP_SCRATCH" -eq 0 ]; then
		rm -rf "$stage" "$mut_root"
	fi
}
trap cleanup EXIT HUP INT TERM

# Stage only what the support laboratory imports. The live checkout's .godot
# cache is never read or written.
for path in project.godot src scenes; do
	if [ ! -e "$PROJECT/$path" ]; then
		echo "run_validation: missing staged path: $PROJECT/$path" >&2
		exit 2
	fi
	cp -R "$PROJECT/$path" "$stage/" || {
		echo "run_validation: failed to stage $path" >&2
		exit 2
	}
done
if [ ! -d "$PROJECT/tools/support_lab" ]; then
	echo "run_validation: missing staged path: $PROJECT/tools/support_lab" >&2
	exit 2
fi
mkdir -p "$stage/tools"
cp -R "$PROJECT/tools/support_lab" "$stage/tools/" || {
	echo "run_validation: failed to stage tools/support_lab" >&2
	exit 2
}
find "$stage" -type d -name .godot -prune -exec rm -rf {} + 2>/dev/null
probe_stage="$stage/src/simulation/ground_support_probe.gd"
probe_pristine="$mut_root/pristine_ground_support_probe.gd"
cp "$probe_stage" "$probe_pristine" || {
	echo "run_validation: failed to preserve pristine probe source" >&2
	exit 2
}

error_re='^(ERROR|SCRIPT ERROR|FATAL|USER ERROR):|^Failed to load script|^Parse Error'

# Portable wall-clock watchdog: stock macOS has no coreutils `timeout`.
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

start_epoch=$(date +%s)

# Print the per-call limit that still fits the outer wrapper budget.
budget_limit() {
	_now=$(date +%s)
	_elapsed=$((_now - start_epoch))
	_remaining=$((OUTER_LIMIT_S - _elapsed))
	if [ "$_remaining" -le 0 ]; then
		echo "run_validation: outer ${OUTER_LIMIT_S}s budget exceeded" >&2
		exit 1
	fi
	if [ "$_remaining" -lt "$TIMEOUT_S" ]; then
		echo "$_remaining"
	else
		echo "$TIMEOUT_S"
	fi
}

grep_errors() {
	grep -nE "$error_re" "$1" || true
}

has_pass_true() {
	summary=$(grep '^SLICE_SUMMARY ' "$1" | tail -n 1)
	[ -n "$summary" ] || return 1
	case "$summary" in
	*'"pass":true'*) return 0 ;;
	*) return 1 ;;
	esac
}

has_pass_false() {
	summary=$(grep '^SLICE_SUMMARY ' "$1" | tail -n 1)
	[ -n "$summary" ] || return 1
	case "$summary" in
	*'"pass":false'*) return 0 ;;
	*) return 1 ;;
	esac
}

case_pass_false() {
	case_id=$1
	log=$2
	result_line=$(grep '^SLICE_RESULT ' "$log" | grep "\"case\":\"$case_id\"" | tail -n 1)
	[ -n "$result_line" ] || return 1
	case "$result_line" in
	*'"pass":false'*) return 0 ;;
	*) return 1 ;;
	esac
}

## For the identity case's historical-source control, prove the old source
## fails only assertions that mention identity: every reported failure must
## carry the marker, so a behavioural regression cannot hide behind the
## control.
legacy_failures_are_identity_only() {
	log=$1
	python3 - "$log" <<'PY'
import json, sys
path = sys.argv[1]
line = None
with open(path, "r", encoding="utf-8", errors="replace") as handle:
    for raw in handle:
        if raw.startswith("SLICE_RESULT "):
            line = raw
if line is None:
    print("no SLICE_RESULT line in legacy log", file=sys.stderr)
    sys.exit(1)
try:
    payload = json.loads(line[len("SLICE_RESULT "):])
except Exception as exc:
    print("cannot parse legacy SLICE_RESULT: %s" % exc, file=sys.stderr)
    sys.exit(1)
failures = payload.get("failures") or []
if not failures:
    print("legacy control reported no failures", file=sys.stderr)
    sys.exit(1)
non_identity = [item for item in failures if "identity" not in str(item)]
if non_identity:
    print("legacy control failed non-identity assertions:", file=sys.stderr)
    for item in non_identity[:5]:
        print("  %s" % item, file=sys.stderr)
    sys.exit(1)
print("%d identity-only failures" % len(failures))
PY
}

mutant_target_case() {
	case "$1" in
	upright_gate) echo frame_orientation_gate ;;
	steep) echo too_steep_surface ;;
	footprint) echo near_edge_partial_support ;;
	distance) echo distant_support ;;
	probe_count) echo exactly_five_queries ;;
	spread) echo uneven_support_spread ;;
	mask) echo mask_exclusion ;;
	direction) echo ceiling_overpass_rejection ;;
	*) return 1 ;;
	esac
}

## Replace exactly one literal occurrence in a staged source file. The
## mutation never touches the live checkout; only the private stage copy.
replace_literal() {
	_file=$1
	_old=$2
	_new=$3
	python3 - "$_file" "$_old" "$_new" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as handle:
    text = handle.read()
count = text.count(old)
if count != 1:
    print("mutation target count %d (expected 1): %r" % (count, old), file=sys.stderr)
    sys.exit(4)
text = text.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text)
PY
}

apply_mutant() {
	_name=$1
	_file=$2
	case "$_name" in
	upright_gate)
		replace_literal "$_file" 'if frame_up_dot < config.min_frame_up_dot:' 'if false:'
		;;
	steep)
		replace_literal "$_file" 'elif detail["up_dot"] < config.min_up_dot:' 'elif false:'
		;;
	footprint)
		replace_literal "$_file" 'if cluster_indices.size() >= config.required_footprint_hits:' 'if cluster_indices.size() >= 1:'
		;;
	distance)
		replace_literal "$_file" 'elif along > config.max_support_distance_m + DISTANCE_TOLERANCE_M:' 'elif false:'
		;;
	probe_count)
		replace_literal "$_file" 'const PROBE_COUNT := 5' 'const PROBE_COUNT := 4'
		;;
	spread)
		replace_literal "$_file" 'return (high - low) <= spread_max + DISTANCE_TOLERANCE_M' 'return (high - low) <= ABSOLUTE_MAX_RAY_LENGTH_M + DISTANCE_TOLERANCE_M'
		;;
	mask)
		replace_literal "$_file" 'query.collision_mask = body.collision_mask' 'query.collision_mask = 4294967295'
		;;
	direction)
		replace_literal "$_file" 'var down := -world_transform.basis.y' 'var down := world_transform.basis.y'
		;;
	*)
		return 1
		;;
	esac
}

run_engine() {
	case_id=$1
	log=$2
	limit=$(budget_limit)
	# `--quit-after` bounds even an engine-level stall (for example a script
	# that fails to load): without it headless Godot keeps iterating after a
	# failed load instead of exiting.
	if [ -n "$case_id" ]; then
		run_bounded "$limit" "$log" "$GODOT_BIN" --headless --fixed-fps 60 \
			--quit-after 6000 --path "$stage" \
			--script res://tools/support_lab/support_lab_entry.gd "--case=$case_id"
	else
		run_bounded "$limit" "$log" "$GODOT_BIN" --headless --fixed-fps 60 \
			--quit-after 6000 --path "$stage" \
			--script res://tools/support_lab/support_lab_entry.gd
	fi
}

echo "run_validation: stage=$stage"
echo "run_validation: godot=$GODOT_BIN (per-call ${TIMEOUT_S}s, outer ${OUTER_LIMIT_S}s)"

import_log="$mut_root/import.log"
: >"$import_log"
if ! run_bounded "$(budget_limit)" "$import_log" "$GODOT_BIN" --headless \
	--path "$stage" --import; then
	echo "run_validation: headless import failed" >&2
	tail -n 40 "$import_log" >&2
	exit 1
fi
if grep_errors "$import_log" | grep -q .; then
	echo "run_validation: import log reported engine errors:" >&2
	grep_errors "$import_log" | sed 's/^/  /' >&2
	exit 1
fi
echo "[support-lab] import complete"

# Historical-source negative control: run the selected case against an older
# probe source supplied by the caller. The control passes only when that
# source fails the case, demonstrating the behaviour change. For the identity
# case it additionally requires every failure to be an identity assertion.
if [ -n "$LEGACY_PROBE" ]; then
	cp "$LEGACY_PROBE" "$probe_stage" || {
		echo "run_validation: failed to stage legacy probe source" >&2
		exit 1
	}
	legacy_log="$mut_root/legacy_probe.log"
	: >"$legacy_log"
	run_engine "$LEGACY_CASE" "$legacy_log"
	legacy_status=$?
	legacy_ok=1
	if grep_errors "$legacy_log" | grep -q .; then
		echo "run_validation: legacy-probe control log reported engine errors:" >&2
		grep_errors "$legacy_log" | sed 's/^/  /' >&2
		legacy_ok=0
	elif [ "$legacy_status" -eq 0 ]; then
		echo "run_validation: LEGACY CONTROL FAILED: old probe passed $LEGACY_CASE" >&2
		legacy_ok=0
	elif ! case_pass_false "$LEGACY_CASE" "$legacy_log"; then
		echo "run_validation: LEGACY CONTROL FAILED: old probe did not fail $LEGACY_CASE" >&2
		legacy_ok=0
	elif [ "$LEGACY_CASE" = "support_identity" ] \
		&& ! legacy_failures_are_identity_only "$legacy_log"; then
		echo "run_validation: LEGACY CONTROL FAILED: $LEGACY_CASE failed non-identity assertions" >&2
		legacy_ok=0
	else
		echo "[support-lab] legacy probe control failed $LEGACY_CASE as expected"
	fi
	if [ "$legacy_ok" -ne 1 ]; then
		exit 1
	fi
	echo "[support-lab] legacy probe control complete"
	exit 0
fi

# Selected-case mode: used directly for debugging and by mutant controls.
if [ -n "$CASE_ID" ]; then
	log="$mut_root/case_$CASE_ID.log"
	: >"$log"
	run_engine "$CASE_ID" "$log"
	status=$?
	if grep_errors "$log" | grep -q .; then
		echo "run_validation: engine reported errors:" >&2
		grep_errors "$log" | sed 's/^/  /' >&2
		status=1
	fi
	if [ "$CASE_ID" = "intentional_failure" ]; then
		if [ "$status" -eq 0 ]; then
			echo "run_validation: intentional-failure case exited 0" >&2
			exit 1
		fi
		if ! grep -q '^INTENTIONAL_FAILURE_PROOF pass=false' "$log"; then
			echo "run_validation: intentional-failure proof line missing" >&2
			exit 1
		fi
		echo "[support-lab] intentional failure proof detected"
		exit 0
	fi
	if [ "$status" -ne 0 ]; then
		echo "run_validation: case $CASE_ID failed" >&2
		exit 1
	fi
	if ! has_pass_true "$log"; then
		echo "run_validation: case $CASE_ID did not report pass=true" >&2
		exit 1
	fi
	echo "[support-lab] case $CASE_ID passed"
	exit 0
fi

suite_log="$mut_root/suite.log"
: >"$suite_log"
run_engine "" "$suite_log"
suite_status=$?
if grep_errors "$suite_log" | grep -q .; then
	echo "run_validation: suite log reported engine errors:" >&2
	grep_errors "$suite_log" | sed 's/^/  /' >&2
	suite_status=1
fi
if [ "$suite_status" -ne 0 ] || ! has_pass_true "$suite_log"; then
	echo "run_validation: full suite did not pass" >&2
	grep '^SLICE_SUMMARY ' "$suite_log" | tail -n 1 >&2 || true
	status=1
else
	echo "[support-lab] full suite passed"
	grep '^SLICE_SUMMARY ' "$suite_log" | tail -n 1
	status=0
fi

proof_log="$mut_root/intentional_failure.log"
: >"$proof_log"
run_engine "intentional_failure" "$proof_log"
proof_status=$?
proof_ok=0
if [ "$proof_status" -ne 0 ] \
	&& grep -q '^INTENTIONAL_FAILURE_PROOF pass=false' "$proof_log" \
	&& has_pass_false "$proof_log"; then
	proof_ok=1
fi
if [ "$proof_ok" -ne 1 ]; then
	echo "run_validation: deliberate-failure proof did not fail as required" >&2
	status=1
else
	echo "[support-lab] deliberate-failure proof detected"
fi

if [ "$SKIP_MUTANTS" -eq 0 ]; then
	for name in $MUTANTS; do
		if [ -n "$MUTANT_ONLY" ] && [ "$name" != "$MUTANT_ONLY" ]; then
			continue
		fi
		target_case=$(mutant_target_case "$name") || {
			echo "run_validation: no target case for mutant $name" >&2
			status=1
			continue
		}
		limit=$(budget_limit)
		cp "$probe_pristine" "$probe_stage" || {
			echo "run_validation: failed to restore pristine probe" >&2
			status=1
			continue
		}
		if ! apply_mutant "$name" "$probe_stage"; then
			echo "run_validation: mutation '$name' did not apply cleanly" >&2
			status=1
			continue
		fi
		mutant_log="$mut_root/mutant_${name}.log"
		: >"$mutant_log"
		run_engine "$target_case" "$mutant_log"
		mutant_status=$?
		if grep -qE '^Failed to load script|^Parse Error' "$mutant_log"; then
			echo "run_validation: mutant $name broke parsing" >&2
			status=1
			continue
		fi
		if [ "$mutant_status" -eq 0 ]; then
			echo "run_validation: NEGATIVE CONTROL FAILED: mutant $name was not detected (exit 0)" >&2
			status=1
			continue
		fi
		if ! case_pass_false "$target_case" "$mutant_log"; then
			echo "run_validation: NEGATIVE CONTROL FAILED: mutant $name did not fail case $target_case" >&2
			status=1
			continue
		fi
		echo "[support-lab] mutant $name detected by case $target_case"
	done
	cp "$probe_pristine" "$probe_stage"
fi

if [ "$KEEP_SCRATCH" -eq 1 ]; then
	echo "run_validation: scratch kept in $stage (logs in $mut_root)"
fi

if [ "$status" -ne 0 ]; then
	exit 1
fi
echo "[support-lab] all required phases passed"
exit 0
