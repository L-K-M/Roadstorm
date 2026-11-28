# Roadstorm M1.8 wall-end geometry review

**Verdict: changes required.** The pinned lab reproduces and closes both reported 0.6 m wall-end failures. A 1.2 m wall made by the same fixture still publishes FRONT at 4.573 m/s severity between two LEFT records while the selected collision normal identifies LEFT on all three ticks.

Reviewer: GPT-6.2 Sol, OpenAI first-party via Codex. Date: 2026-11-28, Europe/Zurich. Candidate: `39ce8d0a3c6a2a6d1a97cac584688dd30aeadfa2`. Scope against `4198a38`: `src/simulation/wall_impact_producer.gd`, `tools/wall_impact_lab/README.md`, and `tools/wall_impact_lab/wall_impact_lab_driver.gd`. The supplied SHA and patch identify the revision. The private build matches the supplied read-only archive under `diff -qr ../source . -x work`. All three scoped files are byte-identical to the coordinator's frozen copy. I read both tracked 4198a38 reviews and the coordinator's frozen sweep summaries.

## Ranked findings

1. **Blocking — The 35 mm cutoff still causes a material wrong-region pulse on the same convex box-wall end.** At `wall_impact_producer.gd:273–299`, an end-plane distance above the cutoff sends the witness directly to normalized point classification, even with a strong, sign-compatible side normal. Reproduce with the default 1.8 × 1.0 × 3.8 m hull, a centered 1.2 m wide, 2 m thick wall with the near plane at world Z = −20 m, initial road velocity (0, 35) m/s, heading 0.9 rad, steer −1, throttle 1. The probe starts at road position (0, 18 − 1.9 × |cos(heading)| − 0.9 × |sin(heading)|) m, using default lab tuning. The fixture directly supports this width via `body_lab_world.gd:53–74`. The only geometry change from the original reproduction is wall width.

   | Tick | Local selected normal (X, Z) | Side/nose inset (mm) | Severity (m/s) | Published |
   | --- | --- | --- | --- | --- |
   | 30 | (1.0000, 0.0000) | 17.692 / 54.283 | 0.057 | LEFT |
   | 31 | (0.9819, 0.1895) | 19.255 / 39.565 | 4.573 | **FRONT** |
   | 32 | (0.8139, 0.5810) | 22.612 / 16.074 | 10.029 | LEFT |
   | 33 | (0.4685, 0.8835) | 7.474 / 13.977 | 9.641 | FRONT |

   Tick 31's local point is (−0.880745, 0.500000, −1.860435) m. Its normalized longitudinal coordinate is 0.979176 versus 0.978606 lateral, so the point rule explains the early FRONT. The next genuine FRONT follows a normal-face change at tick 33. Two more 1.2 m cases disagree: 8 m/s, heading 0.785398, steer −1, throttle 0 at tick 19 (1.032 m/s, 36.883 mm nose inset, LEFT published as FRONT), and 8 m/s, heading 0.3, steer +1, throttle 1 at tick 34 (0.082 m/s, 49.277 mm rear inset, LEFT published as REAR). All are committed, accepted witnesses. The defect is in labeling, with the same static box shape, flat support, pinned backend, and hull as the correction. Add the material sequence as a real regression and validate the face/edge decision across widths before choosing another threshold. The lowest-severity row shows a wider envelope but does not independently drive the verdict.

2. **Low — The physical lab's band predicate is one-sided, and the synthetic margins only partially bracket the rule.** `wall_impact_lab_driver.gd:2004–2010` compares signed insets with 35 mm, whereas `wall_impact_producer.gd:276–279` compares absolute plane distances. A point 50 mm outside either plane satisfies the lab's comparison on that axis and fails the producer's comparison. The measured target rows are inside both planes, so this does not invalidate their assertions. The synthetic 40 mm guard at driver lines 1216–1250 does catch a normal-first implementation and widening that includes that particular point. It tests the end axis with a front-dominant normal over a side-labeled point. The 39.565 mm physical failure has the reverse relationship, so the guard establishes a product rule for its synthetic combination without establishing a physical ceiling for side-dominant wall-end witnesses. The near-diagonal synthetic case at lines 1144–1182 catches removal of the margin using a roughly 0.0005 advantage. It leaves the just-above-0.001 behavior unpinned. Use absolute distances in the physical test's band predicate and add the missing boundary cases when revising the classifier.

## What the passing checks establish

- The exact pinned lab run returned 0, with **15 cases, 1,355 checks and zero failures**. The intentional failure returned 3. At 20 m/s, heading 0.785398, steer −1 and throttle 0 or 1, the current rule labels ticks 27 and 30 LEFT at 5.381 and 6.401 m/s, with nose insets 28.223 and 28.796 mm. Ticks 28 and 31 genuinely transition to FRONT at 9.179 and 11.122 m/s with front-dominant normals. Reapplying only the old 25 mm threshold to those captured rows routes both to the FRONT point rule. The driver asserts the selected normal, point-rule disagreement, exact edge tick and immediate subsequent FRONT. The four mirrored synthetic cases exercise the sign/quadrant logic. The old-band comparison here is classification replay over real rows, with no edited producer run.
- `motor_body_adapter.gd:483–506,633–669,869–941` collects the point, normal and sweep basis at the same committed contact, then uses the same planar-opposition index to select the response normal and associated witness. It installs the final yaw afterward. `wall_impact_producer.gd:145–209` checks pre/post response data and transforms the selected point and road-plane normal in that collision frame. Its normal override requires a compatible dominant sign and a component difference above 0.001. A diagonal or incompatible sign within the band uses the normalized point rule, which chooses the longitudinal region on equal ratios.
- `drive_lab.gd:873–937,1119–1128,1607–1622` publishes through that same producer only from the accepted canonical result and witness fingerprint, after canonical commit. Retry coalescing and gearbox-failure withholding stay in the DriveLab path. The pinned DriveLab validator returned 0 with **16 cases, 5,312 checks**, including **233 passing wall integration checks** and its authored frontal impact at 17.893 m/s. The validator emitted an ObjectDB exit warning reporting four leaked instances. The box-end probe reaches the actual adapter and producer directly, so the specific 1.2 m reproduction was exercised at that boundary.
- Across the sweep I saw no evidence that the widening newly overrode a genuine measured face incorrectly. Every added override agreed with the sign-compatible dominant response normal, including front-right and rear-right mirrors. This metric establishes response-normal agreement. It cannot establish a separate exact feature ID for each solver contact. The remaining material mismatches come from applying the point fallback too early. The absolute band also makes other hull scales a separate calibration question.

## Commands and evidence limits

I used the pinned Godot `4.7.2.stable.official.ed1daf0bf` macOS editor with the project's Jolt backend at fixed 60 Hz. All runs used private HOME, TMPDIR, XDG_CACHE_HOME, XDG_CONFIG_HOME and XDG_DATA_HOME below `../logs/`, and the shared coordinator Godot lock. From `build/`, with `C="$(cd ../../.. && pwd)"`, `L="$(cd ../logs && pwd)"`, and `PIN="$C/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"`:

```sh
timeout -k 5 240 sh tools/wall_impact_lab/run_wall_impact_lab.sh \
  --project "$PWD" --godot "$PIN" --lock "$C/godot-test.lock" \
  --timeout 60 --outer-timeout 180 --log "$L/validator.log" >"$L/runner.log" 2>&1

S="$L/sweep"
timeout -k 5 180 lockf -k -w -t 170 "$C/godot-test.lock" \
  "$PIN" --headless --path "$S" --import
timeout -k 5 55 lockf -k -w -t 45 "$C/godot-test.lock" \
  "$PIN" --headless --fixed-fps 60 --path "$S" --script res://reviewer_probe/entry.gd
timeout -k 5 120 lockf -k -w -t 100 "$C/godot-test.lock" \
  "$PIN" --headless --fixed-fps 60 --path "$S" --script res://tools/drive_lab/validate_drive_lab.gd
python3 "$L/summarize.py" "$L"/sweep-[0-9]*.log "$L/sweep-fine-0.6.log"
```

The stage uses the candidate files and the previous Opus probe from the completed 4198a38 review, with its entry point directed to `res://reviewer_probe/`. The grid uses 8/20/35 m/s, ten headings from 0 to 1.570796 rad including 0.785398 and 0.9, steer −1/0/+1 and throttle 0/1. Each scenario runs for 40 ticks. Each row below has the completion marker and zero producer refusals or noncommitted steps. Flips count adjacent witness pairs within a scenario where the sign-compatible, unambiguous normal face stays the same while the published region changes.

| Width and variant | Witnesses | Normal disagreements | Flips |
| --- | ---: | ---: | ---: |
| 0.30 m centered | 1,368 | 0 | 0 |
| 0.60 m centered | 1,617 | 0 | 0 |
| 0.60 m, negated headings | 1,617 | 0 | 0 |
| 0.60 m, headings +π | 815 | 0 | 0 |
| 0.60 m, start X +0.4 m | 1,326 | 0 | 0 |
| 1.20 m centered | 2,244 | 3 | 5 |
| 2.40 m centered | 2,882 | 0 | 0 |
| 0.60 m centered, 30 headings 0.60–1.47 rad | 2,379 | 0 | 0 |

The probe variables are `OPUS_WALLW`, `OPUS_HNEG`, `OPUS_HOFF`, `OPUS_X` and `OPUS_FINE`. The fine sweep used the 120-second bound. Raw reproduction: `logs/sweep-1.2_0_0_0.log`, scenario `v35_h0.900_s-1_t1`, ticks 30–33. The coordinator supplied additional flat-wall evidence (3,672 witnesses, zero disagreements) and identifies hosted CI 46106195265 as pending at handoff. I did not query its status. That workflow does not exercise this lab.

The verdict covers the wall-end correction on the measured default hull and flat static box walls. Slopes, tilted or curved walls, mesh colliders, other hull/tolerance combinations at wall ends, and other platforms remain unverified here. Full M1.8/M1, sustained-contact policy, car-car, cosmetic damage, hardware, rights and release approval are outside this review. Candidate source and assets were left intact. No Git mutations, delegation, current-reviewer consultation or publication occurred.
