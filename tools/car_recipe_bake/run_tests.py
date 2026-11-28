#!/usr/bin/env python3
"""Bounded private tests for the M0.2 handling bake CLI.

Runs the real command-line path against the committed checker and the pinned
Godot build under an exclusive portable lock (BSD ``lockf`` or util-linux
``flock``) selected per runner workspace:

* positive finite-yaw source fixture;
* positive unlimited-yaw source fixture;
* negative null motor input (checker refusal);
* negative historical 1.0.0 recipe (motor-ready dispatch refusal);
* negative stale canonical content hash (the intentional failure control,
  asserting a nonzero exit and no success manifest);
* refusal to write into an existing destination directory or dangling symlink;
* a symlinked source path that bakes through to a stable target, recording
  both the submitted spelling and the resolved target;
* a checker-accepted negative-zero `handling.drag.rolling` literal that the
  committed engine round trips through `ResourceSaver`/`ResourceLoader` with
  the opposite sign, refused at its exact source path with no output;
* a deterministic module-boundary seam that retargets a lexical source symlink
  after the final recheck opened and read it but before it resolved the target,
  asserting refusal and the bound target for a stable symlink;
* a submitted symlink retargeted to different bytes between the source
  snapshot and the final recheck, refused with a path-specific diagnostic
  and no output, using a test-only ``--godot-bin`` seam; the same seam also
  retargets a symlinked parent directory of the submitted path;
* a dangling input symlink, refused before any engine work.

Every positive case also proves the pinned engine reloaded the emitted `.tres`
through ``ResourceLoader`` and revalidated it, because that round trip is part
of the CLI's engine step and its result is bound into the manifest.

The end-to-end retargeting seam is a wrapper script passed as ``--godot-bin``;
it only substitutes the engine binary the CLI is told to run and fires inside
the pinned-engine bake invocation, so no sleep-based race is involved. The
in-helper recheck control uses the module-level ``_SOURCE_RECHECK_SEAM`` seam,
which production runs leave unset. No case relies on a sleep race.

Standard library only. The runner writes only to its own temporary workspace
and exits nonzero when any case fails.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable, Sequence

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[1]
BAKE_CLI = TOOL_DIR / "bake_handling_recipe.py"
CHECKER_CLI = REPO_ROOT / "tools" / "car_recipe_schema" / "validate_car_recipe.py"
FIXTURE_DIR = TOOL_DIR / "fixtures"
ENGINE_PIN_PATH = REPO_ROOT / "tools" / "toolchain" / "pin" / "engine.txt"


class CaseFailure(RuntimeError):
    pass


class Runner:
    def __init__(self, timeout: int, godot_bin: str | None, workspace: Path) -> None:
        self.timeout = timeout
        self.godot_bin = godot_bin
        self.workspace = workspace
        # One explicit lock file per runner workspace keeps the suite independent
        # of any live checkout and of concurrent workers.
        self.lock_path = workspace / "godot-test.lock"
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
        godot_bin: str | None = None,
        extra_env: dict[str, str] | None = None,
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
        selected_godot = godot_bin if godot_bin is not None else self.godot_bin
        if selected_godot:
            command += ["--godot-bin", selected_godot]
        command += ["--lock-path", str(self.lock_path)]
        print("  $ " + " ".join(command))
        environment = None
        if extra_env:
            environment = dict(os.environ)
            environment.update(extra_env)
        process = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=max(self.timeout * 3, 120),
            check=False,
            env=environment,
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


def _run_checker(recipe: Path, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(CHECKER_CLI),
        "--mode",
        "motor-ready",
        "--root",
        str(REPO_ROOT),
        str(recipe),
    ]
    print("  $ " + " ".join(command))
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
        timeout=max(timeout, 30),
    )


def _load_bake_cli() -> Any:
    spec = importlib.util.spec_from_file_location(
        "_roadstorm_bake_cli_under_test", BAKE_CLI
    )
    if spec is None or spec.loader is None:
        raise CaseFailure(f"could not load bake CLI module: {BAKE_CLI}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _flip_hex_digit(value: str) -> str:
    replacement = "1" if value[0] != "1" else "2"
    return replacement + value[1:]


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
    caller_home = runner.workspace / (
        "caller-home-" + "".join(c if c.isalnum() else "-" for c in case_name)
    )
    caller_home.mkdir(parents=True, exist_ok=True)
    sentinel = caller_home / "sentinel.txt"
    sentinel.write_text("caller-home-sentinel\n", encoding="utf-8")

    def body() -> None:
        # Point the caller's HOME at a private sentinel directory. The CLI must
        # override HOME for every engine call, so the sentinel has to survive
        # byte-for-byte; any engine artifact written through the inherited HOME
        # would add or change entries here and fail the case.
        process = runner.bake(
            fixture,
            output_dir,
            expect_success=True,
            extra_env={"HOME": str(caller_home)},
        )
        _require(process.returncode == 0, "bake did not exit 0")
        _require(output_dir.is_dir(), "success did not create the new output directory")
        _require(
            sorted(entry.name for entry in caller_home.iterdir()) == ["sentinel.txt"],
            "engine wrote into the caller's HOME despite isolation",
        )
        _require(
            sentinel.read_text(encoding="utf-8") == "caller-home-sentinel\n",
            "caller HOME sentinel was modified",
        )

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


def _check_subnormal_fixture_is_checker_accepted(runner: Runner) -> None:
    fixture = FIXTURE_DIR / "negative" / "subnormal_reverse_acceleration.json"

    def body() -> None:
        process = _run_checker(fixture, timeout=runner.timeout)
        output = (process.stdout or "") + "\n" + (process.stderr or "")
        _require(
            process.returncode == 0,
            "the subnormal fixture must pass the committed motor-ready checker:\n"
            + output,
        )

    runner.run("subnormal reverse acceleration is accepted by the committed checker", body)


def _check_negative_zero_drag_rolling_refusal(runner: Runner) -> None:
    """The checker accepts `-0.0`; the published artifact must not.

    `ResourceSaver` omits a property equal to its script default, so the
    reloaded `.tres` carries the default `+0.0`. The report must come from the
    reloaded resource so the bit gate sees that sign flip and refuses before
    publication. A build that still reports only the in-memory mapping exits 0
    here and fails this case.
    """
    fixture = FIXTURE_DIR / "negative" / "negative_zero_drag_rolling.json"
    output_dir = runner.workspace / "out-negative-zero-drag-rolling"

    def body() -> None:
        accepted = _run_checker(fixture, timeout=runner.timeout)
        accepted_output = (accepted.stdout or "") + "\n" + (accepted.stderr or "")
        _require(
            accepted.returncode == 0,
            "the negative-zero fixture must pass the committed motor-ready "
            "checker:\n" + accepted_output,
        )

        process = runner.bake(fixture, output_dir, expect_success=False)
        output = (process.stdout or "") + "\n" + (process.stderr or "")
        _require(process.returncode != 0, "refusal exit code must be nonzero")
        _require(
            "handling.drag.rolling: numeric-conversion-mismatch" in output,
            f"refusal did not name handling.drag.rolling:\n{output}",
        )
        _require(
            "0000000000000080" in output and "0000000000000000" in output,
            f"refusal did not report the sign-flipped binary64 bits:\n{output}",
        )
        _require(
            not output_dir.exists(),
            "a refused bake left an output destination behind",
        )
        _require(
            not (output_dir / "bake_manifest.json").exists(),
            "a refused bake produced a success manifest",
        )

    runner.run("negative zero drag rolling is refused at its exact source path", body)


def _check_corrupt_numeric_bit_control(runner: Runner) -> None:
    finite = FIXTURE_DIR / "positive" / "finite.json"

    def body() -> None:
        module = _load_bake_cli()
        checker = module._load_committed_checker()
        document, findings = checker.load_json_document(finite)
        _require(document is not None and not findings, f"finite fixture did not load: {findings}")
        expected = module._expected_numeric_bits(checker.to_binary64(document))
        _require(bool(expected), "finite fixture produced no expected numeric bits")
        path = sorted(expected)[0]

        def expect_refusal(report: dict[str, Any], needle: str) -> None:
            try:
                module._verify_numeric_fidelity(report, expected)
            except module.BakeError as exc:
                message = str(exc)
                _require(
                    needle in message,
                    f"refusal {message!r} does not mention {needle!r}",
                )
            else:
                raise CaseFailure(
                    f"control was accepted; wanted a refusal mentioning {needle!r}"
                )

        corrupted = dict(expected)
        corrupted[path] = _flip_hex_digit(corrupted[path])
        expect_refusal({"numeric_source_bits": corrupted}, "numeric-conversion-mismatch")

        missing = dict(expected)
        missing.pop(path)
        expect_refusal({"numeric_source_bits": missing}, "missing fields")

        extra = dict(expected)
        extra["handling.not_a_source_field"] = "0000000000000000"
        expect_refusal({"numeric_source_bits": extra}, "unexpected fields")

        malformed = dict(expected)
        malformed[path] = "not-hex"
        expect_refusal(
            {"numeric_source_bits": malformed}, "malformed numeric bit encoding"
        )

    runner.run("control: deliberately wrong numeric report bit is refused", body)


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


def _check_symlinked_source_success(runner: Runner) -> None:
    fixture = FIXTURE_DIR / "positive" / "finite.json"
    source_link = runner.workspace / "stable-source-link.json"
    source_link.symlink_to(fixture)
    output_dir = runner.workspace / "out-symlinked-source"

    def body() -> None:
        runner.bake(source_link, output_dir, expect_success=True)
        _require(output_dir.is_dir(), "success did not create the new output directory")
        manifest = _load_json(output_dir / "bake_manifest.json")
        _require(
            manifest.get("source_recipe") == str(source_link),
            f"manifest did not record the submitted lexical path: "
            f"{manifest.get('source_recipe')!r}",
        )
        _require(
            manifest.get("source_resolved_target") == str(fixture),
            f"manifest resolved target is {manifest.get('source_resolved_target')!r}",
        )
        _require(
            manifest.get("source_file_sha256") == _sha256(fixture),
            "manifest raw source SHA-256 does not match the symlink target bytes",
        )
        _require(
            manifest.get("source_content_hash") == _load_json(fixture).get("content_hash"),
            "manifest content hash does not match the symlink target document",
        )

    runner.run("symlinked source path bakes and records both spellings", body)


def _resolve_real_godot(explicit: str | None) -> str:
    candidate = explicit or os.environ.get("GODOT_BIN") or shutil.which("godot")
    if not candidate or not Path(candidate).is_file():
        raise CaseFailure(
            f"no Godot executable is available for the retargeting seam: {candidate!r}"
        )
    return candidate


def _write_retargeting_godot_wrapper(
    workspace: Path, link: Path, new_target: Path, real_godot: str
) -> Path:
    """Write a test-only ``--godot-bin`` seam that retargets the recipe link.

    The wrapper fires only inside the pinned-engine bake invocation, which is
    after the CLI froze its source snapshot and before the final recheck, and
    then execs the real pinned editor unchanged. The production CLI has no
    test hooks: this only substitutes the engine binary it is told to run.
    """
    wrapper = workspace / "godot-retarget-seam.sh"
    wrapper.write_text(
        "#!/bin/sh\n"
        "# Test-only seam for the bake source-path recheck, not part of the CLI.\n"
        'case "$*" in\n'
        "  *bake_handling.gd*)\n"
        '    rm -f "$SEAM_LINK"\n'
        '    ln -s "$SEAM_TARGET" "$SEAM_LINK"\n'
        "    ;;\n"
        "esac\n"
        'exec "$SEAM_REAL_GODOT" "$@"\n',
        encoding="utf-8",
    )
    wrapper.chmod(0o755)
    return wrapper


def _check_input_symlink_retarget_refusal(runner: Runner) -> None:
    fixture = FIXTURE_DIR / "positive" / "finite.json"
    source_link = runner.workspace / "retargeted-source-link.json"
    source_link.symlink_to(fixture)
    retargeted = runner.workspace / "retargeted-source.json"
    retargeted.write_text('{"retargeted": true}\n', encoding="utf-8")
    real_godot = _resolve_real_godot(runner.godot_bin)
    wrapper = _write_retargeting_godot_wrapper(
        runner.workspace, source_link, retargeted, real_godot
    )
    output_dir = runner.workspace / "out-retargeted-source"
    seam_env = {
        "SEAM_LINK": str(source_link),
        "SEAM_TARGET": str(retargeted),
        "SEAM_REAL_GODOT": real_godot,
    }

    def body() -> None:
        process = runner.bake(
            source_link,
            output_dir,
            expect_success=False,
            godot_bin=str(wrapper),
            extra_env=seam_env,
        )
        output = (process.stdout or "") + "\n" + (process.stderr or "")
        _require(
            "source recipe changed" in output,
            f"refusal did not report a changed source recipe:\n{output}",
        )
        _require(
            str(source_link) in output,
            f"refusal did not name the submitted path:\n{output}",
        )
        _require(
            source_link.resolve() == retargeted.resolve(),
            "the test seam did not retarget the submitted symlink",
        )
        _require(
            not output_dir.exists(),
            "a refused bake left an output destination behind",
        )
        _require(
            not (output_dir / "bake_manifest.json").exists(),
            "a refused bake produced a success manifest",
        )

    runner.run("input symlink retargeted during the bake is refused", body)


def _check_recheck_window_symlink_control(runner: Runner) -> None:
    """Deterministic control for the final source recheck's identity binding.

    The helper exposes a test-only seam invoked after the submitted path is
    opened, read and fstat'd but before the lexical path is resolved. A stable
    symlink must return the opened target; a seam that retargets the link to a
    different file inside that window must refuse rather than return the new
    path next to the old bytes' hash.
    """
    module = _load_bake_cli()
    workspace = runner.workspace / "recheck-window"
    workspace.mkdir(parents=True, exist_ok=True)
    target_a = workspace / "recheck-a.json"
    target_b = workspace / "recheck-b.json"
    target_a.write_bytes(b'{"a": true}\n')
    target_b.write_bytes(b'{"b": true}\n')
    link = workspace / "recheck-link.json"
    link.symlink_to(target_a)
    expected = "sha256:" + hashlib.sha256(target_a.read_bytes()).hexdigest()

    def body() -> None:
        returned = module._require_source_unchanged(link, expected)
        _require(
            returned == target_a.resolve(),
            f"stable symlink returned {returned!r}, expected {target_a.resolve()!r}",
        )

        fired: list[Path] = []
        original_seam = module._SOURCE_RECHECK_SEAM

        def seam(path: Path) -> None:
            fired.append(path)
            link.unlink()
            link.symlink_to(target_b)

        module._SOURCE_RECHECK_SEAM = seam
        try:
            try:
                module._require_source_unchanged(link, expected)
            except module.BakeError as exc:
                message = str(exc)
                _require(
                    "source recipe target changed" in message,
                    f"refusal did not report a changed target: {message!r}",
                )
                _require(
                    str(link) in message,
                    f"refusal did not name the submitted path: {message!r}",
                )
                _require(
                    str(target_b.resolve()) in message,
                    f"refusal did not name the retargeted destination: {message!r}",
                )
            else:
                raise CaseFailure(
                    "helper accepted a source symlink retargeted inside the "
                    "final recheck window"
                )
        finally:
            module._SOURCE_RECHECK_SEAM = original_seam

        _require(fired == [link], f"seam fired with unexpected paths: {fired!r}")
        _require(
            link.resolve() == target_b.resolve(),
            "the test seam did not retarget the submitted symlink",
        )

    runner.run("source symlink retargeted inside the final recheck window is refused", body)


def _check_dangling_input_symlink_refusal(runner: Runner) -> None:
    source_link = runner.workspace / "dangling-source-link.json"
    source_link.symlink_to(runner.workspace / "absent-source-target.json")
    output_dir = runner.workspace / "out-dangling-source"

    def body() -> None:
        process = runner.bake(source_link, output_dir, expect_success=False)
        output = (process.stdout or "") + "\n" + (process.stderr or "")
        _require(
            str(source_link) in output,
            f"refusal did not name the submitted path:\n{output}",
        )
        _require(
            "could not read the source recipe" in output,
            f"refusal did not report an unreadable source:\n{output}",
        )
        _require(
            not output_dir.exists(),
            "a refused bake left an output destination behind",
        )

    runner.run("dangling input symlink is refused", body)


def _check_input_parent_symlink_retarget_refusal(runner: Runner) -> None:
    fixture = FIXTURE_DIR / "positive" / "finite.json"
    real_dir = runner.workspace / "real-source-dir"
    real_dir.mkdir()
    shutil.copy2(fixture, real_dir / "recipe.json")
    other_dir = runner.workspace / "other-source-dir"
    other_dir.mkdir()
    (other_dir / "recipe.json").write_text('{"retargeted": true}\n', encoding="utf-8")
    parent_link = runner.workspace / "linked-source-dir"
    parent_link.symlink_to(real_dir, target_is_directory=True)
    submitted = parent_link / "recipe.json"
    real_godot = _resolve_real_godot(runner.godot_bin)
    wrapper = _write_retargeting_godot_wrapper(
        runner.workspace, parent_link, other_dir, real_godot
    )
    output_dir = runner.workspace / "out-parent-retargeted-source"
    seam_env = {
        "SEAM_LINK": str(parent_link),
        "SEAM_TARGET": str(other_dir),
        "SEAM_REAL_GODOT": real_godot,
    }

    def body() -> None:
        process = runner.bake(
            submitted,
            output_dir,
            expect_success=False,
            godot_bin=str(wrapper),
            extra_env=seam_env,
        )
        output = (process.stdout or "") + "\n" + (process.stderr or "")
        _require(
            "source recipe changed" in output,
            f"refusal did not report a changed source recipe:\n{output}",
        )
        _require(
            str(submitted) in output,
            f"refusal did not name the submitted path:\n{output}",
        )
        _require(
            parent_link.resolve() == other_dir.resolve(),
            "the test seam did not retarget the submitted parent symlink",
        )
        _require(
            not output_dir.exists(),
            "a refused bake left an output destination behind",
        )
        _require(
            not (output_dir / "bake_manifest.json").exists(),
            "a refused bake produced a success manifest",
        )

    runner.run("input parent symlink retargeted during the bake is refused", body)


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
        _check_subnormal_fixture_is_checker_accepted(runner)
        _check_negative(
            runner,
            "subnormal_reverse_acceleration.json",
            "subnormal reverse acceleration is refused at its exact source path",
            "handling.reverse_acceleration_m_s2: numeric-conversion-mismatch",
            failure_control=True,
        )
        _check_negative_zero_drag_rolling_refusal(runner)
        _check_corrupt_numeric_bit_control(runner)
        _check_existing_destination_refusal(runner)
        _check_existing_symlink_refusal(runner)
        _check_symlinked_source_success(runner)
        _check_input_symlink_retarget_refusal(runner)
        _check_dangling_input_symlink_refusal(runner)
        _check_input_parent_symlink_retarget_refusal(runner)
        _check_recheck_window_symlink_control(runner)
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
