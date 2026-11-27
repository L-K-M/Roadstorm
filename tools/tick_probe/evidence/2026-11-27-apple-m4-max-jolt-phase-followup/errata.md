# Errata for earlier phase/repeat evidence (no raw files rewritten)

The following statements in older operator text were imprecise. The raw files
themselves are preserved byte-for-byte; this note is the correction record.

1. `evidence/2026-11-27-apple-m4-max-jolt-phase-alignment/phase-post.txt` is a
   **failed launch** (missing private trace script), not a signal-ordering
   trace. `phase-pre.txt` is also a failed attempt. Use
   `phase-iter-pre.txt` / `phase-iter-post.txt` and the committed hard gate for
   integration-vs-tick pairing; the new `repeat-pre-*.txt` /
   `repeat-post-*.txt` in this directory supersede them as successful runs.
2. `repeat-pre-*.txt` in the phase-alignment directory crash with
   `SCRIPT ERROR` because the old `physics_caller.gd` had no `requested_ticks`
   property. They are failed launches, retained unchanged; they are not
   evidence of pre-fix step counts. Pre-fix behavior is measured by
   `phase-iter-pre.txt` and reproduced by the targeted mutations in this
   directory.
3. The fake-failure command must use `FAKE_CHECKS=135` to match
   `--expect-checks 135`. The earlier `FAKE_CHECKS=85` exits on the count
   mismatch before reaching the intended reported-failure check.
4. Older N1 examples said `--expect-checks 61`; a later note claimed a 76→77
   update. The current pinned strict N1 count is **76**. Current contract count
   is **135** and the repeat hard gate is **70**.
5. Counts recorded at earlier revisions (for example phase-alignment contract
   133, repeat 54) remain historical values for those candidates; they are not
   rewritten here. Current values are in this directory's outputs and
   `provenance.json`.

No prior review report or raw measurement file was edited.
