# Independent Roadstorm M0.2 handling baker review

**Verdict: pass for the scoped baker correction.** Both prior counterexamples reproduce against the base CLI and refuse on the candidate. I found one low-severity diagnostic issue and no additional material integrity defect in the scoped checks.

- Reviewer: OpenAI Codex, `gpt-6.2-sol`, first-party OpenAI. The session invocation identifies the model, with no finer model build exposed.
- Date: 2026-11-28 UTC.
- Candidate: `674eac684d12d0a82d3721c9a2425b9ff27b9807`, from the supplied `candidate.sha`. Scoped base: `90a91f4d50c5c19222f5446da6a0c598dcc10531`.
- Scope: `tools/car_recipe_bake/{README.md,bake_handling_recipe.py,run_tests.py,fixtures/negative/nul_display_name.json}`. Their Git blob hashes matched the supplied patch postimages `46babdb e56aa32 b572a0d a6b8cf3`. Recursive comparison of the private build with the supplied read-only archive showed no differences before or after the checks. I inspected `bake_handling.gd`, the checker, `HandlingRecipeMapper`, `HandlingDefinition`, and `DefinitionIdentity` as dependencies.
- Independence: I read the two named prior reviews. Tests and controls ran from the private archive, with logs, generated fixtures, scratch and outputs under the private logs directory.

## Ranked finding

1. **Low, diagnostic wording — `tools/car_recipe_bake/bake_handling_recipe.py:524,612`.** The metadata comparison treats a changed ctime as a mismatch, then says it will refuse to bind the opened source “to a different file.” My restored-mtime probe confirmed the same device, inode, length and mtime while ctime changed. The message includes both paths and the refusal is correct. A same-inode edit can receive the same wording as a symlink retarget. See `probe.log`.

## Prior counterexamples and earlier protections

- **Identity.** The motor-ready checker accepted the NUL fixture with zero errors or warnings. The base CLI exited 0 and wrote U+FFFD into the resource with `round_trip.ok=true`. The candidate exited 1 at `display_name: handling-identity-mismatch`, showing the source-derived `Alpha\x00Omega handling` and the engine's U+FFFD string. The destination was absent. The CLI derives four strings from the checker-parsed frozen document and compares them before publication (`bake_handling_recipe.py:254,268,397,423,923`). The mapper appends the documented suffixes and copies revision and lifecycle (`handling_recipe_mapper.gd:180`). The Godot report takes identity and numeric values from the validated reload (`bake_handling.gd:90,102,118,327`). Direct equality probes also exercised valid-form differences for all four fields, checking diagnostic paths, and a composed/decomposed Unicode pair.
- **Same inode, restored mtime.** The base helper returned the source path beside the old digest after its seam rewrote the same inode with equal-length bytes and restored mtime. The candidate rejected the same setup with the submitted path in the error. Comparing ctime detects it at the target stat (`bake_handling_recipe.py:507,612`). Masking only the ctime comparison still caused refusal at the second descriptor hash (`:621,641`), so the second read independently covers the demonstrated rewrite. Injected read and seek failures also named the submitted path.
- **Stable inputs and earlier guards.** Finite and unlimited inputs and a stable symlink passed end to end. The symlink case verifies both submitted and resolved paths in the manifest. Direct stable path and relative symlink probes also passed. Changed-byte leaf and parent retargets, dangling source links, and a retarget inside the final seam refused in the suite. My additional same-byte retarget to a different inode refused, isolating target identity from byte comparison. The signed-zero fixture passed the checker and the CLI refused `handling.drag.rolling`, reporting expected binary64 `0000000000000080` versus reloaded `0000000000000000`. The destination was absent.
- **Observation boundary.** The resolved path is observed at the target stat and the second byte read stays on the opened descriptor. An external writer can replace that path after the stat or change bytes after their last observation. A path replacement after the stat can leave the second read on the original inode. The recorded path and bytes still describe the matched observation for that case. The CLI provides no filesystem lock on external writers, as documented at `README.md:384`. That residual race differs from accepting the old digest after the rewrite inside the exercised seam, before the path-binding observation.

## Commands and results

Local runs used Python 3.15, private HOME, TMPDIR and XDG directories, and `PYTHONDONTWRITEBYTECODE=1`. `logs/env.sh` records the setup and assigned coordinator paths. Engine runs used the shared `godot-test.lock` and pinned editor at `toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`. The version gate checked `4.7.2.stable.official.ed1daf0bf`. I did not reverify the publisher archive digest.

| Command or control | Result |
| --- | --- |
| `timeout -k 10 600 lockf -k -t 180 "$shared_lock" /opt/homebrew/bin/python3 -B tools/car_recipe_bake/run_tests.py --godot-bin "$editor" --timeout 90` | macOS **18 passed, 0 failed**, exit 0. `suite.log`. |
| `timeout -k 10 180 sh tools/car_recipe_schema/run_tests.sh` | **98 passed**, exit 0. `checker.log`. |
| `timeout -k 10 180 /opt/homebrew/bin/python3 -B tools/car_recipe_bake/bake_handling_recipe.py --recipe "$fixture" --output-dir "$private_output" --lock-path "$shared_lock" --godot-bin "$editor" --timeout 60` | Both direct negative fixtures exited 1 with the expected diagnostic and no destination. `nul_display_name.log`, `negative_zero_drag_rolling.log`. |
| `timeout -k 5 30 /opt/homebrew/bin/python3 -B ../logs/probe.py` | Source binding, ctime-masked reread, error path and identity probes passed. `probe.log`. |
| Same direct CLI arguments and timeout with `../logs/old_cli.py`, followed by `timeout -k 5 30 /opt/homebrew/bin/python3 -B ../logs/old_recheck.py` | Reconstructed the old CLI in memory by reversing the supplied patch hunks against the exact candidate file. The reconstructed blob matched patch preimage `f32de6c16adfdcb6c80828cd488e270e92c039f4`. Base CLI exited 0 for NUL, and the base helper accepted the restored-mtime rewrite. The Godot script and mapper used by the old CLI are unchanged in this delta. `old-nul.log`, `old-recheck.log`. |

The candidate tests discriminate the old behavior. Case 17 requires checker acceptance, a source-specific identity refusal and no published output, which the base CLI's success violates. Case 18 requires refusal of the seam rewrite, which the base helper's successful return violates. The coordinator separately supplied 18/18 on a frozen source and 0/2 on the two tests against old source. Those runner results are separate from my local suite and reconstructed-base controls.

Hosted Ubuntu for this SHA was outside my verification. The verdict covers the one-recipe baker delta. Milestone acceptance, M0.3 rights, whole-M0 and release checks were outside scope.
