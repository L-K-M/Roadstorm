# Roadstorm M0.8 final tick correction review

**Verdict: pass for the scoped correction.** The new assertions verify that both default-priority observers see each logical tick in the same engine physics frame in which the coordinator commits it. The priority-0 captures isolate the earlier observer’s one-frame delay while preserving the old sequence and callback-count checks. I found no production defect in the correction.

- **Date** November 27, 2026
- **Reviewer** OpenAI Codex, accessed through the API in the `sol` review slot. The requested `gpt-6.2-sol` serving model, Codex CLI route, and Daybreak-disabled setting were unavailable for independent verification.
- **Candidate** `da021e08b6b53d28c659a0b385949550abff1b39`
- **Base** `b5c4f99950bebc551849c1cc197db3b4c810b8c8`
- **Snapshot** `work/agents/coordinator/reviews/tick-da021e0/sol/source`

## Findings

**Production defects.** None found in the scoped change.

**Test and evidence gaps, ranked.**

1. **Low · The mutation harness accepts broader failures than the recorded result.** `tools/tick_probe/tests/run_frame_alignment_mutation.py:105` accepts any nonzero child exit and any failure containing `callback frames align`, provided it sees no matching sequence or callback-count failure lines. A later-observer failure, additional unrelated failures, or missing control PASS lines can still produce `DEMONSTRATED=true`. Require the expected child exit and reconciled summary, exactly the earlier-observer failure, and explicit PASS lines for both sequence checks, the callback count, and later-observer alignment. The three archived captures already meet those stronger conditions.
2. **Low · The evidence introduction misstates the prior verdicts.** `tools/tick_probe/evidence/2026-11-27-apple-m4-max-jolt-frame-alignment/README.md:3` says both `b5c4f99` reviews passed. The prior Opus report says **pass**, with R1 to address before M1. The prior Sol report says **changes required**. Record the two verdicts as issued.

**Optional improvement.** Add a focused rollover and reset check if a consumer begins relying on the diagnostic history beyond the short ordering test. At `tools/tick_probe/src/tick_coordinator.gd:424`, only committed ticks append a frame. The 20,000-entry cap and base calculation preserve the logical-tick lookup after eviction. Reset clears the array and restores base `1` at line 223, and lookups outside the retained range return `-1` at line 621. The ordering test exercises the first 12 entries, so the rollover behavior was verified by inspection.

## Prior findings and evidence

- **Opus R1 is resolved.** The observer records `Engine.get_physics_frames()` beside each observed tick, and the driver compares it with the coordinator’s frame for that exact tick. The sequence and callback-count checks independently enforce all 12 samples. The diagnostic stays outside the compared tick trace. Both mutation anchors occur exactly once. The scratch patch changes coordinator priority from `-1000` to `0` and replaces only the numeric assertion with a count-preserving placeholder. In all three captures the earlier observer is exactly one frame late for every tick, the later observer still aligns, both sequence checks and the count check pass, and the child exits `1` with one failure out of 137. The fixed capture shows observer frames `420–431` against coordinator frames `419–430`. See `tools/tick_probe/tests/contract_driver.gd:94`, `tools/tick_probe/tests/callback_observer.gd:20`, and `tools/tick_probe/evidence/2026-11-27-apple-m4-max-jolt-frame-alignment/mutation-frame-alignment-fixed.txt:83`.
- **The idle and publication windows are documented accurately.** `tools/tick_probe/README.md:330` covers the possible pausable idle advance after the final server step. Line 337 covers a pausable node that runs before the coordinator in the publication iteration. The coordinator sets pending publication at `tools/tick_probe/src/tick_coordinator.gd:595` and pauses at line 382 in the next physics callback.
- **The remaining prior corrections are present.** The documented `FAKE_CHECKS=137` matches `--expect-checks 137`. The capture records the reported-failure branch and exit `1`. The repeat runner’s usage and default both specify `70`. The historical errata points to the existing `repeat-{fixed,default,max}.txt`, and its provenance README hash agrees with the archived file and manifest. The base manifest verifies 56/56 against the original base blobs. The corrected historical manifest verifies 51/56 against the candidate, with the five expected differences in the old probe source and documentation bindings.
- **The captured totals reconcile.** Fixed, default, and max each record contract **137/137**, repeat **70/70**, strict N1 **76/76**, and structural **108/108**. The prior repeat mutations record **17**, **1**, and **1** failures for immediate publication, deferred refusal pause, and removed publication guard, respectively. Those three logs are byte-identical to the previous captures. Their rerun and exit statuses are worker provenance claims. The coordinator separately reported rerunning the contract in all three pacings, the fixed priority mutation, and the fixed repeat suite on the archived candidate.

## Inspection and commands

- Read `review/implementation/m0-tick-opus-5-5-b5c4f99.md` and `review/implementation/m0-tick-gpt-6-2-sol-b5c4f99.md`. Inspected the changed probe README, coordinator, callback observer, contract driver, mutation harness, and repeat runner. Read the relevant contract runner and fake Godot fixture. Audited the `frame-alignment` captures and provenance and the corrected `phase-followup` errata, manifest, and provenance.
- Ran read-only `git rev-parse`, `git show --stat`, and scoped `git diff` and `git diff --check`. The snapshot is nested under an enclosing Git repository, so I used the named commit objects from that repository to establish identity. `git diff --check` reported no whitespace errors.
- Ran `python3 -c` with `git ls-tree` and `git show` to compare all **475** scoped paths and file contents against the candidate. The file sets and bytes matched. Python SHA-256 checks verified **63/63** current manifest entries, both current provenance hash maps, and both corrected historical-document hashes. A first attempt using a shell heredoc was blocked by the read-only sandbox. The inline command completed the checks.
- Used `ls`, `cat`, `rg`, `nl`, `sed`, and inline Python to inspect the captures, reconcile contract JSON with stdout, check totals and mutation frame offsets, and compare the three repeat mutation logs with the historical copies. `test -w ../tmp` reported the assigned scratch directory as unwritable.

## Capability limits

I performed an independent static and evidence review. The read-only sandbox prevented isolated execution, so I did not launch Godot or rerun a suite or mutation. I used no helpers or subagents, read no other current review, and made no source or Git changes. The runtime evidence is from headless Godot `4.7.2.stable.official.ed1daf0bf` with Jolt on one Apple M4 Max host. This verdict covers the tick correction only. Platform, audio, visual, gamepad, general contact and whole-M0 acceptance remain outside its scope.