#!/usr/bin/env python3
"""Run the independent M0.8 tick-probe contract tests in an isolated copy.

The probe project is copied to a temporary directory so the repository's
``.godot`` cache and any installed files are never touched. ``HOME`` and
``TMPDIR`` point inside that copy. Each run is bounded by ``--timeout``.

Usage:
    python3 tools/tick_probe/tests/run_contract_tests.py
    python3 tools/tick_probe/tests/run_contract_tests.py \
        --godot /opt/homebrew/bin/godot --out evidence/<dir>

Exit code 0 means every contract test passed, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_result(stdout: str) -> dict:
    match = None
    for line in reversed(stdout.splitlines()):
        if line.startswith("TEST_RESULT "):
            match = line[len("TEST_RESULT "):]
            break
    if match is None:
        raise RuntimeError("no TEST_RESULT line in contract-test output")
    return json.loads(match)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot", help="Godot binary (default: godot on PATH)")
    parser.add_argument("--project", default=None, help="probe project directory (default: this file's parent's parent)")
    parser.add_argument("--out", default=None, help="directory for captured stdout/JSON evidence")
    parser.add_argument("--timeout", type=float, default=30.0, help="per-run timeout in seconds")
    args = parser.parse_args()

    project = Path(args.project).resolve() if args.project else Path(__file__).resolve().parent.parent
    if not (project / "project.godot").is_file():
        print(f"ERROR: no project.godot under {project}", file=sys.stderr)
        return 1

    out_dir = Path(args.out).resolve() if args.out else None
    if out_dir is not None:
        out_dir.mkdir(parents=True, exist_ok=True)

    scratch = Path(tempfile.mkdtemp(prefix="tick-probe-contract-"))
    try:
        isolated = scratch / "tick_probe"
        shutil.copytree(project, isolated, ignore=shutil.ignore_patterns(".godot"))
        env = dict(os.environ)
        env["HOME"] = str(scratch / "home")
        env["TMPDIR"] = str(scratch / "tmp")
        (scratch / "home").mkdir()
        (scratch / "tmp").mkdir()
        cmd = [
            args.godot,
            "--headless",
            "--fixed-fps",
            "60",
            "--path",
            str(isolated),
            "--script",
            "res://tests/contract_entry.gd",
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=args.timeout, env=env)
        sys.stdout.write(proc.stdout)
        if proc.stderr.strip():
            sys.stderr.write(proc.stderr)
        try:
            report = parse_result(proc.stdout)
        except RuntimeError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        if out_dir is not None:
            (out_dir / "contract-tests.txt").write_text(proc.stdout + proc.stderr)
            (out_dir / "contract-tests.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        failed = report.get("checks_failed", 1)
        print(f"CONTRACT_TESTS_TOTAL={report.get('checks_total', 0)} CONTRACT_TESTS_FAILED={failed}")
        return proc.returncode
    except subprocess.TimeoutExpired:
        print(f"ERROR: contract tests exceeded {args.timeout:.0f}s", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
