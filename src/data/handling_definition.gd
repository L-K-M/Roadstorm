class_name HandlingDefinition
extends DefinitionIdentity
## Typed runtime handling definition for the M0.2 slice.
##
## The fields are exactly the core physical values the committed pure motor
## kernel (`src/simulation/arcade_motor.gd`) accepts through
## `ArcadeMotor.MotorTuning`: a piecewise-linear acceleration curve, braking,
## aerodynamic/rolling drag, grip yaw, lateral damping and the reverse
## transition bounds. Names match that tuning contract; the overlapping
## JSON fields are `handling.acceleration_curve`, `braking_acceleration_m_s2`,
## `drag.aerodynamic`, `drag.rolling`, `yaw_gain.grip`,
## `lateral_damping.grip_per_s` from schemas/handling_config.schema.json.
##
## Defaults are deliberately inert zeros plus the two control-semantic
## constants documented in docs/GAME_DESIGN.md:11 (reverse only strictly
## below 1 m/s after at least a 0.3 s brake hold). They are not measured
## coefficients, not product handling data and not a frozen specification.
## Validation refuses malformed or inconsistent authored content; it never
## clamps or substitutes a value.
##
## Deferred to later slices and deliberately absent here: drift entry/sustain/
## recovery, stability assist, surge candidates, drafting geometry, airborne
## gravity/adhesion, contact caps and per-surface modifiers. See
## src/data/README.md.

## Transient view of one piecewise-linear speed/acceleration point. This
## class is a code-facing value record only; it is never an exported typed-
## array element because Godot 4.7.2 cannot reload a `.tres` whose exported
## element type is an inner Resource class (the loader reports "does not
## inherit from 'GDScript'"). The serialized curve uses two native typed
## float arrays below, which round-trip exactly.
class AccelerationPoint extends RefCounted:
	var speed_m_s := 0.0
	var acceleration_m_s2 := 0.0

	static func make(p_speed_m_s: float, p_acceleration_m_s2: float) -> AccelerationPoint:
		var point := AccelerationPoint.new()
		point.speed_m_s = p_speed_m_s
		point.acceleration_m_s2 = p_acceleration_m_s2
		return point


## GAME_DESIGN.md:11: braking becomes reverse only strictly below 1 m/s and
## only after at least a 0.3 s brake hold. Authored definitions may narrow
## these bounds but never widen them; validation enforces the design ceiling.
const DESIGN_REVERSE_TRIGGER_SPEED_MAX_M_S := 1.0
const DESIGN_REVERSE_HOLD_TIME_MIN_S := 0.3
## Tolerance used when comparing an authored value with a design bound.
const BOUND_TOLERANCE := 1e-9

## Piecewise-linear forward acceleration (m/s^2) versus ground-speed
## magnitude (m/s). Index `i` pairs `acceleration_curve_speeds_m_s[i]` with
## `acceleration_curve_accelerations_m_s2[i]`; the two arrays must have equal
## length. Speeds must strictly increase. These mirror the `handling.
## acceleration_curve` point list in schemas/handling_config.schema.json.
@export var acceleration_curve_speeds_m_s: Array[float] = []
@export var acceleration_curve_accelerations_m_s2: Array[float] = []
@export var braking_acceleration_m_s2 := 0.0
@export var drag_aerodynamic := 0.0
@export var drag_rolling := 0.0
@export var yaw_gain_grip := 0.0
## Absolute yaw-rate cap in rad/s; `INF` disables the cap, matching
## `ArcadeMotor.MotorTuning.max_yaw_rate_rad_s`.
@export var max_yaw_rate_rad_s := INF
@export var lateral_damping_grip_per_s := 0.0
@export var reverse_trigger_speed_m_s := DESIGN_REVERSE_TRIGGER_SPEED_MAX_M_S
@export var reverse_hold_time_s := DESIGN_REVERSE_HOLD_TIME_MIN_S
@export var reverse_acceleration_m_s2 := 0.0
@export var reverse_top_speed_m_s := 0.0


func validate_handling() -> Array[String]:
	var diagnostics: Array[String] = []
	diagnostics.append_array(_validate_curve())
	_validate_non_negative("handling.braking_acceleration_m_s2", braking_acceleration_m_s2, diagnostics)
	_validate_non_negative("handling.drag_aerodynamic", drag_aerodynamic, diagnostics)
	_validate_non_negative("handling.drag_rolling", drag_rolling, diagnostics)
	_validate_non_negative("handling.yaw_gain_grip", yaw_gain_grip, diagnostics)
	_validate_max_yaw_rate(diagnostics)
	_validate_non_negative(
		"handling.lateral_damping_grip_per_s", lateral_damping_grip_per_s, diagnostics
	)
	_validate_reverse_bounds(diagnostics)
	return diagnostics


func validate() -> Array[String]:
	var diagnostics := validate_identity()
	diagnostics.append_array(validate_handling())
	return diagnostics


## Code-facing point view of the serialized curve. A mismatched pair of
## arrays is invalid content, so this returns an empty list rather than a
## truncated point list that would imply valid authored data. Callers must
## still run `validate()`; this accessor never throws for malformed lengths.
func get_acceleration_points() -> Array[AccelerationPoint]:
	if acceleration_curve_speeds_m_s.size() != acceleration_curve_accelerations_m_s2.size():
		return []
	var points: Array[AccelerationPoint] = []
	for index in range(acceleration_curve_speeds_m_s.size()):
		points.append(
			AccelerationPoint.make(
				acceleration_curve_speeds_m_s[index],
				acceleration_curve_accelerations_m_s2[index]
			)
	)
	return points


## Replace the serialized curve atomically from typed points. Returns false
## and leaves the existing curve unchanged when any entry is null or not an
## `AccelerationPoint`; invalid input is never partially applied or silently
## dropped.
func set_acceleration_points(points: Array[AccelerationPoint]) -> bool:
	var speeds: Array[float] = []
	var accelerations: Array[float] = []
	for point in points:
		if not point is AccelerationPoint:
			return false
		speeds.append(point.speed_m_s)
		accelerations.append(point.acceleration_m_s2)
	acceleration_curve_speeds_m_s = speeds
	acceleration_curve_accelerations_m_s2 = accelerations
	return true


func clear_acceleration_curve() -> void:
	acceleration_curve_speeds_m_s = []
	acceleration_curve_accelerations_m_s2 = []


## Scalar projection for a future adapter. Keys match `ArcadeMotor.MotorTuning`
## field names so the adapter can forward them to
## `ArcadeMotor.MotorTuning.make(...)` after converting each
## `AccelerationPoint` to an `ArcadeMotor.SpeedAccelerationPoint`. This method
## does not import, reference or integrate the motor, and it applies no
## physics.
func to_motor_tuning_fields() -> Dictionary:
	return {
		"acceleration_curve": get_acceleration_points(),
		"braking_acceleration_m_s2": braking_acceleration_m_s2,
		"drag_aerodynamic": drag_aerodynamic,
		"drag_rolling": drag_rolling,
		"yaw_gain_grip": yaw_gain_grip,
		"max_yaw_rate_rad_s": max_yaw_rate_rad_s,
		"lateral_damping_grip_per_s": lateral_damping_grip_per_s,
		"reverse_trigger_speed_m_s": reverse_trigger_speed_m_s,
		"reverse_hold_time_s": reverse_hold_time_s,
		"reverse_acceleration_m_s2": reverse_acceleration_m_s2,
		"reverse_top_speed_m_s": reverse_top_speed_m_s,
	}


func _validate_curve() -> Array[String]:
	var diagnostics: Array[String] = []
	var speed_count := acceleration_curve_speeds_m_s.size()
	var acceleration_count := acceleration_curve_accelerations_m_s2.size()
	if speed_count == 0 and acceleration_count == 0:
		diagnostics.append(
			"handling.acceleration_curve: empty; at least one authored point is required"
		)
		return diagnostics
	if speed_count != acceleration_count:
		diagnostics.append(
			"handling.acceleration_curve: speed/acceleration entry counts differ (%d vs %d)"
			% [speed_count, acceleration_count]
		)
	var previous_speed := -INF
	for index in range(mini(speed_count, acceleration_count)):
		var speed := acceleration_curve_speeds_m_s[index]
		var acceleration := acceleration_curve_accelerations_m_s2[index]
		if not _finite(speed) or not _finite(acceleration):
			diagnostics.append(
				"handling.acceleration_curve[%d]: nonfinite speed_m_s=%s acceleration_m_s2=%s"
				% [index, str(speed), str(acceleration)]
			)
			previous_speed = speed
			continue
		if speed < 0.0:
			diagnostics.append(
				"handling.acceleration_curve[%d].speed_m_s: negative %s; expected >= 0"
				% [index, str(speed)]
			)
		if acceleration < 0.0:
			diagnostics.append(
				"handling.acceleration_curve[%d].acceleration_m_s2: negative %s; expected >= 0"
				% [index, str(acceleration)]
			)
		if speed <= previous_speed:
			diagnostics.append(
				"handling.acceleration_curve[%d].speed_m_s: %s does not strictly exceed previous speed %s"
				% [index, str(speed), str(previous_speed)]
			)
		previous_speed = speed
	return diagnostics


func _validate_max_yaw_rate(diagnostics: Array[String]) -> void:
	const FIELD := "handling.max_yaw_rate_rad_s"
	if is_inf(max_yaw_rate_rad_s):
		if max_yaw_rate_rad_s < 0.0:
			diagnostics.append("%s: negative infinity is not a valid cap" % FIELD)
		return
	if not _finite(max_yaw_rate_rad_s):
		diagnostics.append("%s: nonfinite (%s)" % [FIELD, str(max_yaw_rate_rad_s)])
	elif max_yaw_rate_rad_s <= 0.0:
		diagnostics.append(
			"%s: non-positive %s; expected a positive cap or INF" % [FIELD, str(max_yaw_rate_rad_s)]
		)


func _validate_reverse_bounds(diagnostics: Array[String]) -> void:
	const TRIGGER_FIELD := "handling.reverse_trigger_speed_m_s"
	const HOLD_FIELD := "handling.reverse_hold_time_s"
	if not _finite(reverse_trigger_speed_m_s):
		diagnostics.append(
			"%s: nonfinite (%s)" % [TRIGGER_FIELD, str(reverse_trigger_speed_m_s)]
		)
	elif reverse_trigger_speed_m_s < 0.0:
		diagnostics.append(
			"%s: negative %s; expected >= 0" % [TRIGGER_FIELD, str(reverse_trigger_speed_m_s)]
		)
	elif reverse_trigger_speed_m_s > DESIGN_REVERSE_TRIGGER_SPEED_MAX_M_S + BOUND_TOLERANCE:
		diagnostics.append(
			"%s: %s exceeds the docs/GAME_DESIGN.md:11 ceiling of %s m/s"
			% [TRIGGER_FIELD, str(reverse_trigger_speed_m_s), str(DESIGN_REVERSE_TRIGGER_SPEED_MAX_M_S)]
		)

	if not _finite(reverse_hold_time_s):
		diagnostics.append("%s: nonfinite (%s)" % [HOLD_FIELD, str(reverse_hold_time_s)])
	elif reverse_hold_time_s < DESIGN_REVERSE_HOLD_TIME_MIN_S - BOUND_TOLERANCE:
		diagnostics.append(
			"%s: %s is below the docs/GAME_DESIGN.md:11 minimum of %s s"
			% [HOLD_FIELD, str(reverse_hold_time_s), str(DESIGN_REVERSE_HOLD_TIME_MIN_S)]
		)

	_validate_non_negative(
		"handling.reverse_acceleration_m_s2", reverse_acceleration_m_s2, diagnostics
	)
	_validate_non_negative("handling.reverse_top_speed_m_s", reverse_top_speed_m_s, diagnostics)
	if (
		_non_negative_finite(reverse_acceleration_m_s2)
		and _non_negative_finite(reverse_top_speed_m_s)
		and reverse_acceleration_m_s2 > 0.0
		and reverse_top_speed_m_s <= 0.0
	):
		diagnostics.append(
			"handling.reverse_top_speed_m_s: reverse drive with acceleration %s requires a positive top speed"
			% str(reverse_acceleration_m_s2)
		)


func _validate_non_negative(
	field_path: String,
	value: float,
	diagnostics: Array[String]
) -> void:
	if not _finite(value):
		diagnostics.append("%s: nonfinite (%s)" % [field_path, str(value)])
	elif value < 0.0:
		diagnostics.append("%s: negative %s; expected >= 0" % [field_path, str(value)])


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _non_negative_finite(value: float) -> bool:
	return _finite(value) and value >= 0.0
