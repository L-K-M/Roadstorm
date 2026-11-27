# M0.1 independent Python verifier recheck

**Verdict — pass for the scoped verifier repair.** The prior overwrite, skipped-interpreter execution, quoted-path, and authentication wording findings are resolved. One nonblocking documentation clarification remains about the scope of local digest comparisons.

| Item | Review scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `ab3ac754ce58f3ca9693064bf5888d51ee2813b0`, committed 2026-11-27 04:12:08 +01:00 |
| Base | `cc5dac91ed89b934defdd6d1240e729791885ccb` |
| Review date | 2026-11-27, Europe/Zurich |
| Files | `tools/python_pin/verify.sh`, its regression tests and pin files, `tools/python_pin/README.md`, relevant sections of `docs/PYTHON_TOOLCHAIN.md` and `docs/PYTHON_TOOLCHAIN_EVIDENCE.md`, and my cc5dac9 report. |

## Findings

1. **Resolved · Recording preserves checked inputs and existing destinations.** An independent probe verified exit 2 when the record destination was the archive, interpreter, either pin file, an unrelated existing file, a symlink to the archive, or a hardlink to it. The probe confirmed every target's pre-run digest was unchanged. A fresh record succeeds. The documented threat boundary remains a race involving a hostile process that controls the destination parent directory, outside these deterministic checks. [Destination validation and creation](../../tools/python_pin/verify.sh#L464) · [Documented residual race](../../tools/python_pin/README.md#L79)
2. **Resolved · Recording uses observations from the checks.** A marker-writing interpreter stub was never invoked under `--no-interpreter --record`. A matching synthetic archive in a directory containing spaces, brackets and an asterisk was checked and its digest recorded. An empty archive option and absent checksum metadata return 2. Absent archive data or a present hash utility that returns failure cause exit 1. The bundled regressions also cover recording only diagnostic data after failures. [Recording from existing observations](../../tools/python_pin/verify.sh#L495) · [Hash failure handling](../../tools/python_pin/verify.sh#L148)
3. **Resolved · Publisher signature evidence stays separate.** The verifier explains that a running archive check compares a digest. Sigstore is recorded evidence for matching publisher artifact bytes and is never performed automatically per run. The selected Homebrew executable remains a local build. [Verification output](../../tools/python_pin/verify.sh#L389) · [Publisher evidence](../../docs/PYTHON_TOOLCHAIN_EVIDENCE.md#L240)
4. **Low · Clarify the same-path cross-host case.** A matching-version interpreter with different bytes at another path is reported without comparing against the recorded local digest. Changed bytes at the recorded path fail, even when a substituted synthetic hostname reports a different host. That behavior matches the per-path policy, but the README's “never failed against another host's digest” wording can imply a host identity check. State explicitly that matching canonical paths trigger comparison even on another host, or add host scoping if portable same-path checks are later required. [Comparison implementation](../../tools/python_pin/verify.sh#L323) · [Per-path documentation](../../tools/python_pin/README.md#L122)

## Verification

I confirmed the path is ignored and exported the exact candidate with `git archive ab3ac75` into `work/agents/sol-python-2-20261127/snapshot/`. Test output, private aliases and synthetic files are in its parent directory.

| Command | Result |
| --- | --- |
| `TMPDIR=<private scratch> sh tools/python_pin/tests/test_verify.sh` | 70 assertions pass. |
| Same harness invoked with `bash` and `dash` | 70 assertions pass in each invocation. These counts identify the harness shell, and individual cases may invoke `sh` explicitly. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../probe.py` | 16 exact-candidate independent cases pass against a private verifier/pin copy, synthetic archive and interpreter, and private aliases. The script also checks unchanged input bytes and absence of the interpreter marker. |

The coordinator's restored-source hash and prior Sigstore runs remain recorded evidence. I did not hash or modify shared artifacts, rerun Sigstore, install software, or probe installed Python candidates through the verifier. M0.1 acceptance remains separate.
