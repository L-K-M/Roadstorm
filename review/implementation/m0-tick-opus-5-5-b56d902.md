# M0.8 tick probe — independent Opus 5.5 checkpoint review of b56d902

- **Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, native Claude Code session. No helpers, no subagents. I did not read any other review of this candidate.
- **Candidate:** `b56d9028e4a448688b6120ff99da177f44acfdff` ("Make repeated training tick requests exact on a warmed world").
- **Base:** `12958922d34f1a7a89675a4e89381f2c298caba4`.
- **Snapshot:** `work/agents/coordinator/reviews/tick-b56d902/opus/source` (git-archive export). I confirmed it is byte-identical to `b56d902` for `tick_coordinator.gd`, `contract_driver.gd` and `n1_regression_driver.gd`.
- **Verdict: changes required (narrow).** The per-request counts are exact, and the evidence is hash-consistent with the candidate. However:
  - the documented server-step mechanism contradicts the candidate's own measurements (F1);
  - one terminal path probably leaks a server step (F2);
  - repeated requests from physics callbacks have no committed hard gate (F3).

  None of these blocks the kinematic-car counts. F1 must be fixed before M1 writes its integration contract against the README.

## Inspected paths

- **Plan and design docs:**
  - `PLAN.md:63`
  - `docs/TECHNICAL_DESIGN.md:49,63-69,87`
  - `docs/OPPONENT_AI.md:76,92`
- **Probe docs and source:**
  - `tools/tick_probe/README.md` (full)
  - `src/tick_coordinator.gd` (full)
  - `src/probe_driver.gd:465-501`
- **Tests:**
  - `tests/contract_driver.gd:1-330`
  - `tests/n1_regression_driver.gd` (full)
  - `tests/warm_step_probe_driver.gd`
  - `tests/counting_body.gd`
  - `tests/physics_caller.gd`
  - the runner headers
- **Evidence** in `evidence/2026-11-27-apple-m4-max-jolt-repeated-boundary/`:
  - README, provenance and manifest
  - `repeat-pre/post-*`, `mutation-settle-removed.txt`, `n1-{fixed,max}.txt`, `contract-max/contract-tests.txt` and `compare-modes.txt`
- **Prior reports:**
  - `review/implementation/m0-tick-opus-5-5-1295892.md`
  - `review/implementation/m0-tick-gpt-6-2-sol-1295892.md`

## Commands run

| Command | Outcome |
| --- | --- |
| `git diff --stat 1295892 b56d902 -- tools/tick_probe/{src,tests,compare_modes.py,README.md}` | 11 files. `pause_enforcer.gd` removed; coordinator, tests and the new warm-step driver changed. |
| `diff <(git show b56d902:…) snapshot/…` for the three core files | Identical. |
| `shasum -a 256 -c evidence/…repeated-boundary/manifest.sha256` (from `tools/tick_probe`) | All 51 entries OK, so the source hashes equal the committed candidate files. |
| `godot --version` | `4.7.2.stable.official.ed1daf0bf` is present at `/opt/homebrew/bin/godot`. |
| Contract, N1, structural and compare_modes runs | **Not run.** This session was in read-only plan mode, and running Godot writes `.godot` caches and temp output. Every behavioural conclusion below is static, or derived from the candidate's committed outputs. |

## Findings (ranked)

### F1 — Medium, implementation contract and documentation: the server step paired with a request runs *before* tick 1, not after tick n

**Where the wrong mechanism is stated:**

- Code comments: `src/tick_coordinator.gd:57-60`, `:300-311`, `:381-386` and `:566-569`.
- README: `README.md:184-187`, `:270-279` and `:374-381`.

They say the following, none of which matches the measurements:

- "pausing here stops the *next* iteration's server step; this iteration's step is the final accounted tick's step";
- the settle iteration is "fully paused";
- "Idle-time calls keep immediate unpause".

**What the committed data shows:**

1. **`n1-fixed.txt` and `n1-max.txt`, `warmed_single_1`.** `emission_steps=5` from a warm count of 4. That is, one counted integration already exists at `step_finished`, which is emitted inside the tick-1 callback (`:573-579`). That step therefore ran in the settle iteration, before any tick logic.
   - Mechanism: the `call_deferred` activation (`:385`) is flushed before that iteration's server step. The settle iteration is not fully paused.
2. **`mutation-settle-removed.txt:105,111`.** With idle unpause and no settle iteration, same-world requests 2 and 3 count 11 and 0. That is only consistent with the final-tick pause (`:578`) suppressing *its own* iteration's step. Under the README's model the results would be 12 and 1.

**Actual per-request order:**

- Steps run in this order: [step integrating the previous tick's state], L1, S, …, L(n−1), S, Ln, then pause.
- The count is exactly n, and continuous same-world interleaving is preserved.
- The effects of the final tick's commands on server-stepped state are integrated only in the *next* request's settle iteration.
  - They are never integrated on terminal or truncated episodes, or after reset.
- The first request after reset begins with one zero-logic server step.

**Impact:**

- Kinematic cars move by `move_and_collide` and commit inside the callback, so the observed car pose is correct. That is the design (`TECHNICAL_DESIGN.md:69`).
- Any M1 or bridge code that relies on Jolt-stepped state would see a one-tick lag in the published observation: RigidBody props, Area overlaps, and contacts reported by `_integrate_forces`.
- The README tells it the opposite.

**Fix:**

1. Correct the comments and README to describe the measured order.
2. State the lag and the "last tick never integrated at terminal/reset" rule as part of the M1 integration contract.
3. Optionally, add a test that applies an impulse at Ln and asserts it is not visible at publication but is visible after the next request's first server step.

### F2 — Low–Medium, plausible implementation defect, untested: a mid-request `motion_bound` refusal runs k+1 server steps for k elapsed ticks

`src/tick_coordinator.gd:400-404` and `:406-410`. The test is `src/probe_driver.gd:471-489`.

- The refusal fires in callback k+1, in which no tick is accounted.
- Under the order measured in F1, the steps that ran are the settle step plus the steps after L1…Lk, which is k+1. Elapsed is k.
- If speed changes between `begin_step` and tick 1, the result is 1 step for 0 ticks.
- The pre-`begin_step` refusal is correctly 0 (`:277-288`, tested warmed at `contract_driver.gd:189-211`).
- The mid-request test counts no server steps, so it cannot see this.

**Fix:**

1. Add a warmed counting body to the mid-request test.
2. Then do one of the following:
   - evaluate the next tick's envelope at the end of tick k and finish in that callback; or
   - document this error-path step explicitly. `motion_bound` is an environment-error class per `OPPONENT_AI.md:92`.

Static inference only. Not executed.

### F3 — Low, missing evidence: same-world repeated requests from physics callbacks are not hard-gated, and the trace driver is not committed

**What is hard-gated:**

- `contract_driver.gd:147-185` and `n1_regression_driver.gd:209-246` cover only *idle-origin* 12+12+1.
- `contract_driver.gd:99-141` covers only a *single* physics-caller request.

**What is not:**

- Physics-callback and mixed-origin repetition appear only in `repeat-pre-*` and `repeat-post-*` (`SEQ caller_caller` and `idle_caller` lines).
  - These cover 12+12 only, with no +1.
- No committed file emits `SEQ` lines (`grep -rn "SEQ " tests src` finds nothing), so those traces cannot be reproduced from `b56d902`.

**Fix:**

1. Commit that driver, or extend `_same_world_sequence` with physics-caller and mixed-origin 12+12+1 variants.
2. Add a mutation run that each of the new variants catches.

### F4 — Low, test strength: "final observation is the committed body pose" is close to tautological

`contract_driver.gd:179-183`.

- It compares the observation, built from `body.global_position` at emission, with the same paused kinematic body after `take_result`. Nothing can move between the two reads.
- It does not check that the pose equals the expected n-tick displacement, nor anything about the dynamic body's observed state.
- Add an expected-progress check, `-z == speed*DT*tick_count` within tolerance, and see F1 for the dynamic-state check.

### F5 — Nit, documentation and evidence consistency

- **`README.md:279`:** "Idle-time calls keep immediate unpause" contradicts `:307-312`.
- **Expected check counts disagree:**
  - `README.md:552-554` claims the N1 example count was updated to 77, but `:77` says 76 and the evidence shows 76.
  - The `run_n1_tests.py:11` usage still says 61.
- **Realtime figures disagree:**
  - The evidence README gives "10.966 s, 0.912×".
  - The committed `compare-modes.txt` gives 10.881 s, 0.919×.
- **The evidence README overstates the mutation result.** It says the mutation "fails exactly the repeated-request checks". The run actually has 7 failures: 4 frame-account, 2 repeat-same-world and 1 pause-ownership.
- **`warm_step_probe_driver.gd:8,99`** still labels immediate repeat as informational and ungated.
- **`tick_coordinator.gd:313-314`:** duplicated `return true`, which is dead code.
- **Prior F6 is still open:** the runners default to `--expect-checks 0` and do not reconcile `checks_failed` with `len(failures)`.

## Assessment of the focus areas

| Area | Status |
| --- | --- |
| Exact n steps, 12+12+1 same world, idle origin | **Shown.** Hard-gated, with exact `n1` and contract outputs at all three pacings and a mutation that fails. |
| Exact n steps, physics-callback origin | Single request gated. Repetition evidence only (F3). |
| Final committed observation | Kinematic pose correct. Dynamic state lags one tick (F1). Test is weak (F4). |
| Frozen wait | Shown. Zero steps over 30 frames (`n1_regression_driver.gd:45-55`), and the independent-body wait guards pass. |
| Reset | Clears the budget and the settle and deferred flags (`:217-226`). A stale deferred activation is guarded by `_budget > 0` (`:321`). `configure()` now ends frozen (`:154`), which closes prior F5. |
| Terminal and truncated | Finish in the ending tick's callback, so steps equal elapsed. Exception: mid-request `motion_bound` (F2). |
| One committed movement plus swept query | One `move_and_collide` per substep of at most 0.25 m. The margin-0 `cast_motion` predictor and `test_move` diagnostic are unchanged. Trace digests match across pacings with max diff 0. |
| Throughput and cost | Honest n+1 engine frames per request. The realtime ceiling is 0.923× and 0.919× was measured. Accelerated runs at 59×. The settle iteration is not a wasted server step: it is one of the n steps. |
| Prior Opus findings F1–F3 (1295892) | F1: a physics-callback request now integrates 12, not 13. F2: exact `pf_delta == n+1` gates are restored. F3: the motion-bound refusal is warmed. All three are resolved by tests. |

## Open limits

- I executed nothing in Godot. Behavioural claims rest on code reading and the candidate's hash-verified outputs.
- The evidence comes from one host (Apple M4 Max, macOS, Godot 4.7.2/Jolt), headless with dummy drivers.
- This review does not approve or imply results for other platforms, rendering, audio, controllers or hardware, or M0 acceptance.
- Godot and Jolt internals (when deferred calls flush versus the server step, and when `_integrate_forces` runs) are inferred from the measurements, not from engine source.
