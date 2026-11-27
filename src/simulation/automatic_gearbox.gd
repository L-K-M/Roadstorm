class_name AutomaticGearbox
extends RefCounted
## Pure, stateful 60 Hz automatic-gear indication kernel (M1.1 bounded slice).
##
## This is an isolated, integration-ready component for the automatic
## transmission required by docs/GAME_DESIGN.md:9. It selects a gear index
## from the committed `CarState` road-plane motion and reports at most one
## shift event per tick. It changes no physics, writes no `CarState` field,
## touches no Godot body/scene/physics server/clock/RNG, and produces no
## audio. The future simulation integrator owns calling `mirror_gear()` to
## commit the gear indication into a `CarState` copy and routing `ShiftEvent` to
## presentation/audio.
##
## Inputs and output:
##   * input: one committed `CarState` whose every numeric field is finite
##     (`CarState.is_finite()`); the consumed fields are the finite signed
##     forward speed (`velocity_m_s` projected on `heading_rad`) and the
##     committed `reverse_engaged` latch produced by `ArcadeMotor`;
##   * output: `GearboxProposal` with `gear_index` (`-1` reverse, `1..N`
##     forward), a bounded `normalized_rpm` in `[0, 1]`, and a `ShiftEvent`
##     (`from_gear`, `to_gear`, `direction`, post-shift `normalized_rpm`) only
##     when the gear actually changed.
##
## Reverse selection obeys the existing motor latch, never signed velocity
## alone. A negative signed speed while `reverse_engaged` is false can never
## select `-1`; entering reverse requires the latch to be set. Leaving reverse
## requires the latch to clear and forward travel to reach
## `reverse_exit_forward_speed_m_s`, so a latch release during backward roll
## does not snap the indicator to a forward gear.
##
## Forward thresholds are configurable and validated. Upshifts trigger strictly
## above an upshift threshold and downshifts strictly below a downshift
## threshold; every pair keeps at least `min_hysteresis_gap_m_s` of separation
## and shifts are additionally separated by `min_shift_dwell_s`. Together these
## prevent boundary dithering and repeated shift events. Threshold comparison
## uses the forward-speed magnitude for forward gears. From a forward gear the
## selected gear therefore stays forward whenever the latch is released;
## releasing the reverse indication additionally requires forward travel at or
## above `reverse_exit_forward_speed_m_s`, so `-1` persists during backward
## roll after the latch clears.
##
## Invalid configuration, a nonfinite committed `CarState` record (any
## numeric field, per `CarState.is_finite()`), a nonfinite dt, or an unexpected
## nonfinite result is refused atomically: `create()` returns `null`,
## `propose()` returns `null`, and no gearbox or input state changes. `reset()`
## returns the instance to the deterministic initial state (gear 1, zero dwell,
## zero rpm).
## Fixed-step contract: callers pass `DT` (1/60 s); other positive step sizes
## are refused, matching `ArcadeMotor`.
##
## Provisional tuning: the default six forward gears span the committed 0-45
## m/s laboratory motor envelope (`src/laboratory/drive_lab.gd`
## `make_laboratory_tuning()`, whose acceleration curve reaches zero at 45 m/s;
## the M1.1 pure-motor fixture curve also ends at 45 m/s). The default
## thresholds are starting values only, not frozen product handling. M1.6/M1.7
## handling measurements own their ratification.
##
## Deferred seams owned elsewhere: actual torque/rpm physics, throttle/brake
## awareness, airborne behaviour, launch logic, shift audio and HUD display.
## This component only indicates a gear and an event.
##
## State boundary (resolved): the private `GearboxState` is the canonical
## gear/dwell/rpm indication; `CarState.gear_index` is only a committed mirror
## for HUD/audio consumers and initializes to gear 1 like `reset()`. A
## replay/restore must save and restore the `GearboxState` alongside the
## `CarState`; restoring `CarState` alone is insufficient because it carries
## neither the dwell nor the canonical rpm. `restore_and_mirror(candidate,
## car_state)` is the all-or-nothing form: it validates the whole candidate
## pair before mutating this gearbox, commits the canonical copy, and returns
## a repaired copy of the finite `CarState`, or returns `null` and leaves both
## untouched. `restore_state()` commits the canonical state immediately and
## `mirror_gear(car_state)` then repairs the mirror in a second call; that
## two-call window is not transactional, so a caller error can leave a changed
## gearbox with no paired `CarState`.
##
## Commit discipline: `propose()` advances and commits the canonical state
## immediately. Call it exactly once per accepted tick, from that car's
## committed record, and route or mirror the returned proposal before taking
## another proposal; an abandoned proposal leaves the gearbox ahead of the
## committed `CarState`. `mirror_gear()` reads only this gearbox's validated
## canonical current state and cannot bind an arbitrary `CarState` to this
## gearbox, configuration or tick, so the caller owns car identity, tick
## pairing and configuration choice. No proposal enters `mirror_gear()`, so a
## stale or foreign retained proposal cannot affect the published gear. None of
## these helpers changes physics or the physical motor; `propose()` still
## writes no `CarState` field.

const DT := 1.0 / 60.0
## Absolute tolerance for accepting a caller-supplied step size as 60 Hz.
const DT_TOLERANCE_S := 1e-6
## Hard cap on forward gears for configuration validation.
const MAX_FORWARD_GEARS := 8
## Absolute floor for the upshift/downshift separation. A config that validates
## must keep at least this much speed gap so a boundary oscillation cannot
## cross both directions within a single tick.
const MIN_HYSTERESIS_GAP_M_S := 0.25
## Slack for threshold separation comparisons.
const VALIDATION_TOLERANCE := 1e-9
## Inclusive maximum accepted shift dwell, seconds. A larger authored value is
## refused instead of silently clamped: near `1e16` an IEEE-754 double is spaced
## more than one fixed `DT` apart, so subtracting `DT` cannot change it and
## forward shifts stay locked forever. Ten seconds (600 ticks) is far above any
## plausible arcade shift lockout, so the cap costs no realistic tuning freedom
## while every accepted dwell remains countable at 60 Hz.
const MAX_SHIFT_DWELL_S := 10.0


enum ShiftDirection {
	NONE,
	UPSHIFT,
	DOWNSHIFT,
	ENTER_REVERSE,
	EXIT_REVERSE,
}


## One real gear change. `from_gear`/`to_gear` are `-1` or `1..N`; the
## direction is `ENTER_REVERSE`/`EXIT_REVERSE` for latch-driven changes and
## `UPSHIFT`/`DOWNSHIFT` for forward threshold changes. `normalized_rpm` is the
## post-change bounded indicator value.
class ShiftEvent extends RefCounted:
	var from_gear := 0
	var to_gear := 0
	var direction: ShiftDirection = ShiftDirection.NONE
	var normalized_rpm := 0.0


## Explicit, caller-supplied gearbox values. Defaults are provisional M1.1
## laboratory choices spanning the committed 0-45 m/s motor envelope; they are
## not frozen handling coefficients.
##
##   * `forward_gear_count`: number of forward gears (1..8);
##   * `upshift_speeds_m_s`: length N-1, strictly increasing speeds; leaving
##     forward gear k+1 upward requires speed strictly above element k;
##   * `downshift_speeds_m_s`: length N-1, strictly increasing speeds; leaving
##     forward gear k+2 downward requires speed strictly below element k;
##   * `min_shift_dwell_s`: minimum seconds between committed gear changes,
##     accepted in `[0, MAX_SHIFT_DWELL_S]` inclusive;
##   * `min_hysteresis_gap_m_s`: required separation between each downshift and
##     its corresponding upshift threshold (floor
##     `MIN_HYSTERESIS_GAP_M_S`);
##   * `reverse_exit_forward_speed_m_s`: forward speed at/above which a cleared
##     reverse latch releases the `-1` indication;
##   * `top_reference_speed_m_s`: upper bound used for the normalized rpm
##     indicator in top gear; must exceed the last upshift threshold.
class GearboxConfig extends RefCounted:
	var forward_gear_count := 6
	var upshift_speeds_m_s: Array[float] = [8.0, 14.0, 21.0, 29.0, 38.0]
	var downshift_speeds_m_s: Array[float] = [5.0, 10.0, 16.0, 23.0, 31.0]
	var min_shift_dwell_s := 0.25
	var min_hysteresis_gap_m_s := 0.5
	var reverse_exit_forward_speed_m_s := 0.5
	var top_reference_speed_m_s := 45.0


	func is_valid() -> bool:
		if forward_gear_count < 1 or forward_gear_count > MAX_FORWARD_GEARS:
			return false
		var expected := forward_gear_count - 1
		if upshift_speeds_m_s.size() != expected:
			return false
		if downshift_speeds_m_s.size() != expected:
			return false
		if not _non_negative_finite(min_shift_dwell_s):
			return false
		if min_shift_dwell_s > MAX_SHIFT_DWELL_S:
			return false
		if not _finite(min_hysteresis_gap_m_s):
			return false
		if min_hysteresis_gap_m_s < MIN_HYSTERESIS_GAP_M_S - VALIDATION_TOLERANCE:
			return false
		if not _non_negative_finite(reverse_exit_forward_speed_m_s):
			return false
		if not _positive_finite(top_reference_speed_m_s):
			return false

		var previous := -1.0
		for value in upshift_speeds_m_s:
			if not _finite(value) or value < 0.0 or value <= previous:
				return false
			previous = value
		previous = -1.0
		for value in downshift_speeds_m_s:
			if not _finite(value) or value < 0.0 or value <= previous:
				return false
			previous = value

		for index in range(expected):
			if (
				downshift_speeds_m_s[index] + min_hysteresis_gap_m_s
				> upshift_speeds_m_s[index] + VALIDATION_TOLERANCE
			):
				return false
		if (
			expected > 0
			and top_reference_speed_m_s <= upshift_speeds_m_s[expected - 1]
		):
			return false
		return true


	static func _finite(value: float) -> bool:
		return not is_nan(value) and not is_inf(value)


	static func _non_negative_finite(value: float) -> bool:
		return _finite(value) and value >= 0.0


	static func _positive_finite(value: float) -> bool:
		return _finite(value) and value > 0.0


## Copyable gearbox state. `shift_cooldown_s` is the remaining lockout before
## another forward shift may commit; reverse latch transitions bypass it. The
## globally valid domain bounds it to `[0, MAX_SHIFT_DWELL_S]`; a concrete
## gearbox may accept less, up to its configured `min_shift_dwell_s`.
class GearboxState extends RefCounted:
	var gear_index := 1
	var shift_cooldown_s := 0.0
	var normalized_rpm := 0.0


	func copy() -> GearboxState:
		var state := GearboxState.new()
		state.gear_index = gear_index
		state.shift_cooldown_s = shift_cooldown_s
		state.normalized_rpm = normalized_rpm
		return state


	func is_finite() -> bool:
		return (
			not is_nan(shift_cooldown_s)
			and not is_inf(shift_cooldown_s)
			and not is_nan(normalized_rpm)
			and not is_inf(normalized_rpm)
		)


	func is_valid() -> bool:
		if not self.is_finite():
			return false
		if gear_index != -1 and (gear_index < 1 or gear_index > MAX_FORWARD_GEARS):
			return false
		if shift_cooldown_s < 0.0 or shift_cooldown_s > MAX_SHIFT_DWELL_S:
			return false
		if normalized_rpm < 0.0 or normalized_rpm > 1.0:
			return false
		return true


## Result of one gearbox evaluation. `event` is `null` unless the gear changed
## this tick. The proposal copies the new state; the input `CarState` is never
## mutated.
class GearboxProposal extends RefCounted:
	var state := GearboxState.new()
	var gear_index := 1
	var normalized_rpm := 0.0
	var event: ShiftEvent = null


	func has_event() -> bool:
		return event != null


var _forward_gear_count := 0
var _upshifts: Array[float] = []
var _downshifts: Array[float] = []
var _min_shift_dwell_s := 0.0
var _reverse_exit_forward_speed_m_s := 0.0
var _top_reference_speed_m_s := 0.0
var _state := GearboxState.new()


## Create a gearbox from explicit configuration. Returns `null` for a null or
## invalid config. The configuration values are copied, so later mutation of the
## caller's object cannot change or invalidate a live gearbox.
static func create(config: GearboxConfig) -> AutomaticGearbox:
	if config == null or not config.is_valid():
		return null
	var gearbox := AutomaticGearbox.new()
	gearbox._forward_gear_count = config.forward_gear_count
	gearbox._upshifts = config.upshift_speeds_m_s.duplicate()
	gearbox._downshifts = config.downshift_speeds_m_s.duplicate()
	gearbox._min_shift_dwell_s = config.min_shift_dwell_s
	gearbox._reverse_exit_forward_speed_m_s = config.reverse_exit_forward_speed_m_s
	gearbox._top_reference_speed_m_s = config.top_reference_speed_m_s
	gearbox.reset()
	return gearbox


## Deterministic lifecycle reset: gear 1, dwell ready, rpm zero. No RNG, clock
## or input is consulted.
func reset() -> void:
	_state = GearboxState.new()


## Atomically replace the canonical state with a validated copy of `state`.
## The copy is taken only after validation, so an invalid input leaves this
## gearbox unchanged and the caller's object is never shared. A valid state is
## finite, has gear `-1` or `1..forward_gear_count` for this configuration,
## dwell in `[0, min_shift_dwell_s]` (never above `MAX_SHIFT_DWELL_S`), and
## rpm in `[0, 1]`. Returns `false` for null or invalid input.
func restore_state(state: GearboxState) -> bool:
	if not _is_restorable_state(state):
		return false
	_state = state.copy()
	return true


## Read-only copy of the current gearbox state.
func get_state() -> GearboxState:
	return _state.copy()


## Return a copy of `car_state` whose `gear_index` mirrors this gearbox's
## canonical current gear, or `null` when the mirror cannot be published.
## Only the gearbox's own canonical state is read: no proposal enters this
## API, so a stale or foreign proposal cannot affect the result. The canonical
## state and the input record are both validated; a null or nonfinite
## `car_state` is refused. Call immediately after a successful `propose()` or
## `restore_state()`. Neither the input record nor this gearbox is mutated,
## and the returned record does not share storage with either.
func mirror_gear(car_state: CarState) -> CarState:
	if car_state == null or not car_state.is_finite():
		return null
	if not _is_restorable_state(_state):
		return null
	var mirrored := car_state.copy()
	mirrored.gear_index = _state.gear_index
	return mirrored


## All-or-nothing checkpoint convenience. Validates `candidate_state` against
## this gearbox's configuration and `car_state` as a finite committed record
## before mutating anything. On success it commits a copy of the candidate as
## the canonical state and returns a repaired copy of `car_state` whose
## `gear_index` mirrors that gear. On refusal (null candidate, invalid
## candidate for this configuration, null car, or nonfinite car) it returns
## `null` and leaves both this gearbox's canonical state and the input
## `car_state` unchanged. Prefer this over separate `restore_state()` plus
## `mirror_gear()` calls when the pair must be applied together; see the header
## note that `propose()` commits immediately and `mirror_gear()` alone cannot
## bind car identity or tick.
func restore_and_mirror(candidate_state: GearboxState, car_state: CarState) -> CarState:
	if not _is_restorable_state(candidate_state):
		return null
	if car_state == null or not car_state.is_finite():
		return null
	var mirrored := car_state.copy()
	mirrored.gear_index = candidate_state.gear_index
	_state = candidate_state.copy()
	return mirrored


## Machine-readable state snapshot for replay/immutability comparisons.
func snapshot() -> Dictionary:
	return {
		"gear_index": _state.gear_index,
		"shift_cooldown_s": _state.shift_cooldown_s,
		"normalized_rpm": _state.normalized_rpm,
	}


## Snapshot of the copied configuration actually in force.
func config_snapshot() -> Dictionary:
	return {
		"forward_gear_count": _forward_gear_count,
		"upshift_speeds_m_s": _upshifts.duplicate(),
		"downshift_speeds_m_s": _downshifts.duplicate(),
		"min_shift_dwell_s": _min_shift_dwell_s,
		"reverse_exit_forward_speed_m_s": _reverse_exit_forward_speed_m_s,
		"top_reference_speed_m_s": _top_reference_speed_m_s,
	}


## Evaluate one fixed 60 Hz gearbox tick. Returns `null` for null input, any
## nonfinite numeric field of the committed `CarState` record (checked with
## `CarState.is_finite()` before anything is derived), or a step size that is
## not the declared 60 Hz tick. A refusal leaves this gearbox unchanged; a
## valid call advances the owned state and returns a proposal.
func propose(car_state: CarState, dt: float = DT) -> GearboxProposal:
	if car_state == null:
		return null
	# Honor the full committed-record contract: position and the inert seams
	# are validated too, even though only motion and the reverse latch are
	# consumed below.
	if not car_state.is_finite():
		return null
	if not _finite(dt) or dt <= 0.0 or absf(dt - DT) > DT_TOLERANCE_S:
		return null
	# `is_finite()` rejects nonfinite inputs, but a dot product of very large
	# finite values can still overflow; keep the derived guard.
	var forward_speed := car_state.forward_speed_m_s()
	if not _finite(forward_speed):
		return null

	var latched_reverse := car_state.reverse_engaged
	var previous_gear := _state.gear_index
	var new_gear := previous_gear
	var direction := ShiftDirection.NONE
	var speed_abs := absf(forward_speed)

	if latched_reverse:
		# The committed latch alone selects reverse. Signed velocity, including
		# positive travel, neither engages nor releases the reverse indication.
		if previous_gear != -1:
			new_gear = -1
			direction = ShiftDirection.ENTER_REVERSE
	elif previous_gear == -1:
		# Release needs the cleared latch AND forward travel past the exit
		# speed. Backward roll after release cannot reselect reverse here.
		if forward_speed >= _reverse_exit_forward_speed_m_s:
			new_gear = _select_forward_gear(speed_abs)
			direction = ShiftDirection.EXIT_REVERSE
	else:
		var target := _select_forward_gear(speed_abs)
		if target != previous_gear and _state.shift_cooldown_s <= 0.0:
			new_gear = target
			direction = (
				ShiftDirection.UPSHIFT
				if target > previous_gear
				else ShiftDirection.DOWNSHIFT
			)

	var rpm := _normalized_rpm(new_gear, speed_abs)
	if not _finite(rpm):
		return null

	_state.gear_index = new_gear
	_state.normalized_rpm = rpm
	if new_gear != previous_gear:
		_state.shift_cooldown_s = _min_shift_dwell_s
	else:
		_state.shift_cooldown_s = maxf(_state.shift_cooldown_s - dt, 0.0)

	var proposal := GearboxProposal.new()
	proposal.state = _state.copy()
	proposal.gear_index = new_gear
	proposal.normalized_rpm = rpm
	if new_gear != previous_gear:
		var event := ShiftEvent.new()
		event.from_gear = previous_gear
		event.to_gear = new_gear
		event.direction = direction
		event.normalized_rpm = rpm
		proposal.event = event
	return proposal


func _is_restorable_state(state: GearboxState) -> bool:
	if state == null:
		return false
	if not state.is_finite():
		return false
	if state.gear_index != -1 and (
		state.gear_index < 1 or state.gear_index > _forward_gear_count
	):
		return false
	if state.shift_cooldown_s < 0.0 or state.shift_cooldown_s > _min_shift_dwell_s:
		return false
	if state.normalized_rpm < 0.0 or state.normalized_rpm > 1.0:
		return false
	return true



## Forward target gear from the speed magnitude, anchored at the current gear.
## The scan stops at the first threshold crossed in either direction, and the
## validated hysteresis bands make a shift permanent until speed leaves the
## opposite threshold.
func _select_forward_gear(speed_abs: float) -> int:
	var target := _state.gear_index
	if target < 1:
		target = 1
	while target < _forward_gear_count and speed_abs > _upshifts[target - 1]:
		target += 1
	while target > 1 and speed_abs < _downshifts[target - 2]:
		target -= 1
	return target


## Bounded normalized rpm for a gear band. Forward gear 1 starts at zero, each
## higher gear starts at its downshift threshold, non-top gears end at their
## upshift threshold and top gear ends at the configured top reference. Reverse
## uses the full reference span. The result is clamped to `[0, 1]`.
func _normalized_rpm(gear_index: int, speed_abs: float) -> float:
	var low := 0.0
	var high := _top_reference_speed_m_s
	if gear_index >= 1:
		if gear_index >= 2:
			low = _downshifts[gear_index - 2]
		if gear_index <= _forward_gear_count - 1:
			high = _upshifts[gear_index - 1]
	if high <= low:
		return 1.0 if speed_abs >= high else 0.0
	return clampf((speed_abs - low) / (high - low), 0.0, 1.0)


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
