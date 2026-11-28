#!/bin/sh
# Roadstorm Racer! - roadstorm.cosmetic_damage.v1 contract laboratory runner.
#
# Usage:
#   run_validation.sh [--project DIR] [--godot BIN] [--lock FILE]
#       [--work-root DIR] [--lock-wait SECONDS] [--outer-timeout SECONDS]
#       [--log FILE] [--summary-out FILE] [--evidence-out FILE] [--keep-scratch]
#
# The runner exports a plain frozen `git archive HEAD` source tree, overlays
# only src/presentation/cosmetic_damage_state.gd and tools/cosmetic_damage_lab/** from the selected
# project checkout, imports that private copy, runs the contract validator, and
# runs the deliberate failure probe. It never imports or writes the live
# checkout's .godot cache and never mutates Git.
#
# Exit codes: 0 = validator passed and the failure probe was rejected as
# designed; 1 = a validation/output gate failed; 2 = unsafe input, missing
# tools, or an unusable/mismatched engine.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=${ROADSTORM_PROJECT:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}
DEFAULT_GODOT="$PROJECT/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
GODOT_BIN=${ROADSTORM_GODOT:-$DEFAULT_GODOT}
DEFAULT_LOCK="$PROJECT/work/agents/coordinator/godot-test.lock"
LOCK_FILE=${ROADSTORM_GODOT_LOCK:-$DEFAULT_LOCK}
WORK_ROOT=${ROADSTORM_COSMETIC_DAMAGE_WORK_ROOT:-}
LOCK_WAIT_S=${ROADSTORM_LOCK_WAIT:-120}
OUTER_TIMEOUT_S=${ROADSTORM_OUTER_TIMEOUT:-120}
LOG_FILE=""
SUMMARY_OUT=""
EVIDENCE_OUT=""
KEEP_SCRATCH=0

usage() {
	cat <<'EOF'
Usage: run_validation.sh [--project DIR] [--godot BIN] [--lock FILE]
       [--work-root DIR] [--lock-wait SECONDS] [--outer-timeout SECONDS]
       [--log FILE] [--summary-out FILE] [--evidence-out FILE] [--keep-scratch]

Runs the cosmetic-damage contract validator against a frozen git archive HEAD
source tree overlaid only with the owned cosmetic-damage paths. --work-root, when
supplied, must resolve under the repository's ignored work/ tree.
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
	--log)
		[ $# -ge 2 ] || die_usage "--log needs a value"
		LOG_FILE=$2; shift 2 ;;
	--log=*)
		LOG_FILE=${1#*=}; shift ;;
	--summary-out)
		[ $# -ge 2 ] || die_usage "--summary-out needs a value"
		SUMMARY_OUT=$2; shift 2 ;;
	--summary-out=*)
		SUMMARY_OUT=${1#*=}; shift ;;
	--evidence-out)
		[ $# -ge 2 ] || die_usage "--evidence-out needs a value"
		EVIDENCE_OUT=$2; shift 2 ;;
	--evidence-out=*)
		EVIDENCE_OUT=${1#*=}; shift ;;
	--keep-scratch)
		KEEP_SCRATCH=1; shift ;;
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

positive_integer "$LOCK_WAIT_S" || die_usage "--lock-wait must be a positive integer"
positive_integer "$OUTER_TIMEOUT_S" || die_usage "--outer-timeout must be a positive integer"

for tool in git tar lockf shasum sed awk grep tail head ps cp cmp sort find dirname basename mkdir mktemp sleep kill rm; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "run_validation: required tool missing from PATH: $tool" >&2
		exit 2
	}
done
[ -f "$PROJECT/project.godot" ] || {
	echo "run_validation: not a project root: $PROJECT" >&2
	exit 2
}
[ -d "$PROJECT/.git" ] || {
	echo "run_validation: project has no .git directory for read-only archive export: $PROJECT" >&2
	exit 2
}
[ -f "$PROJECT/src/presentation/cosmetic_damage_state.gd" ] || {
	echo "run_validation: missing owned overlay src/presentation/cosmetic_damage_state.gd" >&2
	exit 2
}
[ -d "$PROJECT/tools/cosmetic_damage_lab" ] || {
	echo "run_validation: missing owned overlay tools/cosmetic_damage_lab" >&2
	exit 2
}
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "run_validation: Godot binary not found: $GODOT_BIN" >&2
	exit 2
fi
[ -d "$(dirname -- "$LOCK_FILE")" ] || {
	echo "run_validation: lock directory missing: $(dirname -- "$LOCK_FILE")" >&2
	exit 2
}
touch "$LOCK_FILE" 2>/dev/null || {
	echo "run_validation: cannot create shared lock file: $LOCK_FILE" >&2
	exit 2
}

PROJECT_CANON=$(CDPATH= cd -- "$PROJECT" 2>/dev/null && pwd -P) || {
	echo "run_validation: cannot resolve project root: $PROJECT" >&2
	exit 2
}

if [ -n "$WORK_ROOT" ]; then
	mkdir -p "$WORK_ROOT" 2>/dev/null || {
		echo "run_validation: cannot create work root: $WORK_ROOT" >&2
		exit 2
	}
	WORK_CANON=$(CDPATH= cd -- "$WORK_ROOT" 2>/dev/null && pwd -P) || {
		echo "run_validation: cannot resolve work root: $WORK_ROOT" >&2
		exit 2
	}
	case "$WORK_CANON" in
	"$PROJECT_CANON/work" | "$PROJECT_CANON/work"/*) ;;
	*)
		echo "run_validation: --work-root must stay under ignored $PROJECT_CANON/work" >&2
		exit 2
	;;
	esac
	RUN_DIR=$(mktemp -d "$WORK_CANON/cosmetic-damage-lab.XXXXXX" 2>/dev/null) || {
		echo "run_validation: cannot create a fresh run directory under $WORK_CANON" >&2
		exit 2
	}
else
	RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cosmetic-damage-lab.XXXXXX" 2>/dev/null) || {
		echo "run_validation: cannot create temporary run directory" >&2
		exit 2
	}
fi
RUN_DIR=$(CDPATH= cd -- "$RUN_DIR" 2>/dev/null && pwd -P) || {
	echo "run_validation: cannot resolve run directory" >&2
	exit 2
}

STAGE="$RUN_DIR/stage"
RESULTS="$RUN_DIR/results"
LOGS="$RUN_DIR/logs"
SUMMARY="$RUN_DIR/runner_summary.txt"
CURRENT_PIDFILE=""

mkdir -p "$STAGE" "$RESULTS" "$LOGS" \
	"$RUN_DIR/home" "$RUN_DIR/tmp" "$RUN_DIR/xdg-cache" "$RUN_DIR/xdg-config" "$RUN_DIR/xdg-data" || exit 2
: >"$SUMMARY"

export HOME="$RUN_DIR/home"
export TMPDIR="$RUN_DIR/tmp"
export XDG_CACHE_HOME="$RUN_DIR/xdg-cache"
export XDG_CONFIG_HOME="$RUN_DIR/xdg-config"
export XDG_DATA_HOME="$RUN_DIR/xdg-data"
export LC_ALL=C

# Stop only the one engine child whose exact PID this runner's exec wrapper
# wrote. The command is inspected before signalling; no process-name pattern
# kill is ever used. A marker file preserves the scratch log when this fires.
stop_exact_child() {
	_pidfile=$1
	_child=$(cat "$_pidfile" 2>/dev/null || true)
	case "$_child" in
	'' | *[!0-9]*) return 0 ;;
	esac
	if ! kill -0 "$_child" 2>/dev/null; then
		return 0
	fi
	_cmd=$(ps -p "$_child" -o command= 2>/dev/null || true)
	case "$_cmd" in
	*"$GODOT_BIN"*)
		echo "[cosmetic-damage] stopping stranded exact Godot child pid=$_child command=$_cmd" >&2
		echo "pid=$_child command=$_cmd" >>"$RUN_DIR/stranded_children.txt"
		: >"$RUN_DIR/.stranded"
		kill -TERM "$_child" 2>/dev/null || true
		sleep 1
		if kill -0 "$_child" 2>/dev/null; then
			kill -KILL "$_child" 2>/dev/null || true
		fi
	;;
	*)
		echo "[cosmetic-damage] exact child pid=$_child no longer matches the Godot command; not signalling it" >&2
	;;
	esac
}

stop_current_child() {
	if [ -n "$CURRENT_PIDFILE" ]; then
		stop_exact_child "$CURRENT_PIDFILE"
	fi
}

cleanup() {
	stop_current_child
	if [ -f "$RUN_DIR/.stranded" ]; then
		echo "[cosmetic-damage] stranded-child evidence kept in $RUN_DIR" >&2
		return 0
	fi
	if [ "$KEEP_SCRATCH" -eq 0 ] && [ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ]; then
		case "$RUN_DIR" in
		*/cosmetic-damage-lab.*)
			rm -rf "$RUN_DIR"
		;;
		*)
			echo "[cosmetic-damage] refusing to clean unexpected run directory: $RUN_DIR" >&2
		;;
		esac
	fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fatal() {
	_code=$1
	shift
	echo "run_validation: $*" >&2
	echo "runner_error=$*" >>"$SUMMARY"
	exit "$_code"
}

# run_godot <pidfile> <logfile> <command...>: one outer-bounded engine call.
# The inner shell records its PID and execs the command, so the watchdog can
# terminate exactly that process rather than matching processes by name.
run_godot() {
	_pidfile=$1
	_out=$2
	shift 2
	: >"$_pidfile"
	CURRENT_PIDFILE=$_pidfile
	sh -c 'echo $$ > "$1"; shift; exec "$@"' _ "$_pidfile" "$@" >>"$_out" 2>&1 9>&- &
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

echo "[cosmetic-damage] run directory: $RUN_DIR"
echo "run_dir=$RUN_DIR" >>"$SUMMARY"

# Freeze the committed source with the required plain archive. Git is used only
# for read-only source export; no branch, worktree, index or repository state is
# changed.
HEAD_SHA=$(git -C "$PROJECT" rev-parse HEAD 2>"$LOGS/git-revparse.log") || \
	fatal 2 "git rev-parse HEAD failed; see $LOGS/git-revparse.log"
echo "source_head_sha=$HEAD_SHA" >>"$SUMMARY"
echo "source_head_sha=$HEAD_SHA"

ARCHIVE="$RUN_DIR/source.tar"
git -C "$PROJECT" archive --format=tar HEAD >"$ARCHIVE" 2>"$LOGS/git-archive.log" || \
	fatal 2 "git archive HEAD failed; see $LOGS/git-archive.log"
SOURCE_ARCHIVE_SHA=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
echo "source_archive_sha256=$SOURCE_ARCHIVE_SHA" >>"$SUMMARY"
echo "source_archive_sha256=$SOURCE_ARCHIVE_SHA"

tar -xf "$ARCHIVE" -C "$STAGE" 2>"$LOGS/tar-extract.log" || \
	fatal 2 "archive extraction failed; see $LOGS/tar-extract.log"
[ -f "$STAGE/project.godot" ] || fatal 2 "frozen archive did not contain project.godot"
[ ! -e "$STAGE/.git" ] || fatal 2 "frozen archive unexpectedly contains .git"
[ ! -e "$STAGE/.godot" ] || fatal 2 "frozen archive unexpectedly contains .godot"

# Overlay only the owned cosmetic-damage paths. The explicit allowlist guard means
# no other untracked or locally modified path can enter the frozen build.
OVERLAY_LIST="$RUN_DIR/overlay-files.txt"
{
	printf '%s\n' "src/presentation/cosmetic_damage_state.gd"
	( cd "$PROJECT" && find tools/cosmetic_damage_lab -type f -print | sort )
} >"$OVERLAY_LIST"
[ -s "$OVERLAY_LIST" ] || fatal 2 "owned overlay file list is empty"
while IFS= read -r _rel; do
	case "$_rel" in
	src/presentation/cosmetic_damage_state.gd | tools/cosmetic_damage_lab/*) ;;
	*)
		fatal 2 "refusing non-owned overlay path: $_rel"
	;;
	esac
	[ -f "$PROJECT/$_rel" ] || fatal 2 "missing overlay file: $_rel"
	mkdir -p "$STAGE/$(dirname -- "$_rel")" || fatal 2 "cannot create overlay directory for $_rel"
	cp "$PROJECT/$_rel" "$STAGE/$_rel" || fatal 2 "could not overlay $_rel"
done <"$OVERLAY_LIST"

OVERLAY_HASHES="$RUN_DIR/overlay.sha256"
(
	cd "$PROJECT" || exit 1
	while IFS= read -r _rel; do
		shasum -a 256 -- "$_rel"
	done <"$OVERLAY_LIST"
) >"$OVERLAY_HASHES" 2>"$LOGS/shasum-overlay.log" || \
	fatal 2 "could not hash overlay files; see $LOGS/shasum-overlay.log"
STAGED_HASHES="$RUN_DIR/staged-overlay.sha256"
(
	cd "$STAGE" || exit 1
	while IFS= read -r _rel; do
		shasum -a 256 -- "$_rel"
	done <"$OVERLAY_LIST"
) >"$STAGED_HASHES" 2>"$LOGS/shasum-staged.log" || \
	fatal 2 "could not hash staged overlay files; see $LOGS/shasum-staged.log"
cmp -s "$OVERLAY_HASHES" "$STAGED_HASHES" || \
	fatal 1 "staged overlay hashes differ from the owned source overlay"
OVERLAY_MANIFEST_SHA=$(shasum -a 256 "$OVERLAY_HASHES" | awk '{print $1}')
OVERLAY_COUNT=$(awk 'END {print NR}' "$OVERLAY_LIST")
echo "overlay_file_count=$OVERLAY_COUNT" >>"$SUMMARY"
echo "overlay_manifest_sha256=$OVERLAY_MANIFEST_SHA" >>"$SUMMARY"
echo "overlay_file_count=$OVERLAY_COUNT"
echo "overlay_manifest_sha256=$OVERLAY_MANIFEST_SHA"
cat "$OVERLAY_HASHES" >>"$SUMMARY"

# Serialize the whole bounded engine sequence on the coordinator lock. The lock
# is held by this shell and is released by the kernel if the shell exits.
exec 9<>"$LOCK_FILE" 2>"$LOGS/lock-open.log" || \
	fatal 2 "cannot open shared lock file: $LOCK_FILE"
if ! lockf -t "$LOCK_WAIT_S" 9 2>"$LOGS/lock-acquire.log"; then
	fatal 2 "timed out after ${LOCK_WAIT_S}s waiting for shared lock: $LOCK_FILE"
fi
echo "shared_lock_acquired=$LOCK_FILE" >>"$SUMMARY"
echo "[cosmetic-damage] shared lock acquired: $LOCK_FILE"

PINNED="4.7.2.stable.official.ed1daf0bf"
if [ -r "$STAGE/tools/toolchain/pin/engine.txt" ]; then
	PINNED_FROM_FILE=$(sed -n 's/^version_string=//p' "$STAGE/tools/toolchain/pin/engine.txt" | head -n 1)
	[ -n "$PINNED_FROM_FILE" ] && PINNED=$PINNED_FROM_FILE
fi

echo "[cosmetic-damage] checking pinned engine: $GODOT_BIN"
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
echo "godot_version=$ACTUAL_VERSION"

echo "[cosmetic-damage] importing frozen private project"
IMPORT_LOG="$LOGS/godot-import.log"
: >"$IMPORT_LOG"
run_godot "$RUN_DIR/import.pid" "$IMPORT_LOG" "$GODOT_BIN" --headless --path "$STAGE" --import
IMPORT_RC=$?
echo "import_rc=$IMPORT_RC" >>"$SUMMARY"
if [ "$IMPORT_RC" -ne 0 ]; then
	fatal 1 "headless import exited $IMPORT_RC or timed out; see $IMPORT_LOG"
fi
if ! engine_log_clean "$IMPORT_LOG"; then
	fatal 1 "headless import reported engine errors; see $IMPORT_LOG"
fi

status=0
probe_allowed=1

VALIDATOR_LOG="$LOGS/cosmetic-damage-validator.log"
SUMMARY_JSON="$STAGE/cosmetic_damage_summary.json"
: >"$VALIDATOR_LOG"
echo "[cosmetic-damage] running cosmetic-damage contract validator"
run_godot "$RUN_DIR/validator.pid" "$VALIDATOR_LOG" \
	"$GODOT_BIN" --headless --fixed-fps 60 --path "$STAGE" \
	--script res://tools/cosmetic_damage_lab/validate_cosmetic_damage_lab.gd \
	-- --summary-out="$SUMMARY_JSON"
VALIDATOR_RC=$?
echo "validator_rc=$VALIDATOR_RC" >>"$SUMMARY"
if [ "$VALIDATOR_RC" -ne 0 ]; then
	echo "run_validation: validator exited $VALIDATOR_RC" >&2
	status=1
	probe_allowed=0
fi
if ! engine_log_clean "$VALIDATOR_LOG"; then
	echo "run_validation: validator log reported engine errors" >&2
	status=1
	probe_allowed=0
fi
VALIDATOR_SUMMARY=$(grep '^COSMETIC_DAMAGE_LAB_SUMMARY ' "$VALIDATOR_LOG" | tail -n 1)
if [ -z "$VALIDATOR_SUMMARY" ]; then
	echo "run_validation: validator produced no COSMETIC_DAMAGE_LAB_SUMMARY" >&2
	status=1
	probe_allowed=0
fi
case "$VALIDATOR_SUMMARY" in
*'"pass":true'*) ;;
*)
	echo "run_validation: validator did not report pass=true" >&2
	status=1
	probe_allowed=0
;;
esac
CHECKS_LINE=$(grep '^CHECKS_TOTAL=' "$VALIDATOR_LOG" | tail -n 1)
VALIDATOR_TOTAL=${CHECKS_LINE%% *}
VALIDATOR_TOTAL=${VALIDATOR_TOTAL#CHECKS_TOTAL=}
VALIDATOR_FAILED=${CHECKS_LINE##*CHECKS_FAILED=}
echo "validator_checks_total=$VALIDATOR_TOTAL" >>"$SUMMARY"
echo "validator_checks_failed=$VALIDATOR_FAILED" >>"$SUMMARY"
positive_integer "$VALIDATOR_TOTAL" || {
	echo "run_validation: validator produced no positive CHECKS_TOTAL" >&2
	status=1
	probe_allowed=0
}
if [ "$VALIDATOR_FAILED" != "0" ]; then
	echo "run_validation: validator reported CHECKS_FAILED=$VALIDATOR_FAILED" >&2
	status=1
	probe_allowed=0
fi
echo "[cosmetic-damage] validator rc=$VALIDATOR_RC checks_total=$VALIDATOR_TOTAL checks_failed=$VALIDATOR_FAILED"
tail -n 40 "$VALIDATOR_LOG"

if [ "$probe_allowed" -eq 1 ]; then
	PROBE_LOG="$LOGS/cosmetic-damage-failure-probe.log"
	: >"$PROBE_LOG"
	echo "[cosmetic-damage] running deliberate failure probe (nonzero exit expected)"
	run_godot "$RUN_DIR/failure-probe.pid" "$PROBE_LOG" \
		"$GODOT_BIN" --headless --fixed-fps 60 --path "$STAGE" \
		--script res://tools/cosmetic_damage_lab/failure_probe.gd
	PROBE_RC=$?
	echo "failure_probe_rc=$PROBE_RC" >>"$SUMMARY"
	if [ "$PROBE_RC" -eq 0 ]; then
		echo "run_validation: failure probe exited 0; failing checks are not detectable" >&2
		status=1
	fi
	if ! engine_log_clean "$PROBE_LOG"; then
		echo "run_validation: failure probe log reported engine errors" >&2
		status=1
	fi
	PROBE_RESULT=$(grep '^COSMETIC_DAMAGE_LAB_FAILURE_PROBE ' "$PROBE_LOG" | tail -n 1)
	case "$PROBE_RESULT" in
	*'"pass":false'*) ;;
	*)
		echo "run_validation: failure probe did not report pass=false" >&2
		status=1
	;;
	esac
	PROBE_CHECKS_LINE=$(grep '^CHECKS_TOTAL=' "$PROBE_LOG" | tail -n 1)
	echo "failure_probe_checks_line=$PROBE_CHECKS_LINE" >>"$SUMMARY"
	case "$PROBE_CHECKS_LINE" in
	*CHECKS_FAILED=[1-9]*) ;;
	*)
		echo "run_validation: failure probe did not report a failing check" >&2
		status=1
	;;
	esac
	echo "[cosmetic-damage] failure probe rc=$PROBE_RC"
	tail -n 20 "$PROBE_LOG"
else
	echo "[cosmetic-damage] skipping deliberate failure probe: validator did not pass" >&2
fi

if [ -n "$LOG_FILE" ]; then
	tail -c 2097152 "$VALIDATOR_LOG" >"$LOG_FILE" || status=1
	echo "[cosmetic-damage] validator log copied to $LOG_FILE (bounded to 2 MiB)"
fi

if [ -n "$SUMMARY_OUT" ]; then
	if [ -r "$SUMMARY_JSON" ]; then
		tail -c 4194304 "$SUMMARY_JSON" >"$SUMMARY_OUT" || status=1
		echo "[cosmetic-damage] structured summary written to $SUMMARY_OUT"
	else
		echo "run_validation: validator wrote no structured summary" >&2
		status=1
	fi
fi

echo "runner_status=$status" >>"$SUMMARY"
if [ -n "$EVIDENCE_OUT" ]; then
	cp "$SUMMARY" "$EVIDENCE_OUT" || status=1
	echo "[cosmetic-damage] runner evidence written to $EVIDENCE_OUT"
fi

if [ "$KEEP_SCRATCH" -eq 1 ]; then
	echo "[cosmetic-damage] frozen stage and logs kept in $RUN_DIR"
fi

if [ "$status" -eq 0 ]; then
	echo "[cosmetic-damage] PASS (frozen archive HEAD: $HEAD_SHA)"
else
	echo "[cosmetic-damage] FAIL (frozen archive HEAD: $HEAD_SHA)" >&2
fi
exit "$status"
