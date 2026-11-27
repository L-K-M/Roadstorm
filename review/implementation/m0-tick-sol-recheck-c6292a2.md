# M0.8 independent cold-start and tick-contract recheck

**Verdict — changes required.** The ordinary path now integrates one physics-server step per requested logical tick, including a cold first request. A synchronous accounting listener can still reenter the coordinator or reset it and receive a stale result. The contract runner also trusts a successful child exit over an explicit failed assertion in its output.

| Item | Scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `c6292a2661b48d7f090225bd531427967b404359`, committed 2026-11-27 06:04:19 +01:00 |
| Base | `bdb0a9820b847d23628cce35a9070bb63ae17acd` |
| Review date | 2026-11-27, Europe/Zurich |
| Scope | `tools/tick_probe/**`, historical bdb0a98 Sol findings, the N1 server-step finding, and the M0.8 contract. |

## Ranked findings

1. **Medium · The synchronous accounting signal exposes a reentrant completion window.** In `_finish_step()`, `_budget` is cleared and `step_accounted` emits before `_emit_scheduled` or the pending result flag is set. My separate headless listener called `begin_step(2)` inside completion of a one-tick request, and the coordinator returned true. A second listener called `reset()` inside the accounting callback, yielding tick 0, but the coordinator subsequently published the old tick-1 result even though its live tick count remained 0. Register completion state before dispatching observers. Explicitly preserve a reset's cancellation of unpublished results across synchronous callbacks, and test both listener-driven reentry and reset. [Request refusal](../../tools/tick_probe/src/tick_coordinator.gd#L240) · [Completion ordering](../../tools/tick_probe/src/tick_coordinator.gd#L511)
2. **Low · Runner trusts child exit status over failed assertions in a valid report.** My synthetic Godot command exited 0 and emitted a valid matching 77-check report with `checks_failed: 1` and a matching text total. The contract runner printed the failure count and exited 0. Fail if the reported failed count is nonzero or the runner cannot reconcile the summaries, even when the child returned 0. The actual candidate engine correctly caused exit 1 when I requested a wrong expected total of 76. [Contract runner](../../tools/tick_probe/tests/run_contract_tests.py#L106)

## Verified repairs and evidence

- The 77-test contract suite passes at fixed, default and max pacing. It checks accounting at the logical completion boundary, later frozen callbacks, negative request refusal even after termination, zero-tick publication while already frozen, and reset observation at a zero cap.
- The separate fresh-body regression passes 14 checks. Its counted body integrates 1 or 12 times on first requests of those lengths and 12 times on subsequent twelve-tick requests. A continuous cold control integrates zero times across one physics callback and 11 times across 12 callbacks. A frozen wait integrates zero and moves no body. This distinguishes request behavior from cold registration latency.
- The 108-check structural suite and 600-tick throughput plus intermediate trace comparisons pass. Those cover the supported probe scenarios, bounded movement refusal, termination/truncation, replay, and same-host simulated state across pacing modes. I reviewed the recorded mutation evidence and did not patch candidate source to repeat it.
- The historical manifest references the probe README at `8a5615c`. I verified that README's SHA-256 agrees with the recorded entry and that the README is the only change under `tools/tick_probe/` from 8a5615c to c6292a2. The live commands here ran on the exact c6292a2 export, including the corrected expected count.

## Commands and artifacts

I confirmed the destination was ignored and exported `git archive c6292a2` into `work/agents/sol-tick-3-20261127/snapshot/`. Runs used separate project copies with private homes, temporary dirs, and bounded subprocess waits. Full logs and the scratch runner controls remain in the parent directory. Godot reported `4.7.2.stable.official.ed1daf0bf`.

| Command | Result |
| --- | --- |
| `python3 <private project>/tests/run_contract_tests.py --pacing <fixed/default/max> --expect-checks 77 --timeout 25` | Exit 0 and 77/77 for each pacing mode. Logs in `contract-*/run.log`. |
| `godot --headless --fixed-fps 60 --path <private project> --script res://tests/n1_regression_entry.gd` | Exit 0 and 14/14. Log in `n1/run.log`. |
| `godot --headless --fixed-fps 60 --path <private project> --script res://src/tick_probe.gd -- mode=structural pacing=fixed` | Exit 0, 108/108. Log in `structure/run.log`. |
| `python3 <private project>/compare_modes.py --timeout 25 --expect-throughput-checks 4 --expect-trace-checks 2` | Exit 0. Throughput and cross-pacing trace checks pass. Log in `comparison/run.log`. |
| Headless `res://edge_review.gd` in the scratch project | Reproduces finding 1. Code is `edge/project/edge_review.gd`; output is `edge/reentrant.log`. |
| Contract runner with `--godot <scratch>/edge/fake-godot --expect-checks 77`, and actual engine with `--expect-checks 76` | Injected failed report exits 0. Actual count mismatch exits 1. Logs in `edge/`. |

The results cover the minimal one-car headless probe, with a separate dynamic body as an observer. Full motor and multicar reset, contact/gate behavior, interactive equivalence, platform, and gameplay evidence remain open.
