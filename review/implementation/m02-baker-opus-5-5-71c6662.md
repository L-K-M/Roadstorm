# Independent M0.2 one-recipe handling bake review, exact 71c6662

**Verdict: changes required.** The bake design is sound on macOS. Every
c4b99fd finding in scope is closed in code, and the full behaviour suite
passed 14/14 locally. But the hosted Linux run of that suite on this exact SHA
**failed, 8 passed and 6 failed**. Every engine-backed case is refused at the
engine-version gate, because `flock --verbose` writes a line to stderr that
the gate reads as the engine version (F1). So the Linux portable-lock path and
hosted execution of the actual baker cases, which this candidate exists to
add, are broken, not proven.

| Item | Value |
| --- | --- |
| Reviewer | Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, in Claude Code |
| Date | 2026-11-28 |
| Candidate | `71c6662b17ec29312b093a552a0d48ffcc8009a6`. Plain archive, no Git metadata. Identity comes from the brief and from hosted run 46101433151 `headSha`. |
| Scoped base | `c4b99fd` |
| Scope | The 11 paths in `../scope-stat.txt` / `../scope.patch`: the bake CLI, engine script, runner, fixtures and README; the checker's motor-ready `provenance.source_contract` rule, with its tests, README and schema notes; and the CI baker step. |
| Independence | No delegation or helpers. I did not read the Sol reviewer's current packet. No Git mutation, no edits to candidate files, nothing published. |

## Ranked actionable findings

### F1 (high, broken hosted gate): on Linux, `flock --verbose` stderr is parsed as the engine version, so every engine-backed bake fails

- **Where:**
  - `tools/car_recipe_bake/bake_handling_recipe.py:526` adds `--verbose` to `flock`.
  - `:557-558` (`_engine_output`) joins stdout and stderr.
  - `:571-574` (`_verify_engine`) takes the last non-blank line of that combined output as the version.
  - util-linux `flock --verbose` prints `flock: executing <cmd>` to stderr, so the version check always fails on Linux.
- **Evidence:** hosted run 46101433151 on `71c6662`, job `import, validate, test` (id 140844534918), concluded `failure` at step "Handling bake CLI behaviour suite (M0.2)". The log is saved at `logs/hosted-46101433151-import.log`, lines 669-767.
  - `[tests] passed=8 failed=6`.
  - Both positives, the subnormal refusal, the symlinked-source success and both retarget refusals fail with: `engine is not the pinned build: expected '4.7.2.stable.official.ed1daf0bf', got 'flock: executing /home/runner/work/_temp/godot/Godot_v4.7.2-stable_linux.x86_64'`.
  - The 8 cases that passed are all checker or pre-engine refusals plus the unit-level bit control. No Linux engine bake ran.
  - The other three jobs (contract suites, export preparation, inventory) succeeded.
- **Impact:**
  - On Linux the CLI cannot produce any bake.
  - The new CI step is red, so the claimed hosted coverage does not exist.
  - The subnormal and retarget cases "fail" on Linux for the wrong reason. They never reach the gate they are meant to test.
  - The README overclaims this coverage at `tools/car_recipe_bake/README.md:279-281` and `:317-318` ("Linux `flock` behaviour is proven by the hosted CI step").
- **Fix:**
  - Drop `--verbose`, or parse the version from Godot's stdout only.
  - Keep the last-line equality check.
  - Optionally add a unit control that feeds a stderr line into `_verify_engine`'s parsing.
  - Get a green hosted run on the corrected SHA before claiming Linux evidence.

### F2 (low, fidelity residual): signed zero passes the bit gate, but the published `.tres` reloads with the opposite sign

- **Where:**
  - `tools/car_recipe_bake/bake_handling.gd:280-309` and `:338` build `numeric_source_bits` from the in-memory `handling`, not from the `reloaded` resource.
  - The round-trip check at `:213-216` uses `==`, which treats `-0.0` and `+0.0` as equal.
- **Evidence:** I crafted `probe/negzero.json`: finite fixture, `handling.drag.rolling = -0.0`, rehashed with the committed `content_hash_of`.
  - The checker in motor-ready mode reports 0 errors.
  - The CLI exits 0, the manifest reports `round_trip.ok: true` and 18 fields compared, and the bit gate passes (`-0.0` survives Godot's JSON parse in memory).
  - `ResourceSaver` omitted `drag_rolling` from the `.tres`, because `-0.0 == 0.0`, the script default.
  - My independent `ResourceLoader` reload reads `0000000000000000`, while the source binary64 is `0000000000000080`.
  - Logs: `logs/cli-probes.log`, `logs/reload-probe.log`, `logs/reload-compare.log`.
- **Impact:** physically negligible. But it is a counterexample to the README's "exact binary64 equality" claim for the published artifact.
- **Fix:** emit `numeric_source_bits` from `reloaded`, or make the round-trip float comparison bitwise. A `-0.0` source then fails closed. Alternatively, refuse negative zero in the checker. Add a fixture for this case.

### F3 (low, artifact contract): default-valued fields are omitted from the `.tres`, so a reload depends on current script defaults

- **Evidence:** `ResourceSaver` omits properties equal to their declared defaults.
  - The unlimited bake (`out/unlimited/handling.tres`) has no `max_yaw_rate_rad_s` (the `INF` default), no `reverse_hold_time_s`, `reverse_acceleration_m_s2` or `reverse_top_speed_m_s`, and no `status` (PROVISIONAL), `schema_version` or `notes`.
  - The finite bake omits `revision = "0.1.0"`, `schema_version` and `notes`.
  - Defaults are declared at `src/data/handling_definition.gd:56-69` and `src/data/definition_identity.gd:43-50`.
- **Impact:**
  - Today the reload matches the source exactly; see the positive results below.
  - A later change to a script default (for example `DESIGN_REVERSE_HOLD_TIME_MIN_S`, the yaw default, or `SUPPORTED_SCHEMA_VERSION`) would silently change what an existing baked `.tres` means.
  - `resource_sha256` would not change in that case, so it does not detect the drift.
  - The README says the `.tres` carries "the mapped core physical values" (`README.md:188`), which these files only partly do.
- **Fix:** record this dependency in the README Limitations, or force every exported field to serialize. This can be deferred to the importer/M0.3 boundary. It does not block the bounded slice on its own.

### Nits

- **`timeout` is optional in code but documented as required.** `README.md:50-56` lists `timeout` as a requirement. `_run_locked_godot` (`bake_handling_recipe.py:542-544`) silently skips it when it is absent, as on stock macOS. The fallback `subprocess.run(timeout=...)` kills only the lock wrapper, so the Godot grandchild may survive. Reading the code only; I did not reproduce this.
- **The lock wait and the Godot run share one timeout budget.** The outer `timeout N` covers both the lock wait (`-t N` / `-w N`) and the run. A long lock wait leaves Godot little time.
- **The resolved target is not read atomically with the recheck.** `_require_source_unchanged` returns `recipe_path.resolve()` (`:438`) after the read, so a retarget between the read and `resolve()` can record a different target from the bytes that were hashed. The bytes are still verified; only the recorded target can be wrong. Narrow window.
- **The default lock excludes nobody.** It lives in per-invocation scratch, so a default run is unserialized against other engine jobs. This is documented at `README.md:314-316`. The runner and CI also use a private lock.

## Closure of prior c4b99fd findings (Opus F1-F4 and nits, Sol 1 and 3)

| Prior issue | Status at 71c6662 | Evidence |
| --- | --- | --- |
| Ordinary 1-ULP drift (Opus F1) | **Closed on macOS** | My `probe/ulp.json` (curve speed `15.712549370676921`, braking `12.305009385671827`, rehashed) passes the checker. The CLI then refuses with `handling.acceleration_curve[1].speed_m_s: numeric-conversion-mismatch: expected source binary64 7eaf6745d36c2f40, engine reported 7daf6745d36c2f40`. Exit 1, no output directory. |
| Subnormal `5e-324` collapse (Sol 1) | **Closed on macOS** | The committed fixture is accepted by the checker and refused at `handling.reverse_acceleration_m_s2` with no output. Runner cases 6 and 7 pass locally. On Linux these cases did not reach the gate (F1). |
| Lexical symlink retarget, leaf and parent (Sol 3) | **Closed on macOS** | The lexical path is kept (`:175`, `:390-394`) and re-read at `:241`. Runner cases 12 and 14 pass locally. I also verified an in-place edit of a plain file during the engine run (`scripts/inplace-seam.sh`): "source recipe changed during the bake", exit 1, no output. |
| Linux portable lock and hosted baker execution (Opus F2) | **Not closed** | Implemented (`:508-530`, `ci.yml` step) but fails on hosted Ubuntu (F1). |
| Private macOS HOME, normalized scratch (Opus F4) | **Closed** | `_isolated_env` sets a private `HOME` plus XDG and TMP, each `resolve()`d (`:461-484`). The runner's caller-HOME sentinel assertion passed in my local run. |
| `provenance.source_contract` consistency (Opus F3) | **Closed** | Motor-ready refuses a 1.1.0 recipe without the exact token (`validate_car_recipe.py:1855-1891`). The rule runs after version dispatch, so `schema_version` is always a supported string there and there is no unhashable-key path. Through the CLI, my `prov_mismatch` and `prov_null` probes are refused by the checker with `source-contract-mismatch` / `source-contract-missing`, exit 1, no output. Schema mode keeps null valid (unit tests). The README manifest table (`:196`) now describes the field as validator-assigned and consistent with the rule. |
| Output cleanup and error handling (Opus nits) | **Closed** | `os.mkdir` with a required existing parent (`:788-796`). Created files are removed on failure (`:820-835`). The manifest is written atomically last. Scratch is removed in `finally`. The checker subprocess is now bounded (`:212`). Only non-`OSError` exceptions such as `UnicodeDecodeError` escape as tracebacks; they still exit nonzero and clean scratch. |
| Exact source bytes bind `.tres` and manifest; no old-source false pass | **Holds** | One frozen snapshot feeds the checker, the hashes and Godot. Snapshot and lexical path are rehashed after the engine run (`:235`, `:241`). For my finite and unlimited bakes, `source_file_sha256`, `source_content_hash` and `resource_sha256` match the files. |

## Positive reloads, independently checked

I baked `finite`, `unlimited` and a rehashed `control` through the CLI with
`--lock-path` set to the shared coordinator lock. All exited 0. `control` is
byte-identical to `finite`: same `resource_sha256`, `33df1db6...`.

A separate Godot probe (`scripts/reload_probe.gd`) ran in a private project
under the lock. It loaded each published `.tres` with `CACHE_MODE_IGNORE` and
emitted binary64 hex for every consumed field. `scripts/cmp_reload.py`
compared those values with the CLI's own `_expected_numeric_bits` over the
checker's `to_binary64`:

- finite: 14 fields, 0 mismatches.
- unlimited: 16 fields, 0 mismatches. Yaw is `000000000000f07f` (+inf).
- Revision, status and identity match.
- `validate()` returned empty for both reloads.

## Commands actually run (macOS, this host)

The private stage is `build/work/opus/stage`, copied from `../source`.
Environment: private `HOME`, `TMPDIR` and `XDG_*` under `build/work/opus/`,
`PYTHONDONTWRITEBYTECODE=1`, Python 3.15.2.

The pinned editor is the coordinator's `toolchain-m01/.../Godot` (the CLI
version gate confirmed `4.7.2.stable.official.ed1daf0bf`). Every Godot call
ran under `timeout` and the shared lock, through
`build/work/agents/coordinator/godot-test.lock`. That was either an outer
`lockf -k -t` or the CLI's `--lock-path`. Nothing ran in a live checkout.

1. `timeout -k 10 300 sh tools/car_recipe_schema/run_tests.sh`: **98 tests OK**, exit 0 (`logs/checker-tests.log`).
2. `timeout -k 15 1500 lockf -k -t 600 <shared lock> python3 -B tools/car_recipe_bake/run_tests.py --godot-bin <pinned> --timeout 180`: **14 passed, 0 failed**, exit 0 (`logs/baker-tests.log`). The runner's own engine calls used its private per-workspace lock, nested inside my outer shared lock.
3. `scripts/craft.py`: five rehashed probe recipes, checked with the committed checker in motor-ready mode.
4. Eight CLI invocations: finite, unlimited, control, ulp, negzero, prov_mismatch, prov_null, inplace (`logs/cli-probes.log`). Outputs are in `build/work/opus/out/`.
5. Godot `--import` and `--script res://reload_probe.gd` on a private project, plus `cmp_reload.py` (`logs/reload-*.log`). The import logged a harmless missing `res://scenes/boot.tscn`, because I did not copy `scenes/`.
6. `gh run view 46101433151` and `gh api .../actions/jobs/140844534918/logs`. The run is completed with conclusion **failure**, `headSha` `71c6662...`. Only the `import, validate, test` job failed, at the baker step.

There were no timeouts and no hung Godot children.

## Evidence classes

- **macOS local, executed by me:** the 98 checker tests, the 14/14 runner cases, the CLI probes and the reload probe.
- **Linux, hosted CI:** run 46101433151. The baker suite failed 8/6 (F1). Contract suites passed (job-level conclusion only; I did not count hosted tests).
- **Supplied, not rerun:** the coordinator logs `provenance-baker-combined-20261128/{schema-test.log,baker-test.log}` (98/98 and 14/14). These agree with my macOS results and are macOS evidence, not Linux.

## Files inspected

- The full `../scope.patch`.
- In full: `tools/car_recipe_bake/{bake_handling_recipe.py,bake_handling.gd,run_tests.py}`.
- `tools/car_recipe_bake/README.md`: lock, gate, manifest, tests and limitations sections.
- The checker's motor-ready and source-contract code and `validate_recipe_document` dispatch.
- The new checker tests.
- The `schemas/common.schema.json` and `handling_config_v1_1.md` changes.
- The CI step and the runner list of `ci.yml`.
- `src/data/handling_definition.gd` and `definition_identity.gd` exported defaults.
- The positive fixture contents.
- Both prior c4b99fd reports.

## Limits

- I did not run actionlint, a JSON Schema validator or the data lab.
- I did not reverify the editor archive digests.
- I did not test Linux locally. Linux behaviour comes only from the hosted log.
- The SHA is attested by the brief and by the hosted `headSha`.
- This verdict covers only the one-recipe handling bake, the motor-ready provenance-token rule and the CI baker step. It is not a general importer, a `CarDefinition` bake, production content, full M0.2 or M0 acceptance, release rights or end-to-end acceptance.
