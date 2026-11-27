class_name DriftPhaseModel
extends RefCounted
## Pure, side-effect-free 60 Hz drift-phase evaluator (M1.3 first bounded slice).
##
## It reads one committed `CarState`, one normalized `DriverCommand`, one
## copyable `DriftState` and explicit `Tuning`, then returns a proposed new
## `DriftState` with the phase, drift blend, advisory stability factor and a
## transition event. It never mutates an input and never touches a Godot body,
## scene tree, physics server, clock or RNG. Repeated calls with identical
## inputs produce identical results; only the simulation coordinator owns
## clocks, commits and events (docs/TECHNICAL_DESIGN.md:63-69).
##
## Phases follow docs/GAME_DESIGN.md:17-29: Grip, Drift entry, Sustained drift,
## Recovery and Airborne. Entry requires forward motion above the fixed design
## threshold (`ENTRY_SPEED_DESIGN_MIN_M_S` = 12 m/s, never reversible by tuning
## without a recorded design decision), substantial steering, and a true
## rising-edge handbrake tap; with Standard assist on, a brake tap while
## steering is the documented alternative. Entry blends influence over
## `entry_blend_time_s` (provisional 0.2 s) and recovery restores grip over
## `recovery_blend_time_s` (provisional 0.35 s). Sustained drift tolerates
## ordinary countersteer and exits on steering unwind, low speed, major impact
## or loss of ground; every exit uses a hold timer so one anomalous tick cannot
## chatter between phases.
##
## `drift_blend` is the proposed influence in [0, 1] that the motor integration
## maps onto its own grip/drift yaw and lateral-damping parameters. This model
## does not enforce slip, yaw or lateral motion: the integrator owns that
## physics. `stability_factor` is advisory: the integrator applies it to
## additional rotation above the provisional stability slip angle.
##
## Deferred seams owned elsewhere, intentionally absent here: style points,
## surge grants, course-zone qualification, surface response, player input
## routing, contact classification and the actual yaw/lateral integration. A
## drift-phase exit alone is not a clean or qualifying exit. The 12-40 degree
## useful slip band is telemetry only (`useful_slip`) and gates nothing.
##
## Every physical/timing number below is a caller-supplied tuning field. The
## defaults are explicitly provisional, not frozen product handling.

const DT := 1.0 / 60.0
## Absolute tolerance for accepting a caller-supplied step size as 60 Hz.
const DT_TOLERANCE_S := 1e-6
## Design floor from docs/GAME_DESIGN.md:24: drift entry requires motion above
## 12 m/s. Tuning may raise this threshold, never lower it.
const ENTRY_SPEED_DESIGN_MIN_M_S := 12.0
## Tolerance used when comparing tunable values with design bounds.
const DESIGN_BOUND_TOLERANCE := 1e-9
## Slack for discrete 60 Hz timer completions. Repeated additions of `DT` can
## land just below an exact decimal threshold; without slack the phase length
## would depend on floating-point accumulation.
const TIMER_EPSILON_S := 1e-9

enum Phase { GRIP, ENTRY, SUSTAINED, RECOVERY, AIRBORNE }

## Standard assist enables the documented brake-tap entry alternative and the
## stability factor. Assist off permits only the handbrake entry path.
enum AssistMode { OFF, STANDARD }

## Phase-transition reasons. `NONE` means the tick continued in its phase.
enum Event {
	NONE,
	DRIFT_ENTRY_HANDBRAKE,
	DRIFT_ENTRY_ASSIST_BRAKE,
	DRIFT_SUSTAINED,
	STEERING_UNWIND_RECOVERY,
	LOW_SPEED_RECOVERY,
	MAJOR_IMPACT_RECOVERY,
	AIRBORNE,
	LANDED_RECOVERY,
	GRIP_RESTORED,
}


## Explicit, caller-supplied drift-phase values. Defaults are provisional M1.3
## laboratory choices; the design-fixed entry speed has a validation floor and
## the design reference values (0.2 s entry, 0.35 s recovery, 12-40 degrees
## useful slip, ~50 degrees stability onset) are documented starting points.
class Tuning extends RefCounted:
	## Forward speed strictly above which entry is allowed. Design floor 12 m/s.
	var min_entry_forward_speed_m_s := ENTRY_SPEED_DESIGN_MIN_M_S
	## Minimum |steer| for a valid entry initiation.
	var entry_steer_min := 0.5
	## Handbrake value at/above which a rising edge counts as a tap.
	var handbrake_tap_min := 0.5
	## Brake value at/above which a rising edge counts as an assisted tap.
	var assist_brake_tap_min := 0.5
	## Influence blend time from grip into sustained drift, seconds (~0.2 s).
	var entry_blend_time_s := 0.2
	## Grip-restoration blend time, seconds (~0.35 s).
	var recovery_blend_time_s := 0.35
	## |steer| below this starts the unwind hold in entry/sustain.
	var unwind_steer_max := 0.2
	## Hold time for steering unwind before recovery, seconds.
	var unwind_hold_s := 0.15
	## Forward speed at/below which sustain begins the low-speed hold.
	var sustain_exit_speed_m_s := 8.0
	## Hold time for low speed before recovery, seconds.
	var low_speed_hold_s := 0.2
	## Speed loss in one tick classified as a major impact, m/s.
	var impact_exit_speed_loss_m_s := 6.0
	## Lower bound of the reported useful slip band, degrees.
	var target_slip_deg_min := 12.0
	## Upper bound of the reported useful slip band, degrees.
	var target_slip_deg_max := 40.0
	## Stability assistance begins reducing additional rotation above this
	## absolute slip angle, degrees (design reference ~50).
	var stability_start_deg := 50.0
	## Slip angle at which the stability factor reaches its floor, degrees.
	var stability_full_deg := 90.0
	## Lowest stability factor at/above `stability_full_deg`, in [0, 1].
	var stability_floor_factor := 0.2
	## Minimum time in the air before a landing can end the airborne phase.
	var airborne_min_time_s := 0.1
	## Continuous grounded time required to confirm a landing, seconds.
	var landing_confirm_s := 0.05
	## Assistance mode: STANDARD enables brake-tap entry and stability factor.
	var assist_mode: AssistMode = AssistMode.STANDARD


	func is_valid() -> bool:
		if not _finite(min_entry_forward_speed_m_s):
			return false
		if min_entry_forward_speed_m_s < ENTRY_SPEED_DESIGN_MIN_M_S - DESIGN_BOUND_TOLERANCE:
			return false
		if not _unit_interval(entry_steer_min):
			return false
		if not _unit_interval(handbrake_tap_min):
			return false
		if not _unit_interval(assist_brake_tap_min):
			return false
		if not _positive_finite(entry_blend_time_s):
			return false
		if not _positive_finite(recovery_blend_time_s):
			return false
		if not _unit_interval(unwind_steer_max):
			return false
		if not _non_negative_finite(unwind_hold_s):
			return false
		if not _non_negative_finite(sustain_exit_speed_m_s):
			return false
		if sustain_exit_speed_m_s >= min_entry_forward_speed_m_s:
			return false
		if not _non_negative_finite(low_speed_hold_s):
			return false
		if not _non_negative_finite(impact_exit_speed_loss_m_s):
			return false
		if not _finite(target_slip_deg_min) or target_slip_deg_min < 0.0:
			return false
		if not _finite(target_slip_deg_max) or target_slip_deg_max <= target_slip_deg_min:
			return false
		if target_slip_deg_max > 180.0:
			return false
		if not _finite(stability_start_deg):
			return false
		if stability_start_deg <= 0.0 or stability_start_deg > 180.0:
			return false
		if not _finite(stability_full_deg) or stability_full_deg <= stability_start_deg:
			return false
		if stability_full_deg > 180.0:
			return false
		if not _unit_interval(stability_floor_factor):
			return false
		if not _non_negative_finite(airborne_min_time_s):
			return false
		if not _non_negative_finite(landing_confirm_s):
			return false
		return true


	static func _finite(value: float) -> bool:
		return not is_nan(value) and not is_inf(value)


	static func _positive_finite(value: float) -> bool:
		return _finite(value) and value > 0.0


	static func _non_negative_finite(value: float) -> bool:
		return _finite(value) and value >= 0.0


	static func _unit_interval(value: float) -> bool:
		return _finite(value) and value >= 0.0 and value <= 1.0


## Copyable drift-phase state. All timers are seconds; hold timers accumulate
## only while their condition is true, which prevents one-frame chatter.
class State extends RefCounted:
	var phase: Phase = Phase.GRIP
	## Seconds elapsed in the current phase.
	var phase_time_s := 0.0
	## +1 right, -1 left, 0 when not drifting.
	var drift_sign := 0
	## Last computed influence in [0, 1]; the model also recomputes it each step.
	var drift_blend := 0.0
	## Previous normalized handbrake, for a true rising-edge tap.
	var previous_handbrake := 0.0
	## Previous normalized brake, for a true rising-edge tap.
	var previous_brake := 0.0
	## Steering-unwind hold accumulator.
	var unwind_hold_s := 0.0
	## Low-speed hold accumulator.
	var low_speed_hold_s := 0.0
	## Continuous grounded-time accumulator while airborne.
	var landing_hold_s := 0.0
	## Total time in the airborne phase.
	var airborne_time_s := 0.0
	## Blend captured when recovery began, so grip restoration starts from the
	## actual outgoing influence instead of a fixed value.
	var recovery_start_blend := 0.0


	func copy() -> State:
		var state := State.new()
		state.phase = phase
		state.phase_time_s = phase_time_s
		state.drift_sign = drift_sign
		state.drift_blend = drift_blend
		state.previous_handbrake = previous_handbrake
		state.previous_brake = previous_brake
		state.unwind_hold_s = unwind_hold_s
		state.low_speed_hold_s = low_speed_hold_s
		state.landing_hold_s = landing_hold_s
		state.airborne_time_s = airborne_time_s
		state.recovery_start_blend = recovery_start_blend
		return state


	func is_finite() -> bool:
		var scalars := [
			phase_time_s,
			drift_blend,
			previous_handbrake,
			previous_brake,
			unwind_hold_s,
			low_speed_hold_s,
			landing_hold_s,
			airborne_time_s,
			recovery_start_blend,
		]
		for value in scalars:
			if is_nan(value) or is_inf(value):
				return false
		return true


	func is_valid() -> bool:
		if not self.is_finite():
			return false
		if phase < Phase.GRIP or phase > Phase.AIRBORNE:
			return false
		if drift_sign < -1 or drift_sign > 1:
			return false
		if drift_blend < 0.0 or drift_blend > 1.0:
			return false
		if previous_handbrake < 0.0 or previous_handbrake > 1.0:
			return false
		if previous_brake < 0.0 or previous_brake > 1.0:
			return false
		if phase_time_s < 0.0 or unwind_hold_s < 0.0 or low_speed_hold_s < 0.0:
			return false
		if landing_hold_s < 0.0 or airborne_time_s < 0.0:
			return false
		if recovery_start_blend < 0.0 or recovery_start_blend > 1.0:
			return false
		return true


## Result of one pure drift-phase evaluation. `state_in`, `car_state`,
## `command` and `tuning` are never mutated. `event` is the transition reason
## for this tick (`Event.NONE` when the phase merely continued).
class Proposal extends RefCounted:
	var state := State.new()
	var phase: Phase = Phase.GRIP
	## Proposed drift influence in [0, 1], finite.
	var drift_blend := 0.0
	## Advisory multiplier for additional rotation in [0, 1]; 1.0 disables the
	## reduction. The model does not apply it to any physics quantity.
	var stability_factor := 1.0
	var event: Event = Event.NONE
	var drift_sign := 0
	## Road-plane slip angle read from the committed car state, degrees.
	var slip_deg := 0.0
	## Telemetry only: slip inside `target_slip_deg_min..max`. Gates nothing.
	var useful_slip := false


## Evaluate one fixed 60 Hz drift-phase step. Returns `null` for invalid input:
## null records, nonfinite/invalid car state, command, drift state or tuning, a
## step size that is not the declared 60 Hz tick, or a negative/nonfinite
## impact speed loss. A refusal changes no input object; callers keep their
## prior `DriftState` unchanged.
static func propose(
	car_state: CarState,
	command: DriverCommand,
	drift_state: State,
	tuning: Tuning,
	dt: float = DT,
	impact_speed_loss_m_s: float = 0.0
) -> Proposal:
	if car_state == null or command == null or drift_state == null or tuning == null:
		return null
	if not drift_state.is_valid():
		return null
	if not car_state.is_finite():
		return null
	if not command.is_normalized():
		return null
	if not tuning.is_valid():
		return null
	if not _finite(dt) or dt <= 0.0 or absf(dt - DT) > DT_TOLERANCE_S:
		return null
	if not _finite(impact_speed_loss_m_s) or impact_speed_loss_m_s < 0.0:
		return null

	var proposed := drift_state.copy()
	proposed.phase_time_s = drift_state.phase_time_s + dt
	var outgoing_blend := _blend_after_step(drift_state, tuning, dt)

	var grounded := car_state.grounded
	var forward_speed := car_state.forward_speed_m_s()
	var steer_abs := absf(command.steer)
	var steer_sign := _sign(command.steer)
	var handbrake_edge := (
		command.handbrake >= tuning.handbrake_tap_min
		and drift_state.previous_handbrake < tuning.handbrake_tap_min
	)
	var brake_edge := (
		command.brake >= tuning.assist_brake_tap_min
		and drift_state.previous_brake < tuning.assist_brake_tap_min
	)
	var major_impact := (
		impact_speed_loss_m_s > 0.0
		and impact_speed_loss_m_s >= tuning.impact_exit_speed_loss_m_s
	)
	var low_speed := forward_speed <= tuning.sustain_exit_speed_m_s
	var unwind := steer_abs < tuning.unwind_steer_max
	var event: Event = Event.NONE

	match drift_state.phase:
		Phase.GRIP:
			proposed.unwind_hold_s = 0.0
			proposed.low_speed_hold_s = 0.0
			if not grounded:
				_begin_phase(proposed, Phase.AIRBORNE)
				event = Event.AIRBORNE
			elif major_impact:
				_begin_phase(proposed, Phase.RECOVERY, outgoing_blend)
				event = Event.MAJOR_IMPACT_RECOVERY
			else:
				var entry_event := _entry_event(
					forward_speed, steer_abs, handbrake_edge, brake_edge, tuning
				)
				if entry_event != Event.NONE:
					_begin_phase(proposed, Phase.ENTRY)
					proposed.drift_sign = steer_sign
					event = entry_event
		Phase.ENTRY:
			if not grounded:
				_begin_phase(proposed, Phase.AIRBORNE)
				event = Event.AIRBORNE
			elif major_impact:
				_begin_phase(proposed, Phase.RECOVERY, outgoing_blend)
				event = Event.MAJOR_IMPACT_RECOVERY
			elif unwind:
				proposed.unwind_hold_s = drift_state.unwind_hold_s + dt
				proposed.low_speed_hold_s = 0.0
				if proposed.unwind_hold_s >= tuning.unwind_hold_s - TIMER_EPSILON_S:
					_begin_phase(proposed, Phase.RECOVERY, outgoing_blend)
					event = Event.STEERING_UNWIND_RECOVERY
			elif low_speed:
				proposed.low_speed_hold_s = drift_state.low_speed_hold_s + dt
				proposed.unwind_hold_s = 0.0
				if proposed.low_speed_hold_s >= tuning.low_speed_hold_s - TIMER_EPSILON_S:
					_begin_phase(proposed, Phase.RECOVERY, outgoing_blend)
					event = Event.LOW_SPEED_RECOVERY
			else:
				proposed.unwind_hold_s = 0.0
				proposed.low_speed_hold_s = 0.0
				if proposed.phase_time_s >= tuning.entry_blend_time_s - TIMER_EPSILON_S:
					_begin_phase(proposed, Phase.SUSTAINED)
					event = Event.DRIFT_SUSTAINED
		Phase.SUSTAINED:
			if not grounded:
				_begin_phase(proposed, Phase.AIRBORNE)
				event = Event.AIRBORNE
			elif major_impact:
				_begin_phase(proposed, Phase.RECOVERY, outgoing_blend)
				event = Event.MAJOR_IMPACT_RECOVERY
			elif unwind:
				proposed.unwind_hold_s = drift_state.unwind_hold_s + dt
				proposed.low_speed_hold_s = 0.0
				if proposed.unwind_hold_s >= tuning.unwind_hold_s - TIMER_EPSILON_S:
					_begin_phase(proposed, Phase.RECOVERY, outgoing_blend)
					event = Event.STEERING_UNWIND_RECOVERY
			elif low_speed:
				proposed.low_speed_hold_s = drift_state.low_speed_hold_s + dt
				proposed.unwind_hold_s = 0.0
				if proposed.low_speed_hold_s >= tuning.low_speed_hold_s - TIMER_EPSILON_S:
					_begin_phase(proposed, Phase.RECOVERY, outgoing_blend)
					event = Event.LOW_SPEED_RECOVERY
			else:
				proposed.unwind_hold_s = 0.0
				proposed.low_speed_hold_s = 0.0
		Phase.RECOVERY:
			proposed.unwind_hold_s = 0.0
			proposed.low_speed_hold_s = 0.0
			if not grounded:
				_begin_phase(proposed, Phase.AIRBORNE)
				event = Event.AIRBORNE
			elif major_impact:
				# A fresh major impact restarts the bounded restoration window
				# from the influence actually present, not the original start.
				# The event stays NONE because the phase did not change.
				var outgoing := clampf(_blend_for_phase(drift_state, tuning), 0.0, 1.0)
				proposed.phase_time_s = 0.0
				proposed.recovery_start_blend = outgoing
			elif proposed.phase_time_s >= tuning.recovery_blend_time_s - TIMER_EPSILON_S:
				_begin_phase(proposed, Phase.GRIP)
				proposed.drift_sign = 0
				event = Event.GRIP_RESTORED
		Phase.AIRBORNE:
			proposed.unwind_hold_s = 0.0
			proposed.low_speed_hold_s = 0.0
			proposed.airborne_time_s = drift_state.airborne_time_s + dt
			if grounded:
				proposed.landing_hold_s = drift_state.landing_hold_s + dt
				if (
					proposed.landing_hold_s >= tuning.landing_confirm_s - TIMER_EPSILON_S
					and proposed.airborne_time_s >= tuning.airborne_min_time_s - TIMER_EPSILON_S
				):
					_begin_phase(proposed, Phase.RECOVERY, 0.0)
					event = Event.LANDED_RECOVERY
			else:
				proposed.landing_hold_s = 0.0

	proposed.drift_blend = clampf(_blend_for_phase(proposed, tuning), 0.0, 1.0)
	# True rising-edge taps require the previous normalized values in the copy
	# returned to the caller; refusals above leave every input untouched.
	proposed.previous_handbrake = command.handbrake
	proposed.previous_brake = command.brake

	var proposal := Proposal.new()
	proposal.state = proposed
	proposal.phase = proposed.phase
	proposal.drift_blend = proposed.drift_blend
	proposal.stability_factor = _stability_factor(car_state, tuning)
	proposal.event = event
	proposal.drift_sign = proposed.drift_sign
	proposal.slip_deg = car_state.slip_deg()
	var slip_abs := absf(proposal.slip_deg)
	proposal.useful_slip = (
		slip_abs >= tuning.target_slip_deg_min and slip_abs <= tuning.target_slip_deg_max
	)

	if not _proposal_is_finite(proposal):
		return null
	return proposal


## Reset `state` to `phase` and clear phase-scoped accumulators. When entering
## recovery, `recovery_start_blend` preserves the outgoing influence.
static func _begin_phase(state: State, phase: Phase, recovery_start_blend := 0.0) -> void:
	state.phase = phase
	state.phase_time_s = 0.0
	state.unwind_hold_s = 0.0
	state.low_speed_hold_s = 0.0
	state.landing_hold_s = 0.0
	state.airborne_time_s = 0.0
	if phase == Phase.RECOVERY:
		state.recovery_start_blend = clampf(recovery_start_blend, 0.0, 1.0)
	else:
		state.recovery_start_blend = 0.0


static func _entry_event(
	forward_speed: float,
	steer_abs: float,
	handbrake_edge: bool,
	brake_edge: bool,
	tuning: Tuning
) -> Event:
	if forward_speed <= tuning.min_entry_forward_speed_m_s:
		return Event.NONE
	if steer_abs < tuning.entry_steer_min:
		return Event.NONE
	if handbrake_edge:
		return Event.DRIFT_ENTRY_HANDBRAKE
	if tuning.assist_mode == AssistMode.STANDARD and brake_edge:
		return Event.DRIFT_ENTRY_ASSIST_BRAKE
	return Event.NONE


static func _blend_after_step(state: State, tuning: Tuning, dt: float) -> float:
	var advanced := state.copy()
	advanced.phase_time_s = state.phase_time_s + dt
	return _blend_for_phase(advanced, tuning)


static func _blend_for_phase(state: State, tuning: Tuning) -> float:
	match state.phase:
		Phase.ENTRY:
			return _smooth01(state.phase_time_s / tuning.entry_blend_time_s)
		Phase.SUSTAINED:
			return 1.0
		Phase.RECOVERY:
			return state.recovery_start_blend * (
				1.0 - _smooth01(state.phase_time_s / tuning.recovery_blend_time_s)
			)
		_:
			return 0.0


## Smooth Hermite ramp in [0, 1]. At x <= 0 it is 0, at x >= 1 it is 1.
static func _smooth01(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Advisory stability factor: 1.0 up to `stability_start_deg`, then linearly
## down to `stability_floor_factor` at `stability_full_deg`. Assist off or an
## airborne car receives no reduction. This is not an enforced slip limit.
static func _stability_factor(car_state: CarState, tuning: Tuning) -> float:
	if tuning.assist_mode != AssistMode.STANDARD or not car_state.grounded:
		return 1.0
	var slip_abs := absf(car_state.slip_deg())
	if slip_abs <= tuning.stability_start_deg:
		return 1.0
	var span := tuning.stability_full_deg - tuning.stability_start_deg
	var t := clampf((slip_abs - tuning.stability_start_deg) / span, 0.0, 1.0)
	return lerpf(1.0, tuning.stability_floor_factor, t)


static func _proposal_is_finite(proposal: Proposal) -> bool:
	if not proposal.state.is_finite():
		return false
	if proposal.phase < Phase.GRIP or proposal.phase > Phase.AIRBORNE:
		return false
	if not _finite(proposal.drift_blend):
		return false
	if proposal.drift_blend < 0.0 or proposal.drift_blend > 1.0:
		return false
	if not _finite(proposal.stability_factor):
		return false
	if proposal.stability_factor < 0.0 or proposal.stability_factor > 1.0:
		return false
	if not _finite(proposal.slip_deg):
		return false
	return true


static func _sign(value: float) -> int:
	if value > 0.0:
		return 1
	if value < 0.0:
		return -1
	return 0


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
