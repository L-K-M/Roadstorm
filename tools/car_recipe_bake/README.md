# M0.2 handling bake CLI

Bounded command-line slice that turns **one** motor-ready version `1.1.0`
JSON source recipe into **one** validated `HandlingDefinition` `.tres` plus a
machine-readable bake manifest.

Scope and decisions follow
[`docs/evidence/m02-typed-runtime-mapping-20261127.md`](../../docs/evidence/m02-typed-runtime-mapping-20261127.md)
and the committed contracts:

* [`schemas/handling_config_v1_1.schema.json`](../../schemas/handling_config_v1_1.schema.json)
  (source contract `roadstorm.handling_config.1.1.0`);
* [`tools/car_recipe_schema/validate_car_recipe.py`](../../tools/car_recipe_schema/validate_car_recipe.py)
  (committed stdlib checker);
* [`src/data/handling_recipe_mapper.gd`](../../src/data/handling_recipe_mapper.gd)
  (committed pure mapper API).

This tool does **not** build a `CarDefinition`, does not implement a general
importer or resource cache, does not author production car content, and does
not complete or accept M0.2. It maps only the committed motor-ready core subset.
Unknown/null coefficients are never inferred and the source recipe is never
rewritten.

## Files

| Path | Purpose |
| --- | --- |
| `bake_handling_recipe.py` | Python standard-library CLI entry point. |
| `bake_handling.gd` | Pinned-engine step: map, validate, serialize, reload, compare. |
| `run_tests.py` | Bounded private test runner. |
| `fixtures/positive/finite.json` | Synthetic finite-yaw motor-ready recipe. |
| `fixtures/positive/unlimited.json` | Synthetic `{"unlimited": true}` yaw recipe. |
| `fixtures/negative/null_motor_input.json` | Required input `null` with matching `unknowns` entry. |
| `fixtures/negative/version_1_0_0.json` | Schema-valid historical `1.0.0` recipe. |
| `fixtures/negative/stale_content_hash.json` | Wrong canonical content hash. |

Fixture values are explicit synthetic placeholders (`example`/`provisional`),
not measured production handling. The positive fixtures are adapted from
`fixtures/car_recipe/positive/example_rookie_finite.json`; every fixture
recomputes its canonical `content_hash` except `stale_content_hash.json`, which
is intentionally wrong.

## Requirements

* Python 3 standard library.
* The pinned Godot build. By default the tool uses `$GODOT_BIN`, then `godot`
  on `PATH`, and verifies that `--version` contains the
  `version_string=` recorded in `tools/toolchain/pin/engine.txt`.
* `timeout` and `lockf` on `PATH` (present on this macOS host). `timeout` wraps
  every engine call; `lockf` takes the shared coordinator lock.
* Writable `work/agents/coordinator/` for the existing
  `work/agents/coordinator/godot-test.lock`.

The tool first freezes the input recipe bytes into private scratch, then
checks, hashes and maps that exact copy. It refuses if the original path's
bytes changed before publication. The manifest records the original path and
the accepted byte snapshot's SHA-256. The tool stages a private project copy (`project.godot`, `src/`, `scenes/`,
`tools/car_recipe_bake/`) into a fresh temporary directory and points
`XDG_CACHE_HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `TMPDIR` at private
directories under it. It never imports into or writes through the shared
checkout `.godot/` cache and never modifies `project.godot`.

## Bake command

From the repository root:

```sh
python3 tools/car_recipe_bake/bake_handling_recipe.py \
    --recipe tools/car_recipe_bake/fixtures/positive/finite.json \
    --output-dir /tmp/roadstorm-bake-demo
```

`--output-dir` must name a directory that does not already exist. The command
creates it only after every check and the engine round trip has passed.

Useful options:

```sh
--godot-bin /path/to/Godot   # override $GODOT_BIN / PATH resolution
--timeout 300                # outer seconds per engine invocation (default 300)
```

Exit codes: `0` success, `1` checker/mapper/engine/round-trip/hash/output
failure or refusal, `2` command-line usage error.

### Pipeline

1. Refuse an existing output destination, including a dangling symlink.
2. Run
   `python3 tools/car_recipe_schema/validate_car_recipe.py --mode motor-ready`
   on a private byte snapshot of the recipe. Strict JSON, duplicate-member rejection, decimal/binary64
   representability, null/`unknowns` honesty, the five `1.1.0` inputs,
   cross-field rules, revision/identity preflight and the canonical
   `content_hash` all run in this committed checker. Any finding fails the
   bake.
3. Recompute the canonical source content hash from that same frozen copy with
   the committed checker's own `content_hash_of` and require it to equal the
   recipe's recorded hash.
4. Verify the selected Godot is the pinned build.
5. Stage a private project copy, then under
   `timeout ... lockf -k -w -t <timeout> work/agents/coordinator/godot-test.lock`
   run, with isolated XDG/TMP directories:
   * `godot --headless --path <private-project> --import`;
   * `godot --headless --path <private-project> --script
     res://tools/car_recipe_bake/bake_handling.gd -- --recipe <frozen-checked-recipe>`.
6. The engine loads the checked recipe, calls
   `HandlingRecipeMapper.map_handling`, runs `handling.validate()`, saves the
   `.tres` with `ResourceSaver.save`, reloads it with
   `ResourceLoader.load(..., CACHE_MODE_IGNORE)`, revalidates it, compares all
   18 serialized identity/handling fields, and writes a private JSON report.
   The entry point then re-hashes the frozen and original raw source bytes and
   refuses if either moved while the engine was running.
7. Copy the verified `.tres` into the new output directory and write the
   manifest last. A failure before publication leaves no destination; a
   failure during publication removes the files it created and the directory.

## Output contract

The new directory contains exactly:

| Artifact | Contents |
| --- | --- |
| `handling.tres` | Text `Resource` with `script_class="HandlingDefinition"` and the mapped core physical values. |
| `bake_manifest.json` | UTF-8 JSON object describing the bake. |

Manifest keys:

| Key | Meaning |
| --- | --- |
| `manifest_version` | Manifest format version (`1.0`). |
| `tool` | Entry-point path. |
| `source_contract` | Exact source contract spelling, `roadstorm.handling_config.1.1.0`. |
| `source_schema_version` | Declared source recipe version (`1.1.0`), copied from the mapper result. |
| `source_checker` | Committed checker invocation used. |
| `source_recipe` | Absolute path of the checked source file. |
| `source_content_hash` | Canonical `sha256:` hash of the source with `content_hash` removed, from the committed checker. |
| `source_file_sha256` | `sha256:` hash of the raw source file bytes. |
| `handling_definition_id` | Stable derived ID `<car_id>.handling`. |
| `handling_revision` | Recipe triplet revision, copied unchanged. |
| `handling_status` | Lowercase lifecycle status copied from the source. |
| `handling_display_name` | Derived `<display_name> handling`. |
| `typed_schema_version` | Typed resource contract version (`1.0.0`); never the source version. |
| `resource_file` | `handling.tres`. |
| `resource_sha256` | `sha256:` hash of the emitted `.tres` bytes. |
| `engine_version` | Exact `--version` string of the pinned engine used. |
| `mapping` | Engine summary: curve point count and whether the mapped yaw cap is `finite` or `INF`. |
| `round_trip` | `ok`, `validated`, and `fields_compared` from the pinned-engine reload. |
| `generated_utc` | UTC completion timestamp. |

Example success line:

```text
[car-recipe-bake] baked car.bake_probe_finite.handling -> /tmp/roadstorm-bake-demo/handling.tres (sha256:...)
```

## Tests

From the repository root:

```sh
python3 tools/car_recipe_bake/run_tests.py
python3 tools/car_recipe_bake/run_tests.py --keep-workspace   # inspect temp outputs
```

Options: `--timeout SECONDS` (default 300), `--godot-bin PATH`,
`--keep-workspace`.

Cases:

1. `finite source bakes and round-trips` - positive finite fixture; asserts
   exit 0, manifest and `.tres` hashes, identity/revision/status, pinned engine
   version, mapping summary and `round_trip.ok/validated`.
2. `unlimited source bakes and round-trips` - positive `{"unlimited": true}`
   fixture; asserts the mapped yaw kind is `INF` and the reload round trips it.
3. `null motor input is refused` - nonzero exit, no output directory.
4. `historical 1.0.0 recipe is refused` - nonzero exit, no output directory,
   `motor-input-missing` diagnostic.
5. `failure control: stale content hash` - intentional failing case; asserts
   nonzero exit, `content-hash-mismatch`, no output directory and no success
   manifest.
6. `existing destination is not written` - sentinel directory survives with no
   manifest or `.tres`.
7. `existing dangling destination symlink is refused` - the link survives and
   its absent target is not created.

The published `.tres` is byte-identical to the reloaded engine artifact: the
CLI compares SHA-256 before and after publication.

The runner exits `0` only when every case passes.

## Limitations

* One recipe per invocation; one output resource. No batch mode.
* Only source contract `1.1.0` recipes that pass `motor-ready` validation.
  Historical `1.0.0` recipes and unresolved/null required inputs are refused.
* Only the committed motor-ready `HandlingDefinition` subset is mapped. Drift,
  surge, drafting, airborne, surfaces, upgrades, presentation, contact caps and
  the rest of `CarDefinition` stay deferred.
* The typed `.tres` depends on the committed `HandlingDefinition` script; it is
  not a standalone physics asset and is not imported into any game cache.
* The `.tres` bytes include a generated engine resource id, so the SHA-256 is
  evidence for the artifact from this run, not a canonical content hash across
  independent engine processes.
* The private tests prove this CLI slice against synthetic fixtures. They do
  not replace source-to-runtime conversion review, production-content review,
  M0.2 acceptance or release-rights clearance.

Original project code under the Unlicense.
