# M0.1 independent Python verifier follow-up

**Verdict — changes required.** The requested fixes work on the normal path. Without `realpath`, an ordinary parent-relative interpreter symlink can bypass a local drift comparison and turn a failing run into a passing one.

| Item | Review scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `d8cd39cbfe926ba5321f59b4cc1ada727fd44b08`, committed 2026-11-27 04:35:52 +01:00 |
| Base | `ab3ac754ce58f3ca9693064bf5888d51ee2813b0` |
| Review date | 2026-11-27, Europe/Zurich |
| Files | `tools/python_pin/**`, `docs/PYTHON_TOOLCHAIN.md`, and the historical Sol report on ab3ac75. |

## Findings

1. **Medium · The `readlink` fallback can leave the recorded path unchecked.** The fallback prepends the symlink's directory to a relative target, but leaves components such as `..` in the resulting string. It follows only one link. The digest gate compares this string with the recorded canonical path. In my private probe, a fixture interpreter at the recorded path reports the pinned version but has changed bytes. A sibling symlink uses `../spaces [literal]*/stub python` as its target. With `realpath` available, it exits 1 for digest drift. With a private PATH containing `readlink` and the other required tools but no `realpath`, it exits 0 and reports that the digest was not compared. Resolve the physical path completely in the fallback, or fail when an interpreter symlink cannot be resolved canonically and a local baseline applies. Add a regression with parent components and chained links. [Interpreter path handling](../../tools/python_pin/verify.sh#L290) · [Digest comparison](../../tools/python_pin/verify.sh#L349)
2. **Verified · Host and output semantics.** A changed executable at the recorded canonical path fails on a substituted hostname. A different path receives a visible noncomparison warning in quiet mode. An unprobeable discovered candidate warns without failing a run that finds the pinned version, and a run with no usable pinned version still fails. [Canonical path policy](../../tools/python_pin/README.md#L128)
3. **Verified · Prior safety and filename corrections.** The verifier refuses existing record destinations, including the archive, either pin, the interpreter, unrelated files, and private symlink/hardlink aliases. Every checked input retained its bytes. A fresh record succeeds under `--no-interpreter` without running the marker stub. The bundled tests cover leading dashes and backslashes in filenames; my separate regular-file probe covers spaces and glob metacharacters. Missing metadata, empty archive options, and a failing hash utility retain their error outcomes. [Filename hashing](../../tools/python_pin/verify.sh#L149) · [Recording restrictions](../../tools/python_pin/verify.sh#L484)

## Verification

I verified the destination is ignored and exported `git archive d8cd39c` into `work/agents/sol-python-3-20261127/snapshot/`. Test logs, private aliases and synthetic files are under its parent. All aliases used by write-oriented tests named private scratch files.

| Command from the snapshot | Result |
| --- | --- |
| `TMPDIR=<private scratch> sh tools/python_pin/tests/test_verify.sh` | 88 assertions passed. |
| Same harness launched with `bash` and `dash` | 88 assertions passed in each invocation. These identify the harness shell; individual cases may invoke `sh` directly. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../probe.py` | 18 isolated cases. Sixteen replay the earlier verifier controls. Two exercise the same drifted symlink with and without `realpath`, reproducing finding 1. |

The verifier compares digest values during each archive check. Sigstore is separately recorded publisher-artifact evidence, and does not authenticate the installed Homebrew executable. I did not repeat cryptographic verification, artifact restoration, installation, or installed interpreter checks. M0.1 acceptance is separate.
