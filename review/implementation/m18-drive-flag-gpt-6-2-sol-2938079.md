# Roadstorm accepted wall-contact flag review

**Verdict — PASS.** No actionable findings in the scoped repair.

Independent first-party reviewer — OpenAI GPT-6.2 Sol, 2026-11-28 (CET). Candidate `2938079`, scoped base `09573bf`, using the supplied plain archive and `../scope.patch`. Assessment covers `src/laboratory/drive_lab.gd` and `tools/drive_lab/drive_lab_driver.gd` only. The two files matched the read-only source copy byte for byte.

## Code review

- `src/laboratory/drive_lab.gd:1111` through the publication call at line 1128 captures the accepted result after the adapter's physical commit and after the mirrored canonical pair and tick are committed. The flag is copied by value at line 962, encoded as a Boolean at line 983, and identified in the refusal diagnostic at lines 1011–1012. The acceptance path returns early on gearbox failure before capturing or publishing.
- `src/laboratory/drive_lab.gd:885` checks the fingerprint before the missing-witness branch, ID lookup/allocation, producer and ledger calls, and publication/coalescing updates. Flipping either direction changes the fingerprint. Each mismatch returns false and records one refusal with the specific diagnostic. The ID map, ledger, last event, missed-witness/publication/coalescing totals, canonical state and body pose are preserved.
- `tools/drive_lab/drive_lab_driver.gd:3852` exercises the real-hit retry on the accepted object. The loop at lines 3858–3920 checks the refusal, the field-specific diagnostic and state/ledger invariants. Lines 4103–4159 save and restore the actual Boolean and the committed velocity vector by value. The canonical CarState is a separate copy from the adapter result, so the velocity mutation targets the witness input. Every iteration restores before the next, and the final unmodified retry must coalesce. The committed-velocity branch is now invoked and must report its own mismatch.
- `tools/drive_lab/drive_lab_driver.gd:4016` exercises a real committed clear tick, verifies both witnesses and the contact flag are absent, then flips only the flag. It requires a fingerprint refusal, no fabricated missed-witness increment, no publication or coalesce, an empty ledger with unchanged digest, and unchanged canonical car state and body pose. Restoring the flag leaves that tick unpublishable without another refusal or missed-witness increment.
- **Low, optional, outside this repair** — `src/laboratory/drive_lab.gd:917` still passes the live adapter config to the producer. The producer validates it and uses hull size for contact classification. Pinning or hardening that input is a separate retry-contract decision. Sustained-contact policy and full M1.8 acceptance are outside this review.

## Independent execution

From `sol/build`, read the scoped patch and source with `cat`, `rg`, `nl` and `sed`. Used `cmp` against `../source` and `shasum -a 256` on both reviewed files. Read the adapter commit and gearbox copy paths to verify ordering and aliasing.

Ran the following with the private environment shown, with no engine cache shared with the candidate:

```sh
review_stage=$(mktemp -d "$PWD/.sol-drive-review.XXXXXX")
mkdir "$review_stage"/{tmp,home,cache,config,data,state,runtime}
chmod 700 "$review_stage/runtime"
coord=$(cd ../../.. && pwd)
env HOME="$review_stage/home" TMPDIR="$review_stage/tmp" \
    TMP="$review_stage/tmp" TEMP="$review_stage/tmp" \
    XDG_CACHE_HOME="$review_stage/cache" XDG_CONFIG_HOME="$review_stage/config" \
    XDG_DATA_HOME="$review_stage/data" XDG_STATE_HOME="$review_stage/state" \
    XDG_RUNTIME_DIR="$review_stage/runtime" \
    timeout 580 lockf -k -w -t 120 "$coord/godot-test.lock" \
    tools/drive_lab/run_validation.sh --project "$PWD" \
    --godot "$coord/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot" \
    --timeout 120 --keep-scratch > ../logs/sol-pinned-drive-run.log 2>&1
```

Runner exited 0. Pinned Godot `4.7.2.stable.official.ed1daf0bf` imported successfully. The validator reported Jolt Physics, 16 passing cases, and 5,312 checks with zero failures. The wall integration case passed 233/233, with a physical front hit at committed tick 171 and severity 17.8935 m/s. The bad-config fixture passed 99/99. The deliberate probe reported one failed assertion and exited 3 as expected. Both the validator and bad-config fixture logged a four-instance ObjectDB leak warning on exit. The warning was outside the scoped flag review.

## Regression discrimination and limits

I inspected the coordinator's supplied old-source control at `../../../drive-wall-flag-frozen-6908e5f/old-control/run.log`. That control reported 11 failed assertions when only DriveLab was reverted. The direct failures show the hit flag mutation coalesced and the clear flag mutation incremented missed-witness telemetry. The later status/velocity no-coalesce and final restore-count failures follow from the earlier extra coalesce because those checks compare against the original loop baseline. They do not establish separate defects in the old status or committed-velocity fingerprint logic. The independent passing run and the per-field diagnostic checks establish the corrected path's tested behavior.

The old-source control was supplied evidence. My execution covered the exact candidate's scoped headless suite on one authored head-on wall hit and one clear tick. It makes no claim about sustained contact, other impact geometries, or the full milestone.
