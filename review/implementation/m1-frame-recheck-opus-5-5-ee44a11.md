# Roadstorm M1 frame-trace preflight recheck (Opus 5.5)

**Scoped verdict: pass.** Candidate `ee44a11` closes all three GPT-6.2 Sol frame-preflight defects from the `49d60a1` checkpoint and the relabelled-copy cadence false pass Opus found then. I found no material regression in the four scoped files. Two low-severity nits remain. Neither blocks.

Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, running in Claude Code. Independent first-party review on 2026-11-28. Nothing was delegated. I did not read the other current reviewer's report or work directory. I did not edit source or assets, mutate Git or publish anything.

## Identity

- `../../candidate.sha` = `ee44a11b52fefee93cf5770778425da1d6ba5446`; base `0d9a540174f1b5655a07f78f91c74e86ce0b804a`.
- A recursive SHA-256 manifest of `build/` matches `../source` exactly. The comparison excluded two stray launcher artifacts in `build/`, `result.json` and `stderr.log`. Both hold a CLI usage error and are not candidate content.
- The five lab files in the candidate have these SHA-256 hashes: README `d2abc4cc…`, comparator `7e07c134…`, driver `74ac222a…`, entry `8027a4b8…`, runner `7ac8fceb…`. They match byte for byte both `frame_trace_lab.sha256` and `stage/tools/frame_trace_lab/*` in the coordinator run `run.o62ILx`. That run's `summary.txt` records `source_head_sha=0d9a540` because it was base overlaid with the changed files. The overlay hashes equal the candidate's.
- `../../scope.patch` contains only the four declared files. I reviewed it in full.

## Prior defects

1. **Wrong-cadence launch accepted as 60: closed.** `compare_frame_traces.py:189-213` now requires positive integer `timing.physics_frames` and `timing.process_frames`. It rejects a result when `|process − physics·fps/60| > 4`. The real coordinator launch (`--fixed-fps 30`, label 60) recorded 602 process and 1204 physics frames. It was rejected with a structured `observed physics/process frame ratio 2 …` failure (`run.o62ILx/logs/compare-wrong-cadence.log`). The ±4 tolerance is tiny next to the 602-frame gap between neighbouring cadences, so no other nominal cadence can fall inside it. `fixed_fps_argument` is still copied from `FTP_FPS` rather than the real argv (driver `:375`). The counter check makes that harmless (nit N2).
2. **Forged gate rows: closed.** `:341-356` recomputes the first committed `tick_trace` row with `road_station_m >= 100.0` and requires it to equal `gate.first_committed_tick`. The driver uses the same `>=` rule (`frame_trace_driver.gd:270`). I reproduced Sol's edit (rows 357/358 set to 99.99) and got rc 1: `… first reaches 100.0 m at tick 359`. The reverse stale-summary case (358 vs 357) is rejected in the coordinator run.
3. **Array FPS TypeError: closed.** `:176` checks `is_int` before set membership. `is_int` excludes bool. Negative controls in the runner (`run_frame_trace_lab.sh:455-498`) now need rc 1, `COMPARISON_RESULT … "pass":false`, `COMPARISON FAIL`, and an expected reason substring. That separates a crash from an intended rejection.
4. **Relabelled-copy cadence pass (prior Opus finding): closed.** A copy of the real `full-60.json` relabelled as 30, or as 120, fails the cadence ratio check. In both, 1204 process frames sit against a nominal ratio of 2 or 0.5.

The pinned engine version dict, the `Jolt Physics` backend and host-cohort equality (`:184-187`, `:376-379`) close the "same pinned suite" part of Sol's request.

## Checks performed

All comparator runs used the candidate `build/tools/frame_trace_lab/compare_frame_traces.py` under `python3 -I` against the coordinator's frozen real results in `run.o62ILx/results/`. Script: `opus/logs/adv.py`. Output: `opus/logs/adv.log`. Fixtures: `opus/logs/fx/`.

- Positive: real full-30/60/120 → rc 0.
- Relabel 60→30 and 60→120 without editing timing → rc 1, ratio failure.
- Tolerance boundary at 120: process frames +4 and −4 → rc 0; +5 and −5 → rc 1.
- Hidden gate (Sol repro) → rc 1, tick-359 message.
- `nominal_fixed_fps` set to True, 60.0, "60", {}, None, [60] → each rc 1, structured, no traceback.
- `fixed_fps_argument` set to [], {}, "x", None, 1.5, True → each rc 1, structured.
- Wrong types for timing counters, host fields, engine version and backend, and the gate tick; `timing` or `host` as a non-object; non-numeric `road_station_m` at row 357; a non-dict trace row → all rc 1, structured, no traceback.
- An extra host key in one input → rc 1, `host cohort differs`.
- Coordinator logs: all twelve negative controls hold the structured markers and expected reasons. No `Traceback` appears in any `compare-*.log`. `summary.txt` reports `positive_comparison=pass` and `negative_controls=all_rejected`. Real counts are 602/1204/2408 process frames, 1204 physics frames and gate tick 357 for all three.
- `bash -n run_frame_trace_lab.sh` passes, and `py_compile` of the comparator passes.
- Runner control flow: if the real wrong-cadence Godot launch fails, `run_trace` stops the whole lab through `fatal 1` (`:336-350`). If that launch ever started passing the comparator, the control would record `rejected=no` and the lab would fail. Neither outcome is a silent pass.

I did not make my own Godot engine run. The engine evidence is the coordinator's frozen run, which I re-verified by hash and re-compared with the candidate comparator.

## Findings (ranked)

- **N1 (nit), `compare_frame_traces.py:186`.** The engine version check is Python dict equality, so `"hex": 263938.0` (float) is accepted (`version-hex-float: rc=0`). This has no practical impact because the pinned engine writes integers.
- **N2 (nit), `frame_trace_driver.gd:375`.** `engine.fixed_fps_argument` is the label from `FTP_FPS`, not the real `--fixed-fps` value from argv. The README calls it the recorded argument. The measured counter ratio is the real guard and works, but the field name overstates where the value comes from. Reading `OS.get_cmdline_args()` would make it truthful.
- **Inherent limit (not a defect).** The comparator checks that each result is internally consistent, not where it came from. A hand-forged JSON with consistent labels, counters, rows and gate can still pass. Provenance rests on the runner launching the engine itself and on the recorded result hashes.

## Scope and evidence limits

- Headless `--fixed-fps` changes the nominal process cadence (frame counters of 602/1204/2408 against 1204 physics ticks). It does not change presented or rendered FPS. These results are not display-frame-rate evidence.
- This is a straight, one-car, zero-steer DriveLab preflight with a fixed throttle/coast/brake schedule on one macOS host (Apple M4 Max, headless, Godot 4.7.2 official, Jolt). It is not M1 acceptance. It is not approval of the controller, drift, contact, rights or release, and it does not show that the production game is frame-rate independent.
- Hosted CI for this candidate was not checked, and its workflow does not run this lab.
- My review covers only the four scoped files plus the parts of the driver and entry needed to judge them, inside a bounded time budget.
