#!/bin/sh
# Roadstorm Racer! - toolchain verification (PLAN.md M0.1).
#
# Ownership: tools/toolchain/**. The narrative record lives in
# docs/TOOLCHAIN.md; this script turns that record into an executable check.
#
# What it verifies about the locally installed toolchain:
#   1. a Godot editor binary exists and runs;
#   2. its `--version` string matches the pinned 4.7.2 official build;
#   3. the editor binary's sha256 matches the digest recorded from this
#      machine (a local observation, never an upstream verification);
#   4. matching export templates are installed (version.txt + the three
#      target-platform files) and their sha256 values match the record;
#   5. with --deep: the macOS template's internal release binary really is the
#      pinned build (executed), and the editor binary carries the built-in
#      Jolt 3D physics module.
#
# What it deliberately does NOT claim:
#   * that the local digests match the official release assets (no download);
#   * that any other platform's template binary runs (only macOS does here).
#
# Usage:
#   tools/toolchain/verify.sh                 verify the local toolchain
#   tools/toolchain/verify.sh --godot <path>  use a specific editor binary
#   tools/toolchain/verify.sh --templates <dir>
#   tools/toolchain/verify.sh --deep          also run the in-template checks
#   tools/toolchain/verify.sh --record <file> write observed digests to <file>
#   tools/toolchain/verify.sh --quiet         failures and summary only
#
# Exit codes: 0 = passed, 1 = a check failed, 2 = the command could not run.
# Original project code under the Unlicense.

set -u

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
PIN_DIR="$TOOLS_DIR/pin"
PIN_FILE="$PIN_DIR/engine.txt"
DIGEST_FILE="$PIN_DIR/checksums.txt"

OK=0
FAIL=1
USAGE=2

GODOT_BIN="${GODOT_BIN:-}"
TEMPLATES_DIR="${GODOT_TEMPLATES_DIR:-}"
DEEP=0
QUIET=0
RECORD_FILE=""
DEEP_MACOS_BIN=""

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
	sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
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

# tc_list_dirs <dir> : space-separated names of the immediate subdirectories.
tc_list_dirs() {
	_dir="$1"
	[ -d "$_dir" ] || return 0
	for _entry in "$_dir"/*; do
		[ -d "$_entry" ] || continue
		printf '%s ' "${_entry##*/}"
	done
	printf '\n'
}

load_pin() {
	[ -f "$PIN_FILE" ] || die "missing pin file: $PIN_FILE"
	[ -f "$DIGEST_FILE" ] || die "missing digest file: $DIGEST_FILE"

	PIN_MAJOR="$(pin_get major)"
	PIN_MINOR="$(pin_get minor)"
	PIN_PATCH="$(pin_get patch)"
	PIN_TAG="$(pin_get tag)"
	PIN_COMMIT="$(pin_get commit)"
	PIN_VERSION_STRING="$(pin_get version_string)"
	PIN_UPSTREAM_VERIFIED="$(pin_get upstream_verified)"
	PIN_TEMPLATES_VERSION="$(pin_get templates_version)"

	[ -n "$PIN_MAJOR$PIN_MINOR$PIN_PATCH" ] || die "pin file is incomplete: $PIN_FILE"
	[ -n "$PIN_TEMPLATES_VERSION" ] || die "pin file has no templates_version: $PIN_FILE"
	PIN_VERSION="${PIN_MAJOR}.${PIN_MINOR}.${PIN_PATCH}"
}

# ---------------------------------------------------------------------------
# Godot discovery (mirrors tools/ci/lib/common.sh ordering)
# ---------------------------------------------------------------------------
find_godot() {
	if [ -n "$GODOT_BIN" ]; then
		[ -x "$GODOT_BIN" ] || die "GODOT_BIN is set but not executable: $GODOT_BIN"
		return 0
	fi
	for candidate in \
		"$(command -v godot 2>/dev/null)" \
		"$(command -v godot4 2>/dev/null)" \
		"$(command -v Godot 2>/dev/null)" \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"/opt/homebrew/bin/godot" \
		"/usr/local/bin/godot" \
		"/usr/bin/godot"
	do
		if [ -n "$candidate" ] && [ -x "$candidate" ]; then
			GODOT_BIN="$candidate"
			return 0
		fi
	done
	die "no Godot editor binary found. Set GODOT_BIN=/path/to/godot (see tools/toolchain/README.md)."
}

find_templates_dir() {
	if [ -n "$TEMPLATES_DIR" ]; then
		[ -d "$TEMPLATES_DIR" ] || die "template directory does not exist: $TEMPLATES_DIR"
		return 0
	fi
	for candidate in \
		"${HOME}/Library/Application Support/Godot/export_templates" \
		"${HOME}/.local/share/godot/export_templates" \
		"${HOME}/.var/app/org.godotengine.Godot/data/godot/export_templates" \
		"${APPDATA:-}/Godot/export_templates"
	do
		if [ -n "$candidate" ] && [ -d "$candidate" ]; then
			TEMPLATES_DIR="$candidate"
			return 0
		fi
	done
	return 1
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
check_version() {
	info "engine binary: $GODOT_BIN"
	_path_entry="$(command -v godot 2>/dev/null)"
	if [ -n "$_path_entry" ]; then
		info "'godot' on PATH resolves to: $_path_entry"
	else
		info "'godot' is not on PATH"
	fi

	ENGINE_VERSION="$("$GODOT_BIN" --version 2>/dev/null | head -n 1)"
	[ -n "$ENGINE_VERSION" ] || { bad "cannot read the engine version from $GODOT_BIN"; return 1; }
	info "engine --version: $ENGINE_VERSION"

	case "$ENGINE_VERSION" in
		"$PIN_VERSION_STRING")
			ok "engine version string matches the pin exactly ($PIN_VERSION_STRING)" ;;
		*)
			bad "engine version string is '$ENGINE_VERSION', pinned '$PIN_VERSION_STRING'" ;;
	esac

	case "$ENGINE_VERSION" in
		*.official.*) ok "version string reports an official build" ;;
		*) warn "version string does not contain '.official.': $ENGINE_VERSION" ;;
	esac

	# The commit hash is only meaningful for official builds.
	case "$ENGINE_VERSION" in
		*"$PIN_COMMIT"*) ok "build commit $PIN_COMMIT present in the version string" ;;
		*) warn "build commit $PIN_COMMIT not found in the version string" ;;
	esac
}

check_editor_digest() {
	_expected="$(digest_get editor_sha256)"
	_observed="$(sha256_of "$GODOT_BIN")" || { warn "no sha256 tool available; cannot check the editor digest"; return 0; }
	if [ -z "$_expected" ]; then
		warn "editor sha256 NOT RECORDED in $DIGEST_FILE (not a failure; nothing is invented)"
		info "observed sha256: $_observed"
		return 0
	fi
	if [ "$_observed" = "$_expected" ]; then
		ok "editor sha256 matches the recorded local digest"
	else
		bad "editor sha256 changed: observed $_observed, recorded $_expected"
	fi
	info "editor sha256: $_observed"
}

check_templates() {
	if ! find_templates_dir; then
		warn "no export templates directory found (only needed by 'ci.sh export')"
		return 0
	fi
	info "templates directory: $TEMPLATES_DIR"

	_tdir="$TEMPLATES_DIR/$PIN_TEMPLATES_VERSION"
	if [ ! -d "$_tdir" ]; then
		bad "no $PIN_TEMPLATES_VERSION template directory in $TEMPLATES_DIR"
		info "present: $(tc_list_dirs "$TEMPLATES_DIR")"
		return 1
	fi

	_tver="$(head -n 1 "$_tdir/version.txt" 2>/dev/null)"
	if [ "$_tver" = "$PIN_TEMPLATES_VERSION" ]; then
		ok "template version.txt reports $PIN_TEMPLATES_VERSION (matches the editor)"
	else
		bad "template version.txt reports '$_tver', pinned '$PIN_TEMPLATES_VERSION'"
	fi

	# The three target platforms of PLAN.md "Platforms".
	for _file in macos.zip windows_release_x86_64.exe linux_release.x86_64; do
		if [ -f "$_tdir/$_file" ]; then
			ok "target template present: $_file"
		else
			bad "missing target template: $_tdir/$_file"
		fi
	done

	check_template_digest "$_tdir" version.txt templates_version_txt_sha256
	check_template_digest "$_tdir" macos.zip templates_macos_zip_sha256
	check_template_digest "$_tdir" windows_release_x86_64.exe templates_windows_x86_64_sha256
	check_template_digest "$_tdir" linux_release.x86_64 templates_linux_x86_64_sha256
}

check_template_digest() {
	_dir="$1"; _file="$2"; _key="$3"
	_expected="$(digest_get "$_key")"
	_observed="$(sha256_of "$_dir/$_file")" || { warn "cannot digest $_file"; return 0; }
	if [ -z "$_expected" ]; then
		warn "$_key NOT RECORDED in $DIGEST_FILE"
		info "observed sha256 ($_file): $_observed"
		return 0
	fi
	if [ "$_observed" = "$_expected" ]; then
		ok "$_file sha256 matches the recorded local digest"
	else
		bad "$_file sha256 changed: observed $_observed, recorded $_expected"
	fi
}

# --deep: run the macOS template's release binary and look for the Jolt module.
check_deep() {
	[ "$DEEP" -eq 1 ] || return 0
	_tdir="$TEMPLATES_DIR/$PIN_TEMPLATES_VERSION"
	[ -d "$_tdir" ] || { warn "--deep: no template directory to inspect"; return 0; }

	case "$(uname -s)" in
		Darwin) ;;
		*) warn "--deep macOS-template check needs macOS; skipped on $(uname -s)"; return 0 ;;
	esac

	_tmp="$(mktemp -d "${TMPDIR:-/tmp}/roadstorm-toolchain.XXXXXX")" || { warn "--deep: cannot create a temporary directory"; return 0; }
	# shellcheck disable=SC2064
	trap "rm -rf '$_tmp'" EXIT INT TERM

	info "--deep: extracting macos.zip (release binary only) to $_tmp"
	if unzip -o -q "$_tdir/macos.zip" \
		"macos_template.app/Contents/MacOS/godot_macos_release.universal" -d "$_tmp" 2>/dev/null; then
		_bin="$_tmp/macos_template.app/Contents/MacOS/godot_macos_release.universal"
		DEEP_MACOS_BIN="$_bin"
		_ver="$("$_bin" --headless --version 2>/dev/null | head -n 1)"
		if [ "$_ver" = "$PIN_VERSION_STRING" ]; then
			ok "macOS template release binary reports $PIN_VERSION_STRING (executed)"
		else
			bad "macOS template release binary reports '$_ver', pinned '$PIN_VERSION_STRING'"
		fi
		_expected="$(digest_get macos_template_release_sha256)"
		_observed="$(sha256_of "$_bin")"
		if [ -n "$_expected" ] && [ "$_observed" = "$_expected" ]; then
			ok "macOS template release binary sha256 matches the recorded local digest"
		elif [ -n "$_expected" ]; then
			bad "macOS template release binary sha256 changed: observed $_observed, recorded $_expected"
		else
			warn "macos_template_release_sha256 NOT RECORDED in $DIGEST_FILE"
			info "observed sha256: $_observed"
		fi
	else
		warn "--deep: could not extract macos.zip (unzip unavailable?)"
	fi

	# The Jolt 3D backend must be compiled into the pinned editor (PLAN.md M0.1).
	if grep -a -q "JoltBodyActivationListener" "$GODOT_BIN" 2>/dev/null; then
		ok "editor binary contains the built-in Jolt 3D physics module"
	else
		bad "editor binary shows no Jolt module strings; the pinned build is not the expected one"
	fi
}

record_digests() {
	[ -n "$RECORD_FILE" ] || return 0
	_dir="$(dirname "$RECORD_FILE")"
	mkdir -p "$_dir" || die "cannot create $_dir"
	{
		printf '# Observed digests recorded by tools/toolchain/verify.sh --record\n'
		printf '# Recorded %s on %s (%s %s)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(hostname)" "$(uname -s)" "$(uname -m)"
		printf '# LOCAL observations only. Not upstream verification.\n'
		printf 'editor_sha256=%s\n' "$(sha256_of "$GODOT_BIN")"
		if [ -n "$TEMPLATES_DIR" ] && [ -d "$TEMPLATES_DIR/$PIN_TEMPLATES_VERSION" ]; then
			_tdir="$TEMPLATES_DIR/$PIN_TEMPLATES_VERSION"
			for _entry in \
				"templates_version_txt_sha256:version.txt" \
				"templates_macos_zip_sha256:macos.zip" \
				"templates_windows_x86_64_sha256:windows_release_x86_64.exe" \
				"templates_linux_x86_64_sha256:linux_release.x86_64"
			do
				_key="${_entry%%:*}"
				_file="${_entry#*:}"
				[ -f "$_tdir/$_file" ] || continue
				printf '%s=%s\n' "$_key" "$(sha256_of "$_tdir/$_file")"
			done
		fi
		if [ -n "$DEEP_MACOS_BIN" ] && [ -f "$DEEP_MACOS_BIN" ]; then
			printf 'macos_template_release_sha256=%s\n' "$(sha256_of "$DEEP_MACOS_BIN")"
		fi
	} >"$RECORD_FILE" || die "cannot write $RECORD_FILE"
	info "observed digests written to $RECORD_FILE"
}

print_upstream_status() {
	info ""
	info "upstream checksum verification: ${PIN_UPSTREAM_VERIFIED:-no}"
	if [ "${PIN_UPSTREAM_VERIFIED:-no}" = "yes" ]; then
		info "  selected files matched members of publisher-checksummed archives; see docs/evidence."
	else
		info "  NOT PERFORMED. The digests above are local observations; no official"
		info "  release asset was downloaded to compare them against. See"
		info "  docs/TOOLCHAIN.md §Upstream verification for what would close this."
	fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
		--godot) [ $# -ge 2 ] || die "--godot needs a path"; GODOT_BIN="$2"; shift 2 ;;
		--godot=*) GODOT_BIN="${1#--godot=}"; shift ;;
		--templates) [ $# -ge 2 ] || die "--templates needs a directory"; TEMPLATES_DIR="$2"; shift 2 ;;
		--templates=*) TEMPLATES_DIR="${1#--templates=}"; shift ;;
		--deep) DEEP=1; shift ;;
		--quiet) QUIET=1; shift ;;
		--record) [ $# -ge 2 ] || die "--record needs a file path"; RECORD_FILE="$2"; shift 2 ;;
		--record=*) RECORD_FILE="${1#--record=}"; shift ;;
		-h | --help | help) usage ;;
		*) die "unknown option: $1 (see --help)" ;;
	esac
done

RC=0
load_pin
find_godot

printf '%sRoadstorm toolchain verification (pin %s, release tag %s)%s\n' "$C_BOLD" "$PIN_VERSION" "$PIN_TAG" "$C_RESET"
info "host: $(hostname) / $(uname -s) $(uname -r) $(uname -m)"
info ""

check_version
check_editor_digest
check_templates
check_deep
record_digests
print_upstream_status

info ""
if [ "$RC" -eq 0 ]; then
	printf '%s[ok]%s   toolchain verification: PASS (local observations; upstream verification %s)\n' \
		"$C_GREEN" "$C_RESET" "${PIN_UPSTREAM_VERIFIED:-no}"
else
	printf '%s[fail]%s toolchain verification: FAIL\n' "$C_RED" "$C_RESET"
fi
exit "$RC"
