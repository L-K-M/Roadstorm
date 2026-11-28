# Starter car recipes (provisional)

Original version-1.1.0 handling source recipes for the three starters named in
`docs/GAME_DESIGN.md` "Cars and garage":

| Stable ID | Display name | File | Stock top speed |
| --- | --- | --- | --- |
| `car.sparrow` | Sparrow | `sparrow.json` | 212 km/h |
| `car.balanced_starter` | Comet | `comet.json` | 222 km/h |
| `car.slidewinder` | Slidewinder | `slidewinder.json` | 230 km/h |

## Status

Every recipe is `status: "provisional"`, `revision: "0.1.0"`. Mass, dimensions,
top speed, acceleration curves and handling coefficients are plausible authored
placeholders, not measured values, not frozen tuning, and not a production
freeze. No 5% mixed-course pace spread is claimed or demonstrated. The stock top
speeds sit inside the documented 205-235 km/h target band; they are authored
targets, not verified performance.

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
  profiles are null; surface modifiers, detachable parts and production art are
  absent.
- Drift stability-assist slip limit is null.
- No gameplay, balance, upgrade-effect or release-readiness acceptance is
  claimed.

## Provenance

Authored by job `starter-car-recipes-longcat-20261128` with model
`longcat/LongCat-2.5` (provider `longcat`) on 2026-11-28 UTC. Each file records
the committed canonical `content_hash` and the versioned source contract
`roadstorm.handling_config.1.1.0`.

Names and content are original fictional work for this project. No trademark,
license, asset-signature or provider-rights claim is made, and no third-party
art, audio or code is included.
