# tools/python_pin — asset-generation Python pin verification (PLAN.md M0.1)

Original project code under the Unlicense. Ownership: `tools/python_pin/**`
(see PLAN.md "How agents execute the plan").

## What is here

| Path | Purpose |
| --- | --- |
| `pin/python.txt` | The pinned asset-generation interpreter (CPython 3.15.2), the official python.org sources, the **published** SHA-256 digests of the pinned artifacts, and the upstream-verification status. Data only. |
| `pin/checksums.txt` | sha256 digests **observed on the recording machine** for the local interpreters. Local observations; none of these files is a python.org artifact. Empty fields mean "not recorded" and are reported as such, never invented. |
| `verify.sh` | Executable check of the locally installed interpreters against the pin, and — only when given `--archive` — of an official python.org artifact against the publisher's published digest. |

The narrative record — what was inventoried, what the official sources are,
what was verified, what is open and why — is `docs/PYTHON_TOOLCHAIN.md`. The
independent verification logs behind the statuses below are in
`docs/PYTHON_TOOLCHAIN_EVIDENCE.md`. Read both before trusting any line this
directory prints.

## Recorded verification status (2026-11-27)

| Scope | Status |
| --- | --- |
| Four pinned publisher artifacts: downloaded bytes vs release-page SHA-256 | matched |
| Four `.sigstore` bundles vs `hugo@python.org` / GitHub OIDC issuer | OK; wrong-identity, wrong-issuer and tampered-bytes controls fail |
| Installed Homebrew 3.15.2 build | **LOCAL observation only**; not publisher-authenticated |
| Homebrew channel trust (API JWS, bottle/installed code signatures) | OPEN; checksum agreement only |

## Usage

```sh
tools/python_pin/verify.sh                        # verify local interpreter(s)
tools/python_pin/verify.sh --python <path>        # check a specific interpreter
tools/python_pin/verify.sh --archive <file>...    # verify official artifact(s)
tools/python_pin/verify.sh --no-interpreter       # skip the interpreter check
tools/python_pin/verify.sh --record out/observed.txt
tools/python_pin/verify.sh --quiet
```

Environment: `PYTHON_BIN`, `NO_COLOR`.
Exit codes: `0` passed, `1` a check failed, `2` the command could not run
(missing pin or digest file, no sha256 utility on PATH, bad option). A missing
pinned-version interpreter is a **failure** (`1`), like a missing export
template in `tools/toolchain/verify.sh`: the interpreter is part of the pin.
Pass `--no-interpreter` when a host genuinely has no pinned interpreter and
that gap is accepted.

## Rules this directory must not break

1. **An installed interpreter is not an official artifact.** Homebrew, Xcode,
   uv/astral-sh and distro builds are local builds. A matching version string
   says the interpreter *reports* 3.15.2; it authenticates nothing about
   python.org's bytes. `verify.sh` prints this distinction on every run.
2. **A local digest is not publisher authentication.** `pin/checksums.txt`
   records what is installed on the recording machine so later runs can detect
   change. None of those files is a python.org artifact, and a matching version
   string says only that the interpreter *reports* 3.15.2. `verify.sh` reports
   `installed_interpreter_publisher_authenticated=no` from `pin/python.txt`.
3. **A published-digest match is not Sigstore authentication.** `--archive`
   compares a downloaded file with the digest python.org published; it does not
   verify signatures. `pin/python.txt` separately records that all four pinned
   bundles were Sigstore-verified on 2026-11-27 against `hugo@python.org` via
   the GitHub OIDC issuer (sigstore-python 4.6.0, hash-pinned requirements,
   isolated venv; negative controls failed). Those statuses authenticate
   publisher artifact bytes only, never an installed binary; full logs are in
   `docs/PYTHON_TOOLCHAIN_EVIDENCE.md`.
4. **No installs, no downloads, no global changes.** `verify.sh` only reads
   local files and runs `--version`-style probes. It never installs a Python,
   never writes outside `--record`'s target, and never touches a global
   installation.
5. **Never invent a digest.** If a checksum is unknown, leave the field empty;
   the verifier reports `NOT RECORDED` and still exits 0 for that item.
6. **Version changes are regression decisions.** Changing the pin means the
   Python version moved deliberately (PLAN.md M0.1): record the reason, the
   new published digests and the verification status in
   `docs/PYTHON_TOOLCHAIN.md` together with the change.

## Relationship to the rest of the tooling

`tools/toolchain/` pins Godot with the same conventions; `tools/ci/` owns its
own engine pin. This directory does not change either, does not change
`project.godot` or CI, and does not by itself install the pinned interpreter
anywhere. Wiring CI or a project script to the pinned interpreter is a
separate, recorded decision for those paths' owners.
