# M1.8 impact-event contract laboratory

Pure contract laboratory for the committed impact-event record, its validating
builder and its bounded publication ledger (`src/simulation/impact_event.gd`).

## Scope

This proves the record and publication rules only:

- a complete record validates, and every required physical field refuses when
  it is omitted, even where a legal explicit value for the same field (zero
  severity, a zero contact point, a zero post-contact velocity, a zero
  imparted motion, `FRONT`) is indistinguishable from the default;
- `event_id` identifies one (physical contact, primary car) perspective, so
  both sides of a car-car contact publish two complementary records; the
  optional shared `contact_id` links them;
- an identical retry under a retained ID coalesces, while a conflicting
  payload under the same ID is refused and counted in `conflict_count` rather
  than silently discarded, covering same-tick and cross-tick conflicts;
- duplicate detection is bounded by the retained window, so it is not all-time
  ID memory; an identical retry still coalesces at per-tick capacity, and a
  pruned or reset ID publishes again as a fresh record;
- every refusal is atomic: the retained content digest is unchanged and only
  the diagnostic counters advance;
- the content digest and the payload comparison cover every published field,
  not a sampled subset;
- an out-of-domain `NormalMode` refuses, and finite admitted vectors cannot
  produce INF or NaN in an exported derived magnitude or in normalization,
  because the scaled norm is used instead of `Vector3.length()`;
- the ledger's capacity settings are not mutable public properties after
  construction, and their effective values are clamped, so a publication is
  never reported and pruned at once;
- the module references no motor, body adapter, `CarState`, physics server,
  scene node or race RNG type, and it publishes nothing on its own.

It does not implement the impact producer, does not integrate the motor/body
adapter, does not select physical contact points, and does not drive cosmetic
damage. It cannot prove that a published `severity_m_s` was physically derived
from the committed contact response: the `contact_only_severity_distinction`
case records `derivation_verified: false` deliberately. It makes no M1
acceptance claim.

## Files

| Path | Role |
| --- | --- |
| `validate_impact_lab.gd` | headless `SceneTree` entry point |
| `impact_lab_driver.gd` | cases, assertions, JSON result lines |
| `impact_lab_checks.gd` | assertion collectors and independent fixtures |
| `failure_probe.gd` | deliberate failing-check proof (exit 3) |
| `run_validation.sh` | isolated staging, pinned engine, lock, timeouts |

## Running

```sh
tools/impact_lab/run_validation.sh --help
tools/impact_lab/run_validation.sh
tools/impact_lab/run_validation.sh --log /path/to/validator.log
```

Use `--project`, `--godot`, `--lock`, `--timeout` and `--outer-timeout` to
point at a staged source snapshot, the pinned engine binary and the shared
test lock. The defaults resolve against the live checkout, which is not a safe
test target while other workers edit it.

The runner stages a private copy of the project outside the live checkout,
verifies the pinned engine version, runs a headless import, then runs the
validator and the deliberate failure probe. Every engine call is serialized on
the shared `godot-test.lock` and wrapped in an outer timeout. Exit 0 means the
validator reported `"pass":true` with zero failed checks and the failure probe
exited nonzero with `"pass":false`.

## Result surface

One `IMPACT_LAB_RESULT <json>` line per case and one `IMPACT_LAB_SUMMARY
<json>` line, plus `CHECKS_TOTAL`/`CHECKS_FAILED`. The `measurements` object
records values a reviewer should read directly, including
`adapter_wall_contact_point_present` (whether the inspected
`motor_body_adapter.gd` already exposes the authoritative wall contact point)
and `derivation_verified` (always false).
