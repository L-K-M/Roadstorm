Coordinator attestation: first-party Claude CLI completed with exit 0, success JSON, and modelUsage claude-opus-5-5 provider firstParty. The reviewer body below is verbatim.

# Roadstorm M0.2 source-schema/stdlib-checker checkpoint review (Opus 5.5)

## Identity

- **Candidate source SHA:** `a9cd11b2dd776990bc942576a509919c6f855f44`
- **Candidate tree:** `2158f50526c65ccc6196a6fb8b14a68d86c72291`
- **Base SHA:** `ddd0a421b551f855f056367df65657a851721a51`
- **Reviewer:** Claude Opus 5.5, model ID `claude-opus-5-5`, provider Anthropic, running in Claude Code (Claude Agent SDK). Date 2026-11-28.
- **Inputs:** only `./source` and `./evidence` in `work/agents/coordinator/m02-schema-review-opus.a9cd11b.Ymv850/`. I did not read the live checkout, change Git, delegate or consult the other reviewer.
- **SHA and tree:** the archive is not a Git repository, so I could not check them myself. They come from `evidence/identity.txt`.

## Scope and capability limits

- **Read-only session.** The session ran in plan mode. I wrote nothing outside this report, and nothing into `./source`.
- **Test suite not run.** I did not run `run_tests.sh` or the unittest suite. The suite writes temp files (`tempfile` in `StrictParsingTests` and `CommandLineTests`), and plan mode did not let me make an isolated copy to run it in.
- **What I did run:** in-memory Python probes (`python3 -I -B`, Python 3.15.2). They imported the archived checker and wrote no files or bytecode.
- **No JSON Schema validator.** The `jsonschema 4.26.0` result is coordinator evidence only. I checked the schema documents by reading them and by running my own structural deep diff.
- **No Godot.** Statements about the typed resource come from reading `handling_definition.gd` and `definition_identity.gd`.

## Files inspected

- **Plan and review rules:** `PLAN.md` (M0, M0.2, M0.3) and `plan/IMPLEMENTATION.md`.
- **Design decision:** `docs/evidence/m02-typed-runtime-mapping-20261127.md`.
- **Schemas:** `schemas/handling_config.schema.json`, `schemas/handling_config_v1_1.schema.json`, `schemas/handling_config_v1_1.md` and `schemas/common.schema.json`.
- **Typed resource:** `src/data/handling_definition.gd` and `src/data/definition_identity.gd`.
- **Checker:** `tools/car_recipe_schema/{validate_car_recipe.py,run_tests.sh,README.md,tests/test_car_recipe_schema.py}`.
- **Fixtures:** `fixtures/car_recipe/README.md` and the results for every positive and negative fixture.
- **CI:** `tools/ci/contracts.list`, the contract-suite job in `.github/workflows/ci.yml`, and the hash helpers in the other contract suites.
- **Evidence packet:** all five files.

## Commands I ran and their results

1. **Structural deep diff of v1.0 against v1.1.** Exactly these paths differ:
   - `/schema_version` and `/properties/schema_version/const` change from `1.0.0` to `1.1.0`.
   - `handling.required` gains exactly the five fields.
   - Five `handling.properties` entries are added.
   - `handling.allOf` is added.

   Root and `handling` both keep `additionalProperties: false`, and nothing else changed. This matches the declared contract change.

2. **Shapes of the five new fields.** The schema is correct:
   - **Yaw:** a `oneOf` with two branches that cannot both match. One is `[number, null]` with `exclusiveMinimum: 0`. The other is the closed object `{unlimited: const true}`, with `unlimited` required. `null` matches only the first branch.
   - **Bounds:** reverse trigger speed in `[0, 1]`, hold time `>= 0.3`, reverse acceleration and reverse top speed `>= 0`.
   - **Cross-field rule:** the `allOf` `if`/`then` says that if reverse acceleration is a number `> 0`, reverse top speed must be present and be a number `> 0`.

3. **All 27 negative fixtures in schema mode.** Each fails with exactly its declared code and path. None fails for an unintended reason such as a stale hash. Examples:
   - `accel_positive_top_null` gives `reverse-cross-field`.
   - `duplicate_key` and `yaw_infinity_literal` give `invalid-json`.
   - The `yaw_unlimited_*` files give `bad-unlimited-encoding`.
   - The version negatives give `unsupported-schema-version`.

4. **Counterexample probes.** I ran these on a re-hashed copy of `example_rookie_finite.json` in motor-ready mode:

   | Probe | Result |
   | --- | --- |
   | Unmodified copy | accepted |
   | A 401-digit integer (`10**400`) in yaw, hold or `mass_kg` | **crashes with `OverflowError`** |
   | `display_name` set to a lone surrogate `"\ud800"` | **crashes with `UnicodeEncodeError`** in `content_hash_of` |
   | `handling.acceleration_curve` speeds 10, 5, 5 (not increasing) | **accepted** |
   | `revision: "draft-A"` | **accepted** |
   | `provenance.source_contract` null, or claiming 1.0.0, on a 1.1.0 recipe | accepted |
   | Trigger `-0.0`, a subnormal yaw, or acceleration and top speed of `1e-300` | accepted, which matches the typed resource |

5. **Hash and number-text check.**
   - `{"a":30}` and `{"a":30.0}` produce different hashes.
   - The canonical text uses CPython's number formatting, for example `{"a":30.0,"b":1e-07,"c":1e+21}`.
   - `json.loads` of a 401-digit number returns a Python `int`, not a float.

## Supplied evidence assessed

- **`stdlib-tests.log`:** 42 tests OK. This is the coordinator's run, not mine. The test names match the test file, but I did not re-run it.
- **`jsonschema-4.26.log`:** a one-line summary with no per-file output and no command line. It agrees with my own reading of the schema, but it is coordinator evidence only.
- **`worker-report.md` §2 is false.** It says `run_tests.sh` "no longer contains the fixed `work/agents/car-recipe-v11.coord-387da7b` path".
  - `tools/car_recipe_schema/run_tests.sh:23` still sets `JOB_DIR` to that path, and line 27 prefers it whenever it exists.
  - The behaviour is harmless, because the script only creates a `mktemp` child directory there. The claim itself is still wrong.
- **`worker-report.md` §4 is accurate.** It says the checker does not conform to draft 2020-12.

## Findings, most severe first

### Defects in this slice

**D1 (should fix before acceptance): a very large integer crashes the checker instead of producing a finiteness finding.**
- **Where:** `validate_car_recipe.py:305` (`_is_finite_number`), `:364` (`_check_number`) and `:900` (`_validate_max_yaw_rate`). Each calls `math.isfinite` on a Python `int`, which can be arbitrarily large.
- **Trigger:** any valid JSON integer of 309 or more digits.
- **Reproduction:** set `handling.max_yaw_rate_rad_s` (or `reverse_hold_time_s`, or `mass_kg`) to 1 followed by 400 zeros, re-hash and validate. The checker raises an uncaught exception.
- **Effect on the CLI:** it aborts the whole directory scan with a traceback and exit code 1. That looks the same as an ordinary validation failure, and no diagnostic is printed.
- **Broken claim:** the "Finiteness" section of `handling_config_v1_1.md` says overflowing literals are rejected.
- **Downstream risk:** JSON Schema accepts the value. A reader that parses numbers as floats, such as Godot's, would turn it into `INF`, which is an unlimited yaw cap. The explicit `{"unlimited": true}` rule exists to prevent exactly that.
- **Fix:** treat a number as finite only if `math.isfinite(float(value))` succeeds, and report an `OverflowError` as non-finite. Add a negative fixture and a unit test.

**D2 (should fix): an unpaired surrogate escape crashes content hashing.**
- **Where:** `validate_car_recipe.py:265` accepts `"\ud800"`. Then `:292` raises `UnicodeEncodeError` on `.encode("utf-8")`.
- **Reproduction:** put `"display_name": "\ud800"` in the file text.
- **Effect:** the same uncaught-exception behaviour as D1. The strict-parsing claim does not cover this case.
- **Fix:** reject unpaired surrogates when the file is loaded and report them as `invalid-json`.

**D3 (should fix): CI does not run the new suite.**
- **Where:** `.github/workflows/ci.yml:551-556` lists the contract suites by name. `tools/car_recipe_schema/run_tests.sh` is not in that list or in `tools/ci/contracts.list`.
- **Effect:** a green hosted CI run at this SHA has not run the 42 tests or checked the fixtures, so regressions in the schema, checker or fixtures would go unnoticed.
- **Conflict:** AGENTS.md requires contract suites to "run from the exact checkout and fail loudly when a required suite is absent."
- **Fix:** add the script to the CI suite loop. Optionally, also remove the `JOB_DIR` fallback at `run_tests.sh:23-28`.

**D4 (medium): a recipe that passes motor-ready mode can still fail typed validation.**
- **What motor-ready checks:** `_validate_motor_ready` (`validate_car_recipe.py:1295-1325`) checks only that each motor input is present, non-null and not listed as unknown, and that the acceleration curve is not empty.
- **Gap 1, curve order:** it accepts an acceleration curve whose speeds do not strictly increase. `HandlingDefinition._validate_curve` (`handling_definition.gd:191-195`) rejects such a curve.
- **Gap 2, revision format:** it accepts a `revision` that is not `MAJOR.MINOR.PATCH`. `DefinitionIdentity` (`definition_identity.gd:66-69`) rejects such a revision, and the mapping decision requires the baker to reject it.
- **Dead code:** `REVISION_RE` is defined at `validate_car_recipe.py:75` but never used, which suggests this check was intended.
- **Effect:** the mode name and the README promise more than the checker enforces.
- **Fix, either of:**
  - add the curve-order and revision-format checks to motor-ready mode; or
  - document that motor-ready is necessary but not sufficient, and remove `REVISION_RE`.

**D5 (minor): the `source_contract` spelling is inconsistent, and nothing checks it.**
- **The mismatch:** the fixtures use `roadstorm.handling_config.1.1.0` (for example `example_rookie_finite.json:191`). The contract note at `schemas/handling_config_v1_1.md:104` and the worker report use `roadstorm.handling_config.v1.1.0`.
- **No check:** the checker never compares `provenance.source_contract` with `schema_version` (`:1255-1264`), so a 1.1.0 recipe that claims a 1.0.0 contract passes.
- **Fix:** choose one spelling before the bake manifest depends on it. Optionally, warn when the two disagree.

**D6 (minor): fixture README and negative-fixture test.**
- `fixtures/car_recipe/README.md:29` lists a negative fixture for an unresolved `unknowns` path, but no such file exists. Only the unit test `test_unresolved_unknown_path_is_rejected` covers that case.
- `test_every_negative_fixture_is_rejected_in_schema_mode` (`tests/test_car_recipe_schema.py:202-209`) only checks that some finding exists. My probe 3 shows each fixture is currently precise, but the test would not notice a fixture that starts failing for the wrong reason. It should pin the expected code and path for each fixture.

### Earlier or future gaps (not defects of this slice)

- **F1: the content hash depends on how CPython writes numbers.**
  - **Current definition:** `common.schema.json` says "sorted keys, compact separators, UTF-8". Every suite in the repository implements that with Python's `json.dumps(sort_keys=True, separators=(",",":"), ensure_ascii=False)`.
  - **Consequences:** the hash depends on how a number was written in the source (`30` and `30.0` differ) and on CPython's float formatting (`1e-07`, `1e+21`). A baker written in GDScript or another language cannot reproduce it without copying CPython's behaviour exactly.
  - **Decision needed before the baker writes source hashes into a manifest:** either always hash with the Python tool, or adopt a number canonicalization in the style of RFC 8785.
  - **Status:** this predates the slice and affects the whole repository, so it does not block this checkpoint.
- **F2: declared as absent.** The importer and baker, `.tres` output, source-to-runtime conversion tests (`INF` mapping, the rad/s exception, identity derivation), the bake manifest, provenance recording and production content.

### Optional improvements

- **Bounds tolerance:** the source bounds are slightly stricter than the typed bounds, which allow a `BOUND_TOLERANCE` of `1e-9` on trigger speed and hold time. That direction is safe. Record it so a future baker does not loosen the source bounds to match.
- **Null-path scoping:** `_collect_null_paths` (`:489`) skips keys named `provenance`, `unknowns` or `content_hash` at any depth, not only at the root. That is harmless today because those keys only appear at the root, but limiting it to the root would be tighter.

## Checks that pass (my own reading and probes)

- **Structural diff:** the v1.0 to v1.1 diff contains only the version metadata and constant, the five required nullable handling properties, and the reverse cross-field rule. Root and `handling` stay closed.
- **Unlimited yaw:** the only accepted encoding is exactly `{"unlimited": true}`.
  - Both schema and checker reject `false`, `{}`, extra keys, strings, booleans, and `Infinity` or `NaN`.
  - `1e999` is rejected by the checker only, as the documentation says.
- **Bounds and the cross-field rule:** the finite and range bounds and the reverse acceleration/top-speed rule agree across the schema `allOf`, the checker (`:1000-1018`) and the typed `_validate_reverse_bounds`.
- **Version dispatch:** exact. Only `1.0.0` and `1.1.0` are accepted. Anything else, including `1.1.0\n`, is refused before any other check, and there is no migration. A 1.0.0 recipe that includes the five fields fails because the shape is closed.
- **Strict parsing:** duplicate members are rejected at every depth, and so are the `NaN` and `Infinity` literals. The exceptions are D1 and D2.
- **Null and unknowns pairing:** enforced in both directions, with exact paths for the five fields. A determined value listed as unknown is rejected, and so is an unknowns path that does not resolve.
- **Identity, status and revision mapping:** the decision is coherent.
  - `<car_id>.handling` matches the typed `DEFINITION_ID_PATTERN`.
  - The status values map one-to-one.
  - The revision format is enforced at bake time; D4 is the checker-side gap.
- **Version separation:** the source contract version and the typed resource version are kept apart. The typed version stays `1.0.0`, and the source version is meant to go to the manifest and `source_contract`. D5 covers the spelling.

## Verdict

**Changes required** for this provisional source-schema and stdlib-checker slice.

- **Schemas:** both documents pass my structural review.
- **Checker:** it crashes on two kinds of valid JSON (D1, D2).
- **CI:** it does not run the new suite (D3).
- **Motor-ready mode:** it needs stronger checks or an honest statement of its limits (D4).
- **Minor:** D5 and D6.

A scoped recheck after the fixes should cover D1 to D4. This candidate alone does not support any M0, M0.2 or M0.3 acceptance, any product handling claim or any release-rights claim.

## Remaining M0.2 and M0 gates

- **M0.2:**
  - An importer and baker with version dispatch and refusal, unit mapping (`INF`, rad/s), identity derivation and revision rejection.
  - Typed validation of the baked output.
  - Source-to-runtime conversion tests.
  - A content-hash decision that is either language-neutral or explicitly tied to the Python tool (F1).
  - A bake manifest with the source version, revision and hash, the derived identity, and the output SHA-256.
  - Production car content and asset references.
  - The rest of `CarDefinition.DEFERRED_FIELDS_V1`.
  - A dual Opus/Sol recheck of the corrected candidate.
- **M0.3:** provenance manifests, including recording `source_contract`, and intake of LLM provider terms.
- **M0 acceptance:** a second agent can follow the setup guide, import the project, run a passing and a failing check, and export a smoke build. M0.2, M0.3 and M0.4 are still open.
