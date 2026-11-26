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

The narrow smoke job `793249aa-bb05-4838-9bf9-b6bc29aa14e9` completed; coordinator reran all eight isolated fault-injection cases successfully. It reported deleting a pre-existing `/tmp/roadstorm-baseline-206edf5` scratch checkout copy that it had not created; that deletion was not authorized by the job. The original Opus recheck recorded an intermittent Jolt job-system warning; its cause and Jolt settings inventory remain open. The coordinator added narrow ignore rules for local credentials/builds/captures/saves and corrected the fault harness's misleading expected-exit wording.

Both named scoped rechecks are running on immutable candidate `15faf0d` (base `bdeb8e2`): native GPT-6.2 Sol `/root/sol_final_recheck`, and Venice Opus 5.5 job `2963edd5-0b1f-4713-ad3b-64f7f9e4f332`. The two draft schema audits continue separately. Jolt default/settings capture and the intermittent warning remain open; this pair is not M0 acceptance.

Sol recheck `15faf0d` returned changes required: route snapshot path shape and provider-register fragment validation remain incomplete; `69a41d0f-b856-4eaa-8593-c0b9385acb06` (StepFun) owns `tools/asset_manifest/` to fix those. The coordinator corrected the smoke check's misleading success line on settings failure and reran all eight fault cases. Opus `15faf0d` recheck and the two schema audits remain in progress.

Observation audit `bec6cc5e-d448-432c-8979-0b7390f5c063` found a validator crash on an optional field, non-finite and per-feature range gaps, and cross-slice reference/fixture inconsistencies. Report and repros are in its ignored job directory. Repair job `74b35657-1cb2-47c1-8753-ed569921f41f` (StepFun) owns only observation schema/fixtures; intent cross-references remain pending. The draft schemas remain uncommitted and unfrozen.

Opus recheck `15faf0d` returned changes required: CI invokes the direct smoke script, so a runtime error can pass despite the supported wrapper. Follow-on `1360dafb-4669-4545-a31b-e349fbcb9207` (StepFun) owns CI and workflow files to fix that and test fault injection. The Opus report is uncommitted and must be preserved. Jolt settings/warning and schema integration remain open.

`69a41d0f-b856-4eaa-8593-c0b9385acb06` completed route-reference remediation; the coordinator reran its 115-test suite successfully. The smoke success log was also corrected and its eight fault cases rerun. Both named rechecks of `15faf0d` reported changes required; their reports are preserved in `review/implementation/`. Another scoped review pair is required after the CI runtime-error correction lands.

`52ab36a7-ac1b-4aa4-9994-3f6310a49d45` (StepFun) owns `docs/evidence/jolt-settings.md` and `tools/jolt_inventory/` for a bounded settings inventory and warning record; no handling settings freeze is authorized from that evidence alone.

Observation repair `74b35657-1cb2-47c1-8753-ed569921f41f` completed; independent 27 tests/33 fixtures passed. History/reset semantics and intent cross-references remain unratified; both schema audits and their findings need integration review. Export smoke job `d13e7491-2fcb-4722-8cc8-c61f72f69707` (StepFun) owns only `export_presets.cfg` and `tools/export_smoke/`, using a frozen archive snapshot for any builds.

Cross-schema audit `432dd585-7d19-48eb-9389-adeff2a5719f` returned 13 findings (full report in its ignored `findings.md`): draft 4 m drafting eligibility contradicts the 5–20 m window; common metric schema conflicts with handling validators; scenario/reference evidence and command/history fields are incomplete; additional fixture, bounds and cross-contract issues. Draft schemas remain uncommitted. Repair job `896f97f0-41d9-491a-8d44-1ef435adbaac` (StepFun) owns `schemas/common.schema.json`, `schemas/handling/` and `fixtures/handling/`; intent/scenario follow-on repairs remain due after that ownership frees.

Jolt inventory job `52ab36a7-ac1b-4aa4-9994-3f6310a49d45` completed; a coordinator rerun recorded 32 settings successfully in isolated temporary projects. The game overrides the backend and interpolation, while Jolt-specific values remain engine defaults. The earlier warning was not reproduced in the worker's 15 attempts and remains unexplained; the inventory is not a handling freeze.

Scenario/reference repair job `f4b734f4-85a2-4f26-993f-c752e0539e49` (StepFun) owns only `schemas/scenario/` and `fixtures/scenario/` for supported cross-schema audit findings; shared common schema is concurrently owned by handling repair and remains unfrozen. Jolt inventory was committed as `10d9e51`; 15 no-warning attempts do not close the intermittent warning.

Smoke-export worker `d13e7491-2fcb-4722-8cc8-c61f72f69707` exported Windows/Linux from frozen `10d9e51` plus its presets but could not export macOS with the original project setting. A separate diagnostic enabled ETC2/ASTC and launched an ad-hoc unnotarized macOS placeholder. The coordinator enabled that setting in `project.godot`; the new committed candidate still requires a non-diagnostic export/launch rerun. Windows/Linux exports were not launched on target hosts.

Coordinator independently exported candidate `7b27c2f` from `git archive` to `work/agents/macos-export-check/output/Roadstorm.zip` (SHA-256 `db9685fc4a8d09bb4e57e16b20850fb79be1596f293dade69193e68bd71ff8e8`). Headless launch exited 0 and reached the placeholder menu; `codesign` reported ad-hoc with no team identifier. Desktop was held by another user/session, so no windowed launch was attempted on this candidate. This is not a gameplay or release build.

`e2af3183-00d3-47a6-b206-b48fa5c3c32d` (StepFun) owns `schemas/intent/` and `fixtures/intent/` to address the cross-contract audit and observation audit findings; common schema remains under the handling worker. Both schema interfaces remain provisional.

The desktop subsequently became free. The coordinator launched the `7b27c2f` macOS smoke ZIP windowed via `tools/export_smoke/launch_macos_app.sh`: the placeholder menu was visible in the captured image, the process was terminated by the bounded harness, and no process remained. This is a local macOS shell smoke only; signing remains ad-hoc/unnotarized and Windows/Linux were not launched.

Handling repair `896f97f0-41d9-491a-8d44-1ef435adbaac` and scenario repair `f4b734f4-85a2-4f26-993f-c752e0539e49` completed. They report corrected shared metrics, provisional drafting/geometry/revision fixtures, and scenario commands/history/evidence checks; combined independent checks and both named reviews remain due. The handling worker reported a scenario test refreshed a fixture while its owner was editing; the scenario owner repaired it, but final integrated snapshot must be checked. Read-only LongCat provenance accuracy audit `b701fff7-4b11-49fc-bfb2-fb63be4af335` is running on committed `7b27c2f`.

Setup-guide job `252f35a8-f3dd-41c5-8862-f0eeda8bdfbc` ran the macOS export/launch harness during documentation verification without acquiring the desktop lease, contrary to the desktop protocol. The process has ended; coordinator windowed check used the lease. Future jobs must not run GUI checks without explicit desktop coordination.

Setup guide job `252f35a8-f3dd-41c5-8862-f0eeda8bdfbc` completed on a committed snapshot. It found `ci.sh export --check` rejects Godot's `Windows Desktop` platform as missing `Windows`, so export-preparation CI would fail. Fix and reproduce before M0 acceptance; do not treat cross-exports as target-platform launch tests.

Intent repair `e2af3183-00d3-47a6-b206-b48fa5c3c32d` completed, reporting 17 tests and 27 fixture cases. It identified unresolved road-width disagreement (Surge intent 12 m versus observation 11 m), missing follow-on observation IDs and duplicate partial schema naming. Schema integrator `d649bead-f5dc-4e9d-9ca1-5562254fd19a` (StepFun) now owns all `schemas/` and `fixtures/` exclusively to reconcile these and validate combined contracts. No schema freeze has occurred.

During CI remediation job `1360dafb-4669-4545-a31b-e349fbcb9207`, coordinator stopped recursive `tar` processes when `runtime_error_gate.sh` put its TMPDIR inside the source tree and then archived that tree. This is an observed harness defect: the destination must be outside or explicitly excluded; verify cleanup and retest before accepting CI.

Read-only LongCat M1 feasibility job `c2583734-2d6d-4bd5-a4cd-c268dcdbc0d6` is examining specific movement/query risks while M0 remains open; M1 implementation has not started and is not claimed complete. CI remediation, schema integration, and provenance audit remain active.

Read-only M1 feasibility job `c2583734-2d6d-4bd5-a4cd-c268dcdbc0d6` completed. It identified sweep-margin/recovery behavior, bounded displacement/contact work, and engine-default Jolt settings plus the intermittent warning as risks for M1 experiments. Its findings are hypotheses for the driving gate, not handling evidence; see the ignored job report for detailed proposed matrices.

CI remediation `1360dafb-4669-4545-a31b-e349fbcb9207` completed and reports 70 self-tests and six runtime-error/warning fault cases. It fixed its recursive scratch copy after coordinator intervention. CI remains uncommitted pending independent verification and `21c20177-d893-4489-b217-cfcb026193c8` (StepFun) correcting the Windows Desktop export-preset check. Setup guide is provisional pending that fix.

LongCat provenance audit `b701fff7-4b11-49fc-bfb2-fb63be4af335` completed on `7b27c2f`. It found stale authority/manifest/pin claims, omitted reviewer-provider routes, and historical hash records that were not labeled as historical. Reconciliation job `42e44973-c074-4141-aac7-9e7f0524a9e1` (StepFun) owns `provenance/*.md` and `licenses/README.md`, preserving provider snapshots and keeping terms gaps open. Full audit is in its ignored job directory.

CI fixes `1360dafb-4669-4545-a31b-e349fbcb9207` and `21c20177-d893-4489-b217-cfcb026193c8` were independently checked on an isolated archive with CI files overlaid: 86 self-tests, six runtime-error/warning injections and export-preset check passed; Windows maps to Godot's `Windows Desktop`. The check verifies local templates/presets only. Both named reviewers must recheck the resulting committed candidate.

Scoped checkpoint rechecks on immutable `49dd9c5` (base `15faf0d`) are running: native GPT-6.2 Sol `/root/sol_ci_recheck` and Venice Opus 5.5 `4803d848-c82b-4902-97d7-feee789a5b7b`. They cover route/smoke/CI fixes; M0 acceptance and schema freeze remain open. Schema integration `d649bead-f5dc-4e9d-9ca1-5562254fd19a` and provenance reconciliation `42e44973-c074-4141-aac7-9e7f0524a9e1` remain active on separate uncommitted paths.

Schema integrator `d649bead-f5dc-4e9d-9ca1-5562254fd19a` completed the draft slices and reports Ajv 8.20 draft-2020-12 comparison (11 schemas valid; positive/negative outcomes accounted for). Coordinator independently reran the four suites from a copied tree: 59 handling, 27 observation, 17 intent and 48 scenario tests passed, with fixture cases passing. Two follow-on observation IDs remain absent from examples; metric rules are duplicated between common JSON Schema and subset evaluators. These are provisional contracts, not measured gameplay or a frozen AI schema; both named reviews are required before closing their gate.

The provisional schema batch was committed and pushed as `aee1822`. Schema checkpoint pair on that exact candidate (base `49dd9c5`) is running: native GPT-6.2 Sol `/root/sol_schema_review` and Venice Opus 5.5 job `f68e31f4-8149-4d22-9aa3-efacb4fd9c10`. This is not a schema freeze; missing example references and duplicated validator rules remain open. Earlier Opus CI recheck `4803d848-c82b-4902-97d7-feee789a5b7b` and manifest rejected-path job `c682a700-beea-40a8-925c-22b50c58bff5` are also active.
