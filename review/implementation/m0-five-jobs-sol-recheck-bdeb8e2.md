# M0 early implementation recheck

OpenAI Codex, GPT-6.2 Sol, native OpenAI provider. Review date 2026-11-26. Candidate `bdeb8e24619ba7f833613301df43ffa09b0ce36d`, base `6b571835837dff8e9a25d1696f5622ecf9fa451b`.

**Verdict: changes required.** The original manifest reproductions now fail as expected, and the Godot configuration produced distinct runtime behavior in a backend contrast. The new decoder accepts a manifest containing only JSON `null`. M0 remains open.

## Findings, ranked

1. **Medium — a manifest containing only JSON `null` passes.** At `tools/asset_manifest/manifest_validator.py:510`, the decoder uses `None` as its error sentinel. A valid JSON `null` also decodes to `None`, so the early return at line 614 skips the top-level object check without adding a finding. The candidate CLI returned exit 0 and an empty error array with `--json --check-hashes`. The base passes the decoded value to the object check and rejects it. Use a distinct failure sentinel or distinguish decoder status from its value, and add a null-root regression test.
2. **Low — the toolchain summary still describes an earlier configuration.** `docs/TOOLCHAIN.md:3` describes Python pinning and effective Jolt as unverified. Lines 63–68 describe only the earlier scratch setting and say the project's physics settings were untouched. The candidate pins both versions. The local Python verifier passed and the headless contrast below shows that changing the project pin changes observed physics results. Date the historical observations or update the summary to distinguish established local pins and backend evidence from remaining verification. The Python verifier explicitly leaves its broader upstream artifact status open.

## Prior finding dispositions

| Prior finding | Disposition on candidate |
| --- | --- |
| High — output ownership and cycles | Fixed for the documented path-string rule and dependency graph. Two valid records claiming the same output with correct hashes returned `duplicate-output-path`. A self-loop and a three-node loop returned `dependency-cycle`. Unique claims and an acyclic chain passed. |
| Medium — duplicate JSON members | Fixed for the original cases. A single otherwise valid document with contradictory top-level `registry_status`, nested `rights.license_spdx` and nested `review.status` returned exact `duplicate-json-member` locations for all three. See the new null-root regression above. |
| Medium — toolchain summary and effective Jolt | The publisher archive contradiction and macOS “end to end” wording were corrected. Both projects explicitly select Jolt. Runtime contrast verified the effect of the main project's configuration on this host. The remaining wording discrepancy is recorded above. |
| Low — malformed UTF-8 | Fixed. A one-byte `0xff` input returned exit 1, parseable JSON with `invalid-encoding` at `<manifest>`, and empty stderr. |

## Review evidence

Inspected the prior Sol report and candidate diff for `tools/asset_manifest/manifest_validator.py`, `tools/asset_manifest/tests/test_manifest_validator.py`, `tools/asset_manifest/README.md`, `provenance/MANIFEST_CONTRACT.md`, `docs/TOOLCHAIN.md`, `docs/PYTHON_TOOLCHAIN.md`, `project.godot`, `tools/tick_probe/project.godot`, `tools/tick_probe/README.md`, the three `tools/tick_probe/src/` scripts and the recorded backend contrast check. Executable checks used a `git archive` of the candidate under ignored `work/agents/sol-recheck/` on macOS ARM64.

- `tools/asset_manifest/run_tests.sh` passed 76 tests on Python 3.15.2. `python3 tools/asset_manifest/validate_manifest.py --check-hashes assets/manifest.json` passed the empty checked-in registry.
- A reviewer-written fixture driver in the archive directory reused the candidate's fixture builder and invoked the candidate CLI with `--root --json --check-hashes` against temporary populated manifests. It verified the cases above and required empty stderr for each one.
- `tools/toolchain/verify.sh --deep` exited 0. Installed editor and template digests matched their local pins. The macOS template executed its version probe and printed `4.7.2.stable.official.ed1daf0bf`. The verifier read the recorded upstream comparison.
- `tools/python_pin/verify.sh` exited 0 for the locally installed Python 3.15.2 and matched its recorded local digest. No official archive was passed to the verifier.
- With copies of the candidate's probe scripts, ran `godot --headless --fixed-fps 60 --path backend-a --script res://src/tick_probe.gd -- mode=structural` using the candidate's byte-identical main `project.godot`. All 58 checks passed. The `backend-b` control changed only `3d/physics_engine` to `GodotPhysics3D`. It exited 1 for the expected pin assertion and passed the other 57 checks. The two runs also differed in five numeric physics results, including wall-sweep stop position (Jolt `-1.09974813461304` m, control `-1.09970760345459` m). This tests the effect of selecting the backend through the main configuration.

The recheck used source inspection, local terminal verification, and a headless test harness. Filesystem case aliasing was unavailable on the scratch volume. Publisher archive comparisons were not independently repeated. Full bundle verification, export and platform launches, game behavior, visual and audio behavior, controller operation, rights and release gates were outside this recheck.
