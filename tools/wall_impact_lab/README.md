# M1.8 wall-impact publication laboratory

Pure contract laboratory for `src/simulation/wall_impact_producer.gd`, the
bounded seam that turns one committed `MotorBodyAdapter.Result` carrying the
authoritative wall-response witness into an `ImpactEvent` record.

## Scope

This proves the producer and its use of the existing `ImpactEvent` builder and
ledger:

- a committed wall witness produces a valid event with caller-assigned IDs;
- all four regions classify from the collision-time local point against
  normalized hull half-extents; a solver-near-tie corner uses the response
  normal in that same frame to identify the struck face;
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

The physical cases drive a pinned-Jolt head-on hit and mirrored steering
contacts through `tools/body_lab/body_lab_world.gd`. In both steering directions,
the old point-only rule labels 28 continuing front-corner witnesses as a side;
the response-normal rule labels all 29 witnesses FRONT. The frozen local run
passed 13 cases/906 checks and the deliberate failure exited 3.

## Authority label

The Result fixtures are synthetic. They prove the producer's publication
contract; they are not proof that a witness came from a real committed physics
response. The pinned-Jolt cases add real witness paths but still do
not establish general physical authority, full M1.8 or M1 acceptance. Car-car
production, sustained-contact policy, presentation wiring and cosmetic damage
remain later work.

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
