# Roadstorm exact-candidate checkpoint review

**2026-11-28, Europe/Zurich.** Reviewer route supplied by the invocation: **GPT-6.2 Sol via OpenAI Codex CLI (OpenAI)**. No backend revision is visible to the reviewer.

Candidate **`9f9ef376f8e17ec5025ad6c899c4c93f4b348504`**. `git get-tar-commit-id < ../../source.tar` matched `source-sha.txt`. `shasum -a 256 ../../source.tar` matched `source.tar.sha256` at `3571ed0aec92f38b012fe082fdba9ded03e28ffd9ddbd04d3fc2f35c312ceee7`. Python `tarfile` comparison after testing found byte-for-byte matches for all 1,355 regular archive members in both `source/` and `private/build/`. Both roots lacked `.git`. No shared Git state, archived content, concurrent-reviewer material or helpers were used.

## Verdicts

| Scoped slice | Verdict | Basis |
|---|---|---|
| M0.2 typed upgrade definition and data lab | NOT VERIFIED | No source defect found. The two scoped cases passed their assertions, but the strict engine-error gate is open. The direct all-case run lacked wrapper setup. |
| M1.8 DriveLab wall-policy seam | CHANGES REQUIRED | The accepted retry rebuild depends on live configuration. Reproduced below. |
| M2.1 OPEN driving strip | NOT VERIFIED | No source defect found in the scoped bake. The mesh/Jolt assertions passed, but the strict engine-error gate is open. |
| Arc-test A1/A2/A3 | NOT VERIFIED | Both numerical refusal paths and the documentation check out. The assertions passed, but the strict engine-error gate is open. |

## Ranked actionable defect

**1. Medium, M1.8. An exact accepted-witness retry can fail because it reads the current adapter configuration.** The public contract calls for the same accepted Result and witness snapshot to coalesce the existing record (`src/laboratory/drive_lab.gd:985–1039`, `tools/drive_lab/README.md:208–239`). The fingerprint covers Result fields, but the retry then calls the shared producer with the current `adapter_config` (`drive_lab.gd:1153–1165,1213–1262`). This configuration is public and assigned by reference in `configure()` (`drive_lab.gd:206,496–510`). The producer validates the current config and uses its current hull extents for region (`src/simulation/wall_impact_producer.gd:117–134,203–222,275–314`).

Reproduction uses the existing real-Jolt contact-bay onset in `tools/drive_lab/drive_lab_driver.gd:3715–3840`. After its regular successful same-tick retry, keep the same Result, tick, witness and scope, temporarily set `lab.adapter_config.hull_size_m = Vector3.ZERO`, and call `lab.publish_wall_event(witness)` before any new step. The private driver reported `coalesced:false`, one retained record, an unchanged content digest, and `tick 171 producer refused wall event drive_lab.wall.1.0.0: invalid motor-body config`. Restore the original hull immediately. There is no duplicate event or physics mutation. The failure is loss of the promised idempotent retry even while the accepted record is intact. After checking the accepted object, tick and fingerprint, retry using the retained authoritative event, or preserve the producer inputs when accepting the tick. Add a same-tick regression with a changed live config.

## Inspection

- **Upgrade.** `src/data/upgrade_definition.gd:24–178`, `src/data/definition_identity.gd:16–145`, `tools/data_lab/data_lab_checks.gd:139–161`, `tools/data_lab/validate_data_lab.gd:571–898`, `tools/data_lab/README.md:105–129`, `src/data/README.md:176ff`, and `docs/GAME_DESIGN.md:179–185`. The typed identity validations precede field checks. Price is incremental at 800 and 1,600, and the 7,200 full-car total agrees with the design. The six category effects use stock-relative formulas, including the Tires exit-blend divisor. Tires omit effects on drift damping, entry threshold and slip. The three category round trips preserve exported identity and authored fields and recompute effects. No garage, save, purchase or application behavior was inferred.
- **Wall.** `src/laboratory/drive_lab.gd:823–1289,1330–1402,1750ff,1841ff`, `src/simulation/wall_contact_policy.gd:350–809,913–1010`, `src/simulation/wall_impact_producer.gd:117–334`, `tools/drive_lab/drive_lab_driver.gd:3705–4490`, and `tools/drive_lab/README.md:207–258`. Advancement is after the COMMITTED adapter result and successful canonical gearbox/CarState publication. A producer probe supplies severity, region and road-plane response normal. Suppressed ticks create no publication ID or ledger entry. Exact unchanged retries preserve policy state, and retirement resets the ledger and increases the scope generation. Refusal paths leave physics authority intact. The source-derived wall event has no imparted travel because accepted sweep travel precedes the wall response. The retry defect above concerns the publication seam.
- **OPEN strip.** `src/course/road_strip_baker.gd:19–54,164–283,394–744,746–933`, `tools/road_strip_lab/validate_road_strip_lab.gd:51–305`, `tools/road_strip_lab/failure_probe.gd`, and `tools/road_strip_lab/README.md:1–39`. Checked both clockwise index triples against the preceding up axis, row normals from frame up, the identical triangle soup passed to the one-sided shape, the shared-row copy between chunks, and last partial chunk arithmetic. The Jolt in-world queries hit from above in both fixture chunks. Segment metadata takes section/surface from the preceding frame and allocates exactly one record per segment. Refusals for malformed input, invalid options, closed tables, nonmonotonic stations and unusable geometry occur before engine-resource construction. Vertex/cross-product finiteness, area and alignment are checked before packing. The documented contact-to-segment mapping and surface use remain integration work.
- **Arc tests.** `tools/road_sampling_lab/road_sampling_checks.gd:33–38,150–155,913–921,1065–1175`, `tools/road_sampling_lab/README.md:125–169,208–223`, and the relevant runtime guard in `src/course/road_arc_sampler.gd:421–463`. The old `2^53` fixture still asserts refusal at the roundoff-implied floor. The default-options `2^29` prefix permits integration, then a positive `2^-26` orthogonal span is smaller than half a float64 ULP at that station. The new case checks the specific guard diagnostic, section and span index, positive local length and equal global endpoints. The README distinguishes per-span budget, summed table estimate, and separate residual estimate. Runtime was read for the guard only.

## Commands and evidence

Ran from `private/build`. The runner and logs are in ignored `work/review/`. Every engine invocation used the prescribed absolute Godot editor path under `work/agents/coordinator/toolchain-m01/prefix/editor`, private HOME/TMPDIR and XDG cache/config/data, and this command prefix:

```sh
/usr/bin/lockf -k "$coordinator/godot-test.lock" timeout -k 5 120 \
  "$coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot" \
  --headless --path "$PWD"
```

| Arguments after prefix | Exit and structured evidence |
|---|---|
| `--version`; `--editor --import` | 0; 0. Version `4.7.2.stable.official.ed1daf0bf`. |
| `--script res://tools/data_lab/validate_data_lab.gd --case=all` | 1. 21 cases, 772 checks, two failures for missing legacy-path sentinels in `scratch_reservation_control`. The direct invocation omitted the sentinel creation performed by `tools/data_lab/run_validation.sh:304–325`. Both scoped cases passed. |
| Same data script with `--fixed-fps 60` and each of `--case=upgrade_definition_contract`, `--case=upgrade_tres_round_trip` | 0 and 0. 161 and 77 checks respectively, zero assertion failures. |
| Same data script with `--case=intentional_failure` | 1. `INTENTIONAL_FAILURE_PROOF` reports the intended failure, `observed_checks_failed:1` and `pass:false`. |
| `--fixed-fps 60 --script res://tools/drive_lab/validate_drive_lab.gd` | 0. Jolt, 17 cases, 5,333 checks, zero failures. |
| `--fixed-fps 60 --script res://tools/drive_lab/bad_config_fixture.gd` | 0. `BAD_CONFIG_RESULT`, 99 checks, zero failures. ObjectDB leak warning at exit. |
| `--fixed-fps 60 --script res://tools/drive_lab/failure_probe.gd` | 3. `PROBE_RESULT`, one intentional failure in two checks. |
| `--script res://tools/road_strip_lab/validate_road_strip_lab.gd`; matching `failure_probe.gd` | 0; 3. Three cases and 108 checks with zero failures, then one intentional failure in two checks. |
| `--script res://tools/road_sampling_lab/validate_road_sampling_lab.gd`; matching `failure_probe.gd` | 0; 3. Eleven cases and 646 checks with zero failures, then one intentional failure in two checks. |
| `--fixed-fps 60 --script res://work/review/config_retry.gd` | 0. Private copied driver emitted `REVIEW_CONFIG_RETRY` for the counterexample while its unchanged stock assertions remained green. |

**Engine error gate failed.** All engine launches other than version printed `ERROR: Condition "ret != noErr" is true. Returning: ""` at `get_system_ca_certificates (platform/macos/os_macos.mm:1035)`. No `SCRIPT ERROR` or other `ERROR` line appeared in the logs. The structured results show execution and assertion outcomes, but the requested strict error gate prevents a clean engine verification claim. The full data wrapper with legacy sentinel setup was not run. I did not re-run the coordinator's old-source strip comparison, separate real source-to-strip fixtures, pure-policy standalone suite, full CI or exports.

## Plan and remaining gates

The wall retry issue conflicts with the documented scoped contract. No additional scoped plan mismatch was found. Optional extra checks for this checkpoint are a dedicated upward backface ray, a swept-body seam crossing, and a permanent composite source-to-bake test for banked bends and rapid grades. Full course integration still needs physical seam and surface validation.

- **M0.2 and M0.** Full shell/scene and typed-schema scope, reproducible setup, boot, deliberate-failure and desktop smoke evidence, and rights/provenance inventory remain outside this review. Garage, purchased-level persistence and runtime application are separate product work.
- **M1.8 and M1.** Complete the committed-event stream and contact coverage, corner identity and consumer integration without a feedback impulse. Whole M1 still requires drift/control, speed and FPS equivalence evidence, calibration fixtures, recovery/contact coverage and independent capability-labeled driving review.
- **M2.1 and M2.** Complete shoulders, barriers, closed-loop closure, scene/collision/surface integration and course checks. Whole M2 still requires Riviera, alternate-loop generation, gates/progress/reset anchors, validation for unsafe geometry and clearance, repeatable generation and recorded lap/reference evidence.

There are no GUI, audio-device, target-controller or output-rights conclusions. Both whole-milestone acceptance and coordinator integration remain outside this independent checkpoint.
