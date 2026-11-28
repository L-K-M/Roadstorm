# Independent exact-source M0.2 corrected checker, mapper and one-recipe baker recheck

**Verdict: changes required for the bounded baker slice.** The corrected checker and mapper pass: every Sol and Opus c5c6f06 finding in scope is fixed, and each fix is verified. The new bake CLI publishes a `.tres` whose floats can differ by 1 ULP from the binary64 document its manifest hash binds. The cause is the pinned Godot JSON parser, which is not correctly rounded. I reproduced this end to end with a recipe the checker accepts (F1).

| Item | Value |
| --- | --- |
| Reviewer | Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, running in Claude Code |
| Date | 2026-11-28 |
| Candidate | `c4b99fd8411af20390e5177eb393fbe84f188cf1` (frozen archive with no Git metadata; identity taken from the brief and from the hosted run's `headSha`) |
| Scoped base | `c5c6f06c3e687501fc73196f177948d7527cafd0` |
| Scope | The 18 paths in `../scope.patch` / `../scope-files.txt`, the relevant contracts, and both exact-c5c6f06 reports in `review/implementation/`. M1 changes between base and candidate are excluded. |
| Independence | No delegation, no helpers, no contact with other reviewers. All checks ran in my private `build/` with isolated `HOME`/XDG/`TMPDIR` and the pinned editor under the coordinator lock. |

## Ranked findings

### F1 (medium, correctness of the bake binding): Godot's JSON parser mis-rounds checker-accepted literals, so the baked `.tres` can disagree with the hashed source

- **Where:** `tools/car_recipe_bake/bake_handling.gd:44-45` parses the frozen recipe with `JSON.parse_string`. `tools/car_recipe_bake/bake_handling_recipe.py:171` binds `source_content_hash`, which is computed over Python's correctly rounded binary64 conversion (`validate_car_recipe.py:441-449`, `to_binary64`). No step compares the engine-mapped values with those binary64 values. The round trip at `bake_handling.gd:92-110` compares Godot's values with Godot's own reload, so it cannot detect the drift.
- **Policy it breaks:** the checker docstring (`validate_car_recipe.py:43-51`) refuses any literal whose source text and baked value would disagree. Its round-trip-stable rule (`_is_round_trip_stable`, `:513-525`) explicitly accepts shortest-repr 17-digit literals and exact decimal expansions.
- **Probe 1 (pinned 4.7.2.stable.official.ed1daf0bf):** 5,307 literals, parsed in Godot and compared bit for bit with Python `float()`.
  - Shortest-repr values in [0, 200): 484 of 4,000 parsed to a different double.
  - Shortest-repr values in [0, 1): 134 of 1,000 differed.
  - Exact decimal expansions: 27 of 300 differed.
  - Edge values: `1e-23` and `2.2250738585072014e-308` differed.
  - Every difference I inspected was ±1 ULP.
  - Log: `logs/godot-json-float-probe.txt`. Scripts: `logs/scripts/gen.py`, `logs/scripts/cmp.py`.
- **Probe 2 (end to end through the committed CLI):** I set the second curve speed in `fixtures/positive/finite.json` to `15.712549370676921` and braking to `12.305009385671827`, then recomputed the canonical hash (`logs/scripts/craft.py`).
  - `--mode motor-ready` reports 0 errors.
  - `bake_handling_recipe.py` exits 0. The manifest binds hash `sha256:244e98e3...` and reports `round_trip.ok: true` with 18 fields compared.
  - The emitted `.tres` contains `15.71254937067692` and `12.305009385671829`. Python confirms each is the adjacent double (`nextafter`) of the source value.
  - Log: `logs/bake-ulp.log`.
- **Impact:**
  - The physical effect is negligible. The defect is in the integrity contract this slice introduces: the manifest claims the `.tres` was derived from the hashed source document, but the values can silently differ.
  - Values at an authored bound can be pushed 1 ULP outside it. The mapper then refuses them, so that direction fails closed.
  - The checker's representability policy is defined against CPython, not the runtime parser that actually produces the typed values.
- **Fix:**
  - Have the engine report the exact bits of every mapped float (for example `PackedByteArray.encode_double` hex, or `var_to_str` with full precision).
  - In Python, compare those bits with `to_binary64` of the frozen document for all 13 numeric fields. Refuse on any mismatch.
  - Add a regression fixture with a known mis-rounded literal such as `15.712549370676921`, and expect a refusal (or a correct bake once a correctly rounded path exists).
  - The same issue affects the importer the plan defers, and the data-lab `source_handling_mapping_json_fixtures` case. That case passes only because the committed fixtures use short literals.

### F2 (low, evidence gap): the baker's behaviour runner is local-only and cannot run on hosted Linux as written

- Hosted run 46095701245 only compile-scans `res://tools/car_recipe_bake/bake_handling.gd`. `ci.yml` adds the data lab but does not invoke `tools/car_recipe_bake/run_tests.py`.
- The CLI hardcodes `REPO_ROOT/work/agents/coordinator/godot-test.lock` (`bake_handling_recipe.py:50`) and calls BSD `lockf -k -w -t` (`:283-292`). util-linux has no `lockf`, so the committed tool would fail on the hosted Ubuntu runner.
- `LOCK_PATH.parent.mkdir(parents=True)` (`:278`) also creates `work/agents/coordinator/` inside whatever checkout runs the tool.
- The 7/7 baker result is therefore local pinned-engine evidence only: the coordinator's run and my own (below). State this in the README and status docs, or make the lock path configurable and portable before the baker is relied on in CI.

### F3 (low, plan gap carried from c5c6f06 F7): manifest `source_contract` is a constant, not the recipe's provenance

- `bake_handling_recipe.py:498` writes `SOURCE_CONTRACT_PREFIX + report["source_schema_version"]`, which is always `roadstorm.handling_config.1.1.0`.
- The checker still accepts a 1.1.0 recipe whose `provenance.source_contract` is `roadstorm.handling_config.1.0.0` or `null`, in both modes (`logs/checker-probes.txt`, `contract_mismatch` and `contract_null`). Such a recipe bakes with a manifest claiming 1.1.0. Its own contradictory provenance is neither refused nor recorded.
- The manifest field is defensible if it means "the contract this bake validated against". The README (`tools/car_recipe_bake/README.md:132`) calls it the "exact source contract spelling", which does not settle that meaning.
- **Fix:** either refuse a recipe whose provenance token disagrees with its `schema_version` at the bake boundary, or document the field as validator-assigned and also record the recipe's own value. The underlying meaning question remains an M0.3 item.

### F4 (low, hygiene): engine isolation is incomplete on the documented macOS host

- `_isolated_env` (`bake_handling_recipe.py:265-271`) sets XDG variables and `TMPDIR` but leaves `HOME` unchanged. Godot on macOS ignores the XDG variables.
- My run used a private `HOME`. Inside it, the engine created `Library/Application Support/Godot/editor_settings-4.7.tres`, `app_userdata/Roadstorm Racer!/` and `Library/Caches/Godot/editor_doc_cache-4.7.res`. A normal invocation writes these into the user's real `~/Library`.
- The README (`:54-61`) presents the XDG redirection as isolation. Either override `HOME` for engine calls or narrow that claim.

### Nits

- `os.makedirs(output_dir)` (`bake_handling_recipe.py:523`) creates missing parent directories. On a publication failure, `_remove_created_output` removes only the leaf. Use `os.mkdir` and require an existing parent.
- The checker subprocess (`:148-161`) has no timeout, unlike the engine calls.
- The manifest records an absolute `source_recipe` path and `generated_utc`, so manifests are host-specific and never byte-reproducible. This is documented for the `.tres` resource id but not for these keys.
- `README.md:46-47` says the version check tests that the output "contains" the pinned string. The code (`:320-325`) requires the last output line to equal it, which is stricter and correct. The README should say so.
- The engine pin gate compares only the `--version` string, not the binary digest. This is adequate for honest misconfiguration, not for proving the binary's identity.

## Prior findings: status at c4b99fd

| Prior finding | Status | Evidence |
| --- | --- | --- |
| Sol 1 / Opus F3: curve order compared before binary64 conversion | **Fixed** (`validate_car_recipe.py:1819-1839`) | `2**53`, `2**53+1` gives `number-not-representable` plus `motor-input-order`. `2**53`, `9007199254740992.0` gives `motor-input-order`. `0.1` followed by its exact expansion gives `motor-input-order`. All in motor-ready mode; schema mode stays silent where it should. |
| Opus F5: precision-losing integers accepted | **Fixed** (`:528-541`, `:913-922`) | `10**308` refused with `number-not-representable`; `2**300` accepted in both modes. |
| Sol 2: unknown-path regex prefix match / huge index | **Fixed** (`:136-142`, `:736-781`, `:1669-1682`) | Trailing LF, a 4,400-digit index and a 10-digit index give `bad-unknown-path`. An in-bound but out-of-range 9-digit index gives `unresolved-unknown`. A resolved curve point listed unknown gives `resolved-but-unknown`. No exceptions. |
| Sol 3: Decimal exponent and recursion exceptions | **Fixed** (`:349-364`, `:826-868`, `:1890-1903`, `:403-411`, `:444-449`) | `1e±99999999999999999999999999` gives `invalid-number`. A 5,000-digit integer gives `invalid-json`. Depth 250 or 3,000 gives `nesting-too-deep` at `presentation`. Depth 200,000 or 2,000,000 gives the parser-stage `nesting-too-deep` through both the library and the CLI. Depth 198 is accepted. A direct deep dictionary is refused by `validate_recipe_document` and raises `CanonicalizationError` from `content_hash_of`. |
| Opus F1: mapper null plus unknown reported as resolved-but-unknown | **Fixed** (`handling_recipe_mapper.gd:400-406`, `:499-505`, `:560-566`) | The null check now runs before the unknown check for scalar, yaw and whole-curve paths. The lab case `source_handling_mapping_review_repairs` covers all three. |
| Opus F4: mapper point-level unknowns and units | **Fixed** (`:432-451`, `:271-284`) | Point and point-member unknowns, and null point members, are refused. All four units are checked. Ancestor matching (`:643-647`) still covers `handling.drag` and `handling`. |
| Opus weak-test note: no JSON-fixture crossing | **Fixed** (`validate_data_lab.gd:2322-2343`) | Both committed positives parse in Godot and map with the expected ID and yaw kind. See F1 for the precision limit of this crossing. |
| Opus F2: hosted CI omits the mapper lab | **Fixed** (`ci.yml:127-137`) | Hosted run 46095701245 on `c4b99fd`: 19 cases, 537 checks, 0 failed, plus the deliberate failure proof (`logs/hosted-46095701245.log`). |
| Opus F6: bound messages lose precision | Not addressed (nit) | Unchanged |
| Opus/Sol F7/4: `source_contract` meaning | Open | See F3 |

**Schema-mode stability:** both baker positives and all four committed checker positives pass schema mode. In motor-ready mode, the only errors come from the intended null-input and v1.0.0 fixtures. The baker negatives give the intended codes: `motor-input-unresolved`, `content-hash-mismatch` and `motor-input-missing` ×5. The scope patch does not modify `fixtures/car_recipe/**`, and the content-hash algorithm is unchanged; only its error paths changed. Committed fixture hashes still verify (`logs/fixture-modes.txt`).

**Mapper:** the source dictionary is only read. Curves are built as fresh arrays, and the lab's nonmutation snapshots still pass. Typed identity is unchanged (schema `1.0.0`, `<car_id>.handling`).

**Baker items:**
- **Source bytes:** one private snapshot feeds the checker, the hash, the raw SHA-256 and Godot. The frozen copy and the original are both rehashed after the engine run (`bake_handling_recipe.py:146-178`). This is sound.
- **Destination:** an existing directory or a dangling symlink is refused through `os.path.lexists` on the unresolved leaf (`:131-135`). This is sound.
- **Engine refusal and field comparison:** stale-hash and null-plus-unknown recipes are refused by the checker before the engine runs. The engine report is strictly validated (`:401-467`). All 18 serialized fields are compared after an uncached `ResourceLoader` reload, and the reloaded resource is revalidated.
- **No test coverage:** there is no baker-level case for a resolved-but-unknown recipe, an engine-stage mapper refusal, or a wrong engine version. These paths are covered only by code reading.

## Commands and outcomes (run by me)

All commands ran from `opus/build` or `opus/build/work/opus-probe`, with `HOME`, `TMPDIR` and XDG directories set to private paths. Godot was `../../toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot` (`--version`: `4.7.2.stable.official.ed1daf0bf`, matching the pin), run under `timeout` and `lockf -k -t` on the coordinator lock through the build symlink.

1. `sh tools/car_recipe_schema/run_tests.sh` (private `CAR_RECIPE_WORK_DIR`): **90 tests OK** (`logs/checker-tests.log`).
2. `python3 -I tools/car_recipe_bake/run_tests.py --godot-bin <pinned> --timeout 240`: **7 passed, 0 failed, exit 0** (`logs/bake-run-tests.log`).
3. `python3 -I -B logs/scripts/chk_probe.py ...`: checker probes, results in the prior-findings table (`logs/checker-probes.txt`, `logs/checker-probes-2.txt`).
4. Checker over all positive and baker fixtures in both modes (`logs/fixture-modes.txt`).
5. Godot JSON-precision probe (`proj/probe.gd`) and comparison: 647 of 5,307 mismatches (F1).
6. End-to-end bake of the crafted recipe: exit 0, values drifted (F1; `logs/bake-ulp.log`, output in `build/work/opus-probe/bake/out-ulp/`).
7. `gh run view 46095701245 --repo L-K-M/Roadstorm`: `headSha` is `c4b99fd...`, completed, **success in all four jobs**. The log shows the data lab at 19/537/0 with the deliberate failure proof, and 90 checker tests in contract suites. The baker appears only as a compile scan.

I did not run the data lab myself; its result comes from the hosted log plus coordinator evidence. I did not run actionlint or a JSON Schema validator.

## Files inspected

The full `scope.patch`. In full: `tools/car_recipe_bake/{bake_handling_recipe.py,bake_handling.gd,run_tests.py,README.md}` and the fixture contents. The checker regions changed in the patch, plus `load_json_document`, the hash functions and the motor-ready/unknowns code. The changed mapper hunks plus `_unknown_paths` and `_path_is_unknown`. The data-lab additions and README. The `ci.yml` step. `tools/toolchain/pin/engine.txt`. Both c5c6f06 reports.

## Limits

- **Identity:** no Git metadata, so the SHA is attested by the brief and the hosted `headSha`.
- **Godot parser:** the probe covers 5,307 literals on the pinned macOS editor. I did not test Linux or export templates, which may share the same parser code.
- **Not claimed:** importer/cache behaviour, a `CarDefinition` bake, production content, M0.2 or M0 acceptance, and rights clearance.

## Fixes versus remaining plan gaps

- **Fixed in this candidate:** all three Sol checker findings, Opus F1/F4/F5/F3, the mapper's hosted-lab gap, and the JSON-fixture crossing.
- **Changes required for the baker slice:** F1, an engine-to-binary64 value cross-check with a regression fixture.
- **Remaining plan gaps:**
  - F2: hosted baker evidence and lock portability.
  - F3: `source_contract` meaning (M0.3).
  - F4: macOS `HOME` isolation.
  - Still out of scope: general importer/cache, `CarDefinition` bake, deferred fields, production content and M0 acceptance.


---

## Coordinator identity and disposition attestation

The report above is copied verbatim from this reviewer’s isolated packet. Opus CLI JSON confirms `claude-opus-5-5` on `firstParty`; the separate Sol Codex CLI header confirms `model: gpt-6.2-sol`, `provider: openai`. Each reviewed its own read-only plain archive of exact `c4b99fd8411af20390e5177eb393fbe84f188cf1`, with disjoint writable build and logs. Hosted CI run 46095701245 later passed all four jobs on that SHA, including the data lab at 19 cases/537 checks; the same SHA’s baker runner remains local-only. Both reviewers found a real checker-to-Godot numeric conversion gap. Sol’s subnormal and Opus’s ordinary 1-ULP examples are assigned to LongCat baker job `262a2a40-dd81-47d3-827c-fab062b1c082` for exact-bit source-to-engine comparison. Sol’s leading-zero unknown-path alias has a later uncommitted mapper correction that passed a frozen 19-case/541-check data lab; the source-symlink retargeting, hosted baker coverage and provenance vocabulary remain open. Both named scoped rechecks are due after the final corrected candidate. No full M0.2/M0 or release-rights gate is accepted.
