# M0.1 independent Python verifier recheck

**Verdict — changes required.** The recorded-build bypasses are repaired. The new identity check rejects otherwise valid interpreters on hosts where the recorded Homebrew pathname does not exist.

| Item | Scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `43b667b62ec5546c07fb8504b6cbef1b0eb824c7`, committed 2026-11-27 05:26:38 +01:00 |
| Base | `fb86fc3a006a4c2351a9ca463fa04b6a1c2af4ba` |
| Review date | 2026-11-27, Europe/Zurich |
| Inputs | `tools/python_pin/**`, `docs/PYTHON_TOOLCHAIN.md`, and the earlier Sol and Opus reports on fb86fc3. |

## Findings

1. **Medium · A nonexistent baseline pathname prevents use of a valid pinned interpreter at a different path.** My private two-file reproduction starts with a working pinned alternative at a different path. With the unrelated baseline file present, the alternative exits 0 and prints the documented not-compared warning. After removing only the private baseline pathname, the identical command exits 1 with `not compared (equivalence undetermined)`. The code treats positive evidence of an absent candidate identity as the same situation as inability to inspect an existing comparator. The committed baseline is a Homebrew Cellar pathname and is ordinarily absent on Windows, Linux, and macOS hosts using another install. Distinguish a baseline path known to be absent from an existing comparator whose identity cannot be read. Preserve the fail-closed outcome when equivalence is genuinely indeterminate and the comparator could exist. Test both a missing baseline file and missing baseline parent path. [Identity check](../../tools/python_pin/verify.sh#L427) · [Different-path behavior](../../docs/PYTHON_TOOLCHAIN.md#L245)
2. **Resolved · Recorded and unresolved executable paths are classified before probing versions.** With a private pinned alternative available, a recorded executable reporting 3.16.0 fails with `recorded build changed version`, an unprobeable recorded executable fails with `recorded build unprobeable`, and an unprobeable unresolved symlink without `realpath`/ `readlink` fails with `not compared (unresolved path)`. These exercise both prior bypasses. The independent private-pair harness invokes the exact candidate function definitions with two fixed candidates in place of ambient discovery.
3. **Verified · File identity and resolution controls.** A hardlink to the changed baseline triggers the drift failure. Without `realpath`, parent-relative and chained links through a directory link still reach and check the baseline. With no `stat`, an unequal path fails closed and the exact path remains checkable. Without `readlink`, direct regular files remain checkable and unresolved links fail when a baseline exists. The fallback rejects missing and non-directory intermediates followed by `..`.
4. **Verified · Earlier file safety.** A fresh record preserves spaces and glob metacharacters, `--no-interpreter` leaves its marker stub untouched, and existing record targets, including private hardlink and symlink aliases, retain their bytes. A failing hash utility, missing checksum metadata, and empty archive arguments return nonzero. The same canonical path is compared regardless of the synthetic hostname.

## Verification

I verified the destination is ignored and exported `git archive 43b667b` to `work/agents/sol-python-5-20261127/snapshot/`. Logs and generated private scripts and fixtures remain in its parent.

| Command from snapshot | Result |
| --- | --- |
| `TMPDIR=<private scratch> sh tools/python_pin/tests/test_verify.sh` and equivalent `bash` and `dash` invocations | 131 assertions passed in each harness invocation. This scratch volume is case-sensitive, so the bundled case-variant branch took its documented skip rather than the case-insensitive assertions. The supplied coordinator run covered 133 assertions. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../probe.py` | Exact private CLI and candidate-function probes reproduced the outcomes above. The last probe demonstrates the absent-baseline regression. Hardlinks exercised the device/inode identity path. A live case-insensitive alias was unavailable here. |

Only private synthetic executable and archive bytes were used for independent probe inputs. No installed or shared file was modified. Publisher authentication remains recorded Sigstore evidence rather than a check performed by this verifier. Artifact installation and M0.1 acceptance remain separate.
