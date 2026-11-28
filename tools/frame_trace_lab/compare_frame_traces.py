#!/usr/bin/env python3
"""Compare one bounded Roadstorm frame trace across 30/60/120 nominal FPS.

The comparator validates the harness result contract independently of the
producer, requires three coherent full 1200-tick traces, compares exact
per-tick discrete state and counts, then applies the M1 numerical endpoint and
gate tolerances from docs/BENCHMARKS.md:

* position <= 0.10 m
* speed <= 0.10 m/s
* heading <= 1 degree
* gate time <= one 60 Hz physics tick

Exit 0 means every check passed. Exit 1 means an input is missing/corrupt or
incoherent, or a comparison failed. Exit 2 is command-line usage failure.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

SCHEMA = "roadstorm.frame_trace.result.v1"
EXPECTED_TICKS = 1200
THROTTLE_TICKS = 420
COAST_TICKS = 120
EXPECTED_FPS = {30, 60, 120}

POSITION_TOLERANCE_M = 0.10
SPEED_TOLERANCE_M_S = 0.10
HEADING_TOLERANCE_DEG = 1.0
GATE_TOLERANCE_TICKS = 1

# The endpoint carries the same orientation in radians and degrees. Accept
# only floating-point conversion roundoff between those representations; this
# consistency domain is checked before any angular arithmetic.
HEADING_RAD_TO_DEG_REL_TOLERANCE = 1e-12
HEADING_RAD_TO_DEG_ABS_TOLERANCE = 1e-12

# Startup and drain frames are included in the recorded engine counters. Four
# process frames is deliberately small next to the 602/1204/2408 expected
# counts, while still covering counter phase at launch and drain boundaries.
PROCESS_FRAME_STARTUP_DRAIN_TOLERANCE = 4
# The driver zeroes both engine counters after its ten settle frames and stops
# them after four drain frames. A coherent full run must therefore contain all
# 1200 commit frames. Accept those commits plus the four drain frames and four
# additional counter-boundary frames, for a deliberately tight allowance of
# eight frames. The process counter is bounded to the same run across the
# nominal 30/60/120 cadence cohort before exact integer ratio arithmetic.
PHYSICS_FRAME_STARTUP_DRAIN_ALLOWANCE = 8
MIN_FULL_RUN_PHYSICS_FRAMES = EXPECTED_TICKS
MAX_FULL_RUN_PHYSICS_FRAMES = EXPECTED_TICKS + PHYSICS_FRAME_STARTUP_DRAIN_ALLOWANCE
MIN_FULL_RUN_PROCESS_FRAMES = (
    MIN_FULL_RUN_PHYSICS_FRAMES * min(EXPECTED_FPS) // 60 - PROCESS_FRAME_STARTUP_DRAIN_TOLERANCE
)
MAX_FULL_RUN_PROCESS_FRAMES = (
    MAX_FULL_RUN_PHYSICS_FRAMES * max(EXPECTED_FPS) // 60 + PROCESS_FRAME_STARTUP_DRAIN_TOLERANCE
)
EXPECTED_ENGINE_BACKEND = "Jolt Physics"
EXPECTED_ENGINE_VERSION = {
    "major": 4,
    "minor": 7,
    "patch": 2,
    "hex": 263938,
    "status": "stable",
    "build": "official",
    "hash": "ed1daf0bf001b61586d9930840f2f1394092c079",
    "timestamp": 0,
    "string": "4.7.2-stable (official)",
}
HOST_COHORT_KEYS = {
    "os_name": str,
    "os_version": str,
    "processor_name": str,
    "processor_count": int,
    "display_driver": str,
}

COUNT_KEYS = (
    "gear_shift_events",
    "gear_shift_events_dropped",
    "gearbox_refusals",
    "contact_ticks",
    "wall_contact_ticks",
    "wall_events_published",
    "wall_events_coalesced",
    "wall_events_refused",
    "wall_event_missed_witnesses",
    "lateral_slip_ticks_proxy",
    "max_substeps",
)

TRACE_DISCRETE_KEYS = (
    "expected_phase",
    "command",
    "status",
    "gear_index",
    "reverse_engaged",
    "grounded",
    "contact",
    "wall_contact",
    "substeps",
)

ENDPOINT_DISCRETE_KEYS = (
    "gear_index",
    "reverse_engaged",
    "grounded",
    "surface_id",
    "drift_active",
)


class InputError(Exception):
    pass


class DerivedMetricError(Exception):
    pass


def is_number(value: Any) -> bool:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    if isinstance(value, float):
        return math.isfinite(value)
    try:
        float(value)
    except (OverflowError, ValueError):
        return False
    return True


def is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def safe_repr(value: Any) -> str:
    if is_int(value) and value.bit_length() > 1024:
        return f"<integer bit_length={value.bit_length()}>"
    try:
        text = repr(value)
    except Exception:
        return f"<{type(value).__name__}>"
    if len(text) > 120:
        return text[:117] + "..."
    return text


def safe_text(value: Any) -> str:
    try:
        text = str(value)
    except Exception:
        return f"<{type(value).__name__}>"
    if len(text) > 240:
        return text[:237] + "..."
    return text


def strict_json_dumps(payload: dict[str, Any]) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False)


def load_result(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise InputError(f"missing input file: {path}")
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(
                handle,
                parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"nonfinite JSON constant {value}")),
            )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        raise InputError(f"corrupt input file {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise InputError(f"corrupt input file {path}: top-level JSON value is not an object")
    return data


def expected_command(tick: int) -> dict[str, Any]:
    throttle = 1.0 if tick <= THROTTLE_TICKS else 0.0
    brake = 1.0 if tick > THROTTLE_TICKS + COAST_TICKS else 0.0
    return {
        "steer": 0.0,
        "throttle": throttle,
        "brake": brake,
        "handbrake": 0.0,
        "reset_requested": False,
        "reset_held": False,
    }


def expected_phase(tick: int) -> str:
    if tick <= THROTTLE_TICKS:
        return "full_throttle"
    if tick <= THROTTLE_TICKS + COAST_TICKS:
        return "coast"
    return "brake_then_reverse"


def validate_result(data: dict[str, Any], path: Path) -> list[str]:
    errors: list[str] = []

    def err(message: str) -> None:
        if len(errors) < 80:
            errors.append(message)

    if data.get("schema") != SCHEMA:
        err(f"{path}: schema is {data.get('schema')!r}, expected {SCHEMA!r}")
    for section in ("mode", "engine", "timing", "host", "schedule", "run", "endpoint", "counts", "gate", "harness"):
        if not isinstance(data.get(section), dict):
            err(f"{path}: missing or non-object section {section!r}")
    if not isinstance(data.get("tick_trace"), list):
        err(f"{path}: missing or non-array tick_trace")
    if errors:
        return errors

    mode = data["mode"]
    engine = data["engine"]
    timing = data["timing"]
    host = data["host"]
    schedule = data["schedule"]
    run = data["run"]
    endpoint = data["endpoint"]
    counts = data["counts"]
    gate = data["gate"]
    harness = data["harness"]
    trace = data["tick_trace"]

    nominal_fps = mode.get("nominal_fixed_fps")
    if not is_int(nominal_fps) or nominal_fps not in EXPECTED_FPS:
        err(f"{path}: nominal_fixed_fps is {nominal_fps!r}, expected one of {sorted(EXPECTED_FPS)}")
    if mode.get("variant") != "full":
        err(f"{path}: variant is {mode.get('variant')!r}, expected 'full'")
    if mode.get("control") is not False:
        err(f"{path}: control is {mode.get('control')!r}, expected false")
    if not is_int(engine.get("fixed_fps_argument")) or engine.get("fixed_fps_argument") != nominal_fps:
        err(f"{path}: fixed_fps_argument does not match the nominal FPS label")
    if engine.get("backend") != EXPECTED_ENGINE_BACKEND:
        err(f"{path}: engine backend is {engine.get('backend')!r}, expected pinned {EXPECTED_ENGINE_BACKEND!r}")
    if engine.get("version") != EXPECTED_ENGINE_VERSION:
        err(f"{path}: engine version is {engine.get('version')!r}, expected pinned {EXPECTED_ENGINE_VERSION!r}")

    physics_frames = timing.get("physics_frames")
    process_frames = timing.get("process_frames")
    physics_callbacks = timing.get("physics_callbacks")
    if not is_int(physics_frames) or physics_frames <= 0:
        err(f"{path}: timing.physics_frames is not a positive integer")
    if not is_int(process_frames) or process_frames <= 0:
        err(f"{path}: timing.process_frames is not a positive integer")
    if not is_int(physics_callbacks) or physics_callbacks <= 0:
        err(f"{path}: timing.physics_callbacks is not a positive integer")

    physics_counter_bounded = is_int(physics_frames) and physics_frames > 0
    process_counter_bounded = is_int(process_frames) and process_frames > 0
    physics_callback_counter_bounded = is_int(physics_callbacks) and physics_callbacks > 0
    if physics_counter_bounded and not MIN_FULL_RUN_PHYSICS_FRAMES <= physics_frames <= MAX_FULL_RUN_PHYSICS_FRAMES:
        err(
            f"{path}: timing.physics_frames is outside the plausible full-run range "
            f"[{MIN_FULL_RUN_PHYSICS_FRAMES}, {MAX_FULL_RUN_PHYSICS_FRAMES}] for {EXPECTED_TICKS} "
            f"committed ticks plus at most {PHYSICS_FRAME_STARTUP_DRAIN_ALLOWANCE} "
            "startup/drain/counter-boundary frames"
        )
        physics_counter_bounded = False
    if (
        physics_callback_counter_bounded
        and not MIN_FULL_RUN_PHYSICS_FRAMES <= physics_callbacks <= MAX_FULL_RUN_PHYSICS_FRAMES
    ):
        err(
            f"{path}: timing.physics_callbacks is outside the plausible full-run range "
            f"[{MIN_FULL_RUN_PHYSICS_FRAMES}, {MAX_FULL_RUN_PHYSICS_FRAMES}] for {EXPECTED_TICKS} "
            f"committed ticks plus at most {PHYSICS_FRAME_STARTUP_DRAIN_ALLOWANCE} "
            "startup/drain/counter-boundary frames"
        )
        physics_callback_counter_bounded = False
    if process_counter_bounded and not MIN_FULL_RUN_PROCESS_FRAMES <= process_frames <= MAX_FULL_RUN_PROCESS_FRAMES:
        err(
            f"{path}: timing.process_frames is outside the plausible full-run range "
            f"[{MIN_FULL_RUN_PROCESS_FRAMES}, {MAX_FULL_RUN_PROCESS_FRAMES}] for the nominal "
            "30/60/120 cadence cohort"
        )
        process_counter_bounded = False
    if is_int(nominal_fps) and nominal_fps in EXPECTED_FPS and physics_counter_bounded and process_counter_bounded:
        # Exact integer form of
        # abs(process_frames - physics_frames * nominal_fps / 60) <= 4.
        # The bounds above keep the values small; no float conversion is used,
        # so maliciously large JSON integers cannot overflow this comparison.
        scaled_process_frame_delta = abs(process_frames * 60 - physics_frames * nominal_fps)
        measured_ratio = physics_frames / process_frames
        nominal_ratio = 60.0 / float(nominal_fps)
        if scaled_process_frame_delta > PROCESS_FRAME_STARTUP_DRAIN_TOLERANCE * 60:
            err(
                f"{path}: observed physics/process frame ratio {measured_ratio:.9g} "
                f"does not match nominal {nominal_ratio:.9g} for {nominal_fps} FPS "
                f"({physics_frames} physics vs {process_frames} process frames; "
                f"startup/drain tolerance +/-{PROCESS_FRAME_STARTUP_DRAIN_TOLERANCE} process frames)"
            )

    for key, expected_type in HOST_COHORT_KEYS.items():
        value = host.get(key)
        if expected_type is int:
            valid = is_int(value) and value > 0
        else:
            valid = isinstance(value, str)
        if not valid:
            err(f"{path}: host.{key} is missing or has the wrong type")
    for key in ("physics_ticks_per_second_pinned", "physics_ticks_per_second_observed"):
        if engine.get(key) != 60:
            err(f"{path}: {key} is {engine.get(key)!r}, expected 60")

    if schedule.get("logical_ticks") != EXPECTED_TICKS:
        err(f"{path}: logical_ticks is {schedule.get('logical_ticks')!r}, expected {EXPECTED_TICKS}")
    if schedule.get("expected_committed_ticks") != EXPECTED_TICKS:
        err(f"{path}: expected_committed_ticks is not {EXPECTED_TICKS}")
    if schedule.get("commands_scheduled") != EXPECTED_TICKS:
        err(f"{path}: commands_scheduled is not {EXPECTED_TICKS}")
    if schedule.get("one_command_per_committed_tick") is not True:
        err(f"{path}: schedule does not assert one command per committed tick")
    if schedule.get("traffic_free") is not True:
        err(f"{path}: schedule is not marked traffic-free")

    for key in ("steps_called", "ticks_committed", "commands_consumed", "tick_log_entries", "tick_log_dropped"):
        if not is_int(run.get(key)):
            err(f"{path}: run.{key} is not an integer")
    run_physics_callbacks = run.get("physics_callbacks")
    if not is_int(run_physics_callbacks):
        err(f"{path}: run.physics_callbacks is not an integer")
    if is_int(run_physics_callbacks) and is_int(physics_callbacks) and run_physics_callbacks != physics_callbacks:
        err(
            f"{path}: run.physics_callbacks is {run_physics_callbacks}, but "
            f"timing.physics_callbacks is {physics_callbacks}"
        )
    if is_int(run.get("steps_called")) and run["steps_called"] != EXPECTED_TICKS:
        err(f"{path}: steps_called is {run['steps_called']}, expected {EXPECTED_TICKS}")
    if is_int(run.get("ticks_committed")) and run["ticks_committed"] != EXPECTED_TICKS:
        err(f"{path}: ticks_committed is {run['ticks_committed']}, expected {EXPECTED_TICKS}")
    if is_int(run.get("commands_consumed")) and run["commands_consumed"] != EXPECTED_TICKS:
        err(f"{path}: commands_consumed is {run['commands_consumed']}, expected {EXPECTED_TICKS}")
    if is_int(run.get("tick_log_entries")) and run["tick_log_entries"] != EXPECTED_TICKS:
        err(f"{path}: tick_log_entries is {run['tick_log_entries']}, expected {EXPECTED_TICKS}")
    if is_int(run.get("tick_log_dropped")) and run["tick_log_dropped"] != 0:
        err(f"{path}: tick_log_dropped is {run['tick_log_dropped']}, expected 0")
    if run.get("completed") is not True:
        err(f"{path}: run did not complete")
    if run.get("failed") is not False:
        err(f"{path}: run is marked failed: {run.get('failure_reason')!r}")
    if run.get("halt_reason") != "script complete":
        err(f"{path}: halt_reason is {run.get('halt_reason')!r}, expected 'script complete'")
    if run.get("tick_indices_consecutive") is not True:
        err(f"{path}: tick indices are not consecutive")
    if run.get("callback_indices_consecutive") is not True:
        err(f"{path}: callback indices are not consecutive")
    if run.get("heading_constant_rad") is not True:
        err(f"{path}: heading did not remain constant on the zero-steer straight")
    if run.get("within_straight_boundaries") is not True:
        err(f"{path}: trajectory left the straight-course boundaries")

    if harness.get("coherent") is not True:
        err(f"{path}: harness reports coherent != true")
    checks = harness.get("checks")
    if not isinstance(checks, dict):
        err(f"{path}: harness.checks is missing or not an object")
    else:
        for key, value in sorted(checks.items()):
            if value is not True:
                err(f"{path}: harness check {key!r} is {value!r}, expected true")

    for key in COUNT_KEYS:
        if not is_int(counts.get(key)) or counts.get(key, -1) < 0:
            err(f"{path}: counts.{key} is not a nonnegative integer")

    if endpoint.get("absent") is True:
        err(f"{path}: endpoint is absent")
    position = endpoint.get("position_m")
    velocity = endpoint.get("velocity_m_s")
    if not (isinstance(position, list) and len(position) == 2 and all(is_number(v) for v in position)):
        err(f"{path}: endpoint.position_m is not a finite two-component array")
    if not (isinstance(velocity, list) and len(velocity) == 2 and all(is_number(v) for v in velocity)):
        err(f"{path}: endpoint.velocity_m_s is not a finite two-component array")
    for key in ("speed_m_s", "forward_speed_m_s", "heading_rad", "heading_deg", "road_station_m", "trace_station_m", "station_cross_check_delta_m"):
        if not is_number(endpoint.get(key)):
            err(f"{path}: endpoint.{key} is not finite")
    heading_rad = endpoint.get("heading_rad")
    heading_deg = endpoint.get("heading_deg")
    if is_number(heading_rad) and is_number(heading_deg):
        expected_heading_deg = math.degrees(float(heading_rad))
        if not math.isfinite(expected_heading_deg) or not math.isclose(
            float(heading_deg),
            expected_heading_deg,
            rel_tol=HEADING_RAD_TO_DEG_REL_TOLERANCE,
            abs_tol=HEADING_RAD_TO_DEG_ABS_TOLERANCE,
        ):
            err(f"{path}: endpoint.heading_deg is inconsistent with endpoint.heading_rad")
    if is_number(endpoint.get("station_cross_check_delta_m")) and endpoint["station_cross_check_delta_m"] > 1e-6:
        err(f"{path}: endpoint station disagrees with the final trace station")
    for key in ENDPOINT_DISCRETE_KEYS:
        if key not in endpoint:
            err(f"{path}: endpoint.{key} is missing")

    gate_tick = gate.get("first_committed_tick")
    if not is_int(gate_tick) or not 1 <= gate_tick <= EXPECTED_TICKS:
        err(f"{path}: gate.first_committed_tick is not an integer in [1, {EXPECTED_TICKS}]")
    if gate.get("station_m") != 100.0:
        err(f"{path}: gate.station_m is {gate.get('station_m')!r}, expected 100.0")

    if len(trace) != EXPECTED_TICKS:
        err(f"{path}: tick_trace length is {len(trace)}, expected {EXPECTED_TICKS}")
        return errors

    previous_callback = None
    first_callback = None
    last_callback = None
    callback_order_valid = True
    for index, entry in enumerate(trace, start=1):
        prefix = f"{path}: tick {index}"
        if not isinstance(entry, dict):
            err(f"{prefix}: trace entry is not an object")
            continue
        tick = entry.get("tick")
        if not is_int(tick) or tick != index:
            err(f"{prefix}: tick field is {safe_repr(tick)}, expected integer {index}")
        if entry.get("command_index") != index - 1:
            err(f"{prefix}: command_index is {entry.get('command_index')!r}")
        if entry.get("expected_phase") != expected_phase(index):
            err(f"{prefix}: expected_phase is {entry.get('expected_phase')!r}")
        if entry.get("command") != expected_command(index):
            err(f"{prefix}: command does not match the fixed full schedule")
        if entry.get("status") != 0:
            err(f"{prefix}: adapter status is {entry.get('status')!r}, expected COMMITTED(0)")
        callback = entry.get("callback_index")
        if not is_int(callback):
            err(f"{prefix}: callback_index is not an integer")
            callback_order_valid = False
        else:
            if first_callback is None:
                first_callback = callback
            if previous_callback is not None and callback <= previous_callback:
                err(f"{prefix}: callback_index is not strictly increasing")
                callback_order_valid = False
            previous_callback = callback
            last_callback = callback
        for key in ("road_station_m", "speed_m_s", "forward_speed_m_s", "lateral_speed_m_s", "heading_rad"):
            if not is_number(entry.get(key)):
                err(f"{prefix}: {key} is not finite")
        for key in ("gear_index", "substeps"):
            if not is_int(entry.get(key)):
                err(f"{prefix}: {key} is not an integer")
        for key in ("reverse_engaged", "grounded", "contact", "wall_contact"):
            if not isinstance(entry.get(key), bool):
                err(f"{prefix}: {key} is not a boolean")

    if callback_order_valid and first_callback is not None and last_callback is not None:
        # The absolute first index is an arbitrary producer offset. Only the
        # inclusive ordinal span is meaningful: 1200 committed rows are emitted
        # by 1200 contiguous physics callbacks, while completion, drain and
        # counter-boundary callbacks occur outside that committed span.
        callback_span = last_callback - first_callback + 1
        if callback_span != EXPECTED_TICKS:
            err(
                f"{path}: committed callback_index span is {callback_span} callback ordinals, "
                f"expected exactly {EXPECTED_TICKS} contiguous committed callbacks"
            )
        if physics_counter_bounded and callback_span > physics_frames:
            err(
                f"{path}: committed callback_index span is {callback_span} callback ordinals, "
                f"exceeding measured timing.physics_frames {physics_frames}"
            )
        if physics_callback_counter_bounded and callback_span > physics_callbacks:
            err(
                f"{path}: committed callback_index span is {callback_span} callback ordinals, "
                f"exceeding measured timing.physics_callbacks {physics_callbacks}"
            )

    computed_gate_tick = None
    for index, entry in enumerate(trace, start=1):
        if not isinstance(entry, dict):
            continue
        station = entry.get("road_station_m")
        tick = entry.get("tick")
        if (
            is_int(tick)
            and tick == index
            and entry.get("status") == 0
            and is_number(station)
            and station >= 100.0
        ):
            computed_gate_tick = index
            break
    if computed_gate_tick is None:
        err(f"{path}: no committed tick_trace row reaches the 100.0 m gate")
    elif is_int(gate_tick) and gate_tick != computed_gate_tick:
        err(
            f"{path}: gate.first_committed_tick is {gate_tick}, but committed "
            f"tick_trace first reaches 100.0 m at tick {computed_gate_tick}"
        )

    return errors


def angle_difference_deg(a: float, b: float) -> float:
    # Normalize before subtraction. Both reduced operands are bounded, so even
    # finite but huge unwrapped producer angles cannot overflow the difference.
    a_normalized = float(a) % 360.0
    b_normalized = float(b) % 360.0
    return abs((a_normalized - b_normalized + 180.0) % 360.0 - 180.0)


def require_finite_metric(label: str, name: str, value: float) -> float:
    if not math.isfinite(value):
        raise DerivedMetricError(f"{label}: {name} derived metric is not finite")
    return value


def endpoint_position_delta(pos_a: list[Any], pos_b: list[Any], label: str) -> float:
    delta_x = float(pos_a[0]) - float(pos_b[0])
    delta_y = float(pos_a[1]) - float(pos_b[1])
    if not math.isfinite(delta_x) or not math.isfinite(delta_y):
        raise DerivedMetricError(f"{label}: endpoint position derived delta is not finite")
    delta = math.hypot(delta_x, delta_y)
    if not math.isfinite(delta):
        raise DerivedMetricError(f"{label}: endpoint position derived delta is not finite")
    return delta


def endpoint_speed_delta(speed_a: float, speed_b: float, label: str) -> float:
    difference = float(speed_a) - float(speed_b)
    if not math.isfinite(difference):
        raise DerivedMetricError(f"{label}: endpoint speed derived delta is not finite")
    return abs(difference)


def compare_valid_results(results: dict[int, dict[str, Any]]) -> tuple[list[str], dict[str, Any]]:
    failures: list[str] = []
    metrics: dict[str, Any] = {
        "pairs": {},
        "max_position_delta_m": 0.0,
        "max_speed_delta_m_s": 0.0,
        "max_heading_delta_deg": 0.0,
        "max_gate_delta_ticks": 0,
    }
    pairs = ((30, 60), (30, 120), (60, 120))

    reference_host = results[30]["host"]
    for fps in (60, 120):
        if results[fps]["host"] != reference_host:
            failures.append(f"30/{fps}: host cohort differs between inputs")

    for left, right in pairs:
        a = results[left]
        b = results[right]
        label = f"{left}/{right}"
        pair_metrics: dict[str, Any] = {}

        pos_a = a["endpoint"]["position_m"]
        pos_b = b["endpoint"]["position_m"]
        position_delta = endpoint_position_delta(pos_a, pos_b, label)
        speed_delta = endpoint_speed_delta(a["endpoint"]["speed_m_s"], b["endpoint"]["speed_m_s"], label)
        heading_delta = require_finite_metric(
            label,
            "endpoint heading",
            angle_difference_deg(float(a["endpoint"]["heading_deg"]), float(b["endpoint"]["heading_deg"])),
        )
        gate_delta = abs(int(a["gate"]["first_committed_tick"]) - int(b["gate"]["first_committed_tick"]))

        pair_metrics["position_delta_m"] = position_delta
        pair_metrics["speed_delta_m_s"] = speed_delta
        pair_metrics["heading_delta_deg"] = heading_delta
        pair_metrics["gate_delta_ticks"] = gate_delta
        metrics["pairs"][label] = pair_metrics
        metrics["max_position_delta_m"] = max(metrics["max_position_delta_m"], position_delta)
        metrics["max_speed_delta_m_s"] = max(metrics["max_speed_delta_m_s"], speed_delta)
        metrics["max_heading_delta_deg"] = max(metrics["max_heading_delta_deg"], heading_delta)
        metrics["max_gate_delta_ticks"] = max(metrics["max_gate_delta_ticks"], gate_delta)

        if position_delta > POSITION_TOLERANCE_M:
            failures.append(f"{label}: endpoint position differs by {position_delta:.9g} m")
        if speed_delta > SPEED_TOLERANCE_M_S:
            failures.append(f"{label}: endpoint speed differs by {speed_delta:.9g} m/s")
        if heading_delta > HEADING_TOLERANCE_DEG:
            failures.append(f"{label}: endpoint heading differs by {heading_delta:.9g} deg")
        if gate_delta > GATE_TOLERANCE_TICKS:
            failures.append(f"{label}: gate tick differs by {gate_delta}")

        for key in COUNT_KEYS:
            if a["counts"][key] != b["counts"][key]:
                failures.append(f"{label}: discrete count {key} differs ({a['counts'][key]!r} vs {b['counts'][key]!r})")
        for key in ENDPOINT_DISCRETE_KEYS:
            if a["endpoint"][key] != b["endpoint"][key]:
                failures.append(f"{label}: endpoint discrete state {key} differs ({a['endpoint'][key]!r} vs {b['endpoint'][key]!r})")

        trace_a = a["tick_trace"]
        trace_b = b["tick_trace"]
        for key in TRACE_DISCRETE_KEYS:
            values_a = [entry[key] for entry in trace_a]
            values_b = [entry[key] for entry in trace_b]
            if values_a != values_b:
                first = next((i for i, (va, vb) in enumerate(zip(values_a, values_b), start=1) if va != vb), None)
                failures.append(f"{label}: per-tick discrete sequence {key} first differs at tick {first}")

    return failures, metrics


def emit_exception_failure(exc: Exception) -> int:
    print("FAIL input presence, JSON structure, schema, coherence and fixed-schedule validation")
    print("FAIL exact tick count, discrete counts, commands and per-tick discrete state")
    print("FAILURES_BEGIN")
    print(
        "FAILURE malformed input could not be rejected by the normal validator path "
        f"without an internal exception ({type(exc).__name__}: {safe_text(exc)})"
    )
    print("FAILURES_END")
    payload = {
        "pass": False,
        "failure_count": 1,
        "tolerances": {
            "position_m": POSITION_TOLERANCE_M,
            "speed_m_s": SPEED_TOLERANCE_M_S,
            "heading_deg": HEADING_TOLERANCE_DEG,
            "gate_ticks": GATE_TOLERANCE_TICKS,
        },
        "metrics": {},
    }
    print("COMPARISON_RESULT " + strict_json_dumps(payload))
    print("COMPARISON FAIL")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="compare three frame-trace result JSON files")
    parser.add_argument("inputs", nargs=3, type=Path, metavar="RESULT_JSON")
    args = parser.parse_args()

    loaded: list[tuple[Path, dict[str, Any] | None]] = []
    input_errors: list[str] = []
    for path in args.inputs:
        try:
            data = load_result(path)
        except InputError as exc:
            input_errors.append(str(exc))
            loaded.append((path, None))
            continue
        try:
            errors = validate_result(data, path)
        except Exception as exc:
            errors = [
                f"{path}: malformed input could not be validated without an internal "
                f"exception ({type(exc).__name__}: {safe_text(exc)})"
            ]
        if errors:
            input_errors.extend(errors)
            loaded.append((path, None))
        else:
            loaded.append((path, data))

    failures = list(input_errors)
    metrics: dict[str, Any] = {}
    results: dict[int, dict[str, Any]] = {}
    if not input_errors:
        for path, data in loaded:
            assert data is not None
            fps = int(data["mode"]["nominal_fixed_fps"])
            if fps in results:
                failures.append(f"duplicate nominal fixed-fps input {fps}: {path}")
            results[fps] = data
        missing_fps = sorted(EXPECTED_FPS - set(results))
        if missing_fps:
            failures.append(f"missing nominal fixed-fps inputs: {missing_fps}")
        if not failures:
            try:
                failures, metrics = compare_valid_results(results)
            except DerivedMetricError as exc:
                failures = [str(exc)]
                metrics = {}
            except Exception as exc:
                failures = [
                    "comparison could not be completed for malformed input without an internal "
                    f"exception ({type(exc).__name__}: {safe_text(exc)})"
                ]
                metrics = {}

    if not input_errors and not failures:
        for fps in sorted(results):
            data = results[fps]
            print(
                "INPUT "
                f"fps={fps} ticks={data['run']['ticks_committed']} "
                f"gear_shifts={data['counts']['gear_shift_events']} "
                f"contacts={data['counts']['contact_ticks']} "
                f"wall_contacts={data['counts']['wall_contact_ticks']} "
                f"gate_tick={data['gate']['first_committed_tick']} "
                f"speed={data['endpoint']['speed_m_s']:.9g}"
            )

    def emit(condition: bool, message: str) -> None:
        print(("PASS " if condition else "FAIL ") + message)

    coherent = not input_errors
    emit(coherent, "input presence, JSON structure, schema, coherence and fixed-schedule validation")
    comparison_failures = [failure for failure in failures if failure not in input_errors]
    emit(not comparison_failures, "exact tick count, discrete counts, commands and per-tick discrete state")
    if metrics:
        emit(
            metrics["max_position_delta_m"] <= POSITION_TOLERANCE_M,
            f"endpoint position max delta {metrics['max_position_delta_m']:.9g} m <= {POSITION_TOLERANCE_M:g} m",
        )
        emit(
            metrics["max_speed_delta_m_s"] <= SPEED_TOLERANCE_M_S,
            f"endpoint speed max delta {metrics['max_speed_delta_m_s']:.9g} m/s <= {SPEED_TOLERANCE_M_S:g} m/s",
        )
        emit(
            metrics["max_heading_delta_deg"] <= HEADING_TOLERANCE_DEG,
            f"endpoint heading max delta {metrics['max_heading_delta_deg']:.9g} deg <= {HEADING_TOLERANCE_DEG:g} deg",
        )
        emit(
            metrics["max_gate_delta_ticks"] <= GATE_TOLERANCE_TICKS,
            f"gate-time max delta {metrics['max_gate_delta_ticks']} tick(s) <= {GATE_TOLERANCE_TICKS} tick",
        )

    if failures:
        print("FAILURES_BEGIN")
        for failure in failures[:80]:
            print(f"FAILURE {failure}")
        if len(failures) > 80:
            print(f"FAILURE ... {len(failures) - 80} additional failure(s) omitted")
        print("FAILURES_END")

    payload = {
        "pass": not failures,
        "failure_count": len(failures),
        "tolerances": {
            "position_m": POSITION_TOLERANCE_M,
            "speed_m_s": SPEED_TOLERANCE_M_S,
            "heading_deg": HEADING_TOLERANCE_DEG,
            "gate_ticks": GATE_TOLERANCE_TICKS,
        },
        "metrics": metrics,
    }
    print("COMPARISON_RESULT " + strict_json_dumps(payload))
    print("COMPARISON " + ("PASS" if not failures else "FAIL"))
    return 0 if not failures else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(1)
    except Exception as exc:
        raise SystemExit(emit_exception_failure(exc))
