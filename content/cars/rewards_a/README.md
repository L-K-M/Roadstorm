# Reward car recipes A (provisional)

Original version-1.1.0 handling source recipes for the first three reward cars
named in `docs/GAME_DESIGN.md` "Cars and garage":

| Stable ID | Display name | File | Character and unlock | Stock top speed |
| --- | --- | --- | --- | --- |
| `car.trailbox` | Trailbox | `trailbox.json` | Boxy rally hatch, gravel-confidence target; Coastal Cup completion | 219 km/h |
| `car.longshot` | Longshot | `longshot.json` | Broad muscle coupe, strong acceleration/straight target; Coastal Cup podium | 228 km/h |
| `car.meridian` | Meridian | `meridian.json` | Long grand tourer, calm fast-sweeper target; Highlands Cup completion | 233 km/h |

## Status

Every recipe is `status: "provisional"`, `revision: "0.1.0"`. Mass, dimensions,
top speed, acceleration curves and handling coefficients are plausible authored
placeholders, not measured values, not frozen tuning, and not a production
freeze. No 5% mixed-course pace spread is claimed or demonstrated. The stock top
speeds sit inside the documented 205-235 km/h target band; they are authored
targets, not verified performance. No gravel response, measured balance or
surface behaviour is claimed.

Upgrade factors follow the exact GAME_DESIGN level formulas for L = 0, 1, 2:
engine acceleration `1 + 0.03L` and top speed `1 + 0.015L`; tires grip damping
and drift-exit divisor `1 + 0.05L`; chassis yaw gain `1 + 0.04L` and impact-loss
`1 - 0.05L`. Recorded maxima are 6% acceleration and 3% top speed. These factors
are transcribed, not empirically validated.

## Missing empirical gates

- M1 handling benchmarks and calibration for every coefficient; no hardware,
  platform, lap-time or handling-fixture evidence exists for these files.
- Surge candidate selection (`selected_delta_m_s`) is deliberately null; M1
  chooses among 0.5/1.0/1.5 m/s.
- Airborne gravity and adhesion bounds are null; contact-proxy roof and underside
  profiles are null; drift stability-assist slip limit is null.
- `handling.surfaces` is empty: no per-car gravel or other surface-response
  modifier is authored. Trailbox's "confident on gravel" line is an unvalidated
  character target, not a measured response.
- Detachable parts, paint schemes, production art and asset references are
  absent.
- No gameplay, balance, upgrade-effect or release-readiness acceptance is
  claimed. This is not M0.2, M1 or release acceptance.

## Baked artifacts

The committed baker emits a `HandlingDefinition` `.tres` and a bake manifest for
each recipe. Those generated artifacts are kept under the ignored job directory
`work/agents/coordinator/reward-car-recipes-a-longcat-20261128/bake/` and do not
enter tracked content. See that job's `REPORT.md` for the bake commands, exit
codes and verification results.

## Provenance

Authored by job `reward-car-recipes-a-longcat-20261128` with model
`longcat/LongCat-2.5` (provider `longcat`) on 2026-11-28 UTC. Each file records
the committed canonical `content_hash` and the versioned source contract
`roadstorm.handling_config.1.1.0`.

Names and content are original fictional work for this project. No trademark,
license, asset-signature, CC0 or provider-rights claim is made, and no
third-party art, audio or code is included.
