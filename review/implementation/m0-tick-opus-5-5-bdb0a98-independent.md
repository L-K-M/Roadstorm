# M0.8 tick/reset recheck: independent Opus review of `bdb0a98`

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, running in the Claude Code agent harness
- Date: 2026-11-27
- Candidate: `bdb0a9820b847d23628cce35a9070bb63ae17acd` (`bdb0a98`, "Freeze waiting simulation and verify tick fidelity")
- Base: `d562755c83af1129b4ddf7043baee8d8a742d358` (`d562755`)
- Scope: `tools/tick_probe/**` and the M0.8 line of `PLAN.md` (line 63 at `bdb0a98`)
- Source of truth: `git show bdb0a98:<path>` and `git diff d562755 bdb0a98 -- <path>` only. I did not read live working-tree source.
- Prior input: my earlier review `review/implementation/m0-tick-opus-recheck-64cbe5b0-7cc7-4130-80a3-cfc7d4d59f43.md`
- Not consulted: any Sol report, including `review/implementation/m0-tick-sol-recheck-d562755.md`
- No agents spawned. No Git mutation. No source edits, no GUI, no installed templates touched. This file is the only write.

**Verdict: NOT VERIFIED (runtime). Static review: PASS for the M0.8 one-car probe scope, with no blocking defect.** All the fixes I asked for in the earlier review are present and look correct in the code, except L2 (wording) and L5 (evidence that cannot be told apart from a copy), which are still open. New finding N1 is a plausible gap, not a confirmed one. It should be measured before the M1 motor or any gate or trigger relies on physics-server-stepped state. I did not reproduce the coordinator's 51/51, 99/99 or compare-modes results.

## What I actually ran

| Attempted | Outcome |
| --- | --- |
| `git rev-parse bdb0a98 d562755`, `git log --oneline d562755..bdb0a98`, `git diff --stat/--name-status d562755 bdb0a98 -- tools/tick_probe PLAN.md` | Done |
| `git diff d562755 bdb0a98 --` for `tick_coordinator.gd`, `probe_driver.gd`, `contract_driver.gd`, `run_contract_tests.py`, `README.md` | Done |
| `git show bdb0a98:` for `tick_coordinator.gd` (full), `compare_modes.py` (full), the `run_contract_tests.py` body, the `contract_driver.gd` header, `PLAN.md` M0.8, and the evidence files `README.md`, `manifest.sha256`, `provenance.json`, `compare-modes.txt`, `mutation-sensitivity.txt`, `pre-fix-reproduction.txt`, `post-fix-verification.txt`, plus a key grep of `structural-fixed-fps.json` | Done |
| `git archive bdb0a98 \| tar -x` into a private `/tmp` snapshot | **Refused** by the tool permission layer (needs interactive approval; this session is non-interactive) |
| `godot --version` and every Godot run (structural, contract, trace, compare) | **Refused**, same reason |
| `git show bdb0a98:<file> \| shasum -a 256` to check `manifest.sha256` | **Refused**, same reason |

So every runtime number below comes from the recorded evidence or the coordinator. I checked that the numbers agree with the code, but I reproduced none of them. I also did not recompute the manifest hashes against the `bdb0a98` blobs.

## Status of my earlier findings

| Earlier finding | Change in `bdb0a98` | Static assessment |
| --- | --- | --- |
| **M1** world not frozen after `reset()` or a zero-tick request | `reset()` ends with `set_frozen(true)` (`tick_coordinator.gd:203-208`). `begin_step(0)` refreezes after emitting (`:250-252`). The cap ≤ 0 path (`:236-243`) and the terminal-episode path (`:227-231`) freeze explicitly. The unfreeze/refreeze pairs in `reset()` and `begin_step(0)` are synchronous, so no physics iteration can run between them. | **Fixed.** New contract and structural `wait-guard` tests use an independent `RigidBody3D` with a running-world control, exact `==` equality on `y`, and a wait counted in physics frames. The structural assertion that a reset leaves the world unfrozen was correctly inverted (`probe_driver.gd` reset scenario). |
| **M2** fidelity evidence was one scalar | `mode=trace` (`probe_driver.gd` `_run_trace`) emits per-tick rows (start/end z, accepted length, substeps, grounded, prediction error), RNG draws, event kinds, final pose and rotation, and terminal results for open-road plus reset/replay, wall contact, termination at z = -0.9, and `motion_bound`. `compare_modes.py:123-200` compares the trees recursively across fixed, `--max-fps 60` and default pacing. | **Addressed** for this probe. Recorded max \|diff\| = 0. Limits: see L7. |
| **L1** `begin_step` had no in-flight guard | It refuses when a result is pending (`:225-226`), when a step is in flight (`_budget > 0`, `:232-233`) and for negative ticks (`:234-235`). `_finish_step` zeroes `_budget` (`:458`) so motion_bound ends cannot leave a stale budget. It returns `bool`. | **Fixed.** Tested under all three pacings, and the mutation run shows the checks are sensitive to it. One gap, L8: the terminal-episode path accepts negative ticks. |
| **L2** README and code disagree on cap ≤ 0 | README still says the episode "starts `truncated`". `reset()` and `_reset_state()` still set `episode_terminal = "none"`, so `observe()` reports `"none"` until the first `begin_step`. | **Open** (Low). |
| **L3** backstop recorded residual motion without failing | `_execute_tick` returns `true` on a capped remainder, and `_physics_process` ends the step with `motion_bound` (`:313-318`, `:415-418`). A mid-request over-speed test was added. | **Fixed** in logic, but the backstop itself is still not executed by any committed test. README and provenance say so openly. See N2 for a state detail. |
| **L4** frame-counting limits | The contract runner gained `--pacing fixed\|default\|max`. Waits now count `physics_frame` (`_wait_physics_frames`, `_wait_engine_frames`). | **Fixed.** Recorded 51/51 under each pacing. |
| **L5** fixed-fps and max-fps evidence byte-identical | Still byte-identical: `structural-fixed-fps.{json,raw.txt}` and `structural-max-fps-60.{json,raw.txt}` have the same SHA-256 in the manifest. The payload records no pacing flag (`label: "local"`, no fps field). | **Open** (Info). See P2. |
| **L6** signal emits `_result` by reference; `compare_modes.py` runs in place by default | Unchanged (`:479`; `compare_modes.py:137`) | **Open** (Info). README acknowledges the in-place default. |

## New findings, ranked

**N1 (Medium, plausible, unverified): physics-server steps are probably not one-for-one with logical ticks at the end of a request.**
- `_finish_step` sets `SceneTree.paused = true` from inside the coordinator's `_physics_process` (`:463-464`).
- In Godot's main loop the scene-tree physics callbacks run before `PhysicsServer3D::step()`, and setting `SceneTree.paused` deactivates the physics server.
- If 4.7.2 keeps that order, the server step for a request's final tick is skipped. Anything the server integrates (a `RigidBody3D`, `Area3D` overlap state, contact reports) would then advance `requested - 1` steps per request while logical ticks advance `requested`.
- The probe car is unaffected: it moves by explicit `move_and_collide`. So the recorded tick, position and digest results stay valid.
- The new independent-body tests only show **zero drift while waiting**. None shows **N server steps for N ticks**.
- This matters before M1, and before gates, triggers or any dynamic object depend on the coordinator.
- Suggested check: put a free-falling `RigidBody3D` in the world, run 12-tick requests, and compare its velocity against 12 × g × DT per request (or count `Area3D` overlap transitions). If it shows 11, defer the freeze to the start of the next iteration, or pause from a post-step hook.

**N2 (Low): the backstop ends a request after committing partial motion.**
- On the in-loop backstop path, `move_and_collide` has already moved the body up to 4 m when `_execute_tick` returns `true`.
- `tick_count`, `_step_elapsed`, the RNG draw and `tick_log` are not updated. The final observation therefore shows a pose that no accounted tick produced.
- The pre-check path moves nothing.
- The path is unreachable through public configuration (README/provenance limit), and `motion_bound` ends the episode. Either restore `start` before returning, or document that the final pose is uncounted.

**N3 (Low): the contract runner cannot detect lost checks.**
- `run_contract_tests.py` trusts `checks_failed` and the exit code. It does not assert the expected `checks_total` (51) or fail on `SCRIPT ERROR` in the output.
- `mutation-sensitivity.txt` shows a `SCRIPT ERROR` that aborted `_test_begin_step_refusals`, and the total fell to 50.
- In that run other failures kept the exit nonzero. But a runtime error before a test's first `_check` would pass silently.
- `compare_modes.py` has the same gap for the structural/trace runs.

**N4 (Low): mutation evidence covers only one of the three new freeze sites.**
- The recorded mutation ("reset freeze and begin_step guards disabled") fails the reset wait-guard and refusal checks.
- The zero-tick and exhausted-budget wait-guard checks still **pass** under it. So the `set_frozen(true)` calls at `:241` and `:252` were not reverted, and the test sensitivity for those two paths is shown only by the pre-fix reproduction.
- That reproduction comes from `res://src/repro_followup_entry.gd`, which is **not committed** in `bdb0a98`: it is referenced only in `provenance.json`. And its CAP0 case is a cap-0 *reset* wait, not a cap-0 `begin_step` wait.

**L7 (Low/Info): limits of the trace digest.**
- Rows carry only z per tick. x, y and rotation appear only as final values.
- The tolerance is 1e-6 rather than exact, although the recorded diffs were exactly 0.
- The coordinator ignores `delta`, and every scenario is kinematic against static bodies. Matching across pacings is therefore close to guaranteed whenever tick counts match. It tests accounting more than physics.
- No dynamic body is in the trace, which is where N1 would appear.

**L8 (Low): `begin_step(-1)` on a finished episode is accepted.** It returns `true` and emits `requested_ticks: -1`, because the terminal check (`:227`) comes before the negative check (`:234`). Move the negative check first.

## Evidence provenance

- **P1.** The evidence README and `provenance.json` name `d562755` as the "reviewed candidate". `file_sha256` holds the hashes of the uncommitted follow-up tree, which became `bdb0a98`. The record cannot name its own commit, which is expected, but it never says that the results were produced on that tree and not on `d562755`. I could not confirm that `file_sha256` matches the `bdb0a98` blobs (hashing was refused).
- **P2.** `provenance.json` is not itself listed in `manifest.sha256`.
- **P3.** The structural payloads do not record their pacing flags, so the byte-identical fixed and max files cannot prove which flag produced them.
- **P4.** The pre-fix and post-fix reproduction script is uncommitted (N4).
- The coordinator's report that it independently ran 51/51 in three pacings, 99/99 fixed structural, compare-modes PASS and a manifest check is consistent with these files, but I did not reproduce it.

## Limitations

- No runtime execution and no hash recomputation in this session (permission layer). The verdict is static only.
- Scope is the one-car `CharacterBody3D` probe in headless Godot 4.7.2 with Jolt pinned by setting. Not covered: the full M1 motor, multiple cars, contacts between cars, gameplay, the training bridge, interactive or rendered execution, cross-platform determinism, and runtime confirmation of the backend.
- N1 is reasoned from Godot's main-loop ordering, not measured on 4.7.2.

## Recommended next actions

1. Measure N1 with a dynamic-body steps-per-tick check before M1 relies on server-stepped state.
2. Add the expected `checks_total` and `SCRIPT ERROR` detection to both runners (N3).
3. Extend the mutation run to revert the zero-tick and cap-0 freezes, and commit the reproduction driver or drop the claims that depend on it (N4/P4).
4. Fix L2 and L8. Restore the pose on the backstop path or document it (N2). Record pacing flags in the payloads and hash `provenance.json` (P2/P3).
5. Have an approved runner recompute the manifest against `bdb0a98` blobs to close P1.
