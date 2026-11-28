extends SceneTree
## Headless speed-HUD validation entry point (PLAN.md M1.5 slice).
##
## Run from an isolated project copy after importing resources:
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/hud_lab/validate_speed_hud.gd
##
## Exercises the presentation-only `SpeedHud` component: scene/script wiring,
## 960x540 layout at 100% and 150% HUD scale, zero/forward/reverse label text,
## committed gear indication (`R` and `1`..`8`) with its independent REVERSE
## travel text, km/h and mph conversion, all five drift phases plus qualifying
## gating, invalid/out-of-domain gear atomicity, instance independence, no node
## churn and rejection of reward-style wording.
##
## `--expect-failure` deliberately records a failure so the nonzero exit path
## is observable. The bounded wrapper tools/hud_lab/run_validation.sh runs the
## pass case and this proof.
##
## Scope: structural/behavioural headless checks only. No rendering, visual
## readability, split-screen performance, audio, controller, integrated-race or
## M1.5/M1 acceptance claim.

const HUD_SCRIPT_PATH := "res://src/presentation/speed_hud.gd"
const HUD_SCENE_PATH := "res://scenes/ui/speed_hud.tscn"
const HudScript := preload("res://src/presentation/speed_hud.gd")
const HudScene := preload("res://scenes/ui/speed_hud.tscn")

const EXPECTED_MAJOR := 4
const EXPECTED_MINOR := 7
const EXPECTED_PATCH := 2
const EXPECTED_STATUS := "stable"
const EXPECTED_BUILD := "official"
const EXPECTED_COMMIT_PREFIX := "ed1daf0bf"

## Provisional authored defaults mirrored here as an independent oracle. They
## are not validated presentation constants and may change during tuning.
const BASE_CONTENT_SIZE := Vector2(360.0, 172.0)
const BASE_SPEED_FONT := 40.0
const BASE_UNIT_FONT := 20.0
const BASE_GEAR_FONT := 32.0
const BASE_REVERSE_FONT := 22.0
const BASE_DRIFT_FONT := 22.0
const BASE_QUALIFYING_FONT := 20.0
const BASE_FONTS := [
	BASE_SPEED_FONT,
	BASE_UNIT_FONT,
	BASE_GEAR_FONT,
	BASE_REVERSE_FONT,
	BASE_DRIFT_FONT,
	BASE_QUALIFYING_FONT,
]
const LABEL_NAMES := ["SpeedLabel", "UnitLabel", "GearLabel", "ReverseLabel", "DriftLabel", "QualifyingLabel"]

## Independent oracle for the mirrored gearbox gear domain:
## `-1` reverse or `1..8` forward (AutomaticGearbox.MAX_FORWARD_GEARS).
const GEAR_REVERSE_INDEX := -1
const GEAR_MAX_FORWARD := 8
const GEAR_TEXT_REVERSE := "R"
const GEAR_TEXT_FORWARD := ["1", "2", "3", "4", "5", "6", "7", "8"]
const GEAR_STRESS_TEXTS := ["1", GEAR_TEXT_REVERSE, "8"]

const UNIT_KMH := 0
const UNIT_MPH := 1
const PHASE_GRIP := 0
const PHASE_ENTRY := 1
const PHASE_SUSTAINED := 2
const PHASE_RECOVERY := 3
const PHASE_AIRBORNE := 4
const PHASE_TEXT := ["GRIP", "DRIFT ENTRY", "SUSTAINED DRIFT", "RECOVERY", "AIRBORNE"]
const PHASE_SHAPES := ["ring", "triangle", "disc", "square", "diamond"]
const PHASE_COLORS: Array[Color] = [
	Color(0.45, 0.48, 0.52, 1.0),
	Color(0.96, 0.62, 0.04, 1.0),
	Color(0.13, 0.83, 0.93, 1.0),
	Color(0.98, 0.57, 0.24, 1.0),
	Color(0.65, 0.55, 0.98, 1.0),
]
const UNIT_LABELS := ["km/h", "mph"]
const REVERSE_TEXT := "REVERSE"
const QUALIFYING_TEXT := "QUALIFYING DRIFT"
const FORBIDDEN_WORDS := ["point", "score", "style", "reward", "bonus"]

const PANEL_SIZE := Vector2(960.0, 540.0)
const VECTOR_TOLERANCE := 0.01
const MAX_STARTUP_FRAMES := 120
const MIN_ESSENTIAL_PX := 20.0
const MIN_SPEED_PX := 32.0

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _finished := false
var _started := false
var _wait_frames := 0
var _parent: Control = null
var _hud: SpeedHud = null
var _second: SpeedHud = null


func _initialize() -> void:
	print("[hud-lab] engine ", Engine.get_version_info()["string"])
	_check_engine()

	if not ResourceLoader.exists(HUD_SCRIPT_PATH):
		_record_failure("resource.script", "missing %s" % HUD_SCRIPT_PATH)
		_finish()
		return
	if not ResourceLoader.exists(HUD_SCENE_PATH):
		_record_failure("resource.scene", "missing %s" % HUD_SCENE_PATH)
		_finish()
		return

	_parent = Control.new()
	_parent.name = "HudLabParent"
	_parent.size = PANEL_SIZE
	root.add_child.call_deferred(_parent)

	var first: SpeedHud = HudScene.instantiate() as SpeedHud
	var second: SpeedHud = HudScene.instantiate() as SpeedHud
	_hud = first
	_second = second
	_hud.name = "HudUnderTest"
	_second.name = "HudSecond"
	_parent.add_child.call_deferred(_hud)
	_parent.add_child.call_deferred(_second)
	process_frame.connect(_on_first_frame)


func _on_first_frame() -> void:
	if _finished or _started:
		return
	if not (_parent.is_inside_tree() and _hud.is_inside_tree() and _second.is_inside_tree()):
		_wait_frames += 1
		if _wait_frames > MAX_STARTUP_FRAMES:
			_record_failure(
				"startup.nodes_in_tree",
				"HUD nodes never entered the scene tree within %d frames" % MAX_STARTUP_FRAMES
			)
			_finish()
		return
	_started = true
	_run_checks()
	_finish()


# --- Check groups ----------------------------------------------------------


func _run_checks() -> void:
	_check_structure()
	_check_layout_at_scale(1.0, "layout_100")
	_check_layout_at_scale(1.5, "layout_150")
	_check_speed_labels()
	_check_gear_indication()
	_check_drift_cues()
	_check_atomicity()
	_check_no_churn()
	_check_instance_independence()

	if _has_user_flag("--expect-failure"):
		_check(
			false,
			"expect_failure.deliberate",
			"--expect-failure requested: proving a failing check exits nonzero"
		)


func _check_structure() -> void:
	_check(_hud is SpeedHud, "structure.root_is_speed_hud", str(_hud))
	_check(_hud.get_script() == HudScript, "structure.script_attached", str(_hud.get_script()))
	var contents := _hud.get_node_or_null("Contents")
	_check(contents != null and contents is Control, "structure.contents", str(contents))
	for label_name in LABEL_NAMES:
		var label := _hud.get_node_or_null("Contents/%s" % label_name)
		_check(label != null and label is Label, "structure.%s" % label_name.to_snake_case(), str(label))
	var marker := _hud.get_marker()
	_check(marker != null and marker is Control, "structure.marker_owned", str(marker))
	_check(marker != null and marker.get_parent() == contents, "structure.marker_under_contents", "")
	_check(is_equal_approx(_hud.get_hud_scale(), 1.0), "structure.default_scale", str(_hud.get_hud_scale()))
	_check(not _hud.has_display(), "structure.initial_no_display", str(_hud.has_display()))

	var speed := _label("SpeedLabel")
	_check(speed != null and speed.text == "0", "structure.initial_speed_text", str(speed.text if speed != null else ""))
	var unit := _label("UnitLabel")
	_check(unit != null and unit.text == UNIT_LABELS[UNIT_KMH], "structure.initial_unit_text", str(unit.text if unit != null else ""))
	var gear := _label("GearLabel")
	_check(
		gear != null and gear.text == "" and not gear.visible,
		"structure.initial_gear_hidden",
		str(gear.text if gear != null else "")
	)
	var reverse := _label("ReverseLabel")
	_check(reverse != null and reverse.text == "" and not reverse.visible, "structure.initial_reverse_hidden", "")
	var drift := _label("DriftLabel")
	_check(drift != null and drift.text == PHASE_TEXT[PHASE_GRIP], "structure.initial_drift_text", str(drift.text if drift != null else ""))
	var qualifying := _label("QualifyingLabel")
	_check(qualifying != null and qualifying.text == "" and not qualifying.visible, "structure.initial_qualifying_hidden", "")


func _check_layout_at_scale(scale: float, prefix: String) -> void:
	_check(_hud.set_hud_scale(scale), prefix + ".set_scale", str(scale))
	_check(is_equal_approx(_hud.get_hud_scale(), scale), prefix + ".stored_scale", str(_hud.get_hud_scale()))

	var contents := _hud.get_node("Contents") as Control
	var expected_size := BASE_CONTENT_SIZE * scale
	_check(
		_vec_close(contents.size, expected_size, VECTOR_TOLERANCE),
		prefix + ".contents_size",
		"%s vs %s" % [contents.size, expected_size]
	)
	_check(
		_rect_within(contents.get_global_rect(), _parent.get_global_rect()),
		prefix + ".contents_within_panel",
		str(contents.get_global_rect())
	)

	for index in LABEL_NAMES.size():
		var label := _hud.get_node("Contents/%s" % LABEL_NAMES[index]) as Label
		var global_rect := label.get_global_rect()
		_check(
			_rect_within(global_rect, _parent.get_global_rect()),
			prefix + ".%s_within_panel" % LABEL_NAMES[index].to_snake_case(),
			str(global_rect)
		)
		var effective_font := int(round(BASE_FONTS[index] * scale))
		_check(
			label.get_theme_font_size("font_size") == effective_font,
			prefix + ".%s_font_size" % LABEL_NAMES[index].to_snake_case(),
			"%d vs %d" % [label.get_theme_font_size("font_size"), effective_font]
		)
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var text_size := font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		)
		_check(
			text_size.x <= label.size.x + 0.5 and text_size.y <= label.size.y + 0.5,
			prefix + ".%s_text_fits" % LABEL_NAMES[index].to_snake_case(),
			"text=%s rect=%s" % [text_size, label.size]
		)
		if LABEL_NAMES[index] == "GearLabel":
			for stress in GEAR_STRESS_TEXTS:
				var stress_size := font.get_string_size(
					stress, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
				)
				_check(
					stress_size.x <= label.size.x + 0.5 and stress_size.y <= label.size.y + 0.5,
					prefix + ".gear_stress_fit_%s" % stress,
					"text=%s rect=%s" % [stress_size, label.size]
				)

	_check(
		_hud.get_node("Contents/SpeedLabel").get_theme_font_size("font_size") >= MIN_SPEED_PX,
		prefix + ".speed_font_minimum",
		str(_hud.get_node("Contents/SpeedLabel").get_theme_font_size("font_size"))
	)
	for index in range(1, LABEL_NAMES.size()):
		_check(
			_hud.get_node("Contents/%s" % LABEL_NAMES[index]).get_theme_font_size("font_size") >= MIN_ESSENTIAL_PX,
			prefix + ".essential_font_minimum_%s" % LABEL_NAMES[index].to_snake_case(),
			str(_hud.get_node("Contents/%s" % LABEL_NAMES[index]).get_theme_font_size("font_size"))
		)

	var marker := _hud.get_marker()
	_check(marker.size.x > 0.0 and marker.size.y > 0.0, prefix + ".marker_sized", str(marker.size))
	_check(
		_rect_within(marker.get_global_rect(), _parent.get_global_rect()),
		prefix + ".marker_within_panel",
		str(marker.get_global_rect())
	)

	_check_no_overlap(prefix)

	_measured["%s_speed_font" % prefix] = _hud.get_node("Contents/SpeedLabel").get_theme_font_size("font_size")
	_measured["%s_gear_font" % prefix] = _hud.get_node("Contents/GearLabel").get_theme_font_size("font_size")
	_measured["%s_contents_size" % prefix] = contents.size


func _check_speed_labels() -> void:
	var cue := _make_cue(PHASE_GRIP)

	_check(_hud.update(_make_state(Vector2.ZERO), cue, UNIT_KMH), "speed.zero_update", "")
	_check_text("SpeedLabel", "0", "speed.zero_text")
	_check_text("UnitLabel", UNIT_LABELS[UNIT_KMH], "speed.zero_unit")
	_check(not _label("ReverseLabel").visible, "speed.zero_reverse_hidden", "")
	_check_text("ReverseLabel", "", "speed.zero_reverse_text")

	_check(_hud.update(_make_state(Vector2(0.0, 20.0)), cue, UNIT_KMH), "speed.forward_update", "")
	_check_text("SpeedLabel", "72", "speed.forward_kmh_text")
	_check(not _label("ReverseLabel").visible, "speed.forward_reverse_hidden", "")

	_check(_hud.update(_make_state(Vector2(0.0, 20.0)), cue, UNIT_MPH), "speed.mph_update", "")
	_check_text("SpeedLabel", "45", "speed.forward_mph_text")
	_check_text("UnitLabel", UNIT_LABELS[UNIT_MPH], "speed.mph_unit")
	_measured["20_m_s_kmh"] = 20.0 * 3.6
	_measured["20_m_s_mph"] = 20.0 * 2.2369362920544

	_check(_hud.update(_make_state(Vector2(0.0, 12.34)), cue, UNIT_KMH), "speed.round_kmh_update", "")
	_check_text("SpeedLabel", "44", "speed.round_kmh_text")
	_check(_hud.update(_make_state(Vector2(0.0, 12.34)), cue, UNIT_MPH), "speed.round_mph_update", "")
	_check_text("SpeedLabel", "28", "speed.round_mph_text")

	_check(_hud.update(_make_state(Vector2(0.0, -10.0)), cue, UNIT_KMH), "speed.reverse_update", "")
	_check_text("SpeedLabel", "36", "speed.reverse_text")
	_check(_label("ReverseLabel").visible, "speed.reverse_visible", "")
	_check_text("ReverseLabel", REVERSE_TEXT, "speed.reverse_label_text")

	# Reverse follows the road-plane forward axis, not world -Y.
	_check(_hud.update(_make_state(Vector2(-20.0, 0.0), PI * 0.5), cue, UNIT_KMH), "speed.headed_reverse_update", "")
	_check_text("SpeedLabel", "72", "speed.headed_reverse_text")
	_check(_label("ReverseLabel").visible, "speed.headed_reverse_visible", "")

	# Lateral motion still contributes to absolute road-plane speed.
	_check(_hud.update(_make_state(Vector2(0.0, -20.0), PI * 0.5), cue, UNIT_KMH), "speed.lateral_update", "")
	_check_text("SpeedLabel", "72", "speed.lateral_text")
	_check(not _label("ReverseLabel").visible, "speed.lateral_no_reverse", "")


func _check_gear_indication() -> void:
	var cue := _make_cue(PHASE_GRIP)

	# Forward gears mirror the committed indication only.
	for gear in range(1, GEAR_MAX_FORWARD + 1):
		var accepted := _hud.update(_make_state(Vector2(0.0, 20.0), 0.0, gear), cue, UNIT_KMH)
		_check(accepted, "gear.forward_%d_update" % gear, str(accepted))
		_check_text("GearLabel", GEAR_TEXT_FORWARD[gear - 1], "gear.forward_%d_text" % gear)

	# Reverse gear may be shown while stationary, with no REVERSE travel cue.
	_check(
		_hud.update(_make_state(Vector2.ZERO, 0.0, GEAR_REVERSE_INDEX), cue, UNIT_KMH),
		"gear.reverse_stationary_update",
		""
	)
	_check_text("GearLabel", GEAR_TEXT_REVERSE, "gear.reverse_stationary_text")
	_check(not _label("ReverseLabel").visible, "gear.reverse_stationary_no_travel_reverse", "")

	# Reverse gear with forward travel still shows R; gear never follows motion.
	_check(
		_hud.update(_make_state(Vector2(0.0, 20.0), 0.0, GEAR_REVERSE_INDEX), cue, UNIT_KMH),
		"gear.reverse_forward_roll_update",
		""
	)
	_check_text("GearLabel", GEAR_TEXT_REVERSE, "gear.reverse_forward_roll_text")
	_check(not _label("ReverseLabel").visible, "gear.reverse_forward_roll_no_travel_reverse", "")

	# Backward rolling in a forward gear keeps that gear and adds REVERSE.
	_check(
		_hud.update(_make_state(Vector2(0.0, -10.0), 0.0, 1), cue, UNIT_KMH),
		"gear.backward_roll_forward_gear_update",
		""
	)
	_check_text("GearLabel", GEAR_TEXT_FORWARD[0], "gear.backward_roll_forward_gear_text")
	_check(_label("ReverseLabel").visible, "gear.backward_roll_reverse_visible", "")
	_check_text("ReverseLabel", REVERSE_TEXT, "gear.backward_roll_reverse_text")

	# Backward rolling in reverse gear shows R plus REVERSE.
	_check(
		_hud.update(_make_state(Vector2(0.0, -10.0), 0.0, GEAR_REVERSE_INDEX), cue, UNIT_KMH),
		"gear.backward_roll_reverse_gear_update",
		""
	)
	_check_text("GearLabel", GEAR_TEXT_REVERSE, "gear.backward_roll_reverse_gear_text")
	_check(_label("ReverseLabel").visible, "gear.backward_roll_reverse_gear_reverse_visible", "")

	# Text is the primary accessible cue: one character, always visible after a
	# committed update, distinct from every other label's text.
	_check(_label("GearLabel").visible, "gear.visible_after_update", "")
	var gear_label := _label("GearLabel")
	var font := gear_label.get_theme_font("font")
	var font_size := gear_label.get_theme_font_size("font_size")
	for text in GEAR_STRESS_TEXTS:
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		_check(
			text_size.x <= gear_label.size.x + 0.5 and text_size.y <= gear_label.size.y + 0.5,
			"gear.text_fits_%s" % text,
			"text=%s rect=%s" % [text_size, gear_label.size]
		)


func _check_drift_cues() -> void:
	var state := _make_state(Vector2(0.0, 20.0))
	for phase in PHASE_TEXT.size():
		var cue := _make_cue(phase, false, 24.6)
		_check(_hud.update(state, cue, UNIT_KMH), "drift.phase_%d_update" % phase, "")
		var expected: String = PHASE_TEXT[phase]
		if phase == PHASE_ENTRY or phase == PHASE_SUSTAINED or phase == PHASE_RECOVERY:
			expected = "%s 25°" % expected
		_check_text("DriftLabel", expected, "drift.phase_%d_text" % phase)
		_check(
			_hud.get_marker().get_shape_name() == PHASE_SHAPES[phase],
			"drift.phase_%d_shape" % phase,
			_hud.get_marker().get_shape_name()
		)
		_check(
			_hud.get_marker().get_color().is_equal_approx(PHASE_COLORS[phase]),
			"drift.phase_%d_color" % phase,
			_hud.get_marker().get_color().to_html(false)
		)
		_check(not _label("QualifyingLabel").visible, "drift.phase_%d_qualifying_off" % phase, "")
	_check_no_forbidden_wording("drift.no_reward_wording")

	# Qualifying eligibility is forwarded only during a sustained drift.
	var qualifying_cases := [
		[PHASE_GRIP, false],
		[PHASE_ENTRY, false],
		[PHASE_SUSTAINED, true],
		[PHASE_RECOVERY, false],
		[PHASE_AIRBORNE, false],
	]
	for entry in qualifying_cases:
		var phase: int = entry[0]
		var shown: bool = entry[1]
		var cue := _make_cue(phase, true, 20.0)
		_check(_hud.update(state, cue, UNIT_KMH), "qualifying.phase_%d_update" % phase, "")
		_check(
			_label("QualifyingLabel").visible == shown,
			"qualifying.phase_%d_visible" % phase,
			str(_label("QualifyingLabel").visible)
		)
		if shown:
			_check_text("QualifyingLabel", QUALIFYING_TEXT, "qualifying.phase_%d_text" % phase)
		else:
			_check_text("QualifyingLabel", "", "qualifying.phase_%d_text" % phase)


func _check_atomicity() -> void:
	var cue := _make_cue(PHASE_SUSTAINED, true, 24.0)
	_check(_hud.update(_make_state(Vector2(0.0, 20.0)), cue, UNIT_KMH), "atomic.baseline_update", "")
	var baseline := _snapshot()

	var nan_state := _make_state(Vector2(NAN, 0.0))
	var inf_state := _make_state(Vector2(0.0, 20.0))
	inf_state.heading_rad = INF
	var nan_slip_cue := _make_cue(PHASE_SUSTAINED, false, NAN)
	var high_phase_cue := _make_cue(99, false, 0.0)
	var low_phase_cue := _make_cue(-1, false, 0.0)
	var zero_gear_state := _make_state(Vector2(0.0, 20.0), 0.0, 0)
	var high_gear_state := _make_state(Vector2(0.0, 20.0), 0.0, GEAR_MAX_FORWARD + 1)
	var below_reverse_state := _make_state(Vector2(0.0, 20.0), 0.0, GEAR_REVERSE_INDEX - 1)

	var cases: Array[Dictionary] = [
		{"kind": "null_state", "state": null, "cue": cue, "units": UNIT_KMH},
		{"kind": "nan_velocity", "state": nan_state, "cue": cue, "units": UNIT_KMH},
		{"kind": "inf_heading", "state": inf_state, "cue": cue, "units": UNIT_KMH},
		{"kind": "null_cue", "state": _make_state(Vector2(0.0, 20.0)), "cue": null, "units": UNIT_KMH},
		{"kind": "nan_slip", "state": _make_state(Vector2(0.0, 20.0)), "cue": nan_slip_cue, "units": UNIT_KMH},
		{"kind": "high_phase", "state": _make_state(Vector2(0.0, 20.0)), "cue": high_phase_cue, "units": UNIT_KMH},
		{"kind": "low_phase", "state": _make_state(Vector2(0.0, 20.0)), "cue": low_phase_cue, "units": UNIT_KMH},
		{"kind": "high_units", "state": _make_state(Vector2(0.0, 20.0)), "cue": cue, "units": 99},
		{"kind": "low_units", "state": _make_state(Vector2(0.0, 20.0)), "cue": cue, "units": -1},
		{"kind": "gear_zero", "state": zero_gear_state, "cue": cue, "units": UNIT_KMH},
		{"kind": "gear_high", "state": high_gear_state, "cue": cue, "units": UNIT_KMH},
		{"kind": "gear_below_reverse", "state": below_reverse_state, "cue": cue, "units": UNIT_KMH},
	]
	for index in cases.size():
		var case: Dictionary = cases[index]
		var accepted: bool = _hud.update(case["state"], case["cue"], case["units"])
		var label := "atomic.%s" % case["kind"]
		_check(not accepted, label + ".rejected", str(accepted))
		_check(_same_display(baseline, _snapshot()), label + ".display_unchanged", "")


func _check_no_churn() -> void:
	var contents := _hud.get_node("Contents")
	var marker_before := _hud.get_marker()
	var child_count_before := contents.get_child_count()
	for index in 20:
		var state := _make_state(Vector2(0.0, 20.0 + float(index)))
		var cue := _make_cue(PHASE_SUSTAINED, index % 2 == 0, 20.0 + float(index))
		_hud.update(state, cue, UNIT_KMH if index % 2 == 0 else UNIT_MPH)
	_check(
		contents.get_child_count() == child_count_before,
		"churn.child_count_stable",
		"%d vs %d" % [contents.get_child_count(), child_count_before]
	)
	_check(_hud.get_marker() == marker_before, "churn.marker_identity_stable", "")


func _check_instance_independence() -> void:
	var cue := _make_cue(PHASE_GRIP)
	_check(
		_hud.update(_make_state(Vector2(0.0, 30.0), 0.0, 5), cue, UNIT_KMH),
		"independence.first_update",
		""
	)
	_check(
		_second.update(_make_state(Vector2.ZERO, 0.0, GEAR_REVERSE_INDEX), cue, UNIT_KMH),
		"independence.second_update",
		""
	)
	_check_text("SpeedLabel", "108", "independence.first_text")
	_check_text("GearLabel", GEAR_TEXT_FORWARD[4], "independence.first_gear")
	var second_speed := _second.get_node("Contents/SpeedLabel") as Label
	_check(second_speed.text == "0", "independence.second_text", second_speed.text)
	var second_gear := _second.get_node("Contents/GearLabel") as Label
	_check(second_gear.text == GEAR_TEXT_REVERSE, "independence.second_gear", second_gear.text)
	_check(second_gear.visible, "independence.second_gear_visible", "")
	_check(_hud.get_marker() != _second.get_marker(), "independence.distinct_markers", "")


# --- Helpers ---------------------------------------------------------------


func _make_state(velocity: Vector2, heading_rad: float = 0.0, gear_index: int = 1) -> CarState:
	var state := CarState.new()
	state.velocity_m_s = velocity
	state.heading_rad = heading_rad
	state.grounded = true
	state.gear_index = gear_index
	return state


func _make_cue(phase: int, qualifying: bool = false, slip_deg: float = 0.0) -> SpeedHud.DriftCue:
	return SpeedHud.DriftCue.new(phase, qualifying, slip_deg)


func _label(name: String) -> Label:
	return _hud.get_node("Contents/%s" % name) as Label


func _check_text(name: String, expected: String, label: String) -> void:
	var actual := _label(name).text
	_check(actual == expected, label, "got '%s' expected '%s'" % [actual, expected])


func _check_no_forbidden_wording(prefix: String) -> void:
	for label_name in LABEL_NAMES:
		var text := (_hud.get_node("Contents/%s" % label_name) as Label).text.to_lower()
		for word in FORBIDDEN_WORDS:
			_check(
				not text.contains(word),
				prefix + "." + label_name.to_snake_case() + "." + word,
				text
			)


func _snapshot() -> Dictionary:
	var marker := _hud.get_marker()
	return {
		"speed": _label("SpeedLabel").text,
		"unit": _label("UnitLabel").text,
		"gear": _label("GearLabel").text,
		"gear_visible": _label("GearLabel").visible,
		"reverse": _label("ReverseLabel").text,
		"reverse_visible": _label("ReverseLabel").visible,
		"drift": _label("DriftLabel").text,
		"qualifying": _label("QualifyingLabel").text,
		"qualifying_visible": _label("QualifyingLabel").visible,
		"shape": marker.get_shape_name(),
		"color": marker.get_color().to_html(false),
	}


func _same_display(a: Dictionary, b: Dictionary) -> bool:
	for key in a.keys():
		if not b.has(key) or a[key] != b[key]:
			return false
	return a.size() == b.size()


func _rect_within(inner: Rect2, outer: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x - 0.5
		and inner.position.y >= outer.position.y - 0.5
		and inner.end.x <= outer.end.x + 0.5
		and inner.end.y <= outer.end.y + 0.5
	)


func _vec_close(a: Vector2, b: Vector2, tolerance: float) -> bool:
	return absf(a.x - b.x) <= tolerance and absf(a.y - b.y) <= tolerance


func _rects_intersect(a: Rect2, b: Rect2) -> bool:
	var epsilon := 0.001
	return (
		a.position.x < b.end.x - epsilon
		and b.position.x < a.end.x - epsilon
		and a.position.y < b.end.y - epsilon
		and b.position.y < a.end.y - epsilon
	)


func _check_no_overlap(prefix: String) -> void:
	var marker := _hud.get_marker()
	for first in LABEL_NAMES.size():
		var a := _hud.get_node("Contents/%s" % LABEL_NAMES[first]) as Control
		for second in range(first + 1, LABEL_NAMES.size()):
			var b := _hud.get_node("Contents/%s" % LABEL_NAMES[second]) as Control
			_check(
				not _rects_intersect(a.get_global_rect(), b.get_global_rect()),
				prefix + ".no_overlap_%s_%s" % [
					LABEL_NAMES[first].to_snake_case(),
					LABEL_NAMES[second].to_snake_case(),
				],
				"%s vs %s" % [a.get_global_rect(), b.get_global_rect()]
			)
		_check(
			not _rects_intersect(a.get_global_rect(), marker.get_global_rect()),
			prefix + ".no_overlap_%s_marker" % LABEL_NAMES[first].to_snake_case(),
			"%s vs %s" % [a.get_global_rect(), marker.get_global_rect()]
		)


func _has_user_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()


func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not ok:
		if detail.is_empty():
			_failures.append(label)
		else:
			_failures.append("%s (%s)" % [label, detail])


func _record_failure(label: String, detail: String) -> void:
	_check(false, label, detail)


func _check_engine() -> void:
	var version: Dictionary = Engine.get_version_info()
	_check(version["major"] == EXPECTED_MAJOR, "engine.major", str(version["major"]))
	_check(version["minor"] == EXPECTED_MINOR, "engine.minor", str(version["minor"]))
	_check(version["patch"] == EXPECTED_PATCH, "engine.patch", str(version["patch"]))
	_check(version["status"] == EXPECTED_STATUS, "engine.status", str(version["status"]))
	_check(version["build"] == EXPECTED_BUILD, "engine.build", str(version["build"]))
	_check(
		String(version["hash"]).begins_with(EXPECTED_COMMIT_PREFIX),
		"engine.commit",
		str(version["hash"])
	)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {
		"schema": "roadstorm.hud_lab.validation.v1",
		"component": HUD_SCRIPT_PATH,
		"scene": HUD_SCENE_PATH,
		"backend": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"engine_version": Engine.get_version_info(),
		"panel_size": PANEL_SIZE,
		"scales_checked": [1.0, 1.5],
		"checks_total": _checks,
		"checks_failed": _failures.size(),
		"failures": _failures,
		"measured": _measured,
		"limitations": [
			"Headless dummy display/audio drivers; no rendering, visual readability or contrast measurement.",
			"No SubViewport, split-screen, four-player performance or frame-cost exercise.",
			"No integrated race/panel wiring, input, audio, controller or localization check.",
			"All positions, font sizes and colors are provisional M1.5 authored values pending visual review.",
			"No M1.5 or M1 acceptance claim; the coordinator integrates and judges the component.",
		],
	}
	print("HUD_RESULT ", JSON.stringify(report))
	print("CHECKS_TOTAL=", _checks, " CHECKS_FAILED=", _failures.size())
	quit(1 if _failures.size() > 0 else 0)
