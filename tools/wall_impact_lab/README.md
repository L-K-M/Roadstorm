# M1.8 wall-impact publication laboratory

Pure contract laboratory for `src/simulation/wall_impact_producer.gd`, the
bounded seam that turns one committed `MotorBodyAdapter.Result` carrying the
authoritative wall-response witness into an `ImpactEvent` record.

## Scope

This proves the producer and its use of the existing `ImpactEvent` builder and
ledger:

- a committed wall witness produces a valid event with caller-assigned IDs;
- all four regions classify from the collision-time local point against
  normalized hull half-extents; a contact within the measured 0.035 m corner
  band on both axes uses the response normal in that same frame when its
  dominant-axis sign borders the contacted quadrant, while diagonal or
  sign-inconsistent normals use the deterministic point rule;
- severity is only the stable norm of the witness pre/post velocity difference,
  for head-on and oblique contacts, including a large finite value;
- a tilted raw normal publishes only its normalized road-plane projection, and
  the generic first-contact normal is never substituted;
- `imparted_motion_m` is exactly zero even when the sweep's accepted travel is
  nonzero;
- every refused, incomplete or nonfinite witness fails closed with a reason,
  no event and no ledger mutation; the post velocity must agree with the
  committed state's mapped planar velocity exactly, including one-bit and
  small finite disagreements;
- a collision-time frame distinct from the final yaw frame controls the
  published local point and region;
- publication, identical-retry coalescing, conflicting-payload refusal,
  duplicate-perspective refusal and capacity behave through the real ledger;
- producing twice mutates neither the synthetic result nor the config.

The physical cases drive a pinned-Jolt head-on hit, mirrored steering
contacts, two nonzero-heading corner contacts and two narrow wall-end
transition streams through `tools/body_lab/body_lab_world.gd`. In both
steering directions, the old point-only rule labels 28 continuing
front-corner witnesses as a side; the response-normal rule labels all 29
witnesses FRONT. The speed 20 m/s, heading 0.9 rad, zero-throttle continuing
contact produces 33 witnesses, all LEFT with a stable left-dominant local
normal, including 27 outside the old 0.01 normalized tie band. The speed
35 m/s, heading 1.1 rad, steer +1 first hit is LEFT with severity
26.346 m/s while the old point rule names FRONT.

The narrow-wall cases use a centred 0.6 m wall, speed 20 m/s, heading
0.785398 rad and steer -1, with throttle 0 and 1. They produce 24 and 26
witnesses. After 21 and 24 preceding LEFT contacts, the measured wall-end
edge contacts at ticks 27 and 30 sit (0.01598, 0.02822) m and
(0.01576, 0.02880) m inside the side/end planes, have clearly left-dominant
normals (0.917, 0.399) and (0.914, 0.406), and have severities 5.381 and
6.401 m/s. The point rule names FRONT there, but the corner-normal rule
correctly publishes LEFT; the next tick in each stream is a genuine
clearly front-normal FRONT contact at 9.179 and 11.122 m/s. The frozen local
run passed 15 cases/1355 checks and the deliberate failure exited 3.

## Authority label

The Result fixtures are synthetic. They prove the producer's publication
contract; they are not proof that a witness came from a real committed physics
response. The pinned-Jolt cases add real witness paths but still do
not establish general physical authority, full M1.8 or M1 acceptance. The
0.035 m corner band is calibrated to this laboratory's 1.8 m x 3.8 m hull,
flat straight and narrow box walls, and the pinned Jolt build. It is a local
corner-classification capture width, not a solver tolerance. The independent
38,034-witness flat-wall sweep measured at most 0.0160 m inset in X and
0.0139 m in Z, independent of `orientation_contact_tolerance_m` across its
validated 0-0.1 m range; the narrow wall-end side contact reached 0.0288 m
inside the end plane. Other hulls, wall shapes or tolerances need fresh
pinned measurements before reusing or widening it. Car-car production,
sustained-contact policy, presentation wiring and cosmetic damage remain
later work.

## Files

| Path | Role |
| --- | --- |
| `validate_wall_impact_lab.gd` | headless `SceneTree` entry point |
| `wall_impact_lab_driver.gd` | cases, assertions, JSON result lines |
| `wall_impact_lab_checks.gd` | assertion collectors and synthetic fixtures |
| `failure_probe.gd` | deliberate failing-check proof (exit 3) |
| `run_wall_impact_lab.sh` | isolated staging, pinned engine, lock, timeouts |

## Running

```sh
tools/wall_impact_lab/run_wall_impact_lab.sh --help
tools/wall_impact_lab/run_wall_impact_lab.sh
tools/wall_impact_lab/run_wall_impact_lab.sh --log /path/to/validator.log
```

Use `--project`, `--godot`, `--lock`, `--timeout` and `--outer-timeout` to
point at a staged source snapshot, the pinned engine binary and the shared
test lock. Defaults resolve against the live checkout and the coordinator
`work/agents/coordinator/godot-test.lock`.

The runner stages a private copy outside the live checkout, verifies the
pinned engine version, runs a headless import, then runs the validator and the
deliberate failure probe. Every engine call is serialized on the shared lock
and wrapped in an outer timeout. Exit 0 means the validator reported
`"pass":true` with zero failed checks and the failure probe exited nonzero
with `"pass":false`.

## Result surface

One `WALL_IMPACT_LAB_RESULT <json>` line per case and one
`WALL_IMPACT_LAB_SUMMARY <json>` line, plus `CHECKS_TOTAL`/`CHECKS_FAILED`.
The summary records `witness_sources`, always sets
`physical_authority_verified: false`, and makes no full M1.8 or M1 acceptance
claim.
