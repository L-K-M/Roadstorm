#!/usr/bin/env python3
"""Run the hard same-world repeated-sequence gate in an isolated copy.

Private XDG/TMPDIR redirection, SCRIPT ERROR detection, REPEAT_RESULT /
REPEAT_TOTAL reconciliation, and fail-closed on reported failures.

Usage:
    python3 tools/tick_probe/tests/run_repeat_tests.py --pacing fixed \
        --expect-checks 54
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
        if line.startswith("REPEAT_RESULT "):
            match = line[len("REPEAT_RESULT "):]
            break
    if match is None:
        raise RuntimeError("no REPEAT_RESULT line in repeat-sequence output")
    return json.loads(match)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--project", default=None)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--pacing", choices=["fixed", "default", "max"], default="fixed")
    parser.add_argument("--expect-checks", type=int, default=54)
    args = parser.parse_args()

    project = Path(args.project).resolve() if args.project else Path(__file__).resolve().parent.parent
    if not (project / "project.godot").is_file():
        print(f"ERROR: no project.godot under {project}", file=sys.stderr)
        return 1
    scratch = Path(tempfile.mkdtemp(prefix="tick-probe-repeat-"))
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
             "--script", "res://tests/repeat_sequence_entry.gd"],
            capture_output=True, text=True, timeout=args.timeout, env=env,
        )
        sys.stdout.write(proc.stdout)
        if proc.stderr.strip():
            sys.stderr.write(proc.stderr)
        combined = proc.stdout + proc.stderr
        for marker in ("SCRIPT ERROR", "Parse Error", "Failed to load script"):
            if marker in combined:
                print(f"ERROR: engine reported {marker!r}", file=sys.stderr)
                return 1
        total_match = re.search(r"REPEAT_TOTAL=(\d+)", combined)
        if total_match is None:
            print("ERROR: no REPEAT_TOTAL line", file=sys.stderr)
            return 1
        total = int(total_match.group(1))
        report = parse_result(proc.stdout)
        if int(report.get("checks_total", -1)) != total:
            print("ERROR: REPEAT_RESULT/REPEAT_TOTAL disagree", file=sys.stderr)
            return 1
        if total != args.expect_checks:
            print(f"ERROR: expected {args.expect_checks} checks, got {total}", file=sys.stderr)
            return 1
        failed = report.get("checks_failed", 1)
        print(f"PACING={args.pacing} REPEAT_TESTS_TOTAL={total} REPEAT_TESTS_FAILED={failed}")
        if failed != 0:
            print(f"ERROR: repeat gate reported {failed} failure(s)", file=sys.stderr)
            return 1
        return proc.returncode
    except subprocess.TimeoutExpired:
        print(f"ERROR: repeat tests exceeded {args.timeout:.0f}s", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
