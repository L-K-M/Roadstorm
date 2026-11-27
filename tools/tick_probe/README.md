# M0.8 tick / reset / query probe

Self-contained Godot project that probes the mechanics PLAN.md M0.8 requires
before the M1 motor depends on them:

- exactly **twelve logical ticks per nonterminal training-style request**;
- **early termination/truncation** stopping at the first ending tick and
  returning the actual elapsed tick count;
- **zero logical advancement while waiting** for the trainer;
- **complete reset** of pose, clocks, RNG stream, events and counters;
- **query/physics fidelity**: a nonmutating swept shape cast predicts the
  committed `CharacterBody3D.move_and_collide()` motion;
- **accelerated versus real-time** execution of the same command trace;
- an **explicit bounded work envelope** that refuses commands it cannot apply
  instead of silently dropping the remainder.

The authoritative actor is a real `CharacterBody3D` in a real Godot physics
world (**Jolt**, pinned explicitly in both `project.godot` files — the same
backend the game project selects), moved by explicit displacement once per
accepted substep, the API shape TECHNICAL_DESIGN.md prescribes. It is **not**
the full M1 motor, AI, contact resolver, multi-car reset or training bridge; a
one-car open-road/wall trace is not a full-simulation claim. No actual motor
is implemented or claimed here.

## Files

| Path | Role |
| --- | --- |
| `project.godot` | minimal self-contained project, 60 Hz physics, no main scene, `3d/physics_engine="Jolt Physics"` pinned, `common/physics_interpolation=true` matching the game |
| `src/tick_probe.gd` | headless entry point (`SceneTree` script) |
| `src/probe_driver.gd` | broad structural scenarios, assertions, JSON report, exit codes |
| `src/tick_coordinator.gd` | logical-tick owner: budget, freeze gate, reset, swept movement, queries |
| `tests/contract_entry.gd` | entry point for the independent focused contract tests |
| `tests/contract_driver.gd` | independent contract tests with their own `SceneTree.physics_frame` counting and negative controls |
| `tests/run_contract_tests.py` | runs the contract tests in an isolated copy (temp dir, XDG/TMPDIR redirected, no `HOME` reassignment, bounded timeout), with `--pacing fixed\|default\|max` and optional `--expect-checks N` |
| `compare_modes.py` | runs accelerated/real-time throughput checks and a per-tick trace digest comparison across three pacing modes |
| `.gitignore` | ignores the generated `.godot/` cache |

## Requirements

- Godot **4.7.2 Standard** editor or runtime on `PATH` (M0.1 pinned version).
  The probe fails if the engine is not 4.7.2.
- Python 3 standard library only for `compare_modes.py` and
  `run_contract_tests.py`.

No packages are installed and no network service is used.

## Run

From the repository root:

```sh
# Broad structural scenarios, deterministic locked stepping (1 frame = 1 physics tick)
godot --headless --fixed-fps 60 --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=structural pacing=fixed

# Same scenarios under default headless pacing and near-real-time pacing
godot --headless --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=structural pacing=default
godot --headless --max-fps 60 --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=structural pacing=max

# Independent focused contract tests (isolated copy, XDG/TMPDIR redirected, <=30 s).
# Run them under every pacing mode: --pacing fixed|default|max.
python3 tools/tick_probe/tests/run_contract_tests.py --pacing fixed --expect-checks 77
python3 tools/tick_probe/tests/run_contract_tests.py --pacing default --expect-checks 77
python3 tools/tick_probe/tests/run_contract_tests.py --pacing max --expect-checks 77

# Dynamic server-step regression (one physics-server step per logical tick)
godot --headless --fixed-fps 60 --path tools/tick_probe \
    --script res://tests/n1_regression_entry.gd

# Deterministic per-tick trace for the cross-pacing digest comparison
godot --headless --fixed-fps 60 --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=trace

# Accelerated vs real-time fidelity, throughput and trace digests (600 ticks each)
python3 tools/tick_probe/compare_modes.py \
    --expect-throughput-checks 4 --expect-trace-checks 2

# Prove a failing check exits nonzero
godot --headless --fixed-fps 60 --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=throughput requests=2 inject_failure=1
echo $?   # 1
```

Each run prints `PASS`/`FAIL` lines and one machine-readable
`PROBE_RESULT <json>` (or `TEST_RESULT <json>` for the contract suite) line.
Exit code `0` means every check passed, `1` means at least one failed.
`TICK_PROBE_DEBUG=1` additionally prints per-substep query/commit diagnostics.

The broad structural suite currently has **108 checks**; the independent
contract suite has **77 checks** and passes under `--fixed-fps 60`, default
and `--max-fps 60` pacing. Recorded totals and outputs live under `evidence/`.

## Coordinator contract

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
between requests that consumes zero ticks. The independent contract suite
repeats this for requests of 1, 7, 12 and 13 and compares each logical count
against its own count of `SceneTree.physics_frame` callbacks, not against
`tick_count`.

**Negative controls (no motor claim).** Twelve calls that never ask the
coordinator to step leave `tick_count == 0` and the body at its start pose; the
call log's arithmetic distance is a claim, not measured motion and not evidence
that any motor ran. Conversely, twelve direct `move_and_collide()` calls made
outside any coordinator tick do move the body 2 m while `tick_count` stays at
zero. Call count alone is neither necessary nor sufficient evidence of twelve
correct world steps; the coordinator's tick accounting is authoritative.

**Termination and truncation.** With a finish plane at z = -0.9 m and 10 m/s,
one request returns `elapsed_ticks = 6`, `terminal = terminated`; a later
request returns 0 ticks and cannot move the car. With a 30-tick scenario cap,
requests return `(12, none)`, `(12, none)`, `(6, truncated)`, `(0, truncated)`
and the total stays at 30 ticks.

**Zero/negative tick budget.** `max_ticks` is the total number of logical ticks
an episode may execute. `max_ticks <= 0` has explicit exhausted-budget
semantics: `reset()` reports `terminal = "truncated"` immediately, every
request returns `elapsed_ticks = 0` with `terminal = "truncated"`, the world
is left frozen, and **no** physics callback advances it. This closes the old
off-by-one where `max_ticks = 0` executed one unintended tick, and makes the
observation agree with the documented initial state. `max_ticks = 1` executes
exactly one tick. Negative caps behave as zero, not as one tick.

**Bounded work envelope.** One tick can apply at most
`MAX_SUBSTEPS * SUBSTEP_MAX_LEN = 16 * 0.25 = 4.0 m`, i.e. a supported speed of
`MAX_TICK_TRAVEL_M / DT = 240 m/s`. At the boundary the probe completes 12
ticks and keeps every substep at or below 0.25 m. Above the boundary the
coordinator fails closed: the request returns `elapsed_ticks = 0` and
`terminal = "motion_bound"`, the body does not move, and
`motion_bound_violations` / `last_motion_bound_deficit_m` record the refused
remainder. Forward and reverse over-speed are both refused, including a speed
changed mid-request: the refusal keeps the already-elapsed ticks and ends the
request `motion_bound`. The in-loop backstop path fails the same way rather
than letting the request finish with a dropped remainder. Previously a
250 m/s command silently moved only 48 m of the commanded 50 m (192 substeps);
that residual can no longer be dropped without an explicit failure.

**Reset and result consumption.** After 24 ticks, reset clears tick/distance/
substep counters, RNG history, events, terminal state and stats, restores the
exact pose, works while frozen, and a replayed 24-tick trace reproduces the
transform, rotation, RNG draw sequence, event count and distance totals
bit-for-bit. Reset ends with the authoritative world **frozen for waiting**;
the next `begin_step()` unfreezes it. Reset also clears the stored step result.
`take_result()` consumes the pending result and returns an empty `Dictionary`
when none is pending, so a prior episode's result cannot be read back through
the API. Two completion signals are published: `step_accounted` fires at the
final logical tick with the accounting snapshot (before the pause callback),
and `step_finished` fires once the tree is paused and the result is pending.

**Server steps per tick, including the first request.** A normal request keeps
the tree unpaused through its final physics callback so that tick's
`PhysicsServer3D` step still runs; the coordinator pauses on the next physics
callback, before that iteration's own server step. A freshly created active
`RigidBody3D` added to the frozen world receives exactly one counted
`_integrate_forces` step per requested tick, including the first request of
1, 12 and 24 ticks (measured fixed-fps, default and max-fps pacing). The pause
callback adds one engine frame beyond the logical ticks (`engine_pf_delta =
n + 1`), which the accounting boundary separates from integration count.
Freezing directly inside the final callback suppresses that step (measured at
11 steps per 12-tick request on the original); `tests/n1_regression_entry.gd`
fails on the unfixed behavior with eight failures.

**Waiting.** The authoritative world is frozen whenever the coordinator is
waiting: after every finished request, after `reset()`, after a zero-tick
request (`begin_step(0)`), and after an exhausted-budget early return. Only
`begin_step()` with a positive budget unfreezes it. An independent
`RigidBody3D` added to the probe world proves the freeze is physical, not just
a logical tick counter: after reset and after a zero-tick request it does not
drift across 30 engine physics frames while `tick_count` stays unchanged. The
zero-tick completion signal itself is published with the tree already frozen;
a synchronous `step_finished` listener observes `paused == true`. A trainer
wait between requests likewise consumes zero ticks and resumes with exactly
12. An autonomous `RigidBody3D` also stops under `SceneTree.paused` (exact) and
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

`compare_modes.py` also runs a bounded **intermediate-state trace**
(`mode=trace`): open-road run, reset/replay, wall contact at 10 m/s, early
termination at z = -0.9 m, and a `motion_bound` refusal. For each tick it
compares pose, per-tick start/end z, accepted length, substep count,
grounded flag, prediction error, RNG draws, event kinds and terminal state
across `--fixed-fps 60`, default and `--max-fps 60` pacing (tolerance 1e-6;
recorded runs matched exactly, max |diff| = 0). This is still a one-car
probe trace, not a full-simulator fidelity claim.

## Process pause ownership

The coordinator is the **sole owner of `SceneTree.paused` for the probe world**.
It owns the full waiting lifecycle: freeze after `reset()`, after every
finished request, after zero-tick requests and in exhausted-budget returns;
unfreeze only inside `begin_step()` when a positive budget starts. Other nodes
must not write `SceneTree.paused` while the probe is running. The contract
suite checks both directions: it sets an external pause, verifies
`begin_step()` clears it for a real request, and then requires the requested
ticks to execute; it also verifies that reset and zero-tick requests leave an
independent physics body stationary.

`begin_step()` is non-reentrant: negative budgets (validated before every
fast path, including terminal episodes), overlapping calls, and calls made
before the previous result was consumed are refused (`false`) with
`begin_step_refusals` / `last_begin_step_refusal` recording the reason, leaving
current accounting untouched.

**Frame accounting boundary.** The contract suite snapshots its independent
`SceneTree.physics_frame` tally inside `step_finished` rather than after polling
for the pending result. Under `--max-fps 60` with concurrent host load a
trailing engine callback can land after completion/freeze; post-poll sampling
overcounted by up to 23 callbacks in 100 one-tick requests on the recorded
host, while the simulation advanced exactly one tick each time. The
signal-boundary tally matched the logical elapsed count in every run, and a
frozen trailing callback never advanced `tick_count`.

## Measured limitations (do not overread)

- Headless dummy display/audio drivers: **no rendering, input, audio or
  windowing claim**. `rendering_method_setting` is the project default and is
  irrelevant to these results.
- **This is a one-car mechanics probe, not the full M1 motor or a full
  simulation.** There is no actual motor function, AI, vehicle-to-vehicle
  contact resolver, multi-car reset (velocities/gates/timers/contacts),
  interactive invocation or training bridge here. Those claims stay open for
  M1+.
- **Same-host determinism.** Cross-platform byte equality is not claimed.
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
- The coordinator advances exactly `DT = 1/60 s` per logical tick and
  deliberately does not read the `delta` argument of `_physics_process()`.
  Structural scenarios assert that the delivered physics delta stays exactly
  1/60 s rather than clamping or adapting to a different delta. A future
  variable-delta mode must change this contract and its evidence together.
- Commands above the 4.0 m/tick envelope are refused (`motion_bound`); they are
  not clamped, because silently dropping the remainder was the original bug.
  Speeds within the envelope are subdivided into substeps of at most 0.25 m.
  The pre-tick envelope check is what normal configurations hit; the in-loop
  residual backstop is defence-in-depth for states that bypass the pre-check,
  ends the request with `motion_bound`, and rolls the probe car back to the
  last accounted tick-start pose so the observation never shows uncounted
  motion. It cannot be reached by the probe's public constant-speed
  configuration within the 1e-6 tolerance band, so it is documented rather
  than claimed as independently exercised.
- A body created while the world is paused is registered on its first
  unpaused server step and integrates from the second; a continuous cold
  baseline therefore advances `k - 1` steps over `k` frames (registration
  latency). This baseline is recorded as a control only. Under the
  coordinator's request lifecycle, a freshly created body receives exactly its
  requested number of integrations even on the first request, because the
  finishing iteration stays unpaused until the following physics callback.
  The two effects are measured separately; matching a continuous cold
  baseline alone would not establish first-request semantics.
- `begin_step()` refusals are API contract, not runtime failure injection:
  overlapping/in-flight calls, untaken previous results and negative budgets
  return `false` and leave accounting untouched. A bridge that ignores the
  boolean can still misbehave; the probe cannot force correct call ordering.
- Accelerated speedup is host-dependent. The comparison requires at least 2x
  and a real-time factor within 0.5-2.0 so a harness mistake (for example
  passing `--fixed-fps` to both runs) fails loudly.
- Each run's final position must match its own 600-tick command trace within
  `1e-4 m + 1e-6 m/tick` (float32 accumulation; the measured residual is 0.36 mm
  over 100 m). The two pacing modes must agree with each other within 1 um;
  recorded runs matched exactly (`|dz| = 0`).
- The probe project matches the game's fixed 60 Hz tick and
  `physics_interpolation=true`; the renderer setting still differs
  (`forward_plus` vs `gl_compatibility`), which is irrelevant under headless
  dummy rendering but means the probe is not a full-config copy of the game.

## Evidence

- `evidence/2026-11-27-apple-m4-max-jolt-cold-start/` — **current**: cold-start
  characterization proving the first request is exact (one counted server
  integration per logical tick for a freshly created body), separating body
  registration latency (continuous baseline `k-1`), pause-callback observation
  frame (`engine_pf_delta = n+1`) and true missed integration; includes the
  strengthened regression failing on pristine `bdb0a98`, refreshed
  three-pacing contract/structural evidence, and hash-bound manifests.
- `evidence/2026-11-27-apple-m4-max-jolt-n1-server-steps/` — historical: N1
  server-step measurement/fix against `bdb0a98` plus Sol API-edge fixes,
  backstop rollback, runner strictness, mutation coverage and pacing metadata.
- `evidence/2026-11-27-apple-m4-max-jolt-api-edges/` — historical: the Sol
  API-edge follow-up against `bdb0a98`, covering negative-after-terminal,
  zero-tick signal freeze, cap-0 observation, signal-boundary accounting,
  concurrent-load timing and mutation sensitivity.
- `evidence/2026-11-27-apple-m4-max-jolt-waitguard/` — historical: the wait-guard
  revision against candidate `d562755`, covering physical wait-freeze
  enforcement, begin-step refusals, mid-request motion-bound refusal,
  three-pacing contract suite and per-tick trace digests.
- `evidence/2026-11-27-apple-m4-max-jolt-contract/` — historical: the first
  audit-response revision (stale result, zero budget, motion bound) against
  base candidate `55b04ce`; superseded by the wait-guard directory.
- `evidence/2026-11-26-apple-m4-max-jolt/` — historical: backend-pinned probe
  before the tick/reset/bound fixes, including the backend pin check, the
  GodotPhysics3D contrast run, the margin characterization and the exit-code
  self-test.
- `evidence/2026-11-26-apple-m4-max/` — **superseded**: the original runs made
  with backend `DEFAULT` (shown by the contrast run to be GodotPhysics3D on
  this build). Retained only as the pre-pin record.

## Provenance

Original probe code authored by an LLM agent (LongCat 2.5 via Pi) for the
Roadstorm Racer! M0.8 job on 26 November 2026, against input revision
`0ea596a4fa85ade19375e130313f020ed6010619`. Backend pinning, the backend check,
the margin-0 cast correction and the re-recorded Jolt evidence were produced
by a StepFun 5 Preview agent for the M0.8 backend-correction job
(`9725ba2c-802a-4115-9aeb-337b1dca99c8`) on 26 November 2026.

The tick/reset/bound audit-response fixes (stale result after reset,
`max_ticks <= 0` off-by-one, explicit 4 m/tick motion-bound refusal, independent
frame-counting contract tests, pause-ownership documentation and hash-bound
evidence) were produced for the M0.8 audit-response job against candidate
`55b04cec80fc842d1f40b5ac393a8a6492f112f3`, following the independent audit
report at
`work/agents/1b8fe3ed-3088-4847-a0e1-ea1676abc013/m08-probe-audit/REPORT.md`.
Exact file hashes for that revision were recorded in its own evidence
directory's `manifest.sha256`.

The follow-up fixes (physical wait-freeze enforcement after reset / zero-tick /
exhausted-budget returns with an independent-body test, non-reentrant
`begin_step()` refusals, fail-closed in-loop residual guard, per-tick trace
digests across three pacing modes, contract suite under three pacings) were
produced for the M0.8 Opus-recheck follow-up job against committed candidate
`d562755c83af1129b4ddf7043baee8d8a742d358`, following
`review/implementation/m0-tick-opus-recheck-64cbe5b0-7cc7-4130-80a3-cfc7d4d59f43.md`.
Hashes bind the reviewed candidate and the follow-up worktree contents in
`evidence/2026-11-27-apple-m4-max-jolt-waitguard/manifest.sha256`.

The API-edge follow-up fixes (negative request validated before terminal
fast paths, zero-tick completion published while frozen, cap-0 reset
observation starts truncated, `step_finished`-boundary frame accounting with
independent physics and signal-callback observations) were produced for the
M0.8 Sol-recheck follow-up job against committed candidate
`bdb0a9820b847d23628cce35a9070bb63ae17acd`, following
`review/implementation/m0-tick-sol-recheck-bdb0a98.md`. Hashes bind that
candidate and the follow-up worktree contents in
`evidence/2026-11-27-apple-m4-max-jolt-api-edges/manifest.sha256`.

The N1 server-step follow-up (deferred pause until after the final tick's
`PhysicsServer3D` step, counting-body regression, backstop rollback, runner
strictness, pacing metadata) responds to
`review/implementation/m0-tick-opus-5-5-bdb0a98-independent.md` for reported
candidate `bdb0a9820b847d23628cce35a9070bb63ae17acd`. The worktree also carries
the uncommitted Sol API-edge fixes described above; hashes distinguish the
reported candidate from the follow-up files in
`evidence/2026-11-27-apple-m4-max-jolt-n1-server-steps/provenance.json`.

The cold-start follow-up (fresh-first-request regression with counted
`_integrate_forces`, continuous registration-latency control, engine-frame
observation separation) was produced after that N1 revision; it supersedes
the earlier cold-start caveat. Hashes bind the worktree in
`evidence/2026-11-27-apple-m4-max-jolt-cold-start/manifest.sha256`. Engine:
Godot 4.7.2-stable (official). No third-party assets or network services.

The cold-start evidence manifest records the tested files at commit `8a5615c`.
This later README correction updates the example count from 76 to 77; the
probe source and test inputs are unchanged by that documentation-only update.
