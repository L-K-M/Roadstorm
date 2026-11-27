# Asset-generation Python toolchain (PLAN.md M0.1)

Status: pin recorded 2026-11-26 on the development Mac
(`mac-studio-2026-32-1.home`, macOS 27.0.1, arm64) by the M0.1
asset-generation Python pin research job (StepFun 5 Preview). Publisher
artifact evidence was integrated on 2026-11-27 from the independent
verification job `4dca64d7-9068-48dc-8c3a-c563400d7d85`, whose record is
[docs/PYTHON_TOOLCHAIN_EVIDENCE.md](PYTHON_TOOLCHAIN_EVIDENCE.md). Ownership:
`docs/PYTHON_TOOLCHAIN.md` and `tools/python_pin/**`. This update changed no
other checkout file, installed tool, secret or account configuration, and no
interpreter was installed or altered.

**Bottom line:** the proposed pin is **CPython 3.15.2, exact**, from the
official python.org release
(<https://www.python.org/downloads/release/python-3152/>). On 2026-11-27 all
four pinned official artifacts were downloaded over HTTPS; their bytes matched
the SHA-256 digests python.org publishes on the release page, and each
artifact's `.sigstore` bundle verified against the signer `hugo@python.org`
via the GitHub OIDC issuer using sigstore-python 4.6.0 in an isolated,
hash-pinned verifier environment. Wrong-identity, wrong-issuer and
tampered-artifact negative controls failed. That establishes the authenticity
of the **publisher artifact bytes only**.

The interpreter that project scripts actually select on the recording host is
the Homebrew core `python@3.15` 3.15.2 build: a **different file with a different
digest**, not one of those artifacts and not publisher-authenticated. Its
version string and local sha256 are observations that detect drift. Homebrew
channel trust is checksum agreement only; the API JWS signature and an
installed framework bundle code-signature/resource-sealing question remain
open (see [Open items](#open-items-left-open-not-claimed)).

## Local Python inventory (observations only)

Nothing was installed or changed to produce this table. "Provenance" is what
the machine reports about each interpreter; it is not a claim about any
publisher. No row is publisher-authenticated.

| Interpreter | Version | Provenance | Local sha256 (in `pin/checksums.txt`) |
| --- | --- | --- | --- |
| `/usr/bin/python3` | 3.9.6 | Xcode Command Line Tools (`/Applications/Xcode.app/...`); re-execs the framework binary | `c5a13e37…` |
| `/opt/homebrew/bin/python3` → `python3.15` | 3.15.2 | Homebrew `python@3.15` 3.15.2 | `6cc907e4…` |
| `/opt/homebrew/bin/python3.13` | 3.13.18 | Homebrew `python@3.13` | `506f8a19…` |
| `~/.local/share/uv/python/…-3.11.18…` | 3.11.18 | uv-managed astral-sh python-build-standalone | `2dbdd6e2…` |
| `~/.local/share/uv/python/…-3.12.16…` | 3.12.16 | uv-managed astral-sh python-build-standalone | `7a427de7…` |

Notes:

* No `pyenv`, no Conda, no second Godot-adjacent Python. `uv` is present.
* **None of these is a python.org release artifact.** The Homebrew and
  python-build-standalone interpreters are built from source by their
  distributors; the Xcode one ships with the Command Line Tools. Their digests
  pin *local files* so later runs can detect change — nothing more.
* The local 3.15.2 (Homebrew) and the pinned 3.15.2 (python.org) are
  *different files*: same version string, different build, different digest.
  Homebrew's own formula comments say `--enable-optimizations` and
  `--with-lto` "diverge from what upstream python does for their macOS binary
  releases". The script therefore never treats a version match as
  authentication.
* The Homebrew formula's source URL and sha256 point at
  `Python-3.15.2.tgz`, whose bytes were authenticated on 2026-11-27. That ties
  Homebrew's **source input**, not its separately built binary.
* Existing project scripts (`tools/asset_manifest/**`, `tools/tick_probe/**`,
  `tools/smoke/fault_injection.sh`) run on any reasonably recent `python3`
  and are unaffected by this pin. CI (`tools/ci/`, `.github/workflows/`) still
  uses whatever interpreter the runner provides; adopting this pin there is a
  separate decision for those paths' owners.

## Official release source and published checksums

The version authority for CPython is **python.org itself**: the release page
(`/downloads/release/python-XXXX/`) and the artifact tree
(`/ftp/python/<version>/`). Both were fetched over HTTPS on 2026-11-26 and
re-fetched during the 2026-11-27 verification.

What python.org publishes per release, observed on the 3.15.2 page:

| Mechanism | Status for 3.15.2 |
| --- | --- |
| Per-artifact **SHA-256 checksum** | Published on the release page for every artifact; all four pinned values below matched downloaded bytes on 2026-11-27 |
| **Sigstore** verification bundle (`<artifact>.sigstore`) | Published next to every artifact in the FTP tree; all four pinned bundles verified on 2026-11-27 (section below) |
| Signer identity for Sigstore verification | `hugo@python.org` via OIDC issuer `https://github.com/login/oauth` (PEP 790, release manager of 3.15); certificate issuer `CN=sigstore-intermediate,O=sigstore.dev` |
| SPDX SBOM (`.spdx.json`) | Published for the source tarballs and Windows artifacts; **not** published for the macOS installer |
| Legacy OpenPGP (`.sig`) | Present in the FTP directory; not advertised on the release page |

### Published digests, observed bytes, and Sigstore bundles

Release date **2026-10-25**. "Bytes" is the server `Content-Length` observed
when the artifacts were downloaded for verification on 2026-11-27. Every
observed SHA-256 equals the publisher's published value.

| Pinned artifact | Role | Bytes | Published = observed SHA-256 |
| --- | --- | --- | --- |
| `python-3.15.2-macos11.pkg` | target installer: macOS universal2, macOS 10.15+ | 81,894,859 | `2c6104475535b720b45774c68b0dfc9fcca2235353cf9ff81e05488f89845396` |
| `python-3.15.2-amd64.exe` | target installer: Windows x86-64 | 37,694,360 | `06e225a228191b0f4d1dcf6905fbb21bf9f6970d13a2ec63137ab9bee76f15aa` |
| `Python-3.15.2.tar.xz` | source archive (xz-compressed source of record) | 27,960,396 | `8b5536d280142ecf6cdfe15d12a21ba1c65e300bbf7b28a8d0cdb849575797de` |
| `Python-3.15.2.tgz` | source archive (gzip source of record) | 35,882,840 | `f74e1db0eabd651cd01e4e2a00201bd41866abe74869ab716f9bf33cbbaa0943` |

Retained Sigstore bundle digests (sha256 of each `<artifact>.sigstore` file):

| Artifact | Bundle sha256 | Bytes |
| --- | --- | --- |
| `Python-3.15.2.tgz` | `0fdedee6c00fa4abd2cd377db69737b6ef129cf238546344280ef65a590220a2` | 7,220 |
| `Python-3.15.2.tar.xz` | `d1bbd6bb4bd3865d18f5c2cc1ae0da08c2d9f09d6e82729b527ca06f572d62fa` | 7,083 |
| `python-3.15.2-macos11.pkg` | `2e7a16ed396c33c8c201f9d0e42c4f0fc213ab474bf9389c54adbd58d70a15f2` | 7,130 |
| `python-3.15.2-amd64.exe` | `8b5a848f5e218ee4d0267897c218f6d61a19a620af4fb984ddfcb6c8b2541580` | 7,224 |

Cross-platform coverage, stated honestly: macOS and Windows x86-64 have
official **binary** installers. **python.org publishes no Linux binary
artifact**, so a Linux x86-64 interpreter at this pin is a local build from
the pinned source tarball; its digest cannot be checked against any publisher
digest, only the source tarball's can. Other artifacts exist for the same
release (Windows ARM64, 32-bit, embeddable packages, Android, iOS) and are
outside this project's three target platforms; they are recorded as present,
not pinned.

## Publisher verification evidence (2026-11-27)

Job `4dca64d7-9068-48dc-8c3a-c563400d7d85` performed the checks recorded in
[docs/PYTHON_TOOLCHAIN_EVIDENCE.md](PYTHON_TOOLCHAIN_EVIDENCE.md) sections 4–5;
its raw command logs, retained bundles, certificate details and
transparency-log indexes are in that job's ignored directory. Reproducing them
needs multi-megabyte downloads and an isolated verifier environment. The pin
and `verify.sh` carry the resulting narrowly scoped statuses; they do not
repeat the signature verification.

* **Artifact bytes vs published digests.** All four pinned artifacts were
  downloaded over HTTPS from the URLs above; each SHA-256 matched the
  release-page value (table above). The exact byte counts are the server's
  `Content-Length`.
* **Sigstore signatures.** Each artifact's `.sigstore` bundle was verified with
  sigstore-python 4.6.0 (requirements file hash-pinned to
  `9ddb40e33f7412ae6843c68865f12b82ac5078b559e3549bc1d15bb39ce6fdb8`;
  isolated venv) against `hugo@python.org` /
  `https://github.com/login/oauth`. Each bundle is
  `application/vnd.dev.sigstore.bundle.v0.3+json`; its signing certificate
  names `hugo@python.org`, was issued by
  `CN=sigstore-intermediate,O=sigstore.dev`, and each artifact has one Rekor
  `hashedrekord` entry with an inclusion promise, an inclusion proof and one
  RFC 3161 timestamp. The production Sigstore TUF repository supplied a
  verified trusted root (v16) and signing config. Exact serials, log indexes
  and root hashes are in the evidence record.
* **Negative controls (all failed as expected).** Wrong identity
  (`not-the-signer@example.com`), wrong OIDC issuer
  (`https://accounts.google.com`) and a one-byte-appended `.tgz` copy were
  rejected with the expected diagnostics. The checks are enforced, not
  vacuously passing.
* **Scope.** These checks authenticate the official artifact bytes and the
  publisher-documented signer identity. They do **not** authenticate any
  locally built interpreter, including the Homebrew 3.15.2 selected on the
  recording host.

## Source archives vs target installers

The four pinned artifacts fall into two classes, and the distinction matters:

* **Source archives** — `Python-3.15.2.tgz` and `Python-3.15.2.tar.xz` are the
  upstream source of record. A digest match establishes agreement with the
  published digest; the separately recorded Sigstore verification of their
  bundles is what authenticates the publisher. A Linux x86-64 target has no
  publisher binary; it would be built from the source tarball, and the
  resulting binary digest cannot be compared with any publisher digest.
* **Target installers** — `python-3.15.2-macos11.pkg` (macOS universal2) and
  `python-3.15.2-amd64.exe` (Windows x86-64) are separate built binaries.
  Sigstore-verifying them authenticates those installer bytes only; a digest
  match alone establishes agreement with the published digest. They do not
  make another build from the same source the same bytes, and they say nothing
  about the Homebrew interpreter on this host.

## The proposed pin and why

**Pin: CPython 3.15.2, exact patch, from python.org.** Stored in
`tools/python_pin/pin/python.txt` with the published digests above;
`tools/python_pin/verify.sh` checks it and reports the verification scope.

Why 3.15.2:

* It is the **newest stable maintenance release** (2026-10-25) and an
  *expedited security release*: it blocks the compromised eMudhra
  intermediate CA keys (CVE-2026-115557) among ~130 fixes since 3.15.1.
  **3.15.0 and 3.15.1 predate that fix and must not be pinned.**
* Support runway: 3.15.0 was released 2026-10-09, so under the standard
  two-year bugfix cycle the 3.15 series stays in bugfix into late 2028 and in
  security support beyond — the longest runway of any current branch, which
  matters for a multi-year asset pipeline.
* All three target platforms are covered by official artifacts: a macOS
  universal2 target installer, a Windows x86-64 target installer, and the
  source tarballs for a Linux x86-64 build. Each pinned artifact has a
  published SHA-256 and a Sigstore bundle; all four were authenticated on
  2026-11-27.
* The recording host already runs a 3.15.2 interpreter (Homebrew build), so
  tooling can run at the pinned version immediately, while the official
  artifact itself remains uninstalled. That local build is not the artifact
  and is not authenticated by these checks.

Alternatives considered and not chosen:

| Candidate | Reason not chosen |
| --- | --- |
| 3.14.10 (2026-10-25 page, bugfix branch since 2025-10-07) | Mature, but its bugfix window ends roughly a year earlier than 3.15's; a worse fit for a long production run. Its published digests remain available if a regression decision ever moves the pin. |
| 3.13.18 | Security-only branch (3.13.0 was 2024-10-07); no new bugfixes. |
| 3.16.0a1/a2 | Pre-release; never pinned. |
| Any "latest stable" pointer | A moving target is not a pin (same rule as the engine pin). |

## Authenticated publisher bytes vs installed interpreter

These are different claims and the pin keeps them apart:

| Claim | Status |
| --- | --- |
| Official python.org artifact bytes match the published digest | Established for all four pinned artifacts on 2026-11-27 |
| Those artifact bytes verify against `hugo@python.org` / GitHub OIDC via Sigstore | Established for all four pinned artifacts on 2026-11-27 |
| A `--archive` file given to `verify.sh` matches the published digest recorded in `pin/python.txt` | Checked per run against that recorded value; digest comparison only, not a live release-page fetch or signature verification |
| The installed interpreter is authenticated by any of the above | **No.** Installed interpreters are local builds; `pin/python.txt` records `installed_interpreter_publisher_authenticated=no` |

* **Authenticated publisher artifacts** — the four official python.org files
  above. Authentication has two layers: (a) the artifact's SHA-256 equals the
  digest python.org published; (b) the `.sigstore` bundle verifies against
  `hugo@python.org` via the GitHub OIDC issuer. Both were performed on
  2026-11-27; layer (a) ties the bytes to a published value, layer (b) ties
  the publication to the release manager.
* **Installed interpreter** — any local build (Homebrew 3.15.2 on this host).
  `verify.sh` checks its version string and, for the build at the path recorded
  in `pin/checksums.txt`, compares its local digest; that detects version drift
  and local file change for that recorded build. Any other interpreter that
  merely reports the pinned version is left `NOT RECORDED` for its own path and
  is not failed against another host's digest. Interpreter probes use `-I`, so
  a module in the working directory cannot spoof the result. None of this says
  anything about python.org bytes and none of it is reported as verification.

`verify.sh` prints this distinction on every run under "verification scope",
and its summary line separates "publisher artifact evidence" from "installed
binary".

`verify.sh --record <file>` writes observed digests only to a destination that
does not exist yet. An existing regular file, directory, FIFO/socket/device,
symlink (including a dangling one), hard link, or exact protected input/pin
path is refused with exit 2, so recording cannot clobber an archive it just
checked, the pin metadata, or a local interpreter. Recording reuses only the
observations made by the checks themselves, so `--no-interpreter` also keeps
recording from running an interpreter; a failed run may still write a record,
clearly headed as diagnostic observations rather than a passing result. Record
entries use the same `local_interpreter_<major><minor>_{sha256,path}` keys as
`pin/checksums.txt` and store the resolved interpreter path. Unreadable pin or
digest files fail closed; deliberately empty fields stay `NOT RECORDED`.
Validation plus exclusive creation narrows the window against a concurrent
writer but are not a formal race-free guarantee; the precise contract and
limitation are in `tools/python_pin/README.md`. An `--archive` file whose digest
mismatches the pinned recorded value gets an explicit note that the pin's
digest/Sigstore evidence does **not** apply to it; no publisher-authentication
or Sigstore success is claimed for a mismatching input.

## Open items (left open, not claimed)

1. **Publisher artifact checks: closed, scoped.** All four pinned artifacts
   matched their published digests and their Sigstore bundles verified against
   `hugo@python.org` / GitHub OIDC on 2026-11-27. Remaining limitation: this
   authenticates publisher artifact bytes only, not any installed interpreter.
2. **Installed interpreter is not the official binary.** The selected
   Homebrew 3.15.2 build uses flags its own formula says differ from upstream
   macOS release builds; it cannot be byte-equal to
   `python-3.15.2-macos11.pkg`. No publisher check applies to it.
   `installed_interpreter_publisher_authenticated=no`. Installing the official
   artifact would be a separate decision with its own regression record and
   was not done.
3. **Homebrew channel trust is checksum-based.** The bottle tarball digest
   agrees across five Homebrew-published records and the installed tree
   matches the bottle modulo documented pour-time relocation and runtime
   caches, but the bottle and installed binaries are ad-hoc signed. The
   internal API JWS payload was not cryptographically verified.
   `homebrew_channel_fully_verified=no`.
4. **Installed framework/app bundle code-signature question.**
   `codesign --verify --strict` fails for the installed
   `Frameworks/.../Versions/3.15/Python` and `Resources/Python.app`. An
   independent context-preserving extraction of the verified bottle reproduces
   the same failure, while bare Mach-O copies pass and adding a parseable
   bundle `Info.plist` reproduces it. This is consistent with bundle
   verification requiring a resource seal absent from the ad-hoc signatures.
   It is a distribution question, not evidence of tampering; controlled
   details are in job `00c35fe3-4f0e-4a19-bda3-47cfa50ce2b2`.
5. **Linux x86-64 has no publisher binary.** The source tarball is the
   official record for that platform; no target build or launch was attempted.
6. **No official artifact is installed on this host.** `/Library/Frameworks/
   Python.framework` and `/Applications/Python 3.15` do not exist and there is
   no python package receipt; no global Python was installed, altered or
   selected.
7. **CI and project scripts do not yet use the pin.** `tools/ci/` and
   `.github/workflows/` belong to other owners; adopting the pin there (runner
   setup, `PYTHON_BIN`, a doctor check) needs their own change.
8. **The macOS installer publishes no SPDX SBOM** (blank on the release page);
   recorded as absent, not assumed.
9. **M0.1 acceptance is not claimed.** This record addresses interpreter
   provenance and publisher artifact authenticity; engine/Jolt/templates and
   the other M0.1 items remain per `docs/TOOLCHAIN.md` and `docs/STATUS.md`.

## Checks run and results

Commands ran from the repository root on 2026-11-27 for this integration, in
isolated temporary directories, with no installed tool or global state
modified. Tests create no symlinks or hardlinks: external evidence artifacts
are read directly, negative fixtures are fresh regular files in separate
directories, and the external directory is hashed before and after. Full logs
and the rerunnable `final-checks.sh` are in this job's
`work/agents/9a09e936-ab0c-4b9b-a85f-e4982025696b/integration-tests/`.

| Command | Result |
| --- | --- |
| `NO_COLOR=1 tools/python_pin/verify.sh` | **PASS** (exit 0). Homebrew 3.15.2 version and local sha256 match; output now distinguishes "publisher artifact evidence: digest+Sigstore recorded 2026-11-27" from "installed binary: local build, not publisher-authenticated". |
| `tools/python_pin/verify.sh --quiet` | PASS (exit 0), summary only. |
| `tools/python_pin/verify.sh --python /usr/bin/python3` | **FAIL** (exit 1): no interpreter reporting the pinned version. Expected. |
| `tools/python_pin/verify.sh --no-interpreter` | PASS (exit 0) with the skip warning. |
| `tools/python_pin/verify.sh --help` / `--bogus` | exit 0 / exit 2. |
| `sh -n tools/python_pin/verify.sh` | syntax OK. |
| `tools/python_pin/verify.sh --no-interpreter --archive <direct paths to the four independently verified artifacts>` | **PASS** (exit 0). Each file's role (`source archive` / `target installer`), observed and published digests, and the recorded digest+Sigstore evidence note are printed. External artifacts were hashed before and after and were unchanged. |
| `tools/python_pin/verify.sh --no-interpreter --archive <fresh regular file named Python-3.15.2.tgz>` | **FAIL** (exit 1): sha256 mismatch against the published digest. |
| `tools/python_pin/verify.sh --no-interpreter --archive <some-other-file.exe>` | **FAIL** (exit 1): not a pinned artifact. |
| `tools/python_pin/verify.sh --no-interpreter --archive <missing>/nope.pkg` | **FAIL** (exit 1): archive not found. |
| Temp copy of `tools/python_pin` with `source_tgzz_sha256` set to a small fresh regular fixture's digest, then zeroed | PASS (exit 0) with the correct expected value; **FAIL** (exit 1) after zeroing it. Proves the comparison uses the recorded expected digest. |
| `tools/python_pin/verify.sh --no-interpreter --archive <real .tgz> --record <temp>/observed.txt` | PASS (exit 0); wrote only the requested fresh file, with a header marking the digests LOCAL observations and not publisher authentication. Nothing under `tools/python_pin/` was written. Re-running with the same destination now exits 2 and leaves it unchanged. |
| Evidence consistency script (`check_evidence.py`) over the pin, the retained bundles and the downloaded artifacts | **OK** (exit 0): all four artifact bytes match the pin's published digests, and all four bundle sha256 values match the pin and the recorded certificate details; identity/issuer fields agree. |
| Pin structural sanity script | **OK** (exit 0): four artifacts carry file/url/role/sha256/bundle digest; status fields present. |
| `PATH=<temp without shasum> tools/python_pin/verify.sh --no-interpreter` | exit 2 with "no sha256 utility found"; a check that cannot run is never a pass. |

Upstream facts re-verified while recording (all read-only, HTTPS):
`/downloads/` and `/ftp/python/` list 3.15.2 as the newest stable patch
(3.15.3 → 404; 3.16.0 is alpha-only); the 3.15.2 release page publishes the
SHA-256 column and `.sigstore` links.

## Reproducing this record

```sh
tools/python_pin/verify.sh                  # local interpreter observations +
                                            # the publisher-evidence scope
tools/python_pin/verify.sh --quiet          # summary only
tools/python_pin/verify.sh --python <path>  # a specific interpreter
tools/python_pin/verify.sh --archive <file> # an official artifact vs the
                                            # publisher's published digest
tools/python_pin/verify.sh --no-interpreter # skip the interpreter check
tools/python_pin/verify.sh --record observed-checksums.txt  # destination must not already exist
```

Exit codes: `0` passed, `1` a check failed, `2` the command could not run.
`--archive` compares the file you supply; it downloads nothing. To reproduce
the publisher digest checks yourself:

```sh
curl -sS -L 'https://www.python.org/ftp/python/3.15.2/Python-3.15.2.tgz' | shasum -a 256
curl -sS -L 'https://www.python.org/ftp/python/3.15.2/Python-3.15.2.tar.xz' | shasum -a 256
curl -sS -L 'https://www.python.org/ftp/python/3.15.2/python-3.15.2-macos11.pkg' | shasum -a 256
curl -sS -L 'https://www.python.org/ftp/python/3.15.2/python-3.15.2-amd64.exe' | shasum -a 256
```

To reproduce the Sigstore authentication, follow the isolated-venv procedure
in [docs/PYTHON_TOOLCHAIN_EVIDENCE.md](PYTHON_TOOLCHAIN_EVIDENCE.md) section 4
(hash-pinned sigstore-python 4.6.0 requirements, bundle path, signer identity,
OIDC issuer, negative controls). `verify.sh` deliberately does not perform
signature verification; it reports the recorded result and its scope.

The recorded pin data is in `tools/python_pin/pin/`; see
`tools/python_pin/README.md` for the rules that keep a local digest or a
published-digest match from being mistaken for authentication.

## Changing the pin

Per PLAN.md M0.1 the pinned asset-generation Python changes only through a
recorded regression decision: the reason for the change, the new exact
version, the new published digests and signer identity, and the verification
status, recorded here and in `tools/python_pin/pin/python.txt` together. The
verification status is stored as narrowly scoped, dated fields (publisher
digest match, publisher Sigstore result, installed-binary authentication,
Homebrew channel status) rather than one broad flag, so a positive artifact
result can never be read as verification of an installed interpreter. Do not
track a moving "latest stable" download.

## Related records

* [docs/PYTHON_TOOLCHAIN_EVIDENCE.md](PYTHON_TOOLCHAIN_EVIDENCE.md) — the
  independent provenance and Sigstore verification record (owned elsewhere;
  summarized here, not edited by this integration).
* [docs/evidence/python-3.15.2-source-verification.md](evidence/python-3.15.2-source-verification.md)
  — the earlier source-tarball check that preceded the all-artifact evidence.
* `docs/SETUP.md` is owned elsewhere and still describes the pre-evidence
  status (`upstream_verified=no`, no Sigstore); its owner should refresh those
  lines against this record. This file no longer carries a broad
  `upstream_verified` field.
