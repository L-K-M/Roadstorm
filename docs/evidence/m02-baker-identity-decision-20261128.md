# M0.2 handling baker correction: scoped review decision

Date: 2026-11-28 UTC. Source candidate: `674eac684d12d0a82d3721c9a2425b9ff27b9807`. Scope: `tools/car_recipe_bake/{README.md,bake_handling_recipe.py,run_tests.py,fixtures/negative/nul_display_name.json}`. The baker source is unchanged through `7454cd4` (`git diff 674eac6 7454cd4 -- tools/car_recipe_bake` is empty).

Independent exact-source [Opus 5.5](../../review/implementation/m02-baker-identity-opus-5-5-674eac6.md) and [GPT-6.2 Sol](../../review/implementation/m02-baker-identity-gpt-6-2-sol-674eac6.md) reviews both **pass this scoped integrity correction**. Each ran the pinned macOS baker suite, 18/18, and independently reproduced the two previous failures on the old code: checker-accepted NUL display name published as replacement-character identity, and an equal-length same-inode rewrite with restored mtime escaping the final source check. The corrected source refuses both before publication. The coordinator's separate frozen run passed 18/18; its two new controls failed on old `90a91f4` source. On unchanged baker source at `7454cd4`, hosted Ubuntu [run 46105209762](https://github.com/L-K-M/Roadstorm/actions/runs/46105209762) passed all four jobs, including baker 18/18. The reviewers' reports predate this hosted result; the coordinator verified it separately.

Nonblocking findings remain open for the broader M0.2 acceptance work:

- Some checker-accepted control characters U+0001 and U+000B fail closed when Godot's report JSON cannot be parsed. The CLI does not publish an incorrect resource, but the diagnostic does not name the source field. Add a source-specific refusal or a lossless report transport before the full baker/data gate; the current scoped integrity pass does not assert these names can be baked.
- Case 18 detects removal of both ctime comparison and descriptor reread, but not either removal alone. Preserve a separate post-stat rewrite control that isolates the reread before accepting the full M0.2 toolchain. The present implementation was independently probed and works.
- The same-inode refusal message says “different file.” Clarify the wording with the next baker diagnostic cleanup. The metadata docstring nuance is editorial.

This is not M0.2 acceptance: production typed car definitions, complete content, importer behavior and broader tests remain open. The standard LongCat/StepFun provider terms conflict with the intended Unlicense/CC0 commercial reuse; OI-02/OI-03 rights remain unresolved. This decision does not authorize release.
