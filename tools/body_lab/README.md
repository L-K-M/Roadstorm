# M1.1 motor/body adapter laboratory

Private one-car flat-ground laboratory for the `MotorBodyAdapter` seam between
the pure `ArcadeMotor` and one real `CharacterBody3D` in a Godot/Jolt world.

## Scope

This proves one 60 Hz integration tick at a time:

- the motor proposal is computed from immutable inputs;
- a nonmutating body-motion prediction precedes the single accepted
  `move_and_collide()` commit per substep, using the body's actual collision
  mask so both see the same collision set;
- invalid command/tuning/state/config/dt and over-envelope travel are refused
  with the body and caller state untouched;
- CarState x maps to world +X, CarState y to world -Z, and positive heading
  points the nose toward +X;
- a frontal or oblique thick static wall produces no tunneling at 65 m/s and
  leaves no inward normal velocity in the committed state;
- a rolled wall whose measured normal is `(sqrt(0.84), 0.4, 0)` leaves no
  inward road-plane velocity after the response resolves against the
  normalized horizontal projection of that normal;
- every contact of a multi-contact `move_and_collide()` result is collected, so
  a wall reported after a non-wall-like contact still drives the response,
  while generic telemetry stays the first reported contact;
- an unchecked yaw that would install the hull across a parallel wall is
  constrained to the largest safe fraction of the proposed yaw, or refused;
  clear open-ground steering still rotates freely;
- a gentle yaw below the former per-tick skip threshold (about 0.555 rad/s
  for the default tolerance and this hull) is probed on every committed tick,
  so a trailing hull corner cannot creep across a nearby parallel wall;
- when that probe shortens a proposed yaw, the proposal's longitudinal and
  lateral velocity scalars are reprojected into the applied heading before any
  wall response, so a blocked rotation is not published as velocity and no
  inward component is created solely by the rejected yaw fraction;
- a wall on a layer excluded from the car mask is crossed with the full
  physical motion committed and the primary prediction matching it, while the
  identical wall on an included layer still stops the car and the prediction;
- the wall response uses an authoritative wall-like normal that survives a
  later floor-like contact in the same tick, and a real pinned-Jolt wall
  contact reports and uses that normal;
- repeated fixed-60 Hz callbacks reproduce bit-identical traces.

It does not implement ground adhesion, jumps, drift, reset, surfaces,
multi-car contacts, controls or full car tuning. It makes no M1 acceptance
claim.

## Files

| Path | Role |
| --- | --- |
| `body_lab_entry.gd` | headless `SceneTree` entry point |
| `body_lab_driver.gd` | scenarios, assertions, JSON result lines |
| `body_lab_checks.gd` | assertion collectors and explicit laboratory fixtures |
| `body_lab_world.gd` | deterministic ground/wall/body staging |
| `run_body_lab.sh` | private staging, bounded import/run, log gate |

The adapter itself is `src/simulation/motor_body_adapter.gd`.

## Run

```sh
tools/body_lab/run_body_lab.sh \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
  --timeout 180
```

Options: `--project DIR`, `--case ID` (or `BODY_LAB_CASE`), `--keep-scratch`.
The runner copies only `project.godot`, `src`, `scenes`, `assets` and
`tools/body_lab` into a temporary stage, imports there, and runs the entry with
`--headless --fixed-fps 60`. The live checkout's `.godot/` cache is never
touched. Every engine invocation is bounded by the watchdog, and success
requires a `SLICE_SUMMARY` line containing `"pass":true`.

These scripts are not discovered by `tools/ci` (CI discovers `tests/` and
`tools/smoke/` only).

## Measured assumptions

- Pinned engine: Godot 4.7.2 Jolt, 60 Hz physics, `--fixed-fps 60` so one
  physics callback equals one 1/60 s tick.
- Support plane: flat +Y. Road-to-world mapping is fixed and heading
  independent; heading only rotates the nose frame.
- Hull: axis-aligned `BoxShape3D`, default 1.8 x 1.0 x 3.8 m. `Config` requires
  the actual shape to match its documented envelope.
- Sweep margin 0: on this engine a zero-margin `cast_motion` safe fraction
  reproduces the committed `move_and_collide()` travel; a nonzero margin stops
  the prediction early. The query also copies `body.collision_mask` (default
  physics shape queries test every layer, which would predict blockers the
  committed call ignores). `test_move` is recorded as a secondary diagnostic
  because it carries a depenetration/recovery offset near contacts.
- Default work cap: 16 substeps x 0.25 m = 4.0 m/tick (240 m/s), so a 65 m/s
  tick (1.083 m) is applied as five swept substeps against a 2 m thick wall.
  A constrained config demonstrates refusal above the cap.
- Absolute work bounds: `max_substeps` must be 1..32 and one substep at most
  1.0 m (below the 2 m lab wall and 3.8 m hull). The envelope product is
  required finite. `envelope_epsilon_m` may not exceed 1e-3 of a substep or
  1e-3 m absolute; `contact_stop_epsilon_m` may not exceed 1e-3 of a substep;
  sweep/commit margins may not exceed one substep. These bounds close the
  reported bypass where one substep plus a large epsilon returned COMMITTED
  after applying only part of a no-contact displacement. Any unapplied travel
  beyond the tight epsilon is now refused unless a genuine collision stopped
  the sweep; that case is reported through `remainder_m` and
  `contact_limited_remainder`.
- Wall response: remove the inward component along the normalized road-plane
  (horizontal) projection of the wall normal (restitution 0) and retain the
  configured tangential fraction (1.0). A normal whose road-plane projection is
  degenerate is guarded and leaves the velocity unchanged. Deflection shaping,
  restitution tuning, depenetration and multi-car response remain M1.4 work.
- Authoritative wall normal: `wall_hit` latches once any substep reports a
  wall-like normal. Every reported normal of every collision result is
  inspected, not just the default index, so one result listing a floor-like
  contact before a wall cannot hide the wall. The generic first-contact
  `contact_normal` is retained as diagnostic telemetry and is not the response
  input. All wall-like normals are retained, and after the sweep the
  road-plane-projected normal most opposed to the proposed world velocity
  (smallest dot product) is authoritative; the earliest contact wins an exact
  tie. The choice is exposed as `Result.wall_contact_normal`. This closes
  interim review N2: a later floor or ceiling contact can no longer replace the
  wall normal and leave inward wall velocity.
- Tilted-wall response regression: `tilted_wall_response` stages a real
  pinned-Jolt rolled wall with measured normal `(sqrt(0.84), 0.4, 0)`, drives
  the adapter into it at a 10 m/s approach directly against its horizontal
  projection, and checks `COMMITTED`, `wall_contact`, the measured normal and
  zero inward road-plane speed. On the pre-fix `4ff7bec` source the same case
  reports -1.600 m/s projected and -1.466 m/s full-normal residual inward
  speed, reproducing the reviewer finding; the fixed source measures zero.
- Multi-contact collection regression limit: a literal floor-first/
  wall-second physical batch was not reproduced. Pinned Jolt's
  `move_and_collide()` returned only motion-blocking contacts for horizontal
  motion; a raised deck, ground penetration and a steep-ramp/wall junction all
  produced either single-feature or repeated identical normals, never a
  floor-like contact preceding a wall. `multi_contact_collection` therefore
  injects a deterministic ordered `[floor, wall]` batch at the collection seam
  helper `_collect_collision_contacts()`, asserts the second wall candidate is
  retained while generic telemetry stays the first contact, and separately
  passes a real captured `KinematicCollision3D` through the same helper. The
  existing `wall_contact_normal_authority` selection-seam case remains a
  selector-level check, not end-to-end proof of collection order.
- Gentle-yaw regression: `gentle_yaw_wall_probe` runs 30 ticks at 0.5 rad/s
  (0.1 m/s with grip gain 5.0 and full opposite lock) beside a parallel wall
  5 cm from the hull's right side. The nose turns away from the wall so the
  trailing right corner sweeps toward it while the centreline velocity carries
  the car away. Steering the nose into the wall instead lets pinned Jolt
  depenetration recovery push the body back out every tick, which masks the
  yaw-only overlap this case exists to expose. The case checks the hull/wall
  plane bound on every committed tick, then drives an already-overlapping
  installed pose into a checked atomic `REFUSED_ORIENTATION`, and carries a
  geometric control showing the first six proposed yaw deltas would penetrate
  about 4.4 cm unchecked. Against a pre-fix control
  copy (`work/agents/f1-small-yaw/old_source_control`) the same case fails
  from tick 6 and reaches about 38.6 cm penetration; the fixed source
  constrains at tick 5 and stays within about 2.3 cm.
- Installed orientation: after the translation sweep, the adapter probes the
  final hull pose with a nonmutating `intersect_shape` query using the body's
  collision mask and excluding its RID. The probe runs for every nonzero yaw
  delta. The previous version skipped it whenever
  `0.5 * hull diagonal * |yaw delta| <= orientation_contact_tolerance_m`
  (about 0.555 rad/s for the default 0.02 m tolerance and this hull), leaving
  gentle per-tick yaw unconstrained; the parked-hull geometry from interim
  review F1 crosses the wall plane that way. The probe box is a real box hull
  reduced by twice the contact tolerance in every dimension, so touching
  contact and the pinned solver's penetration slop (0.02 m) do not count as
  overlap; this also keeps ordinary grounded floor contact from being
  rejected. A blocked yaw is reduced by a fixed 12-probe bisection; if even
  the tick-start heading overlaps, the tick is refused (`REFUSED_ORIENTATION`)
  with the body and inputs untouched. `orientation_contact_tolerance_m`
  defaults to 0.02 m (the pinned solver's penetration slop), is capped at
  0.1 m, and must stay below half the smallest hull extent so the reduced
  probe remains a positive box.
- Committed-velocity policy: when `heading_constrained` is true, the adapter
  reprojects `proposal.state.velocity_m_s` from the fully proposed nose frame
  into `applied_heading` by preserving its longitudinal and lateral scalar
  components. The two frames are orthonormal, so both scalars and the speed
  magnitude survive up to rounding; an unconstrained tick keeps the motor
  velocity untouched. The wall response still runs afterwards and only for a
  real wall-like contact, now against the reprojected velocity. A translation
  chord that never touches a wall therefore gets no inward velocity from the
  yaw fraction the probe refused. The policy removes only that rejected-yaw
  contribution: an inward component carried by the accepted translation or by
  a pre-existing lateral scalar remains until a real contact response. It does
  not scrub tangential speed without contact.
- Yaw-constrained velocity regression: `yaw_constrained_velocity_policy`
  stages a real pinned-Jolt parallel wall 5 cm from the hull's right side. The
  car carries a -0.5 m/s lateral component away from the wall at 2 m/s forward
  and steers fully right with yaw gain 9.0 (about 0.3 rad/tick proposed), so
  the translation chord moves away and produces no wall hit while the yawed
  hull corner would cross the wall. Eight ticks assert the committed pose
  basis, heading, finite state, exact reprojection of the proposal's scalars,
  preserved speed bound, nonzero lateral scalar, and that the removed
  rejected-yaw vector points into the wall and leaves the committed velocity
  non-inward. Against the pre-policy `915ad48` adapter in an isolated control
  project the same case fails on the first tick (0.534 m/s reprojection
  error, full-proposal velocity published into the wall) and later ticks then
  collide. A clean-ground control with identical steering asserts no
  constraint and exact motor-velocity passthrough.
- Orientation probe limits: the probe checks only sampled orientations (tick
  start, proposed pose, and the bisection midpoints), never every intermediate
  rotation; contact along a yaw arc is not guaranteed monotonic, so the
  bisection falls back to the verified tick-start heading if its own final
  candidate still overlaps. The probe reports any collider in the body mask,
  floors and ramps included, not only wall-like normals. Flat-ground staging
  keeps the floor outside the reduced box, but adhesion, kerbs and ramp
  integration require a support-aware probe before this constraint can be
  applied there. The installed hull may legitimately sit up to roughly the
  contact tolerance (measured about 5 mm past the nominal shrink) inside wall
  geometry; that is inside the 3 cm laboratory no-tunnel gate.
