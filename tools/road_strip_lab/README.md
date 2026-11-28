# Provisional OPEN driving-strip laboratory

`RoadStripBaker` consumes an accepted OPEN `RoadTransportFrame.FrameTable` and
builds chunked `ArrayMesh` driving surfaces with matching one-sided
`ConcavePolygonShape3D` collision. Each row has left/right vertices and UVs
`(0 or 1, station_m)`. Segment metadata owns `[s_i, s_{i+1})` and carries the
preceding frame's section and surface IDs. Adjacent chunks copy the shared row
bit-exactly. Clockwise front faces and explicit up normals make the road top
visible to a back-face-culling material and support a vehicle from above.

The validator uses three synthetic OPEN frames and chunk size one. It checks
two real mesh/shape chunks, 4 vertices and 2 triangles per chunk, vertex and
UV seams, ordered metadata, structured refusals, and two downward Jolt rays
with `hit_back_faces=false` against the actual one-sided collision shapes. The
headless pinned-Godot 4.7.2 frozen candidate passed **3 cases/108 checks**;
`failure_probe.gd` made one deliberate assertion fail and exited **3**.

Run from a private plain source archive with the publisher-pinned Godot editor:

```sh
godot --headless --path <private-project> --import --quit-after 1
godot --headless --fixed-fps 60 --path <private-project> \
  --script res://tools/road_strip_lab/validate_road_strip_lab.gd
godot --headless --fixed-fps 60 --path <private-project> --quit-after 1 \
  --script res://tools/road_strip_lab/failure_probe.gd
```

Serialize engine calls on `work/agents/coordinator/godot-test.lock`, give each
call a 120-second watchdog, and inspect `SCRIPT ERROR`/`ERROR` and the
`ROAD_STRIP_LAB_SUMMARY` line. Godot can exit zero after a script error.

Separate private pipeline probes used the committed road-source, arc and frame
components with the OPEN straight, banked bend and rapid-grade fixtures; all
three baked with chunk size two and matching mesh/metadata vertex counts. A
before/after physical probe established the source correction: the old one
segment metadata said 3 vertices for a 4-vertex mesh, and its road-top
downward ray missed; the corrected source reports 4 and the one-sided ray
hits. Those ignored probes are evidence, not part of this tracked lab.

This is an OPEN driving strip only. It has no shoulders, barriers, material
assignment, thickness, closed-loop seam, scene integration, course clearance
or car drivability test, and does not close M2.1.
