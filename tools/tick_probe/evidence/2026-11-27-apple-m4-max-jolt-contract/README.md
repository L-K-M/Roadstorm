# Recorded probe evidence — tick/reset/bound fixes, 27 November 2026, Apple M4 Max

Current evidence for the M0.8 tick-probe audit response. Base candidate:
`55b04cec80fc842d1f40b5ac393a8a6492f112f3` (`55b04ce`), audited by
`work/agents/1b8fe3ed-3088-4847-a0e1-ea1676abc013/m08-probe-audit/REPORT.md`.

Supersedes `../../2026-11-26-apple-m4-max-jolt/` as the current record for the
fixed revision. That directory remains valid history for the backend-pinned
probe before these fixes.

## Setup and run policy

- Host: Apple M4 Max, macOS, arm64; Godot `4.7.2.stable.official.ed1daf0bf`;
  Python 3.15.2.
- Every command ran against an isolated copy of `tools/tick_probe` with
  `HOME`/`TMPDIR` inside the scratch directory. No GUI, no desktop, no
  installed-template or repository-file mutation, no git changes, no network.
- Each run was bounded to <= 30 s (the real-time runs finished in ~8-10 s).
- The contract runner (`tests/run_contract_tests.py`) performs its own
  isolated copy with a 30 s timeout.

Commands actually run:

```sh
godot --headless --fixed-fps 60 --path <isolated> --script res://src/tick_probe.gd -- mode=structural
godot --headless --path <isolated> --script res://src/tick_probe.gd -- mode=structural
godot --headless --max-fps 60 --path <isolated> --script res://src/tick_probe.gd -- mode=structural
python3 tools/tick_probe/tests/run_contract_tests.py --timeout 30
python3 tools/tick_probe/compare_modes.py --project <isolated>
godot --headless --fixed-fps 60 --path <isolated> --script res://src/tick_probe.gd -- \
    mode=throughput requests=2 inject_failure=1
```

## Results

| Run | Checks | Exit | Wall |
| --- | --- | ---: | ---: |
| structural `--fixed-fps 60` | 73/73 | 0 | 2 s |
| structural default pacing | 73/73 | 0 | 6 s |
| structural `--max-fps 60` | 73/73 | 0 | 8 s |
| independent contract suite | 30/30 | 0 | < 2 s |
| `compare_modes.py` (600 ticks each) | 9/9 PASS | 0 | 10 s |
| exit-code self-test (`inject_failure=1`) | 5 total, 1 injected failure | 1 | < 1 s |
| pre-fix reproduction on pristine `55b04ce` | n/a | 0 | < 1 s |
| mutation sensitivity (three fixes disabled) | 23/30 pass, 7 expected failures | 1 | < 1 s |

`compare_modes.py`: accelerated 600 ticks in 0.170 s (58.9x), real-time 600
ticks in 10.046 s (0.995x); final z `-99.999641418` m in both, `|dz| = 0`.

### Fixed behaviors now measured

- **Stale result after reset.** On pristine `55b04ce`, after a 12-tick step and
  `reset()` (`tick_count == 0`), `take_result()` returned
  `elapsed_ticks = 12`, `tick_count = 12` from the pre-reset episode
  (`pre-fix-reproduction.txt`). With the fix, `reset()` clears the stored
  result and `take_result()` returns an empty `Dictionary`; the contract suite
  fails if either path regresses.
- **`max_ticks <= 0`.** Pristine `55b04ce` executed one unintended tick at cap
  0 (`elapsed_ticks = 1`, body moved 0.1666667 m) and the same for a negative
  cap. Now cap 0 and cap -3 return `(0, truncated)` without consuming an
  engine physics frame or moving; cap 1 executes exactly one tick.
- **Motion bound.** At 250 m/s, pristine `55b04ce` consumed 12 ticks, reported
  50 m commanded, but moved only 48 m (192 substeps of 0.25 m) with
  `terminal = none` — a silent 2 m residual. Now `MAX_TICK_TRAVEL_M = 4.0`
  (`MAX_SUBSTEPS 16 * SUBSTEP_MAX_LEN 0.25`, supported speed 240 m/s):
  250 m/s forward and reverse return `(0, motion_bound)`, move nothing,
  advance no tick, and record `last_motion_bound_deficit_m = 0.1667` m.
  Exactly 240 m/s completes 12 ticks with `motion_bound_violations = 0`.

The mutation-sensitivity run disables the three fixes in a scratch copy; the
contract suite reports exactly the corresponding 7 failures and exits 1, so
the tests are not vacuous.

## Hash summary

SHA-256 of the exact probe inputs for this revision (full list, including every
evidence output, in `manifest.sha256`; machine-readable copy in
`provenance.json`):

| File | SHA-256 |
| --- | --- |
| `.gitignore` | `bc564f5ea42d01f3be02e26adfca5b5a3a2f30d2ed74f0973d3282705fb65d03` |
| `project.godot` | `dc27a9bf0eb91b1053cd4bc876a352abaaf286c599502ee3e1cbd88c5243a95d` |
| `README.md` (probe) | `c76000a11f1168eb7e4f0c7233f4ba1c3c2ce0e9eb131cd07c5fc18a727152c3` |
| `compare_modes.py` | `25a8101ec246dc0ebd31f2c8b52eecfb88e4e988236abef25314cad2b29a2630` |
| `src/tick_coordinator.gd` | `53e2d0d20fb60f7b31e832d299a4040601fc3011b78b61a69e169485cd60fbd8` |
| `src/probe_driver.gd` | `baf8d3730129a54cd328530ca87244ed71eff8c7f279807cdabfcb88f41e3f11` |
| `src/tick_probe.gd` | `ec46864a9fa5a8f08d980cc3b8c3f4f0a9fa4dabda42bdd64e57f0bbc44eb29d` |
| `tests/contract_entry.gd` | `188632102c4a32ba9aae20b87ba23bcd3c81da66088b68237576823cdd408138` |
| `tests/contract_driver.gd` | `07d9f8da739cd2fec95439c8481db2f64cefe1e2469cdfeff9c84fe71bbb4058` |
| `tests/run_contract_tests.py` | `761c39d93513a5af7ffb98c9b916d9dbf29a2d98e345a8791df325aa05782656` |

Base candidate commit: `55b04cec80fc842d1f40b5ac393a8a6492f112f3`.

## Files

| Path | Role |
| --- | --- |
| `structural-{fixed-fps,default,max-fps-60}.json` | full `PROBE_RESULT` payloads |
| `structural-*.checks.txt` | `CHECKS_TOTAL`/`CHECKS_FAILED` summary |
| `structural-*.raw.txt` | raw stdout/stderr of the run |
| `contract-tests.json` / `.txt` | independent frame-counting contract suite result |
| `compare-modes.txt` | accelerated-vs-real-time comparison |
| `exit-code-selftest.txt` | injected-failure run, exit 1 |
| `pre-fix-reproduction.txt` | adversarial driver output on pristine `55b04ce` |
| `mutation-sensitivity.txt` | contract suite against a copy with the fixes disabled |
| `manifest.sha256` | SHA-256 of every probe source/test file and evidence output above |
| `provenance.json` | machine-readable run record and hashes |

## Limitations (unchanged scope)

- Headless dummy display/audio drivers; no rendering, input, audio or
  windowing claim.
- One-car `CharacterBody3D` probe, not the full M1 motor, AI, contact
  resolver, multi-car reset, interactive invocation or training bridge.
- Same-host determinism only; cross-platform byte determinism is not claimed.
- Backend identity is inferred from the pinned setting plus the earlier
  GodotPhysics3D contrast run; it is not directly observable from GDScript.
- Real-time wall-clock numbers are host-load dependent; structural/contract
  checks are the stable gate.
