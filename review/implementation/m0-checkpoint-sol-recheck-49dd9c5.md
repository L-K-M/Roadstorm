# M0 checkpoint implementation recheck

**Verdict — changes required.** The three findings from my previous review are resolved in local checks. The committed Actions workflow fails validation. Its export job also lacks template setup.

Reviewer — OpenAI Codex, GPT-6.2 Sol, native OpenAI provider. Review date 2026-11-27. Candidate `49dd9c5b2b5f321be9550e2336c6495d04395208`, committed 2026-11-27T00:44:26+01:00. Comparison base `15faf0d572c1fd917b680a123f431c7086806227`.

## Findings

1. **High — GitHub Actions rejects the workflow.** `.github/workflows/ci.yml:238` calls `hashFiles` in the export job's `if`. Actionlint 1.7.12 rejects the expression because that function is available at step level. The condition exists in the base and blocks the entire candidate workflow, including the new gate. Remove the obsolete job-level condition now that the presets are checked in, or move file detection to a step after checkout.
2. **High — Export preparation cannot pass on a fresh runner without templates.** `.github/workflows/ci.yml:242–271` installs the editor and immediately calls `export --check`. The job has no template provisioning step. On the archive snapshot, pointing `GODOT_TEMPLATES_DIR` at an empty directory returned 1 and reported each platform template missing, even though all three presets were recognized. The base has the same setup gap. Provision and verify the pinned export templates before the check.
3. **Medium — Fragment validation still reads a rejected register path.** At `tools/asset_manifest/manifest_validator.py:799–804`, the fragment checker calls the path validator and then reads the register without checking that validation succeeded. The path validator reports symlinks and non-files, but the subsequent read can still follow the symlink or open a special file. Return before reading rejected paths. This is a static finding.
4. **Low — Strict warning failures leave a passing per-check record.** At `tools/ci/ci.sh:910–914`, the check logs and records PASS and increments its pass counter before invoking the strict warning gate. An unexpected warning therefore yields a passing per-check record and a failed test stage. Decide the per-check outcome before emitting the verdict and updating the counters. The runtime regression test confirmed the stage exits 1 as intended.
5. **Low — A failing check skips the warning summary.** The workflow's warning watch at `.github/workflows/ci.yml:144` runs under the default success condition. A Jolt warning detected by the test stage fails that stage and skips the summary intended to surface it. The failing test still prints the warning and the artifact upload remains eligible. Run the summary when earlier stages fail if captured logs are available.

## Previous findings

- **Resolved — Provider snapshot requires a route directory.** The manifest tests reject a file directly below `provenance/provider_terms/`, nested paths, directories in place of files, fragments on snapshots and symlinked route directories. They accept a correctly placed route snapshot.
- **Resolved — Register fragments must identify recorded rows.** The manifest tests reject invented, wrongly cased and empty fragments and accept an exact route in the candidate's register. A register reference may omit the fragment under the documented contract.
- **Resolved — Smoke settings output matches the outcome.** The boot smoke prints the confirmation only when the settings check adds no failures. A separate run with `Jolt Physix` returned 1, printed the settings error and omitted the confirmation.

## Scope and evidence

Reviewed `.github/workflows/ci.yml`, `tools/ci/ci.sh`, `tools/ci/lib/common.sh`, `tools/ci/scripts/runtime_error_gate.sh`, `tools/ci/tests/run_tests.sh`, `tools/ci/warnings.allow`, `export_presets.cfg`, `tools/asset_manifest/manifest_validator.py`, its tests, `tools/smoke/boot_smoke.gd` and my previous report. Tests ran from a `git archive` of the candidate under ignored `work/agents/sol-ci-recheck/` on Darwin ARM64 with Godot `4.7.2.stable.official.ed1daf0bf` and Python 3.15.2.

- `tools/asset_manifest/run_tests.sh` passed 115 tests. `python3 tools/asset_manifest/validate_manifest.py --check-hashes assets/manifest.json` passed the checked-in empty registry.
- `tools/smoke/fault_injection.sh` passed 8 of 8 cases. The separate `run_boot_smoke.sh --project <typo-copy>` control confirmed the failure output described above.
- `tools/ci/tests/run_tests.sh` passed 86 of 86 cases. `tools/ci/scripts/runtime_error_gate.sh` passed 6 of 6 cases. Both injected runtime errors returned CI exit 1 despite Godot exiting 0. The ordinary warning produced exit 0 and a diagnostic. Strict mode and the injected Jolt warning each produced exit 1.
- `tools/ci/ci.sh export --check` returned 0 with the locally installed templates and 1 with an empty template root. `tools/ci/ci.sh export --list-presets` piped to the workflow's Bash tab reader returned the expected three platform labels, including `Windows Desktop`, which now selects `.exe`.
- `actionlint .github/workflows/ci.yml` rejected the job-level expression and reported an unused `section` variable in the export loop.

Hosted execution, actual exports and target launches were outside this recheck. The injected warning exercised log handling. R7's underlying Jolt condition, M0 acceptance, rights, game behavior, release and hardware verification remain open.
