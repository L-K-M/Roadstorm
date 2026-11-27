# Recorded probe evidence — callback ordering / observation freshness follow-up

Current evidence responding to
`review/implementation/m0-tick-opus-5-5-c6292a2-independent.md`. Reported
candidate `c6292a2661b48d7f090225bd531427967b404359`; the worktree also carries
the uncommitted Sol reentrancy fixes and this follow-up. Previous evidence is
preserved unchanged.

## F1/F3 measurement (private copies, counting body + ordered observers)

Driver records, for one fresh-body 12-tick request:

| Metric | `c6292a2` | fixed tree |
| --- | --- | --- |
| logical ticks / elapsed | 12 / 12 | 12 / 12 |
| counted server integrations after request | 12 | 12 |
| integrations sampled at `step_accounted` | 11 | 11 |
| integrations sampled at `step_finished` | 12 | 12 |
| dynamic y at accounting vs emission | 999.821228 vs 999.788879 | same values |
| observer callbacks before coordinator | 13 | 13 |
| observer callbacks after coordinator | 12 | 12 |

Interpretation:

- **F1**: one extra unpaused engine iteration exists per request. A node ordered
  before the coordinator receives 13 callbacks; a node after it receives 12.
  This was already true on `c6292a2`; the exposure is now pinned by a contract
  test. The fix adds an explicit `PROCESS_MODE_ALWAYS` pause-enforcer ordered
  after the coordinator so the pause occurs at the start of the extra
  iteration, keeping later world nodes deterministic even if scheduling order
  changes. Nodes earlier than the coordinator must gate on the coordinator's
  tick state; that exposure is documented and tested rather than hidden.
- **F3**: `step_accounted` samples one step behind (11) while emission sees the
  final step (12); the dynamic position differs by exactly one gravity step
  between the two boundaries. The result observation is now rebuilt inside
  `step_finished`, after the final physics-server step, instead of being built
  at the tick-N `_physics_process` snapshot. The probe car is kinematic/explicit
  and unaffected either way; server-stepped consumers get fresh state.
- No physics-server step is lost: first/repeated 1- and 12-tick requests still
  integrate exactly their requested counts under all three pacings (N1 runner).

## F2 real-time pace

Measured with the final code (`compare_modes.txt`): realtime 600 ticks in
10.884 s, speedup **0.919×**. Expected pause overhead: 50 requests × 1/60 s =
0.833 s, giving a ceiling of 0.923×. The documented acceptance band remains
0.5–2.0 (not changed retroactively); the tool now prints the expected overhead
and ceiling. The 1/(n+1)-style cost is therefore measured and recorded.

## N1 strict runner and evidence errata

- New `tests/run_n1_tests.py`: isolated copy, XDG/TMPDIR redirection (no HOME
  reassignment), SCRIPT ERROR detection, `N1_RESULT`/`N1_TOTAL` reconciliation,
  `--expect-checks`, and fail-closed on reported failures regardless of child
  exit. N1 passes 14/14 under fixed/default/max through this runner.
- N1 driver no longer samples `Engine.get_physics_frames()` after polling: it
  snapshots at `step_finished` and asserts `>= n + 1` (pause callback accounted)
  plus exact server-step equality, removing the poll-timing flake class.
- Historical errata: the cold-start evidence README says “9 failures” for its
  combined mutation, but its own `mutation-sensitivity.txt` records
  **`checks_failed: 10`** (verified). The historical directory is preserved;
  this note corrects the wording.

## Results

| Run | Checks | Exit | Wall |
| --- | --- | ---: | ---: |
| structural fixed / default / max | 108/108 each | 0 | 3 s / 8 s / 12 s |
| contract fixed / default / max (`--expect-checks 91`) | 91/91 each | 0 | <1 s / 7 s / 7 s |
| N1 strict runner fixed / default / max | 14/14 each | 0 | <1 s each |
| compare_modes throughput + trace | 9 + 2 PASS | 0 | ~15 s |
| F1/F3 pre/post drivers | measured above | 0 | <1 s |
| exit-code selftest | 5 total, 1 injected failure | 1 | <1 s |
| guard/ordering mutation | 2 targeted failures / 91 | 1 | <1 s |
| enforcer early-pause mutation | 7 failures / 91 (server steps drop, ordering breaks) | 1 | <1 s |

The observation-refresh change has no automated differential test because the
M0.8 observation schema contains only the kinematic probe car; it is verified by
code inspection and by the accounting/emission server-step counts above.

## Files

| Path | Role |
| --- | --- |
| `f1f3-pre-c6292a2.txt` / `f1f3-post-fix.txt` | ordered observers + counting-body metrics |
| `contract-{fixed,default,max}/` | 91-check contract suite per pacing |
| `structural-*` | 108-check structural suite per pacing |
| `n1-regression-{fixed,default,max}.txt` | strict-runner N1 results |
| `compare-modes.txt` | throughput + INFO overhead/ceiling + trace digests |
| `mutation-guards.txt` | reentry/reset guards disabled: 2 failures |
| `mutation-enforcer-early-pause.txt` | pause-enforcer early-pause: 7 failures |
| `exit-code-selftest.txt` | injected-failure exit code |
| `manifest.sha256` / `provenance.json` | hash-bound record |

## Limits

- One-car probe plus test-only counting/observer nodes; not M1 motor, AI,
  contacts, gates/triggers or full simulation.
- Callback ordering semantics are Godot 4.7.2 scene-tree behavior; M1 nodes
  ordered before the coordinator subtree must gate on coordinator state.
- Observation refresh applies to `observe()` at emission; the M0.8 car pose is
  committed explicitly and cannot expose the old one-step lag.
- No commit created; hashes bind current worktree and reported candidate
  blobs separately.
