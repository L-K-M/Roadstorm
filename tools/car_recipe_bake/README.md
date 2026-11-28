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
| `fixtures/negative/subnormal_reverse_acceleration.json` | Checker-accepted `reverse_acceleration_m_s2` literal `5e-324`; the pinned engine rounds it to zero and the fidelity gate refuses. |
| `fixtures/negative/negative_zero_drag_rolling.json` | Checker-accepted `handling.drag.rolling` literal `-0.0`; `ResourceSaver` drops it as the `+0.0` script default, the reloaded resource has the opposite sign, and the fidelity gate refuses. |

Fixture values are explicit synthetic placeholders (`example`/`provisional`),
not measured production handling. The positive fixtures are adapted from
`fixtures/car_recipe/positive/example_rookie_finite.json`; every fixture
recomputes its canonical `content_hash` except `stale_content_hash.json`, which
is intentionally wrong.

## Requirements

* Python 3 standard library.
* The pinned Godot build. By default the tool uses `$GODOT_BIN`, then `godot`
  on `PATH`, and verifies that the last `--version` line equals the
  `version_string=` recorded in `tools/toolchain/pin/engine.txt`.
* `timeout` and one exclusive lock utility on `PATH`: BSD `lockf` (macOS) or
  util-linux `flock` (Linux). On macOS the tool prefers `lockf`; elsewhere it
  prefers `flock`, falling back to the other when present. Both use
  flock(2)-style advisory locks, so they interoperate on the same inode.
  `timeout` wraps every engine call, and the lock wrapper bounds the wait as
  well. If neither utility exists the tool refuses before invoking the engine;
  it never runs Godot unlocked.
* `--lock-path FILE` selects an explicit lock file. Without it, the
  `ROADSTORM_GODOT_LOCK` environment variable is used, and otherwise the
  invocation locks a private file inside its own scratch directory. An
  explicit lock path must have an existing parent directory; the lock utility
  creates the leaf. The default therefore never creates or writes through a
  live unrelated checkout's `work/agents/coordinator/` tree.

The tool first freezes the input recipe bytes into private scratch, then
checks, hashes and maps that exact copy. It refuses if the original path's
bytes changed before publication. The manifest records the original path and
the accepted byte snapshot's SHA-256. The tool stages a private project copy (`project.godot`, `src/`, `scenes/`,
`tools/car_recipe_bake/`) into a fresh temporary directory and points `HOME`,
`XDG_CACHE_HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `TMPDIR` at private
directories under it, using normalized real absolute paths (`Path.resolve()`)
so the pinned editor's settings, `app_userdata` (including
`objectdb_snapshots`) and cache writes stay in the per-invocation scratch tree.
It never imports into or writes through the shared checkout `.godot/` cache
and never modifies `project.godot`. The positive suite cases point the
caller's `HOME` at a sentinel directory and assert it is unchanged after the
bake, which fails if any engine artifact escapes the private home.

## Bake command

From the repository root:

```sh
python3 tools/car_recipe_bake/bake_handling_recipe.py \
    --recipe tools/car_recipe_bake/fixtures/positive/finite.json \
    --output-dir /tmp/roadstorm-bake-demo
```

`--output-dir` must name a new directory whose parent already exists. The
command creates only the leaf (`os.mkdir`) and does so only after every check
and the engine round trip has passed, so a failed publication cannot leave a
missing parent or partial-directory debris behind.

Useful options:

```sh
--godot-bin /path/to/Godot   # override $GODOT_BIN / PATH resolution
--timeout 300                # outer seconds per engine invocation (default 300)
--lock-path /path/to/lock    # explicit lock file (default: private scratch lock)
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
5. Stage a private project copy, then under `timeout ... <exclusive lock>`
   with isolated `HOME`/XDG/TMP directories run:
   * `godot --headless --path <private-project> --import`;
   * `godot --headless --path <private-project> --script
     res://tools/car_recipe_bake/bake_handling.gd -- --recipe <frozen-checked-recipe>`.
6. The engine loads the checked recipe, calls
   `HandlingRecipeMapper.map_handling`, runs `handling.validate()`, saves the
   `.tres` with `ResourceSaver.save`, reloads it with
   `ResourceLoader.load(..., CACHE_MODE_IGNORE)`, revalidates it, compares all
   18 serialized identity/handling fields, and writes a private JSON report.
   That report carries `numeric_source_bits`, the little-endian binary64 byte
   image of every consumed numeric field keyed by dotted source path. Before
   anything is published, the entry point derives the same mapping from the
   frozen source bytes with the committed checker's parsing/representability
   policy and requires exact path-to-hex equality; a mismatch, missing or
   extra field, or malformed hex refuses with a diagnostic naming the path.
   It then re-hashes the frozen and original raw source bytes and refuses if
   either moved while the engine was running. For the original submitted path
   the bytes are read through one descriptor that stays open across the read,
   a before/after `fstat` stability check, the lexical resolution and a final
   `stat` of the resolved target; device, inode, size and mtime must match the
   opened file, or the bake refuses instead of publishing a mismatched label.
7. Copy the verified `.tres` into the new output directory and write the
   manifest last. A failure before publication leaves no destination; a
   failure during publication removes the files it created and the directory.

## Numeric conversion gate

The pinned Godot 4.7.2 JSON parser rounds some accepted literals before the
mapper sees them: `5e-324` becomes `0.0`. The committed checker accepts that
literal because it is the shortest decimal for the smallest positive binary64
value. Without an explicit boundary check, the bake compared the already
mapped value with itself and reported a validated round trip of the changed
number.

The gate closes that gap without replacing the checker or reparsing in Godot:

* `bake_handling.gd` writes the reloaded definition's numeric fields as raw
  little-endian binary64 bytes (`StreamPeerBuffer.new()`, `big_endian =
  false`, `put_double(value)`, `data_array.hex_encode()`) under
  `numeric_source_bits`, keyed by dotted source path. Covered paths are both
  members of every `handling.acceleration_curve[i]` point plus
  `handling.braking_acceleration_m_s2`, `handling.drag.aerodynamic`,
  `handling.drag.rolling`, `handling.yaw_gain.grip`,
  `handling.max_yaw_rate_rad_s` (finite, or `{"unlimited": true}` encoded as
  binary64 `+inf`), `handling.lateral_damping.grip_per_s`,
  `handling.reverse_trigger_speed_m_s`, `handling.reverse_hold_time_s`,
  `handling.reverse_acceleration_m_s2` and `handling.reverse_top_speed_m_s`.
* From the same frozen bytes, `bake_handling_recipe.py` parses with the
  committed checker's `load_json_document`, converts with its `to_binary64`
  representability policy, and encodes each expected value with
  `struct.pack('<d', value).hex()`.
* The two mappings must have exactly the same keys and equal lowercase
  16-character hex values. Any mismatch, missing field, extra field or
  malformed hex refuses before publication, so no output directory or
  manifest is created.

Example refusal for the subnormal fixture:

```text
[car-recipe-bake] error: handling.reverse_acceleration_m_s2: numeric-conversion-mismatch: expected source binary64 0100000000000000, engine reported 0000000000000000
```

```text
[car-recipe-bake] error: handling.drag.rolling: numeric-conversion-mismatch: expected source binary64 0000000000000080, engine reported 0000000000000000
```

This gate covers the checker-to-Godot boundary for the fields the committed
mapper consumes. It does not repair the pinned parser, and it does not make
Godot's number parsing correctly rounded.

`numeric_source_bits` is taken from the `ResourceLoader` result, not from the
in-memory mapped definition. `ResourceSaver` omits properties equal to their
script defaults, so a mapped value can differ from what the published `.tres`
holds while still comparing equal numerically. The negative-zero fixture
exercises exactly that: the checker accepts `handling.drag.rolling = -0.0`,
the mapper keeps `-0.0` in memory, serialization drops it in favour of the
`+0.0` default, and the gate sees the sign flip and refuses.

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
| `source_contract` | Contract this bake validated against (`roadstorm.handling_config.` plus the report's schema version); validator-assigned, not copied from the recipe's optional `provenance.source_contract`. |
| `source_schema_version` | Declared source recipe version (`1.1.0`), copied from the mapper result. |
| `source_checker` | Committed checker invocation used. |
| `source_recipe` | Absolute path of the checked source file, exactly as submitted. |
| `source_resolved_target` | The path the submitted spelling resolved to during the final recheck, bound by device/inode/size/mtime to the descriptor the accepted bytes were read from. |
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
`--keep-workspace`. Each run passes an explicit private `--lock-path` inside
its own temporary workspace, so the suite never takes a live checkout's
coordinator lock.

Cases:

1. `finite source bakes and round-trips` - positive finite fixture; asserts
   exit 0, manifest and `.tres` hashes, identity/revision/status, pinned engine
   version, mapping summary and `round_trip.ok/validated`. Runs with the
   caller's `HOME` pointed at a sentinel directory and asserts that directory
   is unchanged, proving the engine wrote only under its private home.
2. `unlimited source bakes and round-trips` - positive `{"unlimited": true}`
   fixture; asserts the mapped yaw kind is `INF`, the reload round trips it,
   and the same caller-`HOME` sentinel stays clean.
3. `null motor input is refused` - nonzero exit, no output directory.
4. `historical 1.0.0 recipe is refused` - nonzero exit, no output directory,
   `motor-input-missing` diagnostic.
5. `failure control: stale content hash` - intentional failing case; asserts
   nonzero exit, `content-hash-mismatch`, no output directory and no success
   manifest.
6. `subnormal reverse acceleration is accepted by the committed checker` -
   the committed `motor-ready` checker accepts the new fixture, proving it
   reaches the checker-to-Godot boundary.
7. `subnormal reverse acceleration is refused at its exact source path` -
   nonzero exit, `handling.reverse_acceleration_m_s2:
   numeric-conversion-mismatch`, no output directory and no manifest.
8. `control: deliberately wrong numeric report bit is refused` - unit-level
   control against the real gate: a flipped bit, a missing field, an extra
   field and malformed hex each refuse with a specific diagnostic.
9. `existing destination is not written` - sentinel directory survives with no
   manifest or `.tres`.
10. `existing dangling destination symlink is refused` - the link survives and
   its absent target is not created.
11. `symlinked source path bakes and records both spellings` - success through
    a stable source symlink; manifest records the submitted spelling and the
    resolved target.
12. `input symlink retargeted during the bake is refused` - a test-only
    `--godot-bin` wrapper retargets the source link after the snapshot;
    refusal names the path and leaves no output.
13. `dangling input symlink is refused` - unreadable source, no output.
14. `input parent symlink retargeted during the bake is refused` - same seam
    against a symlinked parent directory; refusal names the submitted path.
15. `negative zero drag rolling is refused at its exact source path` - the
    committed checker accepts the `-0.0` fixture, the pinned engine reloads
    `+0.0`, and the bake exits nonzero with `handling.drag.rolling:
    numeric-conversion-mismatch` (source bits `0000000000000080`, reloaded
    `0000000000000000`), leaving no output directory or manifest.
16. `source symlink retargeted inside the final recheck window is refused` -
    unit-level helper control: a stable symlink returns its opened target,
    then a test-only seam retargets the link after the final recheck opened
    and read it but before it resolved the target; the helper refuses and
    names both spellings instead of returning the new path.

Positive cases 1, 2 and 11 exercise the `ResourceSaver`/`ResourceLoader` round
trip and the exact numeric-bit gate; negative cases cover checker refusals,
the deliberate hash control, the fidelity boundary and destination/source-path
trust. Cases 8 and 16 are unit-level and need no engine.

Hosted CI runs this same suite on clean Ubuntu against the digest-verified
pinned editor, which is where the util-linux `flock` lock path is exercised;
see `.github/workflows/ci.yml`. The macOS host uses BSD `lockf`.

Run the suite with the pinned editor and a bounded outer timeout:

```sh
python3 tools/car_recipe_bake/run_tests.py --timeout 60 \
    --godot-bin /opt/homebrew/bin/godot
```

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
* The numeric gate proves binary64 equality only for the fields the committed
  mapper consumes. It does not repair the pinned JSON parser, cover deferred
  `CarDefinition` fields, or make Godot's number parsing correctly rounded.
* `ResourceSaver` omits properties equal to their declared script defaults
  (`revision = "0.1.0"`, `schema_version`, `notes`, an `INF` yaw cap and
  others). A baked `.tres` therefore reloads through the current defaults of
  `src/data/handling_definition.gd` and `src/data/definition_identity.gd`;
  changing one silently changes what an existing artifact means without
  changing its `resource_sha256`. The numeric gate checks source values against
  the resource reloaded under the current script defaults, including the
  negative-zero fixture; it does not bind future versions of those defaults.
* The final source recheck binds `source_resolved_target` to the identity
  (device, inode, size, mtime) observed while the accepted bytes were being
  read. It narrows the read-to-label window but does not prevent arbitrary
  mutation of the submitted path after that check or after publication.
* The private tests prove this CLI slice against synthetic fixtures. They do
  not replace source-to-runtime conversion review, production-content review,
  M0.2 acceptance or release-rights clearance.
* The default lock is per invocation. A host that wants cross-tool
  serialization passes `--lock-path` (or `ROADSTORM_GODOT_LOCK`) pointing at
  the shared coordinator lock; the tool itself never assumes one exists.
* Linux `flock` behaviour is proven by the hosted CI step, not by this macOS
  host; see the job report for the local static command proof.

Original project code under the Unlicense.
