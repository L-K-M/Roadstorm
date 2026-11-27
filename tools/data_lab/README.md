# M0.2 typed-resource data lab

Pinned-Godot checks for `src/data/definition_identity.gd`,
`src/data/handling_definition.gd` and `src/data/car_definition.gd`. The lab
exercises in-memory validation, `.tres` save/load round trips, negative and
nonfinite physical controls, dimensional bounds, identity rules, completeness
semantics and a deliberate failing assertion.

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
| `malformed_identity_controls` | unsupported schema version, malformed IDs/revisions including trailing-newline whole-string controls, empty display name, and the same identity defects in a referenced handling |
| `negative_and_nonfinite_physical_controls` | negative/nonfinite braking, drag, yaw, damping, reverse bounds and consistency; bad/unsorted/empty curves |
| `dimensional_bounds` | length/width/height envelopes, wheelbase/clearance/jump consistency, mass, inclusive boundaries accepted |
| `missing_handling_and_curve` | missing handling reference, empty referenced curve, minimal one-point handling |
| `completeness_semantics` | draft/incomplete notes and deferred lists, refusal of false `COMPLETE` in this partial slice, complete-with-deferred contradiction, blank entries |
| `curve_accessor_safety` | mismatched curve arrays refuse a truncated point view; atomic refusal of null point input |

`--case intentional_failure` clears a curve and asserts that it remains valid;
that assertion must fail. The runner requires the
`INTENTIONAL_FAILURE_PROOF` line, `"pass":false` and the
`intentional failure probe` marker so a parse/load error cannot masquerade as
failure detection.

## Scratch ownership

Round-trip saves go to a fresh `res://data_lab_scratch_<stamp>_<ticks>_<pid>_<attempt>/`
reserved with an atomic `mkdir`. Cleanup removes only directories this validator
run reserved. The validator is read-only at the legacy fixed
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

## Limits

Pure resource checks only: no scene, body, physics query, clock, rendering,
audio, input routing, motor integration or gameplay claim. Fixtures are
synthetic `example.data_lab.*` EXAMPLE resources with arbitrary authored
numbers, not measured handling or production content. `.tres` coverage is
limited to this slice's fields on the pinned local engine and does not prove
behavior across other Godot versions or exported templates.
