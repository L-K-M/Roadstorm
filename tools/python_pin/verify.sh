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
#   * RECORDED EVIDENCE: pin/python.txt carries narrowly scoped, dated statuses
#     for publisher artifact bytes (digest match and Sigstore verification
#     performed by the independent job recorded in
#     docs/PYTHON_TOOLCHAIN_EVIDENCE.md). This script REPORTS those records;
#     it does not repeat them and they never describe an installed binary.
#   * It downloads nothing, installs nothing and never touches a global
#     Python installation.
#
# Usage:
#   tools/python_pin/verify.sh                       verify local interpreter(s)
#   tools/python_pin/verify.sh --python <path>       check a specific interpreter
#   tools/python_pin/verify.sh --archive <file>...   verify official artifact(s)
#                                                    against the published SHA-256
#   tools/python_pin/verify.sh --no-interpreter      skip the interpreter check
#   tools/python_pin/verify.sh --record <file>       create <file> exclusively and write
#                                                    observed digests there; an existing
#                                                    target, a link, or a protected input
#                                                    or pin path is refused
#   tools/python_pin/verify.sh --quiet               failures and summary only
#
# Quoted paths are supported verbatim, including spaces and glob characters:
#   tools/python_pin/verify.sh --archive "my dir/Python-3.15.2.tgz"
#
# Interpreter probes run with -I, so modules in the caller's working directory
# or PYTHONPATH cannot affect the reported version/build.
#
# --no-interpreter skips interpreter execution everywhere, including recording.
# Recording reuses only observations already made; it never re-probes an
# interpreter. A --record destination must not exist (any file type, including
# a symlink or hard link, is refused), so recording cannot overwrite it. That
# check and the exclusive creation narrow the race with a concurrent writer,
# but are not an absolute race-free guarantee; see the README. Record entries
# use the drift-lookup key convention (local_interpreter_<major><minor>_*;
# pin/checksums.txt retains one older local_interpreter_396_* entry) and store
# the realpath-resolved path when the selected file is a symlink. A real
# launcher such as macOS /usr/bin/python3 stays the launcher. The local-digest drift comparison is
# scoped to the exact canonical path recorded there (not to a host): a build
# at that same path on ANY machine is compared and may fail closed, while an
# interpreter at a different path is NOT RECORDED and not compared. --archive compares with the published digest RECORDED in
# pin/python.txt, and a mismatch produces no publisher/Sigstore success claim.
#
# Exit codes: 0 = passed, 1 = a check failed, 2 = the command could not run
# (missing pin or digest file, no sha256 utility on PATH, a bad or empty option,
# or an unsafe --record target).
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
ARCHIVE_FILES=""        # newline-separated; preserves spaces and glob characters
ARCHIVE_COUNT=0
OBSERVED_INTERPRETERS="" # newline-separated triples: version, sha256, real path
OBSERVED_ARCHIVES=""     # newline-separated pairs: file name, observed sha256
NL='
'

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

# Append one path to a newline-separated list without splitting it.
append_path() {
	if [ -z "$1" ]; then
		printf '%s' "$2"
	else
		printf '%s%s%s' "$1" "$NL" "$2"
	fi
}

reject_newline() {
	case "$2" in
		*"$NL"*) die "$1 must not contain a newline: $2" ;;
	esac
}

# ---------------------------------------------------------------------------
# Pin loading
# ---------------------------------------------------------------------------
# The pin and digest files are required. An unreadable file must fail closed,
# never silently yield an empty value that looks like "not recorded".
pin_get() {
	_key="$1"
	[ -f "$PIN_FILE" ] || return 1
	_val="$(sed -n "s/^${_key}=//p" "$PIN_FILE")" || return 1
	printf '%s\n' "$_val" | tail -n 1
}

digest_get() {
	_key="$1"
	[ -f "$DIGEST_FILE" ] || return 1
	_val="$(sed -n "s/^${_key}=//p" "$DIGEST_FILE")" || return 1
	printf '%s\n' "$_val" | tail -n 1
}

# Print the lowercase hex sha256 of a regular file, or fail. A failing or
# missing sha256 utility is returned as failure, not as an empty "success":
# every caller treats failure as a failed check and nothing is invented.
# The content is fed on stdin ("-") rather than passed as an argument: that
# avoids option parsing for names beginning with "-" and Perl/GNU filename
# escaping for names containing backslashes, both of which would otherwise
# turn into a false "cannot compute" failure.
sha256_of() {
	_file="$1"
	[ -f "$_file" ] || return 1
	if command -v shasum >/dev/null 2>&1; then
		_out="$(shasum -a 256 - < "$_file" 2>/dev/null)" || return 1
	elif command -v sha256sum >/dev/null 2>&1; then
		_out="$(sha256sum - < "$_file" 2>/dev/null)" || return 1
	else
		return 1
	fi
	_hash="${_out%% *}"
	[ "${#_hash}" -eq 64 ] || return 1
	case "$_hash" in
		*[!0-9a-fA-F]*) return 1 ;;
	esac
	printf '%s\n' "$_hash"
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
	# An existing but unreadable pin/digest file is not "not recorded": fail
	# closed instead of letting later lookups silently yield empty values.
	sed -n '1p' "$PIN_FILE" >/dev/null 2>&1 || die "cannot read pin file: $PIN_FILE"
	sed -n '1p' "$DIGEST_FILE" >/dev/null 2>&1 || die "cannot read digest file: $DIGEST_FILE"

	PIN_VERSION="$(pin_get version)"
	PIN_MAJOR="$(pin_get major)"
	PIN_MINOR="$(pin_get minor)"
	PIN_PATCH="$(pin_get patch)"
	PIN_RELEASE_PAGE="$(pin_get release_page)"
	PIN_PUB_DIGEST_DATE="$(pin_get publisher_digest_match_date)"
	PIN_PUB_DIGEST_RESULT="$(pin_get publisher_digest_match_result)"
	PIN_PUB_SIGSTORE_DATE="$(pin_get publisher_sigstore_date)"
	PIN_PUB_SIGSTORE_RESULT="$(pin_get publisher_sigstore_result)"
	PIN_SIGSTORE_VERIFIER="$(pin_get sigstore_verifier)"
	PIN_VERIFICATION_RECORD="$(pin_get verification_record)"
	PIN_SIGSTORE_EMAIL="$(pin_get sigstore_signer_email)"
	PIN_SIGSTORE_ISSUER="$(pin_get sigstore_oidc_issuer)"
	PIN_SIGSTORE_DOC="$(pin_get sigstore_doc)"
	PIN_INSTALLED_AUTH="$(pin_get installed_interpreter_publisher_authenticated)"
	PIN_HOMEBREW_VERIFIED="$(pin_get homebrew_channel_fully_verified)"

	[ -n "$PIN_VERSION" ] || die "pin file has no version: $PIN_FILE"
	case "$PIN_VERSION" in
		"$PIN_MAJOR.$PIN_MINOR.$PIN_PATCH") ;;
		*) die "pin file is inconsistent: version=$PIN_VERSION, major/minor/patch=$PIN_MAJOR.$PIN_MINOR.$PIN_PATCH" ;;
	esac
}

# ---------------------------------------------------------------------------
# Interpreter discovery
# ---------------------------------------------------------------------------
# Call <callback> once per candidate interpreter, most specific first.
# The callback is invoked in this shell (so its side effects persist) and the
# path is passed as a single argument, so spaces and glob characters survive.
# Deliberately cross-platform: PATH lookups first, then the well-known install
# locations on macOS, Windows (Git Bash / MSYS paths) and Linux.
for_each_python_candidate() {
	_cb="$1"
	if [ -n "$PYTHON_BIN" ]; then
		"$_cb" "$PYTHON_BIN"
		return 0
	fi
	for _name in "python$PIN_VERSION" "python$PIN_MAJOR.$PIN_MINOR" python3 python; do
		_p="$(command -v "$_name" 2>/dev/null)" || continue
		[ -n "$_p" ] && "$_cb" "$_p"
	done
	for _path in \
		/usr/bin/python3 \
		/usr/local/bin/python3 \
		/opt/homebrew/bin/python3 \
		//c/Python3"$PIN_MAJOR$PIN_MINOR"/python.exe \
		/c/Python"$PIN_MAJOR$PIN_MINOR"/python.exe \
		"$HOME/.local/share/uv/python/cpython-${PIN_MAJOR}.${PIN_MINOR}"*/bin/python"${PIN_MAJOR}.${PIN_MINOR}" \
		"$HOME/.pyenv/versions/$PIN_VERSION"/bin/python
	do
		[ -e "$_path" ] && "$_cb" "$_path"
	done
	return 0
}

consider_candidate() {
	_py="$1"
	[ -x "$_py" ] || return 0
	_FOUND_ANY=1
	check_interpreter "$_py"
}

obs_append() {
	_v="$1"; _s="$2"; _r="$3"
	[ -n "$OBSERVED_INTERPRETERS" ] && OBSERVED_INTERPRETERS="$OBSERVED_INTERPRETERS$NL"
	OBSERVED_INTERPRETERS="$OBSERVED_INTERPRETERS$_v$NL$_s$NL$_r"
}

obs_append_archive() {
	_n="$1"; _h="$2"
	[ -n "$OBSERVED_ARCHIVES" ] && OBSERVED_ARCHIVES="$OBSERVED_ARCHIVES$NL"
	OBSERVED_ARCHIVES="$OBSERVED_ARCHIVES$_n$NL$_h"
}

# read_version <interpreter> -> prints "X.Y.Z" or nothing.
# -I isolates the probe: the current directory and PYTHONPATH are not put on
# sys.path, so a platform.py or sys.py planted in the caller's working
# directory cannot execute or spoof the reported version. Every targeted
# CPython (including 3.9.6) supports -I.
read_version() {
	"$1" -I -c 'import platform; print(platform.python_version())' 2>/dev/null
}

# read_build <interpreter> -> prints the sys.version line.
read_build() {
	"$1" -I -c 'import sys; print(sys.version)' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
SEEN=""
FOUND_PINNED=0
OBSERVED_SHA=""
_FOUND_ANY=0
LOCAL_DIGEST_STATE="not compared"

check_interpreter() {
	_py="$1"
	[ -x "$_py" ] || { bad "not executable: $_py"; return 1; }
	_real="$(cd "$(dirname "$_py")" && pwd)/$(basename "$_py")"
	if command -v realpath >/dev/null 2>&1; then
		_real="$(realpath "$_py" 2>/dev/null || printf '%s' "$_py")"
	elif command -v readlink >/dev/null 2>&1; then
		# Fallback: make a relative link target absolute before the baseline
		# path comparison, so it is not silently treated as a different build.
		_link="$(readlink "$_py" 2>/dev/null)"
		if [ -n "$_link" ]; then
			case "$_link" in
				/*) _real="$_link" ;;
				*) _real="$(cd "$(dirname "$_py")" && pwd)/$_link" ;;
			esac
		fi
	fi
	case "$SEEN" in
		*"|$_real|"*) return 0 ;; # already inspected this file
	esac
	SEEN="$SEEN|$_real|"

	_ver="$(read_version "$_py")"
	if [ -z "$_ver" ]; then
		# An unprobeable candidate (for example a bare `python` that is
		# Python 2 and rejects -I) must not fail a run that does find the
		# pinned interpreter. If no pinned interpreter is found, the final
		# check below still fails the run closed.
		warn "cannot read a Python version from $_py (skipping this candidate; the run fails if no pinned interpreter is found)"
		return 1
	fi
	_build="$(read_build "$_py")"
	info "interpreter: $_py"
	info "  real path:  $_real"
	info "  version:    $_ver"
	info "  build:      $_build"

	OBSERVED_SHA=""
	if [ "$_ver" = "$PIN_VERSION" ]; then
		FOUND_PINNED=1
		ok "interpreter version matches the pin ($PIN_VERSION)"
		check_interpreter_digest "$_real" "$_ver"
	else
		info "  version does not match the pin ($PIN_VERSION); recorded as present, not compared"
		# Still observe its digest for --record, but never compare it against
		# the pinned version's recorded local digest.
		OBSERVED_SHA="$(sha256_of "$_real" 2>/dev/null)" || OBSERVED_SHA=""
	fi
	if [ -n "$OBSERVED_SHA" ]; then
		obs_append "$_ver" "$OBSERVED_SHA" "$_real"
	fi
}

check_interpreter_digest() {
	_real="$1"; _ver="$2"
	if ! _observed="$(sha256_of "$_real")"; then
		bad "cannot compute the sha256 of $_real"
		return 1
	fi
	OBSERVED_SHA="$_observed"
	_obs_key="local_interpreter_${PIN_MAJOR}${PIN_MINOR}"
	_expected="$(digest_get "${_obs_key}_sha256")"
	if [ -z "$_expected" ]; then
		[ "$LOCAL_DIGEST_STATE" = "compared" ] || LOCAL_DIGEST_STATE="not compared (no recorded digest)"
		warn "no recorded local digest for a $PIN_VERSION interpreter in $DIGEST_FILE (NOT RECORDED; nothing is invented)"
		info "observed sha256: $_observed"
		return 0
	fi
	_expected_path="$(digest_get "${_obs_key}_path")"
	if [ -n "$_expected_path" ] && [ "$_real" != "$_expected_path" ]; then
		# The baseline is one observed build at one canonical path, not a
		# per-host value. A different path means no recorded observation
		# applies; say so even under --quiet.
		[ "$LOCAL_DIGEST_STATE" = "compared" ] || LOCAL_DIGEST_STATE="not compared (different path)"
		warn "different local build: $_real is not the recorded path $_expected_path; local digest NOT compared (NOT RECORDED for this path)."
		info "  version match is not authentication; the baseline applies only to its own path."
		info "observed sha256: $_observed"
		info "  provenance: LOCAL observation only; not publisher-authenticated"
		return 0
	fi
	LOCAL_DIGEST_STATE="compared"
	if [ "$_observed" = "$_expected" ]; then
		ok "interpreter sha256 matches the recorded LOCAL observation"
	else
		bad "interpreter sha256 changed: observed $_observed, recorded $_expected (a local build changed; this is not an upstream verification)"
	fi
	info "interpreter sha256: $_observed"
	info "  provenance: LOCAL observation only; not publisher-authenticated"
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
	_role=""
	for _key in macos_pkg windows_amd64_exe source_tarxz source_tgzz; do
		if [ "$(pin_get "${_key}_file")" = "$_name" ]; then
			_expected="$(pin_get "${_key}_sha256")"
			_url="$(pin_get "${_key}_url")"
			_role="$(pin_get "${_key}_role")"
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
	info "  artifact role:  ${_role:-unknown (not recorded)}"
	_matched=0
	if [ "$_observed" = "$_expected" ]; then
		_matched=1
		ok "$_name sha256 matches the pinned recorded digest (python.org's published SHA-256 as recorded in pin/python.txt)"
	else
		bad "$_name sha256 mismatch: observed $_observed, pinned recorded digest $_expected"
	fi
	obs_append_archive "$_name" "$_observed"
	info "  observed sha256: $_observed"
	info "  pinned recorded sha256: $_expected"
	if [ "$_matched" -ne 1 ]; then
		info "  note: this file does not match the pinned digest, so the pin's recorded"
		info "        digest/Sigstore evidence does NOT apply to it. Nothing about its publisher"
		info "        authenticity is established by this failed comparison."
	elif [ -n "$PIN_PUB_DIGEST_DATE" ] && [ -n "$PIN_PUB_DIGEST_RESULT" ] &&
	   [ -n "$PIN_PUB_SIGSTORE_DATE" ] && [ -n "$PIN_PUB_SIGSTORE_RESULT" ]; then
		info "  recorded evidence for bytes matching this digest: $PIN_PUB_DIGEST_RESULT on"
		info "        $PIN_PUB_DIGEST_DATE, and $PIN_PUB_SIGSTORE_RESULT on $PIN_PUB_SIGSTORE_DATE against"
		info "        ${PIN_SIGSTORE_EMAIL:-hugo@python.org} via ${PIN_SIGSTORE_ISSUER:-https://github.com/login/oauth}."
		info "        This check did not perform Sigstore; see ${PIN_VERIFICATION_RECORD:-docs/PYTHON_TOOLCHAIN_EVIDENCE.md}."
	else
		info "  note: the pin's publisher-evidence fields are incomplete (digest date/result:"
		info "        $PIN_PUB_DIGEST_DATE/$PIN_PUB_DIGEST_RESULT; Sigstore date/result:"
		info "        $PIN_PUB_SIGSTORE_DATE/$PIN_PUB_SIGSTORE_RESULT). No publisher evidence is claimed."
		info "  A digest match is not Sigstore authentication; run the .sigstore procedure"
		info "        from ${PIN_SIGSTORE_DOC:-the python.org Sigstore guide} to authenticate the publisher."
	fi
}

# --- The distinction this pin exists to keep visible -------------------------
print_distinction() {
	info ""
	info "verification scope (publisher artifact bytes vs installed binary):"
	if [ -n "$PIN_PUB_DIGEST_DATE" ] && [ -n "$PIN_PUB_DIGEST_RESULT" ]; then
		info "  * publisher digest match: $PIN_PUB_DIGEST_RESULT on $PIN_PUB_DIGEST_DATE"
		info "    (official artifact bytes downloaded over HTTPS vs the release-page SHA-256)."
	elif [ -n "$PIN_PUB_DIGEST_DATE" ] || [ -n "$PIN_PUB_DIGEST_RESULT" ]; then
		info "  * publisher digest match: INCOMPLETE (date=$PIN_PUB_DIGEST_DATE result=$PIN_PUB_DIGEST_RESULT); not claimed."
	else
		info "  * publisher digest match: NOT RECORDED."
	fi
	if [ -n "$PIN_PUB_SIGSTORE_DATE" ] && [ -n "$PIN_PUB_SIGSTORE_RESULT" ]; then
		info "  * publisher Sigstore signature: recorded result: $PIN_PUB_SIGSTORE_RESULT on $PIN_PUB_SIGSTORE_DATE"
		info "    (signer ${PIN_SIGSTORE_EMAIL:-hugo@python.org}, issuer ${PIN_SIGSTORE_ISSUER:-https://github.com/login/oauth};"
		info "    $PIN_SIGSTORE_VERIFIER)."
		info "    Record: ${PIN_VERIFICATION_RECORD:-docs/PYTHON_TOOLCHAIN_EVIDENCE.md} sections 4-5."
	elif [ -n "$PIN_PUB_SIGSTORE_DATE" ] || [ -n "$PIN_PUB_SIGSTORE_RESULT" ]; then
		info "  * publisher Sigstore signature: INCOMPLETE (date=$PIN_PUB_SIGSTORE_DATE result=$PIN_PUB_SIGSTORE_RESULT); not claimed."
	else
		info "  * publisher Sigstore signature: NOT RECORDED."
	fi
	info "  * Source vs target: the .tgz/.tar.xz artifacts are source-of-record"
	info "    archives; the macOS pkg and Windows amd64 exe are separate target"
	info "    installers. A digest match establishes agreement with the pinned digest"
	info "    for those installer bytes; it is not Sigstore authentication and does not"
	info "    authenticate any interpreter built from the source."
	if [ "$ARCHIVE_COUNT" -gt 0 ]; then
		info "  * This run compared $ARCHIVE_COUNT given --archive file(s) with the published digest."
	else
		info "  * No official artifact was checked in this run. Pass --archive <file>"
		info "    to compare a downloaded official artifact with the published digest."
	fi
	info "  * Installed interpreters are LOCAL BUILDS. A version match plus the"
	info "    recorded local sha256 detects drift only; neither is publisher"
	info "    authentication, and no local build is evidence about python.org bytes."
	if [ "${PIN_INSTALLED_AUTH:-}" = "no" ]; then
		info "  * pin records installed_interpreter_publisher_authenticated=no."
	fi
	if [ "${PIN_HOMEBREW_VERIFIED:-}" = "no" ]; then
		info "  * Homebrew channel is checksum-only here: ad-hoc-signed bottle, API JWS"
		info "    unverified, framework bundle signature question OPEN (docs/PYTHON_TOOLCHAIN.md)."
	fi
}

# Refuse --record destinations that exist or alias/overlap protected inputs.
# The policy is deliberately conservative: recording may only create a path
# that does not exist yet. Existence covers regular files, directories, FIFO/
# socket/device nodes, and symlinks (including dangling ones); because the
# script never follows an existing --record path, hard-link aliases of an
# archive, interpreter, pin or digest file are refused too.
validate_record_target() {
	[ -n "$RECORD_FILE" ] || return 0
	reject_newline "--record path" "$RECORD_FILE"
	if [ -e "$RECORD_FILE" ] || [ -L "$RECORD_FILE" ]; then
		die "--record target already exists: $RECORD_FILE (refusing to overwrite an existing file, link, socket or directory; choose a fresh path)"
	fi

	_protected="$PIN_FILE$NL$DIGEST_FILE"
	[ -n "$PYTHON_BIN" ] && _protected="$_protected$NL$PYTHON_BIN"
	_oldifs="$IFS"
	IFS="$NL"
	set -f
	for _p in $_protected $ARCHIVE_FILES; do
		[ -n "$_p" ] || continue
		if [ "$_p" = "$RECORD_FILE" ]; then
			IFS="$_oldifs"
			set +f
			die "--record target overlaps a protected input or pin path: $RECORD_FILE"
		fi
	done
	IFS="$_oldifs"
	set +f
	return 0
}

record_digests() {
	[ -n "$RECORD_FILE" ] || return 0
	_dir="$(dirname "$RECORD_FILE")"
	mkdir -p "$_dir" || die "cannot create $_dir"

	# Check again immediately before opening: a concurrent writer may have
	# created the target since validation. Exclusive creation (noclobber) must
	# fail rather than truncate; see the README's residual-race limitation.
	if [ -e "$RECORD_FILE" ] || [ -L "$RECORD_FILE" ]; then
		die "--record target appeared before creation: $RECORD_FILE (refusing to overwrite)"
	fi

	set -C
	{
		printf '# Observed digests recorded by tools/python_pin/verify.sh --record\n'
		printf '# Recorded %s on %s (%s %s)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(hostname)" "$(uname -s)" "$(uname -m)"
		printf '# LOCAL observations only. An installed interpreter is a local build;\n'
		printf '# these digests are NOT publisher authentication (see pin/python.txt).\n'
		printf 'pinned_version=%s\n' "$PIN_VERSION"
		if [ "$RC" -ne 0 ]; then
			printf '# NOTE: verification FAILED in this run; the lines below are diagnostic\n'
			printf '#       observations, not a passing result.\n'
		fi
		if [ "$NO_INTERPRETER" -eq 1 ]; then
			printf '# interpreter checks were skipped (--no-interpreter); no interpreter digests recorded.\n'
		elif [ -z "$OBSERVED_INTERPRETERS" ]; then
			printf '# no interpreter observations were available (none inspected or none readable).\n'
		fi
		# Only observations already collected during checks are written.
		# Interpreter entries are triples (version, sha256, real path);
		# archive entries are pairs (file name, observed sha256). Recording
		# never re-probes an interpreter and never re-reads an archive, so
		# --no-interpreter is honored here too and what is recorded is
		# exactly what was checked.
		printf '%s\n' "$OBSERVED_INTERPRETERS" | while IFS= read -r _ver &&
			IFS= read -r _sha &&
			IFS= read -r _real; do
			[ -n "$_ver" ] || continue
			# Emit the drift-lookup key convention
			# (local_interpreter_<major><minor>_{sha256,path}); the shared file
			# keeps one older local_interpreter_396_* entry. Store the
			# realpath-resolved path when the selected file is a symlink; a real
			# launcher such as macOS /usr/bin/python3 stays the launcher.
			_maj="${_ver%%.*}"
			_rest="${_ver#*.}"
			_min="${_rest%%.*}"
			_key="local_interpreter_${_maj}${_min}"
			printf '%s_sha256=%s\n' "$_key" "$_sha"
			printf '%s_path=%s\n' "$_key" "$_real"
		done
		printf '%s\n' "$OBSERVED_ARCHIVES" | while IFS= read -r _name &&
			IFS= read -r _sha; do
			[ -n "$_name" ] || continue
			printf 'archive_%s_sha256=%s\n' "$_name" "$_sha"
		done
	} >"$RECORD_FILE" || die "cannot create $RECORD_FILE (refusing to overwrite an existing target)"
	set +C
	info "observed digests written to $RECORD_FILE"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
		--python)
			[ $# -ge 2 ] || die "--python needs a path"
			[ -n "$2" ] || die "--python requires a non-empty path"
			reject_newline "--python path" "$2"
			PYTHON_BIN="$2"; shift 2 ;;
		--python=*)
			PYTHON_BIN="${1#--python=}"
			[ -n "$PYTHON_BIN" ] || die "--python requires a non-empty path"
			reject_newline "--python path" "$PYTHON_BIN"
			shift ;;
		--archive)
			[ $# -ge 2 ] || die "--archive needs a file path"
			[ -n "$2" ] || die "--archive requires a non-empty file path"
			reject_newline "--archive path" "$2"
			ARCHIVE_FILES="$(append_path "$ARCHIVE_FILES" "$2")"
			ARCHIVE_COUNT=$((ARCHIVE_COUNT + 1))
			shift 2 ;;
		--archive=*)
			_a="${1#--archive=}"
			[ -n "$_a" ] || die "--archive requires a non-empty file path"
			reject_newline "--archive path" "$_a"
			ARCHIVE_FILES="$(append_path "$ARCHIVE_FILES" "$_a")"
			ARCHIVE_COUNT=$((ARCHIVE_COUNT + 1))
			shift ;;
		--no-interpreter) NO_INTERPRETER=1; shift ;;
		--quiet) QUIET=1; shift ;;
		--record)
			[ $# -ge 2 ] || die "--record needs a file path"
			[ -n "$2" ] || die "--record requires a non-empty file path"
			reject_newline "--record path" "$2"
			RECORD_FILE="$2"; shift 2 ;;
		--record=*)
			RECORD_FILE="${1#--record=}"
			[ -n "$RECORD_FILE" ] || die "--record requires a non-empty file path"
			reject_newline "--record path" "$RECORD_FILE"
			shift ;;
		-h | --help | help) usage ;;
		*) die "unknown option: $1 (see --help)" ;;
	esac
done

RC=0
load_pin
require_sha256_tool
validate_record_target

printf '%sRoadstorm asset-generation Python pin verification (pin %s)%s\n' "$C_BOLD" "$PIN_VERSION" "$C_RESET"
info "host: $(hostname) / $(uname -s) $(uname -r) $(uname -m)"
info "release page: $PIN_RELEASE_PAGE"
info ""

if [ "$NO_INTERPRETER" -eq 1 ]; then
	LOCAL_DIGEST_STATE="skipped (--no-interpreter)"
	warn "interpreter checks skipped on request (--no-interpreter)"
else
	_FOUND_ANY=0
	for_each_python_candidate consider_candidate
	if [ "$_FOUND_ANY" -eq 0 ]; then
		LOCAL_DIGEST_STATE="no local interpreter found"
		bad "no Python interpreter found (set PYTHON_BIN=/path/to/python or pass --python)"
	elif [ "$FOUND_PINNED" -eq 0 ]; then
		LOCAL_DIGEST_STATE="no pinned-version interpreter"
		bad "no local interpreter reports the pinned version $PIN_VERSION (install it, point --python at it, or pass --no-interpreter to skip this check explicitly)"
	fi
fi

if [ "$ARCHIVE_COUNT" -gt 0 ]; then
	_oldifs="$IFS"
	IFS="$NL"
	set -f
	for _f in $ARCHIVE_FILES; do
		[ -n "$_f" ] || continue
		check_archive "$_f"
	done
	set +f
	IFS="$_oldifs"
fi

print_distinction
record_digests

PUB_EVIDENCE="not recorded"
if [ -n "$PIN_PUB_DIGEST_DATE" ] && [ -n "$PIN_PUB_DIGEST_RESULT" ] &&
   [ -n "$PIN_PUB_SIGSTORE_DATE" ] && [ -n "$PIN_PUB_SIGSTORE_RESULT" ]; then
	PUB_EVIDENCE="digest+Sigstore recorded $PIN_PUB_DIGEST_DATE"
elif [ -n "$PIN_PUB_DIGEST_DATE" ] || [ -n "$PIN_PUB_DIGEST_RESULT" ] ||
     [ -n "$PIN_PUB_SIGSTORE_DATE" ] || [ -n "$PIN_PUB_SIGSTORE_RESULT" ]; then
	PUB_EVIDENCE="partially recorded"
fi
ARCHIVE_SUMMARY="none"
[ "$ARCHIVE_COUNT" -gt 0 ] && ARCHIVE_SUMMARY="performed ($ARCHIVE_COUNT)"
INSTALLED_SCOPE="local build, not publisher-authenticated"
[ "${PIN_INSTALLED_AUTH:-}" = "yes" ] && INSTALLED_SCOPE="publisher-authenticated"

info ""
if [ "$RC" -eq 0 ]; then
	printf '%s[ok]%s   python pin verification: PASS (local interpreter observations; local digest: %s; official-artifact checks: %s; publisher artifact evidence: %s; installed binary: %s)\n' \
		"$C_GREEN" "$C_RESET" \
		"$LOCAL_DIGEST_STATE" \
		"$ARCHIVE_SUMMARY" \
		"$PUB_EVIDENCE" \
		"$INSTALLED_SCOPE"
else
	printf '%s[fail]%s python pin verification: FAIL (local digest: %s)\n' \
		"$C_RED" "$C_RESET" "$LOCAL_DIGEST_STATE"
fi
exit "$RC"
