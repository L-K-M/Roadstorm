#!/bin/sh
# Focused regressions for tools/python_pin/verify.sh.
#
# Every fixture is a private copy of the pin data plus a fresh synthetic
# regular file named like a pinned artifact; the copy's expected digest is
# overridden to that file's sha256. Nothing here writes to the repository,
# the real pin, installed interpreters, or another job's files. Ephemeral
# symlink/hard-link alias fixtures exist only inside the private temporary
# directory, because refusing them is part of the contract; they are removed
# with it and never link into shared inputs.
#
# Run: sh tools/python_pin/tests/test_verify.sh
# Exit: 0 = all assertions passed, 1 = at least one failed.

set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
VERIFY="$PIN_ROOT/verify.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/python-pin-tests.XXXXXX" 2>/dev/null)" ||
	WORK="${TMPDIR:-/tmp}/python-pin-tests.$$"
mkdir -p "$WORK" || exit 2
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM HUP

PASS=0
FAIL=0
FAILURES=""

assert_eq() { # description expected actual
	if [ "$2" = "$3" ]; then
		PASS=$((PASS + 1))
		printf 'ok   %s\n' "$1"
	else
		FAIL=$((FAIL + 1))
		FAILURES="$FAILURES
  - $1 (expected [$2], got [$3])"
		printf 'FAIL %s\n     expected: [%s]\n     actual:   [%s]\n' "$1" "$2" "$3"
	fi
}

assert_contains() { # description haystack needle
	case "$2" in
		*"$3"*)
			PASS=$((PASS + 1))
			printf 'ok   %s\n' "$1" ;;
		*)
			FAIL=$((FAIL + 1))
			FAILURES="$FAILURES
  - $1 (missing [$3])"
			printf 'FAIL %s\n     missing: [%s]\n' "$1" "$3" ;;
	esac
}

assert_not_contains() { # description haystack needle
	case "$2" in
		*"$3"*)
			FAIL=$((FAIL + 1))
			FAILURES="$FAILURES
  - $1 (unexpected [$3])"
			printf 'FAIL %s\n     unexpected: [%s]\n' "$1" "$3" ;;
		*)
			PASS=$((PASS + 1))
			printf 'ok   %s\n' "$1" ;;
	esac
}

# Canonical absolute path, matching verify.sh's realpath-based resolution.
real_path() {
	if command -v realpath >/dev/null 2>&1; then
		realpath "$1" 2>/dev/null || printf '%s\n' "$1"
	else
		printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"
	fi
}

sha256_file() {
	if command -v shasum >/dev/null 2>&1; then
		_out="$(shasum -a 256 - < "$1" 2>/dev/null)" || return 1
	elif command -v sha256sum >/dev/null 2>&1; then
		_out="$(sha256sum - < "$1" 2>/dev/null)" || return 1
	else
		return 1
	fi
	_hash="${_out%% *}"
	[ "${#_hash}" -eq 64 ] || return 1
	printf '%s\n' "$_hash"
}

# Create an isolated fixture: a copy of verify.sh and pin/, plus one synthetic
# archive whose published digest is recorded as an override in the copy.
new_fixture() {
	_name="$1"
	_dir="$WORK/$_name"
	mkdir -p "$_dir" || return 1
	cp "$VERIFY" "$_dir/verify.sh" || return 1
	cp -R "$PIN_ROOT/pin" "$_dir/pin" || return 1
	printf 'synthetic archive bytes for %s\n' "$_name" > "$_dir/python-3.15.2-macos11.pkg"
	_sha="$(sha256_file "$_dir/python-3.15.2-macos11.pkg")" || return 1
	printf 'macos_pkg_sha256=%s\n' "$_sha" >> "$_dir/pin/python.txt"
	printf '%s' "$_dir"
}

# Fake interpreter that appends one line to $2 per invocation, then answers
# the two probes verify.sh makes regardless of their exact flags. A separate
# failing stub never answers.
make_counting_fake() {
	_file="$1"; _marker="$2"
	cat > "$_file" <<EOF
#!/bin/sh
printf 'x\n' >> "$_marker"
printf '3.15.2\n'
exit 0
EOF
	chmod +x "$_file"
}

# Fake interpreter that also records every argument it receives, to prove the
# probe passes -I (isolated mode).
make_arg_recording_fake() {
	_file="$1"; _marker="$2"; _log="$3"
	sed -e "s|@MARKER@|$_marker|g" -e "s|@LOG@|$_log|g" > "$_file" <<'STUB'
#!/bin/sh
printf 'x\n' >> "@MARKER@"
for _a in "$@"; do printf '%s\n' "$_a" >> "@LOG@"; done
printf '3.15.2\n'
exit 0
STUB
	chmod +x "$_file"
}

make_failing_fake() {
	_file="$1"; _marker="$2"
	printf '#!/bin/sh\nprintf "x\\n" >> "%s"\nexit 1\n' "$_marker" > "$_file"
	chmod +x "$_file"
}

invocation_count() {
	[ -f "$1" ] || { printf '0'; return 0; }
	wc -l <"$1" | tr -d ' '
}

echo "regression tests for $VERIFY"
echo

# --- ordinary recording works and preserves every original -----------------
fx="$(new_fixture fresh)"
before_pkg="$(sha256_file "$fx/python-3.15.2-macos11.pkg")"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/observed.txt" 2>&1)"
rc=$?
assert_eq "fresh --record exits 0" 0 "$rc"
assert_eq "fresh --record created the requested file" "yes" \
	"$([ -f "$fx/observed.txt" ] && printf yes || printf no)"
rec="$(cat "$fx/observed.txt" 2>/dev/null)"
assert_contains "record carries the checked archive digest" "$rec" \
	"archive_python-3.15.2-macos11.pkg_sha256="
assert_eq "archive bytes preserved" "$before_pkg" \
	"$(sha256_file "$fx/python-3.15.2-macos11.pkg")"
before="$(sha256_file "$fx/pin/python.txt")"
(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/observed-2.txt" --quiet) >/dev/null 2>&1
rc2=$?
after="$(sha256_file "$fx/pin/python.txt")"
assert_eq "second run still exits 0" 0 "$rc2"
assert_eq "pin metadata bytes preserved across runs" "$before" "$after"

# --- exact input overlap: --archive FILE --record FILE ---------------------
fx="$(new_fixture overlap-archive)"
before_pkg="$(sha256_file "$fx/python-3.15.2-macos11.pkg")"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/python-3.15.2-macos11.pkg" 2>&1)"
rc=$?
assert_eq "--record equal to --archive is refused (exit 2)" 2 "$rc"
assert_contains "refusal names the overwrite protection" "$out" "refusing to overwrite"
assert_eq "archive survived the refusal" \
	"$before_pkg" "$(sha256_file "$fx/python-3.15.2-macos11.pkg")"

# Same overlap expressed through a different spelling of the path.
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/./python-3.15.2-macos11.pkg" 2>&1)"
rc=$?
assert_eq "--record equal to --archive via ./ is refused" 2 "$rc"
assert_eq "archive survived the ./ refusal" \
	"$before_pkg" "$(sha256_file "$fx/python-3.15.2-macos11.pkg")"

# --- protected pin and digest paths ----------------------------------------
fx="$(new_fixture protected-pin)"
before_pin="$(sha256_file "$fx/pin/python.txt")"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--record "$fx/pin/python.txt" 2>&1)"
rc=$?
assert_eq "--record equal to pin/python.txt is refused" 2 "$rc"
assert_eq "pin metadata survived the refusal" \
	"$before_pin" "$(sha256_file "$fx/pin/python.txt")"

before_cs="$(sha256_file "$fx/pin/checksums.txt")"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--record "$fx/pin/checksums.txt" 2>&1)"
rc=$?
assert_eq "--record equal to pin/checksums.txt is refused" 2 "$rc"
assert_eq "digest metadata survived the refusal" \
	"$before_cs" "$(sha256_file "$fx/pin/checksums.txt")"

before_pin="$(sha256_file "$fx/pin/python.txt")"
ln -s python.txt "$fx/pin-alias"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--record "$fx/pin-alias" 2>&1)"
rc=$?
assert_eq "symlink alias of pin/python.txt is refused" 2 "$rc"
assert_eq "pin metadata survived the symlink-alias refusal" \
	"$before_pin" "$(sha256_file "$fx/pin/python.txt")"
assert_eq "pin alias symlink still exists" "yes" \
	"$([ -L "$fx/pin-alias" ] && printf yes || printf no)"

# --- hard-link and symlink aliases -----------------------------------------
fx="$(new_fixture hardlink-alias)"
before_pkg="$(sha256_file "$fx/python-3.15.2-macos11.pkg")"
ln "$fx/python-3.15.2-macos11.pkg" "$fx/archive-link"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/archive-link" 2>&1)"
rc=$?
assert_eq "hard-link alias is refused" 2 "$rc"
assert_eq "hard-linked archive bytes preserved" \
	"$before_pkg" "$(sha256_file "$fx/python-3.15.2-macos11.pkg")"
assert_eq "hard link itself still exists" "yes" \
	"$([ -e "$fx/archive-link" ] && printf yes || printf no)"

fx="$(new_fixture symlink-alias)"
before_pkg="$(sha256_file "$fx/python-3.15.2-macos11.pkg")"
ln -s python-3.15.2-macos11.pkg "$fx/archive-link"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/archive-link" 2>&1)"
rc=$?
assert_eq "symlink alias is refused" 2 "$rc"
assert_eq "symlink target bytes preserved" \
	"$before_pkg" "$(sha256_file "$fx/python-3.15.2-macos11.pkg")"
assert_eq "symlink itself still exists" "yes" \
	"$([ -L "$fx/archive-link" ] && printf yes || printf no)"

fx="$(new_fixture dangling-symlink)"
ln -s no-such-target "$fx/dangling"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--record "$fx/dangling" 2>&1)"
rc=$?
assert_eq "dangling symlink target is refused" 2 "$rc"
assert_eq "dangling symlink still exists" "yes" \
	"$([ -L "$fx/dangling" ] && printf yes || printf no)"

# --- pre-existing unrelated targets ----------------------------------------
fx="$(new_fixture existing-target)"
printf 'sentinel bytes\n' > "$fx/sentinel.txt"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--record "$fx/sentinel.txt" 2>&1)"
rc=$?
assert_eq "existing regular target is refused" 2 "$rc"
assert_eq "existing target content preserved" "sentinel bytes" \
	"$(cat "$fx/sentinel.txt")"

mkdir -p "$fx/target-dir"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--record "$fx/target-dir" 2>&1)"
rc=$?
assert_eq "directory target is refused" 2 "$rc"

# --- quoted paths containing spaces (and glob characters) ------------------
fx="$(new_fixture spaces)"
mkdir -p "$fx/space dir/glob*here"
cp "$fx/python-3.15.2-macos11.pkg" "$fx/space dir/glob*here/python-3.15.2-macos11.pkg"
before_pkg="$(sha256_file "$fx/space dir/glob*here/python-3.15.2-macos11.pkg")"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--archive "$fx/space dir/glob*here/python-3.15.2-macos11.pkg" \
	--record "$fx/space dir/observed.txt" 2>&1)"
rc=$?
assert_eq "quoted path with spaces exits 0" 0 "$rc"
rec="$(cat "$fx/space dir/observed.txt" 2>/dev/null)"
assert_contains "spaced archive is recorded under its basename" "$rec" \
	"archive_python-3.15.2-macos11.pkg_sha256="
assert_eq "spaced archive bytes preserved" \
	"$before_pkg" "$(sha256_file "$fx/space dir/glob*here/python-3.15.2-macos11.pkg")"

# --archive=<path> form and several paths stay distinct arguments.
cp "$fx/python-3.15.2-macos11.pkg" "$fx/Python-3.15.2.tgz"
tgz_sha="$(sha256_file "$fx/Python-3.15.2.tgz")"
printf 'source_tgzz_sha256=%s\n' "$tgz_sha" >> "$fx/pin/python.txt"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	"--archive=$fx/Python-3.15.2.tgz" \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/multi.txt" 2>&1)"
rc=$?
assert_eq "two --archive forms exit 0" 0 "$rc"
rec="$(cat "$fx/multi.txt" 2>/dev/null)"
assert_contains "first archive recorded" "$rec" "archive_Python-3.15.2.tgz_sha256="
assert_contains "second archive recorded" "$rec" \
	"archive_python-3.15.2-macos11.pkg_sha256="

# --- --no-interpreter: no execution, no interpreter observations ------------
fx="$(new_fixture no-interpreter)"
make_counting_fake "$fx/fake-python" "$fx/marker"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--python "$fx/fake-python" \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/observed.txt" 2>&1)"
rc=$?
assert_eq "--no-interpreter run exits 0" 0 "$rc"
assert_eq "--no-interpreter executes nothing (marker count 0)" 0 \
	"$(invocation_count "$fx/marker")"
rec="$(cat "$fx/observed.txt" 2>/dev/null)"
assert_contains "record states the interpreter checks were skipped" "$rec" \
	"interpreter checks were skipped (--no-interpreter)"
assert_not_contains "record has no invented interpreter digest" "$rec" \
	"interpreter_"

# --- normal mode observes, records and does not re-probe -------------------
fx="$(new_fixture normal-record)"
make_counting_fake "$fx/fake-python" "$fx/marker"
printf 'local_interpreter_315_path=%s\n' "$(real_path "$fx/fake-python")" >> "$fx/pin/checksums.txt"
printf 'local_interpreter_315_sha256=%s\n' \
	"$(sha256_file "$fx/fake-python")" >> "$fx/pin/checksums.txt"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh \
	--python "$fx/fake-python" \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/observed.txt" 2>&1)"
rc=$?
assert_eq "normal mode with a matching fake interpreter exits 0" 0 "$rc"
assert_eq "normal mode probes exactly twice (version + build), not again to record" 2 \
	"$(invocation_count "$fx/marker")"
rec="$(cat "$fx/observed.txt" 2>/dev/null)"
assert_contains "record uses the pin/checksums key scheme" "$rec" \
	"local_interpreter_315_sha256="
assert_contains "record stores the resolved binary path" "$rec" \
	"local_interpreter_315_path="
assert_contains "summary says the local digest was compared" "$out" \
	"local digest: compared"

# --- failing interpreter: checks fail closed, diagnostics marked -----------
fx="$(new_fixture failing-interpreter)"
make_failing_fake "$fx/failing-python" "$fx/marker"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh \
	--python "$fx/failing-python" \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/observed.txt" 2>&1)"
rc=$?
assert_eq "failing interpreter still fails the run (exit 1)" 1 "$rc"
assert_contains "unprobeable candidate is skipped with a warning, not a false failure" \
	"$out" "skipping this candidate"
assert_eq "failing interpreter was probed exactly once before failing" 1 \
	"$(invocation_count "$fx/marker")"
rec="$(cat "$fx/observed.txt" 2>/dev/null)"
assert_contains "failed run labels its record as diagnostic" "$rec" \
	"not a passing result"
assert_not_contains "no interpreter digest is invented" "$rec" "interpreter_"

# --- probes are isolated (-I) ------------------------------------------------
fx="$(new_fixture probe-isolation)"
make_arg_recording_fake "$fx/argfake" "$fx/marker" "$fx/args.log"
printf 'local_interpreter_315_path=%s\n' "$(real_path "$fx/argfake")" >> "$fx/pin/checksums.txt"
printf 'local_interpreter_315_sha256=%s\n' \
	"$(sha256_file "$fx/argfake")" >> "$fx/pin/checksums.txt"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh \
	--python "$fx/argfake" --record "$fx/observed.txt" --quiet 2>&1)"
rc=$?
assert_eq "isolated-probe interpreter passes" 0 "$rc"
assert_eq "probe invocation includes -I" "yes" \
	"$(grep -Fq -- '-I' "$fx/args.log" && printf yes || printf no)"

# --- digest baseline is per exact canonical path, not per host --------------
fx="$(new_fixture other-build)"
make_counting_fake "$fx/fake-a" "$fx/marker-a"
make_counting_fake "$fx/fake-b" "$fx/marker-b"
printf 'local_interpreter_315_path=%s\n' "$(real_path "$fx/fake-a")" >> "$fx/pin/checksums.txt"
printf 'local_interpreter_315_sha256=%s\n' \
	"$(sha256_file "$fx/fake-a")" >> "$fx/pin/checksums.txt"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh \
	--python "$fx/fake-b" \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/observed.txt" 2>&1)"
rc=$?
assert_eq "build at a different path still exits 0" 0 "$rc"
assert_contains "different path is warned as not compared" "$out" "NOT compared"
assert_contains "summary names the different path as the reason" "$out" \
	"local digest: not compared (different path)"
assert_not_contains "different path does not produce a mismatch failure" "$out" \
	"interpreter sha256 changed"
rec="$(cat "$fx/observed.txt" 2>/dev/null)"
assert_contains "record carries the observed second build digest" "$rec" \
	"local_interpreter_315_sha256=$(sha256_file "$fx/fake-b")"
_expected_real="$(real_path "$fx/fake-b")"
assert_contains "record carries the observed second build path" "$rec" \
	"local_interpreter_315_path=$_expected_real"
qout="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --python "$fx/fake-b" \
	--archive "$fx/python-3.15.2-macos11.pkg" --quiet 2>&1)"
qrc=$?
assert_eq "quiet run with a different-path build exits 0" 0 "$qrc"
assert_contains "quiet mode cannot hide the skip warning" "$qout" "NOT compared"
assert_contains "quiet summary still states the drift-gate outcome" "$qout" \
	"local digest: not compared"

# --- changed bytes at the recorded path still fail closed -------------------
fx="$(new_fixture same-path-changed)"
make_counting_fake "$fx/build" "$fx/marker"
printf 'local_interpreter_315_path=%s\n' "$(real_path "$fx/build")" >> "$fx/pin/checksums.txt"
printf 'local_interpreter_315_sha256=%s\n' \
	"$(sha256_file "$fx/build")" >> "$fx/pin/checksums.txt"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --python "$fx/build" --quiet 2>&1)"
rc=$?
assert_eq "same recorded path and unchanged bytes exit 0" 0 "$rc"
assert_contains "summary reports a comparison for the same path" "$out" \
	"local digest: compared"
# Restore the original bytes, then pretend to be a different host: the
# baseline is path-scoped, so the same path must still be compared.
make_counting_fake "$fx/build" "$fx/marker"
mkdir -p "$fx/bin"
printf '#!/bin/sh\necho some-other-host\n' > "$fx/bin/hostname"
chmod +x "$fx/bin/hostname"
out="$(cd "$fx" && PATH="$fx/bin:$PATH" NO_COLOR=1 sh ./verify.sh \
	--python "$fx/build" --quiet 2>&1)"
rc=$?
assert_eq "same path is compared even when hostname differs" 0 "$rc"
assert_contains "cross-host summary still reports compared" "$out" \
	"local digest: compared"
printf '# bytes changed without changing stdout\n' >> "$fx/build"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --python "$fx/build" --quiet 2>&1)"
rc=$?
assert_eq "changed bytes at the recorded path fail (exit 1)" 1 "$rc"
assert_contains "mismatch is reported" "$out" "interpreter sha256 changed"
assert_contains "FAIL summary reports compared" "$out" \
	"local digest: compared"

# --- a bare Python-2-style candidate is skipped, not fatal -----------------
fx="$(new_fixture py2-candidate)"
mkdir -p "$fx/bin"
make_counting_fake "$fx/bin/python3.15" "$fx/marker"
printf 'local_interpreter_315_path=%s\n' "$(real_path "$fx/bin/python3.15")" >> "$fx/pin/checksums.txt"
printf 'local_interpreter_315_sha256=%s\n' \
	"$(sha256_file "$fx/bin/python3.15")" >> "$fx/pin/checksums.txt"
printf '#!/bin/sh\ncase "$1" in -I) echo "python: unknown option: -I" >&2; exit 64;; esac\nprintf "3.15.2\\n"\n' > "$fx/bin/python"
chmod +x "$fx/bin/python"
out="$(cd "$fx" && PATH="$fx/bin:$PATH" NO_COLOR=1 sh ./verify.sh \
	--archive "$fx/python-3.15.2-macos11.pkg" \
	--record "$fx/observed.txt" 2>&1)"
rc=$?
assert_eq "Python-2-like bare python does not fail a run that finds the pin" 0 "$rc"
assert_contains "unprobeable candidate is visible" "$out" "skipping this candidate"
assert_contains "valid pinned candidate is compared" "$out" \
	"local digest: compared"

# --- hashing feeds content on stdin, tolerating odd path names (Unix) -------
case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*)
		assert_eq "odd-name hashing test skipped on Windows" yes yes ;;
	*)
		fx="$(new_fixture backslash-name)"
		_bs="$fx/back\\slash"
		make_counting_fake "$_bs" "$fx/marker"
		printf 'local_interpreter_315_path=%s\n' "$(real_path "$_bs")" >> "$fx/pin/checksums.txt"
		printf 'local_interpreter_315_sha256=%s\n' \
			"$(sha256_file "$_bs")" >> "$fx/pin/checksums.txt"
		out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --python "$_bs" --record "$fx/observed.txt" --quiet 2>&1)"
		rc=$?
		assert_eq "path containing a backslash hashes correctly" 0 "$rc"
		rec="$(cat "$fx/observed.txt" 2>/dev/null)"
		assert_contains "record carries the backslash-name digest" "$rec" \
			"local_interpreter_315_sha256=$(sha256_file "$_bs")"
		;;
esac

# --- a mismatching archive gets no successful Sigstore claim -----------------
fx="$(new_fixture archive-mismatch)"
mkdir -p "$fx/tampered"
printf 'tampered bytes\n' > "$fx/tampered/python-3.15.2-macos11.pkg"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
	--archive "$fx/tampered/python-3.15.2-macos11.pkg" \
	--record "$fx/observed.txt" 2>&1)"
rc=$?
assert_eq "digest-mismatched archive fails (exit 1)" 1 "$rc"
assert_contains "mismatch says recorded evidence does not apply" "$out" "does NOT apply"
assert_not_contains "no Sigstore success statement for a mismatch" "$out" \
	".sigstore bundle verified"
rec="$(cat "$fx/observed.txt" 2>/dev/null)"
assert_contains "mismatch observation is still recorded" "$rec" \
	"archive_python-3.15.2-macos11.pkg_sha256="

# --- unreadable pin/digest metadata fails closed ----------------------------
fx="$(new_fixture unreadable-pin)"
chmod 000 "$fx/pin/python.txt"
if sed -n '1p' "$fx/pin/python.txt" >/dev/null 2>&1; then
	chmod 644 "$fx/pin/python.txt"
	assert_eq "unreadable-pin test skipped (mode 000 is readable here)" yes yes
else
	out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter 2>&1)"
	rc=$?
	chmod 644 "$fx/pin/python.txt"
	assert_eq "unreadable pin file fails closed (exit 2)" 2 "$rc"
	assert_contains "unreadable pin file is named" "$out" "cannot read pin file"
fi

fx="$(new_fixture unreadable-digest)"
chmod 000 "$fx/pin/checksums.txt"
if sed -n '1p' "$fx/pin/checksums.txt" >/dev/null 2>&1; then
	chmod 644 "$fx/pin/checksums.txt"
	assert_eq "unreadable-digest test skipped (mode 000 is readable here)" yes yes
else
	out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter 2>&1)"
	rc=$?
	chmod 644 "$fx/pin/checksums.txt"
	assert_eq "unreadable digest file fails closed (exit 2)" 2 "$rc"
	assert_contains "unreadable digest file is named" "$out" "cannot read digest file"
fi

# --- empty option values are rejected, never silently ignored --------------
fx="$(new_fixture empty-options)"
out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter --archive '' 2>&1)"
rc=$?
assert_eq "empty --archive is rejected (exit 2)" 2 "$rc"
assert_not_contains "empty --archive does not claim checks performed" "$out" \
	"official-artifact checks:"

out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter --archive= 2>&1)"
rc=$?
assert_eq "empty --archive= is rejected (exit 2)" 2 "$rc"

out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter --record '' 2>&1)"
rc=$?
assert_eq "empty --record is rejected (exit 2)" 2 "$rc"

out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --python '' 2>&1)"
rc=$?
assert_eq "empty --python is rejected (exit 2)" 2 "$rc"

# --- a failing sha256 utility fails closed, writing no empty digest --------
fx="$(new_fixture sha-failure)"
mkdir -p "$fx/unreadable-dir"
cp "$fx/python-3.15.2-macos11.pkg" "$fx/unreadable-dir/python-3.15.2-macos11.pkg"
chmod 000 "$fx/unreadable-dir/python-3.15.2-macos11.pkg"
if sha256_file "$fx/unreadable-dir/python-3.15.2-macos11.pkg" >/dev/null 2>&1; then
	# Running privileged (for example as root) defeats mode 000; do not
	# assert a failure that this environment cannot produce.
	chmod 644 "$fx/unreadable-dir/python-3.15.2-macos11.pkg"
	assert_eq "unreadable-archive test skipped (mode 000 is readable here)" yes yes
else
	out="$(cd "$fx" && NO_COLOR=1 sh ./verify.sh --no-interpreter \
		--archive "$fx/unreadable-dir/python-3.15.2-macos11.pkg" \
		--record "$fx/observed.txt" 2>&1)"
	rc=$?
	chmod 644 "$fx/unreadable-dir/python-3.15.2-macos11.pkg"
	assert_eq "unreadable archive fails closed (exit 1)" 1 "$rc"
	assert_contains "failure says the digest could not be computed" "$out" \
		"cannot compute the sha256"
	if [ -f "$fx/observed.txt" ]; then
		assert_eq "record omits an empty digest rather than inventing one" "0" \
			"$(grep -c '^archive_.*sha256=$' "$fx/observed.txt")"
	else
		assert_eq "record was still written as a diagnostic" "yes" yes
	fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
	printf 'PASS: %s assertion(s), 0 failure(s)\n' "$PASS"
	exit 0
fi
printf 'FAIL: %s assertion(s) passed, %s failure(s)%s\n' "$PASS" "$FAIL" "$FAILURES"
exit 1
