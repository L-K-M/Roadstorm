class_name HandlingLabData
extends RefCounted
## Authored parameters for the M1.2 static graybox handling laboratory.
##
## Source hierarchy for these numbers:
##   * fixture-derived dimensions come from fixtures/handling/*.json and
##     docs/BENCHMARKS.md "Handling fixtures";
##   * lab-only choices (bank profile, jump ramp, wall height, shoulder and
##     sand widths, recovery pad size, sampling resolution) are preliminary
##     M1 authoring values, marked "authored_preliminary";
##   * nothing here is a measured handling result, and fixture-declared
##     unknowns remain unknown (see PRELIMINARY_NOTICE).
##
## Coordinate convention: +Y up, -Z forward, +X right. Bays are independent
## test spaces placed on a coarse world grid; each bay builds in world
## coordinates with its authored origin and yaw.

const SCHEMA_VERSION := "roadstorm.handling_lab.v1"
const LAB_ID := "roadstorm.laboratory.handling_lab"
const COORDINATE_FRAME := {"forward": "-Z", "up": "+Y", "right": "+X"}
const UNITS := {"length": "m", "angle": "deg", "speed": "m/s"}

const PRELIMINARY_NOTICE := (
    "All geometry parameters in this laboratory are preliminary M1.2 graybox "
    + "authoring values, not validated handling measurements. Fixture-declared "
    + "unknowns stay unknown. No car integration, gameplay or M1.2 acceptance "
    + "result is claimed."
)
const FIXTURE_UNKNOWN_NOTICE := (
    "fixtures/handling/grounding.json declares jump takeoff grade, airborne "
    + "gap and required landing run null; fixtures/handling/contact.json "
    + "declares barrier height null until M2. This lab authors explicit "
    + "preliminary values for those features and labels them preliminary."
)

## Sampling resolution along a centerline, metres. Authored, not measured.
const SAMPLE_STEP_M := 1.0
## Vertical extrusion thickness shared by visible surfaces and their colliders.
const ROAD_THICKNESS_M := 1.0
## Lateral clearance required on each side of the largest provisional car.
const CLEARANCE_MARGIN_M := 1.0
## Largest provisional car envelope from docs/TECHNICAL_DESIGN.md:111.
const CAR_ENVELOPE_M := {"length": 4.8, "width": 2.2, "height": 1.8}
## 2.2 m car + 1.0 m margin each side, rounded to a documented authored value.
const REQUIRED_ROAD_WIDTH_M := 4.2


static func surfaces() -> Array[Dictionary]:
	## Stable semantic surface IDs. These are metadata/collision-body tags,
	## never Jolt triangle face indices.
	return [
		{
			"surface_id": "asphalt",
			"description": "Dry asphalt baseline surface.",
			"color": Color(0.16, 0.17, 0.19),
			"roughness": 0.95,
		},
		{
			"surface_id": "gravel",
			"description": "Gravel sector surface; modifiers belong to M1 car resources.",
			"color": Color(0.45, 0.38, 0.28),
			"roughness": 1.0,
		},
		{
			"surface_id": "shoulder",
			"description": "Dirt shoulder strip beside the road.",
			"color": Color(0.36, 0.29, 0.20),
			"roughness": 1.0,
		},
		{
			"surface_id": "sand",
			"description": "Sand strip beyond the shoulder.",
			"color": Color(0.75, 0.68, 0.45),
			"roughness": 1.0,
		},
		{
			"surface_id": "recovery",
			"description": "Designated flat recovery pad surface.",
			"color": Color(0.20, 0.45, 0.30),
			"roughness": 0.9,
		},
		{
			"surface_id": "barrier",
			"description": "Solid test wall / barrier surface.",
			"color": Color(0.70, 0.15, 0.12),
			"roughness": 0.8,
		},
	]


# --- Segment authors ------------------------------------------------------
# Every segment dictionary is plain authored data. Common keys:
#   section_id, width_m, surface_id, feature, role, provenance, status.
# `role` is "road" for carriageway that must clear the car envelope and
# "strip" for shoulder/sand runoff that does not.


static func straight(
	section_id: String,
	length_m: float,
	width_m: float = 12.0,
	surface_id: String = "asphalt",
	grade_start_percent: float = 0.0,
	grade_end_percent: float = 0.0,
	bank_start_deg: float = 0.0,
	bank_end_deg: float = 0.0,
	feature: String = "",
	lateral_offset_m: float = 0.0,
	role: String = "road",
	provenance: String = "authored_preliminary",
	restart_at_origin: bool = false
) -> Dictionary:
	return {
		"type": "straight",
		"section_id": section_id,
		"length_m": length_m,
		"width_m": width_m,
		"surface_id": surface_id,
		"grade_start_percent": grade_start_percent,
		"grade_end_percent": grade_end_percent,
		"bank_start_deg": bank_start_deg,
		"bank_end_deg": bank_end_deg,
		"feature": feature,
		"lateral_offset_m": lateral_offset_m,
		"role": role,
		"provenance": provenance,
		"status": "preliminary_graybox",
		"restart_at_origin": restart_at_origin,
	}


static func arc(
	section_id: String,
	radius_m: float,
	angle_deg: float,
	direction: String,
	width_m: float = 12.0,
	surface_id: String = "asphalt",
	bank_start_deg: float = 0.0,
	bank_end_deg: float = 0.0,
	feature: String = "",
	role: String = "road",
	provenance: String = "authored_preliminary"
) -> Dictionary:
	return {
		"type": "arc",
		"section_id": section_id,
		"radius_m": radius_m,
		"angle_deg": angle_deg,
		"direction": direction,
		"width_m": width_m,
		"surface_id": surface_id,
		"bank_start_deg": bank_start_deg,
		"bank_end_deg": bank_end_deg,
		"feature": feature,
		"lateral_offset_m": 0.0,
		"role": role,
		"provenance": provenance,
		"status": "preliminary_graybox",
	}


static func gap(
	section_id: String,
	gap_m: float,
	drop_m: float,
	landing_run_m: float
) -> Dictionary:
	return {
		"type": "gap",
		"section_id": section_id,
		"gap_m": gap_m,
		"drop_m": drop_m,
		"landing_run_m": landing_run_m,
		"feature": "jump_gap",
		"role": "gap",
		"provenance": "authored_preliminary",
		"status": "preliminary_graybox",
	}


static func slab(
	section_id: String,
	width_m: float,
	length_m: float,
	surface_id: String = "recovery",
	feature: String = "recovery_pad"
) -> Dictionary:
	return {
		"type": "slab",
		"section_id": section_id,
		"width_m": width_m,
		"length_m": length_m,
		"surface_id": surface_id,
		"feature": feature,
		"role": "road",
		"provenance": "authored_preliminary",
		"status": "preliminary_graybox",
	}
# --- Bays -----------------------------------------------------------------
# Bay origins place independent test spaces on a coarse world grid so every
# section stays clear of its neighbours. All yaws are 0 in this revision:
# local forward -Z, local right +X.
#
# Banking sign: positive degrees tilt the surface up vector toward local +X,
# so the right edge sits lower and the left edge higher; negative is opposite.
#
# Wall angle convention (lab-local): `angle_deg` rotates the wall's long axis
# around the road up vector away from the road-right direction. 0 degrees is
# therefore a frontal wall across the road; 45 degrees is an oblique wall.
# The fixture JSON uses its own barrier angle field; this lab does not copy
# that convention.


static func bays() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	out.append({
		"bay_id": "straight",
		"title": "500 m asphalt straight",
		"origin": Vector3(-360.0, 0.0, 60.0),
		"yaw_deg": 0.0,
		"fixture_refs": ["fixtures/handling/straight.json"],
		"segments": [
			straight(
				"straight.main", 500.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0,
				"acceleration_braking_top_speed_reverse", 0.0, "road",
				"fixture:handling/straight"
			),
		],
		"walls": [],
	})

	out.append({
		"bay_id": "contact",
		"title": "500 m straight with frontal and oblique walls",
		"origin": Vector3(-200.0, 0.0, 60.0),
		"yaw_deg": 0.0,
		"fixture_refs": [
			"fixtures/handling/contact.json",
			"fixtures/handling/straight.json",
		],
		"segments": [
			straight(
				"contact.approach", 500.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "wall_approach", 0.0, "road",
				"fixture:handling/contact"
			),
		],
		"walls": [
			{
				"wall_id": "wall_frontal",
				"s_m": 480.0,
				"lateral_offset_m": 0.0,
				"angle_deg": 0.0,
				"length_m": 12.0,
				"thickness_m": 0.5,
				"height_m": 2.0,
				"surface_id": "barrier",
				"provenance": "authored_preliminary",
				"status": "preliminary_graybox",
				"note": "Fixture leaves height null until M2; 2.0 m is an authored preliminary value above the 1.8 m car envelope.",
			},
			{
				"wall_id": "wall_oblique",
				"s_m": 480.0,
				"lateral_offset_m": -6.0,
				"angle_deg": 45.0,
				"length_m": 12.0,
				"thickness_m": 0.5,
				"height_m": 2.0,
				"surface_id": "barrier",
				"provenance": "authored_preliminary",
				"status": "preliminary_graybox",
				"note": "Right-edge oblique wall; 45 degrees, span and height are authored preliminary values.",
			},
		],
	})

	out.append({
		"bay_id": "sweeper",
		"title": "90-degree 120 m sweeper with 50 m approach and exit",
		"origin": Vector3(0.0, 0.0, 60.0),
		"yaw_deg": 0.0,
		"fixture_refs": ["fixtures/handling/sweeper.json"],
		"segments": [
			straight(
				"sweeper.approach", 50.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "sweeper_approach", 0.0, "road",
				"fixture:handling/sweeper"
			),
			arc(
				"sweeper.arc", 120.0, 90.0, "left", 12.0, "asphalt",
				0.0, 0.0, "sweeper_corner", "road",
				"fixture:handling/sweeper"
			),
			straight(
				"sweeper.exit", 50.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "sweeper_exit", 0.0, "road",
				"fixture:handling/sweeper"
			),
		],
		"walls": [],
	})

	out.append({
		"bay_id": "hairpin",
		"title": "180-degree 30 m hairpin",
		"origin": Vector3(240.0, 0.0, 60.0),
		"yaw_deg": 0.0,
		"fixture_refs": ["fixtures/handling/hairpin.json"],
		"segments": [
			straight(
				"hairpin.approach", 30.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "hairpin_approach", 0.0, "road",
				"fixture:handling/hairpin"
			),
			arc(
				"hairpin.arc", 30.0, 180.0, "left", 12.0, "asphalt",
				0.0, 0.0, "hairpin_corner", "road",
				"fixture:handling/hairpin"
			),
			straight(
				"hairpin.exit", 30.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "hairpin_exit", 0.0, "road",
				"fixture:handling/hairpin"
			),
		],
		"walls": [],
	})

	out.append({
		"bay_id": "bank",
		"title": "Straight with bank transitions through +12 and -12 degrees",
		"origin": Vector3(420.0, 0.0, 60.0),
		"yaw_deg": 0.0,
		"fixture_refs": [],
		"segments": [
			straight(
				"bank.level", 30.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "bank_level", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"bank.up", 30.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 12.0, "bank_up", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"bank.hold_plus", 30.0, 12.0, "asphalt",
				0.0, 0.0, 12.0, 12.0, "bank_hold_plus", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"bank.cross", 40.0, 12.0, "asphalt",
				0.0, 0.0, 12.0, -12.0, "bank_cross", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"bank.hold_minus", 30.0, 12.0, "asphalt",
				0.0, 0.0, -12.0, -12.0, "bank_hold_minus", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"bank.return", 30.0, 12.0, "asphalt",
				0.0, 0.0, -12.0, 0.0, "bank_return", 0.0, "road",
				"authored_preliminary"
			),
		],
		"walls": [],
	})

	out.append({
		"bay_id": "grounding",
		"title": "12 percent climb, crest, descent and compression",
		"origin": Vector3(-300.0, 0.0, 260.0),
		"yaw_deg": 0.0,
		"fixture_refs": ["fixtures/handling/grounding.json"],
		"segments": [
			straight(
				"grounding.climb", 60.0, 12.0, "asphalt",
				12.0, 12.0, 0.0, 0.0, "climb", 0.0, "road",
				"fixture:handling/grounding"
			),
			straight(
				"grounding.crest", 24.0, 12.0, "asphalt",
				12.0, -12.0, 0.0, 0.0, "crest", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"grounding.descent", 60.0, 12.0, "asphalt",
				-12.0, -12.0, 0.0, 0.0, "descent", 0.0, "road",
				"fixture:handling/grounding"
			),
			straight(
				"grounding.compression", 24.0, 12.0, "asphalt",
				-12.0, 12.0, 0.0, 0.0, "compression", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"grounding.runout", 40.0, 12.0, "asphalt",
				12.0, 0.0, 0.0, 0.0, "runout", 0.0, "road",
				"authored_preliminary"
			),
		],
		"walls": [],
	})

	out.append({
		"bay_id": "jump",
		"title": "Short preliminary ramp jump with gap and landing pad",
		"origin": Vector3(-200.0, 0.0, 260.0),
		"yaw_deg": 0.0,
		"fixture_refs": ["fixtures/handling/grounding.json"],
		"segments": [
			straight(
				"jump.approach", 20.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "jump_approach", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"jump.ramp", 15.0, 12.0, "asphalt",
				0.0, 8.0, 0.0, 0.0, "jump_takeoff", 0.0, "road",
				"authored_preliminary"
			),
			gap("jump.gap", 5.0, 1.0, 40.0),
			straight(
				"jump.landing", 40.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "jump_landing", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"jump.runoff", 30.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "jump_runoff", 0.0, "road",
				"authored_preliminary"
			),
		],
		"walls": [],
	})

	out.append({
		"bay_id": "gravel",
		"title": "Sweeper with 80 m gravel sector",
		"origin": Vector3(700.0, 0.0, 60.0),
		"yaw_deg": 0.0,
		"fixture_refs": ["fixtures/handling/gravel.json"],
		"segments": [
			straight(
				"gravel.approach", 50.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "gravel_approach", 0.0, "road",
				"fixture:handling/gravel"
			),
			arc(
				"gravel.entry_arc", 120.0, 14.323945, "left", 12.0, "asphalt",
				0.0, 0.0, "gravel_entry", "road",
				"fixture:handling/gravel"
			),
			arc(
				"gravel.sector", 120.0, 38.197186, "left", 12.0, "gravel",
				0.0, 0.0, "gravel_sector", "road",
				"fixture:handling/gravel"
			),
			arc(
				"gravel.exit_arc", 120.0, 37.478869, "left", 12.0, "asphalt",
				0.0, 0.0, "gravel_exit", "road",
				"fixture:handling/gravel"
			),
			straight(
				"gravel.exit", 50.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "gravel_runout", 0.0, "road",
				"fixture:handling/gravel"
			),
		],
		"walls": [],
	})

	out.append({
		"bay_id": "shoulder",
		"title": "Road with dirt shoulders and sand strips",
		"origin": Vector3(0.0, 0.0, 260.0),
		"yaw_deg": 0.0,
		"fixture_refs": [],
		"segments": [
			straight(
				"shoulder.road", 120.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "shoulder_road", 0.0, "road",
				"authored_preliminary"
			),
			straight(
				"shoulder.right", 120.0, 3.0, "shoulder",
				0.0, 0.0, 0.0, 0.0, "right_shoulder", 7.5, "strip",
				"authored_preliminary", true
			),
			straight(
				"shoulder.left", 120.0, 3.0, "shoulder",
				0.0, 0.0, 0.0, 0.0, "left_shoulder", -7.5, "strip",
				"authored_preliminary", true
			),
			straight(
				"shoulder.sand_right", 120.0, 4.0, "sand",
				0.0, 0.0, 0.0, 0.0, "right_sand", 11.0, "strip",
				"authored_preliminary", true
			),
			straight(
				"shoulder.sand_left", 120.0, 4.0, "sand",
				0.0, 0.0, 0.0, 0.0, "left_sand", -11.0, "strip",
				"authored_preliminary", true
			),
		],
		"walls": [],
	})

	out.append({
		"bay_id": "recovery",
		"title": "Designated flat recovery pad",
		"origin": Vector3(240.0, 0.0, 260.0),
		"yaw_deg": 0.0,
		"fixture_refs": [],
		"segments": [
			slab("recovery.pad", 24.0, 24.0, "recovery", "recovery_pad"),
		],
		"walls": [],
	})

	return out


static func unknowns() -> Array[Dictionary]:
	return [
		{
			"path": "features.jump.takeoff_grade_percent",
			"reason": "Fixture declares null; this lab authors a preliminary 8 percent ramp.",
			"blocking": true,
			"until": "M1",
		},
		{
			"path": "features.jump.airborne_gap_m",
			"reason": "Fixture declares null; this lab authors a preliminary 5 m gap.",
			"blocking": true,
			"until": "M1",
		},
		{
			"path": "features.jump.required_landing_run_m",
			"reason": "Depends on entry speed and ramp geometry; fixture declares null. The 40 m authored landing run is preliminary.",
			"blocking": true,
			"until": "M1",
		},
		{
			"path": "contact.walls.height_m",
			"reason": "Fixture declares null until M2 barrier content; 2.0 m is an authored preliminary value.",
			"blocking": false,
			"until": "M2",
		},
		{
			"path": "surfaces.handling_modifiers",
			"reason": "Per-car surface grip/drag modifiers belong to M1 handling resources and are not authored here.",
			"blocking": true,
			"until": "M1",
		},
		{
			"path": "cars.handling_revision",
			"reason": "No car body or handling resource is integrated in this static laboratory.",
			"blocking": true,
			"until": "M1",
		},
		{
			"path": "fixtures.esses_and_draft",
			"reason": "Esses and draft fixtures are outside this M1.2 slice and are not built here.",
			"blocking": false,
			"until": "M1.7",
		},
	]
