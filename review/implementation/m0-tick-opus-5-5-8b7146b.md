# M0.8 tick probe: independent Opus 5.5 re-review of 8b7146b

**Verdict: pass.** All six b56d902 blockers you listed are closed. The proof for each is listed under "Blocker closure" below.

I found one new issue that matters before M1. When a request finishes, the tree now stays unpaused for one extra engine iteration so the final tick can integrate. Nodes ordered *before* the coordinator therefore run out of step with the logical ticks. The README and one contract-test label say the opposite (F1). This does not change any step count, so I did not make it a blocker. It is a cheap doc, test and priority fix and should land before M1 places motor or bridge nodes.

## Review details

- **Date:** 2026-11-27.
- **Reviewer route:** Claude Opus 5.5 (`claude-opus-5-5`, Anthropic). I worked directly in a native Claude Code session with no helpers or subagents. I did not consult the other current reviewer or read any current recheck report.
- **Candidate:** `8b7146b7ae81b326a638ab283c42bbbb91841e94`. **Base:** `b56d9028e4a448688b6120ff99da177f44acfdff`.
- **Snapshot:** `work/agents/coordinator/reviews/tick-8b7146b/opus/source`, a non-git export inside the Roadstorm repository.
- **Background reading:**
  - my own `review/implementation/m0-tick-opus-5-5-b56d902.md`;
  - the prior Sol report `m0-tick-gpt-6-2-sol-b56d902.md`, read only as background.

## Files inspected

- **Plan and design:**
  - `PLAN.md:63`
  - `docs/TECHNICAL_DESIGN.md:49,63-69,147`
  - `docs/OPPONENT_AI.md:76,92`
- **Coordinator:** `tools/tick_probe/src/tick_coordinator.gd`, all of it.
- **Tests:**
  - `tests/repeat_sequence_driver.gd`, all
  - `tests/run_repeat_tests.py`, all
  - `tests/contract_driver.gd:55-253` and the frame-account hunk
  - `tests/counting_body.gd`
  - `tests/physics_caller.gd`
  - `tests/callback_observer.gd`
  - `run_n1_tests.py:11,47` and `run_contract_tests.py:48`
- **Probe README:** `tools/tick_probe/README.md:66-80,150-312,560-575`.
- **Evidence** in `evidence/2026-11-27-apple-m4-max-jolt-phase-alignment/`:
  - `README.md`, `provenance.json`
  - `phase-iter-{pre,post}.txt`, `compare-modes.txt`
  - `mutation-{publish,refusaldelay}.txt`
  - `repeat-pre-fixed.txt`, `repeat-post-max.txt`

## Commands run (all read-only)

| Command | Result |
| --- | --- |
| `git diff --stat b56d902 8b7146b` and the code diff for the coordinator, contract driver, counting body, physics caller and `compare_modes.py` | 69 files changed. Logic changes are confined to the coordinator and the tests. |
| For each tick-probe source, test, README and `compare_modes.py` file: `git show 8b7146b:<f> \| cmp - <snapshot>/<f>` | No differences. The snapshot matches the commit. |
| `shasum -a 256 -c evidence/…phase-alignment/manifest.sha256`, run from `tools/tick_probe` | 57/57 OK, 0 failures. The manifest's 21 source entries are snapshot files, so the evidence is bound to 8b7146b. |
| `grep` for `_pending_publish`, `awaiting publication`, `ITERS` and `process_physics_priority` in `src`, `tests` and the READMEs | The guard is not tested (F2). The phase-iteration trace driver is not committed. The coordinator sets no priority. |
| Godot | **Not run.** The session was in read-only plan mode, and the private verified editor is outside the snapshot. The coordinator's runs (repeat 54/54, contract 133/133, N1 76/76 at fixed, default and max pacing) are reported here as its claims, not reproduced by me. |

## Blocker closure

Each item below says whether it rests on a measurement (captured evidence), a code reading, or nothing yet.

| Blocker from b56d902 | Status | Basis |
| --- | --- | --- |
| Each tick gets its own `PhysicsServer3D.step`, including the final tick | **Closed** | **Measurement.** `phase-iter-post.txt` shows integrations `[…,1..12]`, against `[…0,1..11]` before the fix. The hard gate checks the integration list equals `range_start..end_tick` (`repeat_sequence_driver.gd:127`). The immediate-publish mutation produces 10 failures. **Code reading:** activation is armed and runs only in the coordinator's next callback (`tick_coordinator.gd:311,385-390`), with no `call_deferred` and no synchronous unpause. |
| Final publication sees server-owned state | **Closed for transform and velocity** | **Measurement:** the publication iteration (pf=21, `steps 16`) shows L12's integration. **Code reading:** publication happens in the next callback after the engine's sync step (`:371-383`). **Limit:** the equality check `state_y == body_y` (`repeat_sequence_driver.gd:130`) is close to tautological, because both values come from the same sync. The real proof is the integration-tick list plus the step count. Contact, Area and `_integrate_forces`-driven contact state is **untested**, as the evidence README admits. |
| Mid-request refusal gives k steps | **Closed** | **Measurement:** `motion-bound-mid` passes with `[1,2,3]`. The deferred-pause mutation produces `[1,2,3,3]` and fails. **Code reading:** `_finish_step("motion_bound", false)` pauses in the refusing callback (`:407,413,584`). |
| Committed same-world 12+12+1 hard gate for idle, callback and mixed origins | **Closed** | **Measurement:** the 54 checks are 3 sequences × 3 requests × 5 checks, plus 3 frozen-wait, 3 mid-request and 3 terminal checks. Each request checks elapsed ticks, the step-to-tick pairing, freshness, the freeze and exact kinematic progress (`:123-138`). The runner fails closed and pins the check count. |
| Zero-tick request on a live over-envelope episode | **Closed** | **Code reading:** the zero-tick branch now runs before the envelope check (`:282-291`). **Measurement:** `contract_driver.gd:191-216` passes, including the check that a later positive request is still refused. |
| Evidence and operator docs consistent | **Mostly closed** | Realtime is 0.912 in both `compare-modes.txt:14` and the evidence README. README command counts are 133, 76 and 54. Remaining stale text is listed in F3. |
| Overlap guard on `_pending_publish`, reset and reentry | **Correct by code reading, untested** | See F2. |

## Findings, most important first

### F1 — Medium, M1 integration contract and test label: nodes before the coordinator are one iteration out of step, and the tree is unpaused for a window with no tick

`tick_coordinator.gd:385-388` and `:577-581`; `README.md:284-288`; `contract_driver.gd:74-76,87-89`.

Godot checks the pause state node by node as it walks the tree. b56d902's own measurement showed this: the later-ordered node got 11 callbacks when the tree paused partway through an iteration. Under that rule the new code behaves as follows.

- **In the arming iteration:**
  - The tree is still paused when an earlier-ordered pausable node is visited, so that node skips the L1 iteration.
- **In the publication iteration:**
  - The tree is still unpaused when the same node is visited, so it runs in an iteration that has no logical tick.
  - That iteration's server step is suppressed.
  - Anything the node changes ends up in the published observation.
  - Its count is still 12 (L2..L12 plus the publication iteration), so `before.physics_callbacks == 12` passes even though the node never sees L1.
- **Between the final tick's iteration and the publication iteration:**
  - One idle `_process` pass runs while the tree is unpaused.
  - Pausable timers, tweens and animations can advance there. Under default or max pacing they advance by a wall-clock delta.

**Regression:** at b56d902, earlier-ordered nodes lined up with L1..L12, as Sol's report records.

**What the README says:** "During the n tick iterations, nodes ordered before and after the coordinator receive all n callbacks." That is true of the count but false of the alignment. `TECHNICAL_DESIGN.md:49,65` require that only the coordinator advances simulation state, so the probe's counts are unaffected. However, M1 has nothing enforcing this.

**Basis:** code reading plus the b56d902 measurement of the same mechanism. Not measured on 8b7146b.

**Fix:**
1. Give the coordinator the lowest `process_physics_priority` so it always runs first, or document that only the coordinator and later-ordered nodes are aligned with ticks.
2. Have `CallbackObserver` record `coord.tick_count` on each unpaused callback, and assert the before-node and after-node sequences.
3. Correct the README and the test docstring.
4. State the unpaused idle window in the M1 contract.

### F2 — Low, untested: the new overlap guard and resets during the publication window

`tick_coordinator.gd:263-264,225-226`.

By code reading these paths behave correctly:
- A `begin_step` during the window is refused.
- `take_result` returns `{}`.
- `reset()` or `configure()` from idle clears `_pending_publish` and freezes the tree.
- A reset from a later-ordered node in the final iteration pauses the tree and drops the final step. That is acceptable because the reset discards the request anyway.
- Reentrant calls from `step_accounted` or `step_finished` are still refused by `_completion_callbacks`.

However, no test exercises any of these paths. My grep for `awaiting publication` found nothing.

**Fix:** add three checks, each run from inside the window:
- a refused `begin_step`;
- an empty `take_result`;
- a reset, followed by zero further steps and no `step_finished`.

### F3 — Low, documentation and evidence consistency

- **Stale comments:**
  - `tick_coordinator.gd:57-60` still describes publishing synchronously in the final callback.
  - `tick_coordinator.gd:598-600` still says dynamic state "may flush one iteration later".
  - `contract_driver.gd:74-76` says "pauses in the final tick's own callback, so no extra pause iteration".
  - `contract_driver.gd:97-99` mentions a "deferred unpause".
- **Overclaim:** `README.md:293-294` says the gate asserts "a changing dynamic value" for the one-tick terminal case. `repeat_sequence_driver.gd:187` checks only equality.
- **Pre-fix evidence is incomplete:** the evidence README presents `repeat-pre-*.txt` as the old repeated-sequence runs, but they crash with `SCRIPT ERROR` at `repeat_sequence_driver.gd:90` (the old `physics_caller` has no `requested_ticks`). Only 27 of 54 checks ran, so the callback-origin sequence was never measured before the fix.
- **Uncommitted trace drivers:** the drivers behind `phase-{pre,post}` and `phase-iter-{pre,post}` are not committed. This is acceptable as supplementary evidence now that the hard gate is committed.
- **Leftover stale counts:**
  - `README.md:568` ("76 to 77")
  - `run_n1_tests.py:11` (`--expect-checks 61`)
- **Runner defaults:** the contract and N1 runners still default `--expect-checks` to 0 and do not reconcile `checks_failed` with `len(failures)`. The evidence README admits this.

### F4 — Nit, test robustness: possible flake in the mid-request test

`repeat_sequence_driver.gd:157-162` polls `tick_count < 3` once per process frame and hard-codes `[1,2,3]`. If one frame delivers two physics iterations, tick 4 runs before the speed changes. It passed at all three pacings, but it could flake under host load. Change the speed from a `step_accounted`-style hook or a physics-ordered node instead.

### F5 — Nit, dead or redundant code

- The `_result` passed to `step_accounted` is the same dictionary object whose `observation` is later overwritten at `:381`, so an observer that keeps a reference sees it change.
- `observe()` runs twice, at `:381` and `:601`.
- The flush ray at `:376-380` has no demonstrated effect. The pf=21 trace shows state already synced before the callback. It is harmless.

## Prior findings (my b56d902 report)

| Prior finding | Disposition |
| --- | --- |
| F1: mechanism contradicted the docs | **Resolved.** The mechanism was replaced, and the README section on server steps (`:187-199`) matches the measurements. Stale comments remain (F3). |
| F2: mid-request refusal ran k+1 steps | **Resolved.** Measured, and caught by a mutation. |
| F3: callback and mixed origins not hard-gated; trace driver uncommitted | **Resolved.** Committed 12+12+1 gate for idle, callback and mixed origins, with mutations. |
| F4: tautological pose check | **Resolved** by the exact progress check (`repeat_sequence_driver.gd:135-138`). The dynamic-state check is still weak; see the table above. |
| F5: nits | **Partly resolved.** Realtime figures reconciled, duplicate `return` removed, and README `:279` fixed. Still open: the runner defaults, the `61` and `77` counts, and `warm_step_probe_driver.gd:9,99` still calling its checks "informational". |

Sol's prior F1–F4 are covered by the same items. Its F3, the zero-tick envelope check, is resolved and tested.

## Capability limits

- I ran no Godot code. Behaviour claims come from code reading plus the hash-verified committed outputs, and the coordinator's reported results are relayed, not reproduced.
- Godot and Jolt internals are inferred from traces, not engine source. These include when `_integrate_forces` runs relative to the sync step, and per-node pause checks within an iteration.
- Evidence comes from one host: Apple M4 Max, Godot 4.7.2 with Jolt, headless.
- Contact and Area visibility at publication and multi-car behaviour are untested.
- This review gives no platform, controller, audio, rendering or M0-acceptance approval.

**Verdict: pass**
