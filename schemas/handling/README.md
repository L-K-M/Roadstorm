# Handling contract: schema, fixtures and validator

M0.9 handling-contract slice (job `b20cb153-94a8-4997-be00-1f8335daa1a0`, model
`step-5-preview`, provider `stepfun-ai-step-plan`, authored 2026-11-26).
Owned paths: `schemas/handling/**` and `fixtures/handling/**`. Nothing else in
the tree was modified; existing partial schemas
(`schemas/handling_config.schema.json`, `schemas/ai_observation.schema.json`,
`schemas/common.schema.json`) are referenced, not edited. (The partial
`ai_observation.schema.json` was touched once afterwards, on 2026-11-27, by the
M0.9 integration pass that gave it its own non-ratified layout revision
`ai_shared_partial_v0` so it no longer collides with the accepted
`schemas/observation/observation_record.schema.json`'s `ai_shared_v1`; nothing
in this slice depends on it.)

This slice implements the handling-fixture half of PLAN.md M0.9: "Create
versioned handling/AI/reference/scenario schemas and fixture configurations
from BENCHMARKS; schema definitions do not require a working AI implementation
yet." The AI observation schema (`ai_observation.schema.json`) and the per-car
handling configuration schema (`handling_config.schema.json`) are separate
contracts owned elsewhere; this directory adds the **benchmark fixture**
contract that ties them to `docs/BENCHMARKS.md` ("Handling fixtures").

## Files

| Path | Role |
| --- | --- |
| `handling_fixture.schema.json` | Versioned machine-readable fixture contract (draft 2020-12 JSON Schema), schema version 1.0.0. |
| `validate_fixtures.py` | Standard-library validator: required fields, numeric ranges, revision identifiers, and the null/unknown honesty rule. Also usable as a library. |
| `tests/test_handling_fixtures.py` | `unittest` suite: the shipped artifacts must validate, and 43 deliberately broken copies and consistency mutations must be rejected with specific finding codes (59 tests in total). |
| `run_tests.sh` | Runs the suite; a failing check exits nonzero. |
| `../../fixtures/handling/*.json` | The eight authored fixtures, one per BENCHMARKS handling-fixture table row. |

## The contract in one paragraph

A fixture declares immutable source geometry (head-to-tail straight/arc
segments with width, grade, banking and surface), declared surfaces, optional
barriers (position, face angle, thickness and authored span/height) and route
features (crest/compression/jump), one or more runs (initial
pose/velocity plus a scripted `DriverCommand` schedule or a named controller
revision, plus optional other participants for pair/squeeze/draft runs),
timing gates, expected events with optional per-run applicability, a comparison
block (purpose, required clean paired runs, and acceptance metrics), the car
set (car IDs, loadouts and the targeted handling revision), unknowns, a content
hash and provenance. Units are m, kg, s, deg and m/s for speed; the frame
is -Z forward, +Y up, +X right, matching `handling_config.schema.json`.

## Rules the validator enforces

* **Required fields.** All 19 top-level members, per-segment members by
  segment type, non-empty titles/descriptions/purposes, and the gate set must
  contain exactly one start and one finish gate.
* **Closed objects.** The schema sets `additionalProperties: false` at the
  root and in every `$defs` object; the validator rejects undeclared members
  instead of ignoring them.
* **Invalid ranges.** Segment length/radius/width > 0; arc angle in (0, 360];
  grade within +/-12% and banking within +/-12 degrees (TECHNICAL_DESIGN
  initial targets); `steer` in [-1, 1]; throttle/brake/handbrake in [0, 1];
  gates and barriers inside their segment's authored length; surface, run,
  participant and gate references must resolve; at most seven other
  participants (eight cars total).
* **Revision identifiers.** `schema_version` must equal the implemented
  contract revision (a mismatch is rejected, never migrated); `revision` must
  be dotted-numeric; `content_hash` must recompute exactly over canonical JSON
  (sorted keys, compact separators, UTF-8) with the `content_hash` member
  removed; `controller_revision` and `cars.handling_revision` are each either
  a non-empty string or a null that carries an unknowns entry.
* **Metric bounds.** Metric bound members follow the comparator, matching
  `schemas/common.schema.json` (`acceptance_metric`): threshold comparators
  require a numeric `value` and no range bounds; `range`/`ratio_range` require
  `value_min`/`value_max` and no `value`; `report` carries no bound at all.
* **Honesty rule.** Every JSON null must be listed in `unknowns` with a path
  and reason, and every `unknowns` entry must resolve to a member of the
  document (an absent section is declared as an explicit null, never pointed
  at from nowhere). No fixture may use metric status `measured`: fixtures
  carry authored initial values and documented design targets, never measured
  outcomes. Maximum-speed contact entries are therefore `null` with an
  explanation that the documented 205-235 km/h stock range is a target, not a
  measurement.
* **Draft wake window.** In the draft family, runs required to become
  `drafting_eligible` must sit inside the GAME_DESIGN documented 5-20 m wake
  window and +/-10 degree cone, and a declared `wake_gap_window_m` metric must
  agree with that documented window. The BENCHMARKS 4 m and 21 m gaps bracket
  the window, so neither may be required to become eligible.

## Deliberate limitations

* The validator is standard-library only and standalone; it does not run the
  engine, execute a fixture, or judge physics. A valid fixture is a well-formed
  contract, not a passing test.
* It implements the contract's rules in Python rather than evaluating the full
  JSON Schema semantics; `handling_fixture.schema.json` remains the text
  contract of record. No `jsonschema` dependency is introduced.
* Authored initial values that BENCHMARKS does not fix (approach/exit lengths,
  linking straights, the esses/hairpin turn direction, barrier angles, the 30
  m/s draft entry speed) are marked in segment/run notes as authored. They are
  authoring choices, not measurements, and are not listed as unknowns.
* Reset-anchor occupancy for the blocked-reset run is expressed as expected
  events plus prose; anchor data itself is course-level (M2) content. The
  contact fixture therefore documents the occupied-anchor precondition as
  course data it does not construct, rather than claiming it builds the
  occupancy.
* Cross-cutting BENCHMARKS acceptance targets are not handling-fixture
  content. The mixed-loop elapsed-time target within 3% and the stock-car
  spread of at most 5% over an equal-weight mixed-course benchmark
  (BENCHMARKS "Handling fixtures") are closed-loop, multi-course aggregates:
  handling fixtures are open sections by contract, mixed loops are M2 course
  fixtures, and no `fixture_family` row exists for them. The heavy-contact
  rate bound and the >=99% completion target (BENCHMARKS "AI metrics") are
  AI-evaluation measures owned by the scenario/reference slice. All four
  remain documented initial targets, never measurements; their absence here
  is a recorded scope decision, not an oversight.
* `fixtures/handling/` files are not wired into `tools/ci/contracts.list` or
  `tools/ci/ci.sh` here: that inventory is owned by `tools/ci/**`. The
  validator is runnable standalone (see below) and ready to be wired in by the
  CI owner.

## Running

```sh
# validate the shipped fixtures and the schema document
python3 schemas/handling/validate_fixtures.py

# validate specific files or directories
python3 schemas/handling/validate_fixtures.py fixtures/handling/sweeper.json

# run the test suite (shipped-artifact checks + rejection checks)
sh schemas/handling/run_tests.sh
```

Exit codes: 0 = no errors (warnings are printed but do not fail), 1 =
validation errors, 2 = a path could not be read or the command line was wrong.
A file that is not JSON or not UTF-8 is a content defect (exit 1); a missing
path is an environment problem (exit 2).

## Regenerating content hashes

`content_hash` covers the file with the `content_hash` member removed. After
any semantic edit to a fixture, bump `revision` and recompute the hash, e.g.:

```sh
python3 - <<'EOF'
import json, sys
from pathlib import Path
sys.path.insert(0, "schemas/handling")
from validate_fixtures import load_json_document, content_hash_of
for path in sorted(Path("fixtures/handling").glob("*.json")):
    doc, _ = load_json_document(path)
    doc["content_hash"] = content_hash_of(doc)
    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
EOF
```

Original project code under the Unlicense.
