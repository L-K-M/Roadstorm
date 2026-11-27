# Recorded probe evidence — API-edge follow-up, 27 November 2026, Apple M4 Max

Current evidence for the M0.8 Sol-recheck follow-up. Reviewed candidate:
`bdb0a9820b847d23628cce35a9070bb63ae17acd` (`bdb0a98`), base
`d562755c83af1129b4ddf7043baee8d8a742d358`. Follows
`review/implementation/m0-tick-sol-recheck-bdb0a98.md`.

Supersedes `../../2026-11-27-apple-m4-max-jolt-waitguard/` as the current record.
The prior wait-guard manifest was re-verified against its exact committed
candidate `bdb0a98`: all **34/34** entries match `git show bdb0a98:<path>`
byte-for-byte. That directory is preserved unchanged.

## Setup and run policy

- Host: Apple M4 Max, macOS, arm64; Godot `4.7.2.stable.official.ed1daf0bf`;
  Python 3.15.2.
- Headless runs used isolated copies of `tools/tick_probe`; outputs went to an
  isolated scratch directory. No GUI, no desktop, no installed-tool or
  repository-file mutation, no Git changes, no network. `HOME` was not
  overridden; the contract runner redirects `XDG_CACHE_HOME`,
  `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `TMPDIR` into its own scratch copy.
- Each run was bounded to <= 30 s. Slowest recorded runs: `--max-fps 60`
  structural (11 s) and `compare_modes.py` (14 s).

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
| structural `--fixed-fps 60` | 108/108 | 0 | < 1 s |
| structural default pacing | 108/108 | 0 | 9 s |
| structural `--max-fps 60` | 108/108 | 0 | 11 s |
| contract `--pacing fixed` | 69/69 | 0 | < 1 s |
| contract `--pacing default` | 69/69 | 0 | 6 s |
| contract `--pacing max` | 69/69 | 0 | 5 s |
| `compare_modes.py` throughput + trace digests | 9 + 2 PASS | 0 | 14 s |
| exit-code self-test (`inject_failure=1`) | 5 total, 1 injected failure | 1 | < 1 s |
| five suites launched concurrently (incl. max pacing) | all pass | 0 | < 30 s each |
| pre-fix edge reproduction on `bdb0a98` | n/a | 0 | < 1 s |
| post-fix edge verification | n/a | 0 | < 1 s |
| mutation sensitivity (three fixes disabled) | 7 failures / 69 checks | 1 | < 1 s |

### Findings reproduced and closed

- **Negative request after a consumed terminal result.** Pristine `bdb0a98`:
  after a one-tick cap truncated and the result was consumed,
  `begin_step(-2)` returned `true`, published `requested_ticks = -2`,
  `elapsed_ticks = 0`, `terminal = "truncated"`, with `refusals = 0`.
  Post-fix: `accepted=false`, `pending=false`, `tick_count` unchanged,
  `refusals=1`, reason `negative requested_ticks`; the last signal still
  belongs to the consumed step. Negative validation now precedes every fast
  path. See `pre-fix-edge-reproduction.txt` / `post-fix-edge-verification.txt`.
- **Zero-tick completion published while unpaused.** Pristine `bdb0a98`: a
  synchronous `step_finished` listener observed `paused == false` during the
  `(0, none)` emission (the tree was frozen again immediately after).
  Post-fix: the listener observes `paused == true`; `take_result()` still
  returns `(0, none)` and the world stays frozen. Covered by
  `api-edge: zero-tick signal observed with the world frozen`.
- **Cap-0 reset observation.** Pristine `bdb0a98`: `reset()` with
  `max_ticks = 0` reported `terminal = "none"` although the README said the
  episode starts truncated. Post-fix: `observe().terminal == "truncated"`
  immediately, still paused, and the subsequent request stays
  `(0, truncated)`. Covered by `api-edge: cap-0 reset observation starts
  truncated`.
- **Harness timing vs simulation advancement.** The old polling-based tally
  sampled `SceneTree.physics_frame` after the pending result, so a trailing
  engine callback after completion/freeze could inflate both independent
  tallies. On pristine `bdb0a98`, six concurrent max-FPS stress runs produced
  one run with **10/100** overcounts (`elapsed=1`, `ext_delta=2`,
  `coord_delta=2`) while `tick_delta=1` every time
  (`harness-timing/pre-fix-post-poll-concurrent.txt`). The contract suite now
  snapshots the tallies inside `step_finished` and additionally asserts that a
  following frozen callback advances no logical tick. A dedicated post-fix
  experiment (100 one-tick requests per process, eight processes concurrent)
  saw post-poll overcounts up to **30/100** while signal-boundary mismatches
  and simulation-advancement mismatches stayed **0 in every run**
  (`harness-timing/post-fix-boundary-*`). Five suites launched concurrently
  all passed, including max-pacing contract 69/69
  (`concurrent-load/`). No check was weakened: the signal-boundary test is
  stricter about which callbacks count as active work.

## Files

| Path | Role |
| --- | --- |
| `structural-{fixed-fps,default,max-fps-60}.json` | full `PROBE_RESULT` payloads |
| `structural-*.checks.txt` | `CHECKS_TOTAL`/`CHECKS_FAILED` summary |
| `structural-*.raw.txt` | raw stdout/stderr |
| `contract-{fixed,default,max}/contract-tests.json` / `.txt` | contract suite under each pacing |
| `contract-*/run.txt` | full runner stdout/stderr |
| `compare-modes.txt` | throughput + intermediate-state trace digest comparison |
| `concurrent-load/*` | contract fixed/default/max, structural and compare launched together |
| `exit-code-selftest.txt` | injected-failure run, exit 1 |
| `pre-fix-edge-reproduction.txt` | negative/zero-tick/cap-0 edges on pristine `bdb0a98` |
| `post-fix-edge-verification.txt` | same driver against the fixed tree |
| `harness-timing/pre-fix-post-poll-concurrent.txt` | pre-fix polling overcount sample under load |
| `harness-timing/post-fix-boundary-serial.txt` | signal-boundary vs post-poll, serial |
| `harness-timing/post-fix-boundary-concurrent-{1..8}.txt` | same under eight-way concurrency |
| `mutation-sensitivity.txt` | contract suite with the three fixes disabled |
| `manifest.sha256` | SHA-256 of every probe source/test file and evidence output |
| `provenance.json` | machine-readable run record, reviewed-candidate hashes and limits |

## Limits (do not overread)

- Headless dummy display/audio drivers; no rendering, input, audio or
  windowing claim.
- One-car `CharacterBody3D` probe; not the full M1 motor, AI, contact
  resolver, multi-car reset, interactive invocation or full simulation.
- Same-host determinism only; cross-platform byte equality is not claimed.
- Backend identity is inferred from the pinned setting plus the earlier
  GodotPhysics3D contrast run; it is not directly observable from GDScript.
- Concurrent-load timing numbers are host-specific; the signal-boundary and
  simulation-advancement invariants held in every recorded run.
