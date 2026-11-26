#!/bin/sh
# Roadstorm Racer! - fault-injection verification for the boot smoke check.
#
# Ownership: tools/smoke/**.
#
# Proves that the smoke check really fails (nonzero exit) when it should.
# Cases:
#   1. clean tree                            -> expect PASS (exit 0)
#   2. --expect-failure control              -> expect FAIL (exit 1)
#   3. GDScript parse error in game.gd       -> expect FAIL
#   4. runtime error in game.gd::_ready      -> expect FAIL (the scene still
#                                                loads; only the engine
#                                                output, and the wrapper,
#                                                can see the error)
#   5. runtime error in main_menu.gd::_ready -> expect FAIL (breaks the ready
#                                                marker: the quit button is
#                                                never connected)
#   6. detached script in game.tscn          -> expect FAIL
#   7. physics/3d/physics_engine absent      -> expect FAIL (the 3D backend is
#                                                no longer named explicitly)
#   8. physics/3d/physics_engine misspelled  -> expect FAIL (a typo is not the
#                                                pinned backend name)
#
# Isolation: every case runs against a throwaway snapshot copy of the
# checkout (no .git, no .godot, no work/) in a private temporary directory
# with its own HOME and TMPDIR, so the engine cache never touches the live
# tree. The live sources, scenes and scripts are never edited; the harness
# verifies that with checksums before and after and refuses to report success
# if anything in src/boot/ or scenes/ changed. project.godot is likewise only
# ever read from the live checkout and written in the snapshot.
#
# Usage:
#   tools/smoke/fault_injection.sh
#   GODOT_BIN=/path/to/godot tools/smoke/fault_injection.sh
#
# Exit codes: 0 = every case behaved as expected, 1 = a case misbehaved,
# 2 = the harness could not run.
# Original project code under the Unlicense.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"

log() {
	echo "[fault-injection] $*"
}

die() {
	code="$1"
	shift
	log "FAIL: $*" >&2
	exit "$code"
}

[ -n "$GODOT_BIN" ] || GODOT_BIN="$(command -v godot 2>/dev/null || true)"
[ -n "$GODOT_BIN" ] || die 2 "no Godot binary found; set GODOT_BIN"
[ -d "$PROJECT_DIR" ] || die 2 "project directory '$PROJECT_DIR' does not exist"

if command -v shasum >/dev/null 2>&1; then
	SHA_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
	SHA_CMD="sha256sum"
else
	die 2 "no sha256 tool found (shasum or sha256sum)"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roadstorm-fault-injection.XXXXXX" 2>/dev/null)" || die 2 "could not create a temporary working directory"
trap 'rm -rf "$WORK_DIR"' EXIT

SNAPSHOT="$WORK_DIR/snapshot"
SANDBOX_HOME="$WORK_DIR/home"
SANDBOX_TMP="$WORK_DIR/tmp"
PRISTINE_PROJECT_GODOT="$WORK_DIR/project.godot.pristine"

# --- helpers -----------------------------------------------------------------

# Checksums of the files fault injection is allowed to touch (in the snapshot
# only). Used to prove the live checkout is never modified.
live_fingerprint() {
	(cd "$PROJECT_DIR" && find src/boot scenes -type f -exec $SHA_CMD {} + 2>/dev/null | LC_ALL=C sort)
}

# Fresh snapshot of the checkout without VCS data, the engine cache or agent
# work directories.
make_snapshot() {
	rm -rf "$SNAPSHOT"
	mkdir -p "$SNAPSHOT"
	(cd "$PROJECT_DIR" && tar -cf - --exclude=./.git --exclude=./.godot --exclude=./work .) |
		(cd "$SNAPSHOT" && tar -xf -)
}

# Restore the injectable files from the live checkout and drop the snapshot's
# engine cache, so each case starts from a clean, cold state. project.godot is
# restored from the copy taken at harness start (see PRISTINE_PROJECT_GODOT),
# so a case that edits it cannot leak into the next case.
reset_snapshot() {
	rm -rf "$SNAPSHOT/src/boot" "$SNAPSHOT/scenes"
	cp -R "$PROJECT_DIR/src/boot" "$SNAPSHOT/src/boot"
	cp -R "$PROJECT_DIR/scenes" "$SNAPSHOT/scenes"
	cp "$PRISTINE_PROJECT_GODOT" "$SNAPSHOT/project.godot"
	rm -rf "$SNAPSHOT/.godot"
}

# Edit physics/3d/physics_engine in the snapshot's project.godot.
#   inject_setting_change absent      drop the entry (and its comment block)
#   inject_setting_change misspelled  replace the value with a transposed typo
# The rest of the [physics] section (60 ticks/second, interpolation) is left
# alone, so the failure can only come from the physics-engine assertion.
inject_setting_change() {
	# inject_setting_change <absent|misspelled>
	python3 - "$SNAPSHOT/project.godot" "$1" <<'PYEOF'
import sys

path = sys.argv[1]
mode = sys.argv[2]
key = "3d/physics_engine="

with open(path, "r", encoding="utf-8") as handle:
	lines = handle.read().splitlines(keepends=True)

index = None
for position, line in enumerate(lines):
	if line.startswith(key):
		index = position
		break
if index is None:
	sys.exit("no %s line found in %s" % (key, path))

if mode == "absent":
	start = index
	while start > 0 and lines[start - 1].lstrip().startswith(";"):
		start -= 1
	del lines[start:index + 1]
elif mode == "misspelled":
	lines[index] = '3d/physics_engine="Jolt Phsyics"\n'
else:
	sys.exit("unknown mode %r" % mode)

with open(path, "w", encoding="utf-8") as handle:
	handle.write("".join(lines))
PYEOF
}

# Insert a runtime error at the top of a _ready() function in a snapshot copy.
# The script still parses; the scene still loads; only the engine output and
# the wrapper's error scan can see the failure.
inject_runtime_error() {
	# inject_runtime_error <snapshot-relative-path>
	python3 - "$SNAPSHOT/$1" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
	source = handle.read()
needle = "func _ready() -> void:\n"
if needle not in source:
	sys.exit("no _ready() found in %s" % path)
source = source.replace(needle, needle + '\tget_node("NoSuchNode").queue_free()\n', 1)
with open(path, "w", encoding="utf-8") as handle:
	handle.write(source)
PYEOF
}

CASES_RUN=0
CASES_OK=0

# run_case <description> <pass|fail> [extra wrapper args...]
# The current snapshot state is the case input; injection happens before the
# call and reset_snapshot after it.
run_case() {
	desc="$1"
	expect="$2"
	shift 2
	CASES_RUN=$((CASES_RUN + 1))

	rm -rf "$SNAPSHOT/.godot"
	output="$(cd "$SNAPSHOT" && PROJECT_DIR="$SNAPSHOT" GODOT_BIN="$GODOT_BIN" \
		HOME="$SANDBOX_HOME" TMPDIR="$SANDBOX_TMP" \
		"$SNAPSHOT/tools/smoke/run_boot_smoke.sh" "$@" 2>&1)"
	status=$?

	verdict_line="$(printf '%s\n' "$output" | grep -E 'boot-smoke\] (PASS|RESULT)' | tail -n 1)"
	error_line="$(printf '%s\n' "$output" | grep -E 'SCRIPT ERROR|Failed to load script|^ERROR:' | head -n 1)"

	ok=no
	if [ "$expect" = "pass" ]; then
		[ "$status" -eq 0 ] && ok=yes
	else
		[ "$status" -ne 0 ] && ok=yes
	fi
	if [ "$ok" = "yes" ]; then
		CASES_OK=$((CASES_OK + 1))
	fi

	log "case $CASES_RUN: $desc"
	log "  expected: $expect / observed exit: $status -> $ok"
	if [ -n "$verdict_line" ]; then
		log "  smoke verdict: $verdict_line"
	fi
	if [ -n "$error_line" ]; then
		log "  engine error: $error_line"
	fi
	if [ "$ok" = "no" ]; then
		log "  --- case output ---"
		printf '%s\n' "$output" | sed 's/^/  | /' >&2
		log "  --- end case output ---"
	fi
}

# --- setup -------------------------------------------------------------------

log "project: $PROJECT_DIR"
log "godot:   $GODOT_BIN ($("$GODOT_BIN" --version 2>/dev/null || echo 'version unknown'))"
log "workdir: $WORK_DIR"

BEFORE="$(live_fingerprint)"
[ -n "$BEFORE" ] || die 2 "could not checksum src/boot and scenes in $PROJECT_DIR"
LIVE_GODOT_BEFORE=no
[ -e "$PROJECT_DIR/.godot" ] && LIVE_GODOT_BEFORE=yes
[ "$LIVE_GODOT_BEFORE" = yes ] && log "note: the live checkout already had a .godot cache directory before this run"

mkdir -p "$SANDBOX_HOME" "$SANDBOX_TMP"
[ -f "$PROJECT_DIR/project.godot" ] || die 2 "'$PROJECT_DIR' has no project.godot"
cp "$PROJECT_DIR/project.godot" "$PRISTINE_PROJECT_GODOT" || die 2 "could not copy project.godot"
make_snapshot
[ -f "$SNAPSHOT/tools/smoke/run_boot_smoke.sh" ] || die 2 "snapshot is missing tools/smoke/run_boot_smoke.sh"

# --- cases -------------------------------------------------------------------

# 1. Clean snapshot: the check must pass.
run_case "clean snapshot passes" pass

# 2. Control: the documented --expect-failure flag must exit nonzero.
reset_snapshot
run_case "--expect-failure control exits nonzero" fail --expect-failure

# 3. Parse error: the script fails to attach; the scene-structure checks must
#    fail the run even though the boot handoff still completes.
reset_snapshot
printf '\nthis is not valid gdscript ((\n' >>"$SNAPSHOT/src/boot/game.gd"
run_case "parse error in src/boot/game.gd fails" fail

# 4. Runtime error in the game scene's _ready: the scene still loads and the
#    structure checks still pass; only the engine output shows the error, so
#    this case exercises the wrapper's error scan.
reset_snapshot
inject_runtime_error "src/boot/game.gd"
run_case "runtime error in game.gd::_ready fails" fail

# 5. Runtime error in the menu's _ready: the quit button is never connected,
#    so the in-script ready-marker check must fail as well.
reset_snapshot
inject_runtime_error "src/boot/main_menu.gd"
run_case "runtime error in main_menu.gd::_ready fails" fail

# 6. Detached script: game.tscn points at a script that does not exist.
reset_snapshot
sed -i.bak 's|path="res://src/boot/game.gd"|path="res://src/boot/does_not_exist.gd"|' "$SNAPSHOT/scenes/game.tscn"
rm -f "$SNAPSHOT/scenes/game.tscn.bak"
run_case "detached script in scenes/game.tscn fails" fail

# 7. Absent physics engine setting: the entry is removed from the snapshot's
#    project.godot, so the 3D backend is no longer named explicitly.
reset_snapshot
inject_setting_change absent
run_case "physics/3d/physics_engine absent fails" fail

# 8. Misspelled physics engine setting: a transposed value is not the pinned
#    backend name, and it is not a valid engine value either.
reset_snapshot
inject_setting_change misspelled
run_case "physics/3d/physics_engine misspelled fails" fail

# --- isolation verification ---------------------------------------------------

AFTER="$(live_fingerprint)"
if [ "$BEFORE" != "$AFTER" ]; then
	log "FAIL: the live checkout changed during fault injection" >&2
	printf '%s\n' "$BEFORE" >"$WORK_DIR/before.txt"
	printf '%s\n' "$AFTER" >"$WORK_DIR/after.txt"
	diff "$WORK_DIR/before.txt" "$WORK_DIR/after.txt" >&2 || true
	die 1 "live src/boot/ or scenes/ files were modified"
fi
LIVE_GODOT_AFTER=no
[ -e "$PROJECT_DIR/.godot" ] && LIVE_GODOT_AFTER=yes
if [ "$LIVE_GODOT_BEFORE" = no ] && [ "$LIVE_GODOT_AFTER" = yes ]; then
	die 1 "a .godot cache directory appeared in the live checkout"
fi
log "isolation verified: live src/boot/ and scenes/ are unchanged and no cache leaked into the checkout"

# --- summary ------------------------------------------------------------------

log "summary: $CASES_OK/$CASES_RUN cases behaved as expected"
if [ "$CASES_OK" -eq "$CASES_RUN" ]; then
	log "PASS: fault-injection verification"
	exit 0
fi
die 1 "$((CASES_RUN - CASES_OK)) case(s) did not behave as expected"
