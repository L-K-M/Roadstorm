# M0 asset manifest validator recheck

**Verdict — pass for the provider-register correction and scoped M0 check.** The prior rejected-path read is fixed. Two pre-existing CLI diagnostic issues remain for unusually large JSON integers and unhashable output files.

Reviewer — OpenAI Codex, GPT-6.2 Sol, native OpenAI provider. Review date 2026-11-27. Candidate `6cc0058af4680f8ac04409974888c8b12e053e01`. Comparison base `49dd9c5b2b5f321be9550e2336c6495d04395208`. The last validator change is `87ec1c7`.

## Provider-register correction

`tools/asset_manifest/manifest_validator.py:904–921` returns before the row reader after a path validation rejection. The reader independently rejects invalid spelling, symlink components, and unreadable or non-regular files before opening. It uses a nonblocking open with leaf symlink protection where supported and checks the descriptor type before reading bytes at `489–558`. The checked-in tests include stable symlink and FIFO cases, skipped filesystem checks, and injected leaf replacement between the check and open. They instrument the actual reader and descriptor operations. Ordinary invalid or unreadable references report a deterministic `unresolved-reference`. A concurrent parent-directory replacement remains a documented limitation because the open still resolves path components by name.

Exact anchored rows resolve, while empty, invented, and wrongly cased anchors fail. Snapshots require the bounded route/file layout and reject fragments and symlink components. The rights and approval tests cover unknown legal origin, missing provider records, unapproved release inclusion, and required approval metadata. The validator provides structural evidence. Resolution of a record cannot establish the applicability of terms, a rights holder's authority, or the accuracy of a recorded approval.

## Findings

1. **Low — An unreadable output produces a traceback instead of a hash finding.** At `tools/asset_manifest/manifest_validator.py:639–642,1699–1706`, a regular file that exists but cannot be opened raises `PermissionError` before the caller can emit its intended diagnostic. I materialized a complete fixture via `materialize(root, complete_entry())`, wrote the manifest with `write_manifest`, set its output's mode to 000 and ran `validate_manifest.py --json --check-hashes`. The command exited 1 with a traceback and no JSON result. Catch read errors at the hashing boundary and emit the existing structured finding. The check still fails closed.
2. **Low — The JSON integer limit escapes structured validation.** At `tools/asset_manifest/manifest_validator.py:688–697`, the decoder only catches `JSONDecodeError`. A fixture containing `{"schema_version":` followed by 4,500 decimal digits and `}` made pinned Python raise `ValueError`. The same CLI command exited 1 with a traceback and no JSON result. Convert this decoding failure into the existing invalid-input finding. The input is rejected in either case.

## Evidence and limits

Reviewed `tools/asset_manifest/`, `assets/manifest.json`, `provenance/MANIFEST_CONTRACT.md`, and the register and snapshot layout. Commands ran on Python 3.15.2 from an immutable `git archive 6cc0058` snapshot in ignored `work/agents/sol-manifest-6cc0058/snapshot`, with a private TMPDIR and bytecode writes disabled for the test suite. `tools/asset_manifest/run_tests.sh` passed all 135 tests. `python3 tools/asset_manifest/validate_manifest.py --check-hashes assets/manifest.json` returned 0 with zero errors or warnings. The current manifest is an empty registry, so this command establishes its structure only. The independent malformed and unreadable controls and logs are beside the snapshot. Full provenance and legal approval remain open.
