# Roadstorm M1.8 wall-region correction recheck

**Verdict: PASS for the scoped correction and the measured default-hull witness path.** No blocking findings. Reviewer: GPT-6.2 Sol (`gpt-6.2-sol`), OpenAI first-party, via Codex. Date: 2026-11-28, Europe/Zurich.

Candidate `4198a3891cdd83a652555b4ec73fd3a29f5acc54`. Prior scoped candidate `408d6198766fe040d932d10d94df0d68e2f34bae`. The supplied scoped patch is the path-filtered commit diff for `src/simulation/wall_impact_producer.gd`, `tools/wall_impact_lab/README.md` and `tools/wall_impact_lab/wall_impact_lab_driver.gd`. Read-only Git tree inspection and SHA-1 verification matched all 1,226 tracked blobs in both archives to the candidate. The build and read-only copy also matched under `diff -qr ../source . -x work`.

## Independent pinned Jolt results

- Godot `4.7.2.stable.official.ed1daf0bf` on macOS, headless at fixed 60 fps. Isolated import and validator passed. Runner and validator exited 0 with **14 cases, 1,094 checks, zero failures**. The deliberate failing assertion exited 3 and emitted `pass:false`.
- The 20 m/s, 0.9 rad, unsteered continuing-contact regression produced 33 LEFT labels, including 27 witnesses beyond the old normalized 0.01 band. The 35 m/s, 1.1 rad, steer +1 regression published LEFT at tick 4 with **26.346 m/s** severity and an old normalized difference of −0.010098. The mirrored heading-zero steering probes still produced 29 FRONT witnesses per direction.
- Replayed the previous review's 180-scenario grid using its probe driver and a private entry-point path. The grid varied 3 speeds, 10 headings, 3 steering inputs and 2 throttle inputs for 40 ticks per scenario. There were 3,672 accepted witnesses in 170 scenarios, with zero producer refusals and zero non-committed adapter steps. Every logged field except region matched the prior run row for row.
- The maximum absolute face-plane distances were **15.764 mm lateral and 13.838 mm longitudinal**. All 3,672 points were inside the new 25 mm band on both axes. Every sign-compatible unambiguous normal agreed with the published region. The 188 diagonal witnesses all used the point label. There were no sign-incompatible normals. Among 154 scenarios with a single unambiguous normal face throughout the witness stream, scenarios with region flips went from **19 to 0**. The prior log had 370 witnesses outside the old band and 364 sign-compatible normal disagreements. The new run had zero such disagreements.
- The coordinator's frozen old-producer control reports 33 failed assertions. The three synthetic assertions exercise the wide inset and opposite-sign fallback. The 30 physical assertions comprise 28 individual labels and two aggregate counts. The continuing case had 27 wrong labels, and the high-speed first hit supplied the other one. The rotated-frame assertion is a regression guard and passed on the prior producer, which already inverted the collision basis. I inspected the coordinator control log. My independent old/new comparison uses the earlier broad replay log as its control.

## Witness authority

`motor_body_adapter.gd:483–506,638–664,869–948` associates each normal with its own solver point and sweep-basis pose at the committed substep origin. The same planar opposition rule selects the point, frame and raw response normal. The final yaw basis is installed later at :666–669. The yaw-only basis at :735–748 makes inverse basis the correct world-to-local operation for the normalized road-plane response direction. The adapter samples the post-response vector before taking the committed planar components, so the producer's existing exact component-value check remains consistent with real witnesses.

`wall_impact_producer.gd:153–174,271–302` uses both axis distances, then requires the dominant signed direction to push inward from the point's quadrant. +Z identifies FRONT, −Z REAR, +X LEFT and −X RIGHT in local axes when the point supports the label. A dominant-axis difference at or below 0.001, or an incompatible dominant sign, leaves the normalized point rule in charge. The exact point tie goes to FRONT/REAR. The sweep includes actual diagonal fallback evidence and the lab supplies synthetic opposite-sign evidence. At the rotated fixture's 1.2 rad heading, the local nose-dominant normal becomes world-side-dominant with an incompatible sign for the front-left point. Omitting the inverse would fall back to the point label LEFT instead of the required FRONT. The physical LEFT probes independently discriminate a world +Z direction from the side-dominant local direction.

## Ranked actionable findings

1. **Nonblocking calibration limit.** `wall_impact_producer.gd:65–78,273–281` uses an absolute 25 mm band for every config. `motor_body_adapter.gd:119–120,203–212,251–263,565–567` allows other hull dimensions and orientation tolerances up to 100 mm subject to hull size, and uses that tolerance to shrink the orientation query hull. A larger allowance can change the physical point envelope. On a small hull the same 25 mm spans a much larger fraction of a face. A point genuinely on a face within 25 mm of its adjacent edge is eligible for the same normal override, while face centres on the measured hull lie far outside the band. The present calibration and README limit are appropriate for the measured configuration. Before extending physical authority to other configs, measure the two-axis error and face/edge classification with a pinned sweep for those configs, including wall ends or other collider shapes if supported.
2. **Nonblocking test precision.** `wall_impact_lab_driver.gd:1030–1085,1652–1705` exercises an exactly diagonal normal and face centres, while the physical case checks the winning labels and the old normalized band. It would still pass with substantial corner-band widening. Bracket the new boundary on each axis with an otherwise sign-compatible normal that would change the point label and test normal-axis differences just below and above 0.001. A near-edge, genuine face witness would extend the physical evidence beyond the current corner-heavy sweep. The rotated test comment at :1085–1088 could also spell out that the wrong-frame result comes through sign rejection and point fallback for this fixture.

## Files, commands and limits

Inspected the scoped patch, producer, wall-lab README, runner, validator, failure probe, fixture checks and driver, and the adapter and body-lab paths that generate and consume the witness. Read both tracked `review/implementation/m1-wall-producer-{opus-5-5,gpt-6-2-sol}-408d619.md` reports, the prior Opus sweep and the supplied frozen coordinator run and control evidence. Used read-only `git rev-parse`, `git ls-tree -rz`, path-filtered `git diff` piped into `cmp`, archive comparison and Python blob hashing.

From the private `build/` directory, the suite command was:

```sh
C="$(cd ../../.. && pwd)"
PIN="$C/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
L="$(cd ../logs && pwd)"
env HOME="$L/home" TMPDIR="$L/tmp" XDG_CACHE_HOME="$L/cache" \
    XDG_CONFIG_HOME="$L/config" XDG_DATA_HOME="$L/data" \
    timeout 240 sh tools/wall_impact_lab/run_wall_impact_lab.sh \
    --project "$PWD" --godot "$PIN" --lock "$C/godot-test.lock" \
    --timeout 60 --outer-timeout 180 --log "$L/validator.log" \
    >"$L/runner.log" 2>&1
```

For the replay I copied the candidate project and prior probe into a private scratch tree, changing only the probe entry's resource path. With the same private HOME, TMPDIR and XDG settings, I ran `timeout -k 5 180 lockf -k -w -t 170 "$C/godot-test.lock" "$PIN" --headless --path "$S" --import`, then `timeout -k 5 240 lockf -k -w -t 220 "$C/godot-test.lock" "$PIN" --headless --fixed-fps 60 --path "$S" --script res://reviewer_probe/opus_corner_probe_entry.gd`. Both exited 0 and the probe emitted its completion marker. Logs and the comparison script are in `../logs/`.

Physical evidence is limited to the default 1.8 × 1.0 × 3.8 m hull, 0.02 m orientation tolerance, flat support and straight static box walls under the pinned macOS Jolt build. Other geometries, tolerances and platforms remain unverified. The supplied parent hosted CI run 46102234316 was green. Candidate hosted status was not queried, and the workflow does not run the wall behavior lab. Full M1.8, M1, sustained-contact policy, car-car, rights and release acceptance remain outside the verdict. Candidate source and assets were left intact. Git access was read-only. No delegation, current reviewer consultation or publication occurred.
