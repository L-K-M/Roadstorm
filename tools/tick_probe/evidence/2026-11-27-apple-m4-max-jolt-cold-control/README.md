# Recorded probe evidence — max-pacing cold control follow-up

Follow-up to the coordinator's independent strict-N1 report: HEAD `482069e` plus
the uncommitted tick-probe candidate, where strict N1 passed fixed/default but
failed intermittently at max pacing on the continuous cold control while every
request-step check passed.

## Reproduction (private copy, old 14-check driver)

| Pacing | Runs | Failures | Failing checks |
| --- | ---: | ---: | --- |
| max | 30 then 60 | **1/30**, then **13/60** | cold k=1 (delta 1 vs `<=0`) and/or cold k=12 (delta 12 vs `<=11`) |
| fixed | 40 | 0/40 | none |
| default | 40 | 0/40 | none |

Every failing run passed all request scenarios (fresh first 1-, 12-tick,
repeated 12-tick; exact counted server steps) — only the nondeterministic cold
control failed. Full failing sample: `pre-fix-max-failure.txt`.

### Causal diagnosis

Cold-spawn registration is timing-dependent: a body created while paused may be
flushed into Jolt before or after the measured window. The recorded deltas are
therefore either `k` or `k−1`:

- max: k=1 → {0, 1}; k=12 → {11, 12} across samples.
- fixed/default: consistently {0} and {11}, but that is not guaranteed by the
  engine contract.

This is incidental registration behavior, not active-request stepping. No
physics-server step was lost: request counts stayed exact in all failing runs,
including the coordinator's own report where both cold checks failed and all
request checks passed.

The old hard expectation `delta <= k - 1` was therefore an invalid
nondeterministic gate. It is removed with this causal evidence, not to hide a
regression: the deterministic request controls and a new deterministic warmed
control carry the safety assertions.

## Fix: deterministic bounded controls

`tests/n1_regression_driver.gd` now:

- keeps exact request gates for fresh first **1**, **12** and **24** ticks and
  repeated **12**-tick requests;
- adds a **warmed continuous control**: activate the body for several unpaused
  frames, freeze, then require exactly one counted integration per *delivered*
  engine iteration (`server_steps_delta == engine_pf_delta`, `>= 1`). Engine
  catch-up (extra delivered iterations) is accounted instead of compared to a
  nominal frame count;
- records a **cold registration diagnostic** as an informational metric (no
  pass/fail), with its observed distribution in this evidence.

N1 check count goes 14 → **21**. Contract suite unchanged at 91 checks.

## Post-fix verification (private copy)

| Pacing | Repeated runs | Failures | Warmed invariant |
| --- | ---: | ---: | --- |
| max | 60 | **0** | 120/120 samples `steps == engine frames` |
| fixed | 40 | **0** | 80/80 |
| default | 40 | **0** | 80/80 |

Representative strict-runner outputs: `post-fix-n1-{fixed,default,max}.txt`.
Aggregate metrics: `post-fix-repeat-summary.txt`. In post-fix max samples the
warmed window sometimes delivered 2 iterations for a nominal k=1 (catch-up);
the equality invariant still held every time, and request checks never failed.

Contract 91/91 under all three pacings and structural 108/108 were re-verified
on the same private copy; this evidence focuses on the N1 change.

## Files

| Path | Role |
| --- | --- |
| `pre-fix-max-failure.txt` | full strict-N1 failure sample (old 14-check driver) |
| `pre-fix-frequency.txt` | per-pacing sample counts and failing-check summary |
| `post-fix-n1-{fixed,default,max}.txt` | representative post-fix strict-runner output (21 checks) |
| `post-fix-repeat-summary.txt` | 140-run aggregate frequencies and invariants |
| `manifest.sha256` / `provenance.json` | hash-bound record and candidate context |

## Limits

- Godot 4.7.2/Jolt, one host; max-pacing registration flush timing is not a
  guaranteed engine property.
- The cold diagnostic is informational; no M0.8 acceptance claim is made from
  it. Exact request guarantees remain the gated controls.
- Wall-clock/catch-up sample counts are host-load dependent.
- Historical evidence directories are preserved unchanged.
