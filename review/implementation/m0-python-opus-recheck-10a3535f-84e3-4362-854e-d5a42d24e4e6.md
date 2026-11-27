# M0.1 Python pin/provenance review — Opus recheck (job 10a3535f-84e3-4362-854e-d5a42d24e4e6)

| Field | Value |
| --- | --- |
| Reviewer model / provider | Claude Opus 5.5 (`claude-opus-5-5`) / Anthropic, via Claude Code |
| Date | 2026-11-27 |
| Candidate | `cc5dac91ed89b934defdd6d1240e729791885ccb` (cc5dac9) |
| Base | `7a64abe` |
| Inspected tree | `work/agents/10a3535f-84e3-4362-854e-d5a42d24e4e6/snap` (snapshot as supplied) |
| Prior evidence read | `work/agents/4dca64d7-9068-48dc-8c3a-c563400d7d85/raw/` (+ `artifacts/` listing and small text files), `work/agents/9a09e936-ab0c-4b9b-a85f-e4982025696b/integration-tests/` |
| Not consulted | Any Sol report (including `review/implementation/m0-python-sol-recheck-cc5dac9.md`), coordinator incident notes outside the listed directories |
| Scratch | `work/agents/10a3535f-84e3-4362-854e-d5a42d24e4e6/scratch/` |
| Verdict | **Changes required** (dynamic behavior of verify.sh at cc5dac9 **not verified** by this reviewer — see capability limits) |
| M0 acceptance | **Not claimed and not recommended by this review.** |

## Scope

Files reviewed in full: `tools/python_pin/verify.sh`, `tools/python_pin/README.md`,
`tools/python_pin/pin/python.txt`, `tools/python_pin/pin/checksums.txt`,
`docs/PYTHON_TOOLCHAIN.md`, `docs/PYTHON_TOOLCHAIN_EVIDENCE.md`, PLAN.md M0
section. Against M0.1 ("pin … asset-generation Python, with checksums. Verify
before installation; update only through a recorded regression decision"),
with the requested focus: recorded publisher Sigstore checks vs live digest
checks vs installed Homebrew build; source/target metadata; failure safety;
`--record` behavior; inputs with spaces; evidence limitations.

## Capability limits (read this first)

* In this session every command that executes code was refused by the
  permission layer (non-interactive, approval unavailable): `verify.sh`
  (any mode, including `--help`), `sh <script>`, `shasum`, `git log/diff/
  rev-parse`. Only read-only file viewing (`cat`, `grep`, `sed -n`, `ls`) worked.
* Consequently: **I did not run verify.sh, did not re-hash any artifact or
  bundle, did not re-run Sigstore, did not confirm the snapshot is
  byte-identical to cc5dac9, and did not confirm the base diff.** The
  findings below are from static reading of the snapshot, POSIX sh
  semantics, and the prior jobs' logs. Where a log demonstrates the
  behavior I say so; otherwise the finding is static.
* A prepared read-only inventory script (`scratch/inventory.sh`) was written
  but could not be executed.
* No GUI, no secrets, no Git mutation, no edits to source/assets/shared
  artifacts/installed tools. The only writes are this file and
  `scratch/`.

## What I could confirm (static / from retained evidence)

| Claim | Basis | Result |
| --- | --- | --- |
| Pinned digests equal the release-page SHA-256 values | `raw/python-3.15.2-release-page.html` lines 565, 584, 660, 679 (digests split by `<wbr>`), reassembled by hand | all four match `pin/python.txt` |
| Streamed artifact hashes equal published | `raw/artifact-stream-hashes.log`, `raw/tgz-stream.log` (HTTP 200, Content-Length = pin `_size_bytes`) | match |
| Sigstore OK for all four, identity/issuer enforced | `raw/sigstore-verify-online-*.log` end in `OK:`; `raw/control-{wrong-identity,wrong-issuer,tampered}.log` show the expected errors | consistent with docs |
| Signer identity for 3.15 is `hugo@python.org` | `raw/python-sigstore-doc.html` lines 536–542 | consistent |
| Bundle cert details (issuer, SAN, OIDC ext, Rekor entry, RFC3161) | `raw/bundle-cert-details.json` | consistent with docs |
| macOS pkg "for macOS 10.15 and later" | release page line 647 | consistent (but see N3 for "universal2") |
| Restored `.tgz` re-verified after the symlink incident | `raw/coordinator-restored-sigstore.log`: `OK: artifacts/Python-3.15.2.tgz.restored` (TUF offline mode, 03:06); overwritten content preserved as `artifacts/Python-3.15.2.tgz.altered-20261127` ("not the official archive"); `artifacts/expected-source.sha256` = `f74e1db0…0943`; current `artifacts/Python-3.15.2.tgz` is a regular file of 35,882,840 bytes (mtime 03:06) | consistent; **not re-hashed by me** |
| Scope separation in docs/pin | `installed_interpreter_publisher_authenticated=no`, `homebrew_channel_fully_verified=no`, separate dated `publisher_digest_*` / `publisher_sigstore_*` fields; verify.sh summary separates "publisher artifact evidence" from "installed binary" | good; the three layers are kept apart |
| Source vs target metadata | `*_role` fields; verify.sh prints role per archive and the source-vs-installer paragraph | good |

## Findings (ranked)

### F1 — Medium-High (changes required): paths with spaces/glob characters are word-split
`verify.sh:381-382` accumulates archives as `ARCHIVE_FILES="$ARCHIVE_FILES $2"` and
iterates with unquoted `for _f in $ARCHIVE_FILES` (`:417`, `:366`); interpreter
candidates are iterated as `for _py in $(python_candidates)` (`:405`, `:350`).
Consequences (POSIX field splitting + pathname expansion):
* `--archive "/Users/x/My Downloads/Python-3.15.2.tgz"` is checked as
  `/Users/x/My` and `Downloads/Python-3.15.2.tgz` → "archive not found" → exit 1
  for a correct artifact; `--record` silently omits it (`[ -f ] || continue`).
* `--python "/path with space/python3.15"` / `PYTHON_BIN=…` → no executable
  fragment → "no Python interpreter found" → exit 1.
* A `$HOME` containing spaces breaks the uv/pyenv candidates.
* `--archive '/dl/*.tgz'` is glob-expanded inside the script.
Failure direction is safe (I found no realistic false PASS), but the task's
"inputs with spaces" requirement is not met and no test covers it (all prior
tests use `/var/folders/...` paths without spaces).
**Fix:** process each `--archive` during argument parsing (or store
newline-separated and iterate with `IFS=<newline>` and `set -f`), keep
`PYTHON_BIN` as a single word, and emit candidates newline-separated read via
`while IFS= read -r`. Add tests with a space and a `*` in archive, `--python`
and `--record` paths.

### F2 — Medium (changes required): `--record` truncates its target in place, follows symlinks, and can destroy an input while the run reports PASS
`record_digests` (`:339-372`) does `{ … } >"$RECORD_FILE"` directly. The shell
truncates the target before the group runs, follows a symlink at that path, and
does not check whether the target is an `--archive` input or a pin file.
* `--archive dl/Python-3.15.2.tgz --record dl/Python-3.15.2.tgz`: the archive
  check prints `[ok]` (runs first), then the redirect truncates the archive,
  `sha256_of` hashes the now-truncated file and records
  `archive_Python-3.15.2.tgz_sha256=e3b0c442…b855` (empty-file digest), and the
  run ends **PASS, exit 0** with the artifact destroyed.
* `--record tools/python_pin/pin/checksums.txt` overwrites the digest file; the
  next run then finds no `local_interpreter_315_sha256` and only warns
  `NOT RECORDED` (exit 0), so the drift check silently disappears.
* A pre-existing symlink at the record path writes into the link target — the
  same mechanism as the 2026-11-27 incident (a redirect through a symlink into
  the evidence job's `artifacts/Python-3.15.2.tgz`).
README rule 4 ("never writes outside `--record`'s target") is literally true
only if a symlink's target counts as the "target"; the failure-safety intent is
not met. Static finding; not executed by me.
**Fix:** refuse an existing record path that is a symlink or not a regular file
(or require it not to exist); refuse paths that resolve to any `--archive`
input or anything under `tools/python_pin/pin/`; write to `mktemp` in the same
directory and `mv` into place only after all digests succeed; add synthetic
regular-file tests for each case.

### F3 — Low-Medium: the installed-interpreter digest gate is host-specific but applied globally
`check_interpreter_digest` (`:228-247`) compares **every** interpreter reporting
3.15.2 with the single `local_interpreter_315_sha256` recorded on
`mac-studio-2026-32-1.home`; `local_interpreter_315_path` is never consulted.
On any other host (official pkg/exe install, a Linux build from the source
tarball, a Homebrew revision bottle such as `3.15.2_1`), or on this host if a
second 3.15.2 (e.g. uv-managed) is discovered, verify.sh fails with "interpreter
sha256 changed". That contradicts the "deliberately cross-platform" discovery
and makes `--no-interpreter` the only portable mode. Not a false-pass risk.
**Fix:** compare only when the real path equals the recorded path (and/or key
records by host+path); otherwise report "no local observation for this
interpreter" as NOT RECORDED. Document the behavior.

### F4 — Low: `--record` output is not the `checksums.txt` format and records different files
Keys differ (`interpreter_3_15_2_sha256` vs `local_interpreter_315_sha256`), so
recorded output cannot refresh the digest file. For `/usr/bin/python3` it
records the 3.9.6 *launcher* digest `34129c71…` while `checksums.txt` records
the framework binary `c5a13e37…` (evidence: `raw/python_pin-observed.txt`,
`integration-tests/d-record.txt`). `--record` also enumerates and executes
interpreters even with `--no-interpreter`. **Fix:** emit the same key scheme
and resolution as `checksums.txt` (or document the divergence), and honor
`--no-interpreter`.

### F5 — Low: recorded evidence is printed as if it applied to the supplied file, and the "published" digest is the pin's recorded copy, not a live check
After a `[fail] … sha256 mismatch`, `check_archive` (`:287-292`) still prints
"recorded evidence: downloaded bytes matched … and this artifact's .sigstore
bundle verified" (demonstrated in `integration-tests/c-archive-negative.txt`
C1 and C4). `[ok] … matches the digest python.org PUBLISHED` compares against
the value recorded in `pin/python.txt` (read 2026-11-26), not a live fetch of
the release page; `docs/PYTHON_TOOLCHAIN.md:210` repeats "matches the published
digest". The three layers the task asks to keep apart are therefore: (a)
**recorded** publisher Sigstore + digest results from job 4dca64d7 (dated,
not repeated); (b) **per-run** comparison of a supplied file against the
**recorded** published digest (not live); (c) **installed Homebrew build**,
local drift only. (a) and (c) are clearly labelled; (b) should say "published
digest as recorded in pin/python.txt (2026-11-26)".
**Fix:** print the recorded-evidence block only on a match, prefixed "the
pinned artifact (not necessarily this file)…", and relabel (b).

### F6 — Low: evidence for verify.sh is not bound to the candidate SHA, and the incident is undocumented
* The cited integration logs a–f (02:55) were produced by an earlier
  verify.sh revision: they print "framework code-signature anomaly OPEN",
  whereas the snapshot prints "framework bundle signature question OPEN"
  (`verify.sh:335`). `final-checks.log` (03:09) greps only summary lines and
  does not record which revision/SHA it ran against. `docs/PYTHON_TOOLCHAIN.md`
  "Checks run and results" therefore does not demonstrate behavior **at
  cc5dac9**.
* Neither doc records the 2026-11-27 incident: an integration negative test
  wrote through a symlink into the evidence job's retained
  `artifacts/Python-3.15.2.tgz`; the overwritten bytes are kept as
  `Python-3.15.2.tgz.altered-20261127`; a coordinator restored the file and
  re-verified it with Sigstore in TUF **offline** mode against a
  `.restored` name (`raw/coordinator-restored-sigstore.log`). The restore log
  does not state where the restored bytes came from or their sha256 beside the
  OK line. `PYTHON_TOOLCHAIN.md:274-276` ("Tests create no symlinks…") alludes
  to it without saying it happened. The original Sigstore results (02:38)
  predate the incident and are unaffected, but `check_evidence.py`/final
  checks hashed the restored copy.
**Fix:** add a short dated incident note (cause, affected file, restored
source, restored sha256 = `f74e1db0…0943`, offline re-verification, which
results predate it), and re-run `final-checks.sh` against a checkout of the
exact candidate SHA, recording the SHA and full output.

### F7 — Low: interpreter probes are not isolated from the working directory/environment
`read_version`/`read_build` run `"$py" -c …` without `-I`. With `-c`, the
current directory is first on `sys.path`, so a `platform.py` in the directory
the user runs from executes arbitrary code and can spoof the version string;
`PYTHONPATH` is honored too. The digest gate prevents a false PASS for the
recorded file, but a "read-only verifier" should not execute planted code.
**Fix:** use `"$py" -I -c …` (supported by every interpreter it targets,
including 3.9.6).

### Nits
* **N1** `docs/PYTHON_TOOLCHAIN_EVIDENCE.md` §6 item 1 still says "The pin file's
  `upstream_verified` flag is owned elsewhere and was not changed"; the pin no
  longer has that field (`docs/PYTHON_TOOLCHAIN.md:359-360` says so). Reword.
* **N2** State in the Sigstore "Scope" bullet that the verifier ran on the
  Homebrew 3.15.2 interpreter (itself only checksum-verified) and that the
  hash-pinned requirements came from sigstore-python `main` at the recorded
  commit, not a release tag; and that negative controls ran with the cached
  (offline) trust root.
* **N3** "universal2" for `python-3.15.2-macos11.pkg` is not supported by the
  retained release-page row (only "for macOS 10.15 and later"); cite a source
  or drop the word.
* **N4** No `.gitattributes`: a Windows checkout with `core.autocrlf=true`
  gives CRLF pin files/script, so `load_pin` dies "inconsistent" (exit 2, fail
  safe) — relevant because Windows is a target and Git Bash paths are
  probed. Consider `*.sh text eol=lf` and `tools/python_pin/pin/* text eol=lf`.
* **N5** `pin_get` takes the last duplicate key silently; `--python ""` /
  `--archive=` (empty) silently fall back. Consider rejecting both.
* **N6** `raw/published-sha256.txt` in the evidence job is an empty file;
  harmless, but the published values actually live in the release-page HTML.

## Verdict

**Changes required.** The provenance claims are well scoped and, as far as
retained evidence shows, correct: recorded publisher digest + Sigstore results
for the four artifacts are kept separate from the installed Homebrew build
(`installed_interpreter_publisher_authenticated=no`), source archives and target
installers are distinguished, and failures mostly fail closed. But the
verifier mishandles inputs with spaces (F1) and `--record` can silently destroy
an input or the pin's digest file while reporting PASS (F2) — both explicitly
in this review's scope — and the cited test evidence is not bound to cc5dac9
(F6). Because this reviewer could not execute anything, dynamic confirmation of
cc5dac9's behavior is **not verified** here. No M0 acceptance is implied.
