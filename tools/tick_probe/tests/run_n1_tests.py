#!/usr/bin/env python3
"""Run the independent N1/cold-start regression in an isolated copy.

Same strictness as run_contract_tests.py: the project is copied to a temporary
directory, XDG caches/config/data and TMPDIR are redirected (HOME untouched),
engine SCRIPT ERRORs fail the run, and a well-formed report with failed checks
fails closed even if the child exits 0.

Usage:
    python3 tools/tick_probe/tests/run_n1_tests.py
    python3 tools/tick_probe/tests/run_n1_tests.py --pacing max --expect-checks 76

Exit code 0 means every N1 check passed, 1 otherwise.
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
        if line.startswith("N1_RESULT "):
            match = line[len("N1_RESULT "):]
            break
    if match is None:
        raise RuntimeError("no N1_RESULT line in N1 output")
    return json.loads(match)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--project", default=None)
    parser.add_argument("--out", default=None)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--pacing", choices=["fixed", "default", "max"], default="fixed")
    parser.add_argument("--expect-checks", type=int, default=0)
    args = parser.parse_args()

    project = Path(args.project).resolve() if args.project else Path(__file__).resolve().parent.parent
    if not (project / "project.godot").is_file():
        print(f"ERROR: no project.godot under {project}", file=sys.stderr)
        return 1
    out_dir = Path(args.out).resolve() if args.out else None
    if out_dir is not None:
        out_dir.mkdir(parents=True, exist_ok=True)

    scratch = Path(tempfile.mkdtemp(prefix="tick-probe-n1-"))
    try:
        isolated = scratch / "tick_probe"
        shutil.copytree(project, isolated, ignore=shutil.ignore_patterns(".godot"))
        env = dict(os.environ)
        for xdg in ("XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME"):
            path = scratch / xdg.lower().replace("xdg_", "")
            path.mkdir(parents=True, exist_ok=True)
            env[xdg] = str(path)
        (scratch / "tmp").mkdir()
        env["TMPDIR"] = str(scratch / "tmp")
        flags = {"fixed": ["--fixed-fps", "60"], "default": [], "max": ["--max-fps", "60"]}[args.pacing]
        proc = subprocess.run(
            [args.godot, "--headless", *flags, "--path", str(isolated),
             "--script", "res://tests/n1_regression_entry.gd"],
            capture_output=True, text=True, timeout=args.timeout, env=env,
        )
        sys.stdout.write(proc.stdout)
        if proc.stderr.strip():
            sys.stderr.write(proc.stderr)
        combined = proc.stdout + proc.stderr
        for marker in ("SCRIPT ERROR", "Parse Error", "Failed to load script"):
            if marker in combined:
                print(f"ERROR: engine reported {marker!r}; refusing to treat this run as evidence", file=sys.stderr)
                return 1
        total_match = re.search(r"N1_TOTAL=(\d+)", combined)
        if total_match is None:
            print("ERROR: no N1_TOTAL line in N1 output", file=sys.stderr)
            return 1
        reported_total = int(total_match.group(1))
        try:
            report = parse_result(proc.stdout)
        except RuntimeError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        if int(report.get("checks_total", -1)) != reported_total:
            print(f"ERROR: N1_RESULT checks_total={report.get('checks_total')} disagrees with N1_TOTAL={reported_total}",
                  file=sys.stderr)
            return 1
        if args.expect_checks and reported_total != args.expect_checks:
            print(f"ERROR: expected {args.expect_checks} checks, probe reported {reported_total}", file=sys.stderr)
            return 1
        if out_dir is not None:
            (out_dir / "n1-tests.txt").write_text(combined)
            (out_dir / "n1-tests.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        failed = report.get("checks_failed", 1)
        print(f"PACING={args.pacing} N1_TESTS_TOTAL={reported_total} N1_TESTS_FAILED={failed}")
        if failed != 0:
            print(f"ERROR: N1 probe reported {failed} failed check(s); failing closed regardless of child exit",
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
                print(f"ERROR: engine reported {marker!r} before timing out at {args.timeout:.0f}s", file=sys.stderr)
                return 1
        print(f"ERROR: N1 tests exceeded {args.timeout:.0f}s", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
