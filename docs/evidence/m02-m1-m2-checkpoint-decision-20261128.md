# Scoped M0.2/M1/M2 checkpoint decision at `b6ab93a`

Candidate `b6ab93a31075a4596e6d4ea9bdc98e504a7477c3`, base `e94e94feb3a04c872138db9de267ffffd1fb21c7`. The separate first-party reviews were copied verbatim: [Opus 5.5](../../review/implementation/m02-m1-m2-checkpoint-opus-5-5-b6ab93a.md) and [GPT-6.2 Sol](../../review/implementation/m02-m1-m2-checkpoint-gpt-6-2-sol-b6ab93a.md). Each used its own immutable source and writable build, and neither read the other's current report. The Claude CLI JSON confirms canonical first-party `claude-opus-5-5`; the Codex CLI was invoked with exact `-m gpt-6.2-sol` and exited 0, while its event log does not supply separate runtime model attestation. Hosted run [46113265541](https://github.com/L-K-M/Roadstorm/actions/runs/46113265541) later passed all four jobs on this exact candidate; hosted CI does not run the frame or road-source labs.

| Scoped slice | Opus | Sol | Decision |
| --- | --- | --- | --- |
| A. Comet stable ID and numerical frame repair | pass | pass | Bounded repair accepted for this candidate; no M0.2/M1 closure. |
| B. Provisional road-source contract | changes required | changes required | Keep source contract open and repair both independently reproduced defects. |
| C. 420-tick physical sweeper bridge | pass with low gaps | pass with low gap | Preliminary arc-entry witness accepted; full M1.7 open. |
| D. Six provisional reward recipes A/B | pass | pass | Authoring data accepted as provisional; no balance or rights clearance. |
| Overall | changes required | changes required | Checkpoint remains open until both named scoped rechecks of the corrected road source. |

## Required repair and recheck

1. **Finite scalar to non-finite Vector3:** both reviewers reproduced parser acceptance of finite JSON values beyond Godot's float32 Vector3 range, yielding infinite stored control points and breaking canonical round-trip. The road-source worker owns `src/course/road_source.gd` and `tools/road_source_lab/**`; require post-conversion finiteness and regression coverage. The parser's float32 narrowing must be documented or otherwise handled.
2. **Permissive JSON-text syntax:** Sol reproduced acceptance of `,}` and a duplicate `closed` member whose later valid value hides the earlier invalid value. Opus independently observed duplicate-member last-wins behavior. The same worker must enforce strict text grammar and duplicate-member refusal before dictionary construction, including escaped-key equivalence, with valid-source controls. The in-memory `parse_document` checks alone cannot detect a discarded wire member.
3. Freeze the corrected exact source, rerun the pinned seven-case source suite and deliberate failing probe, independently probe both reported counterexamples, then obtain separate Opus 5.5 and GPT-6.2 Sol scoped rechecks. No M2.1 gate closes because arc-length sampling, frames, mesh/collision and course validation are still absent.

## Deferred findings and limits

- Opus found course/revision/section IDs currently have only non-empty string checks; visually similar IDs with trailing whitespace are distinct. Decide and test stable-ID syntax before authoring route registries. Sol found the open source's unused endpoint handles are accepted despite broad wording; document the used-handle rule or validate all handles. These are low-severity source-contract follow-ups, not a reason to ignore the two reproducible blockers.
- The sweeper bridge's two runs recorded zero contacts and full grounding, but the validator does not assert every recorded contact/ground field; its repeat list omits several recorded values. The component refusal case does not drive the bridge's actual failure path. Tighten assertions/claims before M1.7 acceptance. Opus also observed read-only archive cleanup errors despite a PASS; repair the runner's cleanup or narrow that capability claim. The separate full-arc LongCat job is exploratory and was outside this reviewed source.
- Opus noted the new heading coherence guard has only zero-heading genuine traces. The prior numeric counterexamples are repaired, but nonzero physical heading traces and presented FPS remain unverified.
- The final three reward-car recipes C were authored after `b6ab93a`; their later source needs its own review coverage. All twelve recipes remain provisional, unmeasured and without production visuals.
- The earlier baker malformed-report duplicate-member observation is outside this candidate's changed baker source; a separate LongCat repair is active. Case-18 reread isolation and same-inode diagnostic wording remain open for broader M0.2.
- M0.3 LongCat/StepFun standard public terms and OI-02/OI-03 release-rights compatibility remain unresolved. Neither report asserts rights, audio, controller, visual, full milestone or release acceptance.
