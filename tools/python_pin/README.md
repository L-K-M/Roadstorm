# tools/python_pin — asset-generation Python pin verification (PLAN.md M0.1)

Original project code under the Unlicense. Ownership: `tools/python_pin/**`
(see PLAN.md "How agents execute the plan").

## What is here

| Path | Purpose |
| --- | --- |
| `pin/python.txt` | The pinned asset-generation interpreter (CPython 3.15.2), the official python.org sources, the **published** SHA-256 digests of the pinned artifacts, and the upstream-verification status. Data only. |
| `pin/checksums.txt` | sha256 digests **observed on the recording machine** for the local interpreters. Local observations; none of these files is a python.org artifact. Empty fields mean "not recorded" and are reported as such, never invented. |
| `verify.sh` | Executable check of the locally installed interpreters against the pin, and — only when given `--archive` — of an official python.org artifact against the publisher's published digest. |
| `tests/test_verify.sh` | Focused regression suite for the verifier, including record-destination safety and `--no-interpreter`. Creates its fixtures in a private temporary directory. |

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
tools/python_pin/verify.sh --no-interpreter       # skip all interpreter execution
tools/python_pin/verify.sh --record observed.txt  # create a fresh record file
tools/python_pin/verify.sh --quiet
```

Paths are ordinary arguments: quote them normally and spaces, tabs and glob
characters stay part of one path. `--archive` may be repeated and supports
both `--archive <file>` and `--archive=<file>`.

Environment: `PYTHON_BIN`, `NO_COLOR`.
Exit codes: `0` passed, `1` a check failed, `2` the command could not run
(missing pin or digest file, no sha256 utility on PATH, a bad or empty option,
or an unsafe `--record` target). A missing
pinned-version interpreter is a **failure** (`1`), like a missing export
template in `tools/toolchain/verify.sh`: the interpreter is part of the pin.
Pass `--no-interpreter` when a host genuinely has no pinned interpreter and
that gap is accepted.

### Recording safety and residual races

`--record` creates a new regular file and never overwrites one. It fails with
exit `2` if the destination already exists in any form (regular file,
directory, FIFO/socket/device node, symlink including a dangling one), if it is
a hard link to a checked input, or if it is exactly one of the protected
inputs (`--archive` files, `--python`, `pin/python.txt`,
`pin/checksums.txt`). Because the destination must not exist, every symlink or
hard-link alias of those inputs is refused before anything is opened for
writing. Checked archives, interpreters, the pin and the digest file are only
read; they are never opened for writing.

`--record` does not probe anything again: it writes only observations already
collected during checks, so `--no-interpreter` also keeps recording from
running an interpreter. If checks fail, the record is still written (with
parent directories created as needed) but carries an explicit `# NOTE:
verification FAILED ... diagnostic observations` header; nothing is invented.
Record entries use `local_interpreter_<major><minor>_{sha256,path}`, the key
convention `verify.sh` itself uses for its drift lookup (for this pin,
`local_interpreter_315_*`). `pin/checksums.txt` retains one legacy entry under
an older name (`local_interpreter_396_*` for 3.9.6); a record does not rewrite
historical lines. The stored path is resolved with `realpath` when the selected
file is a symbolic link; a real launcher such as macOS `/usr/bin/python3`
stays that launcher (its re-exec target is not followed), so in that case the
digest describes the launcher.

Unreadable pin or digest files are hard failures (exit `2`), never treated as
"not recorded". Deliberately empty fields remain `NOT RECORDED`, as before.

Residual limitation: validation and creation are separate steps. A hostile
process that controls the parent directory could race the check and put a path
at the destination first. By shell semantics (noclobber opens exclusively in
bash 3.2 as `/bin/sh` and dash on macOS), the final creation then fails
instead of truncating, even for a symlink; the bundled suite exercises the
deterministic existence refusals, not this race. This narrows the window but
is **not** a formal, race-free guarantee on every POSIX shell.

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
   local files and runs `--version`-style probes. It never installs a Python
   and never touches a global installation. Its only writes are the
   `--record` destination and missing parent directories needed for it.
5. **Never invent a digest.** If a checksum is unknown, leave the field empty;
   the verifier reports `NOT RECORDED` and still exits 0 for that item. A
   digest utility that cannot read a file is a failure, never an empty
   passing value, and such an item is omitted from a record rather than
   recorded as blank.
6. **Version changes are regression decisions.** Changing the pin means the
   Python version moved deliberately (PLAN.md M0.1): record the reason, the
   new published digests and the verification status in
   `docs/PYTHON_TOOLCHAIN.md` together with the change.
7. **Recording is create-only and fail-closed.** An existing destination is
   refused, not truncated, and protected inputs/pin paths are refused by
   identity as well as by existence. Empty option values (`--archive ''`,
   `--record=`, ...) are usage errors, never silently ignored.
8. **The local digest baseline is scoped to an exact canonical path, not to
   a host.** Only an interpreter whose resolved path equals
   `local_interpreter_315_path` in `pin/checksums.txt` is compared with the
   recorded digest. A build at that same path on **any** machine is compared
   and fails closed on mismatch; an interpreter at a different path is
   reported as a version match but left `NOT RECORDED`, never silently
   assumed to match. No host identity is consulted.
9. **Probes are isolated.** Interpreters are invoked with `-I`; modules in
   the caller's working directory or `PYTHONPATH` cannot affect the result.
   A candidate whose version cannot be read (for example a bare Python 2
   `python`) is skipped with a warning; the run still fails if no
   pinned-version interpreter is found.
10. **The summary reports the drift-gate outcome.** It states
    `local digest: compared`, `not compared (...)` or `skipped
    (--no-interpreter)`, and a skipped comparison also emits a visible
    `[warn]`, so `--quiet` cannot hide that no local digest was checked.

## Regression tests

`sh tools/python_pin/tests/test_verify.sh` builds isolated copies of the pin
with synthetic artifacts and covers: fresh recording, exact `--archive` /
`--record` overlap (including a `./` spelling), pin and digest targets,
hard-link and symlink aliases (including a dangling symlink), existing
unrelated targets and directories, quoted paths with spaces and glob
characters, multiple `--archive` forms, `--no-interpreter` executing nothing
(and recording no interpreter lines), normal-mode observation without
re-probing, a failing fake interpreter marked as diagnostic, `-I` in probes,
a second matching-version build at a different path being NOT compared (with a
visible `--quiet` warning), a changed same-path build failing closed,
checksums-convention record keys, mismatch getting no Sigstore success claim,
rejected empty options, unreadable pin/digest metadata failing closed, a
Python-2-style candidate being skipped without failing the run, odd-name
hashing on stdin, and a failing sha256 command failing closed. All test
fixtures are regular files
created in a private temporary directory; symlink/hard-link fixtures live only
there and are removed with it.

## Relationship to the rest of the tooling

`tools/toolchain/` pins Godot with the same conventions; `tools/ci/` owns its
own engine pin. This directory does not change either, does not change
`project.godot` or CI, and does not by itself install the pinned interpreter
anywhere. Wiring CI or a project script to the pinned interpreter is a
separate, recorded decision for those paths' owners.
