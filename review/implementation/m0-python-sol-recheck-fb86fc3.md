# M0.1 independent Python verifier recheck

**Verdict — changes required.** The ordinary symlink fallback and known unprobeable baseline now fail closed as intended. Two candidate-selection branches still allow the local drift check to be skipped while another executable satisfies the version pin.

| Item | Review scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `fb86fc3a006a4c2351a9ca463fa04b6a1c2af4ba`, committed 2026-11-27 05:06:16 +01:00 |
| Base | `d8cd39cbfe926ba5321f59b4cc1ada727fd44b08` |
| Review date | 2026-11-27, Europe/Zurich |
| Inputs | `tools/python_pin/**`, `docs/PYTHON_TOOLCHAIN.md`, and the historical Sol and Opus Python reports on d8cd39c. |

## Ranked findings

1. **Medium · A canonical baseline whose changed bytes report another version bypasses the drift gate.** In a two-private-candidate reproduction, the executable at the recorded canonical path now reports 3.16.0, and an unrelated candidate at a different path reports the pinned 3.15.2. The first candidate's changed bytes are observed for recording but never compared. The second is accepted by version, and the run state is exit 0 with `not compared (different path)`. The implementation calls the local digest check only after a pinned-version match. Classify candidates by their canonical identity before branching on reported version. A discovered executable at the recorded baseline path should fail on a changed version or a changed digest, regardless of whether another build satisfies the version gate. [Candidate branch](../../tools/python_pin/verify.sh#L402) · [Per-path contract](../../docs/PYTHON_TOOLCHAIN.md#L222)
2. **Medium · Unresolved and unprobeable together can bypass the fail-closed rule.** In the same private-pair harness, I selected a chain to the recorded executable after making it unprobeable and removing both `realpath` and `readlink` from the private PATH. A different-path pinned candidate still yields exit 0. The unresolved-path guard sits in the digest check, which the unprobeable branch never reaches. When an applicable digest baseline is present and an executable path cannot be resolved, decide that outcome before the version probe. The exact canonical unprobeable path already correctly fails with or without the alternate candidate. [Resolution and probe handling](../../tools/python_pin/verify.sh#L364)

## Verified repairs

- A parent-relative symlink without `realpath` reaches the canonical recorded file. A file link through an intermediate directory link does as well. Both detect changed bytes. A pinned-version symlink with neither resolution utility exits 1, while the direct regular-file input can still be compared. The harness also exercises loop and broken-link handling.
- Existing archive, interpreter, pin, unrelated file, and private hardlink or symlink aliases all remain byte-for-byte intact after recording refusals. A fresh record handles spaces and glob characters. Empty archive arguments, absent metadata, unavailable archive bytes, and a failing hash utility produce the expected nonzero statuses. `--no-interpreter --record` leaves the marker stub untouched.

## Commands and limitations

I verified the destination was ignored and used `git archive fb86fc3` to export `work/agents/sol-python-4-20261127/snapshot/`. Scripts, private fixtures, and logs remain in its parent directory.

| Command from the snapshot | Result |
| --- | --- |
| `TMPDIR=<private scratch> sh tools/python_pin/tests/test_verify.sh`, and equivalent `bash` and `dash` invocations | 113 assertions passed in each harness invocation, matching the coordinator's results. Individual bundled cases can invoke `sh` explicitly. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../probe.py` | Independent CLI probes confirm the repaired cases. The script then builds a private harness from the unchanged candidate shell function definitions, replacing only main dispatch with two explicit synthetic candidates to avoid ambient PATH discovery. It reproduces both remaining bypasses and verifies the known-path unprobeable control exits 1. |

No installed file or shared publisher artifact was mutated. I did not repeat Sigstore, install a Python build, or rerun Homebrew distributor checks. Runtime archive verification is a digest comparison and Sigstore remains recorded publisher-artifact evidence. M0.1 acceptance remains separate.
