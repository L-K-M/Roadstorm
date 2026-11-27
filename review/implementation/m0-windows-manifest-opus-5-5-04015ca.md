# M0 Windows asset-manifest gate: independent Opus review of 04015ca

**Verdict: pass** for the bounded native Windows guarded-read gate. The pass has low follow-ups. The main one is documentation that still says the Windows branch is unverified (L1).

| | |
|---|---|
| Reviewer | Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, run through Claude Code |
| Date | 2026-11-27 |
| Candidate | `04015cada50ee6c24c36e51378807b8aaa32d38f` (immutable) |
| Base | `dd0628b29ca7f5379732e2de30395da300c90185` |
| Method | Static review of the exact candidate via `git show`/`git diff` plus the read-only hosted log. Not delegated. I did not read the other reviewer's current report. |

## Scope

This review covers only the native Windows manifest gate:

- `tools/asset_manifest/manifest_validator.py`
- `tools/asset_manifest/tests/test_manifest_validator.py`
- `tools/asset_manifest/tests/run_windows_manifest_ci.py`
- `tools/asset_manifest/tests/test_run_windows_manifest_ci.py`
- `.github/workflows/manifest-windows.yml`
- the Windows sections of `tools/asset_manifest/README.md`
- the related `docs/STATUS.md` lines

It does not cover desktop game launch, export smoke, the separate `ci` workflow (broken at this SHA and cancelled, not counted), or provider/rights terms adequacy.

## Capabilities and limits

- **What ran:**
  - `git log`/`git diff --stat dd0628b..04015ca`
  - `git diff` of the validator
  - `git show 04015ca:<file>` for every file in scope and for the prior `dd0628b` Opus and Sol reports
  - `git grep` of docs and provenance
  - `grep` of `work/agents/coordinator/windows-04015ca-hosted.log`
- **What was blocked:** this session's permission mode denied, without prompting:
  - `git archive` into my scratch directory
  - shell redirection of `git show` output
  - `python3` execution, including a stdlib-only probe
  - `gh run view 46005883236`
- **Consequences:**
  - I ran **no** local suite. I have no independent `gh` confirmation of the run.
  - Every Windows behaviour claim below comes from the hosted log or from static reasoning. I did not manufacture any Windows execution.
  - My scratch directory `work/agents/2b5ec17c-b275-4439-baa7-17895ac0b066/src` was created and is empty.

## Hosted evidence checked (log, not re-executed)

| Item | Value |
|---|---|
| Checkout | fetched `+04015cada50ee6c24c36e51378807b8aaa32d38f`; `HEAD` printed as the same SHA |
| Host | Windows Server 2025 10.0.26100, image `windows-2025-vs2026` 20261123.321.1 |
| Interpreter | Python 3.12.10 |
| Suite | `186 run, 173 passed, 0 failed, 0 errors, 13 skipped` |
| Native tests | `native guarded-open tests expected: 9` / `executed and passed: 9` |
| Runner verdict | `[ok] all native guarded-open tests ran and passed` |
| Shipped manifest | `--check-hashes` exit 0, `PASS (0 error(s), 0 warning(s))` |

All 13 skips sit outside `WindowsNativeGuardTestCase`. Each is justified:

- **5 Unix mode-000 controls.** Each has a native ACL counterpart:
  - manifest → `test_native_unreadable_manifest_exits_2_with_json`
  - output text and CLI JSON → `test_native_unreadable_output_is_structured_not_a_traceback`
  - register ×2 → `test_native_unreadable_register_is_rejected_before_any_read`
- **6 FIFO cases.** No Windows equivalent exists.
- **2 POSIX-flag-only controls.** On Windows `_guarded_open_flags` is never consulted, and `WindowsGuardedOpenTestCase` covers that branch with a fake WinAPI.

This matches the coordinator's summary.

## Assessment against the scoped checks

- **CreateFileW guarded read** (`manifest_validator.py:565-745`, dispatch at `:761-762`): sound.
  - The open uses `OPEN_EXISTING | FILE_FLAG_OPEN_REPARSE_POINT` with GENERIC_READ and full sharing.
  - It rejects a reparse leaf or a directory using the handle's own `FileAttributeTagInfo`.
  - It requires `GetFileType == FILE_TYPE_DISK`.
  - `open_osfhandle(O_RDONLY|O_NOINHERIT)` transfers ownership. The `finally` closes the raw handle exactly once, only when `descriptor is None`, and the `is None` test is correct for descriptor 0.
  - If the adapter cannot be built, the open fails closed (`:714-720`). There is no unguarded fallback.
  - Natively, the positive control passed: a real digest and an anchored register read, which was the prior Sol L1 regression on `dd0628b`. That finding is now resolved.
- **Reparse, junction and symlink handling** (`:470-510`): sound.
  - `_component_is_link` adds the `st_file_attributes & FILE_ATTRIBUTE_REPARSE_POINT` check, so junctions are caught where `is_symlink()` is False on 3.12.
  - `test_native_junction_parent_is_refused` discriminates. It records the outside file's real digest, so reading through the junction would match the hash and lose `missing-file`. It also asserts that nothing was written through the link. It passed natively.
  - `test_native_swap_at_the_pre_check_seam_is_still_refused` discriminates too. Dropping `FILE_FLAG_OPEN_REPARSE_POINT` or the reparse-attribute check would produce a non-`None` digest.
- **Parent swaps and residual TOCTOU:** honestly documented in the README limitation, the `_windows_open_regular_descriptor` docstring (`:707-711`) and the `digest` docstring (`:907-910`). Intermediate components are still resolved by name and no parent-handle walk exists. This is accepted residual risk, not a finding.
- **ACL denial:** sound. `os.access(R_OK)` on Windows does not evaluate ACLs, so the refusal in the native output test must come from the guarded `CreateFileW` failing. That test asserts exactly `["missing-file"]`, exit 1 and empty stderr, so it is real evidence that ACCESS_DENIED maps to a structured finding. The ACL helper skips the test if `icacls` fails, and a skip there fails the runner, so it fails closed. Cleanup ordering (deny removed before the tempdir is deleted) is correct.
- **Oversized JSON integers:** the native CLI test (exit 2, `invalid-json`, empty stderr) passed.
- **Native requirements and skip policy** (`run_windows_manifest_ci.py:158-221`): sound for the current suite.
  - The runner fails on:
    - any failure or error anywhere;
    - any skip inside the native class;
    - an absent native class;
    - any native method missing from the passed set;
    - either critical control missing;
    - a non-zero or non-PASS shipped `--check-hashes`.
  - Failure details are printed before the verdict.
  - `test_run_windows_manifest_ci.py` covers each policy branch with fabricated results.
- **Workflow** (`manifest-windows.yml`): sound.
  - `windows-latest`, Python 3.12, `contents: read`, a 15-minute timeout and concurrency cancel.
  - It runs only the runner.
  - It deliberately bypasses `tools/ci/ci.sh`, as its header documents.

## Actionable findings (ranked)

**L1 (low): documentation and docstrings still say Windows is unverified, and the README does not mention the new gate.**

At `04015ca`, the following text still says the branch is unverified or that Windows is blocked:

- `README.md` (in `tools/asset_manifest/`), Limitations bullet at `:332-348`: "implemented but unverified on a real host … No claim of Windows support is made until those run on a Windows host."
- Disposition at `:506-518`: "Not verified on a real Windows host … each needing a Windows runner the coordinator owns".
- `:550-551`: "Native Windows execution remains blocked on a Windows host".
- `manifest_validator.py:576`: "Not exercised on a real Windows host yet".
- `manifest_validator.py:711-712`: "Not verified on a real Windows host."
- The `WindowsNativeGuardTestCase` docstring: "until a Windows runner executes them, the branch stays unverified".

The README "Limited CI wiring" bullet does not mention `manifest-windows.yml` or `run_windows_manifest_ci.py`.

The stale text understates rather than overstates, so it is safe. Still, the gate's own record contradicts the evidence used to accept it. The fix:

- Describe the workflow and runner policy.
- Record the native acceptance. The hosted run ID belongs in STATUS or review evidence, not in the committed source.
- List what stays open:
  - parent-swap TOCTOU
  - long `\\?\` paths
  - sharing-violation opens
  - non-NTFS and ReFS volumes
  - Python versions other than 3.12

**L2 (low): skips outside the native class are allowed without an allowlist, and the runner docstring undercounts them.**

- `run_windows_manifest_ci.py:20-21`: the docstring says the allowed Windows skips are "the six FIFO cases". The run actually allowed 13: 6 FIFO, 5 mode-000 and 2 POSIX-flag controls.
- `assess` (`:171-175`) accepts any non-native skip.

Today every skip is justified, as tallied above. The risk is a future change: a cross-platform security control that starts skipping on Windows, for example a `skipIf` added to a junction or fake-WinAPI test, would pass the gate silently. The fix is to pin the expected non-native skip set, or at least its count and reasons, and fail on drift. The docstring should be corrected either way.

**L3 (low, plausible, static only): Windows path aliasing is admitted by the path spelling check.**

`_path_spelling_error` (`manifest_validator.py:407-425`) rejects only a leading `X:`, so these spellings pass:

- `:` later in a path, for example `assets/a.png:s`, which names an NTFS alternate data stream;
- components ending in `.` or space, for example `assets/a.png.`, which Win32 normalises to `assets/a.png`.

On Windows these can resolve to, and hash, a stream or an alias of another entry's file. That would weaken the "exactly one owning entry per output path" rule. On POSIX the same spellings simply give `missing-file`, so the problem is Windows-only and fails open only there. Case aliasing is already acknowledged in the README ("Cross-platform path case sensitivity is not simulated").

The fix is to reject `:` anywhere, components with a trailing `.` or space, and reserved device basenames in the spelling check. The check is pure and platform-independent, so the rejection is cheap. I did not execute this, because Python was unavailable to me.

## Optional improvements (non-blocking)

- **Narrow the reparse rejection.** `_component_is_link` and the handle check (`:733`) refuse *every* reparse point. That includes non-link tags: OneDrive or cloud placeholders, dedup files and Windows-container WCI layers. A checkout in such a location would report every output as `symlinked-path`. That is fail-closed but misleading. Consider rejecting name-surrogate tags only (`st_reparse_tag & 0x20000000`, handle `dwReparseTag`), or document the limitation.
- **Fail closed on `lstat` errors.** `_component_is_link` returns False on any `lstat` `OSError` (`:484-487`). It would be stricter to return True except for `FileNotFoundError`/`NotADirectoryError`. Later checks would almost certainly refuse such a path anyway.
- **Catch non-`OSError` exceptions from the adapter.** In `_windows_open_regular_descriptor`, non-`OSError` exceptions (`ctypes.ArgumentError`, `OverflowError` from `open_osfhandle`) still escape as tracebacks after the handle is closed. Catching `Exception` → `None` would keep the "never a traceback" contract.
- **Make the native register-ACL test non-vacuous.** `all(descriptor is None for …)` is True when no guarded open was attempted. Asserting the specific path, either refused before the open or the open attempted and returning `None`, would make the name "rejected before any read" checkable.
- **Workflow hardening:**
  - pin `actions/checkout` and `actions/setup-python` by commit SHA;
  - widen the `paths` filter to `provenance/**`, since `rights_holder_record` resolves there (no effect while the registry is empty);
  - consider a second Python version.
- **Pre-existing, not Windows-specific:**
  - Deeply nested JSON raises `RecursionError` from CPython's C decoder (a `RuntimeError`, not a `ValueError`), so `_decode_manifest_document` (`:990-1002`) would leak a traceback instead of `invalid-json`/exit 2. This is inferred from CPython's scanner; I did not execute it.
  - The manifest read (`:1401`, `read_bytes`) and register read (`:811-817`) are unbounded in size.
  - The manifest path is an operator-supplied CLI argument and is not routed through the guarded open. That is acceptable, because the guard covers root-relative records and hash files, as the README states.

## Missing evidence

- No independent `gh run view 46005883236` (denied here); I relied on the coordinator's log file.
- No local execution of the candidate suite (denied here). The coordinator's Mac result of 186 tests with 9 native skips is not independently re-run by me.
- No native coverage for:
  - the `FILE_TYPE_DISK` refusal (unreachable without a race, because the pre-check's `is_file` refuses device names first);
  - long paths;
  - sharing violations;
  - non-NTFS volumes.

These are acceptable residuals for this bounded gate but should stay listed.

## Verdict

**Pass.** The native Windows guarded-open implementation and its gate meet their scoped acceptance:

- 9/9 native tests ran and passed on a real Windows host at the exact SHA, including discriminating junction, seam-swap and ACL controls.
- The skip policy fails closed on native skips.
- The shipped empty manifest passes `--check-hashes`.

L1 should be fixed when STATUS records the acceptance. L2 and L3 are low follow-ups and do not block this gate.
