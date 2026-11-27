# Recorded probe evidence — wait-guard follow-up, 27 November 2026, Apple M4 Max

Current evidence for the M0.8 Opus-recheck follow-up. Reviewed candidate:
`d562755c83af1129b4ddf7043baee8d8a742d358` (`d562755`), base
`55b04cec80fc842d1f40b5ac393a8a6492f112f3`. Follows
`review/implementation/m0-tick-opus-recheck-64cbe5b0-7cc7-4130-80a3-cfc7d4d59f43.md`.

Supersedes `../../2026-11-27-apple-m4-max-jolt-contract/` as the current record.
The earlier manifest was re-verified against the exact committed candidate:
all **26/26** entries of `../2026-11-27-apple-m4-max-jolt-contract/manifest.sha256`
match `git show d562755:<path>` byte-for-byte (probe sources, test sources and
recorded outputs). That directory remains valid history for the first
audit-response revision.

## Setup and run policy

- Host: Apple M4 Max, macOS, arm64; Godot `4.7.2.stable.official.ed1daf0bf`;
  Python 3.15.2.
- Every command ran headless against an isolated copy of `tools/tick_probe`,
  with `HOME`/`TMPDIR` inside the scratch directory. No GUI, no desktop, no
  installed-template or repository-file mutation, no Git changes, no network.
- Each run was bounded to <= 30 s. The slowest recorded runs are the
  `--max-fps 60` structural suite (12 s) and `compare_modes.py` (13 s).
- The contract runner performs its own isolated copy with a 30 s timeout.

Commands actually run:

```sh
godot --headless --fixed-fps 60 --path <isolated> --script res://src/tick_probe.gd -- mode=structural
godot --headless --path <isolated> --script res://src/tick_probe.gd -- mode=structural
godot --headless --max-fps 60 --path <isolated> --script res://src/tick_probe.gd -- mode=structural
python3 tools/tick_probe/tests/run_contract_tests.py --pacing fixed   --timeout 25
python3 tools/tick_probe/tests/run_contract_tests.py --pacing default --timeout 25
python3 tools/tick_probe/tests/run_contract_tests.py --pacing max     --timeout 25
python3 tools/tick_probe/compare_modes.py --project <isolated> --timeout 25
godot --headless --fixed-fps 60 --path <isolated> --script res://src/tick_probe.gd -- \
    mode=throughput requests=2 inject_failure=1
```

## Results

| Run | Checks | Exit | Wall |
| --- | --- | ---: | ---: |
| structural `--fixed-fps 60` | 99/99 | 0 | 2 s |
| structural default pacing | 99/99 | 0 | 8 s |
| structural `--max-fps 60` | 99/99 | 0 | 12 s |
| contract `--pacing fixed` | 51/51 | 0 | < 1 s |
| contract `--pacing default` | 51/51 | 0 | 5 s |
| contract `--pacing max` | 51/51 | 0 | 6 s |
| `compare_modes.py` throughput | 9/9 PASS | 0 | 10 s total |
| `compare_modes.py` trace digests | 2/2 PASS | 0 | included above |
| exit-code self-test (`inject_failure=1`) | 5 total, 1 injected failure | 1 | < 1 s |
| pre-fix reproduction on `d562755` | n/a | 0 | < 1 s |
| post-fix independent-body verification | n/a | 0 | < 1 s |
| mutation sensitivity (wait freeze + refusal guards disabled) | 6 failures / 50 checks | 1 | < 1 s |

### Follow-up findings reproduced and closed

- **M1 — world kept advancing while waiting.** On pristine `d562755`, an
  independent `RigidBody3D` fell during the wait after `reset()`
  (`y 8.834 -> 5.333` over 30 physics frames, `ticks=0`, `paused=false`) and
  after `begin_step(0)` (`y 9.488 -> 6.752`, `ticks=0`); a cap-0 reset also ran
  free (`y 10.0 -> 8.834`). Post-fix, the same driver reports `drifted=false`
  and `paused=true` in all three cases, while the control body still falls when
  the world is deliberately unpaused. See `pre-fix-reproduction.txt` and
  `post-fix-verification.txt`.
- **L1 — overlapping begin_step.** Pristine `d562755`: after 3 ticks of a
  12-tick request, a second `begin_step(5)` overwrote the budget; the result
  reported `elapsed=5` with `tick_count=8`, silently dropping the first
  request's accounting; `begin_step(-1)` produced a `(0, none)` step. Post-fix:
  the second call is refused (`begin_step_refusals=1`), the first request
  completes `elapsed=12` at `tick_count=12`, negative budgets are refused, and
  untaken-result calls are refused without state change. Covered by
  `contract-{fixed,default,max}` and structural `begin-step:*` checks.
- **L3 — residual-motion backstop.** With only the pre-tick envelope check
  disabled, `d562755` moved 48 m of 50 commanded while recording violations but
  finishing `terminal=none`; the new in-loop backstop ends the request with
  `motion_bound`, matching the pre-check. The primary path is exercised by the
  structural `work-envelope:*` checks including a mid-request speed change
  (`elapsed=2`, `terminal=motion_bound`). The backstop itself is
  defence-in-depth and is documented as not reachable through the public
  constant-speed configuration within the 1e-6 tolerance band.
- **L4 — frame-counting evidence.** The contract suite now waits on engine
  physics callbacks rather than process frames and passes under all three
  pacings (51/51 each). `compare_modes.py` compares per-tick digests across
  fixed/default/max pacing; all recorded digests matched exactly
  (`max |diff| = 0`).
- **L5/L6 — evidence and hygiene.** This manifest binds every source/test file
  and evidence output by SHA-256, and `provenance.json` records the reviewed
  candidate plus the prior manifest verification. `compare_modes.py` can still
  run in place by default; the recorded run used `--project <isolated>`.

## Files

| Path | Role |
| --- | --- |
| `structural-{fixed-fps,default,max-fps-60}.json` | full `PROBE_RESULT` payloads |
| `structural-*.checks.txt` | `CHECKS_TOTAL`/`CHECKS_FAILED` summary |
| `structural-*.raw.txt` | raw stdout/stderr of the run |
| `contract-{fixed,default,max}/contract-tests.json` / `.txt` | contract suite under each pacing |
| `contract-*/run.txt` | full runner stdout/stderr |
| `compare-modes.txt` | throughput + intermediate-state trace digest comparison |
| `exit-code-selftest.txt` | injected-failure run, exit 1 |
| `pre-fix-reproduction.txt` | independent-body/overlap reproduction on pristine `d562755` |
| `post-fix-verification.txt` | same driver against the fixed tree |
| `mutation-sensitivity.txt` | contract suite with the new guards disabled |
| `manifest.sha256` | SHA-256 of every probe source/test file and evidence output |
| `provenance.json` | machine-readable run record, reviewed-candidate hashes and limits |

## Limits (do not overread)

- Headless dummy display/audio drivers; no rendering, input, audio or
  windowing claim.
- One-car `CharacterBody3D` probe, not the full M1 motor, AI, contact
  resolver, multi-car reset, interactive invocation, training bridge or full
  simulation.
- Same-host determinism only; cross-platform byte equality is not claimed.
- Backend identity is inferred from the pinned setting plus the earlier
  GodotPhysics3D contrast run; it is not directly observable from GDScript.
- Wall-clock numbers are host-load dependent; structural/contract checks are
  the stable gate.
- The intermediate-state trace covers this probe's existing one-car scenarios;
  it does not establish full-simulator cross-pacing fidelity.
