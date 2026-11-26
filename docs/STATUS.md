# Implementation status

Updated 2026-11-26. Baseline `0ea596a4fa85ade19375e130313f020ed6010619` was fast-forwarded from origin/main. No milestone is complete and no game build is verified. M0 is in progress; M1–M9 including M4B are open. The coordinator lease is `work/agents/coordinator.lock`, run `1e3d39cf-2fb6-4196-8d18-48755ee9f61f`.

Local Godot reports 4.7.2.stable.official.ed1daf0bf on macOS ARM64; editor binary and three release templates match publisher-checksummed archives; other bundle files, Python pin and hardware reviews remain unverified. LongCat and StepFun auth readiness was reported by pi; quota and successful completions remain to be established. Opus 5.5 via Venice and GPT-6.2 Sol via openai-codex report auth readiness, not proven review availability. No review has been performed.

Active isolated jobs against the baseline (private sessions and logs under `work/agents/<id>`):

| Job | Provider/model | Owned paths | Status |
| --- | --- | --- | --- |
| 9390c59e-cae3-4e4e-baba-d86618c7a2ed | stepfun/step-5-preview | project.godot, scenes/, src/boot/, tools/smoke/ | completed; placeholder shell; independent snapshot headless boot passed, deliberate failure exited 1 |
| c0a9220f-157c-4641-8c7a-82b3b64b6aa2 | longcat/LongCat-2.5 | schemas/, fixtures/ | stopped after prolonged analysis without files; split the work |
| 00b1219c-b656-45e1-b2ad-84f26776eb36 | longcat/LongCat-2.5 | licenses/, provenance/ | completed; pending independent review and terms/authority evidence |
| 93555487-a479-4ecb-ac23-9e95067144cf | stepfun/step-5-preview | tools/ci/, .github/workflows/ | running; CI and commands |
| 9724e895-7e6d-41a6-bc27-1bfd805167f3 | stepfun/step-5-preview | docs/TOOLCHAIN.md, tools/toolchain/ | completed; selected archives and installed files independently verified, see evidence |
| 9370f30f-fbd7-42cb-b401-a69ff4d7a2b5 | stepfun/step-5-preview | docs/MACHINE_INVENTORY.md | completed; pending review; reports no physical controller/audio review and two CI defects |
| 6058a51e-ae48-4329-8fb0-52c3c36eddad | stepfun/step-5-preview | assets/manifest.json, tools/asset_manifest/ | completed; independent 35-test suite and empty-manifest check passed; real assets and rights validation remain open |
| ec6b876f-cdad-40f3-a154-ff99473a0c54 | longcat/LongCat-2.5 | tools/tick_probe/ | completed; initial DEFAULT-backend evidence superseded. Follow-on job 9725ba2c selected Jolt; independent 58-check structural and 600-tick pacing reruns passed; backend identity is inferred from setting and contrast, not directly observable |

Next: collect and independently verify each job, integrate coherent owned paths, establish tooling/checksum and CI, run acceptance against a frozen candidate, then request separate Opus 5.5 and GPT-6.2 Sol reviews. All review, platform, audio, controls, model training and release gates remain open. Do not infer completion from worker reports or auth readiness.

## Five-job checkpoint

Candidate `6b571835837dff8e9a25d1696f5622ecf9fa451b`, base `0ea596a4fa85ade19375e130313f020ed6010619`: Opus 5.5 via Venice job `0bbb2f75-c3eb-47f5-9d89-771bce087012` and GPT-6.2 Sol native agent `/root/checkpoint_sol` completed independent reports under `review/implementation/`; both verdicts are changes required. Pi openai-codex route failed with invalidated OAuth token; pi opencode and openrouter routes returned insufficient balance/credits. These attempts produced no reviews. Both reviews must complete and findings be resolved before checkpoint closure.

Remediation in progress: `3845159a-f14b-4572-ac8d-25bf5f43d841` (StepFun, `tools/asset_manifest/`, Sol findings) and `79b88744-0e83-4ab7-9564-98fc3483d9f3` (StepFun, `tools/smoke/`, Opus smoke findings). Opus also found rights/approval gate, manifest schema, Jolt, toolchain missing-template and other defects; assign separate fixes after paths are free. Both reviewers must recheck corrected candidate. Hardware inventory found CI doctor parse and capture resolution defects, pending CI integration.

Additional active job: `d18bba32-2127-4136-98d6-c7e09c7f3d01` (StepFun, `tools/toolchain/` remediation). Tick probe must explicitly select/verify the intended backend and repeat fidelity measurements.

The GPT-6.2 Sol manifest fixes (`3845159a-f14b-4572-ac8d-25bf5f43d841`) and Opus smoke remediation (`79b88744-0e83-4ab7-9564-98fc3483d9f3`) completed; smoke fault injection was independently rerun (6/6 expected outcomes). Follow-on `ed8c1319-fabb-47d5-8b27-266cc1348576` owns manifest remediation for remaining Opus findings. `9725ba2c-802a-4115-9aeb-337b1dca99c8` owns `project.godot` and `tools/tick_probe/` to select and verify Jolt and repeat probe checks. Reviews remain open pending fixes and rechecks.

`a04dc96f-1f5a-44ff-a636-217034a045fd` (StepFun) completed official LongCat/StepFun terms intake source capture; account applicability and dedication compatibility remain open. `b20cb153-94a8-4997-be00-1f8335daa1a0` (StepFun) owns only `schemas/handling/` and `fixtures/handling/` for a bounded M0.9 slice. The interrupted AI schema remains unaccepted.

`ed8c1319-fabb-47d5-8b27-266cc1348576` completed further manifest remediation; 76 tests and 22 negative probes passed independently; both scoped rechecks remain required. `8cfeb70f-e5b3-4cac-8b4c-83a933d0970b` (StepFun) owns `schemas/intent/` and `fixtures/intent/` for a bounded AI-intent schema slice.

`93555487-a479-4ecb-ac23-9e95067144cf` completed CI tooling, uncommitted and not accepted: its Linux workflow extracts a download without verifying the publisher checksum first, and the machine inventory identified doctor/capture issues. Follow-on `6848aca2-16e6-42f1-abfd-4e493b125af5` owns `tools/ci/` and `.github/workflows/` for targeted fixes. Its claim of a missing nested tick coordinator conflicts with the present file and requires isolated reproduction. Do not call M0 CI complete until independently checked.

Jolt correction `9725ba2c-802a-4115-9aeb-337b1dca99c8` completed: independent isolated rerun passed 58 structural checks and matched accelerated/realtime 600-tick endpoints; inferred backend identity and full simulator gate remain subject to review. The recursively nested scratch copy it made was removed.

Schema slices `b20cb153-94a8-4997-be00-1f8335daa1a0` (handling) and `8cfeb70f-e5b3-4cac-8b4c-83a933d0970b` (tactical intent) completed; their independent runs passed 36 and 12 tests respectively. Contracts and fixtures remain provisional/unreviewed and are not evidence of a car, AI, or measured gameplay. `847d8664-1028-4233-a67c-39f1465b4964` (StepFun) owns `schemas/scenario/` and `fixtures/scenario/`; `b2377a10-187a-40e6-94ae-8b239bc7a93e` owns `docs/PYTHON_TOOLCHAIN.md` and `tools/python_pin/`.

`a67680d9-2923-4992-a350-5804f0fcc193` (StepFun) owns the authority/open-items subset of provenance for an accuracy correction: retain the plan's standing-record requirement while removing invented signature or approval requirements. It does not own provider-term snapshots.

Provenance authority correction `a67680d9-2923-4992-a350-5804f0fcc193` completed; account terms remain open. The StepFun route notation identified in its report has been corrected.

Python pin job `b2377a10-187a-40e6-94ae-8b239bc7a93e` completed. The coordinator checked the 3.15.2 source archive against python.org's published SHA-256; other artifacts, Sigstore verification, local interpreter provenance, and CI pin integration are open. Observation schema job `8667d71d-5817-4955-b069-aed859c8d8f8` owns only `schemas/observation/` and `fixtures/observation/`.

Manifest remediation committed in `bdeb8e2`; Sol scoped recheck `/root/sol_recheck` is running against that immutable candidate. Opus scoped recheck for the same candidate remains due; CI, scenario, and observation jobs continue outside its scope.

Sol recheck of `bdeb8e2` found the original manifest defects fixed but a new JSON `null` root false pass; the coordinator changed the decoder sentinel, added a null-root regression and independently observed structured failure exit 1. The suite passed. The Sol recheck and corrected candidate require another scoped review; Opus recheck of `bdeb8e2` remains in progress. Toolchain summary was updated to distinguish established local Jolt/Python pins from remaining evidence.

Opus recheck of `bdeb8e2` returned changes required; report `review/implementation/m0-five-jobs-opus-recheck-929c4082-0280-464e-830a-00dd35c164e1.md`. Remaining key findings: symlinked parent escape and invalid service-terms references, main-project Jolt guard/settings, missing committed CI/schema references, and an intermittent Jolt job-system warning. `bc086adc-5f31-492e-8d48-54b10fb081cf` (StepFun) owns `tools/asset_manifest/` to fix path/rights findings while preserving the null fix; `a35656d6-09c1-4698-a699-ad211125217d` (StepFun) owns `tools/smoke/` and `docs/evidence/jolt-settings.md` for the Jolt assertion, fault injection and settings/warning evidence. Both reviewers must recheck the eventual corrected candidate.

Scenario contract job `847d8664-1028-4233-a67c-39f1465b4964` completed; its reported 21 tests/20 fixtures remain to be independently checked. Shipped fixtures are planned examples, not measured race results.

CI follow-up `6848aca2-16e6-42f1-abfd-4e493b125af5` completed; it reports checksum-before-extraction and capture/doctor repairs. Coordinator reran the 53-case self-test successfully. GitHub-hosted CI, complete content validation and export presets remain open; do not treat an empty manifest as content completion.

An independent `ci.sh all` run passed on a `git archive` of `935b9e2` with the completed CI files overlaid, in `work/agents/ci-candidate/`; it reported content validation and export presets as missing. This is a local snapshot check, not a GitHub-hosted CI or export pass.

The CI batch was committed and pushed as `6e5b0d1`; its local snapshot run passed but content validation/export/hosted CI remain open. Read-only LongCat review job `432dd585-7d19-48eb-9389-adeff2a5719f` is checking the draft handling, intent and scenario slices for contract/validator inconsistencies; observation is excluded while its worker edits it. No schema freeze is accepted.

`a35656d6-09c1-4698-a699-ad211125217d` was stopped after two unbounded Jolt probe subprocesses; no owned tracked edits were found and Jolt default/settings evidence remains open. Replacement narrow smoke assertion job `793249aa-bb05-4838-9bf9-b6bc29aa14e9` owns only `tools/smoke/`. Observation job `8667d71d-5817-4955-b069-aed859c8d8f8` completed; independent fixture checks passed. Read-only observation audit `bec6cc5e-d448-432c-8979-0b7390f5c063` is running. The Opus recheck report is still uncommitted and must be preserved.

Manifest recheck remediation `bc086adc-5f31-492e-8d48-54b10fb081cf` completed; coordinator independently ran 99 tests successfully. It rejects symlinked intermediate paths, requires resolvable service/rights references and non-unknown perceptual approval; reference existence is not a rights assessment and simulated swap tests do not prove race-free filesystem access. Review remains open until both named reviewers recheck.
