# M1.4 ground-support sensing laboratory

Private bounded laboratory for `GroundSupportProbe`, the downward ray sensor
that reports legal floor support for one `CharacterBody3D` rectangular hull.

## Scope

This proves a sensing component, not an attraction or landing controller:

- exactly five downward physics ray queries per call: one central probe plus
  four footprint probes inset from the hull edges;
- the body's collision mask is obeyed, its RID is excluded, and areas are
  ignored;
- a sideways or inverted hull frame is refused atomically before any query:
  the frame's local +Y must keep `dot(local +Y, world +Y) >= min_frame_up_dot`;
- ceilings, overpasses and wall-like or steep normals are never promoted to
  support, and hits above the probe start are rejected;
- a legal road seam can leave the centre unsupported while one uniquely
  largest coherent cluster of footprint probes on nearby legal floor still
  grounds the body; an equal split across two levels remains ungrounded;
- three road-level footprints plus one lower shoulder within ray reach ground
  on the three-hit cluster, including when a deeper shoulder is discarded as
  beyond the support bound (the old all-legal-hits spread rule rejected the
  shallow case);
- a single distant hit is not promoted: a support bound rejects far floors,
  and a spread tolerance rejects uneven footprint heights;
- invalid config, hull, transform or nonfinite input fails atomically with
  zero queries and leaves every input untouched;
- repeated fixed-60 Hz calls reproduce identical per-probe details.

It does not implement ground adhesion, attraction, snap, swept movement,
landing recovery, surfaces or M1.4 acceptance.

## Files

| Path | Role |
| --- | --- |
| `support_lab_entry.gd` | headless `SceneTree` entry point with an internal watchdog |
| `support_lab_driver.gd` | cases, assertions, JSON result lines |
| `support_lab_checks.gd` | assertion collectors and explicit fixtures |
| `support_lab_world.gd` | deterministic static geometry and carrier staging |
| `run_validation.sh` | private staging, bounded import/run, failure proof, mutants |

The component under test is `src/simulation/ground_support_probe.gd`.

## Run

```sh
tools/support_lab/run_validation.sh \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
  --timeout 120 --outer-timeout 300
```

Options: `--project DIR`, `--case ID`, `--mutant NAME`, `--skip-mutants`,
`--legacy-probe FILE`, `--keep-scratch`. The runner stages only
`project.godot`, `src`, `scenes` and `tools/support_lab` into a temporary
directory, imports there, and never touches the live `.godot/` cache. Every
engine invocation is bounded by a wall-clock watchdog (`--timeout`, default
120 s, maximum 180 s) and Godot's `--quit-after 6000` iteration guard; the
wrapper enforces `--outer-timeout` (default 300 s), and the entry point quits
by itself after 100 s even if an await stalls or a script load fails.
`--legacy-probe FILE` runs only the historical-source negative control: the
supplied older probe must fail `coherent_cluster_three_plus_one`.

Default phases:

1. full suite: exit 0 with `SLICE_SUMMARY "pass":true`;
2. `intentional_failure`: always fails, proving the harness can fail;
3. broken-behaviour mutants: one literal mutation is applied to the staged
   probe source, its mapped case must then fail. A mutant that passes its case
   fails the runner.

| Mutant | Broken behaviour | Detected by |
| --- | --- | --- |
| `upright_gate` | world-upright frame gate removed | `frame_orientation_gate` |
| `steep` | steep-normal rejection disabled | `too_steep_surface` |
| `footprint` | coherent-cluster minimum size reduced to one hit | `near_edge_partial_support` |
| `distance` | support-distance bound removed | `distant_support` |
| `probe_count` | four probes instead of five | `exactly_five_queries` |
| `spread` | coherent-cluster spread bound replaced by the absolute ray cap | `uneven_support_spread` |
| `mask` | body mask replaced by all layers | `mask_exclusion` |
| `direction` | rays cast upward | `ceiling_overpass_rejection` |

These scripts are not discovered by `tools/ci` (CI discovers `tests/` and
`tools/smoke/` only).

## Coordinate convention

- World metres, world +Y up. Hull local frame follows the project car
  convention: local +X right, local +Y up, local +Z rearward (nose is -Z).
- The supplied transform describes the hull box frame: the hull is centred on
  the transform origin and spans `hull_size_m / 2` about it.
- Probe starts are local `(offset_x, 0, offset_z)` on the hull mid-plane; the
  cast direction is `-basis.y`.
- `support_distance_m` is measured along local down from the transform origin.
  `support_height_m` is the world-vertical drop from the origin to the chosen
  support point.

## Provisional thresholds

Labouratory defaults, not frozen handling coefficients:

| Value | Default | Meaning |
| --- | --- | --- |
| `ray_length_m` | 1.0 m | hard ray length, absolute cap 2.0 m |
| `max_support_distance_m` | 0.75 m | closest legal support; beyond this a hit is recorded but cannot support |
| `footprint_inset_fraction` | 0.15 | footprint inset as a fraction of each half-extent |
| `min_up_dot` | 0.5 | legal-normal alignment against world +Y, about 30 degrees from horizontal |
| `min_frame_up_dot` | 0.5 | minimum hull-frame local +Y alignment with world +Y; refuses sideways/inverted poses |
| `required_footprint_hits` | 2 | minimum size of the uniquely largest footprint cluster when the centre misses |
| `footprint_support_spread_max_m` | 0.25 m | maximum spread within one coherent footprint cluster |

M1.4 owns final adhesion, landing and attraction values.

## Centre-miss coherence rule

When the central probe finds no legal support, `grounded` requires exactly
one uniquely largest coherent cluster of legal footprint support distances.
Distances are sorted ascending and a cluster is a run whose spread
(`max - min`) is at most `footprint_support_spread_max_m`; only clusters that
cannot be extended by a neighbouring distance are candidates. The largest
candidate must contain at least `required_footprint_hits` hits. Equal-largest
candidates, such as a 2+2 split across two levels, are ambiguous and leave
the body ungrounded. A legal central hit bypasses clustering and grounds on
its own.

## Limitations

- Point rays have no skin or radius: a seam can fall between the five sample
  points and thin geometry can be missed.
- Sensing only. No sweep, depenetration, attraction, snap or recovery, and no
  claim that the motor should adhere.
- Physics areas are ignored, so area-tagged surfaces are invisible here.
- Bodies that pass the mask, including other cars, read as support.
- Only rectangular box hulls with the centred convention above are supported,
  and the body scale must be one.
- Rays use front-face, outside-origin Jolt queries; edge-on or interior
  geometry may not register.
- Any legal-normal surface below the probe origin counts as support; route or
  height context is required to distinguish a low ceiling from a road.
- The upright gate bounds frame attitude only. It rejects sideways and
  inverted poses with zero queries; it does not prove an admitted upright
  cast reaches ground rather than another surface facing the ray.
- Query determinism is demonstrated on the pinned Godot 4.7.2 Jolt build for
  fixed world state; no cross-platform guarantee is claimed.
