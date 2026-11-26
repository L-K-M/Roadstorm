# Asset-generation Python toolchain (PLAN.md M0.1)

Status: recorded 2026-11-26 on the development Mac
(`mac-studio-2026-32-1.home`, macOS 27.0.1, arm64) by the M0.1
asset-generation Python pin research job (StepFun 5 Preview). Ownership:
`docs/PYTHON_TOOLCHAIN.md` and `tools/python_pin/**`; nothing else in the
checkout was touched, nothing was installed, and no global Python
installation was altered. This record concerns the **asset-generation
interpreter** only; the engine pin is `docs/TOOLCHAIN.md` /
`tools/toolchain/**` and is not duplicated here.

**Bottom line:** the proposed pin is **CPython 3.15.2, exact**, from the
official python.org release
(<https://www.python.org/downloads/release/python-3152/>), whose per-artifact
**SHA-256 digests are published on the release page** and whose artifacts
carry **Sigstore** verification bundles. No official artifact was downloaded
(each is ≥ 26.7 MB and this job's limit was 1 MB), so the initial worker recorded the published digests as *transcribed, not verified*. The coordinator later checked the source tarball; the remaining artifacts stay open: `upstream_verified=no`. A local interpreter
whose version string reads 3.15.2 is **not** the official artifact and is not
evidence about it.

## Local Python inventory (observations only)

Nothing was installed or changed to produce this table. "Provenance" is what
the machine reports about each interpreter; it is not a claim about any
publisher.

| Interpreter | Version | Provenance | Binary digested (sha256 in `tools/python_pin/pin/checksums.txt`) |
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
  distributors; the Xcode one ships with the Command Line Tools. Their
  digests pin *local files* so later runs can detect change — nothing more.
* The local 3.15.2 (Homebrew) and the pinned 3.15.2 (python.org) would be
  *different files*: same version string, different build, different digest.
  The script therefore never treats a version match as authentication.
* Existing project scripts (`tools/asset_manifest/**`, `tools/tick_probe/**`,
  `tools/smoke/fault_injection.sh`) run on any reasonably recent `python3`
  and are unaffected by this pin. CI (`tools/ci/`, `.github/workflows/`) still
  uses whatever interpreter the runner provides; adopting this pin there is a
  separate decision for those paths' owners.

## Official release source and published checksums

The version authority for CPython is **python.org itself**: the release page
(`/downloads/release/python-XXXX/`) and the artifact tree
(`/ftp/python/<version>/`). Both were fetched over HTTPS on 2026-11-26; URL
liveness was additionally confirmed with range requests, and **no artifact
content was downloaded by that worker**.

What python.org publishes per release, observed on the 3.15.2 page:

| Mechanism | Status for 3.15.2 |
| --- | --- |
| Per-artifact **SHA-256 checksum** | Published on the release page for every artifact (transcribed below) |
| **Sigstore** verification bundle (`<artifact>.sigstore`) | Published next to every artifact in the FTP tree; Sigstore is the advertised signing method from the 3.14 series onward (PEP 761) |
| Signer identity for Sigstore verification | `hugo@python.org` via OIDC issuer `https://github.com/login/oauth` (PEP 790, release manager of 3.15) |
| SPDX SBOM (`.spdx.json`) | Published for the source tarballs and Windows artifacts; **not** published for the macOS installer |
| Legacy OpenPGP (`.sig`) | Present in the FTP directory; not advertised on the release page |

The verification procedure python.org documents
(<https://www.python.org/download/sigstore/>) requires the artifact, its
`.sigstore` bundle, prior knowledge of the signer identity, and a Sigstore
client. It was **not performed** here (it needs the multi-megabyte
artifacts).

### Published digests transcribed from the 3.15.2 release page

Release date **2026-10-25**. These are the publisher's published values as
read over HTTPS; at that time they had not been compared against artifact bytes.

| Pinned artifact | Platform role | Size | Published SHA-256 |
| --- | --- | --- | --- |
| `python-3.15.2-macos11.pkg` | macOS, universal2, macOS 10.15+ | 78.1 MB | `2c6104475535b720b45774c68b0dfc9fcca2235353cf9ff81e05488f89845396` |
| `python-3.15.2-amd64.exe` | Windows x86-64 installer | 35.9 MB | `06e225a228191b0f4d1dcf6905fbb21bf9f6970d13a2ec63137ab9bee76f15aa` |
| `Python-3.15.2.tar.xz` | source (Linux x86-64 builds) | 26.7 MB | `8b5536d280142ecf6cdfe15d12a21ba1c65e300bbf7b28a8d0cdb849575797de` |
| `Python-3.15.2.tgz` | source (gzip) | 34.2 MB | `f74e1db0eabd651cd01e4e2a00201bd41866abe74869ab716f9bf33cbbaa0943` |

Cross-platform coverage, stated honestly: macOS and Windows x86-64 have
official **binary** installers. **python.org publishes no Linux binary
artifact**, so a Linux x86-64 interpreter at this pin is a local build from
the pinned source tarball; its digest cannot be checked against any
publisher digest, only the source tarball's can. Other artifacts exist for
the same release (Windows ARM64, 32-bit, embeddable packages, Android, iOS)
and are outside this project's three target platforms; they are recorded as
present, not pinned.

## The proposed pin and why

**Pin: CPython 3.15.2, exact patch, from python.org.** Stored in
`tools/python_pin/pin/python.txt` with the published digests above;
`tools/python_pin/verify.sh` checks it.

Why 3.15.2:

* It is the **newest stable maintenance release** (2026-10-25) and an
  *expedited security release*: it blocks the compromised eMudhra
  intermediate CA keys (CVE-2026-115557) among ~130 fixes since 3.15.1.
  **3.15.0 and 3.15.1 predate that fix and must not be pinned.**
* Support runway: 3.15.0 was released 2026-10-09, so under the standard
  two-year bugfix cycle the 3.15 series stays in bugfix into late 2028 and in
  security support beyond — the longest runway of any current branch, which
  matters for a multi-year asset pipeline.
* All three target platforms are covered by official artifacts (macOS
  universal2 installer, Windows x86-64 installer, source tarball), each with
  a published SHA-256 and a Sigstore bundle.
* The recording host already runs a 3.15.2 interpreter (Homebrew build), so
  tooling can run at the pinned version immediately, while the official
  artifact itself remains uninstalled.

Alternatives considered and not chosen:

| Candidate | Reason not chosen |
| --- | --- |
| 3.14.10 (2026-10-25 page, bugfix branch since 2025-10-07) | Mature, but its bugfix window ends roughly a year earlier than 3.15's; a worse fit for a long production run. Its published digests remain available if a regression decision ever moves the pin. |
| 3.13.18 | Security-only branch (3.13.0 was 2024-10-07); no new bugfixes. |
| 3.16.0a1/a2 | Pre-release; never pinned. |
| Any "latest stable" pointer | A moving target is not a pin (same rule as the engine pin). |

## Authenticated archive vs installed interpreter

These are different things and this record keeps them apart:

* **Authenticated archive** — an official python.org artifact
  (`python-3.15.2-macos11.pkg`, `python-3.15.2-amd64.exe`, the source
  tarballs). Authentication has two layers: (a) the artifact's SHA-256 equals
  the digest python.org published; (b) the `.sigstore` bundle verifies
  against the signer identity `hugo@python.org` (GitHub OIDC issuer). Layer
  (a) alone is a match against a *published* value; layer (b) is what ties
  the publication to the release manager. **Neither layer was performed
  by the initial worker** — no artifact was downloaded by that worker.
* **Installed interpreter** — any local build (Homebrew 3.15.2 on this host).
  `verify.sh` checks its version string and its local digest. That detects
  version drift and local file change. It says nothing about python.org
  bytes and is never reported as verification.

`verify.sh` prints this distinction on every run, and its summary line
separates "official-artifact checks" from "published-digest upstream
verification".

## Open items (left open, not claimed)

1. **`upstream_verified=no`.** The published digests in `pin/python.txt` are
   transcribed from the release page over HTTPS; no artifact was downloaded by the initial worker
   to compare them against artifact bytes. Closing this requires downloading
   each pinned artifact (≥ 26.7 MB each — over this job's 1 MB limit) plus
   its `.sigstore` bundle, comparing SHA-256, and running a Sigstore client
   against `hugo@python.org`. That is a follow-up with an explicit download
   allowance, not a claim made here.
2. **No Sigstore verification performed**, for the same reason. The recorded
   signer identity and the procedure URL are in `pin/python.txt`.
3. **No official artifact is installed on this host.** The pin exists as data
   and a verifier; installing the official macOS installer (or building from
   the source tarball) is a separate decision with its own regression record,
   and was out of scope for this job.
4. **No global Python was installed, altered, or selected** as a system
   default; no `PATH`, Homebrew, uv or Xcode state was changed.
5. **CI and project scripts do not yet use the pin.** `tools/ci/` and
   `.github/workflows/` belong to other owners; adopting the pin there
   (runner setup, `PYTHON_BIN`, a doctor check) needs their own change.
6. **Linux x86-64 has no official binary artifact**; the source tarball is
   the official source of record for that platform.
7. **The macOS installer publishes no SPDX SBOM** (blank on the release
   page); recorded as absent, not assumed.

## Checks run and results

All commands from the repository root on 2026-11-26; nothing downloaded, no
install performed.

| Command | Result |
| --- | --- |
| `tools/python_pin/verify.sh` | **PASS** (exit 0). Found Homebrew `python3.15` 3.15.2 → version matches the pin, sha256 matches the recorded local observation (`6cc907e4…`); `/usr/bin/python3` 3.9.6 reported as present, version mismatch, not compared. |
| `tools/python_pin/verify.sh --quiet` | PASS (exit 0), summary only. |
| `tools/python_pin/verify.sh --python /usr/bin/python3` | **FAIL** (exit 1): no interpreter reporting the pinned version. Expected behaviour — the escape hatch is `--no-interpreter`. |
| `tools/python_pin/verify.sh --archive /tmp/…/Python-3.15.2.tar.xz` (13 bytes of wrong content) | **FAIL** (exit 1): sha256 mismatch reported against the published digest. Proves the comparison path; a genuine artifact PASS was not demonstrated by the worker; the subsequent source tarball check is recorded below. |
| `tools/python_pin/verify.sh --archive …/some-other-file.exe` | **FAIL** (exit 1): not a pinned artifact. |
| `tools/python_pin/verify.sh --archive …/nope.pkg` | **FAIL** (exit 1): archive not found. |
| `tools/python_pin/verify.sh --record /tmp/…/observed.txt` | PASS (exit 0); wrote observed local digests only. |
| `tools/python_pin/verify.sh --no-interpreter` | PASS (exit 0) with a `[warn]` that the interpreter check was skipped. |
| `tools/python_pin/verify.sh --help` / `--bogus` | exit 0 / exit 2 (usage error). |
| `sh -n tools/python_pin/verify.sh` | syntax OK (no shellcheck available on the host). |

Upstream facts re-verified while recording (all read-only, HTTPS):
`/downloads/` and `/ftp/python/` list 3.15.2 as the newest stable patch
(3.15.3 → 404; 3.16.0 is alpha-only); the 3.15.2 release page publishes the
SHA-256 column and `.sigstore` links; `python-3.15.2-macos11.pkg`,
`python-3.15.2-amd64.exe`, `Python-3.15.2.tar.xz` and
`Python-3.15.2.tar.xz.sigstore` all answer range requests (`206`).

## Reproducing this record

```sh
tools/python_pin/verify.sh                  # local interpreter check + the
                                            # archive/interpreter distinction
tools/python_pin/verify.sh --python <path>  # a specific interpreter
tools/python_pin/verify.sh --archive <file> # an official artifact vs the
                                            # publisher's published digest
tools/python_pin/verify.sh --record out/observed-checksums.txt
```

Exit codes: `0` passed, `1` a check failed, `2` the command could not run.
The recorded pin data is in `tools/python_pin/pin/`; see
`tools/python_pin/README.md` for the rules that keep a local digest from
being mistaken for verification.

## Changing the pin

Per PLAN.md M0.1 the pinned asset-generation Python changes only through a
recorded regression decision: the reason for the change, the new exact
version, the new published digests and signer identity, and the
upstream-verification status, recorded here and in
`tools/python_pin/pin/python.txt` together. Do not track a moving "latest
stable" download.

## Subsequent source archive check

The coordinator verified the source tarball against the published SHA-256; see [the evidence record](evidence/python-3.15.2-source-verification.md). Other artifacts, Sigstore authentication, and local interpreter provenance remain open.
