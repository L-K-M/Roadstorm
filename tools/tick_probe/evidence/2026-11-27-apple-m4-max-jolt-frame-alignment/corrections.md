# Corrections applied to prior evidence documentation

No raw measurement file or review report was rewritten. Two stale documentation
entries in `evidence/2026-11-27-apple-m4-max-jolt-phase-followup/` were
corrected in place, and that directory's manifest entries for exactly those two
files were updated so it stays self-consistent. One further historical
statement is recorded below as superseded rather than rewritten.

1. `errata.md` item 1 claimed the successful runs were
   `repeat-pre-*.txt` / `repeat-post-*.txt` "in this directory". They are not:
   the follow-up directory contains `repeat-{fixed,default,max}.txt`. The
   similarly named files live in the phase-alignment directory (the pre-fix
   ones there crashed; the post-fix ones there are old 54-check runs). Item 1
   now names the actual files, and a new item 6 records the later contract
   count change without rewriting items 3-5.
2. `provenance.json` recorded `f8dfa0e6267d0fee632d23dad4741f3bf5e19f4e22e755c95e5dcad115ed3def`
   for `README.md`, but the archived README hashes to
   `03de7713f4f383e1fb18f1948b613f10bc99b26d9948f1ed1d7582edd942e634`, which
   is also what its own `manifest.sha256` records. The coordinator's
   post-review note changed the README after the provenance hash was written.
   The provenance entry was aligned to the actual hash.
3. The phase-followup `README.md` paragraph claiming that pausable nodes
   "never see an unpaused step without a logical tick" is a historical
   statement about the b5c4f99 wording and is **superseded**, not rewritten:
   the live `tools/tick_probe/README.md` and this directory document the two
   distinct idle/publication intervals and the lower-priority-node case
   precisely, with no blanket guarantee.

## What was preserved

- The phase-followup `manifest.sha256` still binds the b5c4f99 source/test/doc
  hashes it originally recorded. They were **not** rebound to this correction
  slice.
- Every raw output in the phase-followup and phase-alignment directories is
  unchanged.
- The phase-alignment directory is byte-identical to candidate `b5c4f99`.

Verification:

- Against candidate `b5c4f99`, the phase-followup manifest verifies 56/56.
- Against this corrected working tree it verifies 51/56. The five failures are
  exactly the files this slice changed: `README.md`,
  `src/tick_coordinator.gd`, `tests/callback_observer.gd`,
  `tests/contract_driver.gd`, `tests/run_repeat_tests.py`. All other entries,
  including every raw output and the two corrected docs, verify. This is the
  expected historical binding of a prior candidate, not a corrupted manifest.
- This slice's own source/test/docs and outputs are bound by
  `provenance.json` and `manifest.sha256` in this directory.
