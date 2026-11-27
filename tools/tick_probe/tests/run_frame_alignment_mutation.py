#!/usr/bin/env python3
"""Negative control for the behavioural callback-order assertion.

Both b5c4f99 reviews found that the committed ``1..n`` tick-sequence check can
pass even when the coordinator's scene-local physics priority is removed: an
earlier-in-tree default-priority observer then runs before the coordinator and
still reads ``1..n`` one iteration late.

This script patches an isolated copy of the probe so that:

* ``PHYSICS_CALLBACK_PRIORITY`` becomes ``0`` (the coordinator loses its
  ordering advantage; at equal priority its tree position puts it after the
  earlier-in-tree observer), and
* the numeric priority configuration assertion is replaced by an excluded
  placeholder, so only the behavioural checks discriminate.

Expected result: the mutated contract run exits nonzero, at least one FAIL
line mentions ``callback frames align``, and the sequence/callback-count checks
still PASS. The script exits 0 when the mutation demonstrates the gap and 1
when it does not.

The project is copied to a temporary directory and XDG/TMPDIR are redirected;
``HOME`` is left untouched. Raw engine output goes to stdout for capture.

Usage:
    python3 tools/tick_probe/tests/run_frame_alignment_mutation.py \
        --pacing fixed --pacing default --expect-checks 137
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PRIORITY_PATCH_OLD = "const PHYSICS_CALLBACK_PRIORITY := -1000"
PRIORITY_PATCH_NEW = "const PHYSICS_CALLBACK_PRIORITY := 0"

NUMERIC_CHECK_OLD = (
    '\t_check(coord.process_physics_priority < before.process_physics_priority,\n'
    '\t\t"ordering: coordinator process_physics_priority is below default observers",\n'
    '\t\t"coordinator=%d observer=%d" % [coord.process_physics_priority, before.process_physics_priority])\n'
)
NUMERIC_CHECK_NEW = (
    '\t_check(true, "ordering: numeric priority assertion excluded by mutation", "")\n'
)


def apply_patches(project: Path) -> None:
    coordinator = project / "src" / "tick_coordinator.gd"
    text = coordinator.read_text()
    if text.count(PRIORITY_PATCH_OLD) != 1:
        raise RuntimeError(f"priority patch anchor not unique in {coordinator}")
    coordinator.write_text(text.replace(PRIORITY_PATCH_OLD, PRIORITY_PATCH_NEW))

    driver = project / "tests" / "contract_driver.gd"
    text = driver.read_text()
    if text.count(NUMERIC_CHECK_OLD) != 1:
        raise RuntimeError(f"numeric-assertion patch anchor not unique in {driver}")
    driver.write_text(text.replace(NUMERIC_CHECK_OLD, NUMERIC_CHECK_NEW))


def run_pacing(godot: str, project: Path, pacing: str, timeout: float,
               expect_checks: int) -> tuple[bool, str]:
    scratch = Path(tempfile.mkdtemp(prefix=f"tick-probe-frame-mutation-{pacing}-"))
    try:
        isolated = scratch / "tick_probe"
        shutil.copytree(project, isolated, ignore=shutil.ignore_patterns(".godot"))
        apply_patches(isolated)
        env = dict(os.environ)
        for xdg in ("XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME"):
            path = scratch / xdg.lower().replace("xdg_", "")
            path.mkdir(parents=True, exist_ok=True)
            env[xdg] = str(path)
        (scratch / "tmp").mkdir()
        env["TMPDIR"] = str(scratch / "tmp")
        flags = {"fixed": ["--fixed-fps", "60"], "default": [], "max": ["--max-fps", "60"]}[pacing]
        proc = subprocess.run(
            [godot, "--headless", *flags, "--path", str(isolated),
             "--script", "res://tests/contract_entry.gd"],
            capture_output=True, text=True, timeout=timeout, env=env,
        )
        combined = proc.stdout + proc.stderr
        sys.stdout.write(proc.stdout)
        if proc.stderr.strip():
            sys.stderr.write(proc.stderr)
        for marker in ("SCRIPT ERROR", "Parse Error", "Failed to load script"):
            if marker in combined:
                print(f"ERROR: engine reported {marker!r} under pacing {pacing}", file=sys.stderr)
                return False, combined
        total_match = re.search(r"TESTS_TOTAL=(\d+)", combined)
        if total_match is None:
            print(f"ERROR: no TESTS_TOTAL line under pacing {pacing}", file=sys.stderr)
            return False, combined
        if expect_checks and int(total_match.group(1)) != expect_checks:
            print(f"ERROR: pacing {pacing} reported {total_match.group(1)} checks, "
                  f"expected {expect_checks}", file=sys.stderr)
            return False, combined

        frame_failures = [line for line in combined.splitlines()
                          if line.startswith("FAIL ") and "callback frames align" in line]
        sequence_failures = [line for line in combined.splitlines()
                             if line.startswith("FAIL ") and "sees consecutive ticks" in line]
        callback_failures = [line for line in combined.splitlines()
                             if line.startswith("FAIL ") and "no phantom or extra publication iteration" in line]
        demonstrated = (
            proc.returncode != 0
            and len(frame_failures) > 0
            and not sequence_failures
            and not callback_failures
        )
        print(f"MUTATION_PACING={pacing} EXIT={proc.returncode} "
              f"FRAME_ALIGN_FAILURES={len(frame_failures)} "
              f"SEQUENCE_FAILURES={len(sequence_failures)} "
              f"CALLBACK_COUNT_FAILURES={len(callback_failures)} "
              f"DEMONSTRATED={str(demonstrated).lower()}")
        return demonstrated, combined
    except subprocess.TimeoutExpired:
        print(f"ERROR: mutation run exceeded {timeout:.0f}s under pacing {pacing}", file=sys.stderr)
        return False, ""
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--project", default=None)
    parser.add_argument("--pacing", action="append", choices=["fixed", "default", "max"],
                        default=None,
                        help="engine pacing; repeat for multiple (default: fixed)")
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--expect-checks", type=int, default=0,
                        help="fail unless each mutated run reports exactly this many checks")
    args = parser.parse_args()

    project = Path(args.project).resolve() if args.project else Path(__file__).resolve().parent.parent
    if not (project / "project.godot").is_file():
        print(f"ERROR: no project.godot under {project}", file=sys.stderr)
        return 1

    pacings = args.pacing or ["fixed"]
    demonstrated = True
    for pacing in pacings:
        ok, _ = run_pacing(args.godot, project, pacing, args.timeout, args.expect_checks)
        demonstrated = demonstrated and ok
    if demonstrated:
        print("MUTATION CONTROL PASS: behavioural frame check fails while sequence checks still pass")
        return 0
    print("MUTATION CONTROL FAILED: the frame-alignment check did not discriminate",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
