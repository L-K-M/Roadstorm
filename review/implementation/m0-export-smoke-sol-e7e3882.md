# M0 export-smoke independent frozen-source review

**Verdict — changes required.** The exact commit, tree, and archive evidence are coherent under a moving HEAD. The preset digest can describe different bytes from the export snapshot, and the snapshot writer can still follow an archived or concurrently substituted link.

| Item | Scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `e7e38823f3b8807cfa606d96d00156ce23f1b53a`, committed 2026-11-27 05:58:06 +01:00 |
| Base | `6cc0058af4680f8ac04409974888c8b12e053e01` |
| Review date | 2026-11-27, Europe/Zurich |
| Files | `tools/export_smoke/lib/common.sh`, `tools/export_smoke/run_export_smoke.sh`, `tools/export_smoke/tests/test_common.sh`, and runner interactions with package checks and launch handling. |

## Ranked findings

1. **High · An archived preset symlink can overwrite a file outside the snapshot.** I extracted a private archive with a regular `project.godot` and an `export_presets.cfg` symlink to a separate private sentinel. With the live owned presets present, the helper returned 0, left the archive's link in place, and changed the sentinel to the live preset contents. Refuse linked or nonregular preset inputs or replace the extracted entry without following it. Require the final export preset to be a regular snapshot-owned file. Apply equivalent checks to `project.godot` before diagnostic writes so they remain local to the snapshot. [Preset overlay](../../tools/export_smoke/lib/common.sh#L368) · [Diagnostic write](../../tools/export_smoke/run_export_smoke.sh#L203)
2. **High · Preset provenance is recomputed from the live working tree.** A private copy stub performed the actual copy and then updated only the source presets before returning. The runner report's `presets_sha256` matched the updated working-tree file and disagreed with the file supplied to the export. Compute and validate the digest from the frozen copy selected for export. Fail before publishing incomplete provenance if either component digest or the composite cannot be computed. [Report digest inputs](../../tools/export_smoke/run_export_smoke.sh#L192)
3. **Medium · A replaced reservation can be written through before failure.** A private tar wrapper modeled replacing the reserved snapshot pathname with a symlink immediately after the pre-extraction identity check. It used the real tar for extraction. The helper failed at the final identity check, but both `project.godot` and `export_presets.cfg` had already appeared in the unrelated target directory. An early existence check and a later device/inode check do not constrain intermediate path-based writes. Operate through a stable directory handle or working directory anchored to the reservation for extraction, overlay and validation. A similar check-then-open gap remains at the digest file and later report/log paths. If the supported contract excludes hostile writes inside private output parents, document that scope explicitly and avoid claiming the current checks prohibit writes through all concurrent replacements. [Pre-extraction check and path-based write](../../tools/export_smoke/lib/common.sh#L349) · [Report creation](../../tools/export_smoke/run_export_smoke.sh#L225)

## Verification and limitations

I verified the directory was ignored and used `git archive e7e3882` to export `work/agents/sol-export-20261127/snapshot/`. Logs, separate scratch parents, and all repro artifacts remain in its parent.

| Command from snapshot | Result |
| --- | --- |
| `EXPORT_SMOKE_TEST_WORK=<private sentinel parent> sh tools/export_smoke/tests/test_common.sh` and same with `dash` | 125 assertions pass each. Both parent sentinels retained their exact content. The harness exercises private throwaway Git fixtures, a moved HEAD, separate archive/extraction failures, preexisting output preservation, and fake-engine error reporting. No shared repo or ref was changed. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../probe.py` | Three deterministic, private repros. The script uses synthetic archive bytes, a Git stub and a failing export stub. Preset symlink returned 0 and overwrote its private target. The report digest matched only the live preset. Replacement failed after writing both files into the unrelated private directory. Per-case logs are under each `probe-*` directory. |

The successful archive report path binds the selected full commit SHA and tree to the bytes of the stored tar before extraction. This does not bind modified diagnostic settings or the live-stub example's preset bytes to the export. I did not run real Godot exports, install or inspect shared templates, launch a platform package, or run a GUI. The runtime behavior of those paths remains outside this review.
