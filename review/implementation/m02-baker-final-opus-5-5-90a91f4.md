# Independent M0.2 handling baker final scoped recheck, exact 90a91f4

**Verdict: pass** for the scoped baker delta. Both blockers from the earlier
reviews are closed. The checks below show each fix doing its job: reverting
either fix makes its new regression case fail, and the fixed tree passes
16/16 locally on macOS and on hosted Ubuntu. I found no new correctness or
artifact-integrity defect. The three findings below are low or nit.

This verdict covers only the five scoped baker paths. It does not accept M0.2,
M0.3 rights, M0 as a whole, or any release.

| Item | Value |
| --- | --- |
| Reviewer | Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, in Claude Code |
| Date | 2026-11-28 |
| Candidate | `90a91f4d50c5c19222f5446da6a0c598dcc10531`. Plain archive with no Git metadata. The `git hash-object` blob hashes of all five scoped files match the postimage indexes in `../scope.patch` (`2824140 7d54402 f32de6c 6e1cdef a9ba913`). `diff -rq ../source .` shows no differences apart from the harness `work/` directory and my `logs/`. Hosted run 46103684201 reports `headSha` 90a91f4d50c5. |
| Scoped base | `6908e5f` |
| Scope | `tools/car_recipe_bake/{README.md, bake_handling.gd, bake_handling_recipe.py, run_tests.py, fixtures/negative/negative_zero_drag_rolling.json}`. I also read the typed dependencies `src/data/handling_definition.gd`, `src/data/definition_identity.gd` and `src/data/handling_recipe_mapper.gd`, plus the earlier reviews `review/implementation/m02-baker-opus-5-5-71c6662.md` and `review/implementation/m02-baker-gpt-6-2-sol-6908e5f.md`. |
| Independence | No delegation or helpers. I did not read the other current reviewer's output. No Git mutation, no edits to candidate files, nothing published. All my writes are in `build/logs/` and this report. |

## Commands and results

Environment for every run below:

- A private copy staged with `rsync -a --exclude logs --exclude work ./ logs/stage/`.
- Private `HOME`, `TMPDIR` and XDG directories under `logs/priv/`.
- Python `/opt/homebrew/bin/python3.15` (3.15.2), run with `-I -B`. The system `python3` here is 3.9.6, so I did not use it.
- Pinned editor at `toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`.
- The shared lock `work/agents/coordinator/godot-test.lock`, taken with `lockf -k -w -t 300` and bounded by `timeout -k 10 600`.

No Godot process hung, so I had nothing to kill.

| # | Command or probe | Result |
| --- | --- | --- |
| 1 | `run_tests.py --godot-bin <pin> --timeout 60` on the exact stage | **16 passed, 0 failed**, exit 0. Log: `logs/suite.log`. |
| 2 | Mutation M1: in a stage copy, the success report reverted to `_success_report(handling, …)`, the pre-fix in-memory report. Then the full suite. | **15/1, exit 1.** Only case 15 failed: `bake exited 0, expected a refusal`. So case 15 detects the original false accept. Log: `logs/mut1.log`. |
| 3 | Mutation M2: in a stage copy, `_require_source_unchanged` replaced by the old shape (`read_bytes`, then the seam, then hash, then `resolve()`). Then the full suite. | **15/1, exit 1.** Only case 16 failed: `helper accepted a source symlink retargeted inside the final recheck window`. So case 16 detects the original A-bytes/B-label defect. Log: `logs/mut2.log`. |
| 4 | Helper boundary probes in `logs/probes/recheck_probe.py`, run against the staged CLI module. Log: `logs/probes/recheck_probe.log`. | See the next table. |
| 5 | End-to-end: finite fixture with `handling.acceleration_curve[0].speed_m_s = -0.0`, hash recomputed with the committed checker's `content_hash_of` (`logs/probes/mkfix.py`). Then the CLI with `ROADSTORM_GODOT_LOCK=<shared lock>`. | The checker reports 0 errors. The CLI exits 1 with `handling.acceleration_curve[0].speed_m_s: numeric-conversion-mismatch: expected source binary64 0000000000000080, engine reported 0000000000000000`. No destination is created. So the reloaded-resource gate also covers the curve arrays, not only the drag fixture. Log: `logs/probes/curve_negzero.log`. |
| 6 | `gh run view 46103684201 -R L-K-M/Roadstorm` (read-only), plus `gh api --allow-escape-sequences …/jobs/140851645738/logs` | Head `90a91f4d50c5…`. The job "import, validate, test" succeeded. Step "Handling bake CLI behaviour suite (M0.2)" succeeded with **`[tests] passed=16 failed=0`** at log line 680, including case 16 on Linux. The contract-suites and inventory jobs succeeded. Export preparation was still `in_progress` when I checked. Log: `logs/hosted-linux-job.log`. |

Results of the helper boundary probes (row 4):

| Probe | Result | Assessment |
| --- | --- | --- |
| P0: stable leaf symlink | Accepted, returns the real target path. | Correct. |
| P0b: stable parent-directory symlink | Accepted, returns the real target path. | Correct. |
| P0c: relative lexical path | Accepted, returns the real target path. | Correct. |
| P1: inside the seam, leaf retargeted to a different file with identical bytes | Refused. | Conservative. |
| P2: inside the seam, in-place rewrite of the same inode | Refused, because size and mtime changed. | Correct. |
| P3: inside the seam, `rename(B, A)` over the target path | Refused, because the inode changed. | Correct. |
| P4: inside the seam, parent-directory symlink retargeted | Refused, naming the `real2` destination. | Correct. |
| P5: leaf retargeted after `resolve()` but before the final `os.stat` | Accepted, labelled with path A. Path A still holds the opened inode and its bytes. | Truthful. This is the documented post-check limit. |
| P6: `rename(B, A)` after `resolve()` but before the final `os.stat` | Refused. | Correct. |
| P7: stable link, wrong expected hash | Refused, with the resolved path named. | Correct. |
| P8: inside the seam, leaf retargeted to a directory | Refused. | Correct. |

The filesystem is APFS (`/dev/disk10s2` on `/Volumes/PaseoData`, `apfs, local`). It reports real inode numbers, so `_same_open_file`'s rule of refusing when there is no usable inode is not triggered here.

Supplied evidence, which I did not rerun: the coordinator's frozen-archive log `baker-both-frozen-6d59ffa/suite.log`, the old helper control, and `baker-signedzero-20261128/REPORT.md`. My M1 and M2 mutations reproduce the same two pre-fix behaviours independently.

## Correctness assessment of the two fixes

**(1) Signed zero and reloaded-resource reporting.**

- `bake_handling.gd:117-119` now passes `reloaded` to `_success_report`.
- `_numeric_source_bits` (`:288-317`) and every identity string in the report (`:336-344`) therefore describe the resource that `ResourceLoader` read back from `handling.tres`.
- `bake_handling_recipe.py:806-818` and `:361-395` compare those bits exactly against the bits the checker derives from the frozen source. Missing, extra, malformed and mismatched entries all refuse before `_publish_outputs`.
- The Python side reads the published bytes from the same `handling.tres` that Godot reloaded (`:822-831`), inside private scratch.
- The mapper writes the same 12 numeric field groups that the gate lists: two curve arrays and ten scalars (`handling_recipe_mapper.gd:184-195`). No consumed numeric field is outside the gate.
- `_compare_round_trip` still uses numeric `==` (`bake_handling.gd:218-221`). That is now harmless, because the bit gate runs on the reloaded values.
- False refusal: a checker-accepted `-0.0` in any consumed field now refuses rather than publishing a `+0.0` artifact. That is the intended fail-closed outcome, and the README documents it. The positive fixtures still bake.

**(2) Final source recheck binding.**

- `bake_handling_recipe.py:462-528` keeps one descriptor open through four steps: `fstat`, then read to EOF, then `fstat` again, then the seam, `resolve(strict=True)` and `os.stat`.
- It requires equal `(st_dev, st_ino, st_size, st_mtime_ns)` and a nonzero inode. The hash check runs on exactly the bytes it read.
- The returned label is a path that, at the final `stat`, named the inode the hashed bytes came from. P5 shows the remaining post-check window. `README.md:348-350` states it accurately.
- The seam is a module global that only tests can set. The CLI has no argument for it, and production leaves it `None` (`:115`, `:494-495`).
- Linux: the code uses only `os.open`/`os.fstat`/`os.stat`/`realpath`, which behave the same on Linux. Hosted Ubuntu passed case 16 and both end-to-end retarget cases.

## Ranked findings

No blocking findings.

1. **Low (test precision): case 15's bit assertion is a loose substring check.**
   - Where: `tools/car_recipe_bake/run_tests.py:391`.
   - The case requires `"0000000000000080" in output and "0000000000000000" in output` anywhere in the combined output. It does not check that the refusal line carries the expected and reported pair in that order.
   - The `handling.drag.rolling: numeric-conversion-mismatch` check at `:387` already anchors the path, and M1 shows the case still catches the real regression. But a future refusal for this path with different bits could pass the case if 16 zeros appear anywhere else in the output.
   - Suggested fix: assert the exact substring `expected source binary64 0000000000000080, engine reported 0000000000000000`.

2. **Nit (documentation): the recheck also refuses a byte-identical replacement.**
   - Where: `tools/car_recipe_bake/README.md:136-140`, `:348-350`.
   - P1 shows that a target replaced by a different inode with the same bytes inside the recheck window is refused. An editor's atomic save of unchanged content would do this.
   - This is conservative and the window is microseconds wide. The README says identity "must match", so it is consistent. It does not state outright that unchanged bytes on a new inode also refuse.

3. **Nit (coverage): case 16 tests the helper, not the CLI.**
   - Where: `run_tests.py:606-673`.
   - Nothing end-to-end proves that `_run` records the helper's return value as `source_resolved_target` when a retarget happens in that window.
   - The wiring is direct (`bake_handling_recipe.py:252-255`, `:855`). The stable symlinked-source case asserts `source_resolved_target == str(fixture)` end to end (`run_tests.py:503-506`). The residual risk is negligible.

Already documented and accepted as limits:

- Default-valued properties are omitted from the `.tres`, so a reload depends on the current script defaults (`README.md:338-345`).
- Mutation after the final stat or after publication is not prevented (`README.md:346-350`, and probe P5).
- Signed zero is now refused outright rather than represented in the artifact. That is a product choice, not a defect.

## Limits

- My local engine execution is macOS only. The Linux evidence is the hosted job above; I did not run Linux locally.
- At the time of checking, the hosted export-preparation job for 90a91f4 had not finished. I did not watch it further.
- I did not rehash the editor archive against the publisher digest. I used the coordinator's pinned install, which reports the pinned version through the CLI's own version gate.
- After recording their logs, I deleted the mutation stage copies `logs/mut1` and `logs/mut2`. The exact edits are described in rows 2 and 3.
- This review does not cover the checker's own suites, `CarDefinition` baking, production content, M0.2, M0.3 rights, M0 as a whole, or release acceptance.

Report path: `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator/m02-baker-final-review-90a91f4/opus/report.md`
