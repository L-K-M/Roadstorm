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
| 9370f30f-fbd7-42cb-b401-a69ff4d7a2b5 | stepfun/step-5-preview | docs/MACHINE_INVENTORY.md | running; hardware inventory |
| 6058a51e-ae48-4329-8fb0-52c3c36eddad | stepfun/step-5-preview | assets/manifest.json, tools/asset_manifest/ | completed; independent 35-test suite and empty-manifest check passed; real assets and rights validation remain open |
| ec6b876f-cdad-40f3-a154-ff99473a0c54 | longcat/LongCat-2.5 | tools/tick_probe/ | running; tick/query feasibility |

Next: collect and independently verify each job, integrate coherent owned paths, establish tooling/checksum and CI, run acceptance against a frozen candidate, then request separate Opus 5.5 and GPT-6.2 Sol reviews. All review, platform, audio, controls, model training and release gates remain open. Do not infer completion from worker reports or auth readiness.
