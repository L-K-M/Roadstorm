#!/bin/sh
# Roadstorm Racer! - portable command-line entry points and CI driver.
#
# Ownership: tools/ci/** (see PLAN.md "How agents execute the plan"). Nothing in
# this file writes to the shared Godot project or its .godot/ import cache: every
# engine run happens in a scratch copy under tools/ci/out/, which is gitignored.
#
# Commands
#   doctor                 report the machine, engine and tooling environment
#   import                 headless import of a scratch copy (T01)
#   validate               engine pin, project settings, resource/script scan (T01)
#   test                   run the discovered headless checks + exit-code proof (M0.4)
#   capture                deterministic movie capture driver
#   export                 export preparation (templates + presets + optional build)
#   verify-engine          verify a downloaded release artifact against the
#                          pinned publisher digest, before extraction/execution
#                          (M0.1)
#   pin                    print the pinned engine facts as key=value lines
#   all                    import + validate + test (what CI runs)
#   help | commands | version
#
# Design rules (PLAN.md M0.4/M0.5, docs/TECHNICAL_DESIGN.md verification matrix):
#   * a failing check returns exit 1; an unusable command returns exit 2;
#   * nothing that is not implemented is claimed to work - missing export
#     presets, capture stages or content validation fail (or report) explicitly;
#   * every engine invocation is logged under tools/ci/out/logs/.
#
# Original project code under the Unlicense.

CI_TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
CI_DEFAULT_PROJECT="$(cd "$CI_TOOLS_DIR/../.." && pwd)"

# shellcheck source=lib/common.sh
. "$CI_TOOLS_DIR/lib/common.sh"

# ---------------------------------------------------------------------------
# Global options
# ---------------------------------------------------------------------------
CI_PROJECT="$CI_DEFAULT_PROJECT"
CI_OUT=""
CI_IN_PLACE=0
CI_REUSE_COPY=0
CI_STRICT_CONTRACTS=0

ci_usage() {
	cat <<'EOF'
Roadstorm Racer! command tooling (tools/ci/ci.sh)

Usage: ci.sh [global options] <command> [command options]

Global options:
  --project <dir>    Project root containing project.godot
                     (default: the checkout this script lives in)
  --godot <path>     Godot editor binary (default: $GODOT_BIN, then PATH,
                     then common install locations)
  --out <dir>        Scratch/report directory (default: <project>/tools/ci/out)
  --in-place         Run the engine against the project itself instead of a
                     scratch copy. This writes the project's .godot/ import
                     cache; do not use it on a shared checkout.
  --reuse-copy       Keep an existing scratch copy instead of re-copying
  --timeout <sec>    Wall-clock limit per engine invocation (default 300)
  --source-sha <sha> Record the source revision under test in the report
  --no-color         Disable ANSI colour
  -h, --help         This help

Commands:
  doctor [--display]      Machine/engine/tooling report. --display also runs
                          the engine with a real display driver to record the
                          GPU and input devices (headless reports dummies).
  import [--in-place]     Headless --import of a scratch copy (T01).
  validate                Engine pin, project settings, resource/script scan,
                          tooling self-check, content-contract inventory.
  test [--list] [--filter <substr>] [--require-tests]
                          Run the discovered headless checks; prove that a
                          deliberately failing check exits nonzero (M0.4).
  capture --check | --list | --probe | --target <res://path>
                          Deterministic movie capture (AVI) driver. The requested
                          resolution is applied to the scratch copy's viewport
                          and the recorded size is verified afterwards.
  export --check | --list-presets | --export <preset> --out <file>
                          Export preparation and optional native export.
  verify-engine --archive <file> [--binary <file>]
                          Compare a downloaded release archive (and optionally
                          the extracted editor binary) against the pinned
                          publisher digest in tools/ci/pin/engine.txt. Fails
                          before anything is extracted or executed (M0.1).
                          Resolves no engine, so it runs on a host with none.
  pin [--field <name>]    Print the pinned engine facts (tag, version, official
                          URLs and digests) as key=value lines.
  all                     import + validate + test (the CI check set).

Environment:
  GODOT_BIN, GODOT_TEMPLATES_DIR, ROADSTORM_SOURCE_SHA, NO_COLOR,
  CI_TIMEOUT_DEFAULT

Exit codes: 0 = passed, 1 = a check failed, 2 = the command could not run.
EOF
}

ci_commands() {
	cat <<'EOF'
doctor      environment and engine-pin report
import      headless import of a scratch project copy
validate    static checks: pin, settings, resource/script scan, tooling
test        run discovered headless checks and the exit-code proof
capture     deterministic AVI capture driver
export      export preparation and optional native export
verify-engine  verify a downloaded release archive against the pinned digest
pin         print the pinned engine facts
all         import + validate + test
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--project)
			[ $# -ge 2 ] || ci_die "--project needs a directory"
			CI_PROJECT="$2"
			shift 2
			;;
		--project=*)
			CI_PROJECT="${1#--project=}"
			shift
			;;
		--godot)
			[ $# -ge 2 ] || ci_die "--godot needs a path"
			GODOT_BIN="$2"
			shift 2
			;;
		--godot=*)
			GODOT_BIN="${1#--godot=}"
			shift
			;;
		--out)
			[ $# -ge 2 ] || ci_die "--out needs a directory"
			CI_OUT="$2"
			shift 2
			;;
		--out=*)
			CI_OUT="${1#--out=}"
			shift
			;;
		--in-place)
			CI_IN_PLACE=1
			shift
			;;
		--reuse-copy)
			CI_REUSE_COPY=1
			shift
			;;
		--strict-contracts)
			CI_STRICT_CONTRACTS=1
			shift
			;;
		--timeout)
			[ $# -ge 2 ] || ci_die "--timeout needs seconds"
			CI_TIMEOUT_DEFAULT="$2"
			shift 2
			;;
		--source-sha)
			[ $# -ge 2 ] || ci_die "--source-sha needs a revision"
			ROADSTORM_SOURCE_SHA="$2"
			shift 2
			;;
		--source-sha=*)
			ROADSTORM_SOURCE_SHA="${1#--source-sha=}"
			shift
			;;
		--no-color | --no-colour)
			NO_COLOR=1
			CI_C_RESET=""
			CI_C_RED=""
			CI_C_GREEN=""
			CI_C_YELLOW=""
			CI_C_BLUE=""
			CI_C_BOLD=""
			shift
			;;
		-h | --help | help)
			ci_usage
			exit "$CI_OK"
			;;
		commands)
			ci_commands
			exit "$CI_OK"
			;;
		--)
			shift
			break
			;;
		-*)
			ci_die "unknown global option: $1 (see --help)"
			;;
		*)
			break
			;;
	esac
done

CI_COMMAND="${1:-}"
[ -n "$CI_COMMAND" ] || {
	ci_usage
	exit "$CI_USAGE"
}
shift 2>/dev/null || true

# ---------------------------------------------------------------------------
# Resolve the project, the output directory and the engine
# ---------------------------------------------------------------------------
[ -d "$CI_PROJECT" ] || ci_die "project directory does not exist: $CI_PROJECT"
CI_PROJECT="$(cd "$CI_PROJECT" && pwd)"
[ -f "$CI_PROJECT/project.godot" ] || ci_die "no project.godot in $CI_PROJECT"

if [ -z "$CI_OUT" ]; then
	CI_OUT="$CI_PROJECT/tools/ci/out"
fi
mkdir -p "$CI_OUT" 2>/dev/null || ci_die "cannot create output directory: $CI_OUT"
CI_OUT="$(cd "$CI_OUT" && pwd)"

# Paths used to exclude the scratch directory from project copies.
CI_OUT_REL_PATH=""
CI_OUT_REL_PATTERN=""
case "$CI_OUT" in
	"$CI_PROJECT"/*)
		CI_OUT_REL_PATH="${CI_OUT#$CI_PROJECT/}"
		CI_OUT_REL_PATTERN="./$CI_OUT_REL_PATH"
		;;
esac
CI_OUT_RES=""
[ -n "$CI_OUT_REL_PATH" ] && CI_OUT_RES="res://$CI_OUT_REL_PATH"

CI_RUN_NAME="$CI_COMMAND"

# Engine discovery is lazy. `verify-engine` and `pin` only read pinned data and
# hash local files, so they must work on a host with no Godot installed at all --
# exactly the state of a clean CI runner before the pinned editor has been
# downloaded and verified. Resolving the engine eagerly would make those
# commands unusable at the point they are needed.
CI_NEEDS_GODOT=1
case "$CI_COMMAND" in
	verify-engine | pin) CI_NEEDS_GODOT=0 ;;
esac
if [ "$CI_NEEDS_GODOT" -eq 1 ]; then
	ci_find_godot || exit "$?"
fi
ci_pin_load || exit "$?"
ci_init_logs
ci_init_report

# ---------------------------------------------------------------------------
# Shared helpers used by the commands
# ---------------------------------------------------------------------------

# ci_prepared_copy : returns a usable scratch copy in $CI_PROJECT_COPY.
ci_prepared_copy() {
	if [ "$CI_IN_PLACE" -eq 1 ]; then
		CI_PROJECT_COPY="$CI_PROJECT"
		ci_warn "--in-place: the engine will write $CI_PROJECT/.godot/ (the shared import cache)"
		return "$CI_OK"
	fi
	# ci_prepare_copy owns the reuse decision, including refusing a stale copy of
	# the tooling itself.
	ci_prepare_copy
}

# ci_res_path <abs file> : res:// path for an engine argument. Accepts a path
# inside the scratch copy or inside the project (the copy mirrors the project);
# anything else is passed through unchanged, which the engine also accepts.
ci_res_path() {
	case "$1" in
		"$CI_PROJECT_COPY"/*) printf 'res://%s\n' "${1#$CI_PROJECT_COPY/}" ;;
		"$CI_PROJECT"/*) printf 'res://%s\n' "${1#$CI_PROJECT/}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}

# ---------------------------------------------------------------------------
# verify-engine : verify a downloaded release artifact against the pinned
# publisher digest BEFORE it is extracted or executed (PLAN.md M0.1: "Pin Godot
# 4.7.2 Standard ... with checksums. Verify before installation").
#
# This command deliberately resolves no engine: a clean CI runner has none yet,
# and verifying the download is what makes it safe to install one.
#
# Exit codes: 0 = every requested digest matched, 1 = a mismatch or an
# unrecorded pin, 2 = the command could not run.
# ---------------------------------------------------------------------------
cmd_verify_engine() {
	_archive=""
	_binary=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--archive)
				[ $# -ge 2 ] || ci_die "verify-engine: --archive needs a file"
				_archive="$2"
				shift 2
				;;
			--archive=*) _archive="${1#--archive=}"; shift ;;
			--binary)
				[ $# -ge 2 ] || ci_die "verify-engine: --binary needs a file"
				_binary="$2"
				shift 2
				;;
			--binary=*) _binary="${1#--binary=}"; shift ;;
			*) ci_die "verify-engine: unknown option $1" ;;
		esac
	done
	if [ -z "$_archive" ] && [ -z "$_binary" ]; then
		ci_die "verify-engine: give --archive <file> and/or --binary <file>"
	fi

	_rc="$CI_OK"
	ci_step "verify-engine: pinned release artifacts"
	ci_info "pin source:  $CI_PIN_SOURCE"
	ci_info "release tag: $CI_PIN_TAG"
	ci_info "archive url: ${CI_PIN_RELEASE_URL:-not recorded}"
	ci_info "checksums:  ${CI_PIN_RELEASE_CHECKSUMS_URL:-not recorded}"

	if [ -z "$(ci_sha512_tool)" ]; then
		ci_fail "no sha512 utility on PATH (need shasum or sha512sum); the publisher's digest cannot be checked, so the artifact is refused"
		return "$CI_FAIL"
	fi

	if [ -n "$_archive" ]; then
		if [ ! -f "$_archive" ]; then
			ci_fail "verify-engine: archive does not exist: $_archive"
			return "$CI_FAIL"
		fi
		ci_info "archive:     $_archive ($(wc -c <"$_archive" 2>/dev/null | tr -d ' ') bytes)"
		# The publisher publishes SHA-512, so compare with SHA-512: a re-derived
		# digest is not the publisher's expectation.
		ci_verify_digest "editor archive sha512" "$_archive" "$CI_PIN_RELEASE_SHA512" sha512 || _rc="$CI_FAIL"
		if [ -n "$CI_PIN_RELEASE_SHA256" ]; then
			ci_verify_digest "editor archive sha256" "$_archive" "$CI_PIN_RELEASE_SHA256" sha256 || _rc="$CI_FAIL"
		else
			ci_warn "editor archive sha256: not pinned; the publisher sha512 above is the authoritative check"
		fi
		if [ "$_rc" -eq 0 ]; then
			ci_ok "the archive may be extracted"
		else
			ci_fail "DO NOT extract or run this archive: it does not match the pinned digest"
		fi
	fi

	if [ -n "$_binary" ]; then
		if [ ! -f "$_binary" ]; then
			ci_fail "verify-engine: binary does not exist: $_binary"
			return "$CI_FAIL"
		fi
		ci_info "binary:      $_binary ($(wc -c <"$_binary" 2>/dev/null | tr -d ' ') bytes)"
		# A locally observed digest of the single member of the verified archive.
		# It is a second, cheap check that extraction produced the expected
		# binary; the publisher's sha512 of the archive is the authority.
		if [ -n "$CI_PIN_RELEASE_BINARY_SHA256" ]; then
			ci_verify_digest "editor binary sha256" "$_binary" "$CI_PIN_RELEASE_BINARY_SHA256" sha256 || _rc="$CI_FAIL"
		else
			ci_warn "editor binary sha256: not pinned; the archive sha512 is the authoritative check"
		fi
		if [ "$_rc" -eq 0 ]; then
			ci_ok "the binary may be executed"
		else
			ci_fail "DO NOT execute this binary: it does not match the pinned digest"
		fi
	fi

	ci_report "verify-engine result=$([ "$_rc" -eq 0 ] && printf pass || printf fail) archive=${_archive:-none} binary=${_binary:-none}"
	[ "$_rc" -eq 0 ] && ci_ok "verify-engine: PASS" || ci_fail "verify-engine: FAIL"
	return "$_rc"
}

# ---------------------------------------------------------------------------
# pin : print the pinned engine facts as key=value lines, so a workflow or a
# reviewer reads one source of truth instead of a second copy of the digests.
# ---------------------------------------------------------------------------
cmd_pin() {
	while [ $# -gt 0 ]; do
		case "$1" in
			--field)
				[ $# -ge 2 ] || ci_die "pin: --field needs a name"
				ci_pin_field "$2"
				return "$?"
				;;
			--field=*) ci_pin_field "${1#--field=}"; return "$?" ;;
			*) ci_die "pin: unknown option $1" ;;
		esac
	done
	printf 'source=%s\n' "$CI_PIN_SOURCE"
	printf 'tag=%s\n' "$CI_PIN_TAG"
	printf 'version=%s.%s.%s\n' "$CI_PIN_MAJOR" "$CI_PIN_MINOR" "$CI_PIN_PATCH"
	printf 'version_string=%s\n' "$CI_PIN_VERSION_STRING"
	printf 'upstream_verified=%s\n' "${CI_PIN_UPSTREAM_VERIFIED:-no}"
	printf 'release_archive_url=%s\n' "$CI_PIN_RELEASE_URL"
	printf 'release_checksums_url=%s\n' "$CI_PIN_RELEASE_CHECKSUMS_URL"
	printf 'release_archive_sha512=%s\n' "$CI_PIN_RELEASE_SHA512"
	printf 'release_archive_sha256=%s\n' "$CI_PIN_RELEASE_SHA256"
	printf 'release_binary_sha256=%s\n' "$CI_PIN_RELEASE_BINARY_SHA256"
	return "$CI_OK"
}

# ci_pin_field <name> : print one pinned fact. A digest field that is not
# recorded fails instead of printing an empty line, so a caller can never verify
# against nothing.
ci_pin_field() {
	_field="$1"
	_value=""
	_digest=0
	case "$_field" in
		source) _value="$CI_PIN_SOURCE" ;;
		tag) _value="$CI_PIN_TAG" ;;
		version) _value="${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}" ;;
		version_string) _value="$CI_PIN_VERSION_STRING" ;;
		upstream_verified) _value="${CI_PIN_UPSTREAM_VERIFIED:-no}" ;;
		release_archive_url) _value="$CI_PIN_RELEASE_URL" ;;
		release_checksums_url) _value="$CI_PIN_RELEASE_CHECKSUMS_URL" ;;
		release_archive_sha512) _value="$CI_PIN_RELEASE_SHA512"; _digest=1 ;;
		release_archive_sha256) _value="$CI_PIN_RELEASE_SHA256"; _digest=1 ;;
		release_binary_sha256) _value="$CI_PIN_RELEASE_BINARY_SHA256"; _digest=1 ;;
		*)
			ci_fail "pin: unknown field '$_field'"
			return "$CI_USAGE"
			;;
	esac
	if [ "$_digest" -eq 1 ] && [ -z "$_value" ]; then
		ci_fail "pin: field '$_field' is not recorded in $CI_PIN_SOURCE"
		return "$CI_FAIL"
	fi
	printf '%s\n' "$_value"
	return "$CI_OK"
}

# ---------------------------------------------------------------------------
# doctor
# ---------------------------------------------------------------------------
cmd_doctor() {
	_display=0
	while [ $# -gt 0 ]; do
		case "$1" in
			--display) _display=1 ;;
			*) ci_die "doctor: unknown option $1" ;;
		esac
		shift
	done

	ci_step "environment report"
	ci_info "project:        $CI_PROJECT"
	ci_info "tooling:        $CI_TOOLS_DIR"
	ci_info "output:         $CI_OUT (local scratch, gitignored)"
	ci_info "engine binary:  $GODOT_BIN"
	ci_info "engine version: $GODOT_VERSION_FULL"
	ci_info "engine sha256:  $(ci_sha256 "$GODOT_BIN")"
	ci_info "shell:          $0 (pid $$)"
	ci_info "os:             $(uname -s) $(uname -r) $(uname -m)"
	ci_info "cpu count:      $( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu 2>/dev/null || printf 'unknown')"
	ci_info "templates:      $(ci_templates_dir || printf 'not found')"

	_rc="$CI_OK"
	ci_check_engine_pin || _rc="$CI_FAIL"

	ci_prepared_copy || return "$CI_FAIL"

	ci_step "engine runtime report"
	if [ "$_display" -eq 1 ]; then
		ci_info "running with a real display driver (no --headless)"
		ci_run_godot env --path "$CI_PROJECT_COPY" --script "res://tools/ci/scripts/environment_report.gd"
	else
		ci_run_godot env --headless --path "$CI_PROJECT_COPY" --script "res://tools/ci/scripts/environment_report.gd"
	fi
	sed 's/^/    /' "$CI_LAST_LOG"
	if [ "$CI_LAST_EXIT" -ne 0 ]; then
		ci_fail "environment report exited $CI_LAST_EXIT"
		_rc="$CI_FAIL"
	fi
	ci_log_gate "$CI_LAST_LOG" || _rc="$CI_FAIL"

	if [ "$_display" -eq 0 ]; then
		ci_warn "headless report only: display/audio drivers are dummies and input devices cannot be enumerated. Re-run 'ci.sh doctor --display' on a machine with a display for the real GPU, renderer and controllers (PLAN.md M0.6)."
	fi

	ci_report "doctor engine=$GODOT_VERSION_FULL result=$([ "$_rc" -eq 0 ] && printf pass || printf fail)"
	[ "$_rc" -eq 0 ] && ci_ok "doctor: PASS" || ci_fail "doctor: FAIL"
	return "$_rc"
}

# ---------------------------------------------------------------------------
# import
# ---------------------------------------------------------------------------
cmd_import() {
	while [ $# -gt 0 ]; do
		case "$1" in
			--in-place) CI_IN_PLACE=1 ;;
			*) ci_die "import: unknown option $1" ;;
		esac
		shift
	done

	ci_prepared_copy || return "$CI_FAIL"
	_target="$CI_PROJECT_COPY"

	ci_step "import: headless resource import"
	ci_info "target: $_target"
	if [ "$_target" = "$CI_PROJECT" ]; then
		ci_warn "importing the project in place; this writes $CI_PROJECT/.godot/"
	fi
	ci_run_godot import --headless --path "$_target" --import
	if [ "$CI_LAST_EXIT" -ne 0 ]; then
		ci_fail "import exited $CI_LAST_EXIT"
		ci_log_error_lines "$CI_LAST_LOG" | sed 's/^/    /'
		ci_report "import result=fail exit=$CI_LAST_EXIT"
		return "$CI_FAIL"
	fi
	ci_log_gate "$CI_LAST_LOG" || {
		ci_report "import result=fail reason=engine-errors"
		return "$CI_FAIL"
	}
	[ -d "$_target/.godot" ] || {
		ci_fail "import produced no .godot/ cache in $_target"
		ci_report "import result=fail reason=no-cache"
		return "$CI_FAIL"
	}
	ci_ok "import: PASS (cache written to $_target/.godot, shared checkout untouched)"
	ci_report "import result=pass target=$_target"
	return "$CI_OK"
}

# ---------------------------------------------------------------------------
# validate
# ---------------------------------------------------------------------------
cmd_validate() {
	_rc="$CI_OK"

	ci_step "validate: engine pin"
	ci_check_engine_pin || _rc="$CI_FAIL"

	ci_prepared_copy || return "$CI_FAIL"

	ci_step "validate: project settings"
	ci_run_godot settings --headless --path "$CI_PROJECT_COPY" \
		--script "res://tools/ci/scripts/check_settings.gd" -- "${CI_PIN_MAJOR}.${CI_PIN_MINOR}"
	_settings_out="$(grep -E '^\[ci-settings\] (key=|summary)' "$CI_LAST_LOG" 2>/dev/null)"
	[ -n "$_settings_out" ] && printf '%s\n' "$_settings_out" | sed 's/^/    /'
	if [ "$CI_LAST_EXIT" -ne 0 ]; then
		ci_fail "project settings check failed (exit $CI_LAST_EXIT)"
		_rc="$CI_FAIL"
	else
		ci_ok "project settings check passed"
	fi
	ci_log_gate "$CI_LAST_LOG" || _rc="$CI_FAIL"

	ci_step "validate: resource and script scan"
	_scan_args=""
	[ -n "$CI_OUT_RES" ] && _scan_args="$CI_OUT_RES"
	ci_run_godot scan --headless --path "$CI_PROJECT_COPY" \
		--script "res://tools/ci/scripts/scan_project.gd" -- $_scan_args
	_scan_out="$(grep -E '^\[ci-scan\] (kind=|summary|RESULT)' "$CI_LAST_LOG" 2>/dev/null)"
	[ -n "$_scan_out" ] && printf '%s\n' "$_scan_out" | sed 's/^/    /'
	if [ "$CI_LAST_EXIT" -ne 0 ]; then
		ci_fail "resource/script scan failed (exit $CI_LAST_EXIT)"
		_rc="$CI_FAIL"
	else
		ci_ok "resource/script scan passed"
	fi
	ci_log_gate "$CI_LAST_LOG" || _rc="$CI_FAIL"

	# Every engine run above is also gated on its captured log (ci_log_gate): the
	# pinned engine exits 0 even when a script fails to compile or a resource is
	# missing, so the exit code alone would falsely pass.

	ci_step "validate: tooling self-check"
	ci_tooling_selfcheck || _rc="$CI_FAIL"

	ci_step "validate: tooling self-test"
	ci_tooling_selftest || _rc="$CI_FAIL"

	ci_step "validate: content-contract inventory"
	ci_contract_inventory || _rc="$CI_FAIL"

	ci_report "validate result=$([ "$_rc" -eq 0 ] && printf pass || printf fail)"
	[ "$_rc" -eq 0 ] && ci_ok "validate: PASS" || ci_fail "validate: FAIL"
	return "$_rc"
}

ci_tooling_selfcheck() {
	# Scoped result variable: a plain _rc here would clobber the caller's.
	_self_rc="$CI_OK"
	for _f in "$CI_TOOLS_DIR/ci.sh" "$CI_TOOLS_DIR/lib/common.sh"; do
		if [ -x "$_f" ]; then
			ci_ok "executable: $(ci_relpath "$_f")"
		else
			ci_fail "not executable: $(ci_relpath "$_f")"
			_self_rc="$CI_FAIL"
		fi
	done
	for _f in "$CI_TOOLS_DIR/scripts/"*.gd "$CI_TOOLS_DIR/pin/engine.txt" "$CI_TOOLS_DIR/contracts.list" \
		"$CI_TOOLS_DIR/tests/run_tests.sh"; do
		if [ -f "$_f" ]; then
			ci_ok "present: $(ci_relpath "$_f")"
		else
			ci_fail "missing tooling file: $(ci_relpath "$_f")"
			_self_rc="$CI_FAIL"
		fi
	done
	# The scratch output directory must never be committed.
	if [ -n "$CI_OUT_REL_PATH" ] && command -v git >/dev/null 2>&1 && [ -d "$CI_PROJECT/.git" ]; then
		_tracked="$(cd "$CI_PROJECT" && git ls-files "$CI_OUT_REL_PATH" 2>/dev/null | ci_count_lines)"
		if [ "$_tracked" = "0" ]; then
			ci_ok "no tracked files under $CI_OUT_REL_PATH"
		else
			ci_fail "$_tracked tracked file(s) under $CI_OUT_REL_PATH - build output must not be committed"
			_self_rc="$CI_FAIL"
		fi
	fi
	# The deliberate-failure probe must exist; test depends on it.
	[ -f "$CI_TOOLS_DIR/scripts/expect_failure_probe.gd" ] || _self_rc="$CI_FAIL"
	return "$_self_rc"
}

# ci_tooling_selftest : run the tooling's own hermetic self-test.
#
# `validate` proves the project is sound and `test` proves the engine checks
# fail correctly, but neither covers the tooling's own logic -- the pin parser,
# the digest comparison, the capture viewport override and the argument
# validation. Those are exactly where a silent no-op would let an unverified
# artifact through (M0.1) or report a capture at the wrong resolution as a
# success (M0.6). The suite is hermetic: no network, no engine, no display, no
# Git, and it runs from a private temporary directory.
ci_tooling_selftest() {
	_runner="$CI_TOOLS_DIR/tests/run_tests.sh"
	if [ ! -f "$_runner" ]; then
		ci_fail "missing tooling self-test: $(ci_relpath "$_runner")"
		return "$CI_FAIL"
	fi
	_out="$(PROJECT_DIR="$CI_PROJECT" TOOLS_CI_DIR="$CI_TOOLS_DIR" sh "$_runner" 2>&1)"
	_status=$?
	# Failures, notes and the summary line; the passing case lines stay in the
	# self-test's own output so `validate` remains readable.
	printf '%s\n' "$_out" | grep -E '^\[ci-selftest\] (.*-> no|summary|note|PASS|FAIL)' | sed 's/^/    /'
	if [ "$_status" -ne 0 ]; then
		ci_fail "tooling self-test exited $_status"
		ci_note "re-run directly for the full case list: sh tools/ci/tests/run_tests.sh"
		ci_report "tooling-selftest result=fail exit=$_status"
		return "$CI_FAIL"
	fi
	_summary="$(printf '%s\n' "$_out" | grep -E '^\[ci-selftest\] summary' | tail -n 1)"
	ci_ok "tooling self-test passed${_summary:+ ($_summary)}"
	ci_report "tooling-selftest result=pass"
	return "$CI_OK"
}

# Content-contract inventory. This is deliberately an inventory, not a
# validation: content validation (T09/T15) is not implemented and is not
# claimed here. Entries marked `required` in contracts.list must exist; entries
# marked `pending` are reported and only enforced with --strict-contracts.
ci_contract_inventory() {
	# NOTE: deliberately not named _rc; a caller's _rc must survive this call.
	_inv_rc="$CI_OK"
	_list="$CI_TOOLS_DIR/contracts.list"
	[ -f "$_list" ] || {
		ci_fail "missing contracts list: $_list"
		return "$CI_FAIL"
	}
	while IFS='|' read -r _status _path _milestone _note; do
		case "$_status" in
			''|\#*) continue ;;
		esac
		if [ -e "$CI_PROJECT/$_path" ]; then
			ci_ok "present:  $_path ($_milestone) - $_note"
		else
			case "$_status" in
				required)
					ci_fail "absent:   $_path ($_milestone) - $_note"
					_inv_rc="$CI_FAIL"
					;;
				pending)
					if [ "$CI_STRICT_CONTRACTS" -eq 1 ]; then
						ci_fail "absent (strict): $_path ($_milestone) - $_note"
						_inv_rc="$CI_FAIL"
					else
						ci_warn "absent:   $_path ($_milestone) - $_note"
					fi
					;;
				*)
					ci_note "optional absent: $_path ($_milestone) - $_note"
					;;
			esac
		fi
	done <"$_list"
	ci_note "inventory only: content validation (T09/T15) is NOT implemented and is not claimed by this check."
	ci_report "contracts result=$([ "$_inv_rc" -eq 0 ] && printf pass || printf fail) strict=$CI_STRICT_CONTRACTS"
	return "$_inv_rc"
}

# ---------------------------------------------------------------------------
# test
# ---------------------------------------------------------------------------
CI_TEST_LIST=""
CI_TEST_RUN=0
CI_TEST_PASS=0
CI_TEST_FAIL=0

cmd_test() {
	_list_only=0
	_require=0
	_filter=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--list) _list_only=1 ;;
			--require-tests) _require=1 ;;
			--filter)
				[ $# -ge 2 ] || ci_die "--filter needs a substring"
				_filter="$2"
				shift
				;;
			--filter=*) _filter="${1#--filter=}" ;;
			*) ci_die "test: unknown option $1" ;;
		esac
		shift
	done

	ci_prepared_copy || return "$CI_FAIL"
	ci_discover_tests "$_filter"

	if [ "$_list_only" -eq 1 ]; then
		ci_step "discovered headless checks"
		if [ -z "$CI_TEST_LIST" ]; then
			ci_warn "no test scripts discovered"
		else
			printf '%s\n' "$CI_TEST_LIST" | while IFS= read -r _t; do
				[ -n "$_t" ] && ci_note "$(ci_res_path "$_t")"
			done
		fi
		return "$CI_OK"
	fi

	if [ -z "$CI_TEST_LIST" ]; then
		if [ "$_require" -eq 1 ]; then
			ci_fail "no test scripts discovered and --require-tests was given"
			ci_report "test result=fail reason=no-tests"
			return "$CI_FAIL"
		fi
		ci_warn "no test scripts discovered under tests/ or tools/smoke/ (PLAN.md M0.4 is not satisfied by this run)"
	fi

	ci_step "running headless checks"
	while IFS= read -r _test; do
		[ -n "$_test" ] || continue
		ci_run_one_test "$_test"
	done <<EOF
$CI_TEST_LIST
EOF

	ci_step "exit-code proof (PLAN.md M0.4)"
	ci_exit_code_proof

	ci_report "test result=$([ "$CI_TEST_FAIL" -eq 0 ] && [ "$CI_TEST_RUN" -gt 0 ] && printf pass || printf fail) run=$CI_TEST_RUN pass=$CI_TEST_PASS fail=$CI_TEST_FAIL"
	if [ "$CI_TEST_FAIL" -gt 0 ]; then
		ci_fail "test: FAIL ($CI_TEST_FAIL of $CI_TEST_RUN check(s) failed)"
		return "$CI_FAIL"
	fi
	if [ "$CI_TEST_RUN" -eq 0 ]; then
		ci_warn "test: nothing was run"
		return "$CI_FAIL"
	fi
	ci_ok "test: PASS ($CI_TEST_RUN check(s))"
	return "$CI_OK"
}

ci_discover_tests() {
	_filter="$1"
	CI_TEST_LIST=""
	_list_file="$CI_OUT/test-list.txt"
	: >"$_list_file"
	for _root in "$CI_PROJECT/tests" "$CI_PROJECT/tools/smoke"; do
		[ -d "$_root" ] || continue
		find "$_root" -type f -name '*.gd' 2>/dev/null >>"$_list_file"
	done
	# Deterministic order; skip the tooling's own scratch directory.
	sort -u "$_list_file" 2>/dev/null | while IFS= read -r _f; do
		[ -n "$_f" ] || continue
		case "$_f" in
			"$CI_OUT"/*) continue ;;
		esac
		printf '%s\n' "$_f"
	done >"$_list_file.tmp" 2>/dev/null
	mv "$_list_file.tmp" "$_list_file" 2>/dev/null

	if [ -n "$_filter" ]; then
		grep -F "$_filter" "$_list_file" 2>/dev/null >"$_list_file.tmp" || : >"$_list_file.tmp"
		mv "$_list_file.tmp" "$_list_file" 2>/dev/null
	fi
	CI_TEST_LIST="$(cat "$_list_file" 2>/dev/null)"
}

ci_run_one_test() {
	_test="$1"
	_res="$(ci_res_path "$_test")"
	_runner="script"
	_timeout="$CI_TIMEOUT_DEFAULT"
	# Optional per-test directives in the first lines of the script:
	#   ## ci-runner: script|scene
	#   ## ci-timeout: 60
	_directives="$(head -n 30 "$_test" 2>/dev/null | grep -E '^##[[:space:]]*ci-(runner|timeout):' || true)"
	if [ -n "$_directives" ]; then
		_v="$(printf '%s\n' "$_directives" | grep 'ci-runner:' | head -n 1 | sed 's/.*ci-runner:[[:space:]]*//')"
		[ -n "$_v" ] && _runner="$_v"
		_v="$(printf '%s\n' "$_directives" | grep 'ci-timeout:' | head -n 1 | sed 's/.*ci-timeout:[[:space:]]*//')"
		case "$_v" in
			'' | *[!0-9]*) : ;;
			*) _timeout="$_v" ;;
		esac
	fi

	CI_TEST_RUN=$((CI_TEST_RUN + 1))
	ci_step "check: $_res (runner=$_runner)"
	CI_RUN_TIMEOUT="$_timeout"
	case "$_runner" in
		script)
			ci_run_godot "test$CI_TEST_RUN" --headless --path "$CI_PROJECT_COPY" --script "$_res"
			;;
		scene)
			ci_run_godot "test$CI_TEST_RUN" --headless --path "$CI_PROJECT_COPY" --scene "$_res"
			;;
		*)
			ci_fail "unknown ci-runner '$_runner' in $_res"
			CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
			return "$CI_FAIL"
			;;
	esac
	CI_RUN_TIMEOUT=""

	if [ "$CI_LAST_EXIT" -eq 0 ]; then
		ci_ok "PASS: $_res"
		CI_TEST_PASS=$((CI_TEST_PASS + 1))
		ci_report "check=$_res result=pass"
	else
		ci_fail "FAIL: $_res exited $CI_LAST_EXIT"
		grep -E '^(ERROR|SCRIPT ERROR|FATAL):' "$CI_LAST_LOG" 2>/dev/null | tail -n 20 | sed 's/^/    /'
		CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
		ci_report "check=$_res result=fail exit=$CI_LAST_EXIT"
	fi
	_errs="$(ci_log_error_count "$CI_LAST_LOG")"
	[ "$_errs" != "0" ] && ci_warn "$_errs engine error line(s) in the log for $_res (informational)"
	return "$CI_OK"
}

ci_exit_code_proof() {
	_probe="$CI_TOOLS_DIR/scripts/expect_failure_probe.gd"
	if [ ! -f "$_probe" ]; then
		ci_fail "exit-code proof: missing probe $_probe"
		CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
		return "$CI_FAIL"
	fi
	ci_run_godot exitproof --headless --path "$CI_PROJECT_COPY" --script "$(ci_res_path "$_probe")"
	if [ "$CI_LAST_EXIT" -ne 0 ]; then
		ci_ok "exit-code proof: a deliberately failing check exited $CI_LAST_EXIT (nonzero)"
	else
		ci_fail "exit-code proof: the deliberately failing probe exited 0 - failures would be reported as passes"
		CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
	fi

	# The existing smoke runner also documents its own --expect-failure flag;
	# exercise it too, but only when it still advertises the flag.
	_smoke="$CI_PROJECT/tools/smoke/boot_smoke.gd"
	if [ -f "$_smoke" ] && grep -q -- '--expect-failure' "$_smoke" 2>/dev/null; then
		ci_run_godot exitproof-smoke --headless --path "$CI_PROJECT_COPY" \
			--script "$(ci_res_path "$_smoke")" -- --expect-failure
		if [ "$CI_LAST_EXIT" -ne 0 ]; then
			ci_ok "exit-code proof: tools/smoke/boot_smoke.gd --expect-failure exited $CI_LAST_EXIT"
		else
			ci_fail "exit-code proof: tools/smoke/boot_smoke.gd --expect-failure exited 0"
			CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
		fi
	else
		ci_note "exit-code proof: tools/smoke/boot_smoke.gd does not advertise --expect-failure; using the tooling probe only"
	fi
	return "$CI_OK"
}

# ---------------------------------------------------------------------------
# capture
# ---------------------------------------------------------------------------
cmd_capture() {
	_sub="${1:-}"
	[ -n "$_sub" ] && shift
	case "$_sub" in
		--check | check) ci_capture_check "$@" ;;
		--list | list) ci_capture_list "$@" ;;
		--probe | probe) ci_capture_probe "$@" ;;
		--target) ci_capture_run "$_sub" "$@" ;;
		'') ci_die "capture: no mode given. Use --check, --list, --probe or --target <res://path> (see --help)." ;;
		*) ci_die "capture: unknown mode '$_sub'" ;;
	esac
}

ci_capture_display_ok() {
	case "$(uname -s 2>/dev/null)" in
		Darwin) return 0 ;;
		*)
			if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
				return 0
			fi
			return 1
			;;
	esac
}

ci_capture_check() {
	_rc="$CI_OK"
	ci_step "capture readiness"
	ci_check_engine_pin || _rc="$CI_FAIL"
	if ci_capture_display_ok; then
		ci_ok "display: available ($(uname -s))"
	else
		ci_note "display: unavailable on this host (no DISPLAY/WAYLAND_DISPLAY); movie capture cannot run here. Run 'ci.sh capture --probe' on a desktop session or under xvfb."
	fi
	# The resolution a capture will actually record, and whether it can be
	# checked. Recorded here because a requested resolution that the engine
	# silently ignores is exactly the failure mode M0.6's inventory reported.
	_cfg="$CI_PROJECT/project.godot"
	_vp="$(ci_project_viewport_size "$_cfg" 2>/dev/null || true)"
	if [ -n "$_vp" ]; then
		ci_ok "project viewport: $_vp (a capture records the project viewport size, not the window size; '--resolution' requests a window size)"
	else
		ci_warn "project viewport: cannot read display/window/size/viewport_width|height from $(ci_relpath "$_cfg")"
	fi
	if command -v ffprobe >/dev/null 2>&1; then
		ci_ok "ffprobe: available (the recorded resolution is verified after every capture)"
	else
		ci_warn "ffprobe: not found; a capture's recorded resolution cannot be verified and will be reported as unverified"
	fi
	_targets="$(ci_capture_targets)"
	if [ -z "$_targets" ]; then
		ci_note "capture stages: none authored yet (PLAN.md M2.6/M5.5). 'capture' still works against any scene you name with --target."
	else
		ci_ok "capture stages: $(printf '%s\n' "$_targets" | grep -c .) scene(s) under res://scenes/"
		printf '%s\n' "$_targets" | sed 's/^/    /'
	fi
	ci_note "AVI output via --write-movie is verified with the pinned engine on macOS. PNG sequence output was not reproduced and is intentionally not offered."
	ci_report "capture-check result=$([ "$_rc" -eq 0 ] && printf pass || printf fail)"
	return "$_rc"
}

ci_capture_list() {
	ci_step "scenes available as capture targets"
	_targets="$(ci_capture_targets)"
	if [ -z "$_targets" ]; then
		ci_warn "no scenes under res://scenes/ in $CI_PROJECT"
		return "$CI_OK"
	fi
	printf '%s\n' "$_targets"
	return "$CI_OK"
}

ci_capture_targets() {
	_dir="$CI_PROJECT/scenes"
	[ -d "$_dir" ] || return 0
	find "$_dir" -type f -name '*.tscn' 2>/dev/null | sort | while IFS= read -r _f; do
		printf 'res://%s\n' "${_f#$CI_PROJECT/}"
	done
}

ci_capture_probe() {
	_frames="${CAPTURE_FRAMES:-6}"
	_fps="${CAPTURE_FPS:-30}"
	_resolution="${CAPTURE_RESOLUTION:-640x360}"
	_target="${1:-}"
	if [ -z "$_target" ]; then
		_target="$(ci_capture_targets | head -n 1)"
	fi
	[ -n "$_target" ] || ci_die "capture --probe: no scene to capture (nothing under res://scenes/ and no --target given)"
	ci_capture_run --target "$_target" --frames "$_frames" --fps "$_fps" --resolution "$_resolution" --name probe
}

ci_capture_run() {
	# Accept both `capture --target X --frames N` and `capture --target=X`.
	_target=""
	_frames=60
	_fps=30
	_resolution="960x540"
	_name=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--target)
				[ $# -ge 2 ] || ci_die "capture: --target needs a res:// path"
				_target="$2"
				shift 2
				;;
			--target=*) _target="${1#--target=}"; shift ;;
			--frames)
				[ $# -ge 2 ] || ci_die "capture: --frames needs a number"
				_frames="$2"
				shift 2
				;;
			--frames=*) _frames="${1#--frames=}"; shift ;;
			--fps)
				[ $# -ge 2 ] || ci_die "capture: --fps needs a number"
				_fps="$2"
				shift 2
				;;
			--fps=*) _fps="${1#--fps=}"; shift ;;
			--resolution)
				[ $# -ge 2 ] || ci_die "capture: --resolution needs WxH"
				_resolution="$2"
				shift 2
				;;
			--resolution=*) _resolution="${1#--resolution=}"; shift ;;
			--name)
				[ $# -ge 2 ] || ci_die "capture: --name needs a value"
				_name="$2"
				shift 2
				;;
			--name=*) _name="${1#--name=}"; shift ;;
			*) ci_die "capture: unknown option $1" ;;
		esac
	done

	[ -n "$_target" ] || ci_die "capture: --target <res://path> is required"
	case "$_frames" in
		'' | *[!0-9]*) ci_die "capture: --frames must be a positive integer" ;;
	esac
	case "$_fps" in
		'' | *[!0-9]*) ci_die "capture: --fps must be a positive integer" ;;
	esac
	# A zero frame count would pass `--quit-after 0`, which tells Godot never to
	# quit: the run would only end when the wall-clock watchdog killed it.
	ci_is_positive_int "$_frames" || ci_die "capture: --frames must be greater than 0 (a 0 would disable --quit-after and run unbounded)"
	ci_is_positive_int "$_fps" || ci_die "capture: --fps must be greater than 0"
	ci_is_wxh "$_resolution" || ci_die "capture: --resolution must be <width>x<height> with positive integers, e.g. 960x540 (got '$_resolution')"

	ci_prepared_copy || return "$CI_FAIL"
	_res="$_target"
	case "$_target" in
		res://*) : ;;
		*) _res="$(ci_res_path "$_target")" ;;
	esac
	# The target must exist in the scratch copy, which mirrors the project.
	case "$_res" in
		res://*) _res_file="$CI_PROJECT_COPY/${_res#res://}" ;;
		*) _res_file="$_res" ;;
	esac
	if [ ! -e "$_res_file" ]; then
		ci_fail "capture target does not exist: $_res"
		ci_note "list scenes with 'ci.sh capture --list'. No capture stage is authored yet (PLAN.md M2.6/M5.5), so name an existing scene such as res://scenes/game.tscn."
		return "$CI_FAIL"
	fi
	# Scenes run with --scene; a script-driven capture stage runs with --script.
	case "$_res" in
		*.gd) _run_flag="--script" ;;
		*) _run_flag="--scene" ;;
	esac

	ci_capture_display_ok || {
		ci_fail "capture: no display available on this host; movie capture needs a rendering display driver"
		return "$CI_FAIL"
	}

	_stamp="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date -u +%s)"
	[ -n "$_name" ] || _name="$(printf '%s' "$_res" | sed 's|.*/||; s|\.tscn$||; s|\.gd$||')"
	mkdir -p "$CI_OUT/captures" 2>/dev/null || ci_die "cannot create $CI_OUT/captures"
	_out="$CI_OUT/captures/${_name}-${_stamp}.avi"

	ci_step "capture: $_res -> $(ci_relpath "$_out")"
	ci_info "frames=$_frames fps=$_fps requested resolution=$_resolution (deterministic: --fixed-fps)"

	# --- Requested resolution vs what the engine will actually record ---------
	# Measured against the pinned engine: Godot's movie writer records the
	# PROJECT VIEWPORT size, while `--resolution` only requests a window size.
	# A capture that silently records 1920x1080 when 960x540 was asked for breaks
	# the BENCHMARKS "four 960x540 panels" convention and M2.6/M5 capture
	# planning, so the viewport is set in the SCRATCH COPY (never the shared
	# checkout) and the recorded size is probed afterwards and must match.
	_scratch_cfg="$CI_PROJECT_COPY/project.godot"
	_project_vp="$(ci_project_viewport_size "$_scratch_cfg" 2>/dev/null || true)"
	ci_info "project viewport: ${_project_vp:-unknown} ($(ci_relpath "$_scratch_cfg") in the scratch copy)"
	if [ -z "$_project_vp" ]; then
		ci_warn "capture: cannot read the scratch project's viewport size; the requested resolution may not be honoured"
	elif [ "$_project_vp" != "$_resolution" ]; then
		_w="${_resolution%%x*}"
		_h="${_resolution##*x}"
		if ci_set_project_viewport_size "$_scratch_cfg" "$_w" "$_h"; then
			ci_info "viewport override applied to the scratch copy: $_project_vp -> $_resolution"
		else
			ci_fail "capture: cannot apply the requested viewport size to $(ci_relpath "$_scratch_cfg") (no viewport_width/viewport_height keys?)"
			ci_note "the shared checkout's project.godot was not modified"
			return "$CI_FAIL"
		fi
	fi
	# --write-movie forces --fixed-fps; --quit-after bounds the run.
	ci_run_godot capture --path "$CI_PROJECT_COPY" "$_run_flag" "$_res" \
		--write-movie "$_out" --fixed-fps "$_fps" --quit-after "$_frames" \
		--resolution "$_resolution"
	if [ "$CI_LAST_EXIT" -ne 0 ]; then
		ci_fail "capture exited $CI_LAST_EXIT"
		ci_log_error_lines "$CI_LAST_LOG" | sed 's/^/    /'
		return "$CI_FAIL"
	fi
	ci_log_gate "$CI_LAST_LOG" || return "$CI_FAIL"
	if [ ! -s "$_out" ]; then
		ci_fail "capture produced no output file: $_out"
		return "$CI_FAIL"
	fi
	_size="$(wc -c <"$_out" 2>/dev/null | tr -d ' ')"

	# What was ACTUALLY recorded, not what was requested. Without ffprobe the
	# size is reported as unverified rather than assumed correct.
	_recorded="$(ci_probe_video_size "$_out" 2>/dev/null || true)"
	if [ -z "$_recorded" ]; then
		ci_warn "recorded resolution could not be verified (ffprobe unavailable or no video stream); requested $_resolution"
		ci_report "capture result=pass target=$_res output=$_out bytes=$_size requested=$_resolution recorded=unverified"
		ci_ok "capture: PASS ($_size bytes at $(ci_relpath "$_out"), recorded resolution unverified)"
		grep -E 'frames at|recorded in' "$CI_LAST_LOG" 2>/dev/null | sed 's/^/    /'
		return "$CI_OK"
	fi
	if [ "$_recorded" != "$_resolution" ]; then
		ci_fail "capture recorded $_recorded but $_resolution was requested"
		ci_note "Godot's movie writer uses the project viewport size; '--resolution' only requests a window size."
		ci_note "This tooling sets the scratch copy's viewport before recording. If it still disagrees, the engine's"
		ci_note "movie-writer behaviour changed: record the finding instead of shipping a mis-sized capture."
		ci_report "capture result=fail reason=recorded-resolution target=$_res requested=$_resolution recorded=$_recorded output=$_out"
		return "$CI_FAIL"
	fi

	ci_ok "capture: PASS ($_size bytes at $(ci_relpath "$_out"), recorded $_recorded as requested)"
	grep -E 'frames at|recorded in' "$CI_LAST_LOG" 2>/dev/null | sed 's/^/    /'
	ci_report "capture result=pass target=$_res output=$_out bytes=$_size requested=$_resolution recorded=$_recorded"
	return "$CI_OK"
}

# ---------------------------------------------------------------------------
# export
# ---------------------------------------------------------------------------
# Required native targets from docs/TECHNICAL_DESIGN.md ("Packaging and
# operations"): macOS Apple Silicon, Windows x86-64, Linux x86-64.
CI_EXPORT_PLATFORMS="macOS Windows Linux"

cmd_export() {
	_sub="${1:-}"
	[ -n "$_sub" ] && shift
	_mode="release"
	while [ $# -gt 0 ]; do
		case "$1" in
			--mode)
				[ $# -ge 2 ] || ci_die "export: --mode needs debug or release"
				_mode="$2"
				shift 2
				;;
			--mode=*) _mode="${1#--mode=}"; shift ;;
			*) break ;;
		esac
	done
	case "$_mode" in
		debug | release) : ;;
		*) ci_die "export: --mode must be debug or release (got '$_mode')" ;;
	esac

	case "$_sub" in
		--check | check) ci_export_check "$_mode" ;;
		--list-presets | list-presets) ci_export_list "$@" ;;
		--export | export) ci_export_build "$_mode" "$@" ;;
		'') ci_die "export: no mode given. Use --check, --list-presets or --export <preset> --out <file> (see --help)." ;;
		*) ci_die "export: unknown mode '$_sub'" ;;
	esac
}

ci_export_check() {
	_mode="$1"
	_rc="$CI_OK"
	ci_step "export preparation (mode=$_mode)"
	ci_check_engine_pin || _rc="$CI_FAIL"

	_tdir="$(ci_templates_dir || true)"
	if [ -z "$_tdir" ]; then
		ci_fail "export templates: no template directory found (set GODOT_TEMPLATES_DIR)"
		_rc="$CI_FAIL"
	else
		_tver="${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}.stable"
		for _platform in $CI_EXPORT_PLATFORMS; do
			# Template file names as shipped in the pinned release
			# (export_templates/<version>/ from the official archive).
			case "$_platform" in
				macOS) _files="macos.zip" ;;
				Windows) _files="windows_${_mode}_x86_64.exe windows_${_mode}_x86_32.exe" ;;
				Linux) _files="linux_${_mode}.x86_64 linux_${_mode}.x86_32" ;;
				*) _files="" ;;
			esac
			_found=""
			for _f in $_files; do
				if [ -f "$_tdir/$_tver/$_f" ]; then
					_found="$_found $_f"
				fi
			done
			if [ -n "$_found" ]; then
				ci_ok "templates: $_platform ->$_found"
			else
				ci_fail "templates: $_platform -> none of [$_files] in $_tdir/$_tver"
				_rc="$CI_FAIL"
			fi
		done
	fi

	_cfg="$CI_PROJECT/export_presets.cfg"
	if [ ! -f "$_cfg" ]; then
		ci_fail "export presets: no export_presets.cfg at the project root"
		ci_note "Native export preparation is not implemented yet (PLAN.md M0.5/M9.1)."
		ci_note "Add export_presets.cfg through the editor's Project > Export dialog (or hand-author it),"
		ci_note "then re-run 'ci.sh export --check'. Until then, no export is claimed to work."
		_rc="$CI_FAIL"
	else
		_presets="$(ci_preset_table "$_cfg")"
		if [ -z "$_presets" ]; then
			ci_fail "export presets: export_presets.cfg has no [preset.N] sections"
			_rc="$CI_FAIL"
		else
			ci_ok "export presets: $(printf '%s\n' "$_presets" | grep -c .) preset(s) declared"
			printf '%s\n' "$_presets" | sed 's/^/    /'
			for _platform in $CI_EXPORT_PLATFORMS; do
				if printf '%s\n' "$_presets" | cut -f3 | grep -qx "$_platform"; then
					ci_ok "preset platform covered: $_platform"
				else
					ci_fail "preset platform missing: $_platform"
					_rc="$CI_FAIL"
				fi
			done
		fi
	fi

	ci_note "A successful export is not a verified release package: PLAN.md M9.2 still requires launching it on each target OS."
	ci_report "export-check mode=$_mode result=$([ "$_rc" -eq 0 ] && printf pass || printf fail)"
	[ "$_rc" -eq 0 ] && ci_ok "export preparation: PASS" || ci_fail "export preparation: FAIL"
	return "$_rc"
}

ci_export_list() {
	_cfg="$CI_PROJECT/export_presets.cfg"
	[ -f "$_cfg" ] || ci_die "no export_presets.cfg at $CI_PROJECT"
	_presets="$(ci_preset_table "$_cfg")"
	[ -n "$_presets" ] || ci_die "export_presets.cfg has no [preset.N] sections"
	case "${1:-}" in
		--format | names) printf '%s\n' "$_presets" | cut -f2 ;;
		*) printf '%s\n' "$_presets" ;;
	esac
}

ci_preset_table() {
	_cfg="$1"
	awk '
		/^\[/ {
			if (inpreset) printf "%s\t%s\t%s\n", idx, name, platform
			inpreset = ($0 ~ /^\[preset\.[0-9]+\]$/)
			idx = ""; name = ""; platform = ""
			if (inpreset) { idx = $0; sub(/^\[/, "", idx); sub(/\]$/, "", idx) }
			next
		}
		inpreset && /^name=/ { v = $0; sub(/^name="/, "", v); sub(/"$/, "", v); name = v }
		inpreset && /^platform=/ { v = $0; sub(/^platform="/, "", v); sub(/"$/, "", v); platform = v }
		END { if (inpreset) printf "%s\t%s\t%s\n", idx, name, platform }
	' "$_cfg" 2>/dev/null
}

ci_export_build() {
	_mode="$1"
	shift
	_preset=""
	_out=""
	# `export --export <preset> --out <file>` and `export --export --preset <name>`
	# are both accepted.
	if [ $# -gt 0 ]; then
		case "$1" in
			--*) : ;;
			*) _preset="$1"; shift ;;
		esac
	fi
	while [ $# -gt 0 ]; do
		case "$1" in
			--preset)
				[ $# -ge 2 ] || ci_die "export --export: --preset needs a name"
				_preset="$2"
				shift 2
				;;
			--preset=*) _preset="${1#--preset=}"; shift ;;
			--out)
				[ $# -ge 2 ] || ci_die "export --export: --out needs a file path"
				_out="$2"
				shift 2
				;;
			--out=*) _out="${1#--out=}"; shift ;;
			*) ci_die "export --export: unknown option $1" ;;
		esac
	done
	[ -n "$_preset" ] || ci_die "export --export: --preset <name> is required"
	[ -n "$_out" ] || ci_die "export --export: --out <file> is required (the correct extension depends on the preset platform)"

	_cfg="$CI_PROJECT/export_presets.cfg"
	[ -f "$_cfg" ] || {
		ci_fail "export --export: no export_presets.cfg at the project root; native export preparation is not implemented yet (PLAN.md M0.5/M9.1)"
		return "$CI_FAIL"
	}
	if ! ci_export_list names | grep -qx "$_preset"; then
		ci_fail "export --export: preset '$_preset' is not declared in export_presets.cfg"
		ci_note "declared presets: $(ci_export_list names | tr '\n' ' ')"
		return "$CI_FAIL"
	fi

	ci_prepared_copy || return "$CI_FAIL"
	mkdir -p "$(dirname "$_out")" 2>/dev/null || ci_die "cannot create output directory for $_out"
	_flag="--export-release"
	[ "$_mode" = "debug" ] && _flag="--export-debug"
	ci_step "export: preset '$_preset' ($_mode) -> $_out"
	ci_run_godot export --headless --path "$CI_PROJECT_COPY" "$_flag" "$_preset" "$_out"
	if [ "$CI_LAST_EXIT" -ne 0 ]; then
		ci_fail "export exited $CI_LAST_EXIT"
		ci_log_error_lines "$CI_LAST_LOG" | sed 's/^/    /'
		ci_report "export result=fail preset=$_preset exit=$CI_LAST_EXIT"
		return "$CI_FAIL"
	fi
	ci_log_gate "$CI_LAST_LOG" || {
		ci_report "export result=fail preset=$_preset reason=engine-errors"
		return "$CI_FAIL"
	}
	if [ ! -s "$_out" ]; then
		ci_fail "export produced no output: $_out"
		ci_report "export result=fail preset=$_preset reason=no-output"
		return "$CI_FAIL"
	fi
	_size="$(wc -c <"$_out" 2>/dev/null | tr -d ' ')"
	ci_ok "export: PASS ($_size bytes at $_out, sha256 $(ci_sha256 "$_out"))"
	ci_note "This is a locally built package, not a verified release: launching it on the target OS (PLAN.md M9.2) and signing/notarization (M9.3) are separate steps."
	ci_report "export result=pass preset=$_preset mode=$_mode output=$_out bytes=$_size sha256=$(ci_sha256 "$_out")"
	return "$CI_OK"
}

# ---------------------------------------------------------------------------
# all
# ---------------------------------------------------------------------------
cmd_all() {
	_rc="$CI_OK"
	# One shared scratch copy for the whole check set.
	ci_prepared_copy || return "$CI_FAIL"
	CI_REUSE_COPY=1

	cmd_import || _rc="$CI_FAIL"
	cmd_validate || _rc="$CI_FAIL"
	cmd_test || _rc="$CI_FAIL"

	ci_prune_logs
	ci_report "all result=$([ "$_rc" -eq 0 ] && printf pass || printf fail)"
	[ "$_rc" -eq 0 ] && ci_ok "all: PASS" || ci_fail "all: FAIL"
	return "$_rc"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$CI_COMMAND" in
	doctor) cmd_doctor "$@" ;;
	import) cmd_import "$@" ;;
	validate) cmd_validate "$@" ;;
	test) cmd_test "$@" ;;
	capture) cmd_capture "$@" ;;
	export) cmd_export "$@" ;;
	verify-engine) cmd_verify_engine "$@" ;;
	pin) cmd_pin "$@" ;;
	all) cmd_all "$@" ;;
	version)
		printf 'pinned: %s.%s.%s (%s)\n' "$CI_PIN_MAJOR" "$CI_PIN_MINOR" "$CI_PIN_PATCH" "$CI_PIN_TAG"
		printf 'found:  %s (%s)\n' "$GODOT_VERSION_FULL" "$GODOT_BIN"
		;;
	*)
		ci_die "unknown command: $CI_COMMAND (see --help)"
		;;
esac
_rc=$?

ci_prune_logs
# The report location is diagnostic metadata, not command output: `pin`,
# `capture --list` and `export --list-presets` print data on stdout that a
# caller may pipe, so this goes to stderr.
[ -n "$CI_REPORT" ] && ci_info "report: $CI_REPORT" >&2
exit "$_rc"
