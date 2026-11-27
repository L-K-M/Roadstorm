class_name SpeedHud
extends Control
## Presentation-only speed and drift HUD for one local player viewport.
##
## PLAN.md M1.5 slice. This is one small reusable 2D `Control` widget, not an
## integrated race HUD: it has no route, race, input, audio or split-screen
## knowledge, and it is never an autoload/singleton. Slot code instantiates
## `scenes/ui/speed_hud.tscn` once per player viewport and calls `update()` from
## committed simulation state. Several independent instances may coexist; each
## owns its own labels and marker.
##
## `update(state, cue, units)` is the single display entry point. It receives
## a committed `CarState`, a small `DriftCue` telemetry record and a unit
## preference (`SpeedUnit.KM_H` or `SpeedUnit.MPH`). Validation happens before
## any widget mutation: a null/invalid/nonfinite state, telemetry or unit
## returns false and leaves the previous display untouched. The HUD never
## writes simulation state, progress, rewards or style score; the qualifying
## flag is only forwarded as the supplier reported it.
##
## Display rules:
##   * Speed is the absolute road-plane magnitude from `CarState.speed_m_s()`
##     converted from m/s, shown as a whole number. The numeral is never
##     negative; a separate `REVERSE` text label states backward travel from
##     `CarState.forward_speed_m_s()` below a small deadband.
##   * Drift phases are `GRIP`, `DRIFT ENTRY`, `SUSTAINED DRIFT`, `RECOVERY`
##     and `AIRBORNE`. Text is the primary accessible cue; color and shape are
##     redundant cues, never the only distinction.
##   * Slip degrees are shown for entry/sustained/recovery as reported by the
##     telemetry record. No score, points or reward wording appears anywhere.
##   * `QUALIFYING DRIFT` is shown only when the supplier reports eligibility
##     during a sustained drift. Other phases, including airborne, never claim
##     qualification.
##
## Provisional authored values (subject to later visual/contrast review):
##   * Base layout targets a 960x540 panel at 100% HUD scale: 40 px speed
##     numerals, 20-22 px essential labels, 360x172 px contents. `set_hud_scale`
##     multiplies positions, sizes and font sizes; 150% was checked to fit.
##   * Palette: dark translucent panel, near-white text, gray grip, amber
##     entry, cyan sustained, orange recovery, violet airborne.
##
## Explicitly unimplemented seams: integration into a race/panel hierarchy,
## split-screen cost, localization, settings persistence, accessibility options
## beyond redundant text, and visual polish/art. Headless validation does not
## prove visual readability, performance, audio or M1.5/M1 acceptance.

## Speed unit preference values. Pass these to `update()`.
enum SpeedUnit {
	KM_H = 0,
	MPH = 1,
}

## Drift presentation phases. `DriftCue.phase` uses these values.
enum DriftPhase {
	GRIP = 0,
	ENTRY = 1,
	SUSTAINED = 2,
	RECOVERY = 3,
	AIRBORNE = 4,
}

const PHASE_COUNT := 5
const UNIT_COUNT := 2

## Standard conversions from metres per second (docs/GAME_DESIGN.md uses m/s
## internally and converts only in the HUD).
const KMH_PER_M_S := 3.6
const MPH_PER_M_S := 2.2369362920544

## Backward travel below this forward component shows REVERSE. A small
## deadband avoids flicker around standstill. Provisional; tune with handling.
const REVERSE_THRESHOLD_M_S := 0.1

# Provisional base layout for one 960x540 panel at 1.0 scale. Every value is
# multiplied by the active HUD scale. See class documentation.
const BASE_MARGIN := 16.0
const BASE_CONTENT_SIZE := Vector2(360.0, 172.0)
const SPEED_RECT := Rect2(14.0, 6.0, 210.0, 52.0)
const UNIT_RECT := Rect2(232.0, 26.0, 96.0, 28.0)
const REVERSE_RECT := Rect2(14.0, 62.0, 120.0, 34.0)
const MARKER_RECT := Rect2(16.0, 108.0, 26.0, 26.0)
const DRIFT_RECT := Rect2(50.0, 104.0, 296.0, 34.0)
const QUALIFYING_RECT := Rect2(50.0, 140.0, 296.0, 26.0)
const SPEED_FONT_SIZE := 40.0
const UNIT_FONT_SIZE := 20.0
const REVERSE_FONT_SIZE := 22.0
const DRIFT_FONT_SIZE := 22.0
const QUALIFYING_FONT_SIZE := 20.0

const UNIT_LABELS: Array[String] = ["km/h", "mph"]
const PHASE_LABELS: Array[String] = [
	"GRIP",
	"DRIFT ENTRY",
	"SUSTAINED DRIFT",
	"RECOVERY",
	"AIRBORNE",
]
const QUALIFYING_LABEL := "QUALIFYING DRIFT"
const REVERSE_LABEL := "REVERSE"


## Small telemetry record paired with a committed `CarState`.
##
## `phase` uses `SpeedHud.DriftPhase` values. `slip_deg` is the signed road-plane
## slip angle in degrees as reported by the simulation; it is informational and
## never converted into points here. All fields are plain data: the record owns
## no clock, random source or simulation authority.
class DriftCue extends RefCounted:
	## One of `SpeedHud.DriftPhase`; values outside the range are refused.
	var phase: int = 0
	## Supplier-reported qualifying-drift eligibility. The HUD does not compute
	## it and only forwards it during a sustained drift.
	var qualifying: bool = false
	## Signed slip angle in degrees; must be finite.
	var slip_deg: float = 0.0


	func _init(p_phase: int = 0, p_qualifying: bool = false, p_slip_deg: float = 0.0) -> void:
		phase = p_phase
		qualifying = p_qualifying
		slip_deg = p_slip_deg


## Redundant color/shape cue drawn with built-in canvas calls.
##
## Shape is the accessibility carrier independent of color: grip is a hollow
## ring, entry a triangle, sustained a filled disc, recovery a hollow square and
## airborne a diamond. A qualifying drift adds a light outer ring.
class PhaseMarker extends Control:
	const PHASE_COLORS: Array[Color] = [
		Color(0.45, 0.48, 0.52, 1.0), # GRIP
		Color(0.96, 0.62, 0.04, 1.0), # ENTRY
		Color(0.13, 0.83, 0.93, 1.0), # SUSTAINED
		Color(0.98, 0.57, 0.24, 1.0), # RECOVERY
		Color(0.65, 0.55, 0.98, 1.0), # AIRBORNE
	]
	const PHASE_SHAPES: Array[String] = ["ring", "triangle", "disc", "square", "diamond"]

	var phase: int = 0
	var qualifying: bool = false


	func set_cue(p_phase: int, p_qualifying: bool) -> void:
		if phase == p_phase and qualifying == p_qualifying:
			return
		phase = p_phase
		qualifying = p_qualifying
		queue_redraw()


	func get_shape_name() -> String:
		if phase < 0 or phase >= PHASE_SHAPES.size():
			return "unknown"
		return PHASE_SHAPES[phase]


	func get_color() -> Color:
		if phase < 0 or phase >= PHASE_COLORS.size():
			return Color(1.0, 0.0, 1.0, 1.0)
		return PHASE_COLORS[phase]


	func _draw() -> void:
		if size.x < 2.0 or size.y < 2.0:
			return
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 2.0
		if radius < 1.0:
			return
		var color := get_color()
		match phase:
			0: # Grip: hollow ring.
				draw_arc(center, radius, 0.0, TAU, 24, color, 3.0, true)
			1: # Entry: filled triangle.
				var triangle := PackedVector2Array([
					center + Vector2(0.0, -radius),
					center + Vector2(-radius * 0.9, radius * 0.75),
					center + Vector2(radius * 0.9, radius * 0.75),
				])
				draw_colored_polygon(triangle, color)
			2: # Sustained: filled disc.
				draw_circle(center, radius * 0.8, color)
			3: # Recovery: hollow square.
				var half := radius * 0.8
				draw_rect(
					Rect2(center - Vector2(half, half), Vector2(half * 2.0, half * 2.0)),
					color,
					false,
					3.0
				)
			4: # Airborne: diamond.
				var diamond := PackedVector2Array([
					center + Vector2(0.0, -radius),
					center + Vector2(radius * 0.8, 0.0),
					center + Vector2(0.0, radius),
					center + Vector2(-radius * 0.8, 0.0),
				])
				draw_colored_polygon(diamond, color)
			_:
				draw_circle(center, radius * 0.5, color)
		if qualifying:
			draw_arc(center, radius + 2.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.9), 2.0, true)


@onready var _contents: Control = $Contents
@onready var _speed_label: Label = $Contents/SpeedLabel
@onready var _unit_label: Label = $Contents/UnitLabel
@onready var _reverse_label: Label = $Contents/ReverseLabel
@onready var _drift_label: Label = $Contents/DriftLabel
@onready var _qualifying_label: Label = $Contents/QualifyingLabel

var _hud_scale := 1.0
var _last_units: int = SpeedUnit.KM_H
var _last_phase: int = DriftPhase.GRIP
var _has_display := false
var _marker: PhaseMarker = null


func _ready() -> void:
	_marker = PhaseMarker.new()
	_marker.name = "PhaseMarker"
	_contents.add_child(_marker)
	_apply_layout()
	_clear_display()


# --- Slot-facing API -------------------------------------------------------


## Explicit display update from one committed state snapshot.
##
## Returns true after the new display is committed. Any invalid input returns
## false and leaves every label, visibility flag and marker property unchanged.
## `units` accepts `SpeedUnit.KM_H` or `SpeedUnit.MPH`; the caller may keep the
## last valid preference by reusing the previous value after a rejection.
func update(state: CarState, cue: DriftCue, units: int) -> bool:
	if not _has_widgets():
		return false
	if not _valid_update_inputs(state, cue, units):
		return false

	var forward_speed := state.forward_speed_m_s()
	var road_speed := state.speed_m_s()
	var conversion := KMH_PER_M_S if units == SpeedUnit.KM_H else MPH_PER_M_S
	var converted := road_speed * conversion
	if not is_finite(forward_speed) or not is_finite(road_speed) or not is_finite(converted):
		return false

	var phase := cue.phase
	var show_reverse := forward_speed < -REVERSE_THRESHOLD_M_S
	var show_qualifying := cue.qualifying and phase == DriftPhase.SUSTAINED

	_set_label_text(_speed_label, str(int(round(converted))))
	_set_label_text(_unit_label, UNIT_LABELS[units])
	_set_label_text(_reverse_label, REVERSE_LABEL if show_reverse else "")
	_set_visible(_reverse_label, show_reverse)
	_set_label_text(_drift_label, _drift_text(phase, cue.slip_deg))
	_set_label_text(_qualifying_label, QUALIFYING_LABEL if show_qualifying else "")
	_set_visible(_qualifying_label, show_qualifying)
	_marker.set_cue(phase, show_qualifying)

	_last_units = units
	_last_phase = phase
	_has_display = true
	return true


## Multiplies every base position, size and font size by `scale`. Nonpositive
## or nonfinite values are refused and leave the current scale unchanged.
## 1.0 is the 960x540 base layout; 1.5 is the checked upper layout scale.
func set_hud_scale(scale: float) -> bool:
	if not is_finite(scale) or scale <= 0.0:
		return false
	_hud_scale = scale
	if _contents != null:
		_apply_layout()
	return true


func get_hud_scale() -> float:
	return _hud_scale


func get_last_units() -> int:
	return _last_units


func get_last_phase() -> int:
	return _last_phase


## True once a valid update has committed a display.
func has_display() -> bool:
	return _has_display


func get_marker() -> PhaseMarker:
	return _marker


# --- Internals -------------------------------------------------------------


func _has_widgets() -> bool:
	return (
		_contents != null
		and _speed_label != null
		and _unit_label != null
		and _reverse_label != null
		and _drift_label != null
		and _qualifying_label != null
		and _marker != null
	)


func _valid_update_inputs(state: CarState, cue: DriftCue, units: int) -> bool:
	if state == null or not is_instance_valid(state):
		return false
	if cue == null or not is_instance_valid(cue):
		return false
	if not _valid_phase(cue.phase) or not _valid_unit(units):
		return false
	if not state.is_finite():
		return false
	return is_finite(cue.slip_deg)


func _valid_phase(phase: int) -> bool:
	return phase >= 0 and phase < PHASE_COUNT


func _valid_unit(units: int) -> bool:
	return units >= 0 and units < UNIT_COUNT


func _drift_text(phase: int, slip_deg: float) -> String:
	var text := PHASE_LABELS[phase]
	if phase == DriftPhase.ENTRY or phase == DriftPhase.SUSTAINED or phase == DriftPhase.RECOVERY:
		return "%s %d°" % [text, int(round(slip_deg))]
	return text


func _set_label_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func _set_visible(control: Control, visible: bool) -> void:
	if control.visible != visible:
		control.visible = visible


func _clear_display() -> void:
	_set_label_text(_speed_label, "0")
	_set_label_text(_unit_label, UNIT_LABELS[SpeedUnit.KM_H])
	_set_label_text(_reverse_label, "")
	_set_visible(_reverse_label, false)
	_set_label_text(_drift_label, PHASE_LABELS[DriftPhase.GRIP])
	_set_label_text(_qualifying_label, "")
	_set_visible(_qualifying_label, false)
	_marker.set_cue(DriftPhase.GRIP, false)
	_last_units = SpeedUnit.KM_H
	_last_phase = DriftPhase.GRIP
	_has_display = false


func _apply_layout() -> void:
	var scale := _hud_scale
	_contents.position = Vector2(BASE_MARGIN, BASE_MARGIN) * scale
	_contents.size = BASE_CONTENT_SIZE * scale
	_place(_speed_label, SPEED_RECT, scale, SPEED_FONT_SIZE)
	_place(_unit_label, UNIT_RECT, scale, UNIT_FONT_SIZE)
	_place(_reverse_label, REVERSE_RECT, scale, REVERSE_FONT_SIZE)
	_place(_drift_label, DRIFT_RECT, scale, DRIFT_FONT_SIZE)
	_place(_qualifying_label, QUALIFYING_RECT, scale, QUALIFYING_FONT_SIZE)
	_marker.position = MARKER_RECT.position * scale
	_marker.size = MARKER_RECT.size * scale
	_marker.queue_redraw()


func _place(label: Label, rect: Rect2, scale: float, base_font_size: float) -> void:
	label.position = rect.position * scale
	label.size = rect.size * scale
	label.add_theme_font_size_override("font_size", maxi(1, int(round(base_font_size * scale))))
