# Roadstorm M0.8 tick probe: Opus 5.5 recheck of the da021e0 correction

**Verdict: pass.** This correction fixes Opus R1. The new check compares physics frames, so it would catch the ordering fault that the `1..n` sequence check misses. The priority=0 mutation removes only the numeric priority check. It leaves the sequence and callback-count checks in place, and the captured runs show that only the new frame check fails. Sol's four items are also corrected. I found no new production defect and no unsupported evidence claim. Three low-severity test and documentation issues remain, listed below. None of them blocks this slice.

## Review details

- **Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), through Anthropic's first-party CLI (Claude Code). I used no helpers, subagents or delegation. I did not read any other review of da021e0.
- **Date:** 2026-11-27.
- **Candidate:** `da021e08b6b53d28c659a0b385949550abff1b39`. **Base:** `b5c4f99950bebc551849c1cc197db3b4c810b8c8`. The base is an ancestor of the candidate.
- **Snapshot:** `work/agents/coordinator/reviews/tick-da021e0/opus/source`. The snapshot sits inside the Roadstorm checkout, so the `git` commands below ran against that enclosing repository, read-only, using root-relative pathspecs.
- **Earlier reports read:**
  - `review/implementation/m0-tick-opus-5-5-b5c4f99.md`
  - `review/implementation/m0-tick-gpt-6-2-sol-b5c4f99.md`

## Files inspected

- **Coordinator:** `tools/tick_probe/src/tick_coordinator.gd`:
  - the new frame-history fields at `:95-96`
  - the reset of that history at `:223-224`
  - the tick commit path at `:395-433`
  - `get_tick_engine_frame` at `:620-624`
  - a grep of every place `tick_count` changes
- **Tests** under `tools/tick_probe/tests/`:
  - `callback_observer.gd`: all of it
  - `contract_driver.gd:71-136`: the ordering test and the alignment helpers
  - `run_frame_alignment_mutation.py`: all of it
  - `run_repeat_tests.py`: the diff
- **Probe README:** `tools/tick_probe/README.md`, all diff hunks, including `:292-353` and `:454-475`.
- **Evidence** in `evidence/2026-11-27-apple-m4-max-jolt-frame-alignment/`:
  - `README.md`, `corrections.md`, `provenance.json`, `manifest.sha256`, `compare-modes.txt`
  - all `mutation-*.txt` files
  - the contract, repeat, N1 and structural totals
  - `fake-checks-negative-control.txt` and `exit-code-selftest.txt`
- **Earlier evidence:**
  - phase-followup: the `errata.md`, `manifest.sha256` and `provenance.json` diffs, and the hash of its `README.md`
  - phase-alignment: the list of repeat files and the `repeat-post-*` totals

## Commands run (all read-only)

| Command | Result |
| --- | --- |
| `git merge-base --is-ancestor b5c4f99 da021e0` | The base is an ancestor of the candidate. |
| `git show --stat da021e0` and `git diff b5c4f99 da021e0` on the probe's `src`, `tests`, `README.md` and the phase-followup evidence | 46 files changed. The logic change touches only the coordinator's diagnostic frame history, the observer, the contract driver, the new mutation script and the repeat runner's default. |
| Hashed every file in `git ls-tree -r da021e0 -- :/tools/tick_probe` with `git hash-object` and compared it to the snapshot | 475 files, 0 differences. The snapshot matches the candidate. |
| `shasum -a 256 -c` on the frame-alignment manifest, from `tools/tick_probe` | 63/63 OK. |
| Python cross-check of `provenance.json` against the files and the manifest | 25 file hashes and 35 evidence hashes all match. Every evidence file except `manifest.sha256` itself is listed in the manifest. |
| `shasum -a 256 -c` on the phase-followup manifest | 5 entries fail: `README.md`, `tick_coordinator.gd`, `contract_driver.gd`, `run_repeat_tests.py` and `callback_observer.gd`. These are exactly the source files this slice changed, as `corrections.md` says. Every raw output and both corrected documents still verify. |
| `git diff --quiet b5c4f99 da021e0` on the phase-alignment directory | No changes, so that directory is preserved. |
| `shasum` on the phase-followup `README.md` | `03de7713…`, which matches the corrected provenance entry. |
| `grep` on the evidence outputs | See the evidence audit below. |
| Godot | **Not run.** This session ran in read-only plan mode, so I wrote nothing, not even to my scratch directory. I did not reproduce any runtime result myself. |

## Opus R1: the new frame check

**Resolved.**

### What the new code records

- **Coordinator:** in the same callback that commits a tick, after incrementing `tick_count`, the coordinator records `Engine.get_physics_frames()` (`tick_coordinator.gd:424,430`).
- **Observer:** each observer records the same counter beside every tick it sees while the tree is unpaused (`callback_observer.gd:23-24`).
- **Test:** `_observer_frames_align` (`contract_driver.gd:126-136`) requires that the observer's tick list and frame list are the same length. It then checks that each observed tick is at least 1, is still in the coordinator's frame history, and has a frame equal to the coordinator's frame for that same tick. The test applies this to both observers, the earlier one and the later one (`:109-114`).
- **Why this works:** Godot increments `Engine.get_physics_frames()` once per physics step, including catch-up steps. An observer that runs one physics iteration late therefore records a frame exactly 1 higher than the coordinator's, even though it still reads the tick sequence `1..12`.

### The frame history

- **Bounds:** the history holds at most `MAX_TICK_LOG` (20000) entries. `_tick_engine_frames_base = tick_count - size + 1` stays correct because `tick_count` changes in only two places: reset (`:205`) and the commit path (`:424`), and the commit path appends exactly one entry. Ticks outside the window return `-1`, which the test treats as a failure.
- **Reset:** `_reset_state` clears the history and resets the base (`:223-224`).
- **Kept out of trace digests:** the history is separate from `tick_log`. The structural trace digests and `compare_modes` show `max |diff| = 0`.

### The priority=0 mutation

`run_frame_alignment_mutation.py` makes two patches:
- It replaces `const PHYSICS_CALLBACK_PRIORITY := -1000` with `0`. The anchor must be unique, or the script stops with an error.
- It replaces the exact three-line numeric priority check with `_check(true, "…excluded by mutation")`, again with a uniqueness check. This keeps the total at 137 checks and leaves the sequence check, the callback-count check and both frame checks untouched.

The captured mutation runs (`mutation-frame-alignment-{fixed,default,max}.txt`) show the same pattern at each pacing:
- `TESTS_TOTAL=137 TESTS_FAILED=1`.
- The only failure is the earlier observer's frame check. For example, the fixed run shows observer frames `[420..431]` against coordinator frames `[419..430]`: off by exactly one iteration.
- These checks pass, three times each: the excluded placeholder, both `1..12` sequence checks, the "no phantom or extra publication iteration" count check, and the later observer's frame check.

This matches the misalignment I derived in the b5c4f99 review: the observer misses the arming iteration and reads tick 12 again in the publication iteration. The coordinator's independent fixed-pacing mutation run, which it reported to me, agrees.

The label is now "earlier-in-tree default-priority node", and the README (`:292-306`) no longer treats the numeric priority comparison as the behaviour that is being checked.

## Earlier follow-up items

| Item | Status | Basis |
| --- | --- | --- |
| Opus R2 / Sol #1: the idle and publication windows | **Resolved.** | `README.md:321-353` now describes both windows. One is the idle gap between the final tick's server step and the coordinator's next callback. The other is the publication iteration, which pausable nodes with lower or equal priority, ordered earlier, still see unpaused. It makes no blanket guarantee, and it tells M1 to gate on `is_publication_pending()` or an explicit episode phase. The old absolute sentence is recorded as superseded in `corrections.md` item 3, not rewritten. |
| Sol #2: the `FAKE_CHECKS` example | **Resolved.** | `README.md:78-81` uses `FAKE_CHECKS=137` with `--expect-checks 137`. `fake-checks-negative-control.txt` shows that the run reaches the reported-failure branch (`TESTS_TOTAL=137 TESTS_FAILED=1`, exit 1), not the count-mismatch branch. |
| Sol #3: the provenance README hash | **Resolved.** | The phase-followup `provenance.json` now records `03de7713…`, which matches the file. The two corrected manifest lines are documented in `corrections.md`. |
| Opus R4 / Sol #3: the errata repeat-file names | **Resolved.** | Item 1 now names `repeat-{fixed,default,max}.txt`, which are present. The `repeat-post-*` files in the phase-alignment directory do exist and record `REPEAT_TOTAL=54`, as the corrected text says. |
| Opus R3 / Sol #4: the repeat runner default | **Resolved.** | `run_repeat_tests.py` now defaults to 70, and its docstring says 70. |

## Evidence audit: worker claims checked against the hash-bound files

These checks show that the captured files, which hash correctly, contain these results. They do not show that I reproduced them.

- **Contract:** `TESTS_TOTAL=137 TESTS_FAILED=0` at fixed, default and max pacing. All six ordering checks pass.
- **Repeat:** `REPEAT_TOTAL=70 REPEAT_FAILED=0` at all three pacing modes.
- **N1:** `N1_TOTAL=76 N1_FAILED=0` at all three pacing modes.
- **Structural:** `CHECKS_TOTAL=108 CHECKS_FAILED=0` at all three pacing modes.
- **Compare modes:** `COMPARISON PASS`. The file has 12 PASS lines: 10 throughput and fidelity lines, plus 2 trace lines.
- **The three earlier mutations,** rerun against the new source with 70 checks:
  - immediate publish: 17 failures;
  - deferred refusal pause: 1 failure (`[1,2,3,3]`);
  - publication guard removed: 1 failure (`accepted=true`).
- **Exit-code self-test:** a structural run with 5 checks and 1 injected failure exits 1.

The coordinator also reported independent results to me: contract 137/137 at all three pacing modes, the fixed mutation, repeat fixed 70/70, and 63/63 manifest entries. I verified the manifest myself. The other runtime results agree with the captured files, but I did not reproduce them.

## Findings, most important first

### Production defects

None.

### Test and evidence gaps

**T1 (low): the mutation script can report a false success if a check label is renamed.**
- **Where:** `tests/run_frame_alignment_mutation.py:105-115`.
- **Problem:** the script decides the sequence and count checks passed only because no `FAIL` line contains their label substrings. If someone renames those labels, the script finds no matching failures and still reports `DEMONSTRATED=true`, even if those checks actually failed.
- **Effect today:** none. The captured files contain the expected `PASS` lines, three times each.
- **Fix:** also require the `PASS` lines for the two sequence checks and the count check, for example by requiring at least two sequence `PASS` lines and one count `PASS` line.

**T2 (nit): the evidence names the base commit as its candidate, not da021e0.**
- **Where:** evidence `README.md:16-17` and `provenance.json` `candidate_identity`.
- **Problem:** both describe the evidence as an "uncommitted correction slice" on top of `b5c4f99`. They do not name `da021e0`.
- **Effect:** none in practice. All 25 source hashes match the files in da021e0 exactly, so the evidence is bound to this candidate.
- **Fix:** record the commit ID once the coordinator commits.

**T3 (nit): the compare-modes count label is unclear.**
- **Where:** evidence `README.md:94`.
- **Problem:** "throughput (4) + trace (2) | 12 PASS" does not add up. The file has 10 throughput and fidelity PASS lines plus 2 trace lines. The "(4)" appears to count enforced throughput checks (`throughput_checks_enforced` in `provenance.json`), not PASS lines. The b5c4f99 evidence recorded 9+2.
- **Fix:** state what each number counts.

### Optional improvements

- **O1: narrow the frame history's visibility.** `tick_engine_frames` (`tick_coordinator.gd:95`) is a public, mutable array, but `get_tick_engine_frame()` is the only consumer it needs. Making the array private would follow AGENTS.md's default-private rule.
- **O2: avoid the shift at the cap.** `pop_front()` at 20000 entries shifts the whole array on every tick once the cap is reached. This repeats the existing `tick_log` pattern and costs little at this size. A ring buffer would avoid it if M1 keeps this diagnostic.

## Capability limits

- I executed no Godot code. I did not personally run the mutation or the positive suites. Everything about runtime behaviour comes from reading the code and from the hash-verified captured outputs.
- My explanation of the engine's ordering rests on Godot's documented physics-frame counter and its priority-then-tree-order dispatch. I did not read the engine source.
- All evidence comes from one host: Apple M4 Max, Godot 4.7.2 with Jolt, headless.
- Contact, `Area3D` and contact-manifold freshness at publication are still not checked, as the evidence README states.
- This recheck covers only the tick-probe correction. It gives no platform, audio, visual, gamepad or general contact sign-off, and no M0 or M0.8 acceptance sign-off.

**Verdict: pass.** T1 is worth a small follow-up. T2, T3, O1 and O2 are optional.