# M0 manifest hash and error-handling recheck

**Verdict — pass for the scoped fixes on the reviewed POSIX host.** The two prior CLI tracebacks are corrected. The guarded readers reject leaf swaps, and the absence of either required flag prevents an open. Windows support for these reads remains unavailable.

Reviewer — OpenAI Codex, GPT-6.2 Sol, native OpenAI provider. Review date 2026-11-27. Candidate `dd0628b29ca7f5379732e2de30395da300c90185`. Base `6cc0058af4680f8ac04409974888c8b12e053e01`.

## Verified behavior

- Under Python 3.15.2, `tools/asset_manifest/run_tests.sh` passed 149/149. `python3 tools/asset_manifest/validate_manifest.py --check-hashes assets/manifest.json` returned 0 with no findings. The tracked registry is empty. The test suite and an independent private regular-file control separately verified real digest computation.
- `validate_manifest.py --json --check-hashes` on a private fixture with a 4,500-digit `schema_version` integer returned 2 with `invalid-json`. The same command on a complete fixture whose generated output had mode 000 returned 1 with `missing-file`. Both emitted parseable JSON without a traceback.
- The suite exercises final-open symlink and FIFO replacements in both output hashing and provider-register reads. It uses a real symlink or FIFO after the final pre-check, then verifies that the swapped destination is rejected without blocking. `manifest_validator.py:551–574` opens with both flags, checks `fstat`, then restores blocking mode for accepted regular files. I injected `OSError(EIO)` independently at `fstat` and at `read` in both reader paths. Each returned no content or digest and called the real `os.close` once. Successful reads and hashes also closed once.
- I separately simulated each absent flag by setting `_NO_FOLLOW_FLAG` or `_NON_BLOCK_FLAG` to `None` with a spy that would fail on any `os.open`. Both cases rejected an otherwise valid hashed fixture without invoking the guarded open.

## Finding and limits

- **Low — Unsupported-platform errors look like missing or unreadable files.** `manifest_validator.py:527–555` intentionally refuses to open if either protection is absent. A normal populated manifest on Windows therefore cannot complete `--check-hashes`, and an anchored provider-register lookup cannot read its rows. Windows Python lacks the Unix-only `O_NONBLOCK` constant. The simulated hash cases reported only `missing-file`, which does not identify the unavailable host capability. The README at lines 304–305 also describes a platform that offers neither flag, while either missing flag is enough to refuse. Document the Windows limitation and identify the missing capability in diagnostics. The fail-closed behavior is correct. [Python open flag availability](https://docs.python.org/3/library/os.html#os.O_NONBLOCK)
- The leaf flags do not pin parent directory components. A parent replaced by a symlink after the pre-check can still redirect the open, as the updated digest docstring and README document. Stable parent symlinks are rejected. This check does not establish race-free path traversal.

I reviewed the base Sol and Opus reports, the validator and its tests, and the relevant README. Commands ran from a private `git archive dd0628b` snapshot at `work/agents/sol-manifest-dd0628b/snapshot` on Darwin ARM64, with an isolated TMPDIR and fixtures. I inspected CPython's documented Windows flag availability and simulated missing flags locally. I did not run Windows or Linux. This review does not establish legal rights, approve provenance, or attest to any shipped assets.
