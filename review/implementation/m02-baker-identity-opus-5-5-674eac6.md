# Independent M0.2 handling baker identity/recheck correction review, exact 674eac6

**Verdict: pass** for the scoped baker correction. Both earlier Sol findings
are closed:

- The NUL `display_name` case now refuses at `display_name` with no output.
- The same-inode, equal-length rewrite with a restored mtime now refuses.

My checks found no false accept. The findings below are low or nit. All of
them fail closed or concern test coverage and wording.

This verdict covers only the four scoped baker paths. It does not accept
M0.2, M0.3 rights, M0 as a whole, or any release.

| Item | Value |
| --- | --- |
| Reviewer | Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, in Claude Code |
| Date | 2026-11-28 |
| Candidate | `674eac684d12d0a82d3721c9a2425b9ff27b9807`. Plain archive with no Git metadata. The `git hash-object` blob hashes of the four scoped files equal the postimage indexes in `../scope.patch`: `46babdb` (README), `e56aa32` (CLI), `a6b8cf3` (NUL fixture) and `b572a0d` (runner). `diff -rq ../source <stage>` reports no differences. |
| Scoped base | `90a91f4` |
| Scope | `tools/car_recipe_bake/{README.md, bake_handling_recipe.py, run_tests.py, fixtures/negative/nul_display_name.json}`. I also read the dependencies, which the scope patch leaves unchanged: `bake_handling.gd`, `src/data/handling_recipe_mapper.gd`, `src/data/handling_definition.gd`, `src/data/definition_identity.gd` and the checker's `load_json_document`, `to_binary64`, `content_hash_of` and `_check_string`. |
| Prior inputs | `review/implementation/m02-baker-final-opus-5-5-90a91f4.md` (my own prior review) and `review/implementation/m02-baker-final-gpt-6-2-sol-90a91f4.md` (the other model's prior review). |
| Independence | No delegation or helpers. I did not consult the current Sol reviewer. No Git mutation, no candidate edits, nothing published. I wrote only under `../logs/` and to this report. |

## Commands and results

Environment for every run:

- A private copy staged with `rsync -a build/ logs/stage/`, byte-identical to `../source`.
- Private `HOME`, `TMPDIR` and `XDG_*` directories under `logs/priv/`, and `PYTHONDONTWRITEBYTECODE=1`.
- Python `/opt/homebrew/bin/python3.15` (3.15.2), run with `-B` or `-I -B`.
- Pinned editor `toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`.
- The shared lock `coordinator/godot-test.lock`. Suites ran under `timeout -k 10 900 lockf -k -t 600 <shared lock>`. Direct CLI probes passed `--lock-path <shared lock>` and had no outer lock.
- No Godot child hung, and no PID was stopped. After the runs, no Godot process from this directory remained.

The engine was never run on the live checkout.

| # | Command or probe | Result |
| --- | --- | --- |
| 1 | `run_tests.py --godot-bin <pin> --timeout 90` on the exact stage | **18 passed, 0 failed**, exit 0, 17 s. Log: `logs/suite.log`. |
| 2 | Mutation mD: delete the `_verify_identity_fidelity(report, expected_identity)` call (`:923`), then the full suite | **17/1.** Only case 17 failed, with `bake exited 0, expected a refusal`. So case 17 detects the original false accept. Log: `logs/mut/mD.log`. |
| 3 | Mutation mA: drop `st_ctime_ns` from `_stat_identity` (`:520`) | **18/0.** The descriptor re-read alone still catches case 18. Log: `logs/mut/mA.log`. |
| 4 | Mutation mB: hash `raw` instead of `reread` (`:641`), which disables the re-read gate | **18/0.** The ctime field alone still catches case 18. Log: `logs/mut/mB.log`. |
| 5 | Mutation mC: mA and mB together | **17/1.** Only case 18 failed: `helper accepted a same-inode equal-length rewrite with a restored mtime`. Log: `logs/mut/mC.log`. |
| 6 | Direct CLI on `fixtures/negative/nul_display_name.json` with the shared lock | Exit 1, no destination. Message: `display_name: handling-identity-mismatch: expected display_name 'Alpha\x00Omega handling', engine reported 'Alpha�Omega handling'`. Log: `logs/probes/nul_direct.log`. |
| 7 | `logs/probes/names.py`: 15 `display_name` variants. Each one is written into the finite fixture, rehashed with the committed `content_hash_of`, run through the motor-ready checker, then baked end to end. | See the identity table below. Log: `logs/probes/names.log`. |
| 8 | `logs/probes/recheck_probe.py`: helper boundary probes on the staged `_require_source_unchanged` | See the recheck table below. Log: `logs/probes/recheck_probe.log`. |
| 9 | `sh tools/car_recipe_schema/run_tests.sh` (checker, unchanged in scope) | **98 OK** when `python3` on PATH is 3.13 or 3.15. With the system `/usr/bin/python3` 3.9.6, which was first on my private PATH, 1 failure: `test_deep_presentation_nesting_is_refused_at_the_file_boundary`. That is an old-interpreter environment effect on an unscoped file, not a candidate defect. Log: `logs/checker.log`. |
| 10 | `gh run list/view -R L-K-M/Roadstorm --commit 674eac6…` (read-only) | The only run, 46105083542, is `completed/cancelled` with no jobs. **Hosted Ubuntu is not verified for this SHA.** Logs: `logs/hosted-runs.json`, `logs/hosted-run-view.json`. |

### Identity probes (row 7)

The checker accepted every variant except the lone surrogate, which the committed hash refuses.

| `display_name` source | Bake | Published / diagnostic | Assessment |
| --- | --- | --- | --- |
| `Alpha Omega`, `\t`, `\n`, U+007F, U+2028, emoji pair, NFD `é`, `"` and `\`, `%s %d`, literal U+FFFD, U+FFFF | exit 0 | Manifest and `.tres` hold exactly `<source> handling`, code point for code point. NFD was not normalized. | Correct. |
| `Alpha\u0000Omega` | exit 1, no output | `display_name: handling-identity-mismatch` | Correct. The defect is closed. |
| `﻿Alpha` (leading BOM) | exit 1, no output | Engine round trip: `display_name: round-trip-mismatch` | Correct. Fail-closed. |
| `Alpha\u0001Omega` | exit 1, no output | `could not read engine bake report: Invalid control character` | False refusal with a non-source-path message (F1). |
| `Alpha\u000bOmega` | exit 1, no output | `could not read engine bake report: Invalid \escape` | False refusal with a non-source-path message (F1). |
| `Alpha\ud800Omega` | not baked | Committed `content_hash_of` refuses it (surrogates not allowed) | Correct at the checker boundary. |

No variant produced a published artifact whose identity differs from the
source derivation. In this probe set the gate has no false accept.

### Recheck probes (row 8)

| Probe | Result | Assessment |
| --- | --- | --- |
| P0 stable leaf symlink; P0b stable parent symlink; P0c plain path; P0d two-level symlink chain; P0e hard-link alias | All accepted, each labelled with the real target or alias path. | Correct. No false refusal. |
| P12 concurrent read of the file inside the seam (atime only) | Accepted. | Correct. |
| P1 leaf retargeted in the seam to a different inode with identical bytes | Refused. | Conservative, as before. |
| P2 in-place equal-length rewrite in the seam, mtime restored | Refused through ctime. | Sol F2 is closed. |
| P3 `rename(B, A)` in the seam; P4 parent symlink retargeted in the seam | Refused. | Correct. |
| P9 equal-length rewrite with restored mtime **after** the final `stat`, before the descriptor re-read | Refused: `refusing to publish bytes that differ from the frozen source`. | Exercises the new re-read gate alone. |
| P9b A→B→A rewrite in the seam, so the final bytes equal the frozen ones | Refused through ctime. | Conservative. |
| P10 `chmod` only in the seam; P11 unrelated hard link added in the seam | Refused. | Conservative refusal of a metadata-only change inside a microsecond window. Acceptable. |
| P5 leaf retargeted between `resolve()` and the final `os.stat` (`os.stat` hook) | Accepted, labelled with path A. Path A still names the opened inode, whose bytes are A. | Truthful. This is the documented post-observation limit. |
| P14 directory submitted | Refused: `[Errno 21] Is a directory`, naming the path. | Correct, with a path-specific diagnostic. |

The filesystem is APFS (`/dev/disk10s2`, local) with real inode numbers.

## Assessment of the correction

**Identity gate.**

- `_expected_identity` (`bake_handling_recipe.py:397`) derives the four strings from the checker-parsed frozen document, which is the same document the numeric gate uses.
- The derivation matches the mapper exactly: `"%s.handling" % car_id`, `"%s handling" % display_name`, revision and status copied (`handling_recipe_mapper.gd:180-183`).
- The engine reports these fields from the `ResourceLoader` result, not from the in-memory mapping (`bake_handling.gd:117-119, 336-344`).
- `_verify_identity_fidelity` (`:413`) compares exact Python strings before any publication and names the source member.
- The other exported `DefinitionIdentity`/`HandlingDefinition` strings are not source-derived. `schema_version` is checked against the constant, and `notes` stays at its default. So no further source-derived identity field escapes a gate.
- Mutation mD shows case 17 is a real regression test.
- The new `OSError` wrappers in the CLI turn raw tracebacks into `BakeError` diagnostics that name the path. They do not change the decisions.

**Final source recheck.**

- ctime (`:520`) and the descriptor re-read (`:641`) each close the demonstrated same-inode case independently: mutations mA and mB both stay green, while mC fails.
- An unprivileged writer cannot set ctime, so on local POSIX filesystems the ctime check alone is sound. The re-read additionally covers rewrites between the final `stat` and the re-read (P9).
- Remaining window: a writer acting after the re-read, or retargeting after `resolve()` while the old path still names the opened inode (P5). This is the unavoidable post-observation race. It is not a defect in the scoped gate. The label remains truthful at the observation, and README lines 386-392 state the limit.
- Stable symlinks, symlink chains, parent links and hard-link aliases bake without false refusal.

## Findings, ranked

1. **Low, reproduced. Some checker-accepted control characters in `display_name` cause a false refusal with a diagnostic that names no source path.**
   - Reproduction: the checker accepts `"Alpha\u0001Omega"` and `"Alpha\u000bOmega"`. The bake exits 1 with `could not read engine bake report: Invalid control character …` or `Invalid \escape …`.
   - Cause: the engine writes its report with `JSON.stringify` (`bake_handling.gd:392`), which emits U+0001 raw and U+000B as the non-JSON escape `\v`. Python's strict `json.loads` then rejects the report (`bake_handling_recipe.py:882`).
   - Evidence that the engine kept the name: the parse error sits at the `display_name` line of the sorted report, so the reloaded resource still held the character. The refusal comes from the report transport, not from identity loss.
   - Impact: fail-closed and rare, with no integrity effect. It contradicts the README's claim at lines 210-211 that any identity difference refuses with `<source-path>: handling-identity-mismatch`. Here there is no difference, and the refusal does not name the path.
   - Options: transport the identity strings unambiguously, for example as UTF-8 hex the way the numeric gate transports bits. Or refuse these characters at the source boundary with a path-specific diagnostic. Or document the refusal. Not a blocker.
   - Log: `logs/probes/names.log`.
2. **Low, test coverage. Case 18 does not isolate either defence.**
   - Mutations mA (no ctime) and mB (no re-read) each leave the suite at 18/18. Only removing both makes case 18 fail.
   - So a future change could silently remove the descriptor re-read, whose purpose (`:619-622`) is filesystems without a usable ctime and rewrites after the final `stat`, without any committed test noticing.
   - My probe P9 shows the re-read works today.
   - A seam or test fired after `_same_open_file` (as in P9) would pin it.
   - Logs: `logs/mut/mA.log`, `logs/mut/mB.log`, `logs/mut/mC.log`, `logs/probes/recheck_probe.log`.
3. **Nit. The same-inode refusal message is misleading** (`bake_handling_recipe.py:614-616`).
   - When ctime, size or mtime differ on the same inode (P2, P10, P11), the helper reports `refusing to bind the opened source to a different file: X (resolved to X)`.
   - The file is the same; its content or metadata changed. The refusal is correct, but the wording could send a user looking for a retarget that never happened.
4. **Nit, documentation.** The `_stat_identity` docstring (`:510-513`) says POSIX updates ctime "on that metadata restoration". That is true, but ctime is also updated by the write itself. Either one alone defeats the restored-mtime evasion. The meaning is unchanged.

The prior Sol findings F1 (NUL display name) and F2 (restored-mtime
in-place rewrite) are both **closed**. I found no other material integrity gap
in the scoped gate with a concrete reproduction.

## Limits

- **Local only.** Everything above was verified locally on macOS (APFS, Python 3.15.2, pinned 4.7.2 editor).
- **Hosted Linux not verified.** The only hosted run for `674eac6` (46105083542) was cancelled with no jobs, so the hosted Ubuntu suite was not observed for this SHA. ctime and descriptor re-read semantics are standard on Linux, but I did not run them there.
- **Supplied evidence, not rerun.** The coordinator's 18/18 frozen-archive log and its old-source 0/2 control. My mutations mD and mC reproduce the two pre-fix behaviours independently.
- **Probe coverage.** Probes cover the listed `display_name` variants and recheck seams only. `car_id`, `revision` and `status` mismatches are guarded by the same code but not reachable through checker-accepted ASCII grammars, so I did not exercise them end to end.
- **No external writer was raced.** The remaining read-to-publication window is documented, and I treat it as inherent.

Report: `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator/m02-baker-identity-review-674eac6/opus/report.md`
