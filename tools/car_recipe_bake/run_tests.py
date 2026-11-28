#!/usr/bin/env python3
"""Bounded private tests for the M0.2 handling bake CLI.

Runs the real command-line path against the committed checker and the pinned
Godot build under the shared coordinator lock:

* positive finite-yaw source fixture;
* positive unlimited-yaw source fixture;
* negative null motor input (checker refusal);
* negative historical 1.0.0 recipe (motor-ready dispatch refusal);
* negative stale canonical content hash (the intentional failure control,
  asserting a nonzero exit and no success manifest);
* refusal to write into an existing destination directory or dangling symlink.

Every positive case also proves the pinned engine reloaded the emitted `.tres`
through ``ResourceLoader`` and revalidated it, because that round trip is part
of the CLI's engine step and its result is bound into the manifest.

Standard library only. The runner writes only to its own temporary workspace
and exits nonzero when any case fails.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable, Sequence

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[1]
BAKE_CLI = TOOL_DIR / "bake_handling_recipe.py"
FIXTURE_DIR = TOOL_DIR / "fixtures"
ENGINE_PIN_PATH = REPO_ROOT / "tools" / "toolchain" / "pin" / "engine.txt"


class CaseFailure(RuntimeError):
    pass


class Runner:
    def __init__(self, timeout: int, godot_bin: str | None, workspace: Path) -> None:
        self.timeout = timeout
        self.godot_bin = godot_bin
        self.workspace = workspace
        self.passed = 0
        self.failed = 0
        self.failures: list[str] = []

    def run(self, name: str, body: Callable[[], None]) -> None:
        print(f"[case] {name}")
        try:
            body()
        except Exception as exc:  # a test defect is a failing case
            self.failed += 1
            detail = f"{type(exc).__name__}: {exc}"
            self.failures.append(f"{name}: {detail}")
            print(f"  FAIL {detail}")
        else:
            self.passed += 1
            print("  PASS")

    def bake(
        self,
        recipe: Path,
        output_dir: Path,
        *,
        expect_success: bool,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            sys.executable,
            str(BAKE_CLI),
            "--recipe",
            str(recipe),
            "--output-dir",
            str(output_dir),
            "--timeout",
            str(self.timeout),
        ]
        if self.godot_bin:
            command += ["--godot-bin", self.godot_bin]
        print("  $ " + " ".join(command))
        process = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=max(self.timeout * 3, 120),
            check=False,
        )
        output = (process.stdout or "") + "\n" + (process.stderr or "")
        if expect_success and process.returncode != 0:
            raise CaseFailure(
                f"bake exited {process.returncode}, expected 0:\n{output}"
            )
        if not expect_success and process.returncode == 0:
            raise CaseFailure("bake exited 0, expected a refusal")
        return process


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CaseFailure(message)


def _pinned_version() -> str:
    for line in ENGINE_PIN_PATH.read_text(encoding="utf-8").splitlines():
        if line.startswith("version_string="):
            return line.split("=", 1)[1].strip()
    raise CaseFailure(f"could not read pinned engine version from {ENGINE_PIN_PATH}")


def _sha256(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _check_positive(
    runner: Runner,
    fixture_name: str,
    expected_definition_id: str,
    expected_revision: str,
    expected_status: str,
    expected_mapping: dict[str, Any],
    case_name: str,
) -> None:
    fixture = FIXTURE_DIR / "positive" / fixture_name
    output_dir = runner.workspace / f"out-{case_name}"

    def body() -> None:
        process = runner.bake(fixture, output_dir, expect_success=True)
        _require(process.returncode == 0, "bake did not exit 0")
        _require(output_dir.is_dir(), "success did not create the new output directory")

        manifest_path = output_dir / "bake_manifest.json"
        resource_path = output_dir / "handling.tres"
        _require(manifest_path.is_file(), "success manifest is missing")
        _require(resource_path.is_file(), "baked .tres is missing")

        manifest = _load_json(manifest_path)
        fixture_document = _load_json(fixture)

        _require(
            manifest.get("source_schema_version") == "1.1.0",
            f"source schema version is {manifest.get('source_schema_version')!r}",
        )
        _require(
            manifest.get("source_contract") == "roadstorm.handling_config.1.1.0",
            f"source contract is {manifest.get('source_contract')!r}",
        )
        _require(
            manifest.get("source_content_hash") == fixture_document.get("content_hash"),
            "manifest source content hash does not match the checked fixture",
        )
        _require(
            manifest.get("source_file_sha256") == _sha256(fixture),
            "manifest raw source SHA-256 does not match the fixture file",
        )
        _require(
            manifest.get("handling_definition_id") == expected_definition_id,
            f"derived definition id is {manifest.get('handling_definition_id')!r}",
        )
        _require(
            manifest.get("handling_revision") == expected_revision,
            f"revision is {manifest.get('handling_revision')!r}",
        )
        _require(
            manifest.get("handling_status") == expected_status,
            f"status is {manifest.get('handling_status')!r}",
        )
        _require(
            manifest.get("typed_schema_version") == "1.0.0",
            f"typed schema version is {manifest.get('typed_schema_version')!r}",
        )
        _require(
            manifest.get("engine_version") == _pinned_version(),
            f"engine version is {manifest.get('engine_version')!r}",
        )
        _require(
            manifest.get("resource_file") == "handling.tres",
            f"resource_file is {manifest.get('resource_file')!r}",
        )
        _require(
            manifest.get("resource_sha256") == _sha256(resource_path),
            "manifest .tres SHA-256 does not match the emitted file",
        )
        _require(
            manifest.get("mapping") == expected_mapping,
            f"mapping summary is {manifest.get('mapping')!r}",
        )

        round_trip = manifest.get("round_trip")
        _require(isinstance(round_trip, dict), "manifest has no round_trip object")
        _require(round_trip.get("ok") is True, "manifest round trip is not ok")
        _require(
            round_trip.get("validated") is True,
            "reloaded .tres did not pass validate()",
        )
        _require(
            isinstance(round_trip.get("fields_compared"), int)
            and round_trip["fields_compared"] >= 18,
            f"round-trip field count is {round_trip.get('fields_compared')!r}",
        )

        resource_text = resource_path.read_text(encoding="utf-8")
        _require(
            'script_class="HandlingDefinition"' in resource_text,
            "emitted .tres does not carry the HandlingDefinition script class",
        )

    runner.run(case_name, body)


def _check_negative(
    runner: Runner,
    fixture_name: str,
    case_name: str,
    expected_marker: str,
    *,
    failure_control: bool = False,
) -> None:
    fixture = FIXTURE_DIR / "negative" / fixture_name
    output_dir = runner.workspace / f"out-{case_name}"

    def body() -> None:
        process = runner.bake(fixture, output_dir, expect_success=False)
        _require(process.returncode != 0, "refusal exit code must be nonzero")
        output = (process.stdout or "") + "\n" + (process.stderr or "")
        _require(
            expected_marker in output,
            f"diagnostic {expected_marker!r} was not reported:\n{output}",
        )
        _require(
            not output_dir.exists(),
            "a refused bake left an output destination behind",
        )
        if failure_control:
            _require(
                not (output_dir / "bake_manifest.json").exists(),
                "intentional failure control produced a success manifest",
            )

    runner.run(case_name, body)


def _check_existing_destination_refusal(runner: Runner) -> None:
    fixture = FIXTURE_DIR / "positive" / "finite.json"
    output_dir = runner.workspace / "out-existing-destination"
    output_dir.mkdir(parents=True)
    sentinel = output_dir / "sentinel.txt"
    sentinel.write_text("do-not-modify\n", encoding="utf-8")

    def body() -> None:
        runner.bake(fixture, output_dir, expect_success=False)
        _require(sentinel.read_text(encoding="utf-8") == "do-not-modify\n", "destination was modified")
        _require(
            not (output_dir / "bake_manifest.json").exists(),
            "existing destination gained a success manifest",
        )
        _require(
            not (output_dir / "handling.tres").exists(),
            "existing destination gained a baked .tres",
        )

    runner.run("existing destination is not written", body)


def _check_existing_symlink_refusal(runner: Runner) -> None:
    fixture = FIXTURE_DIR / "positive" / "finite.json"
    target = runner.workspace / "missing-symlink-target"
    output_link = runner.workspace / "out-existing-symlink"
    output_link.symlink_to(target, target_is_directory=True)

    def body() -> None:
        runner.bake(fixture, output_link, expect_success=False)
        _require(output_link.is_symlink(), "existing output symlink was removed")
        _require(not target.exists(), "a dangling output symlink target was created")

    runner.run("existing dangling destination symlink is refused", body)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="outer seconds per engine invocation passed to the CLI (default: 300)",
    )
    parser.add_argument("--godot-bin", default=None, help="Godot executable override")
    parser.add_argument(
        "--keep-workspace",
        action="store_true",
        help="keep the temporary workspace for inspection",
    )
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")

    workspace = Path(tempfile.mkdtemp(prefix="car-recipe-bake-tests-"))
    runner = Runner(args.timeout, args.godot_bin, workspace)
    try:
        _check_positive(
            runner,
            "finite.json",
            "car.bake_probe_finite.handling",
            "0.1.0",
            "example",
            {"curve_points": 2, "max_yaw_rate_rad_s": "finite"},
            "finite source bakes and round-trips",
        )
        _check_positive(
            runner,
            "unlimited.json",
            "car.bake_probe_unlimited.handling",
            "1.2.0",
            "provisional",
            {"curve_points": 3, "max_yaw_rate_rad_s": "INF"},
            "unlimited source bakes and round-trips",
        )
        _check_negative(
            runner,
            "null_motor_input.json",
            "null motor input is refused",
            "motor-input-unresolved",
        )
        _check_negative(
            runner,
            "version_1_0_0.json",
            "historical 1.0.0 recipe is refused",
            "motor-input-missing",
        )
        _check_negative(
            runner,
            "stale_content_hash.json",
            "failure control: stale content hash",
            "content-hash-mismatch",
            failure_control=True,
        )
        _check_existing_destination_refusal(runner)
        _check_existing_symlink_refusal(runner)
    finally:
        if args.keep_workspace:
            print(f"[tests] workspace kept at {workspace}")
        else:
            shutil.rmtree(workspace, ignore_errors=True)

    print(f"\n[tests] passed={runner.passed} failed={runner.failed}")
    for failure in runner.failures:
        print(f"[tests] FAILED {failure}")
    return 0 if runner.failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
