# Road-strip seam support laboratory

Diagnostic baseline for the M2.1 road-strip seam support gap. It is not M2.1
acceptance and does not claim a car falls through.

Uses the committed banked-bend fixture
`tools/road_frame_lab/fixtures/road_frame_open_banked_bend.json` at 2 m spacing,
built through `RoadSourceDocument -> RoadArcSampler -> RoadTransportFrame ->
RoadStripBaker`. For each bake (`max_segments_per_chunk` 1 and 1024) it
instantiates the real `ConcavePolygonShape3D` chunks under separate `Node3D`
containers, adds one `CharacterBody3D` with the default
`GroundSupportProbe.Config` and matching `BoxShape3D`, and calls the real
`GroundSupportProbe.probe()` at exact interior frame-row poses across lateral
fractions plus a small forward-offset control. All queries are real Jolt rays.

Run from a private plain source archive with the publisher-pinned Godot editor:

```sh
godot --headless --path <private-project> --import --quit-after 1
godot --headless --fixed-fps 60 --path <private-project> \
  --script res://tools/road_strip_seam_lab/validate_road_strip_seam_lab.gd
godot --headless --fixed-fps 60 --path <private-project> --quit-after 1 \
  --script res://tools/road_strip_seam_lab/failure_probe.gd
```

Limits: diagnostic baseline only; no car dynamics, no drivability claim, no
scene integration, no closed-loop seam. A measured center-miss gap is reported
as a baseline, not as "seam safe".
