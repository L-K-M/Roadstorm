# M0 second-developer setup exercise — 2026-11-27

**Decision:** The setup guide's required local exercise passed on the pinned Apple Silicon macOS host. Whole M0 remains open. This is an independent second-agent exercise of a committed source baseline, not a target Linux launch, a rights clearance or a gameplay test.

| Input | Exact identity |
| --- | --- |
| Product source | `a5ba7a41f836e9ac451c3e0348015128a8cb2c8e`, tree `4daf9b0f854802de0bcc8db04a1859cf75773ed8` |
| Exercised guide | `docs/SETUP.md` from `24585b7ec901a4f4f4cef4156f2971a92443a39e`, blob `6affac079b64e58aa163c55c0fb6ee2566a25905` |
| Exerciser | Separate Pi direct LongCat 2.5 job `c58de8a3-6260-4e4b-a6d5-eebe5cdfcf21` |
| Engine | Pinned Godot `4.7.2.stable.official.ed1daf0bf`, SHA-256 `c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf`; built-in Jolt |

The agent exported `a5ba7a4` with `git archive` and overlaid only the committed guide into its ignored job directory. The implementation procedure forbids a second clone/worktree, so it did not execute the guide's `git clone` line; it checked the archive against the source commit instead. The agent reported 1,107 non-guide blob matches and no mismatches. The coordinator independently recomputed all 1,107 Git blob hashes and the guide blob hash, with no mismatch. Local toolchain and installed templates were read, without installing or downloading anything.

| Exercised step | Result |
| --- | --- |
| Pin, editor/template and Python checks | Exit 0; `toolchain/verify.sh`, `--deep`, `python_pin/verify.sh`, `ci.sh pin` and `version` passed |
| Headless import and validation | `ci.sh import`, `validate`, and `all` each exited 0; one known nested `tools/tick_probe/project.godot` warning was surfaced |
| Passing boot/test | `ci.sh test` found and passed two checks; `run_boot_smoke.sh` exited 0 and reached the placeholder menu |
| Deliberately failing check | `run_boot_smoke.sh --expect-failure` exited 1 with its intentional assertion marker; `ci.sh test` also observed the required nonzero probes |
| Desktop smoke export | `ci.sh export --export "Linux x86-64"` exited 0; package inventory `PASS`, two nonempty components, 53/53 pack-entry MD5s, no development-only paths or missing required runtime resources |
| Existing-output refusal | A repeated export to the same destination exited 1 without changing either package SHA-256 |

The exported Linux main binary is 73,519,416 bytes, SHA-256 `d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63`. Its 162,400-byte `.pck` is SHA-256 `887d58b8c9179c37b682e829a1fb9035167bd37073a160652f2271542003b3ce`. The coordinator independently hashed both retained files, inspected the inventory verdict and read the command/exit table and failing-check log. Raw logs, report and packages remain under the ignored `work/agents/c58de8a3-6260-4e4b-a6d5-eebe5cdfcf21/` directory. The agent also checked 15/15 local guide links and the named paths; no exercised command-form drift was found.

This verifies the guide's M0 acceptance *exercise* on the available host. The Linux package was not launched on Linux. The exercise did not run the install/download paths, GUI or macOS export-smoke launcher, full capture, or real controller/audio review. `validate` reports a content-contract inventory; it does not implement T09/T15 content validation. M0.2 typed runtime resources, M0.3 provider/output rights OI-02/OI-03, M0.4 overall and whole-M0 dual acceptance remain open. The empty asset registry does not clear future creative assets.
