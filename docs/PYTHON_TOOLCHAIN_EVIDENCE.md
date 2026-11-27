# Python toolchain evidence — selected interpreter provenance (PLAN.md M0.1)

Status: recorded 2026-11-27 on `mac-studio-2026-32-1.home` (macOS 27.0.1
`26A434`, arm64) by job `4dca64d7-9068-48dc-8c3a-c563400d7d85`: an initial
read-only pass, followed by the authorized Sigstore follow-up described in
section 4. Ownership: `docs/PYTHON_TOOLCHAIN_EVIDENCE.md` only. Nothing else
in the checkout was edited, no Git state was changed, no secrets were
inspected, and no GUI was used. The follow-up installed pinned development
tools only into an isolated virtual environment under the job's ignored
directory, with its caches there; it did not modify global Python, global
packages, global configuration, or any installed tool. Downloads were limited
to public read-only checksum/signature evidence from python.org, Homebrew's
formula API/repository, one Homebrew patch file, and the hash-pinned verifier
requirements from the sigstore-python repository. Raw command logs and
machine-readable comparisons are in the job's ignored directory:
`work/agents/4dca64d7-9068-48dc-8c3a-c563400d7d85/raw/`.

**This record does not claim M0.1 acceptance.** It investigates what the
actually selected interpreter is and how far its provenance can be tied to
primary sources.

## Bottom line

The selected interpreter is **Homebrew core `python@3.15` 3.15.2**, an arm64
bottle (`3.15.2.arm64_golden_gate`) poured on 2026-11-06. The selected
interpreter is **not** a python.org release binary. The version string matching the pin is a local-build observation,
not authentication.

What is established here:

* The executed file, its symlink chain, version/build configuration, and local
  sha256 are recorded and reproducible.
* The Homebrew distribution channel is tied together: the cached bottle
  tarball's sha256 equals the digest published by Homebrew in five separate
  records; the bottle manifest's sha256 equals the formula's recorded manifest
  digest; the formula's source URL and sha256 equal python.org's published
  values; the applied Homebrew patch's sha256 equals the digest in Homebrew's
  internal package metadata.
* The installed Cellar tree matches that verified bottle: 3902 files are
  byte-identical, 97 differ only in Homebrew's documented pour-time prefix
  relocation/ad-hoc signature handling, and 336 extra files are runtime bytecode
  caches plus the install receipt. Across all differing Mach-O files, every
  code/data section compared is byte-identical except zero-initialized BSS
  sections.
* All four pinned python.org artifacts' bytes were re-checked in this job
  against the digests python.org publishes: `Python-3.15.2.tgz`,
  `Python-3.15.2.tar.xz`, `python-3.15.2-macos11.pkg`, and
  `python-3.15.2-amd64.exe` all matched.

What remains open: the installed binary cannot be equal to a python.org
macOS installer because Homebrew builds with different configure flags; the
Homebrew API JWS payload was not cryptographically verified; and the Linux
target has no publisher binary to compare. Sigstore authentication of all
four pinned artifacts was performed in a later authorized follow-up using an
isolated verifier environment; it authenticates the publisher bytes and signer
identity only, not the installed Homebrew build (section 4). The earlier
source-tarball check establishes the *source* of the distributor build only;
it does not prove anything about the separately built installed binary.

## 1. Selected executable (local observations)

Project scripts call plain `python3`; on this host `/opt/homebrew/bin`
precedes `/usr/bin` on `PATH`, so `python3` resolves into the Homebrew Cellar.
`tools/python_pin/verify.sh` selects the same file by looking for
`python3.15`. `/usr/bin/python3` is the Xcode Command Line Tools 3.9.6
launcher and is not the selected interpreter.

Resolution chain:

```
/opt/homebrew/bin/python3
  -> ../Cellar/python@3.15/3.15.2/bin/python3
     -> ../Frameworks/Python.framework/Versions/3.15/bin/python3
        -> python3.15   (regular file)
/opt/homebrew/bin/python3.15
  -> ../Cellar/python@3.15/3.15.2/bin/python3.15
     -> ../Frameworks/Python.framework/Versions/3.15/bin/python3.15
/opt/homebrew/opt/python@3.15 -> ../Cellar/python@3.15/3.15.2
```

Executed file and digest:

| Item | Value |
| --- | --- |
| Real path | `/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15` |
| Size / format | 34,640 bytes; Mach-O thin arm64 |
| sha256 | `6cc907e4a022fefc843bcd93954eaf5a2cbfc77a095640bfadeeed96154190c5` |
| `-VV` | `Python 3.15.2 (main, Oct 25 2026, 16:57:51) [Clang 21.0.0 (clang-2100.3.34.2)]` |
| Build / compiler | `('main', 'Oct 25 2026 16:57:51')`, `Clang 21.0.0 (clang-2100.3.34.2)`, CPython |
| Platform | `macosx-27.0-arm64`, `platform.platform()` = `macOS-27.0.1-arm64-arm-64bit-Mach-O` |
| `sys.executable` as reported | `/opt/homebrew/opt/python@3.15/bin/python3.15` (Homebrew `sitecustomize.py` rewrites the prefix at startup) |
| `sys.prefix` / `base_prefix` | `/opt/homebrew/opt/python@3.15/Frameworks/Python.framework/Versions/3.15` |
| Code signature | ad-hoc; identifier `python3-55554944e9d00cc08b2730af91d9f8cbc50e2ba2`; no `TeamIdentifier`; `codesign --verify --strict` = valid on disk |

This digest matches the local observation already recorded in
`tools/python_pin/pin/checksums.txt` (`local_interpreter_315_sha256`), and
`NO_COLOR=1 tools/python_pin/verify.sh` currently exits 0 with "interpreter
version matches the pin (3.15.2)" and "interpreter sha256 matches the recorded
LOCAL observation". That script itself prints that a local build is never
evidence about python.org bytes.

Notable configure facts from `_sysconfigdata__darwin_darwin.py` /
`sysconfig.get_config_var("CONFIG_ARGS")`:

* `--prefix=/opt/homebrew/opt/python@3.15`, framework layout under
  `/opt/homebrew/opt/python@3.15/Frameworks`.
* `--enable-optimizations`, `--with-lto`, `--with-tail-call-interp`,
  `MACOSX_DEPLOYMENT_TARGET=27`, `--with-openssl=/opt/homebrew/opt/openssl@4`,
  `--with-system-expat`, `--with-system-libmpdec`, `--without-ensurepip`.
* The Homebrew formula comments explicitly say `--enable-optimizations` and
  `--with-lto` "diverge from what upstream python does for their macOS binary
  releases", which is why a Homebrew build cannot be byte-equal to the
  python.org installer.

## 2. Distributor/channel verification (Homebrew)

All paths below are on this host; all URLs are the primary sources used.

| Record | Path / URL | Key value |
| --- | --- | --- |
| Install receipt | `/opt/homebrew/Cellar/python@3.15/3.15.2/INSTALL_RECEIPT.json` | `poured_from_bottle: true`, `built_as_bottle: true`, `loaded_from_api: true`, `loaded_from_internal_api: true`, `arch: arm64`, tap `homebrew/core`, source spec `stable` 3.15.2; receipt time `1793963609` = 2026-11-06T11:13:29Z; built_on macOS 27.0 / Xcode 27.0 / CLT 27.0.0 / clang |
| Installed formula | `/opt/homebrew/Cellar/python@3.15/3.15.2/.brew/python@3.15.rb` (sha256 `a9a91304…`) | `url https://www.python.org/ftp/python/3.15.2/Python-3.15.2.tgz`; `sha256 f74e1db0…`; patch `Patches/python/3.13-sysconfig.diff`; configure args as above |
| Bottle tarball (cached) | `~/Library/Caches/Homebrew/downloads/81adcff5…--python@3.15--3.15.2.arm64_golden_gate.bottle.tar.gz` | size 20,333,889; sha256 `3b1247250932fb08290f3dd05f2e476a958b09600ac9a6e18ff6ab3695cab4ba` |
| Bottle manifest (cached) | `~/Library/Caches/Homebrew/downloads/acf8a6f0…--python@3.15-3.15.2.bottle_manifest.json` | sha256 `625dc15badb74fc019db93e64603b07c38ac842494865436980812cf90346a1f`; annotation `sh.brew.bottle.digest` for `3.15.2.arm64_golden_gate` = `3b124725…` |
| Installed SBOM | `/opt/homebrew/Cellar/python@3.15/3.15.2/sbom.spdx.json` | created 2026-11-06T11:13:29Z by brew 7.0.12; source `https://www.python.org/ftp/python/3.15.2/Python-3.15.2.tgz` digest `f74e1db0…`; bottle blob `https://ghcr.io/v2/homebrew/core/python/3.15/blobs/sha256:3b124725…` |
| Homebrew formula API | `https://formulae.brew.sh/api/formula/python%403.15.json` | `urls.stable.url` = python.org `.tgz`; checksum `f74e1db0…`; bottle `arm64_golden_gate` sha256 `3b124725…` |
| Homebrew core formula (HEAD) | `https://raw.githubusercontent.com/Homebrew/homebrew-core/HEAD/Formula/p/python%403.15.rb` | sha256 `75a937345ba05b51353f167440ce2d31bb1a0ed4aeeba7b05970d5276118008f`; same source sha256 and bottle sha256; `manifest_sha256` = `625dc15…` |
| Homebrew internal API payload | `~/Library/Caches/Homebrew/api/internal/packages.arm64_golden_gate.jws.json.payload` | `stable_checksum f74e1db0…`, `bottle_checksum 3b124725…`, `bottle_manifest_checksum d7ef8740…` (= the arm64 golden-gate OCI manifest digest inside the cached manifest), `ruby_source_checksum 75a93734…` |
| Homebrew patch | `https://raw.githubusercontent.com/Homebrew/homebrew-core/HEAD/Patches/python/3.13-sysconfig.diff` | sha256 `9f2eae1d08720b06ac3d9ef1999c09388b9db39dfb52687fc261ff820bff20c3`; equals the API's `local_patch_checksums` value for that path |

Outcomes worth stating precisely:

* The cached bottle tarball is the exact `3.15.2.arm64_golden_gate` bottle
  digest published by Homebrew (formula API, GitHub formula, SBOM, manifest
  annotation, internal API all agree). This is a checksum agreement with
  Homebrew-published data over HTTPS, not an Apple-notarized signature: the
  bottle and installed binaries are ad-hoc signed.
* The manifest JSON on disk hashes to the `manifest_sha256` recorded in the
  formula, and the internal API's `ruby_source_checksum` equals the GitHub
  HEAD formula's hash.
* The Homebrew patch fetched from Homebrew's repository hashes to the value
  Homebrew's own metadata lists for that patch.
* The formula/SBOM source URL+sha256 point at the python.org `.tgz`; the
  `.tgz` bytes were downloaded in this job and matched the digest python.org
  publishes (section 4).

## 3. Installed tree versus the verified bottle

Method: extracted the cached bottle tarball read-only into the job directory
and walked both trees (`/opt/homebrew/Cellar/python@3.15/3.15.2/` and the
extraction), hashing regular files and comparing symlink targets. No installed
file was modified. Full result: `raw/install-vs-bottle.json`; section-level
result: `raw/section-compare.json`.

| Comparison | Result |
| --- | --- |
| Common entries byte-identical | 3902 |
| Common entries differing | 97 |
| Only in installed tree | 336 |
| Only in bottle | 0 |

The 97 differing entries resolve as follows:

* 16 text/script files match byte-for-byte after replacing Homebrew's
  `@@HOMEBREW_CELLAR@@` / `@@HOMEBREW_PREFIX@@` / `@@HOMEBREW_LIBRARY@@`
  placeholders with `/opt/homebrew/Cellar`, `/opt/homebrew`, and
  `/opt/homebrew/Library` respectively. These are exactly the receipt's
  16-entry `changed_files` list — e.g.
  `_sysconfigdata__darwin_darwin.py`, `sitecustomize.py`,
  `sysconfig/__init__.py`, `Makefile`, `*.pc` files.
* 80 Mach-O files (the interpreter, `libpython` framework library, the
  `Python.app` executable, and 77 extension modules) differ only in Mach-O
  load-command path strings/sizes and the embedded ad-hoc signature. In the
  bottle they contain `@@HOMEBREW_CELLAR@@/python@3.15/3.15.2/...`; in the
  Cellar they contain `/opt/homebrew/Cellar/python@3.15/3.15.2/...`
  (`otool -L` sample in `raw/moc/`).
* `sbom.spdx.json` differs because the installed copy is a larger,
  install-time-generated SBOM (brew 7.0.12, 2026-11-06) that adds dependency
  and bottle entries; the source and bottle digests it records agree with
  section 2.

Section-level comparison of the 97 differing files (copies had their ad-hoc
signatures removed before comparison; installed files untouched): 802 sections
compared; 19 section comparisons differed, all of them zero-initialized
`__bss`, `__common`, or `__thread_bss` sections in 17 files. No `__text`,
`__cstring`, or other initialized code/data section differed. This supports
the interpretation that the installed binaries are the bottle binaries with
Homebrew's pour-time prefix relocation, not a different build.

Installed-tree extras: 335 `__pycache__/*.pyc` files (runtime bytecode caches)
and `INSTALL_RECEIPT.json`. No file exists only in the bottle.

Code-signing observation (open, not fully explained): `codesign --verify
--strict` succeeds for the installed `bin/python3.15` and for sampled
installed extension modules, but fails for the installed framework library
`Frameworks/Python.framework/Versions/3.15/Python` and for
`Resources/Python.app` with "code has no resources but signature indicates
they must be present". An independent context-preserving extraction of the
bottle reproduced the same failure for both framework and app. Bare copies of
the Mach-O binaries passed; adding a parseable bundle `Info.plist` reproduced
the failure. This corrects the earlier comparison, which tested bare copies.
The result is consistent with bundle verification requiring a resource seal
absent from the ad-hoc Mach-O signatures; it does not establish tampering.
See job `00c35fe3-4f0e-4a19-bda3-47cfa50ce2b2` for the controlled matrix,
source analysis and limits.

## 4. Official primary-source checks performed here

Release page re-fetched and parsed on 2026-11-27:
`https://www.python.org/downloads/release/python-3152/`. During the initial
pass each artifact was streamed over HTTPS and hashed without being retained;
sizes below are the server's `Content-Length`. The Sigstore follow-up
downloaded fresh copies into `$JOB/artifacts/` from the same URLs and
re-checked their sha256 before verifying signatures.

| Artifact | Primary URL | Published SHA-256 | Observed SHA-256 | Bytes | Result |
| --- | --- | --- | --- | --- | --- |
| `Python-3.15.2.tgz` | `https://www.python.org/ftp/python/3.15.2/Python-3.15.2.tgz` | `f74e1db0eabd651cd01e4e2a00201bd41866abe74869ab716f9bf33cbbaa0943` | same | 35,882,840 | match |
| `Python-3.15.2.tar.xz` | `https://www.python.org/ftp/python/3.15.2/Python-3.15.2.tar.xz` | `8b5536d280142ecf6cdfe15d12a21ba1c65e300bbf7b28a8d0cdb849575797de` | same | 27,960,396 | match |
| `python-3.15.2-macos11.pkg` | `https://www.python.org/ftp/python/3.15.2/python-3.15.2-macos11.pkg` | `2c6104475535b720b45774c68b0dfc9fcca2235353cf9ff81e05488f89845396` | same | 81,894,859 | match |
| `python-3.15.2-amd64.exe` | `https://www.python.org/ftp/python/3.15.2/python-3.15.2-amd64.exe` | `06e225a228191b0f4d1dcf6905fbb21bf9f6970d13a2ec63137ab9bee76f15aa` | same | 37,694,360 | match |

`tools/python_pin/verify.sh --archive <tgz> --archive <pkg>` was run on
downloaded copies of the `.tgz` and the macOS installer and exited 0 with
"sha256 matches the digest python.org PUBLISHED for 3.15.2" for each; the
large copies were deleted afterwards. This is artifact-versus-published-digest
only, not publisher authentication.

Sigstore bundles were fetched from
`https://www.python.org/ftp/python/3.15.2/<artifact>.sigstore` and hashed
(retained in `raw/*.sigstore`):

| Bundle | sha256 | Bytes |
| --- | --- | --- |
| `Python-3.15.2.tgz.sigstore` | `0fdedee6c00fa4abd2cd377db69737b6ef129cf238546344280ef65a590220a2` | 7,220 |
| `Python-3.15.2.tar.xz.sigstore` | `d1bbd6bb4bd3865d18f5c2cc1ae0da08c2d9f09d6e82729b527ca06f572d62fa` | 7,083 |
| `python-3.15.2-macos11.pkg.sigstore` | `2e7a16ed396c33c8c201f9d0e42c4f0fc213ab474bf9389c54adbd58d70a15f2` | 7,130 |
| `python-3.15.2-amd64.exe.sigstore` | `8b5a848f5e218ee4d0267897c218f6d61a19a620af4fb984ddfcb6c8b2541580` | 7,224 |

### Follow-up: Sigstore cryptographic verification (performed)

A later authorized follow-up performed real signature verification. The
publisher guidance (`https://www.python.org/download/sigstore/`) documents the
CPython 3.15 signer as `hugo@python.org` with OIDC issuer
`https://github.com/login/oauth` (PEP 790) and recommends sigstore-python plus a
hash-pinned requirements file. In this section `$JOB` means
`work/agents/4dca64d7-9068-48dc-8c3a-c563400d7d85`.

Verifier provenance, pinned and hash-enforced:

* Requirements used:
  `https://raw.githubusercontent.com/sigstore/sigstore-python/main/install/requirements.txt`,
  sha256 `9ddb40e33f7412ae6843c68865f12b82ac5078b559e3549bc1d15bb39ce6fdb8`;
  fetched when upstream `main` was commit
  `cee376355556d4624da1e426598e174f305141a7` (commit date 2026-11-24).
* `sigstore==4.6.0`; its two distribution hashes in that file are
  `dc9a7bd0e35ee381a6f70281f520f858d12b34a997c023f7dec835c0095a5067` and
  `df10bc2b87b821df0922405377305b875894e6ce6007175b3eddb3bcc9b23cfa`.
  `python -m sigstore --version` prints `sigstore 4.6.0`.
* Installed into `$JOB/venv` (uv 0.13.7; base interpreter
  `/opt/homebrew/bin/python3`, the already-selected 3.15.2; 26 packages listed
  in `raw/sigstore-venv-package-list.txt`) with
  `uv pip install --require-hashes -r .../requirements.txt`. Every downloaded
  distribution's hash was checked against the pinned file. No global Python,
  site-packages, or tool was modified.
* Verifier caches were confined to `$JOB/tuf-data` and `$JOB/tuf-cache` via
  `raw/sigstore_isolated.py` (platformdirs override). An initial `--offline`
  invocation had copied only the embedded trust root into
  `~/Library/Caches/sigstore-python/tuf/...`; that directory was created by this
  job, contained only `trusted_root.json`/`signing_config.v0.2.json`, and was
  removed afterwards. No other state outside `$JOB` was written.

Exact command per artifact (first run online to refresh TUF; later runs reuse
the job-local cache):

```sh
$JOB/venv/bin/python $JOB/raw/sigstore_isolated.py verify identity -vvv \
  --bundle $JOB/raw/<artifact>.sigstore \
  --cert-identity hugo@python.org \
  --cert-oidc-issuer https://github.com/login/oauth \
  $JOB/artifacts/<artifact>
```

Results, each exit 0, each verbose log showing "Found and verified trusted
root", "Successfully verified signing certificate validity", "successfully
verified inclusion proof"/"inclusion promise", "Successfully verified
signature", then `OK`:

| Artifact | Result |
| --- | --- |
| `Python-3.15.2.tgz` | OK (`raw/sigstore-verify-online-Python-3.15.2.tgz.log`) |
| `Python-3.15.2.tar.xz` | OK (`raw/sigstore-verify-online-Python-3.15.2.tar.xz.log`) |
| `python-3.15.2-macos11.pkg` | OK (`raw/sigstore-verify-online-python-3.15.2-macos11.pkg.log`) |
| `python-3.15.2-amd64.exe` | OK (`raw/sigstore-verify-online-python-3.15.2-amd64.exe.log`) |

Trust roots and verifier internals actually exercised:

* Production Sigstore TUF repository `https://tuf-repo-cdn.sigstore.dev`;
  loaded root v16 (`root_history/16.root.json`, sha256
  `27aea7e372aa7864065174f0661784fcf8b0e28b1dbfebeada31a0f1fb19167f`),
  timestamp v845, snapshot v166, targets v14. The downloaded and TUF-verified
  `trusted_root.json` has sha256
  `6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66`;
  `signing_config.v0.2.json` has sha256
  `9711a6d5375706957a4859af31c5866a4474f81f0544f9f4b76c9c4f4c8a539c`.
  (One initial HTTPS 404 for a nonexistent `17.root.json` during normal root
  history handling did not affect the verified result.)
* Each bundle is `application/vnd.dev.sigstore.bundle.v0.3+json`; its signing
  certificate issuer is `CN=sigstore-intermediate,O=sigstore.dev`, SAN email
  `hugo@python.org`, OIDC issuer extension `https://github.com/login/oauth`,
  valid for 10 minutes on 2026-10-26. Each has one Rekor `hashedrekord` entry
  (log ID key `wNI9atQGlz+VWfO6LRygH4QUfY/8W4RFwiT5i5WRgB0=`) with an inclusion
  promise, an inclusion-proof checkpoint, and one RFC 3161 timestamp. Exact
  serials, indices, and root hashes are in `raw/bundle-cert-details.json`.

Negative controls (all exit 1), proving the checks are enforced rather than
vacuously passing:

* Wrong identity `not-the-signer@example.com` → "Certificate's SANs do not
  match ... actual SANs: {'hugo@python.org'}".
* Wrong OIDC issuer `https://accounts.google.com` → "Certificate's OIDCIssuer
  does not match ...".
* One-byte-appended copy of the `.tgz` → "Bundle message digest mismatch".

This verifies the artifact bytes' signatures against the publisher-documented
identity and issuer. It does **not** authenticate the installed Homebrew
interpreter; those artifacts are not installed (see below).

No official python.org installer is installed: `/Library/Frameworks/Python.framework`
does not exist, `/Applications/Python 3.15` does not exist, and
`/var/db/receipts` contains no python package receipt.

## 5. What is independently verified, and what is only observed

Independently tied to a publisher/distributor record:

* The four pinned python.org artifact digests above, against python.org's
  release page (re-fetched) and the actual bytes.
* The Homebrew bottle tarball digest against five Homebrew-published records;
  the bottle manifest digest against the formula's `manifest_sha256`; the
  Homebrew patch digest against Homebrew's internal package metadata.
* The build source name/digest Homebrew records (`Python-3.15.2.tgz`) against
  python.org's published digest and the actual `.tgz` bytes.
* Sigstore signatures on all four pinned artifacts, verified against
  `hugo@python.org` / `https://github.com/login/oauth` with hash-pinned
  sigstore 4.6.0 in an isolated venv (section 4); wrong-identity,
  wrong-issuer, and tampered-artifact controls all fail.

Local observations only:

* The selected interpreter's identity, path chain, version/build string,
  configure arguments, code-signature state, and local sha256.
* The installed Cellar tree's equality to the verified Homebrew bottle modulo
  the described prefix/signature differences. This is strong distributor-channel
  evidence, but Homebrew's bottle is ad-hoc signed and its API payload was not
  cryptographically verified, so it is not Apple-notarized or publisher-signed
  provenance.
* The `python3` PATH selection by project scripts.

Not verified / not possible here:

* Any equality between the installed binary and a python.org binary artifact.
  The Homebrew build uses flags the formula itself says differ from upstream
  macOS release builds, and the source tarball is the upstream source, not the
  built binary.
* A reproducible rebuild comparison (not performed; LTO/toolchain output is
  not guaranteed deterministic).
* Any Linux x86-64 artifact (python.org publishes none; out of scope here).

## 6. Concrete gaps left open

1. **CLOSED for the four pinned artifacts — Sigstore authentication
   performed.** All four `.sigstore` bundles verified against
   `hugo@python.org` / `https://github.com/login/oauth` with a hash-pinned
   sigstore 4.6.0 in an isolated venv (section 4); negative controls failed as
   expected. Remaining limitation: this authenticates publisher artifact bytes
   only, not the installed Homebrew interpreter. The pin file's
   `upstream_verified` flag is owned elsewhere and was not changed.
2. **OPEN — installed interpreter is not the official binary.** No method can
   make the Homebrew-built `python3.15` equal to `python-3.15.2-macos11.pkg`
   contents; only the build source is tied to python.org bytes. Installing the
   official artifact would be a separate decision and was not done.
3. **OPEN — Homebrew channel trust is checksum-based.** The bottle and
   installed binaries are ad-hoc signed (no Developer ID/notarization). The
   internal API JWS signature was not verified against Homebrew's key.
4. **OPEN — framework code-signing anomaly.** Installed
   `Frameworks/.../Versions/3.15/Python` and `Resources/Python.app` fail
   `codesign --verify --strict`; context-preserving bottle counterparts fail
   the same way, while bare binaries pass. Bundle verification and resource
   sealing remain an open distribution question, not evidence of tampering.
5. **OPEN — Linux x86-64 has no publisher binary.** The source tarball is the
   official record for that platform; no target build/launch was attempted.
6. **OPEN — CI/project scripts still use PATH `python3`**, i.e. the Homebrew
   build; adopting the python.org pin there is a separate owner decision
   (already noted in `docs/PYTHON_TOOLCHAIN.md`).
7. **OPEN — M0.1 acceptance not claimed.** This evidence addresses interpreter
   provenance only; engine/Jolt/templates and other M0.1 items remain per
   `docs/TOOLCHAIN.md` and `docs/STATUS.md`.

## 7. Reproduction

```sh
# selected interpreter identity
command -v python3; readlink -f "$(command -v python3)"
/opt/homebrew/bin/python3 -VV
shasum -a 256 /opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15

# local pin verifier (read-only; writes only if --record is given)
NO_COLOR=1 tools/python_pin/verify.sh

# official artifact digests (streaming; nothing retained)
curl -sS -L 'https://www.python.org/ftp/python/3.15.2/Python-3.15.2.tgz' | shasum -a 256
curl -sS -L 'https://www.python.org/ftp/python/3.15.2/Python-3.15.2.tar.xz' | shasum -a 256
curl -sS -L 'https://www.python.org/ftp/python/3.15.2/python-3.15.2-macos11.pkg' | shasum -a 256
curl -sS -L 'https://www.python.org/ftp/python/3.15.2/python-3.15.2-amd64.exe' | shasum -a 256

# Sigstore verification in an isolated venv under the job directory (follow-up)
export UV_CACHE_DIR="$PWD/uv-cache" UV_PYTHON_INSTALL_DIR="$PWD/uv-python"
uv venv --python /opt/homebrew/bin/python3 "$PWD/venv"
uv pip install --python "$PWD/venv/bin/python" --require-hashes \
  -r "$PWD/raw/sigstore-python-install-requirements.txt"
"$PWD/venv/bin/python" "$PWD/raw/sigstore_isolated.py" verify identity \
  --bundle "$PWD/raw/Python-3.15.2.tgz.sigstore" \
  --cert-identity hugo@python.org \
  --cert-oidc-issuer https://github.com/login/oauth \
  "$PWD/artifacts/Python-3.15.2.tgz"

# distributor records
shasum -a 256 "$HOME/Library/Caches/Homebrew/downloads/81adcff5…--python@3.15--3.15.2.arm64_golden_gate.bottle.tar.gz"
shasum -a 256 "$HOME/Library/Caches/Homebrew/downloads/acf8a6f0…--python@3.15-3.15.2.bottle_manifest.json"
curl -sS -L 'https://formulae.brew.sh/api/formula/python%403.15.json'
curl -sS -L 'https://raw.githubusercontent.com/Homebrew/homebrew-core/HEAD/Patches/python/3.13-sysconfig.diff'
```

Job raw artifacts (`install-vs-bottle.json`, `section-compare.json`,
`placeholder-resolved.json`, `signature-resolved.json`,
`artifact-stream-hashes.log`, `archive-verify.txt`, release-page HTML, fetched
formula/patch/bundles, `bundle-cert-details.json`, `sigstore_isolated.py`,
per-artifact online verification logs, negative-control logs, TUF metadata
under `tuf-data/`/`tuf-cache/`, and verifier artifacts under `artifacts/` and
`venv/`) are under
`work/agents/4dca64d7-9068-48dc-8c3a-c563400d7d85/`.

Companion records: [docs/PYTHON_TOOLCHAIN.md](PYTHON_TOOLCHAIN.md) (pin
rationale and open items) and
[docs/evidence/python-3.15.2-source-verification.md](evidence/python-3.15.2-source-verification.md)
(the earlier source-tarball check).
