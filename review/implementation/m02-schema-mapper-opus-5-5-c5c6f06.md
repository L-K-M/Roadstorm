# Roadstorm M0.2 corrected source-contract/checker and mapper checkpoint (Opus 5.5)

## Identity

- **Reviewer:** Claude Opus 5.5, model ID `claude-opus-5-5`, provider Anthropic (first-party), running in Claude Code (Claude Agent SDK). Date 2026-11-28 (UTC).
- **Candidate:** `c5c6f06c3e687501fc73196f177948d7527cafd0`. The `source/` snapshot has no Git metadata, so I took the SHA from the brief. Hosted CI reports the same `headSha` (see below).
- **Prior candidate:** `a9cd11b`, with both reports in `review/implementation/m02-source-schema-*-a9cd11b.md`.
- **Scope:** the bounded source-contract/checker slice (repairs `a45dcdc`, `58c59e9`, `4b5e524`, `aa85e7f`) and the new pure `HandlingRecipeMapper` (`c5c6f06`), as covered by `../scope.patch`. Intervening M1 commits are out of scope. I make no claim about the baker/importer, production content, M0.2 acceptance, M0 acceptance or rights clearance.
- **Independence:** I did not delegate, did not consult the concurrent Sol review, did not read or edit the shared checkout, and did not mutate Git. I wrote only this report and files under `opus/logs/`.

## Files inspected

- `scope.patch` (file list), `task.md`
- Prior reports: `review/implementation/m02-source-schema-opus-5-5-a9cd11b.md` and `...-gpt-6-2-sol-a9cd11b.md`
- `docs/evidence/m02-typed-runtime-mapping-20261127.md`
- `src/data/handling_recipe_mapper.gd`, `src/data/handling_definition.gd`, `src/data/definition_identity.gd`
- `tools/car_recipe_schema/validate_car_recipe.py`, `tests/test_car_recipe_schema.py`, `run_tests.sh`
- `schemas/handling_config_v1_1.md` (version and provenance sections), `schemas/handling_config.schema.json` (point and handling shapes), `schemas/common.schema.json` (provenance)
- `tools/ci/contracts.list`, `.github/workflows/ci.yml` (contract-suites job)
- `tools/data_lab/README.md`, `validate_data_lab.gd` (mapper cases, lines 1697-2270), `data_lab_checks.gd` (`source_handling_recipe`)
- Fixture corpus `fixtures/car_recipe/{positive,negative}` (`source_contract` tokens, positive fixtures loaded in probes)

## Commands and results

All of these ran in my private `build/` copy, using private temp and XDG directories. `diff -rq source build` showed no differences before I started.

1. **Checker suite.** I ran `TMPDIR=logs/tmp CAR_RECIPE_WORK_DIR=logs sh build/tools/car_recipe_schema/run_tests.sh` on Python 3.15.2. Result: **78 tests OK**, exit 0. Log: `logs/car-recipe-tests.JY0gSS/tests.log`.
2. **Checker CLI.**
   - `example_rookie_finite.json` and `example_rookie_unlimited.json` in motor-ready mode: 0 errors, exit 0.
   - `negative/yaw_zero.json`: `bad-yaw-rate`, exit 1.
   - The positive directory in motor-ready mode: 7 errors, as designed. They come from the null-input fixture and the 1.0.0 fixture.
   - `example_rookie_null_motor_inputs.json`: `motor-input-unresolved` on the yaw and trigger paths. Log: `logs/checker_null_fixture.log`.
3. **Checker probes.** Scripts `logs/probes/checker_probe.py` and `checker_probe2.py`, run with `python3 -I -B`. Output: `logs/checker_probe.log` and `checker_probe2.log`. Summary:
   - **401-digit integer** in yaw or `mass_kg`, from file text: path findings `non-finite-number` and `bad-yaw-rate`/`bad-number`. No crash.
   - **Lone `\ud800` in `display_name`:** `unpaired-surrogate` at its path, plus `content-hash-uncomputable`. No crash.
   - **`{"unlimited": 1}` and `{"unlimited": 1.0}`:** `bad-yaw-rate`. `{"unlimited": true}` is accepted.
   - **Curve speeds 10, 5, 5:** `motor-input-order` at `[1]` and `[2]`.
   - **`revision: "draft-A"`:** `bad-revision-format` in motor-ready mode. Schema mode accepts it.
   - **Literals at and past the bounds:**
     - Trigger `1.00000000000000001` gives `number-not-representable` and `bad-number`.
     - Trigger `1.000` is accepted.
     - Hold equal to the exact binary expansion of `0.3` gives `bad-number`, because it is below decimal 0.3.
     - Yaw `1e999` gives `non-finite-number`, and yaw `1e-400` gives `number-not-representable`.
     - Yaw `5e-324` and trigger `-0.0` are accepted.
     - `presentation.x = 1e999` gives `non-finite-number` at `presentation.x`.
   - **Provenance `source_contract`** set to `roadstorm.handling_config.1.0.0`, or to `null`, on a 1.1.0 recipe: accepted.
   - **Integer `9007199254740993`** for hold time (re-hashed): accepted. The canonical text keeps `9007199254740993`, while binary64 is `9007199254740992.0`.
   - **Curve speeds `0.1` and then the exact decimal expansion of binary64 0.1:** accepted in motor-ready mode. The two decimals differ, but they round to the same float.
4. **Data lab.** I ran this on the pinned Godot 4.7.2 binary:

   ```
   sh build/tools/data_lab/run_validation.sh --project build --godot <pinned> --private-dir logs/lab-stage-all --case all --log logs/data_lab_all.log
   ```

   Result: exit 0, **17 cases, `CHECKS_TOTAL=490 CHECKS_FAILED=0`**. The intentional-failure proof exited nonzero with its marker. Logs: `logs/data_lab_all.log` and `logs/data_lab_all.stdout`.
5. **Mapper probes.** I ran `logs/probes/mapper_probe.gd` headless in my imported stage (`logs/lab-stage-all/zz_probe/`), using Godot's own `JSON.parse_string` on the committed checker fixtures. Output: `logs/mapper_probe.log`.
   - **`example_rookie_finite.json`:** ok.
     - Identity: `car.example_rookie.handling`, revision `0.1.0`, status EXAMPLE.
     - Values: yaw 2.5 rad/s unconverted, curve speeds [0, 30], trigger 1.0, hold 0.3.
   - **`example_rookie_unlimited.json`:** ok, with yaw `inf`.
   - **`example_rookie_v1_0_0.json`:** refused with exactly the five `missing-field` paths.
   - **`example_rookie_null_motor_inputs.json`:** refused, but with **`motor-input-unknown`** and the message "a resolved value may not also be undetermined". See F1.
   - **A resolved curve point listed in unknowns** (`handling.acceleration_curve[0].speed_m_s`): **maps successfully**. See F4.
   - **`units.length = "ft"` and `units.time = "min"`:** **maps successfully**. See F4.
   - **Numbers parsed by Godot:**
     - A 401-digit integer and `1e400` both parse to `inf`, and the mapper refuses them.
     - `9007199254740993` parses to `9007199254740992.0`.
     - The curve `0.1` followed by its exact expansion is refused with `motor-input-order`.
   - **Other inputs:**
     - `{"unlimited": 1}` is refused.
     - Trigger `1.0000000000000002` is refused, but the diagnostic reads "1.0 is above the maximum 1.0" (see F6).
     - Trigger `-0.0` maps.
     - A `StringName` version is refused as unsupported.
     - A `source_contract` that does not match the version maps.
6. **Hosted CI** (read-only `gh run view`). Run **46092943533** is `completed/success` on `headSha c5c6f06c3e687501fc73196f177948d7527cafd0`, and all four jobs succeeded.
   - The contract-suites log shows `=== contract suite: tools/car_recipe_schema/run_tests.sh ===`, then `Ran 78 tests`, then `All contract suites passed`.
   - In the Godot job, `handling_recipe_mapper.gd` and `validate_data_lab.gd` appear only as ci-scan `compiles` entries. I found no evidence that hosted CI runs the data lab cases. See F2.

## Disposition of prior a9cd11b findings

| Prior finding | Status at c5c6f06 | Evidence |
| --- | --- | --- |
| Sol 1: numeric unlimited sentinel `{"unlimited": 1/1.0}` | **Corrected** | `validate_car_recipe.py:1181-1198` (`set(value) != {"unlimited"}`, `is not True`). Probe 3 confirms, and tests 598-640 use re-hashed files. |
| Sol 2: inherited required members and object types; schema-valid empty strings | **Corrected** for the listed cases | Parity tables `tests/...:179-270`, run in both versions and both modes. The table asserts the code and the path as separate set memberships, not as a pair (weak-test nit). |
| Sol 3 / Opus D4: motor-ready curve ordering | **Corrected**, with one residual: ordering is compared in decimal space (F3) | `validate_car_recipe.py:1661-1677`, tests 788-813 |
| Opus D4: revision triplet and derived ID | **Corrected** | `_validate_bake_preflight` `:1680-1717` uses `REVISION_RE.fullmatch` and the derived `<car_id>.handling` fullmatch. Its docstring now states "necessary, not sufficient". |
| Version dispatch, including `1.1.0\n` | **Correct** (unchanged) | `:1739-1747`. The mapper does the same (`handling_recipe_mapper.gd:154-169`). |
| Opus D1 / Sol 4: very large numbers | **Corrected** | `_finite_float` `:445-460` catches `OverflowError`. `_scan_representability` `:733-796` runs first, over the whole document including `presentation`. |
| Sol 4: decimals at declared bounds | **Corrected** | `parse_float=Decimal` (`:323-328`). Bounds are compared exactly through `Decimal(str(bound))` (`:560-582`), and non-round-trip-stable literals are refused. Residual for integers: F5. |
| Opus D2 / Sol 4: surrogates and UTF-8 | **Corrected** | Strings and member names are scanned (`:746-786`). `canonical_json` uses `allow_nan=False`. `content_hash_of` wraps encoding errors (`:401-414`). Invalid UTF-8 bytes give `invalid-encoding`. |
| Sol 5: exact and ambiguous unknown paths in open keys | **Corrected** | `presentation` is exempt from collection (`:691-712`). Non-plain keys become bracketed quoted segments (`:504-514`) that `UNKNOWN_PATH_RE` cannot name. `_declared_path_covers` excludes quoted segments (`:715-730`). The five fields still require an exact `handling.<field>` entry (`:1237-1259`). |
| Opus D5: `source_contract` token | **Spelling corrected; still unchecked** | `handling_config_v1_1.md:104` now reads `roadstorm.handling_config.1.1.0`, which matches the fixtures. No checker or mapper compares it with `schema_version` (F7). |
| Opus D3: CI suite inclusion | **Corrected and verified hosted** | `ci.yml:551-558`, `contracts.list:17`. The run 46092943533 log shows 78 tests. |
| Worker-report `JOB_DIR` claim | **Resolved** | `run_tests.sh` no longer has a fixed job path. It uses only `CAR_RECIPE_WORK_DIR` or `TMPDIR`. |
| Opus D6: negative fixtures not pinned | **Corrected** | `tests/...:469-483` checks that the set of negative fixtures equals the expectation map, and asserts the exact `(code, path)` pair for each. |

## Mapper review against the decision record and HandlingDefinition

These points conform. Each was verified by reading the code and by lab or probe output.

- **Version dispatch:** exact. `1.1.0` maps. `1.0.0` is refused with exactly five `missing-field` paths, whatever the rest of the document contains. Absent, non-string, `StringName` and trailing-newline versions are refused, and there is no migration.
- **Source nonmutation:** the code only reads (`get`, `has`, indexing) and builds new typed arrays. The lab checks value equality against a deep snapshot, both on success and on refusal.
- **Required motor inputs:** all eleven are required. A missing or null input, or one listed under an exact or ancestor unknowns path, is refused. No typed default is ever substituted, because `HandlingDefinition`'s inert defaults are never read.
- **Units and the INF sentinel:**
  - `units.angle` must be `deg`, and yaw is copied as rad/s without conversion.
  - Only an exact sole-member `{"unlimited": true}` (`TYPE_BOOL`) maps to positive `INF`.
  - Non-positive yaw, numeric sentinels, strings and booleans are refused.
- **Identity:**
  - The derived values are `<car_id>.handling` and `<display_name> handling`.
  - The triplet revision is validated by `DefinitionIdentity.is_valid_revision` and copied unchanged.
  - Status maps one-to-one, and the typed `schema_version` stays `1.0.0`.
- **Finite and curve checks:** NaN, infinity, overflow (Godot parses it as `inf`), booleans and strings are refused. The curve must be non-empty, ordered by strictly increasing speed, and made of objects that each have both members. Bounds match the typed resource but are exact (no 1e-9 tolerance), which is the safe direction.
- **Diagnostics and partial results:** any refusal returns `ok=false` and `handling=null`, with at least one path diagnostic. The typed `validate()` runs before success.

## Findings, most severe first

### F1 (code defect, medium): the mapper reports the ordinary null-with-unknowns case as "resolved but unknown"

- **Where:** `handling_recipe_mapper.gd:480-486` (scalars), `:541-547` (yaw) and `:395-401` (curve) check `_path_is_unknown` before `value == null`. The message at `:646-651` says "a resolved value may not also be undetermined".
- **Effect:** an honest recipe that sets a motor input to `null` and lists it in `unknowns` is refused with `motor-input-unknown` and a false claim that the value is resolved. That is the contract's normal way to defer a value, and it is exactly the committed `example_rookie_null_motor_inputs.json` (probe 5).
  - For the same file, the Python checker reports `motor-input-unresolved` (command 2).
  - The refusal itself is correct, but the checker and the future baker give different diagnostic codes and wording for the most common refusal.
- **Missing test:** none of the 17 lab cases covers null plus a matching unknowns entry. The null case at `validate_data_lab.gd:1956-1962` has no unknowns entry, and the unknown case at `:1966-1974` uses a resolved value.
- **Fix:** test for null before unknown membership, or give a separate message to an unknowns entry over a resolved value. Add a lab case that uses the committed null-input fixture shape.

### F2 (missing evidence / CI gap, medium): hosted CI does not run the mapper's behavioural lab

- **What hosted CI covers:** run 46092943533 shows only ci-scan `compiles` entries for `src/data/handling_recipe_mapper.gd` and `tools/data_lab/validate_data_lab.gd`. Neither `tools/ci/contracts.list` nor `ci.yml` refers to `data_lab`.
- **Consequence:** the 490-check result, including the 4 mapper cases, is local pinned-Godot evidence only, from the coordinator and from my reproduction. A regression in the mapper would pass hosted CI as long as the file still compiles.
- **Status:** this may be a deliberate plan choice for the Godot lab, but it should be stated, or the lab wired into the Godot CI job before a baker depends on the mapper.

### F3 (code defect, low): motor-ready orders curve speeds in decimal space; the typed resource orders them in binary64

- **Where:** `validate_car_recipe.py:1661-1677` compares the parsed `Decimal` values.
- **Trigger:** the literal `0.1` followed by `0.1000000000000000055511151231257827021181583404541015625` (the exact expansion of float 0.1). Both pass the round-trip-stability check (`:463-475`). Motor-ready accepts them (probe 3). Godot parses them to equal floats, and both the mapper and `HandlingDefinition` refuse them (probe 5).
- **Effect:** the documented boundary says bounds are compared in decimal space, but ordering is a typed-resource rule. The bake-preflight docstring's "necessary, not sufficient" wording covers this, so the gap is low. It is still a concrete checker/mapper divergence.
- **Fix:** compare `_finite_float(speed)` values in the ordering loop, and add a regression test.

### F4 (code gap, low): the mapper's defensive scope skips two checks it implies it makes

These only matter if the external checker is bypassed. The class documentation lists "unknown motor inputs" and "a wrong angle unit" among the defensive refusals.

- **Curve-point unknowns:** `_path_is_unknown` (`handling_recipe_mapper.gd:624-628`) is only consulted with the whole-curve path. An unknowns entry `handling.acceleration_curve[0].speed_m_s` over a resolved number therefore maps successfully (probe 5). The checker refuses the same document with `resolved-but-unknown`.
- **Units:** `units.length`, `mass` and `time` are not checked (`:267-279`), and `"ft"`/`"min"` map successfully (probe 5). Meanwhile the documentation at `:53-54` says speeds and times are copied "as authored m/s, m/s^2 and s".
- **Fix, either of:**
  - check child paths of `handling.acceleration_curve` and all four unit constants; or
  - narrow the class documentation so it states that these checks belong to the checker.

### F5 (code/documentation defect, low): integers above 2^53 are accepted although they have no exact binary64 value

- **Where:** `_scan_representability` applies the round-trip test only to `Decimal` values (`validate_car_recipe.py:766`). The module documentation (`:41-46`) says a literal is refused when "it has no binary64 representation the source text can be recovered from".
- **Trigger:** hold time `9007199254740993` is accepted, and its canonical hash text is `9007199254740993`. Godot reads it as `9007199254740992.0` (probes 3 and 5).
- **Impact:** small today, because no bound lies near 2^53. It still breaks the stated invariant that the source text and the baked value agree.
- **Fix:** for an `int`, require `int(float(v)) == v`. Add a test.

### F6 (diagnostic quality, nit): the mapper's bound messages lose precision

`str(float)` in `handling_recipe_mapper.gd:490-500` prints `1.0000000000000002` as `1.0`. The result is "1.0 is above the maximum 1.0" (probe 5). Formatting with `%.17g` (or similar) would fix it.

### F7 (plan gap, low): `provenance.source_contract` is never compared with `schema_version`

- **Current behaviour:** the spelling is now consistent (`roadstorm.handling_config.1.1.0`). However, the checker (`validate_car_recipe.py:1569-1578`) and the mapper both accept a 1.1.0 recipe that claims a 1.0.0 contract, or a null contract (probes 3 and 5).
- **Description clash:** `common.schema.json:51-53` describes `source_contract` as the "Design/benchmark document this artifact was derived from", and the handling fixtures use `docs/BENCHMARKS.md#handling-fixtures`. The v1.1 note uses the same field for the source schema version token.
- **Decision needed:** settle the field's meaning before the bake manifest records it. This belongs to M0.3 and the future baker, not to this slice.

### Weak-test notes (no defect found)

- `InheritedContractParityTests` (`tests/...:821-828`) checks that the code and the path each appear somewhere, not that they appear as one finding. Using the existing `pairs()` helper would pin them together.
- The mapper lab uses a synthetic GDScript dictionary (`data_lab_checks.gd:139`), not the committed checker fixtures parsed by Godot's `JSON`. No committed test proves that a fixture which passes the checker in motor-ready mode maps through the mapper. My probe 5 shows that the two motor-ready positives do map today. A small lab case that loads them would lock in this cross-tool contract.
- `map_handling`'s `typeof(recipe) != TYPE_DICTIONARY` guard (`handling_recipe_mapper.gd:147-152`) can never run, because the parameter is typed `Dictionary`. Godot rejects a non-Dictionary argument at the call.

## Verdict

**Pass with follow-ups** for this bounded source-contract/checker slice. Every prior Opus and Sol a9cd11b finding in scope is corrected, apart from the residuals noted in the table (F3, F5, F7). The fixes were verified by reading the code, by 78/78 local tests, by my own probes, and by the hosted contract-suite run on this exact SHA.

**Changes required (minor)** for the mapper slice before a baker depends on it:

- **F1:** correct the diagnostic order and message, and add the missing null-plus-unknowns case.
- **F2:** either run the mapper lab in hosted CI or record that it is local-only evidence.

The mapper's refusal behaviour is fail-closed in every case I probed, and no half-built resource is ever returned. I found no defect that would emit an incorrect `HandlingDefinition` from a recipe that passes the checker. F3 to F7 are low-severity follow-ups.

## Limitations

- **Identity:** the snapshot has no Git metadata, so the candidate SHA and tree come from the brief and from the hosted run's `headSha`.
- **JSON Schema:** I did not run a JSON Schema validator.
- **Test runs:** the Godot lab and probes ran in my private staged copy, not in hosted CI. My Python run used the local Python 3.15.2.
- **Not reviewed:** intervening M1 commits outside `scope.patch`.
- **No claim:** nothing here establishes M0.2 acceptance, a baker/importer, production content, product handling or release rights.

## Remaining gates (unchanged by this slice)

- **Baker/importer:** an importer and baker with refusal paths, `.tres` output, and source-to-runtime conversion evidence.
- **Hashing:** a canonical-hash decision that does not depend on CPython number formatting.
- **Bake record:** a bake manifest recording the source version, revision, hash, derived identity and output SHA-256.
- **Content:** production car content.
- **Deferred fields:** `CarDefinition.DEFERRED_FIELDS_V1`.
- **M0.3:** provenance and the `source_contract` meaning.
- **M0 acceptance.**


---

## Coordinator identity and disposition attestation

The report above is copied verbatim from this reviewer's isolated packet. The Opus CLI JSON confirms `claude-opus-5-5` on `firstParty`; the Sol Codex CLI stderr confirms `model: gpt-6.2-sol`, `provider: openai`. Both reviewed a separate plain archive of exact `c5c6f06c3e687501fc73196f177948d7527cafd0`, with separate build/cache paths and no access to the other current report. Hosted CI run 46092943533 later completed successfully in all four jobs on that SHA. The coordinator independently reran Sol's three checker counterexamples and reproduced the curve collapse and two exception classes. Those findings, Opus's mapper diagnostic finding, and CI coverage remain open for bounded repairs; no M0.2 gate is accepted by copying this report.
