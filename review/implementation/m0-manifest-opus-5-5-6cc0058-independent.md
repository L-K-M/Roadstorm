# M0 asset-manifest validator — independent recheck (Opus 5.5), candidate 6cc0058

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, run through Claude Code. No subagents or helper models were used. I did not consult the other current review.
- Candidate: `6cc0058` ("Record Python verifier checkpoint reviews"). Base: `49dd9c5`.
- Scope: `tools/asset_manifest/**`, `assets/manifest.json`, and the provenance and manifest contracts they depend on. Rights and provider-account terms are **not** settled by code validation. OI-01, OI-02 and OI-03 stay open.
- Date: 2026-11-27.

## What was actually run

All of these are read-only Git commands, run in the main checkout:

```
git log --oneline 49dd9c5..6cc0058
git diff --stat 49dd9c5 6cc0058 -- tools/asset_manifest assets docs/provenance docs/contracts
git show --stat --format='%H %an %ad%n%B' 87ec1c7
git diff 49dd9c5 6cc0058 -- tools/asset_manifest/manifest_validator.py tools/asset_manifest/README.md
git diff 49dd9c5 6cc0058 -- tools/asset_manifest/tests/test_manifest_validator.py
git show 6cc0058:tools/asset_manifest/manifest_validator.py
git show 6cc0058:assets/manifest.json
git grep -n "chmod\|PermissionError\|unreadable" 6cc0058 -- tools/asset_manifest/tests/test_manifest_validator.py
git grep -c "    def test_" 6cc0058 -- tools/asset_manifest/tests/test_manifest_validator.py   # -> 135
git status --porcelain -- tools/asset_manifest assets/manifest.json provenance       # clean
git rev-parse HEAD                                                                   # e7e3882...
git diff --stat 6cc0058 HEAD -- tools/asset_manifest assets/manifest.json provenance # empty
```

**Execution was blocked.** The session's permission policy refused to run anything:
- `git archive` into `/tmp`, which I meant to use as an isolated snapshot;
- `python3 -I -m unittest discover -s tools/asset_manifest/tests` with `PYTHONDONTWRITEBYTECODE=1`.

**No tests were executed in this review.** I counted 135 `test_` methods in the candidate. That matches the coordinator's earlier run of 135 tests, but I have not reproduced that run. Every finding below comes from reading the source.

In the range `49dd9c5..6cc0058`, only `87ec1c7` changes `tools/asset_manifest/**`. Three files changed: `manifest_validator.py` (143 lines changed), `README.md` and `tests/test_manifest_validator.py`. `assets/manifest.json` did not change: it is still the empty registry, with `registry_status: "empty"` and OI-01/02/03 open. The scoped tree at `6cc0058` is byte-identical to the current `HEAD` (`e7e3882`).

## Was the prior finding corrected? (rejected register path read before validation)

**Yes, as far as static reading can show.** I traced each path:

- `_check_reference_resolves` now returns a verdict. It returns `False` for each of these after reporting `unresolved-reference`:
  - a symlink at any component;
  - a missing path;
  - a non-file (directory, FIFO, device);
  - with `require_readable=True`, a file that fails `_record_file_is_readable`.
- `_check_terms_register_reference` exits before `_terms_register_route_ids` when that verdict is `False` (`manifest_validator.py:914`). It also exits when there is no fragment, when file checks are off, or when there is no root (`:912`). A rejected register path therefore never gets to the read.
- The only way to read the register is `_terms_register_route_ids` → `_read_record_text`. Before opening, that function re-checks three things through `_record_file_is_readable`: spelling, every component for symlinks, and `is_file()` plus `os.access(R_OK)`. It opens with `O_RDONLY|O_NOFOLLOW|O_NONBLOCK`. Then `fstat` must report `S_ISREG`, or the descriptor is closed unread. `OSError` and `UnicodeDecodeError` both become `None`, which the caller reports as `unresolved-reference` ("could not be read as text").
- The read is always of the constant `PROVIDER_TERMS_REGISTER`. It is reached only when the target equals that constant exactly (`:847`), after a spelling check (`:839`). So a manifest-controlled spelling cannot steer the read.
- Other record references (`rights_holder_record` and snapshot files) are checked for existence and type only and are never opened. A FIFO there is rejected by `is_file()` without being opened.
- `--no-file-checks` and `root is None` still skip resolution, without reading.

Error handling for rights, approval and schema: the rights, terms and review/approval gates are unchanged by this range. I read them as context only. `license_spdx`/CC0 rules, the `unknown-legal-origin` gates, the required `service_terms_ref` for `service_generated`, and the `approved`/`release_inclusion` requirements behave as documented. No regression was found.

## Findings

### F1 — Low (test gap): the descriptor-level defences are never exercised

`O_NOFOLLOW`, `O_NONBLOCK` and the `fstat` check have no test.

- The two "time-of-check/time-of-use" tests swap the register inside a wrapper around `_check_reference_resolves` (`test_register_swapped_for_a_symlink_after_the_check_is_not_followed`, `test_register_swapped_for_a_fifo_after_the_check_does_not_block`).
- That swap happens **before** `_read_record_text` re-runs `_record_file_is_readable`.
- So it is that path re-check that refuses the swapped file, and both tests correctly assert `opened == []`.
- No test swaps the file between `_record_file_is_readable` and `os.open`. The README and docstring say a FIFO in that window "is opened without blocking, then rejected by `fstat`", and that a symlinked leaf is refused by `O_NOFOLLOW`. Both claims are plausible on macOS and Linux, but nothing tests them.

Suggested test: patch `manifest_validator._record_file_is_readable` to return `True` and then swap the file, or swap the file from inside it. Then assert that the result is `None`, the call does not hang on a FIFO, and the outside rows are never returned.

Not blocking: the guarantee that a rejected path is never opened does not depend on this.

### F2 — Low, pre-existing (outside `87ec1c7`): `--check-hashes` can crash or hang on an unreadable or special output file

`PathChecker.digest` (`manifest_validator.py:622-643`) checks spelling, symlinks and `is_file()`. It then calls `open(target, "rb")`:
- without catching `OSError`;
- without `O_NONBLOCK`;
- without `O_NOFOLLOW`;
- without a descriptor check.

Its caller (`:1699`) has no `try` either. The consequences:
- An output file with mode `000` raises `PermissionError` and gives a traceback instead of the documented `missing-file` "cannot hash … unreadable" finding (`:1704`). The traceback exits with code 1 from the interpreter, not under the exit-code contract.
- A file swapped for a FIFO or symlink between the check and the open can block or be followed. This is the same time-of-check/time-of-use class that `87ec1c7` narrowed for the register.

No test covers either case: there is no `chmod` test on a hashed output. Suggested fix: send `digest` through the same guarded open as `_read_record_text`, as a streaming variant, and map `OSError` to `None`. This is inside the tool's scope but predates the candidate.

### F3 — Info: what the change does not guard against, and is honest about

- Only the leaf gets `O_NOFOLLOW`. A *parent* directory swapped for a symlink after `_symlinked_component` and before `os.open` would still be followed. The docstrings and README say outright that this is not race-free, so the documentation is not overclaiming.
- A real fix would walk the path with `dir_fd`, using `O_NOFOLLOW|O_DIRECTORY` for each directory component, and open the leaf with `O_NOFOLLOW` against the final directory descriptor.
- For a validator that runs over a local checkout, the residual risk is low.

### F4 — Info: behaviour changes, intended and acceptable

- An unreadable register is now `unresolved-reference` **even without an anchor**, because `require_readable=True` applies whether or not a fragment is present. Before, it passed. This is stricter, consistent with the README, and does not involve a read (`os.access` only).
- `os.access` uses the real UID, so a run as root treats a mode-`000` register as readable. The tests skip themselves under root and say why, so this is fine.
- Fragments are `.strip()`-ed (`provenance/PROVIDER_TERMS.md#pi-stepfun ` resolves), and so are register route IDs. This predates the candidate, is harmless, and is noted for the record.

### F5 — Info: the repaired real-register test is now sound

`test_service_generated_rejects_an_unregistered_route_against_the_real_register` used to hard-code `#pi-mistral`, which the register later gained, so the test asserted nothing. It now builds a route ID that is provably absent from the rows the register currently records. The fix is correct.

### Test-instrumentation check

`spy_on_register_reads` patches `os.open`, `builtins.open`, `Path.read_text` and `Path.read_bytes` globally, and `manifest_validator._read_record_text` on the module. The validator calls `os.open` by attribute lookup, and `_terms_register_route_ids` looks up `_read_record_text` from module globals. Both patches therefore take effect, and the zero-open assertions mean something.

The positive controls are present:
- an accepted anchor is read exactly once;
- a reference with no anchor is read zero times;
- a binary register is opened once, fails to decode, and resolves no row.

## Limits

- I did not execute anything (see above). I reproduced neither the 135-test pass nor the FIFO no-hang behaviour on this Mac.
- I did not review `.github/workflows/**`, `tools/ci/**` or the other findings from the 49dd9c5 recheck; they are outside scope.
- Code validation only shows that a reference *resolves* to a register row or snapshot. It says nothing about whether provider-account terms permit the use, or whether owner and contributor authority exists. OI-01, OI-02 and OI-03 remain open, and the empty manifest claims no assets.

## Verdict

**The prior finding is corrected; I accept it with the low-severity notes above. The verdict comes from source reading only, because test execution was blocked.**

A rejected provider-register path (symlinked at the leaf or a parent, missing, a directory, a FIFO or special file, unreadable, or outside the root) is reported once as `unresolved-reference` and is never opened. The fragment check runs only after the reference has resolved to a readable regular file.

Recommended follow-ups, none blocking:
- add a test for the window after the re-check (F1);
- harden `PathChecker.digest` the same way (F2, pre-existing);
- optionally, move to `dir_fd`-based resolution if race-free reads are ever wanted (F3).
