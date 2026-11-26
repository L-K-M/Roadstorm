# tools/toolchain — toolchain pin verification (PLAN.md M0.1)

Original project code under the Unlicense. Ownership: `tools/toolchain/**`
(see PLAN.md "How agents execute the plan").

## What is here

| Path | Purpose |
| --- | --- |
| `pin/engine.txt` | The pinned engine version, its exact `--version` string, the official source URLs, and the upstream-verification status. Data only. |
| `pin/checksums.txt` | sha256 digests **observed on the recording machine**. Local observations; selected files were compared with verified archives as documented in the evidence record. Empty fields mean "not recorded" and are reported as such, never invented. |
| `verify.sh` | Executable check that the locally installed editor and export templates still match the pin. Export templates are **required** by default; pass `--no-templates` to skip that check explicitly. |

The narrative record — what was verified, how, what is unknown and why — is
`docs/TOOLCHAIN.md`. Read it before trusting any line this directory prints.

## Usage

```sh
tools/toolchain/verify.sh                  # verify the local toolchain
tools/toolchain/verify.sh --deep           # also run the in-template checks
tools/toolchain/verify.sh --no-templates   # skip the template checks
tools/toolchain/verify.sh --record out.txt # write observed digests to out.txt
tools/toolchain/verify.sh --quiet          # failures and the summary only
tools/toolchain/verify.sh --godot <path> --templates <dir>
```

Environment: `GODOT_BIN`, `GODOT_TEMPLATES_DIR`, `NO_COLOR`.
Exit codes: `0` passed, `1` a check failed, `2` the command could not run
(the same contract as `tools/ci/ci.sh`; that includes "no sha256 utility on
PATH" and "`--deep` combined with `--no-templates`"). A missing export-templates
directory is a **failure** (`1`), not a warning: the templates are part of the
pin. Use `--no-templates` when a host genuinely has no templates installed and
that gap is accepted.

## Rules this directory must not break

1. **A local digest is not upstream verification.** The verifier compares installed files to recorded local hashes. The coordinator verified **selected files only** — the editor binary, `version.txt` and the three target templates — against publisher-checksummed archives separately; see the evidence record. The full bundle is not verified, and no target platform was launched.
2. **No installs, no downloads.** `verify.sh` only reads local files. `--deep`
   extracts the already-installed `macos.zip` into a temporary directory that
   it removes again; it downloads nothing.
3. **Never invent a digest.** If a checksum is unknown, leave the field empty;
   the verifier reports `NOT RECORDED` and still exits 0 for that item.
4. **A missing tool is a failure, not a pass.** No sha256 utility on PATH, or
   no export-templates directory without `--no-templates`, must fail the run;
   a check that cannot run must never print PASS.
5. **Version changes are regression decisions.** Changing the pin means the
   engine version moved deliberately (PLAN.md M0.1): record the reason, the new
   observed digests, and the new verification status together.

## Relationship to tools/ci

`tools/ci/ci.sh doctor` reports the environment and checks its own engine pin
(`tools/ci/pin/engine.txt`, owned by `tools/ci/**`). This directory is the
record of what the M0.1 inventory actually observed; it does not write to the
CI tooling, the shared project, or the `.godot/` import cache.
