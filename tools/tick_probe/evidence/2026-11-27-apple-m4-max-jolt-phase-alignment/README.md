# Recorded probe evidence — per-tick physics-server phase alignment

Both independent `b56d902` reviews require changes. This bounded correction
addresses Opus F1/F2 and Sol F1/F2: align every logical tick with its own
`PhysicsServer3D.step()` and publish only after the final server-owned state is
observable. It also adds the committed callback/mixed hard gate (Opus F3) and
the expected-progress/dynamic-freshness checks (Opus F4 / Sol F2).

Base candidate `b56d9028e4a448688b6120ff99da177f44acfdff`; Godot
`4.7.2.stable.official.ed1daf0bf`, Jolt, Apple M4 Max.

## Measured phase shift (pre-correction, private scratch)

A warmed counting `RigidBody3D` records which logical tick each
`_integrate_forces` observes (`phase-iter-pre.txt`):

- 12-tick request integrations: `[0,0,0,0,0,1,2,...,11]` — one integration
  before L1 and **no integration of L12**.
- One-tick terminal: integration observed tick `0`, final tick never integrated.
- Mid-request `motion_bound` after k=3 elapsed ticks: `k+1 = 4` integrations
  (one extra error-path step).
- Repeated same-world idle requests: `[13,12]`, i.e. one phantom then one lost
  boundary step.

## Corrected scheduling (measured post)

- Every origin arms the request; the coordinator's next ALWAYS physics callback
  unpauses and executes L1 in that iteration, so L1's server step follows it.
  No synchronous or `call_deferred` unpause can run a step before L1.
- After Ln the tree stays unpaused through that server step. The next callback
  pauses first (suppressing its own step), flushes/syncs server state, rebuilds
  the observation and publishes `step_finished`.
- Instrumented sequence now integrates `[1..12]` in order; no pre-tick phantom
  and no missing final tick. One-tick terminal integrates exactly once before
  publication. Mid-request refusal now yields exactly k steps.
- Signal-time span is `n + 1` engine frames (one activation/publication
  boundary iteration); server steps remain exactly `n`.

## Hard committed gate

`tests/repeat_sequence_{entry,driver}.gd` (+ strict `run_repeat_tests.py`) run
**12 + 12 + 1 on one warmed body/world** for idle, callback and mixed origins,
with no reset or artificial unpause between requests. At `step_finished` and
after `take_result()`:

- `requested == elapsed == tick_delta == server_step_delta`;
- the integration slice equals the consecutive tick range (no phantom/lost);
- frozen nonterminal publication;
- published server-owned dynamic transform/velocity equal the live values;
- committed kinematic progress `-z == speed * DT * ticks`;
- a separate 30-frame frozen wait adds no step or motion;
- warmed mid-request `motion_bound` yields exactly k=3 steps;
- a one-tick terminal publishes exactly one integration and fresh state.

The callback/mixed driver is committed. `physics_caller.gd` is configurable
(`requested_ticks`) so callback sequences are not fixed at 12.

## Mutation sensitivity

- Publish immediately in the final callback (old behavior): 10 failures;
  integrations end at 11/23, final tick missing.
- Defer the mid-request refusal pause: 1 failure; `k+1 = 4` steps, integration
  `[1,2,3,3]`.

## Results (pinned engine, private XDG/TMPDIR)

| Run | Checks | Exit |
| --- | --- | ---: |
| contract fixed/default/max | 133/133 each | 0 |
| strict N1 fixed/default/max | 76/76 each | 0 |
| repeat hard gate fixed/default/max | 54/54 each | 0 |
| structural fixed/default/max | 108/108 each | 0 |
| compare_modes throughput + trace | 9 + 2 PASS | 0 |
| exit-code selftest | 5 total, 1 injected failure | 1 |
| mutation: immediate publish | 10 failures / 54 | 1 |
| mutation: deferred refusal | 1 failure / 54 | 1 |

## Honest overhead and residuals

- Every request costs one additional engine frame (`n + 1`) for activation and
  publication; it adds **no** physics-server step. Realtime measured 0.912× in
  this run against the 0.923× ideal ceiling from 50 boundary iterations; host
  variance applies. Accelerated throughput includes the same iterations.
- Historical raw outputs from earlier revisions remain preserved unchanged.
- Opus F4’s broader “server-owned contact/area state visibility” question is
  partially addressed by the dynamic transform/velocity freshness equality and
  by documenting the flush boundary; contacts/areas themselves are not gated.
- Runner gaps remain: `--expect-checks` defaults to 0 and `checks_failed` is
  not reconciled with `len(failures)` (recorded runs pin counts explicitly).
- No M0.8 acceptance claim; other platforms/hardware untested.

## Files

| Path | Role |
| --- | --- |
| `phase-pre.txt` / `phase-post.txt` | ordering traces around signals |
| `phase-iter-pre.txt` / `phase-iter-post.txt` | integration-vs-tick pairing proof |
| `repeat-pre-{fixed,max}.txt` / `repeat-post-{fixed,max}.txt` | old/new repeated-sequence runner output |
| `contract-{fixed,default,max}/` | 133-check contract suite |
| `n1-{fixed,default,max}.txt` | 76-check strict N1 |
| `structural-*` | 108-check structural suite |
| `compare-modes.txt` / `exit-code-selftest.txt` | pacing/fidelity and exit code |
| `mutation-publish.txt` / `mutation-refusaldelay.txt` | targeted mutation failures |
| `manifest.sha256` / `provenance.json` | hash-bound record |
