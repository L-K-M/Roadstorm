#!/usr/bin/env python3
"""M0.2 handling bake CLI for one motor-ready version-1.1.0 source recipe.

This is the bounded M0.2 slice described in
docs/evidence/m02-typed-runtime-mapping-20261127.md: one explicit path from a
single checked JSON recipe to one validated ``HandlingDefinition`` ``.tres``
plus a machine-readable bake manifest in a new user-specified directory.

Pipeline, in order:

1. Refuse an existing output destination before doing any work.
2. Freeze the source bytes privately, then run the committed standard-library
   checker on that exact copy in ``motor-ready`` mode
   (strict JSON, canonical content hash, null/unknown honesty, identity
   preflight).
3. Hash that same accepted copy and bind its bytes to the manifest.
4. Verify the selected engine is the pinned Godot build.
5. Stage a private copy of the project, run the pinned engine headlessly under
   the shared coordinator Godot lock, load the checked recipe, call
   ``HandlingRecipeMapper.map_handling``, run ``HandlingDefinition.validate()``,
   serialize the ``.tres`` and reload it through ``ResourceLoader``.
6. Re-read the submitted lexical ``--recipe`` path, following any symlinked
   leaf or parent at that moment, and require the frozen source bytes. The
   manifest records the submitted path and the target it resolved to, so a
   link retargeted during the bake can never be published under the old bytes.
7. Copy the verified ``.tres`` into the new output directory and write the
   manifest last. Any failure leaves no output directory or manifest.

The submitted ``--recipe`` path is kept absolute but unresolved. Symlinks in
the leaf or in a parent directory are followed when bytes are read, both for
the private snapshot and for the final pre-publication recheck, so what gets
published is always bound to the bytes the submitted path holds at that moment.

Standard library only. This does not build a ``CarDefinition``, does not add
game import/cache state, does not author production content and does not claim
M0.2 completion or release-rights clearance.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[1]
CHECKER_PATH = REPO_ROOT / "tools" / "car_recipe_schema" / "validate_car_recipe.py"
ENGINE_PIN_PATH = REPO_ROOT / "tools" / "toolchain" / "pin" / "engine.txt"
LOCK_PATH = REPO_ROOT / "work" / "agents" / "coordinator" / "godot-test.lock"
BAKE_SCRIPT_RES = "res://tools/car_recipe_bake/bake_handling.gd"
PROJECT_WORK_RES = "car_recipe_bake_work"

SOURCE_CONTRACT_PREFIX = "roadstorm.handling_config."
EXPECTED_SOURCE_VERSION = "1.1.0"
TYPED_SCHEMA_VERSION = "1.0.0"
MANIFEST_VERSION = "1.0"
STATUSES = ("provisional", "measured", "frozen", "superseded", "example")

DEFINITION_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_-]+)*$")
REVISION_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")

STAGE_ITEMS = ("project.godot", "src", "scenes", "tools/car_recipe_bake")
STAGE_IGNORE = shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store")

OUTPUT_RESOURCE_NAME = "handling.tres"
OUTPUT_MANIFEST_NAME = "bake_manifest.json"

## Every numeric scalar `HandlingDefinition` field the committed mapper
## consumes, as dotted source paths. The two acceleration-curve arrays are
## handled separately because their length is dynamic.
NUMERIC_SCALAR_PATHS = (
    "handling.braking_acceleration_m_s2",
    "handling.drag.aerodynamic",
    "handling.drag.rolling",
    "handling.yaw_gain.grip",
    "handling.max_yaw_rate_rad_s",
    "handling.lateral_damping.grip_per_s",
    "handling.reverse_trigger_speed_m_s",
    "handling.reverse_hold_time_s",
    "handling.reverse_acceleration_m_s2",
    "handling.reverse_top_speed_m_s",
)
UNLIMITED_YAW_PATH = "handling.max_yaw_rate_rad_s"
BINARY64_HEX_LENGTH = 16
BINARY64_HEX_RE = re.compile(r"[0-9a-f]{%d}" % BINARY64_HEX_LENGTH)

ERROR_SCAN = ("SCRIPT ERROR", "Parse Error", "Failed to load script")


class BakeError(RuntimeError):
    """A refusal or failure that must leave no successful output."""


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        return _run(args)
    except BakeError as exc:
        print(f"[car-recipe-bake] error: {exc}", file=sys.stderr)
        return 1
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"[car-recipe-bake] error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("[car-recipe-bake] interrupted", file=sys.stderr)
        return 1


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Bake one motor-ready handling source recipe (schema 1.1.0) into "
            "a validated HandlingDefinition .tres and a bake manifest."
        )
    )
    parser.add_argument("--recipe", required=True, help="source recipe JSON file")
    parser.add_argument(
        "--output-dir",
        required=True,
        help="new output directory; it must not already exist",
    )
    parser.add_argument(
        "--godot-bin",
        default=None,
        help="Godot executable (default: $GODOT_BIN, then 'godot' on PATH)",
    )
    parser.add_argument(
        "--timeout",
        type=_positive_int,
        default=300,
        help="outer seconds per pinned-engine invocation (default: 300)",
    )
    return parser


def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def _run(args: argparse.Namespace) -> int:
    # Keep the submitted lexical path absolute but unresolved: a symlinked
    # leaf or parent must still be re-read exactly as the user named it at the
    # final recheck, and the manifest must not silently substitute a canonical
    # target for the --recipe argument.
    recipe_path = _absolute_lexical(Path(args.recipe).expanduser())
    # Do not resolve the leaf: an existing symlink, including a dangling one,
    # is an existing destination and must be refused.
    output_dir = Path(args.output_dir).expanduser().absolute()

    # Refusal happens before any engine or filesystem output work.
    if os.path.lexists(output_dir):
        raise BakeError(f"refusing to write to existing destination: {output_dir}")

    if not CHECKER_PATH.is_file():
        raise BakeError(f"committed checker is missing: {CHECKER_PATH}")

    if not os.path.lexists(recipe_path):
        raise BakeError(f"source recipe does not exist: {recipe_path}")

    scratch = Path(tempfile.mkdtemp(prefix="car-recipe-bake-"))
    try:
        # One private byte snapshot is the input to every checker, mapper and
        # hash step. A mutable original path cannot change the accepted recipe
        # between the Python checker and Godot. The submitted lexical path is
        # re-read just before publication so a retargeted link is also
        # reported as a refusal.
        frozen_recipe = scratch / "checked_recipe.json"
        frozen_recipe.write_bytes(_read_submitted_source(recipe_path))
        checker = subprocess.run(
            [
                sys.executable,
                str(CHECKER_PATH),
                "--mode",
                "motor-ready",
                "--root",
                str(REPO_ROOT),
                str(frozen_recipe),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if checker.stdout:
            sys.stdout.write(checker.stdout)
        if checker.returncode != 0:
            if checker.stderr:
                sys.stderr.write(checker.stderr)
            raise BakeError(
                f"source checker refused the recipe (exit {checker.returncode})"
            )

        source_content_hash, source_file_sha256, converted_document = (
            _hash_source_with_committed_tool(frozen_recipe)
        )
        expected_numeric_bits = _expected_numeric_bits(converted_document)
        godot_bin = _resolve_godot(args.godot_bin)
        engine_version = _verify_engine(godot_bin, args.timeout)
        project_dir, cache_env = _prepare_private_project(scratch)
        _run_engine_import(godot_bin, project_dir, cache_env, args.timeout)
        _run_engine_bake(godot_bin, project_dir, cache_env, args.timeout, frozen_recipe)
        _require_source_unchanged(frozen_recipe, source_file_sha256)
        report = _read_and_validate_report(project_dir, expected_numeric_bits)
        resource_bytes, resource_sha256 = _read_emitted_resource(project_dir)
        # Final trust boundary: re-read exactly what the user submitted,
        # following any symlinked leaf or parent at this moment, and require
        # the frozen bytes before anything is published.
        resolved_target = _require_source_unchanged(recipe_path, source_file_sha256)
        manifest = _build_manifest(
            args, recipe_path, resolved_target, source_content_hash,
            source_file_sha256, engine_version, report, resource_sha256,
        )
        _publish_outputs(output_dir, resource_bytes, manifest)
        print(
            "[car-recipe-bake] baked %s -> %s (%s)"
            % (report["definition_id"], output_dir / OUTPUT_RESOURCE_NAME, resource_sha256)
        )
        return 0
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


# --- Source hashing ----------------------------------------------------------


def _load_committed_checker() -> Any:
    spec = importlib.util.spec_from_file_location(
        "_roadstorm_committed_validate_car_recipe", CHECKER_PATH
    )
    if spec is None or spec.loader is None:
        raise BakeError(f"could not load committed checker module: {CHECKER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _hash_source_with_committed_tool(
    recipe_path: Path,
) -> tuple[str, str, dict[str, Any]]:
    """Return (content hash, raw SHA-256, binary64-converted document).

    The converted document uses the committed checker's ``to_binary64``
    policy, so the expected-value derivation below sees exactly the binary64
    values the checker accepts. The raw hash still binds the frozen bytes.
    """
    checker = _load_committed_checker()
    document, findings = checker.load_json_document(recipe_path)
    if document is None:
        detail = "; ".join(str(finding) for finding in findings) or "unreadable"
        raise BakeError(f"committed checker could not load recipe: {detail}")
    try:
        converted = checker.to_binary64(document)
        computed = checker.content_hash_of(document)
    except Exception as exc:  # CanonicalizationError and parse helpers
        raise BakeError(f"could not convert/hash the source recipe: {exc}") from exc
    recorded = document.get("content_hash")
    if recorded != computed:
        raise BakeError(
            "canonical source content hash disagrees with the recorded hash: "
            f"{computed} != {recorded!r}"
        )
    raw = recipe_path.read_bytes()
    return computed, "sha256:" + hashlib.sha256(raw).hexdigest(), converted


# --- Checker-to-Godot numeric fidelity --------------------------------------


def _binary64_hex(value: float) -> str:
    """Little-endian binary64 byte image as lowercase hex."""
    if math.isnan(value):
        raise BakeError("checked recipe produced NaN for a consumed numeric field")
    return struct.pack("<d", value).hex()


def _expected_numeric_bits(document: dict[str, Any]) -> dict[str, str]:
    """Derive the consumed numeric values from the frozen source document.

    Paths mirror the committed mapper's source contract. Acceleration-curve
    entries carry both array members; ``{"unlimited": true}`` yaw is binary64
    positive infinity. The result is compared bit-for-bit with the pinned
    engine's report before anything is published.
    """
    handling = document.get("handling")
    if not isinstance(handling, dict):
        raise BakeError("checked recipe has no handling object")

    bits: dict[str, str] = {}
    curve = handling.get("acceleration_curve")
    if not isinstance(curve, list):
        raise BakeError("checked recipe has no acceleration_curve array")
    for index, point in enumerate(curve):
        if not isinstance(point, dict):
            raise BakeError(f"handling.acceleration_curve[{index}] is not an object")
        for member in ("speed_m_s", "acceleration_m_s2"):
            path = f"handling.acceleration_curve[{index}].{member}"
            if member not in point:
                raise BakeError(f"checked recipe is missing {path}")
            bits[path] = _binary64_hex(float(point[member]))

    for dotted in NUMERIC_SCALAR_PATHS:
        node: Any = document
        for segment in dotted.split("."):
            if not isinstance(node, dict) or segment not in node:
                raise BakeError(f"checked recipe is missing {dotted}")
            node = node[segment]
        if dotted == UNLIMITED_YAW_PATH and isinstance(node, dict):
            if set(node.keys()) != {"unlimited"} or node["unlimited"] is not True:
                raise BakeError(f"{dotted}: unsupported unlimited-yaw encoding")
            value = math.inf
        else:
            value = float(node)
        bits[dotted] = _binary64_hex(value)
    return bits


def _verify_numeric_fidelity(
    report: dict[str, Any], expected_bits: dict[str, str]
) -> None:
    """Refuse unless the engine report's numeric bits match the source exactly.

    Equality is between exact little-endian binary64 byte images at each
    dotted path. Missing fields, extra fields, malformed hex and any differing
    bit pattern all refuse with a diagnostic naming the path.
    """
    actual = report.get("numeric_source_bits")
    if not isinstance(actual, dict):
        raise BakeError("engine report has no numeric_source_bits mapping")

    expected_paths = set(expected_bits)
    actual_paths = set(actual)
    missing = sorted(expected_paths - actual_paths)
    if missing:
        raise BakeError(
            "engine report numeric_source_bits is missing fields: " + ", ".join(missing)
        )
    extra = sorted(actual_paths - expected_paths)
    if extra:
        raise BakeError(
            "engine report numeric_source_bits has unexpected fields: " + ", ".join(extra)
        )

    for path in sorted(expected_paths):
        encoded = actual[path]
        if not isinstance(encoded, str) or BINARY64_HEX_RE.fullmatch(encoded) is None:
            raise BakeError(f"{path}: malformed numeric bit encoding: {encoded!r}")
        if encoded != expected_bits[path]:
            raise BakeError(
                f"{path}: numeric-conversion-mismatch: expected source binary64 "
                f"{expected_bits[path]}, engine reported {encoded}"
            )


# --- Engine ------------------------------------------------------------------


def _absolute_lexical(path: Path) -> Path:
    """Absolute form of a submitted path without resolving any symlink."""
    if path.is_absolute():
        return path
    return Path.cwd() / path


def _read_submitted_source(recipe_path: Path) -> bytes:
    """Read the submitted lexical path, following symlinks at this moment."""
    try:
        return recipe_path.read_bytes()
    except OSError as exc:
        detail = str(exc)
        if recipe_path.is_symlink():
            try:
                detail += f" (symlink target: {os.readlink(recipe_path)})"
            except OSError:
                pass
        raise BakeError(
            f"could not read the source recipe at {recipe_path}: {detail}"
        ) from exc


def _resolved_target(path: Path) -> str:
    try:
        return str(path.resolve())
    except OSError:
        return str(path)


def _require_source_unchanged(recipe_path: Path, expected_raw_sha256: str) -> Path:
    """Fail when the source bytes moved between checking/baking and binding.

    ``recipe_path`` is read exactly as named, so a symlinked leaf or parent is
    followed at this moment rather than at snapshot time. The returned path is
    what it resolved to, which the manifest records next to the submitted
    spelling so provenance stays truthful.
    """
    try:
        raw = recipe_path.read_bytes()
    except OSError as exc:
        raise BakeError(f"could not re-read the source recipe after baking: {exc}") from exc
    actual = "sha256:" + hashlib.sha256(raw).hexdigest()
    if actual != expected_raw_sha256:
        raise BakeError(
            "source recipe changed during the bake; refusing to bind the old hash: "
            f"{recipe_path} (resolved to {_resolved_target(recipe_path)})"
        )
    return recipe_path.resolve()


def _resolve_godot(explicit: str | None) -> str:
    candidate = explicit or os.environ.get("GODOT_BIN") or shutil.which("godot")
    if not candidate:
        raise BakeError(
            "no Godot executable found; set GODOT_BIN or put the pinned editor on PATH"
        )
    if not Path(candidate).is_file():
        raise BakeError(f"Godot executable is not a file: {candidate}")
    return candidate


def _pinned_version() -> str:
    for line in ENGINE_PIN_PATH.read_text(encoding="utf-8").splitlines():
        if line.startswith("version_string="):
            version = line.split("=", 1)[1].strip()
            if version:
                return version
    raise BakeError(f"engine pin has no version_string: {ENGINE_PIN_PATH}")


def _isolated_env(cache_root: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["XDG_CACHE_HOME"] = str(cache_root / "cache")
    env["XDG_CONFIG_HOME"] = str(cache_root / "config")
    env["XDG_DATA_HOME"] = str(cache_root / "data")
    env["TMPDIR"] = str(cache_root / "tmp")
    return env


def _run_locked_godot(
    godot_bin: str, godot_args: Sequence[str], timeout: int, env: dict[str, str]
) -> subprocess.CompletedProcess[str]:
    """Run one Godot invocation under the shared coordinator Godot lock."""
    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    command: list[str] = []
    timeout_binary = shutil.which("timeout")
    if timeout_binary:
        command += [timeout_binary, str(timeout)]
    command += [
        "lockf",
        "-k",
        "-w",
        "-t",
        str(timeout),
        str(LOCK_PATH),
        godot_bin,
        *godot_args,
    ]
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        env=env,
        timeout=max(timeout + 30, 60),
        check=False,
    )


def _engine_output(process: subprocess.CompletedProcess[str]) -> str:
    return (process.stdout or "") + "\n" + (process.stderr or "")


def _verify_engine(godot_bin: str, timeout: int) -> str:
    probe_cache = Path(tempfile.mkdtemp(prefix="car-recipe-bake-version-"))
    try:
        env = _isolated_env(probe_cache)
        process = _run_locked_godot(godot_bin, ["--version"], timeout, env)
    finally:
        shutil.rmtree(probe_cache, ignore_errors=True)
    output = _engine_output(process)
    if process.returncode != 0:
        raise BakeError(f"pinned engine --version failed (exit {process.returncode})")
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        raise BakeError("pinned engine --version produced no output")
    actual = lines[-1]
    pinned = _pinned_version()
    if actual != pinned:
        raise BakeError(
            f"engine is not the pinned build: expected '{pinned}', got '{actual}'"
        )
    return actual


# --- Private project staging -------------------------------------------------


def _prepare_private_project(scratch: Path) -> tuple[Path, dict[str, str]]:
    project_dir = scratch / "project"
    project_dir.mkdir(parents=True)
    for item in STAGE_ITEMS:
        source = REPO_ROOT / item
        destination = project_dir / item
        if not source.exists():
            raise BakeError(f"required project input is missing: {source}")
        if source.is_dir():
            shutil.copytree(source, destination, ignore=STAGE_IGNORE)
        else:
            shutil.copy2(source, destination)

    cache_root = scratch / "cache"
    for name in ("cache", "config", "data", "tmp"):
        (cache_root / name).mkdir(parents=True, exist_ok=True)
    return project_dir, _isolated_env(cache_root)


def _check_engine_process(process: subprocess.CompletedProcess[str], stage: str) -> str:
    output = _engine_output(process)
    if process.returncode != 0:
        raise BakeError(f"{stage} failed (exit {process.returncode}):\n{output}")
    for marker in ERROR_SCAN:
        if marker in output:
            raise BakeError(f"{stage} reported an engine script error:\n{output}")
    return output


def _run_engine_import(
    godot_bin: str, project_dir: Path, env: dict[str, str], timeout: int
) -> None:
    process = _run_locked_godot(
        godot_bin,
        ["--headless", "--path", str(project_dir), "--import"],
        timeout,
        env,
    )
    _check_engine_process(process, "private project import")


def _run_engine_bake(
    godot_bin: str,
    project_dir: Path,
    env: dict[str, str],
    timeout: int,
    recipe_path: Path,
) -> None:
    process = _run_locked_godot(
        godot_bin,
        [
            "--headless",
            "--path",
            str(project_dir),
            "--script",
            BAKE_SCRIPT_RES,
            "--",
            "--recipe",
            str(recipe_path),
        ],
        timeout,
        env,
    )
    _check_engine_process(process, "handling bake")


# --- Engine artifacts --------------------------------------------------------


def _read_and_validate_report(
    project_dir: Path, expected_numeric_bits: dict[str, str]
) -> dict[str, Any]:
    report_path = project_dir / PROJECT_WORK_RES / "bake_report.json"
    if not report_path.is_file():
        raise BakeError(f"engine did not write its bake report: {report_path}")
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BakeError(f"could not read engine bake report: {exc}") from exc
    if not isinstance(report, dict):
        raise BakeError("engine bake report is not a JSON object")
    if report.get("ok") is not True:
        diagnostics = report.get("diagnostics", [])
        raise BakeError(
            "engine refused the recipe: " + "; ".join(str(item) for item in diagnostics)
        )

    required_strings = (
        "source_schema_version",
        "typed_schema_version",
        "definition_id",
        "revision",
        "status",
        "display_name",
    )
    for key in required_strings:
        value = report.get(key)
        if not isinstance(value, str) or not value:
            raise BakeError(f"engine report has no valid {key}")

    if report["source_schema_version"] != EXPECTED_SOURCE_VERSION:
        raise BakeError(
            "engine report source version is not the supported "
            f"{EXPECTED_SOURCE_VERSION}: {report['source_schema_version']!r}"
        )
    if report["typed_schema_version"] != TYPED_SCHEMA_VERSION:
        raise BakeError(
            "engine report typed schema version is not "
            f"{TYPED_SCHEMA_VERSION}: {report['typed_schema_version']!r}"
        )
    if not DEFINITION_ID_RE.fullmatch(report["definition_id"]):
        raise BakeError(f"engine report definition_id is malformed: {report['definition_id']!r}")
    if not REVISION_RE.fullmatch(report["revision"]):
        raise BakeError(f"engine report revision is malformed: {report['revision']!r}")
    if report["status"] not in STATUSES:
        raise BakeError(f"engine report status is not a lifecycle name: {report['status']!r}")

    mapping = report.get("mapping")
    if not isinstance(mapping, dict):
        raise BakeError("engine report has no mapping summary")
    curve_points = mapping.get("curve_points")
    if not isinstance(curve_points, int) or curve_points < 1:
        raise BakeError("engine report mapping curve_points is invalid")
    if mapping.get("max_yaw_rate_rad_s") not in ("finite", "INF"):
        raise BakeError("engine report mapping max_yaw_rate_rad_s is invalid")

    round_trip = report.get("round_trip")
    if not isinstance(round_trip, dict):
        raise BakeError("engine report has no round-trip result")
    if round_trip.get("ok") is not True or round_trip.get("validated") is not True:
        raise BakeError("engine report does not prove a validated ResourceLoader round trip")
    if not isinstance(round_trip.get("fields_compared"), int) or round_trip["fields_compared"] <= 0:
        raise BakeError("engine report round-trip field count is invalid")

    diagnostics = report.get("diagnostics")
    if not isinstance(diagnostics, list) or diagnostics:
        raise BakeError("engine report success carries diagnostics")

    _verify_numeric_fidelity(report, expected_numeric_bits)
    return report


def _read_emitted_resource(project_dir: Path) -> tuple[bytes, str]:
    resource_path = project_dir / PROJECT_WORK_RES / OUTPUT_RESOURCE_NAME
    if not resource_path.is_file():
        raise BakeError(f"engine did not emit {OUTPUT_RESOURCE_NAME}: {resource_path}")
    data = resource_path.read_bytes()
    if not data:
        raise BakeError("engine emitted an empty .tres")
    if not data.lstrip().startswith(b"[gd_resource"):
        raise BakeError("engine output is not a Godot text resource")
    return data, "sha256:" + hashlib.sha256(data).hexdigest()


# --- Manifest and publication ------------------------------------------------


def _build_manifest(
    args: argparse.Namespace,
    recipe_path: Path,
    resolved_target: Path,
    source_content_hash: str,
    source_file_sha256: str,
    engine_version: str,
    report: dict[str, Any],
    resource_sha256: str,
) -> dict[str, Any]:
    source_version = report["source_schema_version"]
    return {
        "manifest_version": MANIFEST_VERSION,
        "tool": "tools/car_recipe_bake/bake_handling_recipe.py",
        "source_contract": SOURCE_CONTRACT_PREFIX + source_version,
        "source_schema_version": source_version,
        "source_checker": "tools/car_recipe_schema/validate_car_recipe.py --mode motor-ready",
        "source_recipe": str(recipe_path),
        "source_resolved_target": str(resolved_target),
        "source_content_hash": source_content_hash,
        "source_file_sha256": source_file_sha256,
        "handling_definition_id": report["definition_id"],
        "handling_revision": report["revision"],
        "handling_status": report["status"],
        "handling_display_name": report["display_name"],
        "typed_schema_version": report["typed_schema_version"],
        "resource_file": OUTPUT_RESOURCE_NAME,
        "resource_sha256": resource_sha256,
        "engine_version": engine_version,
        "mapping": report["mapping"],
        "round_trip": report["round_trip"],
        "generated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def _publish_outputs(
    output_dir: Path, resource_bytes: bytes, manifest: dict[str, Any]
) -> None:
    created = False
    try:
        os.makedirs(output_dir)
        created = True

        resource_destination = output_dir / OUTPUT_RESOURCE_NAME
        resource_destination.write_bytes(resource_bytes)
        destination_hash = "sha256:" + hashlib.sha256(resource_destination.read_bytes()).hexdigest()
        if destination_hash != manifest["resource_sha256"]:
            raise BakeError("copied .tres does not match the engine-emitted hash")

        manifest_destination = output_dir / OUTPUT_MANIFEST_NAME
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=".bake_manifest.", suffix=".tmp", dir=output_dir
        )
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                json.dump(manifest, handle, indent=2, sort_keys=True)
                handle.write("\n")
            os.replace(temporary_name, manifest_destination)
        except BaseException:
            try:
                os.unlink(temporary_name)
            except OSError:
                pass
            raise
    except BaseException:
        if created:
            _remove_created_output(output_dir)
        raise


def _remove_created_output(output_dir: Path) -> None:
    for name in (OUTPUT_RESOURCE_NAME, OUTPUT_MANIFEST_NAME):
        try:
            (output_dir / name).unlink()
        except OSError:
            pass
    try:
        output_dir.rmdir()
    except OSError:
        pass


if __name__ == "__main__":
    sys.exit(main())
