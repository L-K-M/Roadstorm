# M0 CI residual and native Windows manifest runner: scoped recheck of fed4f61

**Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party Claude Code CLI. No delegation, helpers or subagents.
**Date:** 2026-11-27
**Candidate:** `fed4f616fc9dbf60904ce4f622aef7d723de7b91`
**CI comparison base:** `482069e4d8b81be26b8bf2a6d38a3d88cb414a79`
**Windows runner comparison base:** `04015cada50ee6c24c36e51378807b8aaa32d38f`

## Scoped verdict

- **CI report publication and `.ci-lock` guards: PASS (scoped).** There are no blocking defects. One minor defect is confirmed (F1): a directory or a symlink to a directory at the report name is not refused, even though the new comment says it is. There are also two test/evidence gaps (F2, F3).
- **Windows manifest runner ID fix: PASS (scoped).** The expected native IDs now equal the IDs discovery reports. All 14 native controls and both critical controls still fail closed.
- **Not verified:** a hosted CI run on fed4f61, a hosted Windows run on this fix, native Windows behavior, platform launch, and full M0. The current CI gate is **not complete**: the known M1 `tests/handling/pure_motor_driver.gd` discovery hang is still open.

## Limits and provenance

- The snapshot directory has no `.git` of its own. Git inside it resolves to the parent Roadstorm repository's object store (`git rev-parse --show-toplevel` returns `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm`).
  - I used only commit objects addressed by SHA (`git show`/`git diff` on fed4f61, c502e4a, 6cb434c and their parents). I did not read live working-tree files as candidate content.
  - I checked that the snapshot is exact: `git hash-object` of each snapshot file equals the blob at `fed4f616…:<path>`. All 11 match: `tools/ci/{ci.sh,lib/common.sh,tests/run_tests.sh,README.md}`, `.github/workflows/{ci.yml,manifest-windows.yml}`, `tools/asset_manifest/tests/{run_windows_manifest_ci.py,test_run_windows_manifest_ci.py,test_manifest_validator.py,__init__.py}`, `assets/manifest.json`.
- I did not rerun the full 235-case shell selftest. I rely on the coordinator's run for that and say so here. I did not run Godot.
- Nothing was written to the snapshot. All probes ran under my scratch `…/opus/tmp/` in `lnprobe1/`, `pubprobe/`, `initprobe/`, `repo-am/` and `vacuous/`. These are left in place for the coordinator.

## Files inspected

- `tools/ci/ci.sh`:
  - outer export: 1760–1927
  - lock precheck and acquire: 1929–1966
  - inner worker: 1980–2300
- `tools/ci/lib/common.sh`:
  - lock fds and watchdog: 74–165
  - reports: 1032–1127
- `tools/ci/tests/run_tests.sh`:
  - new cases: 296–347, 2609–2634, 2899–2936
  - neighbouring cases: 2808–2897
- `tools/ci/README.md`: export row at line 122
- `.github/workflows/ci.yml`: 338–475
- `.github/workflows/manifest-windows.yml`: whole file
- `tools/asset_manifest/tests/run_windows_manifest_ci.py`: whole file
- `tools/asset_manifest/tests/test_run_windows_manifest_ci.py`: the c502e4a diff
- Diffs read: `fed4f61`, `c502e4a`, and `6cb434c --stat`
- Prior reports read:
  - `review/implementation/m0-ci-opus-5-5-482069e.md`
  - `review/implementation/m0-ci-gpt-6-2-sol-482069e.md`
  - `review/implementation/m0-windows-manifest-opus-5-5-04015ca.md`, headings only
  - `review/implementation/m0-windows-manifest-gpt-6-2-sol-04015ca.md`

## Commands run and results

1. **Syntax:** `sh -n` and `dash -n` on `ci.sh`, `lib/common.sh` and `tests/run_tests.sh` all exited 0.
2. **`ln` destination probe** (macOS `/bin/ln`, scratch):

   | Destination already at the name | `ln` exit | What happened |
   | --- | --- | --- |
   | existing directory | 0 | link created **inside** the directory |
   | symlink to a directory | 0 | link created **inside the symlink's target** |
   | dangling symlink | 1 ("File exists") | refused, symlink preserved |

3. **`ci_publish_report_exclusive` probe** (sourced `common.sh`, scratch):
   - With a directory, or a symlink to a directory, at `export-linux-x86-64-<id>.txt`, the helper returned 0 and the caller set `CI_REPORT` to the directory path.
   - The next `ci_report` failed with "Is a directory" and the verdict line was lost.
   - In the symlink case a hard link of the report header was planted in the symlink's target directory, outside `reports/`.
4. **`ci_init_report` probe** (behavior before fed4f61, same primitive): `ROADSTORM_CI_ATTEMPT_ID=FIXEDID ci.sh --project <scratch> --out <scratch> pin`, with a directory pre-created at `reports/pin-FIXEDID.txt`.
   - It exited 0 and printed `[ci] report: …/pin-FIXEDID.txt`, which is the directory.
   - The body was left as `pin-FIXEDID.txt/.ci-report-body.*`.
5. **Vacuity probe:** the two helper-level selftest bodies (regular-file and dangling-symlink cases) report `yes` even when `ci_publish_report_exclusive` is not defined at all.
6. **Windows runner on macOS** (scratch copy of `tools/asset_manifest`, `assets/manifest.json` and `provenance/`; Python 3.15.2; `PYTHONDONTWRITEBYTECODE=1`; scratch `TMPDIR`):
   - `run_windows_manifest_ci.py` exited **1**.
   - Suite: 211 run, 197 passed, 0 failed, 0 errors, 14 skipped.
   - The runner reported 14 native expected, 2 critical required, 0 native passed, the shipped `--check-hashes` PASS, and "Windows acceptance NOT established".
   - The first attempt had 5 errors only because my scratch copy lacked `provenance/PROVIDER_TERMS.md`. Adding it resolved them.
7. **ID equality:** `native_control_ids(tests.test_manifest_validator.WindowsNativeGuardTestCase)` gives 14 expected IDs. They equal the 14 discovered `…WindowsNativeGuardTestCase.*` IDs exactly, the 2 critical IDs are a subset, and the only module prefix is `tests.test_manifest_validator`. 211 IDs were discovered in total.
8. **Regression discrimination:** I replaced `runner.load_test_module` with the old bare `import test_manifest_validator` and ran `RunnerNamespaceTestCase`. 3 of 5 cases fail:
   - `test_expected_ids_equal_prefixed_discovery_ids`
   - `test_prefixed_discovered_successes_clear_the_verdict`
   - `test_windows_success_path_returns_zero_from_main`

   The two negative controls still pass, as they should.

## Ranked findings

### Implementation defects

**F1 (minor, confirmed): directory and symlink-to-directory destinations are not refused.**
- **Where:** `tools/ci/lib/common.sh:1112-1127`, called from `tools/ci/ci.sh:1842-1847` (outer path) and `tools/ci/ci.sh:1998-2003` (direct inner path).
- **The claim:** the comment at `common.sh:1114-1115` says `ln` "fails … when a regular file, directory or dangling symlink occupies the name."
- **What actually happens:** POSIX/BSD/GNU `ln src dst` without `-n`/`-T` treats an existing directory, or a symlink that resolves to one, as a target directory. It succeeds (commands 2 and 3).
- **Consequences:**
  - `CI_REPORT` becomes the directory path.
  - Every later `ci_report` fails, and the export's verdict lines are lost. The `[ci] report:` line names a directory.
  - With a symlink to a directory, a report-header hard link is written outside `reports/`.
  - The exit status is still correct, and nothing is overwritten.
- **The same primitive exists before fed4f61** in `ci_init_report` at `common.sh:1084` (confirmed by command 4).
- **Reachability:** an occupant needs a name built from the mktemp-random attempt ID, or a reused fixed `ROADSTORM_CI_ATTEMPT_ID`. So this is low-likelihood, and not a regression in the competing-file or dangling-symlink scenarios the coordinator asked about.
- **Fix:** add `[ -d "$dst" ] && return 1`, or publish from inside the reports directory with `ln -n`/`-h` semantics. Correct the comment either way.

### Test and evidence gaps

**F2 (minor): two of the five new selftest cases are vacuous, and the new tests miss F1.**
- The regular-file case at `tools/ci/tests/run_tests.sh:308-320` and the dangling-symlink case at `run_tests.sh:322-333` use `if helper; then :; elif <preserved>`. They pass when the helper is missing or always returns 1 (command 5).
- They only show that the helper is non-destructive. They do not tie its behavior to the call sites.
- The other three cases do discriminate the old code:
  - the coherence case at `run_tests.sh:335-347` needs a successful hard link that shares an inode;
  - the direct-inner namespace case at `run_tests.sh:2609-2634` fails against the old concatenated guard, because `name.exe.ci-lock` plus `name.exe.pck` ends in `.pck` and the old code would create a lock file;
  - the publication-race case at `run_tests.sh:2899-2936` fails against the old `mv`, because the `ln` shim never fires and `mv` places the report at the renamed path.
- No case covers a directory at the report name, which is how F1 went unnoticed.

**F3 (minor): hosted CI does not require the two new engine-backed cases by name.**
- The required-needle list at `.github/workflows/ci.yml:369-401` does not include:
  - "a direct __export-inner namespace destination is refused before locks, writes or engine"
  - "a report path claimed at publication time is not replaced"
- The suite's overall PASS still covers them whenever they run, because they sit inside the same template-gated block that the skip checks guard. But a future change that silently stops running them would not be caught by name.

### Optional improvements and residual items carried forward from the 482069e reviews

- **O1: publication failure is silent.** When `ci_publish_report_exclusive` fails (`ci.sh:1844`, `:2000`), the export carries on under the generic name with no warning and no report line. A foreign file at `export-<slug>-<this-attempt-id>.txt` then sits beside this attempt's real report, which may carry the opposite verdict.
  - The `[ci] report:` line correctly names the generic path, and nothing is borrowed or overwritten.
  - A consumer keyed on the preset-specific name could still be misled. Adding a `ci_warn` plus a `report-publication=failed` report line would make this explicit. Failing closed would be stricter.
- **O2: the package artifact still uploads lock files.** The upload step at `.github/workflows/ci.yml:467-472` still uploads all of `build/`, including the persistent `*.ci-lock` files. This is open from the 482069e reviews (Sol P2 #5, Opus F6). It is low severity: the files are empty coordination files, not package content.
- **O3: inherited report metadata is trusted from the environment.** `ROADSTORM_CI_REPORT` is honored from the environment for any invocation (`common.sh:1045-1048`). This is the second half of Sol 482069e P2 #4. The first half, the missing locks on direct `__export-inner`, is fixed: the worker acquires its own locks at `ci.sh:2061-2085`. Low risk, since a caller who controls the environment can already write wherever it likes.
- **O4: worker exec path (Opus 482069e F4).** The worker is now run as `"$CI_TOOLS_DIR/ci.sh"` (`ci.sh:1915`) rather than `$0`. That relies on the executable bit, which git records (100755). Running it with `sh` would also cover checkouts that drop the mode.

## Verified behavior in the requested focus

**CI**

- **Create-only publication on both paths:** both the outer path (`ci.sh:1842-1847`) and the direct inner path (`ci.sh:1998-2003`) now publish with `ln`.
  - A competing regular file or dangling symlink is refused byte- and link-exact, and the generic report stays the single visible path.
  - In the normal flow the inner worker gets the already-published name through `ROADSTORM_CI_REPORT`, so `src == dst` and it is a no-op.
  - After a failed outer publication, the inner worker's retry is refused the same way. Parent and worker therefore keep one coherent pointer.
  - On success, both names share one inode, so verdicts cannot contradict each other. Two paths with identical bytes are uploaded, as the README documents.
- **Reserved `.ci-lock` namespace:** the main output and the derived sidecar are now checked separately on both the outer path (`ci.sh:1864-1879`) and the inner path (`ci.sh:2018-2033`). On the inner path both checks run before the lock precheck, `exec 9>>`, the project copy and the engine.
  - The sidecar check cannot currently fire, because the sidecar always ends in `.pck`. It is harmless defense in depth.
- **In-process advisory lock lifetime:** unchanged by fed4f61 and consistent with the README.
  - The fds are opened in the worker shell (`ci.sh:2062`, `2073`) and released by the EXIT/INT/TERM/HUP traps.
  - The engine child keeps the fds on purpose.
  - The watchdog closes them before `sleep` (`common.sh:153-159`).
  - The lock-timeout verdict is now structured (`ci.sh:1957-1962`), which closes Opus 482069e F2.
- **Attempt identity:**
  - The report body is reserved with `ln` (`common.sh:1065-1091`).
  - The inventory name carries the slug, the SHA tag and the attempt ID (`ci.sh:2207-2215`).
  - The checker creates its report exclusively. Failure records and the PASS companion are mktemp-exclusive and carry `attempt_id` and the full `source_sha` (`ci.sh:2226-2288`).
  - Attempt-specific log and copy bases (`ci.sh:1906-1908`) close Sol 482069e P1 #2.
- **Other 482069e findings:**
  - Sol P1 #1 (lock namespace): closed.
  - Sol P1 #3 and Opus (report reservation): closed, apart from F1.
  - Sol P2 #6 and Opus F1 (failure printer): restored at `ci.sh:1972-1978`.

**Windows**

- **The ID fix:** `load_test_module` now imports `tests.test_manifest_validator`, the same dotted name discovery uses. Previously it imported the bare `test_manifest_validator`. It is one module object (`run_windows_manifest_ci.py:172-189`), and `tools/asset_manifest/tests/__init__.py` exists.
  - The repository-root `tests/` has no `__init__.py`, and a regular package takes precedence over a namespace portion, so `tests` resolves to the asset-manifest package.
- **Fail-closed behavior on this Mac:** all 14 native controls fail closed. They are reported as skipped, as missing from the passed set, and, for both critical IDs, as critical controls that did not run. The runner exits 1.
- **The positive simulation does not count as native acceptance.** `test_windows_success_path_returns_zero_from_main` mocks `run_suite` and redirects stdout and stderr, so its "[ok] … Windows acceptance recorded" line never reaches the hosted log. Acceptance in the hosted job still comes only from the real discovered suite in `main()`.
- **Forged-ID hazard removed:** `_FakeNative` used to be a module-level `TestCase` with a forged `__module__`/`__qualname__`. Discovery could have counted its trivial passes as the real critical IDs. It is now function-local, so that can no longer happen.
- **Outside this review:** the hosted Windows run for this fix is pending, and I make no claim about it. The provider-rights item is out of scope.