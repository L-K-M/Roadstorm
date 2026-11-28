# M0.2 car-DRAFT mapper lab

Pinned-Godot checks for `src/data/car_recipe_mapper.gd`. The lab parses the
committed positive source recipe through Godot's JSON reader and the committed
`HandlingRecipeMapper`, then maps it to a partial typed `CarDefinition` with
`CarRecipeMapper.map_draft(recipe, handling)` and exercises refusals. It is a
pure in-memory mapping check: no `.tres`, bake manifest or provenance artifact
is written, and full JSON Schema/strict-parse/content-hash validation stays
with `tools/car_recipe_schema/validate_car_recipe.py`.

## Prerequisites

- Pinned Godot editor at
  `work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`
  printing `4.7.2.stable.official.ed1daf0bf`.
- POSIX shell, `rsync` or `tar`, `mktemp`, and the shared coordinator lock.
- Run from the repository root of an isolated checkout copy; the runner stages
  its own private project and XDG cache/config/data directories and never
  writes the live checkout's `.godot/` cache.

## Run

```sh
timeout 600 lockf -k -w -t 600 work/agents/coordinator/godot-test.lock \
  sh tools/car_draft_lab/run_validation.sh --case all \
  --log <ignored-job-dir>/car_draft_lab.log
```

Options: `--project DIR`, `--godot BIN`, `--private-dir FRESH_DIR`,
`--timeout SECONDS` (default 180, maximum 180; every engine command is also
watchdog-bounded), `--log FILE`, `--case <id>|all|intentional_failure`.
`--private-dir` must not already exist; it is atomically reserved and staged.

Exit codes:

- `0`: every selected case passed and the deliberate-failure proof exited
  nonzero with its assertion marker;
- `1`: a validator check or output gate failed;
- `2`: unsafe arguments or unusable/mismatched engine.

The validator prints `CAR_DRAFT_LAB_STAGE preloads_resolved=1` only after every
preloaded class parsed, per-case lines, `CAR_DRAFT_LAB_RESULT {json}`,
`CHECKS_TOTAL=n CHECKS_FAILED=n`, and exits `0`/`1`. The runner separately
fails on any engine `SCRIPT ERROR` / `Parse Error` / `ERROR:` line, labeling it
a parse/load failure rather than an assertion failure. `--case
intentional_failure` asserts a false expectation about a valid draft and must
exit nonzero with `INTENTIONAL_FAILURE_PROOF ... "pass":false` plus the
`intentional failure probe` marker.

## Cases

| Case | Coverage |
| --- | --- |
| `positive_fixture_mapping` | `example_rookie_finite.json` parsed through JSON + `HandlingRecipeMapper`; mapped identity/version/status/dimensions/mass/contact/handling; completeness INCOMPLETE with the fixed note and exact `DEFERRED_FIELDS_V1`; optional nulls; source nonmutation; full car validation |
| `positive_unlimited_fixture_mapping` | `example_rookie_unlimited.json` maps its `{"unlimited": true}` yaw to positive Godot INF and produces a fully valid INCOMPLETE draft with the same honest limits |
| `optional_null_preservation` | authored null wheelbase/clearance/jump stay null and validate; a resolved optional dimension listed in `unknowns` is refused |
| `version_units_frame_refusals` | 1.0.0 refusal naming the five missing handling paths, unsupported/mistyped/missing/trailing-newline versions, missing/wrong units, missing/wrong coordinate frame axes/origin |
| `handling_agreement_refusals` | missing handling; wrong derived ID, revision, status or typed schema version; physically invalid referenced handling |
| `required_mapped_field_refusals` | missing/null/unknown required dimensions, mass and contact shape; unknown ancestor; malformed contact proxy/shape/derived_from; resolved optional text/number listed as unknown; missing optional member |
| `invalid_dimensions_and_contact_refusals` | out-of-envelope/nonfinite/mistyped dimensions, zero/negative/nonfinite mass, inconsistent optional dimensions, mistyped contact roof/underside |
| `no_half_mapped_result` | every refusal returns `ok=false`, no car and path-level diagnostics; success is fully valid, INCOMPLETE and honestly noted |

## Limits

- Pure in-memory mapping only: no scene, body, physics query, clock,
  rendering, audio device, input routing, motor integration, `.tres` write,
  bake manifest or gameplay claim.
- The fixture is the authored synthetic example recipe, not measured handling
  or production car content.
- The external source checker remains the authority for JSON Schema, strict
  parsing, duplicate members, canonical content hash and source
  null/`unknowns` pairing; this lab defends only against direct malformed
  dictionaries reaching the mapper.
- Only identity, dimensions including optional nulls, intact mass, contact
  shape/roof/underside and the typed handling reference are mapped. Every
  `DEFERRED_FIELDS_V1` field stays absent and no coefficient is guessed.
- The draft is always INCOMPLETE; validation alone does not authorize a motor,
  a measured status or product-complete content.
- Headless pinned local engine only; no cross-version, exported-template,
  platform, controller, visual or release claim.
