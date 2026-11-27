class_name CarState
extends RefCounted
## Committed road-plane car state consumed and produced by the pure motor.
##
## Coordinate convention (docs/handling_config.schema.json `coordinate_frame`
## projected onto the support plane, with Y used for the road-plane longitudinal
## axis in this 2D record):
##   * `position_m` / `velocity_m_s` axis 0 (`x`) is lateral right;
##   * axis 1 (`y`) is longitudinal forward;
##   * `heading_rad` is the signed angle from the +y forward axis toward the
##     +x right axis. The forward unit vector is therefore
##     `(sin(heading), cos(heading))` and the right unit vector is
##     `(cos(heading), -sin(heading))`.
##
## This is a plain data record. It owns no Godot body, clock or physics query;
## the simulation coordinator is responsible for converting this road-plane
## motion into world motion on the support basis and committing it.
##
## Committed gear mirror: `gear_index` mirrors the canonical
## `AutomaticGearbox.GearboxState.gear_index` (`-1` reverse, `1..N` forward)
## for HUD/audio consumers and initializes to gear 1 so a fresh record agrees
## with the gearbox deterministic reset. The gearbox owns selection, shift
## dwell and rpm indication. A replay/restore must save and restore the
## `GearboxState` together with this record and then apply both as one atomic
## step with `AutomaticGearbox.restore_and_mirror()`; `restore_state()`
## followed by `mirror_gear()` is the compatible two-call form, but only the
## combined helper is transactional. Restoring this record alone cannot
## reproduce dwell or shift timing. `AutomaticGearbox.propose()` commits the
## canonical state immediately, so the integrator must propose exactly once
## per accepted tick from this car's committed record and pair the returned
## gear with the matching car/tick.
##
## Inert seams for later M1 slices (present so the state shape already matches
## docs/TECHNICAL_DESIGN.md:81; the M1.1 motor copies them unchanged and does not
## interpret them): `drift_active`, `drift_timer_s`, `surge_cooldown_s`,
## `drafting_active`, `contact_immunity_s` and `valid_progress_m`. Surface
## response is likewise deferred: `surface_id` is carried through untouched and
## M1.3/M1.7 owns modifier resolution.

## Road-plane position relative to the scenario origin, metres.
var position_m := Vector2(0.0, 0.0)
## Road-plane velocity: x = lateral right, y = longitudinal forward, m/s.
var velocity_m_s := Vector2(0.0, 0.0)
## Signed heading in radians; positive rotates the nose right. Unwrapped.
var heading_rad := 0.0
## Whether the car is on the ground. Airborne integration is out of this slice.
var grounded := true
## Route-local surface identifier. Inert in M1.1; defaults to asphalt.
var surface_id := &"asphalt"

# --- Active in this slice -------------------------------------------------
## Automatic-transmission reverse state derived from the design rule at
## docs/GAME_DESIGN.md:11: brake becomes reverse below 1 m/s after a 0.3 s hold.
var reverse_engaged := false
## Time the brake has been held at or below the trigger speed, seconds.
var reverse_hold_s := 0.0

# --- Inert documented seams (copied unchanged by M1.1) --------------------
## Committed mirror of the gearbox's canonical gear indication (`-1` reverse,
## `1..N` forward). Defaults to gear 1; the integrator repairs it from
## `AutomaticGearbox` after each successful proposal or restore.
var gear_index := 1
## Drift state machine seam; drift entry/sustain/exit is M1.3.
var drift_active := false
## Seconds since drift entry; M1.3 owns the value.
var drift_timer_s := 0.0
## Reserved slip-angle mirror for M1.3 telemetry; inert here. Use `slip_deg()`
## for a computed value.
var drift_slip_deg := 0.0
## Surge cooldown remaining, seconds; surge is M1.3/M1.7.
var surge_cooldown_s := 0.0
## Drafting eligibility/active seam; drafting response is later work.
var drafting_active := false
## Post-reset contact immunity remaining, seconds; reset policy is later work.
var contact_immunity_s := 0.0
## Valid route progress, metres; progress gates are owned by CourseProgress.
var valid_progress_m := 0.0


## Forward unit vector in the road plane.
func forward_vector() -> Vector2:
	return Vector2(sin(heading_rad), cos(heading_rad))


## Right unit vector in the road plane.
func right_vector() -> Vector2:
	var forward := forward_vector()
	return Vector2(forward.y, -forward.x)


## Longitudinal forward speed component, m/s (negative while reversing).
func forward_speed_m_s() -> float:
	return velocity_m_s.dot(forward_vector())


## Lateral right speed component, m/s.
func lateral_speed_m_s() -> float:
	return velocity_m_s.dot(right_vector())


## Ground speed magnitude, m/s.
func speed_m_s() -> float:
	return velocity_m_s.length()


## Signed slip angle between the nose and the travel direction, degrees.
## Positive means the velocity points to the right of the nose.
func slip_deg() -> float:
	var forward := forward_vector()
	var right := right_vector()
	var forward_component := velocity_m_s.dot(forward)
	var lateral_component := velocity_m_s.dot(right)
	if is_zero_approx(forward_component) and is_zero_approx(lateral_component):
		return 0.0
	return rad_to_deg(atan2(lateral_component, forward_component))


func copy() -> CarState:
	var state := CarState.new()
	state.position_m = position_m
	state.velocity_m_s = velocity_m_s
	state.heading_rad = heading_rad
	state.grounded = grounded
	state.surface_id = surface_id
	state.reverse_engaged = reverse_engaged
	state.reverse_hold_s = reverse_hold_s
	state.gear_index = gear_index
	state.drift_active = drift_active
	state.drift_timer_s = drift_timer_s
	state.drift_slip_deg = drift_slip_deg
	state.surge_cooldown_s = surge_cooldown_s
	state.drafting_active = drafting_active
	state.contact_immunity_s = contact_immunity_s
	state.valid_progress_m = valid_progress_m
	return state


## Every numeric field must be finite for the pure kernel to accept the state.
func is_finite() -> bool:
	var scalars := [
		position_m.x,
		position_m.y,
		velocity_m_s.x,
		velocity_m_s.y,
		heading_rad,
		reverse_hold_s,
		drift_timer_s,
		drift_slip_deg,
		surge_cooldown_s,
		contact_immunity_s,
		valid_progress_m,
	]
	for value in scalars:
		if is_nan(value) or is_inf(value):
			return false
	return true
