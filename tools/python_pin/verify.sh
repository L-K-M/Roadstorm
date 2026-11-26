#!/bin/sh
# Roadstorm Racer! - asset-generation Python pin verification (PLAN.md M0.1).
#
# Ownership: tools/python_pin/**. The narrative record lives in
# docs/PYTHON_TOOLCHAIN.md; this script turns that record into an executable
# check.
#
# What it verifies, and what it does NOT:
#   * INSTALLED INTERPRETERS (default mode): it finds local Python
#     interpreters, reports each one's version and build string, requires at
#     least one whose version matches the pin, and compares that interpreter's
#     sha256 with the recorded local observation. An installed interpreter is
#     a LOCAL BUILD (Homebrew, Xcode, uv/astral-sh, distro, ...). A version
#     match is NOT authentication: it says the interpreter reports 3.15.2, not
#     that it is the official python.org artifact.
#   * OFFICIAL ARTIFACTS (--archive <file>): it compares the SHA-256 of a
#     downloaded official artifact with the digest python.org published on the
#     release page. That is a match against the PUBLISHED digest; it does not
#     by itself authenticate the publication channel. Full authentication is
#     python.org's Sigstore procedure (artifact + .sigstore bundle + signer
#     identity hugo@python.org via the GitHub OIDC issuer), which this script
#     does not perform.
#   * It downloads nothing, installs nothing and never touches a global
#     Python installation.
#
# Usage:
#   tools/python_pin/verify.sh                       verify local interpreter(s)
#   tools/python_pin/verify.sh --python <path>       check a specific interpreter
#   tools/python_pin/verify.sh --archive <file>...   verify official artifact(s)
#                                                    against the published SHA-256
#   tools/python_pin/verify.sh --no-interpreter      skip the interpreter check
#   tools/python_pin/verify.sh --record <file>       write observed digests to <file>
#   tools/python_pin/verify.sh --quiet               failures and summary only
#
# Exit codes: 0 = passed, 1 = a check failed, 2 = the command could not run
# (missing pin or digest file, no sha256 utility on PATH, or a bad option).
# Original project code under the Unlicense.

set -u

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
PIN_DIR="$TOOLS_DIR/pin"
PIN_FILE="$PIN_DIR/python.txt"
DIGEST_FILE="$PIN_DIR/checksums.txt"

OK=0
FAIL=1
USAGE=2

PYTHON_BIN="${PYTHON_BIN:-}"
NO_INTERPRETER=0
QUIET=0
RECORD_FILE=""
ARCHIVE_FILES=""

# ---------------------------------------------------------------------------
# Output helpers (no colour by default; NO_COLOR is respected)
# ---------------------------------------------------------------------------
if [ -n "${NO_COLOR:-}" ]; then
	C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BOLD=""
else
	C_RESET="$(printf '\033[0m')"
	C_RED="$(printf '\033[31m')"
	C_GREEN="$(printf '\033[32m')"
	C_YELLOW="$(printf '\033[33m')"
	C_BOLD="$(printf '\033[1m')"
fi

info() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
ok()   { [ "$QUIET" -eq 1 ] || printf '%s[ok]%s   %s\n' "$C_GREEN" "$C_RESET" "$*"; }
bad()  { printf '%s[fail]%s %s\n' "$C_RED" "$C_RESET" "$*"; RC="$FAIL"; }
die()  { printf '%s[error]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit "$USAGE"; }

usage() {
	sed -n '2,/^# Original project code/p' "$0" | sed 's/^# \{0,1\}//'
	exit "$OK"
}

# ---------------------------------------------------------------------------
# Pin loading
# ---------------------------------------------------------------------------
pin_get() {
	_key="$1"
	[ -f "$PIN_FILE" ] || return 1
	sed -n "s/^${_key}=//p" "$PIN_FILE" | tail -n 1
}

digest_get() {
	_key="$1"
	[ -f "$DIGEST_FILE" ] || return 1
	sed -n "s/^${_key}=//p" "$DIGEST_FILE" | tail -n 1
}

sha256_of() {
	_file="$1"
	[ -f "$_file" ] || return 1
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$_file" | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$_file" | awk '{print $1}'
	else
		return 1
	fi
}

# Every digest check depends on a sha256 utility. Without one the verifier
# cannot check anything, so that is a hard failure (exit 2), never a pass.
require_sha256_tool() {
	if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
		return 0
	fi
	die "no sha256 utility found (need shasum or sha256sum on PATH); no digest could be checked"
}

load_pin() {
	[ -f "$PIN_FILE" ] || die "missing pin file: $PIN_FILE"
	[ -f "$DIGEST_FILE" ] || die "missing digest file: $DIGEST_FILE"

	PIN_VERSION="$(pin_get version)"
	PIN_MAJOR="$(pin_get major)"
	PIN_MINOR="$(pin_get minor)"
	PIN_PATCH="$(pin_get patch)"
	PIN_RELEASE_PAGE="$(pin_get release_page)"
	PIN_UPSTREAM_VERIFIED="$(pin_get upstream_verified)"

	[ -n "$PIN_VERSION" ] || die "pin file has no version: $PIN_FILE"
	case "$PIN_VERSION" in
		"$PIN_MAJOR.$PIN_MINOR.$PIN_PATCH") ;;
		*) die "pin file is inconsistent: version=$PIN_VERSION, major/minor/patch=$PIN_MAJOR.$PIN_MINOR.$PIN_PATCH" ;;
	esac
}

# ---------------------------------------------------------------------------
# Interpreter discovery
# ---------------------------------------------------------------------------
# Candidate interpreters, most specific first. Deliberately cross-platform:
# PATH lookups first, then the well-known install locations on macOS, Windows
# (Git Bash / MSYS paths) and Linux.
python_candidates() {
	if [ -n "$PYTHON_BIN" ]; then
		printf '%s\n' "$PYTHON_BIN"
		return 0
	fi
	for name in "python$PIN_VERSION" "python$PIN_MAJOR.$PIN_MINOR" python3 python; do
		command -v "$name" 2>/dev/null
	done
	for path in \
		/usr/bin/python3 \
		/usr/local/bin/python3 \
		/opt/homebrew/bin/python3 \
		//c/Python3"$PIN_MAJOR$PIN_MINOR"/python.exe \
		/c/Python"$PIN_MAJOR$PIN_MINOR"/python.exe \
		"$HOME/.local/share/uv/python/cpython-${PIN_MAJOR}.${PIN_MINOR}"*/bin/python"${PIN_MAJOR}.${PIN_MINOR}" \
		"$HOME/.pyenv/versions/$PIN_VERSION"/bin/python
	do
		[ -e "$path" ] && printf '%s\n' "$path"
	done
	return 0
}

# read_version <interpreter> -> prints "X.Y.Z" or nothing.
read_version() {
	"$1" -c 'import platform; print(platform.python_version())' 2>/dev/null
}

# read_build <interpreter> -> prints the sys.version line.
read_build() {
	"$1" -c 'import sys; print(sys.version)' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
SEEN=""
FOUND_PINNED=0

check_interpreter() {
	_py="$1"
	[ -x "$_py" ] || { bad "not executable: $_py"; return 1; }
	_real="$(cd "$(dirname "$_py")" && pwd)/$(basename "$_py")"
	if command -v realpath >/dev/null 2>&1; then
		_real="$(realpath "$_py" 2>/dev/null || printf '%s' "$_py")"
	elif command -v readlink >/dev/null 2>&1; then
		_link="$(readlink "$_py" 2>/dev/null)"
		[ -n "$_link" ] && _real="$_link"
	fi
	case "$SEEN" in
		*"|$_real|"*) return 0 ;; # already inspected this file
	esac
	SEEN="$SEEN|$_real|"

	_ver="$(read_version "$_py")"
	if [ -z "$_ver" ]; then
		bad "cannot read a Python version from $_py"
		return 1
	fi
	_build="$(read_build "$_py")"
	info "interpreter: $_py"
	info "  real path:  $_real"
	info "  version:    $_ver"
	info "  build:      $_build"

	if [ "$_ver" = "$PIN_VERSION" ]; then
		FOUND_PINNED=1
		ok "interpreter version matches the pin ($PIN_VERSION)"
		check_interpreter_digest "$_real" "$_ver"
	else
		info "  version does not match the pin ($PIN_VERSION); recorded as present, not compared"
	fi
}

check_interpreter_digest() {
	_real="$1"; _ver="$2"
	if ! _observed="$(sha256_of "$_real")"; then
		bad "cannot compute the sha256 of $_real"
		return 1
	fi
	_expected="$(digest_get "local_interpreter_${PIN_MAJOR}${PIN_MINOR}_sha256")"
	if [ -z "$_expected" ]; then
		warn "no recorded local digest for a $PIN_VERSION interpreter in $DIGEST_FILE (NOT RECORDED; nothing is invented)"
		info "observed sha256: $_observed"
		return 0
	fi
	if [ "$_observed" = "$_expected" ]; then
		ok "interpreter sha256 matches the recorded LOCAL observation"
	else
		bad "interpreter sha256 changed: observed $_observed, recorded $_expected (a local build changed; this is not an upstream verification)"
	fi
	info "interpreter sha256: $_observed"
}

# --- Official artifact check (--archive) ------------------------------------
# Matches the archive's file name against the pinned artifacts in the pin file
# and compares its sha256 with the digest python.org published for it.
check_archive() {
	_path="$1"
	if [ ! -f "$_path" ]; then
		bad "archive not found: $_path"
		return 1
	fi
	_name="${_path##*/}"
	_expected=""
	_url=""
	for _key in macos_pkg windows_amd64_exe source_tarxz source_tgzz; do
		if [ "$(pin_get "${_key}_file")" = "$_name" ]; then
			_expected="$(pin_get "${_key}_sha256")"
			_url="$(pin_get "${_key}_url")"
		fi
	done
	if [ -z "$_expected" ]; then
		bad "$_name is not a pinned official artifact; pin/python.txt pins only: macos pkg, windows amd64 exe, source tar.xz, source tgz"
		return 1
	fi
	if ! _observed="$(sha256_of "$_path")"; then
		bad "cannot compute the sha256 of $_path"
		return 1
	fi
	info "archive: $_path"
	info "  official source: ${_url:-unknown}"
	if [ "$_observed" = "$_expected" ]; then
		ok "$_name sha256 matches the digest python.org PUBLISHED for $PIN_VERSION"
	else
		bad "$_name sha256 mismatch: observed $_observed, published $_expected"
	fi
	info "  observed sha256: $_observed"
	info "  published sha256: $_expected"
	info "  note: a published-digest match is not Sigstore authentication; run the"
	info "        .sigstore procedure from $(pin_get sigstore_doc) to authenticate the publisher."
}

# --- The distinction this pin exists to keep visible -------------------------
print_distinction() {
	info ""
	info "authenticated archive vs installed interpreter:"
	if [ -n "$ARCHIVE_FILES" ]; then
		info "  * --archive checked official python.org artifact(s) against the"
		info "    publisher's published SHA-256. That is artifact-vs-published-digest."
	else
		info "  * No official artifact was checked in this run. Pass --archive <file>"
		info "    to compare a downloaded official artifact with the published digest."
	fi
	info "  * Any interpreter listed above is a LOCAL BUILD. Its version string"
	info "    matching the pin is not authentication, and its sha256 only detects"
	info "    local change. A local build is never evidence about python.org bytes."
	if [ "${PIN_UPSTREAM_VERIFIED:-no}" = "yes" ]; then
		info "  * pin records upstream_verified=yes (see docs/PYTHON_TOOLCHAIN.md for scope)."
	else
		info "  * pin records upstream_verified=no: not all pinned published digests have been"
		info "    compared with downloaded artifact bytes. See docs/evidence for the source check;"
		info "    not verified (docs/PYTHON_TOOLCHAIN.md, Open items)."
	fi
}

record_digests() {
	[ -n "$RECORD_FILE" ] || return 0
	_dir="$(dirname "$RECORD_FILE")"
	mkdir -p "$_dir" || die "cannot create $_dir"
	{
		printf '# Observed digests recorded by tools/python_pin/verify.sh --record\n'
		printf '# Recorded %s on %s (%s %s)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(hostname)" "$(uname -s)" "$(uname -m)"
		printf '# LOCAL observations only. Not upstream verification.\n'
		printf 'pinned_version=%s\n' "$PIN_VERSION"
		_recorded=""
		for _py in $(python_candidates); do
			[ -x "$_py" ] || continue
			_ver="$(read_version "$_py")"
			[ -n "$_ver" ] || continue
			_real="$(cd "$(dirname "$_py")" && pwd)/$(basename "$_py")"
			if command -v realpath >/dev/null 2>&1; then
				_real="$(realpath "$_py" 2>/dev/null || printf '%s' "$_py")"
			fi
			case "$_recorded" in
				*"|$_real|"*) continue ;;
			esac
			_recorded="$_recorded|$_real|"
			_key="$(printf '%s' "$_ver" | tr '.' '_')"
			printf 'interpreter_%s_sha256=%s\n' "$_key" "$(sha256_of "$_real" 2>/dev/null)"
			printf 'interpreter_%s_path=%s\n' "$_key" "$_real"
		done
		for _f in $ARCHIVE_FILES; do
			[ -f "$_f" ] || continue
			printf 'archive_%s_sha256=%s\n' "${_f##*/}" "$(sha256_of "$_f" 2>/dev/null)"
		done
	} >"$RECORD_FILE" || die "cannot write $RECORD_FILE"
	info "observed digests written to $RECORD_FILE"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
		--python) [ $# -ge 2 ] || die "--python needs a path"; PYTHON_BIN="$2"; shift 2 ;;
		--python=*) PYTHON_BIN="${1#--python=}"; shift ;;
		--archive) [ $# -ge 2 ] || die "--archive needs a file path"; ARCHIVE_FILES="$ARCHIVE_FILES $2"; shift 2 ;;
		--archive=*) ARCHIVE_FILES="$ARCHIVE_FILES ${1#--archive=}"; shift ;;
		--no-interpreter) NO_INTERPRETER=1; shift ;;
		--quiet) QUIET=1; shift ;;
		--record) [ $# -ge 2 ] || die "--record needs a file path"; RECORD_FILE="$2"; shift 2 ;;
		--record=*) RECORD_FILE="${1#--record=}"; shift ;;
		-h | --help | help) usage ;;
		*) die "unknown option: $1 (see --help)" ;;
	esac
done

RC=0
load_pin
require_sha256_tool

printf '%sRoadstorm asset-generation Python pin verification (pin %s)%s\n' "$C_BOLD" "$PIN_VERSION" "$C_RESET"
info "host: $(hostname) / $(uname -s) $(uname -r) $(uname -m)"
info "release page: $PIN_RELEASE_PAGE"
info ""

if [ "$NO_INTERPRETER" -eq 1 ]; then
	warn "interpreter checks skipped on request (--no-interpreter)"
else
	_found_any=0
	for _py in $(python_candidates); do
		[ -x "$_py" ] || continue
		_found_any=1
		check_interpreter "$_py"
	done
	if [ "$_found_any" -eq 0 ]; then
		bad "no Python interpreter found (set PYTHON_BIN=/path/to/python or pass --python)"
	elif [ "$FOUND_PINNED" -eq 0 ]; then
		bad "no local interpreter reports the pinned version $PIN_VERSION (install it, point --python at it, or pass --no-interpreter to skip this check explicitly)"
	fi
fi

for _f in $ARCHIVE_FILES; do
	check_archive "$_f"
done

print_distinction
record_digests

info ""
if [ "$RC" -eq 0 ]; then
	printf '%s[ok]%s   python pin verification: PASS (local interpreter observations; official-artifact checks: %s; published-digest upstream verification: %s)\n' \
		"$C_GREEN" "$C_RESET" \
		"$([ -n "$ARCHIVE_FILES" ] && printf 'performed' || printf 'none')" \
		"${PIN_UPSTREAM_VERIFIED:-no}"
else
	printf '%s[fail]%s python pin verification: FAIL\n' "$C_RED" "$C_RESET"
fi
exit "$RC"
