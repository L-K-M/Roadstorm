# M0.1 independent Python verifier recheck

**Verdict — pass for the scoped Python verifier repair.** A valid pinned interpreter at an alternate path now works when the recorded executable or its parent is absent. Inaccessible, replaced, or otherwise uncertain baselines still fail closed.

| Item | Scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `451c070b31edc46be61917af6ec6c0cdca35582c`, committed 2026-11-27 05:46:51 +01:00 |
| Base | `43b667b62ec5546c07fb8504b6cbef1b0eb824c7` |
| Review date | 2026-11-27, Europe/Zurich |
| Inputs | `tools/python_pin/**`, `docs/PYTHON_TOOLCHAIN.md`, and both historical Python reports on 43b667b. |

## Findings

1. **Resolved · Missing baseline versus uncertain identity.** A pinned executable at another path exits 0 and prints that the recorded build is absent after I remove the private baseline pathname. Pointing the baseline at a missing parent also exits 0. With an existing comparator in a private directory lacking search permission, the run exits 1 with `equivalence undetermined`. With two existing paths and no `stat`, the run also fails closed. A direct canonical pathname remains checkable without `stat`. [Absence classifier](../../tools/python_pin/verify.sh#L382) · [Identity decision](../../tools/python_pin/verify.sh#L485)
2. **Resolved · Recorded pathname replaced by a link.** A private recorded pathname replaced by a symlink fails with `recorded build path replaced`, whether the command selects that link or independently selects its target. Replacing the baseline with a dangling symlink preserves the same failure rather than becoming the missing-baseline case. [Replacement check](../../tools/python_pin/verify.sh#L491)
3. **Verified · Earlier drift closures.** A changed-version recorded build and an unprobeable recorded build both fail even with a different pinned build available. An unprobeable, unresolved symlink also fails before version selection when both `realpath` and `readlink` are unavailable. Parent-relative and chained directory/file links detect drift without `realpath`, and a private hardlink to the changed executable triggers the same comparison as the original. A live case-insensitive alias was unavailable on this scratch volume. [Interpreter resolution and identity](../../tools/python_pin/verify.sh#L452)
4. **Verified · Existing verification and recording behavior.** Fresh recording, filename quoting, skipped-interpreter behavior, no-clobber checks for existing files and aliases, empty arguments, missing metadata, and nonzero hash-tool results retain their prior outcomes. I found no new blocking defect in the reviewed scope.

## Commands and limits

I verified the destination is ignored and used `git archive 451c070` to export `work/agents/sol-python-6-20261127/snapshot/`. Logs, scripts and synthetic fixtures are under its parent.

| Command from snapshot | Result |
| --- | --- |
| `TMPDIR=<private scratch> sh tools/python_pin/tests/test_verify.sh`, and equivalent `bash` and `dash` invocations | 146 assertions passed in each harness invocation. The bundled case-insensitive branch skipped on this volume, accounting for the difference from the coordinator's 148. Some bundled cases invoke `sh` directly. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../probe.py` | Independent private CLI tests reproduce the missing, inaccessible, replaced and dangling baseline cases. Two-candidate checks use the unchanged candidate function definitions with explicit synthetic inputs in place of ambient discovery. The hardlink case checks device/inode identity. |

No installed interpreter, publisher artifact, or shared file was modified. The script performs local and archive digest comparisons. Sigstore remains separately recorded publisher-artifact evidence and was not rerun here. M0.1 acceptance remains separate.
