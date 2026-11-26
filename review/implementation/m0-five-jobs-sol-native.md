# M0 early implementation review

Independent reviewer: OpenAI Codex, GPT-6.2 Sol (native). Date: 2026-11-26. Candidate `6b571835837dff8e9a25d1696f5622ecf9fa451b`, base `0ea596a4fa85ade19375e130313f020ed6010619`.

**Verdict: changes required.** The placeholder shell and deliberate failure passed their respective checks. The selected installed toolchain artifacts passed the local verifier. Update the contradictory toolchain evidence and fix the manifest validator defects below before depending on these checks. M0 acceptance remains open.

## Scope and methods

Inspected the scoped changes in `.gitignore`, `project.godot`, `scenes/`, `src/boot/`, `tools/smoke/`, `tools/toolchain/`, `tools/asset_manifest/`, `assets/manifest.json`, `docs/STATUS.md`, `docs/TOOLCHAIN.md`, and `docs/evidence/`. Reviewed the relevant contracts in `PLAN.md`, `plan/IMPLEMENTATION.md`, `docs/TECHNICAL_DESIGN.md`, `docs/ASSET_PRODUCTION.md`, and `docs/BENCHMARKS.md`. All executable checks used a `git archive` snapshot in ignored scratch on macOS ARM64.

- `godot --headless --path . --script res://tools/smoke/boot_smoke.gd` exited 0, observed boot-to-menu on frame 4 and loaded the game scene on frame 5. Appending `-- --expect-failure` exited 1.
- `godot --headless --path . --editor --import` exited 0. A reviewer-created dummy resource in the snapshot initially produced engine errors despite exit 0. After moving the fixtures out of Godot's scan, the repeat exited 0 with no logged errors or warnings.
- `bash -n tools/toolchain/verify.sh` and `tools/toolchain/verify.sh --deep` exited 0. The editor version and recorded local digests matched, and the macOS release template binary printed the expected version. The archive digest comparisons were inspected as recorded coordinator evidence.
- `tools/asset_manifest/run_tests.sh` passed all 35 tests under Python 3.15.2. `python3 tools/asset_manifest/validate_manifest.py --check-hashes assets/manifest.json` exited 0 with an empty release asset registry. Additional Python fixtures exercised contradictory JSON, lineage, output ownership and invalid encoding.

## Findings

1. **High — ambiguous populated manifests can pass verification.** `tools/asset_manifest/manifest_validator.py:593`–`:622` tracks unique IDs only. The dependency check at `:1181`–`:1199` checks membership only. Two individually valid fixture entries with distinct IDs, the same output path and correct hashes, and dependencies on each other yielded zero findings with hash verification enabled. As a result, provenance for a file can have two owners and the lineage cannot be traversed as a production dependency order. Define the output ownership rule, enforce it across entries, and reject direct and indirect dependency cycles with fixture tests.
2. **Medium — duplicate JSON members silently overwrite metadata.** `tools/asset_manifest/manifest_validator.py:477` accepts Python's default duplicate-key handling. A fixture with successive `registry_status` values of `empty` and `populated` passed hash-enabled validation, although the first value contradicts the records. Detect duplicate members during decoding and emit a validation finding, including for nested rights and review fields.
3. **Medium — the toolchain summary contradicts the recorded evidence.** `docs/TOOLCHAIN.md:3`–`:8` says the digests were not confirmed against official releases, while `:95`–`:97`, `docs/evidence/godot-4.7.2-archive-verification.md:8`, and `tools/toolchain/pin/engine.txt:39` report confirmed selected archive members. Update the opening summary and qualify the “end to end” macOS wording at `docs/TOOLCHAIN.md:122` to name the executed template version probe. Keep full bundle verification, export and platform launch open. The project itself also has no explicit 3D backend selection in `project.godot:26`–`:29`. Module strings and an accepted setting in a scratch project do not establish the effective backend in the candidate. M0.1 still needs explicit settings and a runtime backend check alongside the Python pin.
4. **Low — malformed UTF-8 bypasses the CLI's result format.** The read path catches `OSError` only at `tools/asset_manifest/manifest_validator.py:467`–`:475`. A one-byte invalid UTF-8 manifest passed to `--json` returned exit 1 with a Python traceback on stderr and no JSON. Catch decoding failures and return a structured finding, including under `--json`.

## Review limits

Capabilities exercised here were source review, terminal checks, and headless Godot on the local Mac. The game scene was loaded directly by the smoke script. Visual rendering, controller interaction, audio, gameplay, tick fidelity, export, target-platform launch, rights, and release gates were not verified. M0 CI and the checks owned by other jobs were outside this review. The current smoke script verifies scene handoff and placeholder node presence. Godot errors that leave those conditions intact can escape the check, so later CI should independently surface engine errors.
