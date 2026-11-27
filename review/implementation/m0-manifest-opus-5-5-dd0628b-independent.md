# M0 asset manifest - independent scoped recheck of dd0628b (hash/error fixes)

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, run in Claude Code on this Mac.
  No subagents, helpers or other models were used.
- Candidate: `dd0628b29ca7f5379732e2de30395da300c90185` ("Guard manifest hash reads and malformed JSON")
- Base: `6cc0058af4680f8ac04409974888c8b12e053e01`
- Scope: `tools/asset_manifest/**` only (`manifest_validator.py`, `README.md`,
  `tests/test_manifest_validator.py`; +465/-32 between base and candidate).
- I did not read the other current review of this candidate.
- **This is not rights approval.** It reviews checker code only.

## What I did

Commands and checks I actually ran:

- `git rev-parse dd0628b 6cc0058`: both resolve to the full SHAs above.
- `git log --oneline 6cc0058..dd0628b`, `git diff --stat 6cc0058 dd0628b -- tools/asset_manifest`
- `git diff 6cc0058 dd0628b -- tools/asset_manifest/{manifest_validator.py,README.md,tests/test_manifest_validator.py}`:
  I read the full diff.
- `git show dd0628b:tools/asset_manifest/manifest_validator.py`: I read the guarded-open
  primitive, `_record_file_is_readable`, `_symlinked_component`, `_read_record_text`,
  `PathChecker.digest`, `_decode_manifest_document`, the manifest read path (around
  lines 1170-1200), the `--check-hashes` caller (around lines 1765-1800) and the
  register-anchor caller (around lines 1000-1016).
- `git grep -n -i windows dd0628b -- tools/asset_manifest docs ...` and
  `.github/workflows/ci.yml`: I checked which platforms the project claims to support.
- `git diff --stat dd0628b -- tools/asset_manifest provenance` (empty) and
  `git status --porcelain --ignored -- tools/asset_manifest provenance`, which shows only
  ignored `__pycache__/`. The working-tree copies in scope therefore equal the
  candidate's Git objects, so the line-range `Read`s I made of the working tree show the
  exact candidate bytes.

### Execution blocked

I could not run anything in this session. The permission layer refused every attempt:

- `git archive` into `/tmp` or into the ignored `work/` directory, and `tar -x`, for a
  private snapshot. I created the empty `work/opus-dd0628b-snap` directory and then
  removed it. Nothing else was written.
- `python3 -B -m unittest discover -s tools/asset_manifest/tests`
- `git ls-tree`

So I did **not** run the 149 tests, the empty `--check-hashes` run, the negative
controls or the valid controls. Everything below comes from reading the exact Git
objects. The coordinator's execution of 149 tests and an empty `--check-hashes` run is
the only execution evidence for this candidate. I have not reproduced it.

## Assessment of the changes

### Prior finding: unreadable or special output under `--check-hashes` (Sol 1 / Opus F2): fixed

`PathChecker.digest` used to call `target.is_file()` and then the builtin `open()`. Now it
checks, in order:

1. spelling
2. `resolve`
3. `_symlinked_component`
4. `_record_file_is_readable`, which re-checks spelling, symlinks, `is_file` and
   `os.access(R_OK)`
5. `_open_regular_file_descriptor`

After that it reads with `os.read`, inside `try/except OSError` with `finally: os.close`.

Every failure returns `None`. The caller turns `None` into the existing `missing-file`
finding. I found no remaining path where `OSError` or `PermissionError` can escape
`digest`: `os.open`, `fstat`, `os.read` and the path predicates are all guarded.

### Prior finding: oversized integer traceback (Sol 2): fixed

`_decode_manifest_document` now catches `(json.JSONDecodeError, ValueError)` and emits
`invalid-json`. The CLI's exit-2 contract then applies. The tests cover text mode and
`--json` mode with empty stderr, and skip cleanly when `sys.get_int_max_str_digits` is
missing or 0.

Undecodable bytes are handled earlier, as `invalid-encoding`, because the manifest is
decoded before `json.loads`.

### fd lifecycle: correct

`_open_regular_file_descriptor`:

- closes the descriptor when `fstat` fails and when the file is not a regular file
- ignores a failure of `set_blocking(True)`, which is harmless for a regular file
- returns the descriptor only on success

Both callers (`digest` and `_read_record_text`) close it in `finally`.

I found no leak and no double close. The only gap is an asynchronous exception, such as
`KeyboardInterrupt`, arriving between `os.open` and the `try`. That is theoretical.

Opening a directory `O_RDONLY` succeeds on POSIX, and the `S_ISREG` check then closes it,
so directories are refused correctly.

### Race claims: honest

The README's new "Reads narrow, they do not close, the swap window" limitation is
accurate:

- `O_NOFOLLOW` covers only the leaf.
- Parent components are resolved by name after `_symlinked_component`.
- A swap after the open is not detected.
- No `dir_fd` walk exists.

`digest`'s docstring repeats this. The change claims no more than the code delivers.

### Negative and valid controls: adequate in design (not executed by me)

- **Valid:**
  - a regular output hashes and the whole document validates
  - `_open_regular_file_descriptor` returns a regular-file descriptor
- **Negative:**
  - a mode-000 output fails, both directly and through the CLI with `--json`, exit 1 and
    empty stderr; skipped when running as root
  - an oversized integer fails, both directly and through the CLI
  - a FIFO or symlink swapped in at the pre-check/open boundary fails, for both `digest`
    and the register reader. The swap happens inside the patched
    `_record_file_is_readable`, which runs after `_symlinked_component`, so it really
    lands in the path-check-to-`os.open` window.
  - the primitive refuses a FIFO without blocking and refuses a symlinked leaf
  - with flags unavailable, both readers fail closed
- `bounded_call` re-raises exceptions from the worker, so a crash cannot be mistaken for
  a refusal that returned `None`. Its deadline turns a hang into a test failure.

## Findings

No blocking findings. All of the following are low or nits.

**L1 (low): fail-closed on platforms without the flags is honest in kind but misleading in detail, and changes Windows behaviour from 6cc0058.**

- The condition is wider than documented. `_guarded_open_flags` returns `None` when
  *either* `O_NOFOLLOW` or `O_NONBLOCK` is missing. The module comment and the README
  limitation both say the check fails closed "where a platform provides *neither*" (or
  "offers neither ... nor").
- CPython on Windows has neither flag, so on Windows:
  - every `--check-hashes` output becomes `missing-file` with the text "the file is
    missing, unreadable, a symlink or outside the root". That misdiagnoses a
    platform limitation as a file problem.
  - every `#route-id` register anchor becomes `unresolved-reference`, "could not be read
    as text".
- At base 6cc0058, `_read_record_text` used `getattr(os, ..., 0)` and could read the
  register on Windows. Register reads on Windows are therefore a regression the README
  does not name.
- Impact today is low. CI runs on `ubuntu-latest`, and `docs/MACHINE_INVENTORY.md`
  states that no Windows host exists. Failing closed is the safe direction.
- Suggested fix:
  - fix the "neither" wording
  - name Windows explicitly in the limitation
  - optionally, emit a distinct reason, such as "this platform lacks O_NOFOLLOW /
    O_NONBLOCK", rather than reusing the missing-file text

**L2 (low, pre-existing, not executed): deeply nested JSON can still escape as a traceback.**

`json.loads` raises `RecursionError` for very deep nesting, such as `"[" * 100000`.
`RecursionError` is not a `ValueError`, so the widened `except` does not cover it. That
would break the same structured-error and exit-2 contract the Sol 2 fix restores.

This rests on known CPython behaviour. I could not run it here, so I have not verified it
against this interpreter. It is outside the two prior findings but inside "structured
errors".

**N1 (nit): the `ValueError` catch is broad.**

A `ValueError` raised by a future bug in `_DuplicateMemberCollector` (the
`object_pairs_hook`) would be reported as `invalid-json`. Also, an oversized integer is
grammatically valid JSON that this interpreter refuses to convert, so the "is not valid
JSON" wording is slightly off. Acceptable as is. A narrower catch or a distinct message
would be more precise.

**N2 (nit): the trailing `validate()` in the digest symlink-swap test does not test the fd level.**

In `test_digest_refuses_a_symlink_swapped_in_at_the_open_boundary`, the trailing
`validate()` runs after the patch is removed. It therefore exercises only the path-level
symlink rejection. The fd-level claim rests on the bounded `digest` assertion before it,
which is sufficient. The `assertNotEqual(digest, outside_digest)` after
`assertIsNone(digest)` adds nothing, because `None` never equals a hex string.

**N3 (hardening idea, not required): the parent-swap residual could be closed per platform.**

The documented parent-component residual could be narrowed further with the
platform-specific flags `O_NOFOLLOW_ANY` (macOS) or `openat2` with `RESOLVE_NO_SYMLINKS`
(Linux), or with a `dir_fd` walk. The README already states that it is not implemented,
which is the honest position.

## Limitations of this review

- No execution by me: tests, CLI runs and the empty `--check-hashes` run were blocked by
  permissions (see above).
- I did not review anything outside `tools/asset_manifest/**`. The other 125 files changed
  between 6cc0058 and dd0628b (tick probe, CI, export smoke and others) are out of scope.
- I did not test on Windows or Linux. I did not check whether the README's statement of
  "2 failures and 9 errors" against the pre-fix module is accurate.

## Verdict

**Accept for the scoped hash and error fixes, with the low notes above.** The checker now
reports both prior findings as structured findings:

- unreadable or special `--check-hashes` outputs
- oversized-integer tracebacks

Descriptor handling is correct, and the race and portability claims are honest in
substance. L1's "neither"/"either" wording and the unnamed Windows behaviour should be
corrected in a follow-up. My static review supports this verdict. It does not replace the
coordinator's execution evidence.
