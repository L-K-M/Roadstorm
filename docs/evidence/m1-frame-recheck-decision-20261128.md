# M1 frame preflight: exact-source scoped recheck decision

Date: 2026-11-28 UTC. Candidate `ee44a11b52fefee93cf5770778425da1d6ba5446`, base `0d9a540174f1b5655a07f78f91c74e86ce0b804a`. The independent first-party [Opus 5.5](../../review/implementation/m1-frame-recheck-opus-5-5-ee44a11.md) and [GPT-6.2 Sol](../../review/implementation/m1-frame-recheck-gpt-6-2-sol-ee44a11.md) reports are preserved verbatim. They used separate immutable source archives and writable build/log trees, and neither read the other's current report before submitting. Opus's result metadata identifies `claude-opus-5-5` from its first-party provider; Sol was invoked with exact `-m gpt-6.2-sol` in a first-party Codex session.

The coordinator froze the four changed lab files over base `0d9a540` and independently ran the full pinned-Godot/Jolt lab: 1,200 committed DriveLab ticks for each 30/60/120 nominal headless fixed-FPS mode, 602/1,204/2,408 process frames, 1,204 physics frames, gate tick 357, zero endpoint and gate differences, and all twelve existing negative controls rejected with structured diagnostics. The source hashes matched the worker's own frozen passing run. The suite is numerical headless preflight; it does not measure presented/rendered FPS or establish M1 acceptance.

Both reviewers confirmed the prior wrong-cadence launch, forged 100 m gate rows, malformed FPS field and relabelled-copy examples now refuse. Opus gave a scoped pass with two low findings: one engine-version integer is compared by Python dictionary equality and can be supplied as an equal float; the reported `fixed_fps_argument` still copies the environment label although the measured counters independently guard cadence. Those observations should be corrected or dispositioned before this lab is used for milestone acceptance.

Sol's additional mutations found three material gaps, so the coordinator accepts its **changes required** verdict for this exact candidate:

1. `tick_trace` accepts a floating-point tick equal to its integer ordinal, while the recomputed first-crossing scan skips it. A changed gate summary can then pass despite an earlier 100 m row.
2. A trace claiming 1,200 committed ticks passes with both physics and process frame totals set to one, because the comparator checks only their ratio.
3. A huge positive JSON integer in `timing.physics_frames` triggers an uncaught `OverflowError` during float conversion instead of a structured refusal.

A bounded Devin worker owns only `tools/frame_trace_lab/` to fix those three, retain the previous positive and negative cases, and provide new regression controls. Both named reviewers must recheck the corrected final source. No frame/M1 or release gate is closed by this decision.
