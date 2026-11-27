# M0 CI implementation recheck

**Verdict — changes required.** The hosted run passed, and both remaining findings from my previous review are resolved. Fault injection exposed contradictory reporting and artifact eligibility for a rejected pack. The new Git preflight also lets Validate report a corrupt index as clean.

Reviewer — OpenAI Codex, GPT-6.2 Sol, native OpenAI provider. Review date 2026-11-27. Candidate `8c6c92847a3d9055bf7fb6edd24e2526c16681b1`. Comparison base `245ee1d4a8ae281a526916090f369d913f24b8cf`.

## Findings

1. **Medium — A package that fails inventory is reported as passing and remains eligible for package upload.** `tools/ci/ci.sh:1898–1909` prints PASS and writes `export result=pass` before the pack inventory runs. `tools/ci/ci.sh:1947–1953` writes a second, failing result on rejection. I ran a real Linux export with a delegating engine wrapper that replaced the freshly produced sidecar with 13 bytes immediately after the pinned editor exited 0. The export returned 1, but its console first printed PASS, then reported that the PCK could not be parsed. Its per-run report contained both verdicts. `.github/workflows/ci.yml:385–390` uploads all of `build/` under `if: always()`, so the rejected files remain eligible for `export-packages` whenever this failure occurs in CI. Record one final verdict after inventory and upload packages only after the package verification step succeeds. The log upload can still retain failed-run evidence.
2. **Medium — An unreadable Git index is reported clean.** `tools/ci/ci.sh:934–941` uses `git rev-parse --git-dir` as a repository preflight. This succeeds with an unreadable index. The pipeline and unconditional return in `tools/ci/lib/common.sh:1156–1162` then swallow the actual `git ls-files` failure. In a separate local project fixture with a valid `.git` and a truncated index, `git rev-parse --git-dir` returned 0, `git ls-files tools/ci/out` returned 128, and `ci.sh validate` returned 0 after reporting no tracked build output. Capture and propagate the status of the actual index query before filtering the sentinel.

## Verified fixes

- **Symlink-parent export.** From an isolated caller directory I linked `via` to its sibling `path-elsewhere/inner` and exported the Linux preset using `--out 'via/../package'`. The pinned Godot export returned 0, wrote the main file and PCK to `path-elsewhere/`, and left the caller-side package absent. This reproduces the previously failing command shape with the filesystem-resolved destination. Local engine-backed self-test cases also exercised all three ordinary relative paths.
- **Per-preset evidence and export log artifact scope.** The exact hosted run completed all jobs successfully and built the macOS, Windows, and Linux presets with the pinned Ubuntu editor. The downloaded `export-logs` archive contained 21 files, all under `logs/` or `reports/`, with separate import logs, export logs, per-run reports, and passing pack inventories for all three presets. The artifact size was 16,094 bytes, down from 101,719,222 on the base run. The three inventories recorded zero missing required runtime resources. The package artifact upload reported five files. [Hosted run 45928824558](https://github.com/L-K-M/Roadstorm/actions/runs/45928824558)
- **Provisioning and test continuity.** Hosted output shows pinned engine and template verification, template installation, export preparation, and the 6/6 runtime gate. The checks job's forwarded engine enabled engine-backed tests. The hosted checks job passed 160/160 applicable self-tests and logged the skips for unavailable tools and export templates. The separate hosted export job provided real package and inventory evidence. Local `dash tools/ci/tests/run_tests.sh` passed 186/186, including existing-template preservation, isolated copies, and per-preset exports and evidence. Local `tools/ci/scripts/runtime_error_gate.sh` passed 6/6, including the strict-warning and injected Jolt cases. `actionlint .github/workflows/ci.yml` passed.

## Scope and reproduction

Reviewed `.github/workflows/ci.yml`, `tools/ci/ci.sh`, `tools/ci/lib/common.sh`, the CI self-tests and runtime gate, `tools/export_smoke/lib/pack_inventory.py`, and my prior report. Commands ran against a fresh `git archive 8c6c928` in ignored `work/agents/sol-ci-8c6c928/snapshot` on Darwin ARM64 with Godot `4.7.2.stable.official.ed1daf0bf`. Local artifacts, the isolated Git fixture, fault-injection controls, and logs were written to that review directory. The self-test copied installed templates into a temporary home. The separate export controls read the installed templates through an isolated home. No review command installed or wrote shared templates.

I checked the exact SHA with `gh run view 45928824558 --repo L-K-M/Roadstorm --json headSha,status,conclusion,jobs`, read full logs with `--log`, and downloaded only the `export-logs` artifact for content inspection. Actual R7 workload behavior, package launches on target systems, package archive download and digest verification, and release acceptance remain outside this recheck.

The following commands reproduce the two negative cases with the retained isolated fixtures. Run from the ignored review directory. The wrapper at `controls/godot-corrupt-pck` delegates every call to the installed pinned editor, then writes `printf 'corrupt pack\n' > "$arg.pck"` only after a successful `--export-release` call, where its final argument is the output path.

```sh
review_dir="$(pwd)"
export REVIEW_REAL_GODOT="$(command -v godot)"
HOME="$review_dir/control-home" TMPDIR="$review_dir/control-tmp" \
  snapshot/tools/ci/ci.sh --project "$review_dir/snapshot" \
  --godot "$review_dir/controls/godot-corrupt-pck" \
  --out "$review_dir/corrupt-out" export --export 'Linux x86-64' \
  --out "$review_dir/controls/corrupt-package"
# Exit 1. Console: export: PASS, then package inventory check FAILED.
# Report: export result=pass, then export result=fail reason=pack-inventory.

printf 'invalid Git index\n' > index-control/.git/index
git -C index-control rev-parse --git-dir
# Exit 0. Output: .git
git -C index-control ls-files tools/ci/out
# Exit 128. Output: fatal: .git/index: index file smaller than expected
(
  cd index-control
  TMPDIR="$review_dir/index-tmp" tools/ci/ci.sh \
    --source-sha 8c6c92847a3d9055bf7fb6edd24e2526c16681b1 validate
)
# Exit 0. Console: no tracked build output under tools/ci/out.
```
