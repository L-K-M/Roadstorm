# Handling benchmark fixtures

M0.9 handling-contract slice (job `b20cb153-94a8-4997-be00-1f8335daa1a0`).
Owned paths: `fixtures/handling/**`. The contract these files implement is
[`../../schemas/handling/handling_fixture.schema.json`](../../schemas/handling/handling_fixture.schema.json);
the checker is
[`../../schemas/handling/validate_fixtures.py`](../../schemas/handling/validate_fixtures.py).
Every fixture is derived from `docs/BENCHMARKS.md` ("Handling fixtures") and is
an authored initial contract, not a measurement. On 2026-11-27 the M0.9
integration pass added the missing `provenance.author` member (the authoring
job was previously recorded only inside `provenance.note`) so all four M0.9
fixture slices carry the same provenance shape, and recomputed the content
hashes; no authored value changed.

| File | BENCHMARKS row | Runs | Notable authored choices |
| --- | --- | --- | --- |
| `straight.json` | Straight: 500 m asphalt; standing and 30 m/s rolling starts; acceleration, braking, top speed, reverse | 4 | 12 m road width; 2 s brake trigger; 250 m intermediate marker (a position marker, unrelated to the brake command at t_s 2) |
| `sweeper.json` | Sweeper: 90 degrees, 120 m radius, 12 m width, 30 m/s entry, 50 m approach/exit | 2 (drift/grip) | left turn; scripted controllers reserved for M1 |
| `hairpin.json` | Hairpin: 180 degrees, 30 m radius, 18 m/s entry, 12 m width | 2 (drift/grip) | 30 m approach/exit; left turn |
| `esses.json` | Esses: two opposite 60-degree arcs, 65 m radius, 25 m/s entry | 2 (drift/grip) | 50 m approach, 20 m link, 50 m exit; 12 m width |
| `gravel.json` | Gravel: sweeper with an 80 m gravel sector and matching asphalt control run | 2 (gravel/asphalt control) | sector split into three arcs (30/80/78.4956 m) so each surface boundary is explicit; control run overrides the gravel segment to asphalt |
| `grounding.json` | Grounding: 12% climb/descent, bank +/-12 degrees, crest/compression, short jump with safe landing | 1 | segment lengths/radii and the 25 m/s entry speed; jump ramp geometry is null with unknowns entries |
| `contact.json` | Contact: maximum-speed frontal/oblique walls, head-on/rear-end/side pairs, four-car squeeze, blocked reset, correction-limit saturation | 8 | all maximum-speed entries are null with unknowns entries; barrier angles, pair offsets and the 500 m section are authored; wall spans (12 m) are authored so `wall_contact` is reconstructable while wall heights stay null with unknowns entries; the blocked-reset run documents the occupied-anchor precondition as course (M2) data it does not construct |
| `draft.json` | Draft: equal stock cars, 500 m straight, gaps 4/5/10/20/21 m and outside-cone controls | 6 (5 gaps + outside-cone control) | 30 m/s entry speed; 2.0 m lateral separation for the outside-cone control; the 4 m and 21 m gaps bracket the documented 5-20 m wake window and must not become drafting-eligible |

## What these files deliberately do not contain

* **No measured values.** Status is `provisional` and no metric uses status
  `measured`. Reference lap times, measured top speeds, grip coefficients and
  surge/draft magnitudes are M1/M4 reference-run records, not fixture content.
* **No invented undetermined numbers.** Maximum-speed contact entries and the
  jump ramp geometry are JSON null with matching `unknowns` entries; the
  validator rejects any null that is not explained.
* **No per-car handling coefficients.** Those live in each car's handling
  resource (`schemas/handling_config.schema.json`); the fixtures reference cars
  by stable ID and loadout, plus the handling resource revision they target
  (`cars.handling_revision`, null until M1 assigns it, with an unknowns
  entry).
* **No cross-cutting benchmark aggregates.** The mixed-loop elapsed-time
  target within 3%, the stock-car spread of at most 5% over an equal-weight
  mixed-course benchmark, the heavy-contact rate bound and the >=99%
  completion target are documented BENCHMARKS initial targets with no
  handling-fixture vehicle: the first two are closed-loop M2 course content
  and the last two are AI-evaluation measures. See the scope note in
  [`../../schemas/handling/README.md`](../../schemas/handling/README.md).
* **No course data.** Reset anchors, gates beyond the fixture section and
  scenery are M2 course content.

## Validating

```sh
python3 schemas/handling/validate_fixtures.py fixtures/handling
sh schemas/handling/run_tests.sh
```

Original project files under the Unlicense.
