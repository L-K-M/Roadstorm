# M0.8 tick / reset / query probe

Self-contained Godot project that probes the mechanics PLAN.md M0.8 requires
before the M1 motor depends on them:

- exactly **twelve logical ticks per nonterminal training-style request**;
- **early termination/truncation** stopping at the first ending tick and
  returning the actual elapsed tick count;
- **zero logical advancement while waiting** for the trainer;
- **complete reset** of pose, clocks, RNG stream, events and counters;
- **query/physics fidelity**: a nonmutating swept shape cast predicts the
  committed `CharacterBody3D.move_and_collide()` motion, and a counter-only
  "motor" that never steps the world is shown not to move the body;
- **accelerated versus real-time** execution of the same command trace.

The authoritative actor is a real `CharacterBody3D` in a real Godot physics
world (**Jolt**, pinned explicitly in both `project.godot` files — the same
backend the game project selects), moved by explicit displacement once per
accepted substep, the API shape TECHNICAL_DESIGN.md prescribes. It is not the full M1 motor, AI, contact
resolver or training bridge; it proves the engine mechanics those will rely on.

## Files

| Path | Role |
| --- | --- |
| `project.godot` | minimal self-contained project, 60 Hz physics, no main scene, `3d/physics_engine="Jolt Physics"` pinned |
| `src/tick_probe.gd` | headless entry point (`SceneTree` script) |
| `src/probe_driver.gd` | scenarios, assertions, JSON report, exit codes |
| `src/tick_coordinator.gd` | logical-tick owner: budget, freeze gate, reset, swept movement, queries |
| `compare_modes.py` | runs accelerated and real-time traces and compares them |
| `.gitignore` | ignores the generated `.godot/` cache |

## Requirements

- Godot **4.7.2 Standard** editor or runtime on `PATH` (M0.1 pinned version).
  The probe fails if the engine is not 4.7.2.
- Python 3 standard library only for `compare_modes.py`.

No packages are installed and no network service is used.

## Run

From the repository root:

```sh
# Structural scenarios, deterministic locked stepping (1 frame = 1 physics tick)
godot --headless --fixed-fps 60 --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=structural

# Same scenarios under default headless pacing and near-real-time pacing
godot --headless --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=structural
godot --headless --max-fps 60 --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=structural

# Accelerated vs real-time fidelity and throughput (600 ticks each)
python3 tools/tick_probe/compare_modes.py

# Prove a failing check exits nonzero
godot --headless --fixed-fps 60 --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=throughput requests=2 inject_failure=1
echo $?   # 1
```

Each run prints `PASS`/`FAIL` lines and one machine-readable
`PROBE_RESULT <json>` line. Exit code `0` means every check passed, `1` means
at least one failed. `TICK_PROBE_DEBUG=1` additionally prints per-substep
query/commit diagnostics.

## What is checked

**Pinned backend.** The probe fails unless `physics/3d/physics_engine` reads
back `"Jolt Physics"`, and records the engine's allowed values for the setting
(`DEFAULT,Jolt Physics,GodotPhysics3D,Dummy`). GDScript cannot query which
backend is actually instantiated (`PhysicsServer3D` is opaque, and this build
prints no backend line even with `--verbose`), so the pin is the setting value
plus the explicit GodotPhysics3D contrast run recorded under
`evidence/2026-11-26-apple-m4-max-jolt/`, which shows the selection really
changes the physics server and that the pre-pin `DEFAULT` evidence matched
GodotPhysics3D bit-for-bit.

**Twelve ticks per request.** Five sequential requests of 12 ticks each consume
exactly 12, 12, 12, 12, 12 ticks and 60 total, with a five-frame trainer wait
between requests that consumes zero ticks. A fake motor-function counter
that records twelve calls without asking the coordinator to step leaves
`tick_count == 0`, the body at its start pose, and claims 2 m of travel.
Conversely, twelve direct `move_and_collide()` calls made outside any
coordinator tick do move the body 2 m while `tick_count` stays at zero. Call
count alone is therefore neither necessary nor sufficient evidence of twelve
correct world steps; the coordinator's tick accounting is authoritative.

**Bypass contrast.** Twelve direct physics calls outside the coordinator move
the body 1.9999998 m but consume zero logical ticks, so world motion without
tick accounting is explicitly detected rather than assumed away.

**Termination and truncation.** With a finish plane at z = -0.9 m and 10 m/s,
one request returns `elapsed_ticks = 6`, `terminal = terminated`; a later
request returns 0 ticks and cannot move the car. With a 30-tick scenario cap,
requests return `(12, none)`, `(12, none)`, `(6, truncated)`, `(0, truncated)`
and the total stays at 30 ticks.

**Reset.** After 24 ticks, reset clears tick/distance/substep counters, RNG
history, events, terminal state and stats, restores the exact pose, works while
frozen, and a replayed 24-tick trace reproduces the transform, rotation, RNG
draw sequence, event count and distance totals bit-for-bit.

**Waiting.** The coordinator freezes the tree between requests. During an
explicit 60-frame trainer wait, `tick_count` and the body pose do not change
while driver process frames continue; resuming consumes exactly 12 more ticks.
An autonomous `RigidBody3D` also stops under `SceneTree.paused` (exact) and
under `Engine.time_scale = 0` (after the engine applies the change).

**Query/physics fidelity.** Each tick casts the car hull nonmutating with
`DirectSpaceState3D.cast_motion` **at margin 0** (the real hull) from an
explicit simulated transform, commits one `move_and_collide()` per substep of
at most 0.25 m, and checks that the predicted and committed endpoints agree.
On open road the maximum error is 0 m over 60 ticks; against a wall it is
0.000162 m under Jolt (margin/recovery rounding). The committed path stops at
the wall face instead of the naive straight chord (-1.0997 m actual versus
-2.0 m chord). At 65 m/s (1.083 m per tick, above the design's "more than a
meter per tick" concern) subdivision keeps every substep at or below 0.25 m
and the car stops at z = -0.5997 m at a contact plane of -0.6 m rather than
tunneling to the naive -1.083 m. The margin-0 rule is a measured Jolt
correction, not a preference — see the limitations below.

**Accelerated versus real time.** `compare_modes.py` runs 50 requests (600
ticks, 10 simulated seconds) with `--fixed-fps 60` and `--max-fps 60`. Both
runs report a constant 1/60 s physics delta and the **same final position**
(-99.999641418457 m in the recorded run); only wall time differs. Representative
measurements on the recorded host (Apple M4 Max, macOS, Godot 4.7.2, Jolt
backend, 26 November 2026):

| Mode | Ticks | Wall time | Logical ticks/s | Speedup vs wall clock |
| --- | ---: | ---: | ---: | ---: |
| `--fixed-fps 60` | 600 | 0.07-0.15 s | 3,900-8,600 | 65-144x |
| `--max-fps 60` | 600 | ~10.0 s | ~60 | ~1.00x |

Wall-clock spread between recorded runs is host-load variance; final state and
tick accounting did not change.

Under `--fixed-fps 60` rendered frames equal physics ticks (600/600); under
`--max-fps 60` the two can differ slightly (602 frames for 600 ticks), which is
why logical ticks are counted from physics callbacks, not frames.

## Measured limitations (do not overread)

- Headless dummy display/audio drivers: **no rendering, input, audio or
  windowing claim**. `rendering_method_setting` is the project default and is
  irrelevant to these results.
- The probe validates **same-host determinism**. Cross-platform byte equality
  is not claimed.
- **Backend identity cannot be directly verified from inside the engine.**
  `PhysicsServer3D` is opaque from GDScript and this build logs no backend
  line, so no run can name the active backend. The pin is the
  `physics/3d/physics_engine` setting value (checked every run) plus the
  GodotPhysics3D contrast run in `evidence/2026-11-26-apple-m4-max-jolt/`.
  Treat "the game runs on Jolt" as pinned-by-setting with contrast evidence,
  not as a directly observed runtime identity.
- **`cast_motion` margin semantics are backend-specific.** Under Jolt the
  query margin *grows* the cast shape while `move_and_collide` stops at the
  real surface regardless of the body's `safe_margin`. A margin-grown cast
  both predicts contact 0.08 m early and reports the segment clear once the
  grown hull overlaps a contact (committed motion then stays 0) — a
  full-substep prediction error. The probe therefore casts the real hull at
  margin 0; see `evidence/2026-11-26-apple-m4-max-jolt/margin-experiment.txt`
  for the controlled measurement. Any M1 planning that casts with a margin, or
  that switches between `cast_motion` and `test_move`, must re-measure this.
- `CharacterBody3D.test_move()` with this Godot/Jolt build reports a ~0.070 m
  vertical depenetration/recovery offset when it predicts a near contact, even
  though the committed motion has no such component (0.076 m under
  GodotPhysics3D). The probe therefore uses `cast_motion` as the primary
  predictor and reports the `test_move` artifact
  (`test_move_recovery_artifact_m`) instead of hiding it. Any M1 planning that
  switches between these queries must re-measure this discrepancy.
- `SceneTree.paused` freezing a free `RigidBody3D` exactly, and
  `Engine.time_scale = 0` holding one after a settling frame, are measured
  behaviors of this build, not a cross-version guarantee. The coordinator's own
  freeze gate is what enforces zero logical ticks; the engine-level freeze
  prevents autonomous bodies from drifting while waiting.
- Accelerated speedup is host-dependent. The comparison requires at least 2x
  and a real-time factor within 0.5-2.0 so a harness mistake (for example
  passing `--fixed-fps` to both runs) fails loudly.
- Each run's final position must match its own 600-tick command trace within
  `1e-4 m + 1e-6 m/tick` (float32 accumulation; the measured residual is 0.36 mm
  over 100 m). The two pacing modes must agree with each other within 1 um;
  recorded runs matched exactly (`|dz| = 0`).

## Evidence

- `evidence/2026-11-26-apple-m4-max-jolt/` — current runs under the pinned Jolt
  backend, including the backend pin check, the GodotPhysics3D contrast run,
  the margin characterization and the exit-code self-test.
- `evidence/2026-11-26-apple-m4-max/` — **superseded**: the original runs made
  with backend `DEFAULT` (shown by the contrast run to be GodotPhysics3D on
  this build). Retained only as the pre-pin record.

## Provenance

Original probe code authored by an LLM agent (LongCat 2.5 via Pi) for the
Roadstorm Racer! M0.8 job on 26 November 2026, against input revision
`0ea596a4fa85ade19375e130313f020ed6010619`. Backend pinning, the backend check,
the margin-0 cast correction and the re-recorded Jolt evidence were produced
by a StepFun 5 Preview agent for the M0.8 backend-correction job
(`9725ba2c-802a-4115-9aeb-337b1dca99c8`) on 26 November 2026. Engine: Godot
4.7.2-stable (official). No third-party assets or network services.
