# M0.1 private-prefix verify-then-extract record

Date: 2026-11-27. Host: `mac-studio-2026-32-1.home`, macOS 27.0.1 (26A434),
arm64. Checkout: `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm`.

This record covers one bounded execution, the coordinator's `toolchain-m01`
run, followed by independent re-checks in the `m01-evidence-20261127` job. The
coordinator used the cached official macOS editor ZIP, downloaded the official
4.7.2 export-template TPZ, copied the official python.org macOS installer into
its job directory, and extracted each into a project-private prefix **only
after** its publisher digest matched. The evidence job re-computed the digests,
re-ran the offline Sigstore check and re-verified the source-snapshot identity
on the same day. The evidence job changed no Git object or state, tracked file,
installed tool, credential or GUI, spawned no helper and installed nothing
system-wide; the coordinator's recorded scripts wrote only under its ignored
`work/agents/` prefix.

## Result

* The cached official **Godot 4.7.2 macOS editor ZIP** matched the publisher's
  `SHA512-SUMS.txt` line before `ditto -x -k` extraction into `$PREFIX/editor`.
* The **Godot 4.7.2 export-template TPZ**, downloaded by the coordinator job,
  matched the same publisher checksum before extraction;
  `tools/ci/ci.sh install-templates` independently re-checked its pinned
  SHA-512 and refused to extract until it matched.
* **`ci.sh test --require-tests`** ran against the git-archive source snapshot
  with the private editor: **PASS (1 check)**.
* The official **Python 3.15.2 macOS `.pkg`** matched its published SHA-256 and
  its Sigstore bundle hash; offline Sigstore verification against
  `hugo@python.org` returned `OK`; `pkgutil --expand-full` then produced a
  runnable 3.15.2 interpreter in `$PREFIX/python-pkg`.

This is **not** M0.1 signoff, not a target-platform launch, not full Godot
bundle verification, and not Homebrew publisher authentication. See
[Limitations](#limitations).

## Artifacts, digests and snapshot identity

Publisher authority for Godot is the release's `SHA512-SUMS.txt`; publisher
authority for Python is the SHA-256 values recorded from the python.org release
page in `tools/python_pin/pin/python.txt`. Sizes are bytes observed locally.

| Artifact | Size | Digest |
| --- | ---: | --- |
| Godot 4.7.2 macOS universal editor ZIP | 170,622,178 | SHA-512 `38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca` |
| Godot 4.7.2 export templates TPZ | 1,281,349,702 | SHA-512 `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079` |
| Python 3.15.2 macOS installer `.pkg` | 81,894,859 | SHA-256 `2c6104475535b720b45774c68b0dfc9fcca2235353cf9ff81e05488f89845396` |
| Its Sigstore bundle | 7,130 | SHA-256 `2e7a16ed396c33c8c201f9d0e42c4f0fc213ab474bf9389c54adbd58d70a15f2` |
| Source snapshot tar (`git archive`, this host) | 14,530,560 tar | SHA-256 `e82f05e4469beadff01b6cc16b8ceb5f2fd637dd9d36b287668c99379528318e` |

Source snapshot identity:

* Commit `1e99b2d4afaba3509bd7903efbb677465c1ea318`
  (`Keep empty training requests live and reconcile tick evidence`,
  commit date `2026-11-27T15:35:22+01:00`).
* `git archive --format=tar 1e99b2d` produces 888 files and the tar digest
  above. The evidence job reproduced that archive and ran `diff -rq` against
  the coordinator's `source/` tree: **no differences**. The CI runs used this
  snapshot as `--project`, so their inputs are bound to that commit. The tar
  digest is a local observation of `git archive` output on this host; the
  commit hash and the 888-file tree are the durable identity.

Private artifacts derived during the run:

* Editor binary
  `$PREFIX/editor/Godot.app/Contents/MacOS/Godot`:
  SHA-256 `c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf`,
  equal to the editor member streamed out of the verified ZIP.
* Private template tree version.txt:
  SHA-256 `38885c88f75abbc797a1db7559719800279a00cfb9fa8b2e2868a7f6f84bad2e`,
  content `4.7.2.stable`.
* Private Python interpreter:
  SHA-256 `a35b08329e2ecf79a151f8954695d43d6f584ee8483c890295200eaad99c14b7`;
  framework dylib `…/Versions/3.15/Python`:
  SHA-256 `020aed5774ec6ccba7b4522e32c9d11958e6ef83e89030890d04053e443fc2e4`.
  These two digests describe what the verified `.pkg` expands to; python.org
  publishes no per-file values for the expanded tree.

## Verification happened before extraction

### 1. Godot editor ZIP, then private extraction

```sh
ZIP=<official Godot_v4.7.2-stable_macos.universal.zip>
SUMS=<publisher SHA512-SUMS.txt>
expected_editor=38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca
actual_editor=$(shasum -a 512 "$ZIP" | awk '{print $1}')
[ "$actual_editor" = "$expected_editor" ] || { echo 'editor digest mismatch' >&2; exit 1; }
printf 'VERIFIED editor sha512=%s\n' "$actual_editor"
# VERIFIED editor sha512=38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca
grep 'Godot_v4.7.2-stable_macos.universal.zip' "$SUMS" | awk '{print $1}'  # same line

[ ! -e "$PREFIX/editor/Godot.app" ] || exit 1   # refuse to overwrite
mkdir -p "$PREFIX/editor"
ditto -x -k "$ZIP" "$PREFIX/editor"             # extraction only after the match

"$PREFIX/editor/Godot.app/Contents/MacOS/Godot" --headless --version
# 4.7.2.stable.official.ed1daf0bf
shasum -a 256 "$PREFIX/editor/Godot.app/Contents/MacOS/Godot"
# c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf
unzip -p "$ZIP" 'Godot.app/Contents/MacOS/Godot' | shasum -a 256
# c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf
codesign --verify --deep --strict "$PREFIX/editor/Godot.app"
# valid on disk; satisfies its Designated Requirement
```

The recorded script guards the digest comparison with `|| { echo mismatch;
exit 1; }`; extraction is a later statement and never runs on mismatch. The
digest agreement is publisher-checksum evidence over HTTPS origin, **not** a
cryptographic signature over the Godot archive; none is recorded.

### 2. Export templates, then private installation

```sh
TPZ=<official Godot_v4.7.2-stable_export_templates.tpz>
expected_templates=ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079
actual_templates=$(shasum -a 512 "$TPZ" | awk '{print $1}')
[ "$actual_templates" = "$expected_templates" ] || { echo 'templates digest mismatch' >&2; exit 1; }
printf 'VERIFIED templates sha512=%s\n' "$actual_templates"
# VERIFIED templates sha512=ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079

GODOT_BIN="$PREFIX/editor/Godot.app/Contents/MacOS/Godot" NO_COLOR=1 \
  "$SNAPSHOT/tools/ci/ci.sh" --project "$SNAPSHOT" --out "$PREFIX/ci-out" \
  install-templates --archive "$TPZ" --dest "$PREFIX/export_templates"
# [ci:ok] export templates archive sha512: sha512 matches the pinned digest
# [ci:ok] the archive matches the pinned digest and may be extracted
# [ci:ok] staged templates: version.txt reports 4.7.2.stable
# [ci:ok] templates: macOS preset 'macOS Apple Silicon' … -> macos.zip
# [ci:ok] templates: Windows preset 'Windows x86-64' … -> windows_release_x86_64.exe …
# [ci:ok] templates: Linux preset 'Linux x86-64' … -> linux_release.x86_64
# [ci:ok] install-templates: PASS

shasum -a 256 "$PREFIX/export_templates/4.7.2.stable/version.txt"
# 38885c88f75abbc797a1db7559719800279a00cfb9fa8b2e2868a7f6f84bad2e
```

`$SNAPSHOT` below is the `git archive 1e99b2d` tree described above.
`cmd_install_templates` (`tools/ci/ci.sh`) computes the archive SHA-512 again
and returns failure before its staging/extraction step if it does not equal
`templates_archive_sha512` in `tools/ci/pin/engine.txt`. The version/tag fields
come from `tools/toolchain/pin/engine.txt`. A standalone
`ci.sh verify-templates --archive "$TPZ"` performs the same digest gate; it
was not a separate step in this run because `install-templates` enforces it.

### 3. Official Python `.pkg`, then private expansion and execution

The `.pkg` was copied into the coordinator's job directory (`cp -n`) and
hashed there; the retained `.sigstore` bundle came from the earlier Python
evidence job.

```sh
PKG=<official python-3.15.2-macos11.pkg>
BUNDLE=<python-3.15.2-macos11.pkg.sigstore>

shasum -a 256 "$PKG"     # 2c6104475535b720b45774c68b0dfc9fcca2235353cf9ff81e05488f89845396
shasum -a 256 "$BUNDLE"  # 2e7a16ed396c33c8c201f9d0e42c4f0fc213ab474bf9389c54adbd58d70a15f2

"$J/venv/bin/python" "$J/raw/sigstore_isolated.py" verify identity --offline \
  --bundle "$BUNDLE" --cert-identity hugo@python.org \
  --cert-oidc-issuer https://github.com/login/oauth "$PKG"
# WARNING  TUF repository is loaded in offline mode; updates will not be performed
# OK: <PKG>

[ ! -e "$PREFIX/python-pkg" ] || exit 1
pkgutil --expand-full "$PKG" "$PREFIX/python-pkg"   # expansion only; no installer scripts
mkdir -p "$PREFIX/python-fw/Library/Frameworks"
ln -s "$PREFIX/python-pkg/Python_Framework.pkg/Payload" \
      "$PREFIX/python-fw/Library/Frameworks/Python.framework"

PY="$PREFIX/python-pkg/Python_Framework.pkg/Payload/Versions/3.15/bin/python3.15"
DYLD_FALLBACK_FRAMEWORK_PATH="$PREFIX/python-fw/Library/Frameworks" \
  "$PY" -I -c 'import sys; print(sys.version); print(sys.executable); print(sys.prefix)'
# 3.15.2 (v3.15.2:5e58eaad7c5, Oct 25 2026, 14:19:34) [Clang 21.0.0 …]
# $PREFIX/python-pkg/…/bin/python3.15
# $PREFIX/python-pkg/…/Versions/3.15
```

`pkgutil --check-signature` separately reports Apple platform signing of the
`.pkg`: `Developer ID Installer: Python Software Foundation (BMM5U3QVKW)`,
`Notarization: trusted by the Apple notary service`, timestamp
`2026-10-25 21:36:37 +0000`. The `--offline` verifier uses TUF metadata
already cached by the earlier Python evidence job and performs no network
fetch. Wrong-identity, wrong-issuer and tampered-artifact negative controls
for these bundles are recorded in `docs/PYTHON_TOOLCHAIN_EVIDENCE.md` §4.

### 4. Headless test with the private editor and source snapshot

`$SNAPSHOT` is the same `git archive 1e99b2d` tree.

```sh
NO_COLOR=1 "$SNAPSHOT/tools/ci/ci.sh" --project "$SNAPSHOT" \
  --godot "$PREFIX/editor/Godot.app/Contents/MacOS/Godot" \
  --out "$PREFIX/ci-test-out" test --require-tests
# [ci:ok] import: no engine errors in the scratch copy
# [ci:warn] 1 engine warning … (nested res://tools/tick_probe/project.godot;
#          accepted in warnings.allow; surfaced, not fatal)
# [ci:ok] PASS: res://tools/smoke/boot_smoke.gd
# [ci:ok] exit-code proof: a deliberately failing check exited 3 (nonzero)
# [ci:ok] exit-code proof: tools/smoke/boot_smoke.gd --expect-failure exited 1
# [ci:ok] test: PASS (1 check(s))
```

`--require-tests` fails when no checks are discovered; this run discovered one
and passed it. Scratch copies and logs stayed under `--out`; the shared
`.godot/` cache was not written.

## Private tools versus pre-existing host installations

The verified artifacts were extracted only into ignored prefixes under
`work/agents/`. They are distinct from the host installs, which predate
verification:

| Tool | This run's private copy | Pre-existing host install (not modified) |
| --- | --- | --- |
| Godot editor | Extracted from the verified ZIP into `$PREFIX/editor`; binary `c7cccbf8…` | `/Applications/Godot.app` via Homebrew cask, installed 2026-11-05/06, before artifact verification |
| Export templates | Installed from the verified TPZ into `$PREFIX/export_templates`; `version.txt` `38885c88…` | `~/Library/Application Support/Godot/export_templates/4.7.2.stable`, created 2026-11-05, before verification |
| Python 3.15.2 | Expanded from the verified `.pkg` into `$PREFIX/python-pkg`; interpreter `a35b0832…` | Homebrew build at `/opt/homebrew/opt/python@3.15`, installed 2026-11-06, before verification; **no publisher authentication** |

No PATH, environment, installer or system location was changed. The private
editor's binary happens to be byte-identical to the host editor because both
derive from the same official ZIP member; that equality does not move the
host's install time earlier, and this record does not reorder the host's
history.

## Reproducing this record

1. Obtain the official release assets named in `tools/toolchain/pin/engine.txt`
   and `tools/ci/pin/engine.txt`; obtain `python-3.15.2-macos11.pkg` and its
   `.sigstore` bundle from the python.org 3.15.2 release directory.
2. Recompute every digest above and compare with the publisher sources before
   extracting anything.
3. Create `$SNAPSHOT` with `git archive --format=tar 1e99b2d | tar -x`; confirm
   the tar SHA-256 above.
4. Run the three command blocks in order. Each extraction/expansion step must
   come after its own successful digest check.
5. Optional: re-run `ci.sh verify-templates --archive "$TPZ"` before
   `install-templates`, and run the headless test with `--require-tests`.

Pins and prior narrative records remain authoritative: `PLAN.md` M0.1,
`docs/TOOLCHAIN.md`, `docs/PYTHON_TOOLCHAIN.md`,
`docs/PYTHON_TOOLCHAIN_EVIDENCE.md`, `docs/evidence/godot-4.7.2-archive-verification.md`.

## Limitations

* **No M0.1 signoff.** The read-only audit's closure conditions remain open;
  this record supplies verify-then-extract evidence for private copies, not an
  approval decision.
* **Host installs are not covered by this ordering.** The `/Applications/Godot.app`,
  host templates and Homebrew Python predate their artifact verification (audit
  §2). Nothing here retroactively authenticates them.
* **Godot evidence is publisher-checksum agreement, not an archive signature.**
  Selected members were compared; other bundle files and non-target templates
  were not. Full-bundle verification remains undone.
* **No target-platform launch.** On this host only the macOS editor executed
  from the private copy (headless version probe and the headless CI checks).
  No exported game or template binary was launched, and the Windows/Linux
  template binaries were not executed on this host.
* **Python scope.** The verified `.pkg` bytes and their Sigstore authentication
  are established, and those bytes expand to a working 3.15.2 interpreter. This
  is not a reproducibility claim about a rebuilt binary, and it says nothing
  about the Homebrew channel. `pip` is absent because the package's postinstall
  was deliberately not run. python.org publishes no Linux x86-64 binary.
* **Scratch lifetime.** Prefixes, extracted trees, logs and the snapshot tar
  live under ignored `work/agents/` directories and may be removed; the tracked
  pins and this document are the durable record. No credentials or raw
  third-party logs are copied here.

## Sources

* `PLAN.md` M0.1 and M0 acceptance text.
* Read-only audit: `work/agents/78c4da63-ed43-4b99-bc4b-940309811cfe/REPORT.md`.
* Preparation: `work/agents/m01-reinstall-20261127/REPORT.md`.
* Coordinator execution scripts and logs:
  `work/agents/coordinator/toolchain-m01/verify_then_extract.{sh,log}`,
  `verify_then_expand_python.{sh,log}`, `private-editor-test.log`.
* Pins: `tools/toolchain/pin/engine.txt`, `tools/toolchain/pin/checksums.txt`,
  `tools/ci/pin/engine.txt`, `tools/python_pin/pin/python.txt`.
