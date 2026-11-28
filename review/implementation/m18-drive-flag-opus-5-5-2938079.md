# Scoped review: DriveLab accepted wall-result flag repair, candidate 2938079

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, first-party,
  run through Claude Code. No delegation and no helper models.
- Date: 2026-11-28 (UTC run window about 03:19 to 03:25).
- Candidate: exact 2938079 ("Bind DriveLab wall retries to accepted contact
  flag"). Scoped base: 09573bf.
- Scope: only the accepted-wall-result `wall_contact` flag and fingerprint
  repair in `src/laboratory/drive_lab.gd` and
  `tools/drive_lab/drive_lab_driver.gd`, as given by `../scope.patch`
  (sha256 `ce676ac7...ca68`, 207 lines, two files).
- Verdict: **PASS** for this exact repair. No blocking or important findings.

## Inputs and identity

| File | sha256 (build and ../source identical) |
| --- | --- |
| src/laboratory/drive_lab.gd | 16ca30459fc62b10ab6441c337f40e1487d4ee2b0102d5a73e103bd0f28ed1aa |
| tools/drive_lab/drive_lab_driver.gd | f082e6f889f5071f41add26460b6bbb629af02be40986454b0df05d68a9ffe33 |

`diff -rq build source` differs only in `build/work/` (coordinator scratch
artefacts inside the archive, not candidate source). I did not edit any
candidate file, mutate Git, or read the sibling reviewer's report.

## Commands run (my own execution)

All runs used the pinned editor
`work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`
(reported `4.7.2.stable.official.ed1daf0bf`, backend Jolt Physics), serialized
through `lockf -t 1800 work/agents/coordinator/godot-test.lock`, with private
`HOME`, `TMPDIR`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME` under
`opus/private/`, and the runner's own watchdog (`--timeout 600`). Each run
stages an isolated project copy.

1. Candidate:
   `tools/drive_lab/run_validation.sh --project build --godot <pinned> --timeout 600 --log private/run.log`
   rc=0. `DRIVE_LAB_SUMMARY` 16 cases, 5312 checks, 0 failed;
   `wall_impact_integration` 233/233; bad-config fixture 99/99; deliberate
   failure probe rc=3 (expected). Event `drive_lab.wall.1.171.0`, hit tick
   170, region front, severity 17.89 m/s.
2. Old-source control (`private/oldctl`): copy of `../source` with only the
   `drive_lab.gd` hunk of `scope.patch` reverse-applied (driver kept new).
   rc=1, 5312 checks, 11 failed, all in `wall_impact_integration`:
   `wall.mutant.wall_contact_flag_{refused,no_coalesce,counts_one_refusal,specific_diagnostic}`,
   `wall.mutant.adapter_status_no_coalesce`,
   `wall.mutant.committed_velocity_no_coalesce`,
   `wall.mutant.restore_does_not_forge_a_second_event`,
   `wall.clear.mutant_{counts_one_refusal,does_not_fabricate_missed_witness,specific_diagnostic}`,
   `wall.clear.restore_leaves_missed_witness_unchanged`.
   This reproduces both Sol defects (real-hit retry coalesced; clear-tick
   mutation fabricated missed-witness telemetry) and matches the
   coordinator's supplied old-control result.
3. Fingerprint-only mutant (`private/fpctl`): candidate with only the
   `encode_for_digest(bool(snapshot["wall_contact"]))` fingerprint line
   deleted (snapshot and diagnostic kept). rc=1, the same 11 failures. The
   fingerprint entry, not the diagnostic, is the effective gate, and the
   tests discriminate it.
4. Committed-velocity mutant (`private/cvctl`): candidate with only the
   `committed_velocity` fingerprint line deleted. rc=1, 1 failure:
   `wall.mutant.committed_velocity_specific_diagnostic` (see finding 1).

Proj copies were deleted afterwards; logs remain under `opus/private/`.
No Godot process of mine remained (the only Godot-related processes seen
belonged to an unrelated Devin helper, which I did not touch). No parse
error or hang occurred.

## Code assessment

- **Capture after commit.** `drive_lab.gd:1117-1128`: the accepted
  result, tick, snapshot and fingerprint are set only on the COMMITTED path
  after the nonfinite guard, the gearbox proposal, mirror, and gear-agreement
  checks, after `state = published` and `ticks_committed += 1`, and before
  the first `publish_wall_event`. Every refusal or rollback path returns
  first, so no accepted snapshot exists for an uncommitted or unmirrored
  tick. `_wall_witness_snapshot` (`:950-972`) now stores `wall_contact` by
  value, so later caller mutation of the Result cannot change it.
- **Check order.** `publish_wall_event` (`:873-948`): identity/tick/failed
  /halted/stale gate, then snapshot and fingerprint comparison (`:885-896`),
  which now includes `wall_contact` (`:983`). Only after a match does the
  missed-witness branch (`:897-904`) read `result.wall_contact`, and only
  after that are the ID map, producer, ledger and published/coalesced
  counters touched. A mutated flag therefore refuses with exactly one
  `wall_events_refused` increment, a specific diagnostic (`:1011-1012`,
  "wall contact flag"), and no ID slot, ledger, last-event, missed-witness,
  state or pose change.
- **Both mutations.** Real hit, `wall_contact` true to false: previously
  coalesced, now refused. Clear tick, false to true: previously incremented
  `wall_event_missed_witnesses` silently through a "matching" fingerprint,
  now refused before that branch. Restoring the flag gives exact prior
  behaviour (hit coalesces once; clear tick returns false with no counter).
- **Diagnostic ordering** places the flag check after the two witness flags
  and before geometry; any single-field mutation names its field.

## Test assessment

- The new clear-tick case (`drive_lab_driver.gd:4011-4096`) first asserts the
  premise (COMMITTED, no witnesses, `wall_contact` false), then checks refusal
  count +1, unchanged missed-witness, published, coalesced, empty ledger,
  digest, canonical `snapshot_state`, body pose and the specific diagnostic,
  then restores and checks no further counters. It discriminates (control 2).
- The real-hit mutation loop (`:3858-3916`) gains `wall_contact_flag` and the
  previously uninvoked `committed_velocity` entry (closing the earlier Opus
  09573bf note) and adds canonical-state and body-pose invariance per
  iteration.
- **Save/restore honesty.** `_saved_wall_witness_state` and
  `_restore_wall_witness_state` (`:4101-4128`) now cover every field each
  loop entry mutates, including `wall_contact` and
  `committed_state.velocity_m_s` (a `Vector3`, copied by value; the
  `committed_state` object is the Result's own, and the per-iteration
  `snapshot_state(lab.state)` check would expose aliasing with `lab.state`).
  The loop restores after every entry, and the post-loop
  `restored_witness_still_coalesces` / `restore_does_not_forge_a_second_event`
  checks prove the restore is exact, since any residue would fail the
  fingerprint. Refusal counts are per-iteration (`iteration_base`), so they
  do not hide cascades.

## Findings (ranked)

1. **Low, test discrimination (non-blocking).**
   `drive_lab_driver.gd:3869,4159-4160`. For the `committed_velocity`
   entry, the refusal, counter, ledger and no-coalesce checks are also
   satisfied by `WallImpactProducer.produce`'s own post/committed equality
   refusal (`wall_impact_producer.gd:143-150`) when the DriveLab fingerprint
   omits the field (control 4). Only the specific-diagnostic check
   discriminates the DriveLab gate there. That is still a real, failing
   discriminator, and behaviour stays safe either way (no event, no new ID
   slot). Optional: also mutate `wall_post_response_velocity_world_m_s`
   identically, or assert the diagnostic does not contain "producer refused".
2. **Info, cascade in failure reporting.** `drive_lab_driver.gd:3881-3885`
   compares `coalesced` against the pre-loop `base_telemetry`, so one leaked
   coalesce (as in the old-source control) also fails later entries'
   `no_coalesce` (`adapter_status`, `committed_velocity`). This makes failure
   lists noisier but never hides a defect. No change needed.

## Out of scope (not findings against this repair)

- **Adapter-config hardening (low, optional).** `publish_wall_event` passes
  the live `adapter_config` (`drive_lab.gd:917-918`); the producer reads
  `config.hull_size_m` for region classification. Config is lab-owned and
  replaced only through the reconfigure path, not through the caller-owned
  Result, so it is not a Result-mutation bypass. Snapshotting the hull size
  at acceptance would be optional hardening.
- **Sustained-contact policy.** `wall_contact_ticks` (`:1367-1368`) and
  missed-witness semantics for multi-tick contact are a policy question for
  later M1.8 work; this repair only binds the accepted flag.
- **Full M1.8.** This review does not assess wall-region classification
  (the separate producer corner work in shared main), other wall producer
  contracts, or M1.8 readiness overall.

## Limits

- I ran only the scoped DriveLab suite (`tools/drive_lab/run_validation.sh`),
  not `tools/ci/ci.sh`, export smoke, other labs, or Python contract suites.
- Pinned engine digest verification was not repeated by me; I relied on the
  runner's version check against `tools/toolchain/pin/engine.txt`.
- Local macOS execution only; no CI result was inspected.
- Coordinator logs under `work/agents/coordinator/drive-wall-flag-frozen-6908e5f/`
  were read only to find the runner command and compare outcomes; my
  results above come from my own runs.
