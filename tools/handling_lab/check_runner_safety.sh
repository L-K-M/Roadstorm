#!/bin/sh
# Non-destructive safety controls for tools/handling_lab/run_validation.sh.
#
# Everything happens inside one mktemp root that the script owns and removes on
# exit. The control never touches the repository, the live project or any
# caller supplied path. It uses a recording stub as --godot so it can prove
# whether the runner reached a Godot invocation; the accepted-path case is
# expected to exit 1 because the stub emits no CHECKS_TOTAL line.
#
# Usage: tools/handling_lab/check_runner_safety.sh
# Exit 0 = every control passed, 1 = at least one failed, 2 = setup failure.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUNNER="${RUNNER:-$SCRIPT_DIR/run_validation.sh}"

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/handling-lab-safety-XXXXXX") || exit 2
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
mkdir -p "$PROJ/src"
printf '[application]\nconfig/name="synthetic"\n' > "$PROJ/project.godot"
echo marker > "$PROJ/src/marker.txt"

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

# 1. Occupied directory: refuse, preserve sentinel, never invoke Godot.
occ="$ROOT/occupied"
mkdir "$occ"
echo sentinel > "$occ/sentinel.txt"
st=$(run_runner --private-dir "$occ")
if [ "$st" -eq 2 ] \
	&& [ "$(cat "$occ/sentinel.txt" 2>/dev/null)" = "sentinel" ] \
	&& [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "occupied directory refused with sentinel intact"
else
	record fail "occupied directory refused with sentinel intact" "status=$st sentinel=$(cat "$occ/sentinel.txt" 2>/dev/null)"
fi

# 2. Symlink: refuse even though its target is an unrelated file.
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

# 3. Dangling symlink: refuse before any copy.
ln -s "$ROOT/does_not_exist" "$ROOT/dangling"
st=$(run_runner --private-dir "$ROOT/dangling")
if [ "$st" -eq 2 ] && [ -L "$ROOT/dangling" ] && [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "dangling symlink refused"
else
	record fail "dangling symlink refused" "status=$st"
fi

# 4. Existing regular file: refuse.
echo file-sentinel > "$ROOT/a_file"
st=$(run_runner --private-dir "$ROOT/a_file")
if [ "$st" -eq 2 ] && [ "$(cat "$ROOT/a_file")" = "file-sentinel" ] && [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "occupied file refused with contents preserved"
else
	record fail "occupied file refused with contents preserved" "status=$st"
fi

# 5. Unsafe containment: fresh private dir inside the source project, outside
#    the ignored work/ root, must be refused without creating anything.
st=$(run_runner --private-dir "$PROJ/inside")
if [ "$st" -eq 2 ] && [ ! -e "$PROJ/inside" ] && [ ! -e "$ROOT/godot_invocations.log" ]; then
	record pass "inside-project private dir refused"
else
	record fail "inside-project private dir refused" "status=$st created=$([ -e "$PROJ/inside" ] && echo yes || echo no)"
fi

# 6. Allowed containment: the repository's ignored work/ scratch root. Staging
#    excludes work/, so this is safe; the destination itself is excluded too.
allowed="$PROJ/work/agents/job/private"
st=$(run_runner --private-dir "$allowed")
if [ "$st" -eq 1 ] && [ -f "$allowed/project.godot" ] && [ -f "$ROOT/godot_invocations.log" ]; then
	record pass "work/ private dir staged and invoked"
else
	record fail "work/ private dir staged and invoked" "status=$st"
fi

# 7. Fresh explicit private dir outside the project: accepted and staged.
fresh="$ROOT/fresh"
st=$(run_runner --private-dir "$fresh")
if [ "$st" -eq 1 ] \
	&& [ -f "$fresh/project.godot" ] \
	&& [ -f "$fresh/src/marker.txt" ] \
	&& [ -f "$ROOT/godot_invocations.log" ]; then
	record pass "fresh explicit private dir staged and invoked"
else
	record fail "fresh explicit private dir staged and invoked" "status=$st"
fi

# 8. Default private dir: auto-created temporary copy, invoked, then cleaned.
st=$(run_runner)
if [ "$st" -eq 1 ] && [ -f "$ROOT/godot_invocations.log" ] && grep -q '\[run-validation\]' "$ROOT/out.txt"; then
	record pass "default temporary private dir used"
else
	record fail "default temporary private dir used" "status=$st"
fi

echo "SAFETY_CHECKS_TOTAL=$((PASS + FAIL)) SAFETY_CHECKS_FAILED=$FAIL"
if [ "$FAIL" -ne 0 ]; then
	exit 1
fi
exit 0
