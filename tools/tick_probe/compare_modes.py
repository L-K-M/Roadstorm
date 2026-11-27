#!/usr/bin/env python3
"""Compare M0.8 tick-probe execution across engine pacing modes.

Two kinds of evidence are compared:

* throughput/fidelity: 50 requests (600 ticks) of a constant-speed open-road
  command trace under ``--fixed-fps 60`` and ``--max-fps 60``, checking tick
  counts, physics delta, prediction error and final position;
* intermediate-state trace: a bounded contact / termination / reset-replay /
  motion-bound sequence, comparing a per-tick digest (pose, per-tick motion,
  RNG draws, event kinds, terminal state) across ``--fixed-fps 60``,
  ``--max-fps 60`` and default pacing.

The digest comparison is deliberately bounded: it covers this probe's existing
one-car scenarios, not a full simulation.

Usage:
    python3 tools/tick_probe/compare_modes.py
    python3 tools/tick_probe/compare_modes.py --godot /opt/homebrew/bin/godot \
        --requests 25 --timeout 30

Exit code 0 means every fidelity and pacing sanity check passed, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

DT = 1.0 / 60.0
SCRIPT = "res://src/tick_probe.gd"
TOL = 1e-6


def parse_result(stdout: str) -> dict:
    match = None
    for line in reversed(stdout.splitlines()):
        if line.startswith("PROBE_RESULT "):
            match = line[len("PROBE_RESULT "):]
            break
    if match is None:
        raise RuntimeError("no PROBE_RESULT line in probe output")
    return json.loads(match)


def run_probe(
    godot: str,
    project: Path,
    label: str,
    flags: list[str],
    mode: str,
    timeout: float,
    extra: list[str] | None = None,
) -> dict:
    cmd = [
        godot,
        "--headless",
        *flags,
        "--path",
        str(project),
        "--script",
        SCRIPT,
        "--",
        f"mode={mode}",
        f"label={label}",
    ]
    pacing = "fixed" if "--fixed-fps" in flags else ("max" if "--max-fps" in flags else "default")
    cmd.append(f"pacing={pacing}")
    if extra:
        cmd.extend(extra)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    combined = proc.stdout + proc.stderr
    # N3: never accept a run whose script failed to compile or was truncated.
    for marker in ("SCRIPT ERROR", "Parse Error", "Failed to load script"):
        if marker in combined:
            raise RuntimeError(f"{label} {mode} probe reported {marker!r}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")
    if proc.returncode != 0:
        raise RuntimeError(
            f"{label} {mode} probe exited {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    report = parse_result(proc.stdout)
    if report.get("checks_failed", 1) != 0:
        raise RuntimeError(f"{label} {mode} probe reported failed checks: {report.get('failures')}")
    return report


def run_mode(godot: str, project: Path, label: str, flags: list[str], requests: int, timeout: float,
             expect_checks: int = 0) -> dict:
    report = run_probe(godot, project, label, flags, "throughput", timeout, [f"requests={requests}"])
    _enforce_expected_checks(label, "throughput", report, expect_checks)
    return report["scenarios"]["throughput"]


def run_trace(godot: str, project: Path, label: str, flags: list[str], timeout: float,
              expect_checks: int = 0) -> dict:
    report = run_probe(godot, project, label, flags, "trace", timeout)
    _enforce_expected_checks(label, "trace", report, expect_checks)
    return report["scenarios"]["trace"]


def _enforce_expected_checks(label: str, mode: str, report: dict, expected: int) -> None:
    if not expected:
        return
    actual = int(report.get("checks_total", -1))
    if actual != expected:
        raise RuntimeError(f"{label} {mode} probe reported {actual} checks, expected {expected}")


def _is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def compare_value(path: str, a: object, b: object, failures: list[str], max_diff: float) -> float:
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a) != set(b):
            failures.append(f"{path}: key sets differ ({sorted(a)} vs {sorted(b)})")
            return max_diff
        for key in a:
            max_diff = compare_value(f"{path}.{key}", a[key], b[key], failures, max_diff)
        return max_diff
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            failures.append(f"{path}: length {len(a)} vs {len(b)}")
            return max_diff
        for index, (item_a, item_b) in enumerate(zip(a, b)):
            max_diff = compare_value(f"{path}[{index}]", item_a, item_b, failures, max_diff)
        return max_diff
    if _is_number(a) and _is_number(b):
        diff = abs(float(a) - float(b))
        max_diff = max(max_diff, diff)
        if diff > TOL:
            failures.append(f"{path}: {a!r} vs {b!r} (|diff|={diff:.3e})")
        return max_diff
    if a != b:
        failures.append(f"{path}: {a!r} vs {b!r}")
    return max_diff


def compare_traces(a: dict, b: dict) -> tuple[int, float, list[str]]:
    failures: list[str] = []
    max_diff = compare_value("trace", a, b, failures, 0.0)
    return len(failures), max_diff, failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot", help="Godot binary (default: godot on PATH)")
    parser.add_argument("--project", default=None, help="probe project directory (default: this script's directory)")
    parser.add_argument("--requests", type=int, default=50, help="training requests of 12 ticks (default: 50)")
    parser.add_argument("--timeout", type=float, default=30.0, help="per-run timeout in seconds")
    parser.add_argument("--expect-throughput-checks", type=int, default=0,
                        help="fail unless throughput reports exactly this many checks (0 disables)")
    parser.add_argument("--expect-trace-checks", type=int, default=0,
                        help="fail unless trace reports exactly this many checks (0 disables)")
    args = parser.parse_args()

    project = Path(args.project).resolve() if args.project else Path(__file__).resolve().parent
    if not (project / "project.godot").is_file():
        print(f"ERROR: no project.godot under {project}", file=sys.stderr)
        return 1

    try:
        accelerated = run_mode(args.godot, project, "accelerated", ["--fixed-fps", "60"], args.requests,
                                args.timeout, args.expect_throughput_checks)
        realtime = run_mode(args.godot, project, "realtime", ["--max-fps", "60"], args.requests,
                            args.timeout, args.expect_throughput_checks)
        acc_trace = run_trace(args.godot, project, "accelerated", ["--fixed-fps", "60"], args.timeout,
                             args.expect_trace_checks)
        rt_trace = run_trace(args.godot, project, "realtime", ["--max-fps", "60"], args.timeout,
                            args.expect_trace_checks)
        def_trace = run_trace(args.godot, project, "default", [], args.timeout, args.expect_trace_checks)
    except subprocess.TimeoutExpired as exc:
        partial = ""
        for stream in (exc.stdout, exc.stderr):
            if isinstance(stream, bytes):
                partial += stream.decode("utf-8", "replace")
            elif stream:
                partial += str(stream)
        for marker in ("SCRIPT ERROR", "Parse Error", "Failed to load script"):
            if marker in partial:
                print(f"ERROR: engine reported {marker!r} before the per-run timeout", file=sys.stderr)
                return 1
        print(f"ERROR: probe exceeded the per-run timeout", file=sys.stderr)
        return 1
    except RuntimeError as exc:
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

    # Every request spans n+1 engine frames: n tick iterations plus one
    # activation/publication boundary iteration that adds no physics-server
    # step. Record that honest cost and its realtime ceiling; the documented
    # 0.5-2.0 acceptance band is unchanged.
    boundary_s = args.requests * DT
    realtime_ceiling = realtime["sim_seconds"] / (realtime["sim_seconds"] + boundary_s)
    print(
        f"INFO: {args.requests} activation/publication boundary iterations expected "
        f"({boundary_s:.3f}s, zero server steps); realtime ceiling ~{realtime_ceiling:.3f}, "
        f"observed {realtime['speedup_vs_wall_clock']:.3f}"
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

    print("\nintermediate-state trace (contact / termination / reset-replay / motion-bound)")
    for name, other in (("realtime", rt_trace), ("default", def_trace)):
        mismatch_count, max_diff, details = compare_traces(acc_trace, other)
        check(mismatch_count == 0,
              f"trace fidelity: accelerated vs {name} per-tick digests match within {TOL:g} "
              f"(max |diff|={max_diff:.3e}, mismatches={mismatch_count})")
        if details:
            print("  first mismatches:")
            for detail in details[:3]:
                print("   ", detail)
        else:
            print(f"  max |diff| vs {name}: {max_diff:.3e}")

    if failures:
        print(f"\nCOMPARISON FAILED: {len(failures)} check(s)")
        return 1
    print("\nCOMPARISON PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
