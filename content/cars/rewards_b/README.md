# Reward car recipes (provisional)

Original version-1.1.0 handling source recipes for three reward cars named in
`docs/GAME_DESIGN.md` "Cars and garage" and "Career and rewards":

| Stable ID | Display name | Silhouette and character | Accel / speed / grip / drift / stability | Cup award | File | Stock top speed |
| --- | --- | --- | --- | --- | --- | --- |
| `car.rook` | Rook | Rally sedan, flexible and planted | 4 / 3 / 5 / 3 / 4 | Highlands Cup podium | `rook.json` | 221 km/h |
| `car.sandhammer` | Sandhammer | Low racing pickup, weighty and playful | 5 / 3 / 3 / 4 / 4 | Skyline Cup completion | `sandhammer.json` | 218 km/h |
| `car.prism` | Prism | Low exotic wedge, sharp and fast | 3 / 5 / 4 / 4 / 3 | Skyline Cup podium | `prism.json` | 233 km/h |

## Status

Every recipe is `status: "provisional"`, `revision: "0.1.0"`. Mass, dimensions,
top speed, acceleration curves and handling coefficients are conservative
original placeholders that express each car's documented silhouette and
relative authoring target within one shared competitive class. They are not
measured values, not frozen tuning and not production data. No
score-to-coefficient mapping, mixed-course pace spread, balance or
release-readiness claim is made or demonstrated. The stock top speeds sit
inside the documented 205-235 km/h target band; they are authored targets, not
verified performance.

The five scores are the documented relative 1-5 authoring targets, transcribed
from `docs/GAME_DESIGN.md`, not multipliers. The three files distinguish
themselves through mass, dimensions, top speed, acceleration curve, drag, yaw
gain, lateral damping and yaw-rate cap. The distinction is plausible and
provisional only; it is not the result of any handling fixture.

Upgrade factors follow the exact `docs/GAME_DESIGN.md` level formulas for
L = 0, 1, 2: engine acceleration `1 + 0.03L` and top speed `1 + 0.015L`; tires
grip damping and drift-exit divisor `1 + 0.05L`; chassis yaw gain `1 + 0.04L`
and impact-loss `1 - 0.05L`. Recorded maxima are 6% acceleration and 3% top
speed. These factors are transcribed, not empirically validated.

## Unknowns and calibration

Calibration is still due. The following members are JSON `null` and are each
paired with an `unknowns` path:

- `engine.acceleration_curve`: the engine/handling curve duplication is
  unresolved in the 1.1.0 slice; only `handling.acceleration_curve` carries
  the provisional authored curve.
- `handling.drift.stability_assist_max_slip_deg`: not measured;
  stability-assist tuning awaits the M1 handling benchmark.
- `handling.surge.selected_delta_m_s`: null until M1 compares the
  0.5/1.0/1.5 m/s candidates and records one selection.
- `handling.airborne.gravity_m_s2` and `handling.airborne.adhesion_bounds`:
  not measured or authored; deferred pending M1 calibration.
- `contact_proxy.roof` and `contact_proxy.underside`: contact proxy roof and
  underside profiles not authored; only the simplified declared-dimension hull
  exists.

`handling.surfaces` and `detachable_parts` are empty; no per-surface gravel
modifier or detachable part is asserted. No gameplay, balance, upgrade-effect
or production-art acceptance is claimed.

## Provenance

Authored by job `reward-car-recipes-b-longcat-20261128` with model
`longcat/LongCat-2.5` (provider `longcat`) on 2026-11-28 UTC, through the known
standard public provider route `pi-longcat`. Each file records the canonical
`content_hash` and the versioned source contract
`roadstorm.handling_config.1.1.0`.

Names and content are original fictional work for this project. No trademark,
license, asset-signature or provider-rights claim is made, and no third-party
art, audio or code is included. The standard public provider route is known,
but Unlicense/CC0 release-rights clearance remains unresolved; see
`provenance/PROVIDER_TERMS.md`, where the route is OPEN/BLOCKING. Nothing here
claims rights clearance.

## Verification

The committed standard-library checker runs in `motor-ready` mode on exactly
these three JSONs. Pinned-engine bake results, manifests and their SHA-256
values are recorded in the ignored job report at
`work/agents/coordinator/reward-car-recipes-b-longcat-20261128/REPORT.md`.
A passing bake is evidence for these provisional artifacts only; it is not M0.2,
M1, milestone, rights or tuning acceptance.
