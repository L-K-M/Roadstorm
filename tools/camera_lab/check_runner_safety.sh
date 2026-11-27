#!/bin/sh
# Non-destructive safety controls for tools/camera_lab/run_validation.sh.
#
# All scratch lives in one mktemp root this script owns and removes on exit.
# The recording stub stands in as --godot so refusal cases can prove no Godot
# invocation was reached; the accepted-destination cases stage and invoke it
# and are expected to exit 1 because the stub emits no CHECKS_TOTAL line.
#
# The single "live project" control names a fresh, uniquely named missing
# parent under this tool's owned directory and asserts the runner created
# nothing there. No existing user path is removed or altered anywhere.
#
# Usage: tools/camera_lab/check_runner_safety.sh
# Exit 0 = every control passed, 1 = at least one failed, 2 = setup failure.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUNNER="${RUNNER:-$SCRIPT_DIR/run_validation.sh}"
LIVE_PROJECT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/camera-lab-safety-XXXXXX") || exit 2
PASS=0
FAIL=0

cleanup() {
	rm -rf "$ROOT"
}
trap cleanup EXIT HUP INT TERM

record() {
	if [ "$1" = "pass" ]; then
		PASS=$((PASS + 1))
		echo "PASS $2"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL $2: $3"
	fi
}

run_runner() {
	rm -f "$ROOT/godot_invocations.log"
	"$RUNNER" --project "$PROJ" --godot "$FAKE" --timeout 10 "$@" >"$ROOT/out.txt" 2>&1
	status=$?
	if [ "${SAFETY_VERBOSE:-0}" = "1" ]; then
		cat "$ROOT/out.txt"
	fi
	printf '%s\n' "$status"
}

if [ ! -f "$RUNNER" ]; then
	echo "FAIL runner not found: $RUNNER"
	exit 2
fi

if sh -n "$RUNNER"; then
	record pass "sh -n run_validation.sh"
else
	record fail "sh -n run_validation.sh" "shell syntax error"
fi

PROJ="$ROOT/proj"
mkdir -p "$PROJ/src" "$PROJ/tools/toolchain/pin"
printf '[application]\nconfig/name="synthetic"\n' > "$PROJ/project.godot"
echo marker > "$PROJ/src/marker.txt"
printf 'version_string=4.7.2.stable.official.ed1daf0bf\n' > "$PROJ/tools/toolchain/pin/engine.txt"

FAKE="$ROOT/fake_godot.sh"
cat > "$FAKE" <<EOF
#!/bin/sh
if [ "\${1:-}" = "--version" ]; then
	echo "4.7.2.stable.official.ed1daf0bf"
	exit 0
fi
echo "invoked: \$*" >> "$ROOT/godot_invocations.log"
exit 0
EOF
chmod +x "$FAKE"

# 1. Missing parent inside the synthetic project's non-work tree: refused
#    side-effect-free, before any Godot invocation.
stale="$PROJ/src/missing/child"
st=$(run_runner --private-dir "$stale")
if [ "$st" -eq 2 ] \
	&& [ ! -e "$PROJ/src/missing" ] \
	&& [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "missing parent in project non-work tree refused without side effects"
else
	record fail "missing parent in project non-work tree refused without side effects" \
		"status=$st created=$([ -e "$PROJ/src/missing" ] && echo yes || echo no)"
fi

# 2. Same control against the live checkout: a fresh path under this tool's
#    owned directory, asserted absent afterwards.
live_parent="$LIVE_PROJECT/tools/camera_lab/.safety_missing_parent_test/child"
live_dest="$LIVE_PROJECT/tools/camera_lab/.safety_missing_parent_test/child/private"
rm -f "$ROOT/godot_invocations.log"
"$RUNNER" --project "$LIVE_PROJECT" --godot "$FAKE" --timeout 10 \
	--private-dir "$live_dest" >"$ROOT/out-live.txt" 2>&1
live_status=$?
if [ "$live_status" -eq 2 ] \
	&& [ ! -e "$LIVE_PROJECT/tools/camera_lab/.safety_missing_parent_test" ] \
	&& [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "live-project missing parent refused without side effects"
else
	record fail "live-project missing parent refused without side effects" \
		"status=$live_status created=$([ -e "$LIVE_PROJECT/tools/camera_lab/.safety_missing_parent_test" ] && echo yes || echo no)"
fi

# 3. Existing parent, unsafe non-work destination: refused with nothing created.
unsafe="$PROJ/inside"
st=$(run_runner --private-dir "$unsafe")
if [ "$st" -eq 2 ] && [ ! -e "$unsafe" ] && [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "unsafe containment with existing parent refused without side effects"
else
	record fail "unsafe containment with existing parent refused without side effects" \
		"status=$st created=$([ -e "$unsafe" ] && echo yes || echo no)"
fi

# 4. Occupied directory: sentinel preserved, no invocation.
occ="$ROOT/occupied"
mkdir "$occ"
echo sentinel > "$occ/sentinel.txt"
st=$(run_runner --private-dir "$occ")
if [ "$st" -eq 2 ] \
	&& [ "$(cat "$occ/sentinel.txt" 2>/dev/null)" = "sentinel" ] \
	&& [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "occupied directory refused with sentinel intact"
else
	record fail "occupied directory refused with sentinel intact" \
		"status=$st sentinel=$(cat "$occ/sentinel.txt" 2>/dev/null)"
fi

# 5. Symlink: refused even though its target is an unrelated file.
echo target-sentinel > "$ROOT/sym_target"
ln -s "$ROOT/sym_target" "$ROOT/sym_link"
st=$(run_runner --private-dir "$ROOT/sym_link")
if [ "$st" -eq 2 ] \
	&& [ -L "$ROOT/sym_link" ] \
	&& [ "$(cat "$ROOT/sym_target" 2>/dev/null)" = "target-sentinel" ] \
	&& [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "symlink refused with target preserved"
else
	record fail "symlink refused with target preserved" "status=$st"
fi

# 6. Dangling symlink: refused before any copy.
ln -s "$ROOT/does_not_exist" "$ROOT/dangling"
st=$(run_runner --private-dir "$ROOT/dangling")
if [ "$st" -eq 2 ] && [ -L "$ROOT/dangling" ] && [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "dangling symlink refused"
else
	record fail "dangling symlink refused" "status=$st"
fi

# 7. Existing regular file: refused with contents preserved.
echo file-sentinel > "$ROOT/a_file"
st=$(run_runner --private-dir "$ROOT/a_file")
if [ "$st" -eq 2 ] \
	&& [ "$(cat "$ROOT/a_file")" = "file-sentinel" ] \
	&& [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "occupied file refused with contents preserved"
else
	record fail "occupied file refused with contents preserved" \
		"status=$st content=$(cat "$ROOT/a_file" 2>/dev/null)"
fi

# 8. Allowed fresh work/ destination: staged and invoked (stub yields exit 1
#    because it emits no CHECKS_TOTAL line).
allowed_parent="$PROJ/work/agents/job"
mkdir -p "$allowed_parent"
allowed="$allowed_parent/private"
st=$(run_runner --private-dir "$allowed")
if [ "$st" -eq 1 ] \
	&& [ -f "$allowed/project.godot" ] \
	&& [ -f "$allowed/src/marker.txt" ] \
	&& [ -f "$ROOT/godot_invocations.log" ]; then
	record pass "allowed fresh work/ destination staged and invoked"
else
	record fail "allowed fresh work/ destination staged and invoked" \
		"status=$st project=$([ -f "$allowed/project.godot" ] && echo yes || echo no)"
fi

# 9. Fresh explicit destination outside the project with an existing parent:
#    staged and invoked.
fresh_parent="$ROOT/fresh_parent"
mkdir "$fresh_parent"
fresh="$fresh_parent/private"
st=$(run_runner --private-dir "$fresh")
if [ "$st" -eq 1 ] \
	&& [ -f "$fresh/project.godot" ] \
	&& [ -f "$fresh/src/marker.txt" ] \
	&& [ -f "$ROOT/godot_invocations.log" ]; then
	record pass "fresh external private dir staged and invoked"
else
	record fail "fresh external private dir staged and invoked" "status=$st"
fi

# 10. Default temporary copy: auto-created, invoked, auto-cleaned.
st=$(run_runner)
if [ "$st" -eq 1 ] \
	&& [ -f "$ROOT/godot_invocations.log" ] \
	&& grep -q '\[run-validation\]' "$ROOT/out.txt"; then
	record pass "default temporary private dir used"
else
	record fail "default temporary private dir used" "status=$st"
fi

echo "SAFETY_CHECKS_TOTAL=$((PASS + FAIL)) SAFETY_CHECKS_FAILED=$FAIL"
if [ "$FAIL" -ne 0 ]; then
	exit 1
fi
exit 0
