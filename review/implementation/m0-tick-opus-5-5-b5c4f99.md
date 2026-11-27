# Roadstorm M0.8 tick follow-up: Opus 5.5 scoped re-review of b5c4f99

**Verdict: pass.** This slice adds no new medium or major production defect.

The fixes for the earlier follow-ups are correct when I read the code. That covers the coordinator's callback priority, the deterministic mid-request injection, the `requested_ticks` check, the dynamic-change checks and the `_pending_publish` window. However, one of the new tests does not prove what it claims (R1). The `1..n` tick-sequence assertion would read the same if an observer ran one iteration out of step with the ticks. Only a check that compares the configured priority numbers guards the ordering fix. That is a test-validity and evidence gap, not a production defect. It should be fixed before M1 adds nodes with their own priorities.

## Review details

- **Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), through Anthropic's first-party CLI (Claude Code). I used no helpers, subagents or delegation, and I did not read the other current b5c4f99 review.
- **Date:** 2026-11-27.
- **Candidate:** `b5c4f99950bebc551849c1cc197db3b4c810b8c8`. **Base:** `8b7146b7ae81b326a638ab283c42bbbb91841e94`.
- **Snapshot:** `work/agents/coordinator/reviews/tick-b5c4f99/opus/source`. It sits inside the Roadstorm checkout, so the `git` commands below ran against that enclosing repository, read-only.
- **Historical reports read:**
  - `review/implementation/m0-tick-opus-5-5-8b7146b.md`
  - `review/implementation/m0-tick-gpt-6-2-sol-8b7146b.md`

## Files inspected

- **Coordinator:** `tools/tick_probe/src/tick_coordinator.gd`
  - lines 54-60, 123-126
  - lines 194-313: reset, `set_frozen`, `begin_step`
  - lines 322-430: `take_result`, `observe`, `_physics_process`
  - lines 563-615: `_finish_step`, `_emit_result`, `is_publication_pending`, `_emit_finished`
- **Tests** under `tools/tick_probe/tests/`:
  - `callback_observer.gd`, `motion_injector.gd`, `publication_probe.gd`, `physics_caller.gd`, `counting_body.gd`: all of each
  - `repeat_sequence_driver.gd`: all of it
  - `contract_driver.gd`: lines 71-125
  - `run_repeat_tests.py`, `run_contract_tests.py`, `run_n1_tests.py`: argument defaults and count reconciliation
- **Probe README:** `tools/tick_probe/README.md`, the diff hunks and lines 290-320.
- **Evidence** in `evidence/2026-11-27-apple-m4-max-jolt-phase-followup/`:
  - `README.md`, `errata.md`, `provenance.json`, `manifest.sha256`
  - all three `mutation-*.txt` files
  - the `contract-*` ordering lines and the totals in the contract, repeat and N1 outputs
- **Historical evidence:** the file listing of `…phase-alignment/` and the tail of its `repeat-post-fixed.txt`.

## Commands run (all read-only)

| Command | Result |
| --- | --- |
| `git diff --stat 8b7146b b5c4f99` and the code diff for `tools/tick_probe/{src,tests,README.md}` | The logic change is limited to the coordinator (+priority, +`is_publication_pending`, comments) and the tests. There are two new test nodes. |
| For every file in `git ls-tree b5c4f99 -- tools/tick_probe review/implementation`: `git show b5c4f99:<f> \| cmp - <snapshot>/<f>` | 500 files, 0 differences. The snapshot matches the candidate exactly. |
| `shasum -a 256 -c …/phase-followup/manifest.sha256`, from `tools/tick_probe` | 56/56 OK. The 24 source entries hash to the snapshot files, so the evidence is bound to b5c4f99's sources. |
| `grep` and `sed` on the evidence outputs | Contract 135/0 and repeat 70/0 at fixed, default and max pacing; N1 76/0 at all three. The four ordering labels pass 3×. Mutations: pubguard 1 failure (`accepted=true`), refusal-delay 1 failure (`[1,2,3,3]`), publish 17 failures. |
| `grep` for the runner `--expect-checks` defaults | `run_repeat_tests.py:42` still defaults to `54`. |
| Godot | **Not run.** The session was in read-only plan mode, so I wrote nothing, including to my scratch directory. All runtime results below come from the worker's and coordinator's claims and the hash-verified captured outputs, not from my own runs. |

## Ranked findings

### R1 — Medium, test validity and evidence overclaim (not a production defect): the `1..n` sequence assertion cannot detect the misalignment it is meant to catch

**Where:**
- `tests/contract_driver.gd:78-105`
- `tests/callback_observer.gd:11-17`
- `README.md:306-309`
- evidence `README.md` §1

`CallbackObserver` appends `coord.tick_count` on each unpaused callback. Consider a pausable observer that really executes *before* the coordinator, for example with the coordinator back at priority 0 and the observer at root index 0:

- **Arming iteration:** the tree is still paused when the observer is visited, so it is skipped. The coordinator then unpauses and runs L1.
- **Iterations L2..L12:** the observer runs before the coordinator and records `tick_count` = 1..11, the previous tick.
- **Publication iteration:** the tree is still unpaused, because the coordinator pauses only in its own callback (`tick_coordinator.gd:372-374`). The observer records 12.

The result is `tick_sequence == [1..12]` and `unpaused_physics_callbacks == 12`. That is identical to a correctly ordered observer.

So these checks would pass with the priority fix removed:
- "node before the coordinator sees consecutive ticks 1..12";
- "no phantom or extra publication iteration reached either observer".

Even though that observer misses L1's iteration and runs during the publication iteration, which has no tick. The only check that would fail is the configuration comparison `coord.process_physics_priority < before.process_physics_priority` (line 90).

**On whether priority is the right property:**
- The priority comparison is a valid proxy *for this scene*, because Godot orders physics callbacks by priority, then by tree order.
- It is not the behaviour that matters. That behaviour is: in each physics iteration, the observer runs after the coordinator's tick k and before tick k's server step, and it never runs in the arming or publication iterations.
- The test label "node before the coordinator" now describes only tree position. After the fix, that node runs *after* the coordinator.
- No mutation demonstrates that a behavioural check catches the misalignment. The three mutations cover publish, refusal delay and the publication guard.

**Basis:** code reading plus the per-node pause behaviour measured at b56d902 and cited in my 8b7146b report. I did not measure this at b5c4f99.

**Fix**, with each check made discriminating:
1. Have the observer record `Engine.get_physics_frames()`, have the coordinator log the physics frame of each tick, and assert they match. Alternatively, assert the observer never sees `coord.is_publication_pending()` or an armed-but-unexecuted request while the tree is unpaused.
2. Add a mutation with `PHYSICS_CALLBACK_PRIORITY = 0` and the configuration check excluded, and show the behavioural checks fail.
3. Rename the label to "earlier-in-tree default-priority node".

### R2 — Low, documentation overclaim: "pausable nodes never observe an unpaused step without a logical tick"

**Where:** `README.md:312-314` and evidence `README.md:33-35`.

The sentence is absolute, but it holds only for nodes the coordinator outranks. The paragraph just before it correctly says nodes with a lower priority (or the same priority, ordered earlier in the tree) still run first. Any such pausable node does run unpaused in the publication iteration, as the derivation in R1 shows. The committed `publication_probe.gd` at -2000 is an ALWAYS node, but it shows such nodes exist in practice.

Separately, during a request under default and max pacing, idle `_process` passes do not line up one-for-one with ticks: a frame can contain 0 or 2 physics iterations, and pausable `_process` sees wall-clock deltas. This is inherent and not new. I am not claiming the sentence says otherwise, but the M1 contract should state it.

**Fix:** qualify the sentence with "pausable nodes the coordinator outranks", and state the idle-pass pacing caveat.

### R3 — Low, stale runner default

`tests/run_repeat_tests.py:42` (`default=54`) and its docstring at `:9` were not updated to 70.

If the runner is invoked without `--expect-checks`, it now fails closed with `expected 54 checks, got 70`. That is safe but misleading.

The evidence README's "Runner gaps" bullet says `--expect-checks` defaults to 0. That is true for the contract and N1 runners, not for the repeat runner.

### R4 — Nit, errata path

`errata.md:10-11` says "the new `repeat-pre-*.txt` / `repeat-post-*.txt` in this directory supersede them". The follow-up directory contains only `repeat-{fixed,default,max}.txt`. The successful `repeat-post-*` runs (54/54) are in the *phase-alignment* directory, the same place item 2 says the `repeat-pre-*` runs crashed.

## Prior follow-ups: disposition

| Prior item | Disposition | Basis |
| --- | --- | --- |
| Opus F1: earlier-ordered nodes one iteration out of step; unpaused window | **Production: resolved for default-priority nodes.** At `-1000`, the coordinator runs first in the arming iteration (unpause, then L1) and in the publication iteration (pause), so default-priority pausable observers see exactly L1..Ln. **Test: weak** (R1). **Docs:** mostly accurate, one overclaim (R2). | Code reading: `tick_coordinator.gd:126,372-389`. |
| Opus F2: `_pending_publish` overlap, take and reset untested | **Resolved.** `publication_probe.gd` (-2000, ALWAYS) runs in the publication iteration before the coordinator and makes three calls. | See the breakdown below this table. |
| Opus F3: stale comments, README overclaim, failed old launches | **Resolved.** Coordinator comments `:57-60,606-609` and contract comments are updated. README `:290-295` now matches the new checks. The errata records the failed launches without rewriting raw files, apart from the R4 path slip. | Diff and file reads. |
| Opus F4 / Sol #1: mid-request injector flakiness | **Resolved.** `motion_injector.gd` is a pausable, default-priority physics node, so it runs after the coordinator in the L3 iteration, even under catch-up. The L4 coordinator callback then refuses synchronously. `requested_ticks == 12` is now asserted. The refusal-delay mutation still yields `[1,2,3,3]`, 1 failure. | Code reading plus the captured mutation. |
| Sol #2: misleading old evidence | **Resolved,** apart from R4. | `errata.md` |
| Sol #2: `requested_ticks` and dynamic-change assertions | **Resolved.** `repeat_sequence_driver.gd:134-139,180-181,201-207` checks returned `requested_ticks`. It also checks that y strictly decreases and velocity becomes more negative across every request and the one-tick terminal. The immediate-publish mutation makes the terminal dynamic-change checks fail (`dy=0 dv=0`). | Code reading plus the captured mutation. |
| `FAKE_CHECKS` and N1 example counts | **Resolved.** The README uses `FAKE_CHECKS=133` with `--expect-checks 135`; `run_n1_tests.py:11` uses 76. Only R3 remains. | Diff. |

**Detail for Opus F2.** The probe makes three calls and the test checks each:
- **`begin_step(12)`:** this is refused only by `_pending_publish`. All other guards are clear at that point: `_completion_callbacks=0`, `_pending_result=false`, `_budget=0`, and the episode is not terminal. The pubguard mutation flips this check to `accepted=true`.
- **`take_result()`:** returns `{}`, because `_pending_result` is still false.
- **`reset()`:** clears `_pending_publish` and freezes the tree. The coordinator's callback then returns early: no flag is set and `_budget` is 0. The suppressed server step, the zero `step_finished` count and `tick_count==0` are all asserted. The count of 70 reconciles as 54 + 3 + 3 + 4 + 6.

**Integrity:**
- The manifest binds the current source.
- The provenance lists the changed and new files correctly.
- The evidence README says the coordinator corrected the priority assertion after capture and reran it. The captured PASS lines carry no values, so byte-identical stdout is consistent with that.

## Claims I am relaying, not reproducing

These are other people's claims. I verified only that the files hash correctly and that their contents agree with the claims:
- the coordinator's own reruns of the contract suite (135/135 at each pacing, bytes identical to the captured runs);
- the worker's results: repeat 70/70, N1 76/76, structural 108/108 per pacing, compare 9+2 PASS, and the exit-code self-test;
- the three mutations each exiting 1.

## Capability limits

- I executed no Godot code, and I did not run the R1 mutation that would confirm that finding empirically.
- Pause and priority dispatch semantics are inferred from earlier traces and Godot's documented ordering, not from reading the engine source.
- Evidence comes from one host: Apple M4 Max, Godot 4.7.2 with Jolt, headless.
- Contact, `Area3D` and manifold freshness at publication remain ungated, as the evidence README admits.
- This review gives no platform, visual, audio, gamepad or general contact sign-off, and no M0 or M0.8 acceptance sign-off.

**Verdict: pass.** R1 should be fixed before M1. R2–R4 are optional cleanup.
