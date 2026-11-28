# M0.2 typed-resource data lab

Pinned-Godot checks for `src/data/definition_identity.gd`,
`src/data/handling_definition.gd`, `src/data/car_definition.gd` and the pure
source-recipe mapper `src/data/handling_recipe_mapper.gd`. The lab exercises
in-memory validation, `.tres` save/load round trips, source-to-typed handling
mapping, negative and nonfinite physical controls, dimensional bounds, identity
rules, completeness semantics and a deliberate failing assertion.

## Run

```sh
timeout 600 lockf -k -w -t 600 work/agents/coordinator/godot-test.lock \
  sh tools/data_lab/run_validation.sh --case all \
  --log <ignored-job-dir>/data_lab_main.log
```

Options: `--project DIR`, `--godot BIN`, `--private-dir FRESH_DIR`,
`--timeout SECONDS`, `--log FILE`, `--case <id>|all|intentional_failure`.
`--timeout` defaults to 180 and rejects values above 180; every engine command
is additionally watchdog-bounded. The runner stages an isolated project copy
with private XDG cache/config/data directories, so the live checkout's
`.godot` cache is never written.

Exit codes:

- `0`: every selected case passed and the deliberate-failure proof exited
  nonzero with its assertion marker;
- `1`: a validator check or output gate failed;
- `2`: unsafe arguments or unusable/mismatched engine.

## Cases

| Case | Coverage |
| --- | --- |
| `valid_in_memory_definition` | valid synthetic handling/draft car, identity grammar, units/frame constants, tuning projection, explicit deferred list |
| `tres_round_trip` | `.tres` save/load into a reserved scratch directory, curve/scalar/dimensional/contact/completeness equality, full referenced-handling comparison plus altered-ID/curve detection controls, rebound loaded handling; the car references an external handling resource, not an embedded subresource |
| `enum_domain_controls` | out-of-range direct status/contact-proxy-shape/completeness assignments (including negative values), a hand-authored malformed `.tres`, and safe `status_name()` on invalid status |
| `handling_diagnostic_attribution` | referenced handling identity/status/schema defects are reported as `handling.*`, distinct from the car's own paths even when both records carry the same defect, and physical diagnostics are not doubled |
| `deferred_fields_declaration` | draft/incomplete declarations must list every `DEFERRED_FIELDS_V1` path exactly once; arbitrary, missing-one-field, duplicate and blank/whitespace-only entries fail while a full or nonblank extended declaration validates |
| `scratch_reservation_control` | unique atomic scratch reservation per run, distinct reservations, owned-content cleanup scope, and byte-identical sentinels at the legacy fixed `res://data_lab_*_roundtrip.tres` paths |
| `scratch_cleanup_controls` | a reservation holding only known outputs is emptied and removed; unexpected, nested-directory and hidden entries are retained, reported and byte-checked; a separate test-only teardown then removes only those exact fixtures after re-verifying type and bytes, removes the now-empty reservations, and asserts no `data_lab_scratch_*` residue remains; legacy sentinels stay unchanged |
| `malformed_identity_controls` | unsupported schema version, malformed IDs/revisions including trailing-newline whole-string controls, empty display name, and the same identity defects in a referenced handling |
| `negative_and_nonfinite_physical_controls` | negative/nonfinite braking, drag, yaw, damping, reverse bounds and consistency; bad/unsorted/empty curves |
| `dimensional_bounds` | length/width/height envelopes, wheelbase/clearance/jump consistency, mass, inclusive boundaries accepted |
| `missing_handling_and_curve` | missing handling reference, empty referenced curve, minimal one-point handling |
| `completeness_semantics` | draft/incomplete notes and deferred lists, refusal of false `COMPLETE` in this partial slice, complete-with-deferred contradiction, blank entries |
| `curve_accessor_safety` | mismatched curve arrays refuse a truncated point view; atomic refusal of null point input |
| `source_handling_mapping_finite` | valid 1.1.0 finite recipe maps to derived identity, copied revision/status, typed version 1.0.0, boundary reverse values, rad/s yaw exception and source-dictionary nonmutation |
| `source_handling_mapping_unlimited` | exact `{"unlimited": true}` sole-member encoding maps to positive Godot `INF`; lower-bound trigger and nonzero reverse drive validate; source nonmutation |
| `source_handling_mapping_refusals` | 1.0.0 refusal naming all five missing paths, unsupported/mistyped versions, missing/null/unknown motor inputs (including an unknown ancestor), missing parent/path, empty/unordered/duplicate/non-object/missing-member curves, invalid revision, bad status/identity/display name and wrong angle unit; refusals return no half-valid resource |
| `source_handling_mapping_numeric_honesty` | NaN/infinity/overflow, boolean and numeric-string inputs refused, range bounds enforced after float conversion, rejected yaw encodings, reverse cross-field rule, non-finite curve points, exact int-to-float conversion and refusal-time source nonmutation |
| `source_handling_mapping_review_repairs` | null plus matching `unknowns` reports unresolved rather than resolved-but-unknown; resolved curve-point members listed unknown refuse, including a leading-zero `[00]` index alias for point 0; length, mass and time unit mismatches refuse on direct mapper calls |
| `source_handling_mapping_json_fixtures` | the two committed checker-positive motor-ready JSON files parse in Godot and map to the expected typed identity and finite/unlimited yaw kind |

`--case intentional_failure` clears a curve and asserts that it remains valid;
that assertion must fail. The runner requires the
`INTENTIONAL_FAILURE_PROOF` line, `"pass":false` and the
`intentional failure probe` marker so a parse/load error cannot masquerade as
failure detection.

## Scratch ownership

Round-trip saves go to a fresh `res://data_lab_scratch_<stamp>_<ticks>_<pid>_<attempt>/`
reserved with an atomic `mkdir`. Cleanup removes only the exact file names this
validator creates inside a reservation (`handling_roundtrip.tres`,
`car_roundtrip.tres`, `bad_enum.tres`, `owned.txt`), and only after checking
they are not directories. Any other entry, including nested directories and
hidden files, is retained, printed to stderr and listed in the report's
`scratch_cleanup_reports`; the reservation directory is removed only when
nothing remains. Cleanup never recurses, so a symlinked directory cannot be
traversed. Production cleanup deliberately leaves such entries behind. The
`scratch_cleanup_controls` case then performs a separate test-only teardown:
it re-checks each exact captured fixture path for the expected basename,
regular-file type and unchanged bytes, removes only those files, removes the
now-empty subdirectory and reservations, and fails (retaining and reporting)
on any changed or unexpected state. It uses no recursive removal, no glob
cleanup and no symlink traversal, and ends by asserting no `data_lab_scratch_*`
entry remains under `res://`. The validator is read-only at the legacy fixed
`res://data_lab_handling_roundtrip.tres` and `res://data_lab_car_roundtrip.tres`
paths: it never opens them for write and never removes them.
`run_validation.sh` populates distinct sentinel files in its own freshly reserved
private stage before invoking the validator (checked absence plus noclobber
redirection). The `scratch_reservation_control` case requires both sentinels to
exist, captures their bytes, reserves scratch, writes owned content inside the
reservation, cleans up only those reservations, then requires the sentinel bytes
unchanged. A direct execution without externally prepopulated sentinels fails
loudly instead of claiming preservation coverage.

## Output and parse-vs-assertion distinction

The validator prints `DATA_LAB_STAGE preloads_resolved=1` only after every
preloaded class parsed, then per-case lines, `DATA_LAB_RESULT {json}`,
`CHECKS_TOTAL=n CHECKS_FAILED=n` and exits `0`/`1`. The runner separately
fails on any engine `SCRIPT ERROR` / `Parse Error` / `ERROR:` line in the
import, validator or proof logs and labels it a parse/load failure rather than
an assertion failure. Godot can exit `0` after a script load failure, so the
captured log inspection is authoritative.

The hosted CI workflow also runs `--case all` and the deliberate failure proof
with the pinned Godot build. Exact `c4b99fd` ran 19 cases and 537 checks in
hosted CI. The later frozen-source leading-zero alias repair passes 19 cases
and 541 checks; its same repair case on the prior mapper fails 26 of 35
assertions.

## Limits

Pure in-memory mapping and resource checks only: no scene, body, physics query,
clock, rendering, audio, input routing, motor integration or gameplay claim.
The mapper writes no `.tres`, bake manifest or provenance sidecar, and full JSON
Schema/strict-parse/content-hash validation remains an external prerequisite
owned by `tools/car_recipe_schema/validate_car_recipe.py`. Fixtures are
synthetic `example.data_lab.*` EXAMPLE resources with arbitrary authored
numbers, not measured handling or production content. The default handling
fixture uses the documented derivation `example.data_lab.car.handling`; the
typed validator accepts any valid handling reference and does not enforce that
derivation. `.tres` coverage is
limited to this slice's fields on the pinned local engine and does not prove
behavior across other Godot versions or exported templates.
