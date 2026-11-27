#!/usr/bin/env python3
"""Run the independent M0.8 tick-probe contract tests in an isolated copy.

The probe project is copied to a temporary directory so the repository's
``.godot`` cache and any installed files are never touched. Engine caches and
temporary files are redirected through ``XDG_*``/``TMPDIR`` inside the scratch
directory; ``HOME`` itself is deliberately left untouched. Each run is bounded
by ``--timeout``.

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
import re
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
    parser.add_argument("--expect-checks", type=int, default=0,
                        help="fail unless the probe reports exactly this many checks (0 disables)")
    parser.add_argument(
        "--pacing",
        choices=["fixed", "default", "max"],
        default="fixed",
        help="engine pacing: --fixed-fps 60 (fixed), none (default), --max-fps 60 (max)",
    )
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
        # Leave HOME alone; isolate caches/config/data and temp instead.
        for xdg in ("XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME"):
            path = scratch / xdg.lower().replace("xdg_", "")
            path.mkdir(parents=True, exist_ok=True)
            env[xdg] = str(path)
        (scratch / "tmp").mkdir()
        env["TMPDIR"] = str(scratch / "tmp")
        pacing_flags = {
            "fixed": ["--fixed-fps", "60"],
            "default": [],
            "max": ["--max-fps", "60"],
        }[args.pacing]
        cmd = [
            args.godot,
            "--headless",
            *pacing_flags,
            "--path",
            str(isolated),
            "--script",
            "res://tests/contract_entry.gd",
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=args.timeout, env=env)
        sys.stdout.write(proc.stdout)
        if proc.stderr.strip():
            sys.stderr.write(proc.stderr)
        combined = proc.stdout + proc.stderr
        # N3: a lost/garbled run must never pass quietly.
        for marker in ("SCRIPT ERROR", "Parse Error", "Failed to load script"):
            if marker in combined:
                print(f"ERROR: engine reported {marker!r}; refusing to treat this run as evidence",
                      file=sys.stderr)
                return 1
        total_match = re.search(r"TESTS_TOTAL=(\d+)", combined)
        if total_match is None:
            print("ERROR: no TESTS_TOTAL line in contract-test output", file=sys.stderr)
            return 1
        reported_total = int(total_match.group(1))
        try:
            report = parse_result(proc.stdout)
        except RuntimeError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        if int(report.get("checks_total", -1)) != reported_total:
            print(f"ERROR: TEST_RESULT checks_total={report.get('checks_total')} disagrees with TESTS_TOTAL={reported_total}",
                  file=sys.stderr)
            return 1
        if args.expect_checks and reported_total != args.expect_checks:
            print(f"ERROR: expected {args.expect_checks} checks, probe reported {reported_total}", file=sys.stderr)
            return 1
        if out_dir is not None:
            (out_dir / "contract-tests.txt").write_text(combined)
            (out_dir / "contract-tests.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        failed = report.get("checks_failed", 1)
        print(f"PACING={args.pacing} CONTRACT_TESTS_TOTAL={reported_total} CONTRACT_TESTS_FAILED={failed}")
        # A well-formed report that reports failures is authoritative even if
        # the child process exited 0 (for example a harness or script bug).
        if failed != 0:
            print(f"ERROR: probe reported {failed} failed check(s); failing closed regardless of child exit",
                  file=sys.stderr)
            return 1
        return proc.returncode
    except subprocess.TimeoutExpired as exc:
        partial = ""
        for stream in (exc.stdout, exc.stderr):
            if isinstance(stream, bytes):
                partial += stream.decode("utf-8", "replace")
            elif stream:
                partial += str(stream)
        for marker in ("SCRIPT ERROR", "Parse Error", "Failed to load script"):
            if marker in partial:
                print(f"ERROR: engine reported {marker!r} before timing out at {args.timeout:.0f}s",
                      file=sys.stderr)
                return 1
        print(f"ERROR: contract tests exceeded {args.timeout:.0f}s", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
