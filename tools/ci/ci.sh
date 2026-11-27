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
#   install-templates      verify the export-template archive, then install its
#                          templates/<version> payload where the engine reads it;
#                          refuses an existing installed tree instead of deleting
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
# Exposed so a bounded test shim can signal the exact ci.sh process; it is
# informational and never used to infer lock ownership.
ROADSTORM_CI_PID="$$"
export ROADSTORM_CI_PID

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
# Warning policy: 0 = engine WARNING lines are surfaced and counted but do not
# fail a check (default); 1 = any WARNING line fails (--strict-warnings).
CI_STRICT_WARNINGS=0

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
  --strict-contracts  Treat `pending` content-contract entries as failures
  --strict-warnings   Fail a check when the engine log contains a WARNING line
                      that is not listed in tools/ci/warnings.allow (default:
                      warnings are surfaced and counted, not fatal)
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
                          Every check is judged on its exit status AND on its
                          captured engine log: a runtime error that leaves the
                          engine running (exit 0) fails the check, exactly as
                          tools/smoke/run_boot_smoke.sh does.
  capture --check | --list | --probe | --target <res://path>
                          Deterministic movie capture (AVI) driver. The requested
                          resolution is applied to the scratch copy's viewport
                          and the recorded size is verified afterwards.
  export --check | --list-presets | --export <preset> --out <file>
                          Export preparation and optional native export. --check
                          verifies the export templates where the ENGINE reads
                          them (its own user-data directory), for the
                          architecture each preset declares, plus preset
                          coverage.
  verify-engine --archive <file> [--binary <file>]
                          Compare a downloaded release archive (and optionally
                          the extracted editor binary) against the pinned
                          publisher digest in tools/ci/pin/engine.txt. Fails
                          before anything is extracted or executed (M0.1).
                          Resolves no engine, so it runs on a host with none.
  verify-templates --archive <file> [--dir <dir>] [--mode release|debug]
                          Compare the downloaded export-template archive against
                          the pinned publisher digest BEFORE it is extracted,
                          and/or verify an installed template tree
                          (<dir>/<version>.stable: version.txt and the
                          templates this project's presets require, non-empty).
                          Resolves no engine. (M0.1, Opus recheck E1.)
  install-templates --archive <file> --dest <dir> [--mode release|debug]
                          Verify the archive against the pinned publisher digest
                          BEFORE extraction, then install the archive's template
                          payload at <dest>/<version>.stable. Godot's official
                          .tpz packages templates/* at the archive root (there is
                          no <version>.stable directory inside it), so the
                          payload is located by its version.txt and that version
                          is validated before anything is moved into <dest>.
                          The staged tree must satisfy this project's presets.
                          An existing <dest>/<version>.stable is REFUSED, never
                          replaced (remove it explicitly to reinstall).
                          Resolves no engine. (M0.1; coordinator follow-up.)
  pin [--field <name>]    Print the pinned engine facts (tag, version, official
                          URLs and digests) as key=value lines.
  all                     import + validate + test (the CI check set).

Environment:
  GODOT_BIN, ROADSTORM_SOURCE_SHA, NO_COLOR, CI_TIMEOUT_DEFAULT, CI_STRICT_WARNINGS
  GODOT_TEMPLATES_DIR is reported but NOT used to pass the export check: the
  engine reads templates from its own user-data directory (measured, see
  lib/common.sh ci_templates_engine_dir), so a check that honoured the variable
  could pass a tree whose export then fails.

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
verify-templates  verify the export-template archive / an installed template tree
install-templates  verify the archive, then install it where the engine reads it
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
		--strict-warnings)
			CI_STRICT_WARNINGS=1
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
# Early export-namespace guard
#
# ci_find_godot below runs "$GODOT_BIN" --version before the command is
# dispatched, so a destination inside the reserved .ci-lock namespace must be
# rejected BEFORE this point. The later canonical guards in ci_export_build
# and ci_export_build_inner stay in place as the authority for everything that
# runs under the destination locks; this pass only stops an invalid request
# from ever touching the engine, a lock file, the scratch copy or the output.
# ---------------------------------------------------------------------------

# ci_export_path_in_lock_namespace <path> : true when <path>, case-insensitively,
# ends in the reserved .ci-lock suffix.
ci_export_path_in_lock_namespace() {
	case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
	*.ci-lock) return 0 ;;
	esac
	return 1
}

# ci_export_sidecar_for_out <main-output> : print the sidecar .pck path derived
# from the output BASENAME, so a dot in a directory component cannot move it.
ci_export_sidecar_for_out() {
	_cso_out="$1"
	case "$_cso_out" in
	*/*) _cso_dir="${_cso_out%/*}"; _cso_base="${_cso_out##*/}" ;;
	*) _cso_dir="."; _cso_base="$_cso_out" ;;
	esac
	case "$_cso_base" in
	*.*) _cso_base="${_cso_base%.*}" ;;
	esac
	printf '%s/%s.pck\n' "$_cso_dir" "$_cso_base"
}

# _ci_early_export_request <command> [args...] : print three lines
# (<out>, <preset>, <mode>) for a package-building request, or nothing when the
# invocation cannot be recognised as one. Anything unusual returns nothing and
# is left to the real parsers, which fail in their own way.
_ci_early_export_request() {
	_eer_cmd="$1"
	shift
	case "$_eer_cmd" in
	export)
		_eer_mode="release"
		while [ $# -gt 0 ]; do
			case "$1" in
			--mode) [ $# -ge 2 ] || return 0; _eer_mode="$2"; shift 2 ;;
			--mode=*) _eer_mode="${1#--mode=}"; shift ;;
			--export | export) shift; break ;;
			--check | check | --list-presets | list-presets) return 0 ;;
			*) return 0 ;;
			esac
		done
		_eer_preset=""
		_eer_out=""
		while [ $# -gt 0 ]; do
			case "$1" in
			--preset) [ $# -ge 2 ] || break; _eer_preset="$2"; shift 2 ;;
			--preset=*) _eer_preset="${1#--preset=}"; shift ;;
			--out) [ $# -ge 2 ] || break; _eer_out="$2"; shift 2 ;;
			--out=*) _eer_out="${1#--out=}"; shift ;;
			--) shift; break ;;
			-*) break ;;
			*) [ -z "$_eer_preset" ] && _eer_preset="$1"; shift ;;
			esac
		done
		[ -n "$_eer_out" ] || return 0
		printf '%s\n%s\n%s\n' "$_eer_out" "$_eer_preset" "$_eer_mode"
		;;
	__export-inner)
		[ $# -ge 3 ] || return 0
		[ -n "$3" ] || return 0
		printf '%s\n%s\n%s\n' "$3" "$1" "$2"
		;;
	esac
	return 0
}

# ci_early_namespace_guard <command> [args...] : reject a build destination in
# the .ci-lock namespace before any Godot invocation. Returns CI_OK when the
# request is clear (or is not a build), CI_FAIL with a structured report line
# when it is refused. On refusal it creates only logs/reports evidence: no
# lock file, scratch copy or package output is touched.
ci_early_namespace_guard() {
	_eng_req="$(_ci_early_export_request "$@" 2>/dev/null)" || return "$CI_OK"
	[ -n "$_eng_req" ] || return "$CI_OK"
	_eng_out_raw="$(printf '%s\n' "$_eng_req" | sed -n '1p')"
	_eng_preset="$(printf '%s\n' "$_eng_req" | sed -n '2p')"
	_eng_mode="$(printf '%s\n' "$_eng_req" | sed -n '3p')"
	case "$_eng_out_raw" in
	/*) : ;;
	*) _eng_out_raw="${PWD:-$(pwd)}/$_eng_out_raw" ;;
	esac
	_eng_out="$(ci_abs_path "$_eng_out_raw" 2>/dev/null)" || return "$CI_OK"
	_eng_pck="$(ci_export_sidecar_for_out "$_eng_out")"
	if ci_export_path_in_lock_namespace "$_eng_out"; then
		ci_init_logs
		ci_init_report
		ci_fail "export: destination is inside the reserved .ci-lock lock namespace: $_eng_out (choose another output name)"
		ci_report "export result=fail preset=$_eng_preset mode=$_eng_mode reason=lock-namespace output=$_eng_out"
		ci_info "report: $CI_REPORT" >&2
		return "$CI_FAIL"
	fi
	if ci_export_path_in_lock_namespace "$_eng_pck"; then
		ci_init_logs
		ci_init_report
		ci_fail "export: sidecar destination is inside the reserved .ci-lock lock namespace: $_eng_pck (choose another output name)"
		ci_report "export result=fail preset=$_eng_preset mode=$_eng_mode reason=lock-namespace output=$_eng_out"
		ci_info "report: $CI_REPORT" >&2
		return "$CI_FAIL"
	fi
	return "$CI_OK"
}

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

# Refuse a reserved .ci-lock destination before the engine version probe. This
# must run before ci_find_godot, which invokes the engine.
ci_early_namespace_guard "$CI_COMMAND" "$@" || exit "$?"

# Engine discovery is lazy. `verify-engine` and `pin` only read pinned data and
# hash local files, so they must work on a host with no Godot installed at all --
# exactly the state of a clean CI runner before the pinned editor has been
# downloaded and verified. Resolving the engine eagerly would make those
# commands unusable at the point they are needed.
CI_NEEDS_GODOT=1
case "$CI_COMMAND" in
	verify-engine | verify-templates | install-templates | pin) CI_NEEDS_GODOT=0 ;;
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
# verify-templates : verify the export-template archive BEFORE extraction, and
# an installed template tree (M0.1; Opus recheck finding E1).
#
# The hosted export-preparation job used to install no templates at all, so
# `export --check` could not pass on a fresh runner and the obvious workaround
# (GODOT_TEMPLATES_DIR) would have turned a red check green while the build
# still failed. This command closes both halves: the archive is compared against
# the publisher's pinned SHA-512 before anything is unpacked, and the installed
# tree is checked where the engine actually reads it.
#
# Like verify-engine, it resolves no engine: it hashes files and reads the pin.
#
# Exit codes: 0 = every requested check matched, 1 = a mismatch or an
# unrecorded pin, 2 = the command could not run.
# ---------------------------------------------------------------------------
cmd_verify_templates() {
	_archive=""
	_dir=""
	_mode="release"
	while [ $# -gt 0 ]; do
		case "$1" in
			--archive)
				[ $# -ge 2 ] || ci_die "verify-templates: --archive needs a file"
				_archive="$2"
				shift 2
				;;
			--archive=*) _archive="${1#--archive=}"; shift ;;
			--dir)
				[ $# -ge 2 ] || ci_die "verify-templates: --dir needs a directory"
				_dir="$2"
				shift 2
				;;
			--dir=*) _dir="${1#--dir=}"; shift ;;
			--mode)
				[ $# -ge 2 ] || ci_die "verify-templates: --mode needs debug or release"
				_mode="$2"
				shift 2
				;;
			--mode=*) _mode="${1#--mode=}"; shift ;;
			*) ci_die "verify-templates: unknown option $1" ;;
		esac
	done
	case "$_mode" in
		debug | release) : ;;
		*) ci_die "verify-templates: --mode must be debug or release (got '$_mode')" ;;
	esac
	if [ -z "$_archive" ] && [ -z "$_dir" ]; then
		ci_die "verify-templates: give --archive <file> and/or --dir <dir>"
	fi

	_rc="$CI_OK"
	ci_step "verify-templates: pinned export templates"
	ci_info "pin source:     $CI_PIN_SOURCE"
	ci_info "pinned tag:     $CI_PIN_TAG"
	ci_info "templates url:  ${CI_PIN_TEMPLATES_URL:-not recorded}"
	ci_info "checksums url:  ${CI_PIN_RELEASE_CHECKSUMS_URL:-not recorded}"

	if [ -z "$(ci_sha512_tool)" ]; then
		ci_fail "no sha512 utility on PATH (need shasum or sha512sum); the publisher's digest cannot be checked, so the artifact is refused"
		return "$CI_FAIL"
	fi

	if [ -n "$_archive" ]; then
		if [ ! -f "$_archive" ]; then
			ci_fail "verify-templates: archive does not exist: $_archive"
			return "$CI_FAIL"
		fi
		ci_info "archive:        $_archive ($(wc -c <"$_archive" 2>/dev/null | tr -d ' ') bytes)"
		# The publisher publishes SHA-512, so compare with SHA-512.
		ci_verify_digest "export templates archive sha512" "$_archive" "$CI_PIN_TEMPLATES_SHA512" sha512 || _rc="$CI_FAIL"
		if [ "$_rc" -eq 0 ]; then
			ci_ok "the template archive may be extracted"
		else
			ci_fail "DO NOT extract or install this template archive: it does not match the pinned digest"
		fi
	fi

	if [ -n "$_dir" ]; then
		_tver="${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}.stable"
		if [ ! -d "$_dir/$_tver" ]; then
			ci_fail "verify-templates: no $_tver directory in $_dir (the engine reads $_dir/$_tver)"
			_rc="$CI_FAIL"
		else
			_vtxt="$(head -n 1 "$_dir/$_tver/version.txt" 2>/dev/null)"
			if [ "$_vtxt" = "$_tver" ]; then
				ci_ok "installed templates: version.txt reports $_tver in $_dir"
			else
				ci_fail "installed templates: version.txt reports '$_vtxt' in $_dir/$_tver (expected $_tver)"
				_rc="$CI_FAIL"
			fi
			ci_export_templates_check "$_dir" "$_mode" "$CI_PROJECT/export_presets.cfg" || _rc="$CI_FAIL"
		fi
	fi

	ci_report "verify-templates result=$([ "$_rc" -eq 0 ] && printf pass || printf fail) archive=${_archive:-none} dir=${_dir:-none} mode=$_mode"
	[ "$_rc" -eq 0 ] && ci_ok "verify-templates: PASS" || ci_fail "verify-templates: FAIL"
	return "$_rc"
}

# ---------------------------------------------------------------------------
# install-templates : verify the export-template archive against the pinned
# publisher digest BEFORE extraction, then install the payload where the engine
# reads it (coordinator follow-up).
#
# The official Godot build-release.sh packages the template files under a
# top-level templates/ directory inside the .tpz:
#     templates/version.txt, templates/linux_release.x86_64, ...
# There is no <version>.stable/ directory in the archive, so searching the
# extracted tree for one fails on the publisher's own artifact. This command
# locates the payload by its version.txt instead, validates that the version
# matches the pin BEFORE anything is moved, and requires the staged tree to
# satisfy this project's presets before it replaces <dest>/<version>.stable.
#
# `--dest` is the engine's export_templates root (on GitHub Linux,
# $HOME/.local/share/godot/export_templates); the installed tree is
# <dest>/<major>.<minor>.<patch>.stable. An existing target directory is
# REFUSED, never deleted or replaced silently: this command must not be able to
# destroy an installed template tree. Remove the existing directory explicitly
# if a reinstall is intended (a fresh hosted runner has none).
#
# Like verify-engine/verify-templates, it resolves no engine.
#
# Exit codes: 0 = installed and verified, 1 = mismatch/refused, 2 = unusable.
# ---------------------------------------------------------------------------
cmd_install_templates() {
	_archive=""
	_dest=""
	_mode="release"
	while [ $# -gt 0 ]; do
		case "$1" in
			--archive)
				[ $# -ge 2 ] || ci_die "install-templates: --archive needs a file"
				_archive="$2"
				shift 2
				;;
			--archive=*) _archive="${1#--archive=}"; shift ;;
			--dest)
				[ $# -ge 2 ] || ci_die "install-templates: --dest needs a directory"
				_dest="$2"
				shift 2
				;;
			--dest=*) _dest="${1#--dest=}"; shift ;;
			--mode)
				[ $# -ge 2 ] || ci_die "install-templates: --mode needs debug or release"
				_mode="$2"
				shift 2
				;;
			--mode=*) _mode="${1#--mode=}"; shift ;;
			*) ci_die "install-templates: unknown option $1" ;;
		esac
	done
	case "$_mode" in
		debug | release) : ;;
		*) ci_die "install-templates: --mode must be debug or release (got '$_mode')" ;;
	esac
	if [ -z "$_archive" ] || [ -z "$_dest" ]; then
		ci_die "install-templates: give --archive <file> and --dest <dir>"
	fi

	_tver="${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}.stable"
	ci_step "install-templates: pinned export templates"
	ci_info "pin source:    $CI_PIN_SOURCE"
	ci_info "pinned tag:    $CI_PIN_TAG"
	ci_info "templates url: ${CI_PIN_TEMPLATES_URL:-not recorded}"
	ci_info "destination:   $_dest/$_tver"

	if [ -z "$(ci_sha512_tool)" ]; then
		ci_fail "no sha512 utility on PATH (need shasum or sha512sum); the publisher's digest cannot be checked, so the artifact is refused"
		return "$CI_FAIL"
	fi
	if [ ! -f "$_archive" ]; then
		ci_fail "install-templates: archive does not exist: $_archive"
		return "$CI_FAIL"
	fi

	# PLAN.md M0.1: verify before installation. Nothing is extracted unless the
	# archive is the publisher's pinned bytes.
	ci_info "archive:       $_archive ($(wc -c <"$_archive" | tr -d ' ') bytes)"
	if ! ci_verify_digest "export templates archive sha512" "$_archive" "$CI_PIN_TEMPLATES_SHA512" sha512; then
		ci_fail "DO NOT extract or install this template archive: it does not match the pinned digest"
		return "$CI_FAIL"
	fi
	ci_ok "the archive matches the pinned digest and may be extracted"

	_stage="$(mktemp -d "$CI_OUT/templates-stage.XXXXXX" 2>/dev/null)" || {
		ci_fail "install-templates: cannot create a staging directory under $CI_OUT"
		return "$CI_FAIL"
	}
	trap 'rm -rf "$_stage"' EXIT INT TERM

	mkdir -p "$_dest" || {
		ci_fail "install-templates: cannot create destination: $_dest"
		return "$CI_FAIL"
	}

	if ! unzip -q "$_archive" -d "$_stage"; then
		ci_fail "install-templates: unzip failed for $_archive"
		return "$CI_FAIL"
	fi

	# The publisher's archive carries templates/<files> at its root. Find the
	# payload by version.txt rather than assuming a directory named after the
	# version, while still accepting a self-named legacy layout.
	_payload=""
	if [ -f "$_stage/templates/version.txt" ]; then
		_payload="$_stage/templates"
	else
		_candidates="$(find "$_stage" -maxdepth 3 -type f -name version.txt 2>/dev/null | sort)"
		_n="$(printf '%s\n' "$_candidates" | grep -c . || true)"
		if [ "$_n" = "1" ]; then
			_payload="$(dirname "$_candidates")"
		elif [ "$_n" -gt 1 ]; then
			ci_fail "install-templates: the archive contains $_n version.txt files; cannot choose the template payload"
			printf '%s\n' "$_candidates" | sed 's/^/    /' >&2
			return "$CI_FAIL"
		fi
	fi
	if [ -z "$_payload" ] || [ ! -f "$_payload/version.txt" ]; then
		ci_fail "install-templates: the verified archive contains no template payload (expected templates/version.txt)"
		return "$CI_FAIL"
	fi

	# Validate the version BEFORE anything is placed: a payload for another
	# engine version must never reach the engine's directory.
	_vtxt="$(head -n 1 "$_payload/version.txt" 2>/dev/null)"
	if [ "$_vtxt" != "$_tver" ]; then
		ci_fail "install-templates: refusing to install: version.txt reports '$_vtxt' (expected $_tver)"
		return "$CI_FAIL"
	fi
	ci_ok "staged templates: version.txt reports $_tver"

	# Verify the staged tree against this project's presets before it replaces
	# anything in the destination. ci_export_templates_check expects the tree at
	# <root>/<version>.stable, so stage it under that name first.
	_check_root="$_stage/install"
	mkdir -p "$_check_root" || {
		ci_fail "install-templates: cannot create the staging root $_check_root"
		return "$CI_FAIL"
	}
	if ! mv "$_payload" "$_check_root/$_tver"; then
		ci_fail "install-templates: could not stage the payload at $_check_root/$_tver"
		return "$CI_FAIL"
	fi
	if ! ci_export_templates_check "$_check_root" "$_mode" "$CI_PROJECT/export_presets.cfg"; then
		ci_fail "install-templates: refusing to install: the staged templates do not satisfy the project's export presets"
		return "$CI_FAIL"
	fi

	# Destination policy: never mutate an existing installed tree. A fresh
	# hosted runner has no <dest>/<version>.stable; on a persistent host the
	# operator removes it explicitly before reinstalling. This check runs after
	# archive, payload, and template validation, immediately before the move.
	# It is not a race-free transaction with another installer.
	if [ -e "$_dest/$_tver" ] || [ -L "$_dest/$_tver" ]; then
		ci_fail "install-templates: $_dest/$_tver already exists; refusing to replace an installed template tree (remove it explicitly if a reinstall is intended)"
		return "$CI_FAIL"
	fi

	if ! mv "$_check_root/$_tver" "$_dest/$_tver"; then
		ci_fail "install-templates: could not install the verified templates into $_dest/$_tver"
		return "$CI_FAIL"
	fi

	ci_ok "installed templates: $_dest/$_tver"
	ci_report "install-templates result=pass dest=$_dest tver=$_tver mode=$_mode archive=$_archive"
	ci_ok "install-templates: PASS"
	return "$CI_OK"
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
	printf 'templates_url=%s\n' "$CI_PIN_TEMPLATES_URL"
	printf 'templates_archive_sha512=%s\n' "$CI_PIN_TEMPLATES_SHA512"
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
		templates_url) _value="$CI_PIN_TEMPLATES_URL" ;;
		templates_archive_sha512) _value="$CI_PIN_TEMPLATES_SHA512"; _digest=1 ;;
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
	ci_info "templates:      $(ci_templates_engine_dir || printf 'not determined')"

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
	for _f in "$CI_TOOLS_DIR/ci.sh" "$CI_TOOLS_DIR/lib/common.sh" \
		"$CI_TOOLS_DIR/scripts/runtime_error_gate.sh" \
		"$CI_TOOLS_DIR/scripts/warning_watch.sh"; do
		if [ -x "$_f" ]; then
			ci_ok "executable: $(ci_relpath "$_f")"
		else
			ci_fail "not executable: $(ci_relpath "$_f")"
			_self_rc="$CI_FAIL"
		fi
	done
	for _f in "$CI_TOOLS_DIR/scripts/"*.gd "$CI_TOOLS_DIR/pin/engine.txt" "$CI_TOOLS_DIR/contracts.list" \
		"$CI_TOOLS_DIR/warnings.allow" "$CI_TOOLS_DIR/tests/run_tests.sh"; do
		if [ -f "$_f" ]; then
			ci_ok "present: $(ci_relpath "$_f")"
		else
			ci_fail "missing tooling file: $(ci_relpath "$_f")"
			_self_rc="$CI_FAIL"
		fi
	done
	# The scratch output directory must never be committed. It keeps itself
	# ignored with a tracked .gitignore sentinel; that exact sentinel is the
	# intended exception (tools/ci/out/.gitignore is deliberately in the index),
	# while every other tracked path there is build output and fails. Exempting
	# the whole directory or every dotfile would defeat the check.
	if [ -n "$CI_OUT_REL_PATH" ] && command -v git >/dev/null 2>&1 &&
		{ [ -d "$CI_PROJECT/.git" ] || [ -f "$CI_PROJECT/.git" ]; }; then
		# Fail closed: the helper returns git ls-files' real status, so an
		# unreadable or truncated index fails here instead of looking like an
		# empty path list (Sol recheck 8c6c928).
		_tracked_list="$(ci_tracked_output_paths "$CI_PROJECT" "$CI_OUT_REL_PATH")"
		_tracked_rc=$?
		if [ "$_tracked_rc" -ne 0 ]; then
			ci_fail "tracked-output check: could not list tracked paths under $CI_OUT_REL_PATH (git exited $_tracked_rc); refusing to report it clean"
			_self_rc="$CI_FAIL"
		else
			_tracked="$(printf '%s\n' "$_tracked_list" | ci_count_lines)"
			if [ "$_tracked" = "0" ]; then
				ci_ok "no tracked build output under $CI_OUT_REL_PATH (its own .gitignore sentinel is the intended exception)"
			else
				ci_fail "$_tracked tracked file(s) under $CI_OUT_REL_PATH - build output must not be committed:"
				printf '%s\n' "$_tracked_list" | sed 's/^/    /'
				_self_rc="$CI_FAIL"
			fi
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
	# Forward GODOT_BIN so the suite uses the same editor this command already
	# resolved (on CI that is the digest-verified downloaded binary). Without it
	# the hosted self-test cannot discover an engine and silently skips every
	# engine-backed export --check case even though the runner has one.
	_out="$(PROJECT_DIR="$CI_PROJECT" TOOLS_CI_DIR="$CI_TOOLS_DIR" GODOT_BIN="$GODOT_BIN" sh "$_runner" 2>&1)"
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
# Engine WARNING lines seen across the discovered checks: total, and how many of
# them are not in tools/ci/warnings.allow. Both are reported, so a run that
# printed warnings is never reported as an unqualified pass (Opus recheck
# finding R7') and a warning the project has accepted is visibly accepted
# rather than quietly dropped.
CI_TEST_WARN=0
CI_TEST_WARN_UNEXPECTED=0

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

	if [ "$CI_TEST_WARN" -gt 0 ]; then
		if [ "$CI_STRICT_WARNINGS" -eq 1 ]; then
			ci_warn "$CI_TEST_WARN engine warning line(s) across $CI_TEST_RUN check(s), $CI_TEST_WARN_UNEXPECTED of them not accepted in $CI_WARNINGS_ALLOW; strict warnings are on, so an unaccepted warning failed its check (see the per-check lines above)"
		else
			ci_warn "$CI_TEST_WARN engine warning line(s) across $CI_TEST_RUN check(s), $CI_TEST_WARN_UNEXPECTED of them not accepted in $CI_WARNINGS_ALLOW; surfaced, not fatal (use --strict-warnings to fail on unexpected ones)"
		fi
	fi
	ci_report "test result=$([ "$CI_TEST_FAIL" -eq 0 ] && [ "$CI_TEST_RUN" -gt 0 ] && printf pass || printf fail) run=$CI_TEST_RUN pass=$CI_TEST_PASS fail=$CI_TEST_FAIL warnings=$CI_TEST_WARN unexpected_warnings=$CI_TEST_WARN_UNEXPECTED strict_warnings=$CI_STRICT_WARNINGS"
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

# ci_run_one_test : run one discovered headless check and judge it.
#
# Three independent signals decide the verdict, because the pinned engine exits 0
# for a script that throws at runtime (Opus recheck finding N1):
#   1. the exit status;
#   2. the captured engine log, gated on error lines exactly as the supported
#      wrapper tools/smoke/run_boot_smoke.sh gates it;
#   3. Jolt physics warnings in that log, which mean the physics step ignored
#      contacts or fell back to a slower allocator (finding R7').
# Signal 2 is what makes `ci.sh test` at least as strong as the wrapper: a
# runtime error in any boot script (a missing dictionary key, push_error(), ...)
# leaves the shell running, so the exit code alone reports a pass.
#
# Engine WARNING lines that do not name Jolt are surfaced and counted, never
# silent, and are fatal only with --strict-warnings (see ci_log_warning_gate).
# The exit-code proof is untouched: a deliberately failing check must still exit
# nonzero.
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

	# Signal 1: the exit status.
	if [ "$CI_LAST_EXIT" -ne 0 ]; then
		ci_fail "FAIL: $_res exited $CI_LAST_EXIT"
		ci_log_error_lines "$CI_LAST_LOG" | tail -n 20 | sed 's/^/    /'
		CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
		ci_count_check_warnings "$CI_LAST_LOG"
		ci_report "check=$_res result=fail exit=$CI_LAST_EXIT errors=$(ci_log_error_count "$CI_LAST_LOG") warnings=$(ci_log_warning_count "$CI_LAST_LOG") unexpected_warnings=$(ci_log_unexpected_warning_count "$CI_LAST_LOG") jolt_warnings=$(ci_log_jolt_warning_count "$CI_LAST_LOG")"
		ci_log_warning_gate "$CI_LAST_LOG" "$_res" || CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
		return "$CI_OK"
	fi

	# Signal 2: engine error lines in the captured log. The exit status was 0, so
	# this is the only remaining signal that the check really ran clean.
	_errs="$(ci_log_error_count "$CI_LAST_LOG")"
	if [ "$_errs" != "0" ]; then
		ci_fail "FAIL: $_res exited 0 but the engine reported $_errs error line(s); the check did not fail on a runtime error"
		ci_log_error_lines "$CI_LAST_LOG" | tail -n 20 | sed 's/^/    /'
		CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
		ci_count_check_warnings "$CI_LAST_LOG"
		ci_report "check=$_res result=fail exit=0 reason=engine-errors errors=$_errs warnings=$(ci_log_warning_count "$CI_LAST_LOG") unexpected_warnings=$(ci_log_unexpected_warning_count "$CI_LAST_LOG") jolt_warnings=$(ci_log_jolt_warning_count "$CI_LAST_LOG")"
		ci_log_warning_gate "$CI_LAST_LOG" "$_res" || CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
		return "$CI_OK"
	fi

	# Signal 3, before the pass is recorded: a Jolt warning is a physics result,
	# not noise (see ci_log_jolt_warning_lines for the five shapes the pinned
	# engine emits), so it turns an exit-0 check into a failure.
	_jolt="$(ci_log_jolt_warning_count "$CI_LAST_LOG")"
	if [ "$_jolt" != "0" ]; then
		ci_fail "FAIL: $_res reported $_jolt Jolt physics warning line(s); the engine ignores contacts or falls back to a slower allocator when these appear"
		ci_log_jolt_warning_lines "$CI_LAST_LOG" | sed 's/^/    /'
		CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
		ci_count_check_warnings "$CI_LAST_LOG"
		ci_report "check=$_res result=fail exit=0 reason=jolt-warning errors=0 warnings=$(ci_log_warning_count "$CI_LAST_LOG") unexpected_warnings=$(ci_log_unexpected_warning_count "$CI_LAST_LOG") jolt_warnings=$_jolt"
		return "$CI_OK"
	fi

	# Signal 4, decided BEFORE the verdict is recorded. With --strict-warnings an
	# unaccepted warning is fatal, and Sol recheck finding 4 is that the pass was
	# recorded and counted first, so a strict failure left a passing per-check
	# record next to a failed stage. The gate also prints every warning line, so
	# the FAIL line that follows it still names the reason.
	if ! ci_log_warning_gate "$CI_LAST_LOG" "$_res"; then
		ci_fail "FAIL: $_res (strict warnings: an unaccepted engine warning is fatal)"
		CI_TEST_FAIL=$((CI_TEST_FAIL + 1))
		ci_count_check_warnings "$CI_LAST_LOG"
		ci_report "check=$_res result=fail exit=0 reason=strict-warnings errors=0 warnings=$(ci_log_warning_count "$CI_LAST_LOG") unexpected_warnings=$(ci_log_unexpected_warning_count "$CI_LAST_LOG") jolt_warnings=$(ci_log_jolt_warning_count "$CI_LAST_LOG")"
		return "$CI_OK"
	fi

	ci_ok "PASS: $_res"
	CI_TEST_PASS=$((CI_TEST_PASS + 1))
	ci_count_check_warnings "$CI_LAST_LOG"
	ci_report "check=$_res result=pass exit=0 errors=0 warnings=$(ci_log_warning_count "$CI_LAST_LOG") unexpected_warnings=$(ci_log_unexpected_warning_count "$CI_LAST_LOG") jolt_warnings=0"
	return "$CI_OK"
}

# ci_count_check_warnings <logfile> : add one check's warning lines to the
# stage totals used in the report.
ci_count_check_warnings() {
	_w="$(ci_log_warning_count "$1")"
	_u="$(ci_log_unexpected_warning_count "$1")"
	[ "$_w" != "0" ] && CI_TEST_WARN=$((CI_TEST_WARN + _w))
	[ "$_u" != "0" ] && CI_TEST_WARN_UNEXPECTED=$((CI_TEST_WARN_UNEXPECTED + _u))
	return 0
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
# The required native targets (docs/TECHNICAL_DESIGN.md "Packaging and
# operations") and their Godot preset `platform=` values live in
# lib/common.sh: CI_EXPORT_PLATFORMS, ci_preset_platform_for and
# ci_preset_platform_coverage. The names differ from the preset values
# ("Windows" is platform="Windows Desktop" in export_presets.cfg), so the
# coverage check must go through the mapping rather than compare directly.
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

# ci_export_templates_check <templates-root> <mode> <export_presets.cfg> :
# verifies that the template tree holds the template every REQUIRED target
# needs, for the architecture that target's preset declares. Prints one
# ci_ok/ci_fail line per covering preset and returns CI_OK/CI_FAIL.
#
# Two findings this closes, both measured against the pinned engine:
#   E1 - the engine reads <user data dir>/export_templates/<version>.stable and
#        ignores $GODOT_TEMPLATES_DIR, so the tree passed in here must be the
#        engine's own (the caller decides which directory that is).
#   E2 - a presence check that accepted ANY architecture passed a tree holding
#        only the 32-bit Windows and Linux templates while both presets declare
#        x86_64; the export then fails. The required file is now derived from
#        the preset's binary_format/architecture, and an empty file is refused
#        (a zero-byte template is corrupt and cannot be exported).
# Variables are prefixed (_etc_*) so no caller state is clobbered.
ci_export_templates_check() {
	_etc_root="$1"
	_etc_mode="$2"
	_etc_cfg="$3"
	_etc_rc="$CI_OK"

	if [ ! -f "$_etc_cfg" ]; then
		ci_fail "templates: no export_presets.cfg at $_etc_cfg, so the required templates cannot be determined"
		return "$CI_FAIL"
	fi

	_tver="${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}.stable"
	_vtxt="$(head -n 1 "$_etc_root/$_tver/version.txt" 2>/dev/null)"
	if [ "$_vtxt" = "$_tver" ]; then
		ci_ok "templates: version.txt reports $_tver in $(ci_relpath "$_etc_root")"
	else
		ci_fail "templates: version.txt reports '$_vtxt' in $(ci_relpath "$_etc_root")/$_tver (expected $_tver)"
		_etc_rc="$CI_FAIL"
	fi

	_etc_table="$(ci_preset_table "$_etc_cfg" 2>/dev/null | tr '\t' '|')"
	while IFS='|' read -r _etc_idx _etc_name _etc_platform; do
		[ -n "$_etc_idx" ] || continue
		# Only presets that cover a REQUIRED target constrain the templates;
		# ci_preset_platform_coverage reports the targets themselves.
		_etc_req=""
		for _etc_r in $CI_EXPORT_PLATFORMS; do
			if [ "$(ci_preset_platform_for "$_etc_r")" = "$_etc_platform" ]; then
				_etc_req="$_etc_r"
				break
			fi
		done
		[ -n "$_etc_req" ] || continue

		_etc_arch="$(ci_preset_architecture "$_etc_cfg" "$_etc_idx" 2>/dev/null)"
		if [ -z "$_etc_arch" ]; then
			ci_fail "templates: preset '$_etc_name' ($_etc_platform) declares no binary_format/architecture, so the required template cannot be determined (declare it; do not rely on the engine default)"
			_etc_rc="$CI_FAIL"
			continue
		fi
		_etc_files="$(ci_template_files_for "$_etc_req" "$_etc_arch" "$_etc_mode" 2>/dev/null)"
		if [ -z "$_etc_files" ]; then
			ci_fail "templates: preset '$_etc_name' declares architecture '$_etc_arch', which Godot does not accept for $_etc_req (accepted: $(ci_template_architectures "$_etc_req" 2>/dev/null | tr '\n' ' '))"
			_etc_rc="$CI_FAIL"
			continue
		fi

		_etc_found=""
		for _etc_f in $_etc_files; do
			if [ -s "$_etc_root/$_tver/$_etc_f" ]; then
				_etc_found="$_etc_found $_etc_f"
			fi
		done
		if [ -n "$_etc_found" ]; then
			ci_ok "templates: $_etc_req preset '$_etc_name' (architecture=$_etc_arch, mode=$_etc_mode) ->$_etc_found"
		else
			ci_fail "templates: $_etc_req preset '$_etc_name' (architecture=$_etc_arch, mode=$_etc_mode) -> none of [$(printf '%s ' $_etc_files)] in $(ci_relpath "$_etc_root")/$_tver"
			_etc_rc="$CI_FAIL"
		fi

		# The official macOS template ships ONE universal archive, so an arm64 or
		# x86_64 request is a build-time failure the check cannot see here. Say so
		# instead of letting the file presence look like coverage.
		if [ "$_etc_req" = "macOS" ] && [ "$_etc_arch" != "universal" ]; then
			ci_warn "templates: macOS preset '$_etc_name' requests architecture '$_etc_arch'; the official 4.7.2 macOS template (macos.zip) ships only a universal binary, so the build step will fail unless a custom_template is configured"
		fi
	done <<EOF
$_etc_table
EOF
	return "$_etc_rc"
}

ci_export_check() {
	_mode="$1"
	_rc="$CI_OK"
	ci_step "export preparation (mode=$_mode)"
	ci_check_engine_pin || _rc="$CI_FAIL"

	_cfg="$CI_PROJECT/export_presets.cfg"
	if [ ! -f "$_cfg" ]; then
		ci_fail "export presets: no export_presets.cfg at the project root"
		ci_note "Native export preparation is not implemented yet (PLAN.md M0.5/M9.1)."
		ci_note "Add export_presets.cfg through the editor's Project > Export dialog (or hand-author it),"
		ci_note "then re-run 'ci.sh export --check'. Until then, no export is claimed to work."
		ci_report "export-check mode=$_mode result=fail reason=no-presets"
		ci_fail "export preparation: FAIL"
		return "$CI_FAIL"
	fi

	_presets="$(ci_preset_table "$_cfg")"
	if [ -z "$_presets" ]; then
		ci_fail "export presets: export_presets.cfg has no [preset.N] sections"
		ci_report "export-check mode=$_mode result=fail reason=no-preset-sections"
		ci_fail "export preparation: FAIL"
		return "$CI_FAIL"
	fi
	ci_ok "export presets: $(printf '%s\n' "$_presets" | grep -c .) preset(s) declared"
	printf '%s\n' "$_presets" | sed 's/^/    /'
	# Map each required target to the platform value Godot writes in a preset
	# before looking for it, so a covered target is not reported missing
	# ("Windows" -> platform="Windows Desktop").
	ci_preset_platform_coverage "$_cfg" || _rc="$CI_FAIL"

	# Templates: verified where the ENGINE reads them, not where an environment
	# variable points. Measured against the pinned engine: GODOT_TEMPLATES_DIR is
	# not read at all (the name does not appear in the binary, and an export with
	# it set while the engine's own directory is empty fails with "No export
	# template found at the expected path" under that directory). Opus recheck
	# finding E1 is exactly that a check honouring the variable passed a tree the
	# engine then refused to export, so the variable is only ever reported.
	_edir="$(ci_templates_engine_dir || true)"
	_envdir="$(ci_templates_env_dir || true)"
	_tver="${CI_PIN_MAJOR}.${CI_PIN_MINOR}.${CI_PIN_PATCH}.stable"
	if [ -z "$_edir" ]; then
		ci_fail "export templates: cannot determine the engine's user-data directory (HOME/APPDATA unset?)"
		_rc="$CI_FAIL"
	else
		if [ -n "$_envdir" ] && [ "$_envdir" != "$_edir" ]; then
			ci_warn "GODOT_TEMPLATES_DIR=$_envdir is NOT read by the engine; the check below verifies the engine's own directory instead ($_edir)"
			ci_note "install the templates into $_edir/$_tver (the CI workflow does exactly that, after verifying the publisher's digest)"
		fi
		ci_info "engine template directory: $_edir"
		ci_export_templates_check "$_edir" "$_mode" "$_cfg" || _rc="$CI_FAIL"
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

# ---------------------------------------------------------------------------
# Export destination locking (Sol recheck 675ec1c finding 1)
# ---------------------------------------------------------------------------
# Robust OS advisory locks on persistent lock FILES. `<destination>.ci-lock`
# is created without truncation when absent; its bytes are never written. The
# kernel releases the lock automatically when the owning process exits,
# including on a crash, so a stale lock never blocks a later export. No lock
# path is ever deleted or unlinked by this tool. Pre-existing regular files at
# a lock path are preserved byte-for-byte and merely locked; a pre-existing
# symlink or non-regular path is refused, never followed or removed.
_CI_LOCK_TOOL=""
_CI_LOCK_HELD=""
for _cand in flock lockf; do
	if command -v "$_cand" >/dev/null 2>&1; then
		_CI_LOCK_TOOL="$_cand"
		break
	fi
done

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

	# Canonicalise --out against the CALLER's directory BEFORE invoking the
	# engine. Godot resolves a relative export path against --path (the scratch
	# project), so a relative --out silently lands in tools/ci/out/project-copy/
	# while this wrapper looks for it in the caller's directory -- reproduced
	# locally for all three presets as exit 0 followed by "export produced no
	# output". ci_abs_path resolves the result with filesystem semantics, so a
	# ".." after a symlink follows the target's parent as the OS would.
	case "$_out" in
		/*) : ;;
		*) _out="${PWD:-$(pwd)}/$_out" ;;
	esac
	mkdir -p "$(dirname "$_out")" 2>/dev/null || ci_die "cannot create output directory for $_out"
	_out="$(ci_abs_path "$_out")"

	_cfg="$CI_PROJECT/export_presets.cfg"
	[ -f "$_cfg" ] || {
		ci_fail "export --export: no export_presets.cfg at the project root; native export preparation is not implemented yet (PLAN.md M0.5/M9.1)"
		return "$CI_FAIL"
	}
	if ! ci_export_list names | grep -Fqx -- "$_preset"; then
		ci_fail "export --export: preset '$_preset' is not declared in export_presets.cfg"
		ci_note "declared presets: $(ci_export_list names | tr '\n' ' ')"
		return "$CI_FAIL"
	fi

	# Give this invocation preset-specific log/report names. Each ci.sh process
	# starts CI_LOG_SEQ at 0, so without this every preset overwrites the
	# previous preset's export-2-export.log and the evidence for earlier presets
	# disappears from the uploaded logs.
	_slug="$(ci_preset_slug "$_preset")"
	[ -n "$_slug" ] || _slug="preset"
	CI_RUN_NAME="export-$_slug"
	# ci_init_report ran before dispatch and therefore used the generic command
	# name. Give the already-written report the same preset-specific name as the
	# logs so two presets can never share an evidence file. Publication is
	# create-only at the exact destination (ci_link_create_only): a regular
	# file, dangling symlink, directory or symlink-to-directory occupant is
	# refused instead of written through or into, and the successful link leaves
	# one inode behind both names so the parent/worker handoff stays coherent.
	# A failure here aborts before the engine writes anything: continuing would
	# let an export exit 0 while its verdict landed nowhere.
	if [ -n "$CI_REPORT" ] && [ -f "$CI_REPORT" ] && [ -n "$CI_ATTEMPT_ID" ]; then
		_new_report="$CI_OUT/reports/export-${_slug}-${CI_ATTEMPT_ID}.txt"
		if ! ci_publish_report_exclusive "$CI_REPORT" "$_new_report"; then
			ci_fail "export --export: cannot publish the preset-specific report at $_new_report; the name is occupied by something that is not this attempt's report"
			ci_note "refusing to continue without a writable per-attempt verdict; the attempt keeps its report at $CI_REPORT"
			ci_report "export result=fail preset=$_preset mode=$_mode reason=report-publication-failed output=$_out report=$_new_report"
			return "$CI_FAIL"
		fi
		CI_REPORT="$_new_report"
	fi

	# Sidecar path, derived from the output BASENAME so a dot in a directory
	# component cannot move it. Computed before the engine runs.
	_pck="$(ci_export_sidecar_for_out "$_out")"

	# Reject destinations inside the reserved ".ci-lock" namespace. Lock files
	# are "<destination>.ci-lock"; an output ending in .ci-lock would itself be
	# another invocation's lock file, letting two cooperating exports enter the
	# engine and one overwrite the other's empty lock with package bytes. The
	# early guard already refused this before the engine version probe; keep the
	# canonical checks on each path separately under the real parsed values.
	if ci_export_path_in_lock_namespace "$_out"; then
		ci_fail "export --export: destination is inside the reserved .ci-lock lock namespace: $_out (choose another output name)"
		ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-namespace output=$_out"
		return "$CI_FAIL"
	fi
	if ci_export_path_in_lock_namespace "$_pck"; then
		ci_fail "export --export: sidecar destination is inside the reserved .ci-lock lock namespace: $_pck (choose another output name)"
		ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-namespace output=$_out"
		return "$CI_FAIL"
	fi

	# Validate the lock namespace and lock paths here for a fast, structured
	# failure. The worker re-checks under its own process and acquires the fds.
	_wait="${CI_EXPORT_LOCK_WAIT:-900}"
	case "$_wait" in '' | *[!0-9]*) _wait=900 ;; esac
	if [ "$_out" = "$_pck" ]; then
		_lock_list="$_out.ci-lock"
	else
		_lock_list="$(printf '%s.ci-lock\n%s.ci-lock\n' "$_out" "$_pck" | LC_ALL=C sort)"
	fi
	while IFS= read -r _lp; do
		[ -n "$_lp" ] || continue
		_ci_lock_precheck "$_lp" || {
			ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-path-invalid lock=$_lp"
			return "$CI_FAIL"
		}
	done <<EOF
$_lock_list
EOF
	if [ -z "$_CI_LOCK_TOOL" ]; then
		ci_fail "export --export: neither flock(1) nor lockf(1) is available; refusing to export without an exclusive lock"
		ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-tool-missing"
		return "$CI_FAIL"
	fi
	_saved_report_env="${ROADSTORM_CI_REPORT:-}"
	export ROADSTORM_CI_REPORT="$CI_REPORT" ROADSTORM_CI_ATTEMPT_ID="$CI_ATTEMPT_ID"
	_attempt_slug="${_slug}-${CI_ATTEMPT_ID}"
	export ROADSTORM_CI_LOG_BASE="$CI_OUT/logs/export-${_attempt_slug}"
	export ROADSTORM_CI_COPY_BASE="$CI_OUT/attempts/export-${_attempt_slug}/project-copy"
	export CI_STRICT_WARNINGS="${CI_STRICT_WARNINGS:-0}" CI_TIMEOUT_DEFAULT="${CI_TIMEOUT_DEFAULT:-300}"
	_shq() {
		printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
	}
	_source_sha_args=""
	[ -n "${ROADSTORM_SOURCE_SHA:-}" ] && _source_sha_args="--source-sha $(_shq "$ROADSTORM_SOURCE_SHA")"
	_inner_cmd="$(_shq "$CI_TOOLS_DIR/ci.sh") --project $(_shq "$CI_PROJECT") --godot $(_shq "$GODOT_BIN") --out $(_shq "$CI_OUT") $_source_sha_args __export-inner $(_shq "$_preset") $(_shq "$_mode") $(_shq "$_out")"
	# Restore the caller-visible report pointer after the worker handoff:
	# leaving ROADSTORM_CI_REPORT exported would suppress this process's own
	# final `report:` line even though it did not create that file.
	eval "$_inner_cmd"
	_inner_rc=$?
	if [ -n "$_saved_report_env" ]; then
		export ROADSTORM_CI_REPORT="$_saved_report_env"
	else
		unset ROADSTORM_CI_REPORT
	fi
	return "$_inner_rc"
}

# _ci_lock_precheck <path> : refuse symlinks/non-regular pre-existing lock paths.
_ci_lock_precheck() {
	_lpc="$1"
	if [ -L "$_lpc" ]; then
		ci_fail "export --export: refusing to follow existing symlink lock path: $_lpc (remove or replace it manually)"
		return "$CI_FAIL"
	fi
	if [ -e "$_lpc" ] && [ ! -f "$_lpc" ]; then
		ci_fail "export --export: refusing to use non-regular lock path: $_lpc (remove or replace it manually)"
		return "$CI_FAIL"
	fi
	return "$CI_OK"
}

# _ci_lock_acquire_fd <fd> <path> <timeout> : acquire an in-process advisory
# lock on an already-open descriptor. Keeping the fd in this shell means the
# kernel releases the lock when the exporting process exits, is signalled or
# crashes; no external locker process or inherited watchdog holds it alive.
_ci_lock_acquire_fd() {
	_af_fd="$1"; _af_file="$2"; _af_wait="$3"
	_af_err="$CI_LOG_DIR/export-lock-error.log"
	: >"$_af_err" 2>/dev/null
	case "$_CI_LOCK_TOOL" in
		flock) flock -x -w "$_af_wait" "$_af_fd" 2>"$_af_err" ;;
		lockf) lockf -s -t "$_af_wait" "$_af_fd" 2>"$_af_err" ;;
		*) ci_die "unknown lock tool: $_CI_LOCK_TOOL" ;;
	esac
	_af_rc=$?
	if [ "$_af_rc" -ne 0 ]; then
		_af_msg="$(cat "$_af_err" 2>/dev/null)"
		ci_fail "export --export: timed out after ${_af_wait}s waiting for lock $_af_file (tool $_CI_LOCK_TOOL rc $_af_rc); another export is still active or the lock path is not writable"
		[ -n "$_af_msg" ] && printf '%s\n' "$_af_msg" | sed 's/^/    /'
		ci_report "export result=fail reason=lock-timeout lock=$_af_file wait=$_af_wait tool=$_CI_LOCK_TOOL rc=$_af_rc"
		return "$CI_FAIL"
	fi
	_CI_LOCK_HELD="$_CI_LOCK_HELD $_af_fd"
	return "$CI_OK"
}

# ci_print_export_failure_log <logfile> : print the whole captured engine log,
# indented. Godot's export configuration errors are multi-line and indented;
# filtering to anchored ERROR lines alone hid the reason in hosted run
# 45921573623. Called only on a failed export; never replaces the verdict.
ci_print_export_failure_log() {
	_pfl="$1"
	[ -f "$_pfl" ] || return 0
	ci_note "full engine log ($_pfl):"
	sed 's/^/    /' "$_pfl"
	return 0
}

ci_export_build_inner() {
	_preset="$1"
	_mode="$2"
	_out="$3"
	_cfg="$CI_PROJECT/export_presets.cfg"
	[ -f "$_cfg" ] || {
		ci_fail "export --export: no export_presets.cfg at the project root"
		return "$CI_FAIL"
	}
	if ! ci_export_list names | grep -Fqx -- "$_preset"; then
		ci_fail "export --export: preset '$_preset' is not declared in export_presets.cfg"
		return "$CI_FAIL"
	fi
	_slug="$(ci_preset_slug "$_preset")"
	[ -n "$_slug" ] || _slug="preset"
	CI_RUN_NAME="export-$_slug"
	# Same exact-destination create-only publication as the outer path: a
	# direct __export-inner call must not replace an existing report path
	# either, and must abort before any lock or engine write if it cannot.
	if [ -n "$CI_REPORT" ] && [ -f "$CI_REPORT" ] && [ -n "$CI_ATTEMPT_ID" ]; then
		_new_report="$CI_OUT/reports/export-${_slug}-${CI_ATTEMPT_ID}.txt"
		if ! ci_publish_report_exclusive "$CI_REPORT" "$_new_report"; then
			ci_fail "export --export: cannot publish the preset-specific report at $_new_report; the name is occupied by something that is not this attempt's report"
			ci_note "refusing to continue without a writable per-attempt verdict; the attempt keeps its report at $CI_REPORT"
			ci_report "export result=fail preset=$_preset mode=$_mode reason=report-publication-failed output=$_out report=$_new_report"
			return "$CI_FAIL"
		fi
		CI_REPORT="$_new_report"
	fi
	_pck="$(ci_export_sidecar_for_out "$_out")"

	# Reserved lock namespace must be rejected even for a direct worker call,
	# and the early guard has already done so before any engine invocation. Check
	# each path separately, exactly like the outer path: concatenating the
	# lowercased names lets an output ending in .ci-lock hide behind a sidecar
	# suffix that does not (e.g. out=name.ci-lock, pck=name.pck), so the
	# combined string no longer ends in .ci-lock and the guard would bypass.
	if ci_export_path_in_lock_namespace "$_out"; then
		ci_fail "export --export: destination is inside the reserved .ci-lock lock namespace: $_out (choose another output name)"
		ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-namespace output=$_out"
		return "$CI_FAIL"
	fi
	if ci_export_path_in_lock_namespace "$_pck"; then
		ci_fail "export --export: sidecar destination is inside the reserved .ci-lock lock namespace: $_pck (choose another output name)"
		ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-namespace output=$_out"
		return "$CI_FAIL"
	fi

	# Acquire both destination locks IN THIS PROCESS before the stale-output
	# check. fd-form flock/lockf associate the advisory lock with the open file
	# description held by this shell, so the kernel releases it when the actual
	# export process exits, is signalled or crashes -- including cases where an
	# engine watchdog child would otherwise inherit an external locker's fd.
	_wait="${CI_EXPORT_LOCK_WAIT:-900}"
	case "$_wait" in '' | *[!0-9]*) _wait=900 ;; esac
	if [ "$_out" = "$_pck" ]; then
		_lock_list="$_out.ci-lock"
	else
		_lock_list="$(printf '%s.ci-lock\n%s.ci-lock\n' "$_out" "$_pck" | LC_ALL=C sort)"
	fi
	while IFS= read -r _lp; do
		[ -n "$_lp" ] || continue
		_ci_lock_precheck "$_lp" || {
			ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-path-invalid lock=$_lp"
			return "$CI_FAIL"
		}
	done <<EOF
$_lock_list
EOF
	if [ -z "$_CI_LOCK_TOOL" ]; then
		ci_fail "export --export: neither flock(1) nor lockf(1) is available; refusing to export without an exclusive lock"
		ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-tool-missing"
		return "$CI_FAIL"
	fi
	_lock1="$(printf '%s\n' "$_lock_list" | head -n 1)"
	if ! exec 9>>"$_lock1"; then
		ci_fail "export --export: cannot open lock file $_lock1"
		ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-open-failed lock=$_lock1"
		return "$CI_FAIL"
	fi
	if ! _ci_lock_acquire_fd 9 "$_lock1" "$_wait"; then
		exec 9>&-
		return "$CI_FAIL"
	fi
	if [ "$_out" != "$_pck" ]; then
		_lock2="$(printf '%s\n' "$_lock_list" | tail -n 1)"
		if ! exec 8>>"$_lock2"; then
			ci_fail "export --export: cannot open lock file $_lock2"
			_ci_close_lock_fds
			ci_report "export result=fail preset=$_preset mode=$_mode reason=lock-open-failed lock=$_lock2"
			return "$CI_FAIL"
		fi
		if ! _ci_lock_acquire_fd 8 "$_lock2" "$_wait"; then
			_ci_close_lock_fds
			return "$CI_FAIL"
		fi
	fi
	trap '_ci_close_lock_fds' EXIT
	trap '_ci_close_lock_fds; exit 130' INT TERM HUP

	# Under the lock: refuse to reuse an output path that already holds a file
	# or sidecar (Opus R2). Without this, a later engine run that silently
	# writes nothing would be validated against the PREVIOUS package and its
	# inventory would pass on old bytes. ci.sh never deletes or replaces
	# existing user outputs: the caller moves/removes them explicitly.
	_stale=""
	{ [ -e "$_out" ] || [ -L "$_out" ]; } && _stale="$_out"
	if [ -z "$_stale" ]; then
		{ [ -e "$_pck" ] || [ -L "$_pck" ]; } && _stale="$_pck"
	fi
	if [ -n "$_stale" ]; then
		ci_fail "export --export: refusing to overwrite existing output: $_stale"
		ci_note "ci.sh never deletes or replaces existing outputs; move or remove it and re-run"
		ci_report "export result=fail preset=$_preset mode=$_mode reason=output-exists output=$_out"
		return "$CI_FAIL"
	fi

	ci_prepared_copy || return "$CI_FAIL"
	_flag="--export-release"
	[ "$_mode" = "debug" ] && _flag="--export-debug"
	ci_step "export: preset '$_preset' ($_mode) -> $_out"
	ci_run_godot export --headless --path "$CI_PROJECT_COPY" "$_flag" "$_preset" "$_out"
	if [ "$CI_LAST_EXIT" -ne 0 ]; then
		ci_fail "export exited $CI_LAST_EXIT"
		ci_print_export_failure_log "$CI_LAST_LOG"
		ci_report "export result=fail preset=$_preset exit=$CI_LAST_EXIT"
		return "$CI_FAIL"
	fi
	ci_log_gate "$CI_LAST_LOG" || {
		ci_print_export_failure_log "$CI_LAST_LOG"
		ci_report "export result=fail preset=$_preset reason=engine-errors"
		return "$CI_FAIL"
	}
	if [ ! -s "$_out" ]; then
		ci_fail "export produced no output: $_out"
		ci_note "the engine exited 0 and its log was checked; if --out was relative, it has been resolved against the caller's directory ($PWD), not the scratch copy"
		ci_print_export_failure_log "$CI_LAST_LOG"
		ci_report "export result=fail preset=$_preset reason=no-output"
		return "$CI_FAIL"
	fi

	# The package is more than its main file (Opus recheck finding E3). With
	# binary_format/embed_pck=false Godot writes a sidecar .pck NEXT TO the
	# output, with the output's extension replaced -- measured against the pinned
	# engine: the Linux preset (embed_pck=false) writes "<out>.pck", the Windows
	# preset (which does not declare the key, so the engine default applies) also
	# writes "<name>.pck", and the macOS preset embeds the .pck inside the app
	# bundle in the .zip and writes no sidecar. On Linux the main binary IS the
	# pinned stock template -- its digest identifies no game content at all,
	# while the .pck carries the project -- so hashing only the main file proved
	# nothing about what was built. The sidecar is required when the preset
	# declares it, and hashed whenever it is written.
	_idx="$(ci_preset_index_for "$_cfg" "$_preset" 2>/dev/null)"
	_embed=""
	[ -n "$_idx" ] && _embed="$(ci_preset_field "$_cfg" "$_idx" binary_format/embed_pck 2>/dev/null)"
	_size="$(wc -c <"$_out" 2>/dev/null | tr -d ' ')"
	_sha="$(ci_sha256 "$_out")"
	_pck_note=""
	_pass_msg=""
	_pass_fields=""
	if [ -e "$_pck" ]; then
		if [ ! -s "$_pck" ]; then
			ci_fail "export wrote an empty sidecar .pck: $_pck (the package carries no project data)"
			ci_report "export result=fail preset=$_preset reason=empty-pck"
			return "$CI_FAIL"
		fi
		_pck_size="$(wc -c <"$_pck" 2>/dev/null | tr -d ' ')"
		_pck_sha="$(ci_sha256 "$_pck")"
		_pck_note="; pck $_pck ($_pck_size bytes, sha256 $_pck_sha)"
		_pass_msg="PASS (main $_out $_size bytes, sha256 $_sha$_pck_note)"
		_pass_fields="output=$_out bytes=$_size sha256=$_sha pck=$_pck pck_bytes=$_pck_size pck_sha256=$_pck_sha embed_pck=${_embed:-not-declared}"
	elif [ "$_embed" = "false" ]; then
		# Declared, and then missing: the package was not produced as configured.
		ci_fail "export: preset '$_preset' declares binary_format/embed_pck=false but no sidecar .pck was written next to $_out (expected $_pck)"
		ci_note "a package whose .pck is missing carries no project data; do not treat the main file alone as the build"
		ci_report "export result=fail preset=$_preset reason=missing-pck output=$_out bytes=$_size"
		return "$CI_FAIL"
	else
		_pck_note="; no sidecar .pck was written (binary_format/embed_pck=${_embed:-not declared}; the macOS preset embeds the .pck inside the app bundle)"
		_pass_msg="PASS (main $_out $_size bytes, sha256 $_sha$_pck_note)"
		_pass_fields="output=$_out bytes=$_size sha256=$_sha embed_pck=${_embed:-not-declared} sidecar_pck=absent"
	fi

	# Re-read the produced package with the project's own pack inventory
	# (tools/export_smoke/lib/pack_inventory.py): it verifies the .pck parses,
	# every pack entry's MD-5 matches its bytes, no excluded development-only
	# path reappeared and every required runtime resource is present. This makes
	# E4 an actual check on packages CI uploads, not only on export-smoke runs.
	# --snapshot is deliberately omitted: CI exports the clean checkout, while
	# byte-for-byte source comparison belongs to the frozen export-smoke
	# candidate. The report goes under $CI_OUT/reports, which the narrowed
	# export-logs artifact uploads.
	_inv_plat=""
	_inv_platform_line="$(ci_preset_table "$_cfg" 2>/dev/null | awk -F'\t' -v n="$_preset" '$2 == n { print $3; exit }')"
	case "$_inv_platform_line" in
		macOS) _inv_plat=macOS ;;
		"Windows Desktop") _inv_plat=Windows ;;
		Linux) _inv_plat=Linux ;;
	esac
	_inv_script="$CI_TOOLS_DIR/../export_smoke/lib/pack_inventory.py"
	[ -f "$_inv_script" ] || _inv_script="$CI_PROJECT/tools/export_smoke/lib/pack_inventory.py"
	if [ -z "$_inv_plat" ]; then
		ci_fail "export: cannot map preset '$_preset' to a pack-inventory platform"
		ci_report "export result=fail preset=$_preset reason=unknown-inventory-platform"
		return "$CI_FAIL"
	fi
	if [ ! -f "$_inv_script" ]; then
		ci_fail "export: package inventory tool is missing: $_inv_script (cannot verify the package contents)"
		ci_report "export result=fail preset=$_preset reason=inventory-tool-missing"
		return "$CI_FAIL"
	fi
	if ! command -v python3 >/dev/null 2>&1; then
		ci_fail "export: python3 is required to run the package inventory check ($_inv_script)"
		ci_report "export result=fail preset=$_preset reason=no-python3"
		return "$CI_FAIL"
	fi
	# Bind the inventory evidence to the source revision when one was supplied
	# (--source-sha). The SHA is also in this run's report header; putting it in
	# the inventory filename means a downloaded artifact names its source even
	# though tools/export_smoke (not owned here) writes the file itself.
	_inv_tag="$_slug"
	_sha_tag="$(printf '%s' "${ROADSTORM_SOURCE_SHA:-}" | tr -c '[:alnum:]-' '-' | cut -c 1-12)"
	[ -n "$_sha_tag" ] && _inv_tag="${_inv_tag}-${_sha_tag}"
	# Same per-attempt token as this invocation's report, so an inventory can
	# always be associated with the attempt that produced it -- including a
	# failed attempt (Sol recheck 675ec1c finding 2). Earlier attempts keep
	# their own distinct files as history; they cannot masquerade as this one.
	[ -n "$CI_ATTEMPT_ID" ] && _inv_tag="${_inv_tag}-${CI_ATTEMPT_ID}"
	_inv_report="$CI_OUT/reports/export-package-inventory-${_inv_tag}.txt"
	mkdir -p "$(dirname "$_inv_report")" 2>/dev/null || ci_die "cannot create report directory for $_inv_report"
	# Do NOT pre-create, pre-check or reserve this pathname: the smoke owner's
	# CLI creates --report with O_CREAT|O_EXCL and refuses any existing regular
	# file, directory or symlink. Pre-creating it here would make every export
	# fail after the handoff. The checker therefore owns the success identity;
	# ci.sh only validates what it produced and writes failure evidence under a
	# separate, exclusively created name.
	_inv_out="$(python3 "$_inv_script" check --platform "$_inv_plat" --main "$_out" --report "$_inv_report" --quiet 2>&1)"
	_inv_rc=$?
	if [ "$_inv_rc" -ne 0 ]; then
		_fr="$(ci_new_evidence_file "$CI_OUT/reports")" || {
			ci_fail "export: package inventory check failed and no exclusive failure evidence path could be reserved"
			ci_report "export result=fail preset=$_preset reason=pack-inventory-no-evidence"
			return "$CI_FAIL"
		}
		{
			printf 'verdict=FAIL\n'
			printf 'reason=checker-failed\n'
			printf 'attempt_id=%s\n' "$CI_ATTEMPT_ID"
			printf 'source_sha=%s\n' "${ROADSTORM_SOURCE_SHA:-not recorded}"
			printf 'preset=%s\n' "$_preset"
			printf 'platform=%s\n' "$_inv_plat"
			printf 'checker_exit=%s\n' "$_inv_rc"
			printf 'inventory_report_path=%s\n' "$_inv_report"
			printf 'checker_output_start:\n%s\nchecker_output_end:\n' "$_inv_out"
		} >"$_fr" 2>/dev/null
		ci_fail "export: package inventory check FAILED for preset '$_preset' ($_inv_plat); distinct FAIL evidence: $_fr"
		printf '%s\n' "$_inv_out" | sed 's/^/    /'
		ci_report "export result=fail preset=$_preset reason=pack-inventory inventory_report=none inventory_failure_record=$_fr"
		return "$CI_FAIL"
	fi
	# Exit 0 alone is insufficient: require a regular non-symlink report created
	# by THIS checker invocation (the exclusive-create contract), carrying the
	# expected platform/main identity and an explicit PASS verdict. Never read,
	# append to or stamp a prior PASS file by pathname.
	if [ -L "$_inv_report" ] || [ ! -f "$_inv_report" ] || [ ! -s "$_inv_report" ] ||
		! grep -q "^platform=$_inv_plat$" "$_inv_report" 2>/dev/null ||
		! grep -q "^main=$(basename "$_out")$" "$_inv_report" 2>/dev/null ||
		! grep -q '^verdict=PASS$' "$_inv_report" 2>/dev/null; then
		_fr="$(ci_new_evidence_file "$CI_OUT/reports")" || {
			ci_fail "export: inventory checker exited 0 without attributable PASS evidence and no failure evidence path could be reserved"
			ci_report "export result=fail preset=$_preset reason=inventory-no-evidence"
			return "$CI_FAIL"
		}
		{
			printf 'verdict=FAIL\n'
			printf 'reason=missing-or-invalid-checker-report\n'
			printf 'attempt_id=%s\n' "$CI_ATTEMPT_ID"
			printf 'source_sha=%s\n' "${ROADSTORM_SOURCE_SHA:-not recorded}"
			printf 'preset=%s\n' "$_preset"
			printf 'platform=%s\n' "$_inv_plat"
			printf 'checker_exit=0\n'
			printf 'inventory_report_path=%s\n' "$_inv_report"
		} >"$_fr" 2>/dev/null
		ci_fail "export: inventory checker exited 0 but left no current-attempt PASS report; FAIL evidence: $_fr"
		ci_report "export result=fail preset=$_preset reason=invalid-inventory-report inventory_report=$_inv_report inventory_failure_record=$_fr"
		return "$CI_FAIL"
	fi
	# Separate, exclusively created identity/evidence companion for the success
	# report (the checker owns that file and does not append arbitrary fields).
	_inv_meta="$(ci_new_evidence_file "$CI_OUT/reports")" || {
		ci_fail "export: cannot reserve inventory identity evidence"
		ci_report "export result=fail preset=$_preset reason=inventory-evidence-unavailable"
		return "$CI_FAIL"
	}
	{
		printf 'verdict=PASS\n'
		printf 'attempt_id=%s\n' "$CI_ATTEMPT_ID"
		printf 'source_sha=%s\n' "${ROADSTORM_SOURCE_SHA:-not recorded}"
		printf 'preset=%s\n' "$_preset"
		printf 'platform=%s\n' "$_inv_plat"
		printf 'inventory_report=%s\n' "$_inv_report"
	} >"$_inv_meta" 2>/dev/null

	# Emit PASS only AFTER the package itself and its inventory have both
	# succeeded. Printing or recording a passing verdict first let a rejected
	# package look successful and left it eligible for the package upload
	# (Sol recheck 8c6c928).
	ci_ok "export: $_pass_msg"
	ci_ok "export: package inventory passed ($_inv_plat; report $_inv_report)"
	if ! ci_report "export result=pass preset=$_preset mode=$_mode $_pass_fields pack_inventory=pass platform=$_inv_plat report=$_inv_report"; then
		ci_fail "export: the passing verdict could not be appended to $CI_REPORT; refusing to report an unrecorded pass"
		return "$CI_FAIL"
	fi

	ci_note "This is a locally built package, not a verified release: launching it on the target OS (PLAN.md M9.2) and signing/notarization (M9.3) are separate steps."
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
	__export-inner) ci_export_build_inner "$@" ;;
	verify-engine) cmd_verify_engine "$@" ;;
	verify-templates) cmd_verify_templates "$@" ;;
	install-templates) cmd_install_templates "$@" ;;
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
[ -n "$CI_REPORT" ] && [ -z "${ROADSTORM_CI_REPORT:-}" ] && ci_info "report: $CI_REPORT" >&2
exit "$_rc"
