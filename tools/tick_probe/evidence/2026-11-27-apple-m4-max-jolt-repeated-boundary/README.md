# Recorded probe evidence — repeated-request boundary correction

Follows the coordinator’s independent note that `_exact_warmed_request()` reset
between requests and therefore did not prove repeated requests on one world.
This turn adds a hard same-world 12+12+1 sequence and corrects the resume
boundary.

## Measured problem (pre-correction, deferred-pause tree)

Same warmed `RigidBody3D`, two immediate idle-origin 12-tick requests, no
reset/warm-up between them (`repeat-pre-{fixed,default,max}.txt`):

| Pacing | Request 1 server steps | Request 2 server steps |
| --- | ---: | ---: |
| fixed | 13 | 12 |
| default | 13 | 12 |
| max | 13 | 12 |

The first request carried an extra boundary step; the second lost one. The old
per-request `_exact_warmed_request()` scenarios could not see this because each
called `_configure()`/`reset()`.

## Correction

An idle-origin request now consumes **one fully paused physics iteration**
before activation (`_activate_after_physics`). That mirrors the settling a
physics-callback caller already received via end-of-frame activation and keeps
the first tick paired with its server step across repeated same-world requests.
Completion still pauses synchronously in the final tick callback.

Post-correction same-world sequence (`repeat-post-*.txt`): every request is
exactly 12 counted server steps for all origin/pacing combinations; the hard
sequence is 12 + 12 + 1.

## Hard gate and mutation

Contract `repeat-same-world:*` and N1 `same_world_12_12_1:*` run 12+12+1 on one
warmed body/world with no reset or artificial unpause. At `step_finished` and
after `take_result()` they require:

`requested == elapsed == tick_delta == server_step_delta`, frozen publication,
and a committed final observation pose.

Mutation removing only the settling iteration
(`mutation-settle-removed.txt`) fails exactly the repeated-request checks:
second request `server_steps_delta=11`, third `0`.

## Honest engine-frame overhead

Each idle-origin request spans `n + 1` engine frames at signal time: `n` tick
iterations plus one fully paused settling iteration. No server step is added —
server steps stay exactly `n`. Physics-callback-origin requests also span
`n + 1`. Realtime cost is therefore real: measured 600 ticks / 50 requests in
10.966 s, speedup **0.912×**; expected ceiling from 50 settling iterations is
`10 / (10 + 0.833) = 0.923×`. The documented 0.5–2.0 acceptance band is
unchanged. Accelerated throughput includes the same settling iterations.

## Results (pinned engine, private XDG/TMPDIR)

| Run | Checks | Exit |
| --- | --- | ---: |
| contract fixed/default/max (`--expect-checks 128`) | 128/128 each | 0 |
| strict N1 fixed/default/max (`--expect-checks 76`) | 76/76 each | 0 |
| structural fixed/default/max | 108/108 each | 0 |
| compare_modes throughput + trace | 9 + 2 PASS; realtime 0.912× | 0 |
| exit-code selftest | 5 total, 1 injected failure | 1 |
| mutation: settling removed | 7 failures / 128 (repeated requests lose steps) | 1 |

## Remaining limits / low issues

- The settling iteration is a deliberate engine-frame cost required for exact
  repeated same-world stepping; it is recorded, not hidden.
- Immediate-repeat pre-correction values remain in `repeat-pre-*` as history.
- Strict parsers still default `--expect-checks 0` and do not reconcile
  `checks_failed` with failure-list length (F6, unchanged).
- Cold registration diagnostic remains informational.
- No M0.8 acceptance claim.

## Files

| Path | Role |
| --- | --- |
| `repeat-pre-{fixed,default,max}.txt` | pre-correction same-world traces |
| `repeat-post-{fixed,default,max}.txt` | post-correction traces (exact 12,12) |
| `contract-{fixed,default,max}/` | 128-check suite including 12+12+1 |
| `n1-{fixed,default,max}.txt` | 76-check strict runner incl. same-world sequence |
| `structural-*` | 108-check structural suite |
| `compare-modes.txt` / `exit-code-selftest.txt` | pacing/fidelity and exit code |
| `mutation-settle-removed.txt` | regression sensitivity |
| `manifest.sha256` / `provenance.json` | hash-bound record |
