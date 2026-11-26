# Implementation log

This is a concise provenance ledger. Private prompts, sessions, scratch captures and logs remain under ignored `work/agents/`; this ledger does not assert legal clearance for any authoring route. See `provenance/PROVIDER_TERMS.md` and `provenance/OPEN_ITEMS.md`.

## 2026-11-26–27: initial M0 work

- The coordinator fast-forwarded the shared `main` checkout from `25d6520` to `0ea596a`, then integrated and pushed the placeholder shell (`ee0ec19`), toolchain records (`d544c1c`, `f4cee18`), manifest validation (`6b57183`, `bdeb8e2`, `935b9e2`, `b28d5bf`, `bd94d17`), recorded reviews and smoke fixes (`f763ae1`, `15faf0d`), tick probe/Jolt selection (`ae8a134`, `10d9e51`), provenance intake (`7733fb1`), CI (`6e5b0d1`, `49dd9c5`), and export smoke preparation (`7b27c2f`). See Git history for exact source and `docs/STATUS.md` for current gates.
- Implementation jobs used Pi `stepfun/step-5-preview` and `longcat/LongCat-2.5`; task IDs, ownership and progress are recorded in `docs/STATUS.md` and the corresponding ignored job records. The coordinator independently reran the listed local checks before integration; not every job's claims are accepted.
- Independent Opus 5.5 via Venice/Pi and GPT-6.2 Sol via native Codex reviewed candidate `6b57183` and rechecked `bdeb8e2` and `15faf0d`; reports in `review/implementation/` record findings and limits. Both requested changes. A further pair is reviewing `49dd9c5`. No review closes M0 or represents a release review.
- The `7b27c2f` macOS smoke ZIP was exported from an isolated archive, SHA-256 `db9685fc4a8d09bb4e57e16b20850fb79be1596f293dade69193e68bd71ff8e8`, ad-hoc signed and unnotarized. Headless and bounded windowed launches reached the placeholder menu. The user-facing game, other platform launches and release packages remain unverified.
- One worker reported deleting a pre-existing `/tmp/roadstorm-baseline-206edf5` scratch copy it did not create. Another ran a GUI check without the desktop lease. These deviations were recorded in status; neither implies loss of tracked repository content.

This is an interim log, not an assertion that any M0–M9 gate has passed.
