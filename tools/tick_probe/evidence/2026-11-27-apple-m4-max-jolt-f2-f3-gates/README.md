# Recorded probe evidence — F2/F3 regression strength

Responds to Opus findings F2/F3 in
`review/implementation/m0-tick-opus-5-5-1295892.md` and Sol’s two low findings,
on top of the uncommitted F1 physics-callback fix. Base tick commit:
`12958922d34f1a7a89675a4e89381f2c298caba4`.

## Measured exact signal-time relationship first

Before choosing any gate, warmed request cycles were measured at signal time
(`step_finished`) across pacings (`signal-time-summary.txt`, raw `sig-*.txt`):

| Pacing | Warmed requests | `server_steps_delta == requested` and `signal_pf_delta == requested` |
| --- | ---: | ---: |
| fixed | 75 | **75/75** |
| default | 75 | **75/75** |
| max | 150 | **150/150** |

Host catch-up changes delivered iterations for continuous windows, but warmed
request cycles are exact at both step and frame level under the corrected
synchronous boundary. No nominal frame count that catch-up disproves is used as
a hard request gate.

## Root cause found by warming the controls

The earlier deferred-pause design cost one extra server step per request for an
already-active body; cold-body registration absorbed it, which is why fresh-body
gates appeared green. Warmed two-request trace (pre-fix, private copy):
first 12-tick request = 13 counted steps, second = 12; immediate-repeat
informational metric remains 11–12 depending on the pause/resume boundary.

Corrections:

- Completion now pauses synchronously in the final tick’s own callback: the
  final tick’s server step is counted and the next iteration is skipped. No
  extra boundary iteration exists, so realtime speedup returns to ~1.00×.
- `begin_step()` validates the motion envelope **before unpausing**. An
  over-envelope refusal never activates the server, so its warm control is
  exactly zero steps; the runtime pre-check remains for mid-request changes.
- Physics-callback-origin requests activate at end of frame (`call_deferred`),
  equivalent to idle-time activation; a later-ordered observer verifies no
  unaccounted unpaused iteration (expected `requested - 1` callbacks).
- Warm gates use deterministic activation (unpause 5 frames, freeze, settle 2)
  because cold registration adds ±1 iteration. Fresh-body scenarios remain but
  use an explicit `[n−1, n]` bound; exact request equality lives in warmed
  cycles for 1/12/24 and repeated 12-tick requests.

## Pre/post warm probe (committed `tests/warm_step_probe_entry.gd`)

| Metric | pre-fix tree | corrected |
| --- | ---: | ---: |
| warmed idle 12-tick counted steps | **13** | **12** |
| physics-caller paused after call | true | true |
| physics-caller counted steps | 12 | 12 |
| physics-caller unaccounted unpaused callbacks | **12** | **11** |
| warmed motion-bound refusal counted steps | **1** | **0** |

Pre-fix: 3/5 checks failed; corrected: 5/5 passed. The probe is committed, so
the evidence is reproducible from source.

## Mutation sensitivity (private copies)

- Remove begin-step envelope validation (refusal reaches the runtime boundary):
  warmed motion-bound control fails with `steps=4->5`.
- Make physics-callback origin synchronously unpause: physics-caller frozen
  check and unaccounted-unpaused-iteration check fail (observer delta 12 vs 11).

## Verification results (pinned engine, private XDG/TMPDIR)

| Run | Checks | Exit |
| --- | --- | ---: |
| contract fixed/default/max (`--expect-checks 110`) | 110/110 each | 0 |
| strict N1 fixed/default/max (`--expect-checks 61`) | 61/61 each | 0 |
| structural fixed/default/max | 108/108 each | 0 |
| `compare_modes.py` throughput + trace | 9 + 2 PASS; realtime 1.00× | 0 |
| exit-code selftest | 5 total, 1 injected failure | 1 |
| mutation F2 | 2 failures / 110 | 1 |
| mutation F3 | 1 failure / 110 | 1 |

Sol low findings addressed: per-request `elapsed_ticks`/paused assertions folded
into N1; stale `--expect-checks 14` usage updated; cold-start wording qualified
as informational diagnostic.

## Remaining low issues / limits

- Immediate back-to-back requests can show a pause/resume reactivation variance
  (informational metric); exact gates use independently warmed cycles.
- F4 pause-enforcer machinery removed: completion pauses in the coordinator, so
  no extra iteration exists; later-in-tree nodes miss the synchronously paused
  final iteration (callback delivery only), counted server steps stay exact.
- F5 `configure()` now ends frozen; freed-helper fallback is moot.
- F6 strict parsers still default `--expect-checks 0` and do not reconcile
  `checks_failed` with failure-list length; not changed here.
- Cold registration diagnostic remains informational; no M0.8 acceptance claim.

## Files

| Path | Role |
| --- | --- |
| `warm-probe-pre.txt` / `warm-probe-post.txt` | committed warmed probe on old/new trees |
| `signal-time-summary.txt` / `sig-{fixed,default,max}.txt` | 300 warmed request measurements |
| `contract-{fixed,default,max}/` | 110-check contract suite |
| `n1-{fixed,default,max}.txt` | strict 61-check N1 runner outputs |
| `structural-*` | 108-check structural suite |
| `mutation-f2.txt` / `mutation-f3.txt` | targeted mutation failures |
| `compare-modes.txt` / `exit-code-selftest.txt` | pacing/fidelity and exit code |
| `manifest.sha256` / `provenance.json` | hash-bound record |
