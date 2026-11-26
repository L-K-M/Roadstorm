#!/usr/bin/env python3
"""Run the M0.8 tick probe in accelerated and real-time modes and compare them.

The two runs must execute the same 600-tick command trace with the same fixed
physics delta and produce the same committed final state. The wall-clock speeds
must differ by a large factor: --fixed-fps disables real-time synchronization,
--max-fps 60 keeps the loop near wall clock.

Usage:
    python3 tools/tick_probe/compare_modes.py
    python3 tools/tick_probe/compare_modes.py --godot /opt/homebrew/bin/godot \
        --requests 25

Exit code 0 means fidelity and pacing sanity checks passed, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

DT = 1.0 / 60.0
SCRIPT = "res://src/tick_probe.gd"


def parse_result(stdout: str) -> dict:
    match = None
    for line in reversed(stdout.splitlines()):
        if line.startswith("PROBE_RESULT "):
            match = line[len("PROBE_RESULT "):]
            break
    if match is None:
        raise RuntimeError("no PROBE_RESULT line in probe output")
    return json.loads(match)


def run_mode(godot: str, project: Path, label: str, flags: list[str], requests: int, timeout: float) -> dict:
    cmd = [
        godot,
        "--headless",
        *flags,
        "--path",
        str(project),
        "--script",
        SCRIPT,
        "--",
        "mode=throughput",
        f"label={label}",
        f"requests={requests}",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError(
            f"{label} probe exited {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    report = parse_result(proc.stdout)
    if report.get("checks_failed", 1) != 0:
        raise RuntimeError(f"{label} probe reported failed checks: {report.get('failures')}")
    return report["scenarios"]["throughput"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot", help="Godot binary (default: godot on PATH)")
    parser.add_argument("--project", default=None, help="probe project directory (default: this script's directory)")
    parser.add_argument("--requests", type=int, default=50, help="training requests of 12 ticks (default: 50)")
    parser.add_argument("--timeout", type=float, default=180.0, help="per-run timeout in seconds")
    args = parser.parse_args()

    project = Path(args.project).resolve() if args.project else Path(__file__).resolve().parent
    if not (project / "project.godot").is_file():
        print(f"ERROR: no project.godot under {project}", file=sys.stderr)
        return 1

    try:
        accelerated = run_mode(args.godot, project, "accelerated", ["--fixed-fps", "60"], args.requests, args.timeout)
        realtime = run_mode(args.godot, project, "realtime", ["--max-fps", "60"], args.requests, args.timeout)
    except (subprocess.TimeoutExpired, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    expected_ticks = args.requests * 12
    failures: list[str] = []

    def check(condition: bool, message: str) -> None:
        print(("PASS " if condition else "FAIL ") + message)
        if not condition:
            failures.append(message)

    print(
        f"{'mode':<12}{'ticks':>7}{'wall_s':>10}{'ticks/s':>12}{'speedup':>10}{'final_z':>20}"
    )
    for name, data in (("accelerated", accelerated), ("realtime", realtime)):
        print(
            f"{name:<12}{data['elapsed_ticks']:>7}{data['wall_seconds']:>10.3f}"
            f"{data['logical_ticks_per_wall_second']:>12.1f}{data['speedup_vs_wall_clock']:>10.2f}"
            f"{data['final_z_m']:>20.9f}"
        )

    for name, data in (("accelerated", accelerated), ("realtime", realtime)):
        check(data["elapsed_ticks"] == expected_ticks, f"{name}: consumed {expected_ticks} logical ticks")
        check(abs(data["delta_min"] - DT) < 1e-6 and abs(data["delta_max"] - DT) < 1e-6,
              f"{name}: physics delta stayed 1/60 s")
        check(data["max_prediction_error_m"] < 0.01,
              f"{name}: shape-cast prediction error below 0.01 m "
              f"({data['max_prediction_error_m']:.9f} m)")

    dz = abs(accelerated["final_z_m"] - realtime["final_z_m"])
    check(dz <= 1e-6, f"fidelity: accelerated and real-time final positions agree (|dz|={dz:.3e} m)")
    check(abs(accelerated["position_error_m"] - realtime["position_error_m"]) <= 1e-6,
          "fidelity: accumulated command-trace error matches across pacing modes")
    check(accelerated["speedup_vs_wall_clock"] >= 2.0,
          f"pacing: accelerated mode is meaningfully faster than wall clock "
          f"({accelerated['speedup_vs_wall_clock']:.1f}x)")
    check(0.5 <= realtime["speedup_vs_wall_clock"] <= 2.0,
          f"pacing: real-time mode tracks wall clock "
          f"({realtime['speedup_vs_wall_clock']:.3f}x)")

    if failures:
        print(f"\nCOMPARISON FAILED: {len(failures)} check(s)")
        return 1
    print("\nCOMPARISON PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
