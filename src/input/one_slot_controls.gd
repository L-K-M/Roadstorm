class_name OneSlotControls
extends RefCounted
## Normalizes raw, already-routed inputs for one local player slot.
##
## This is the reusable per-slot seam described by PLAN.md M1.1/M3.1 and
## docs/TECHNICAL_DESIGN.md:139. It receives raw steering, throttle, brake,
## handbrake and reset values that an adapter has already routed to this slot;
## it performs no device discovery, ownership, remapping or persistence.
## Call `sample()` once per fixed physics tick with the raw values and the
## elapsed tick time. Each successful call returns a fresh `DriverCommand`;
## invalid input returns `null`.
##
## Steering has two distinguishable raw sources so WASD/arrows and a stick can
## feed the same slot later:
##   * `p_steer` is the analog axis in [-1, 1], positive right. Magnitudes at
##     or below `steer_deadzone` become 0. Above the deadzone the normalized
##     remainder is multiplied by `steer_sensitivity` and clamped to [-1, 1]:
##       magnitude = (|p_steer| - deadzone) / (1 - deadzone)
##       steer = sign(p_steer) * clamp(magnitude * sensitivity, 0, 1)
##   * `p_steer_left` / `p_steer_right` are digital buttons. Their target is
##     -1, 0 or +1 (both pressed cancels to 0). The stored value moves toward
##     the target by at most `digital_ramp_per_second * p_dt`, so press,
##     release and reversal are all rate-limited.
##
## Output selection: while a digital button is held, or while the stored
## digital value is still returning to center after release, the digital value
## drives `steer`; otherwise the normalized analog axis does. A digital press
## therefore overrides a deflected stick, and a stick deflection takes over
## again only after the digital ramp reaches exactly 0.
##
## `reset_requested` is a rising edge: true only on a tick where
## `p_reset_pressed` changed from false to true. Holding the button emits one
## request, not a stream. `clear_lifecycle_state()` discards the digital ramp.
## If the stored reset level was held, it also arms a fresh-press requirement:
## that same continuing hold emits nothing until it is released and pressed
## again. A press that begins after the clear emits normally. Together these
## rules keep held values and stale edges from surviving a focus loss, pause,
## reassignment or reconnect.
##
## Validation is atomic: `p_dt` must be finite and nonnegative (zero is
## allowed), and all four analog raw values must be finite. An invalid call
## returns `null` and leaves the stored ramp and reset level untouched. Valid
## finite values outside their normalized ranges are clamped by
## `DriverCommand.create()`, preserving its contract.
##
## Defaults (`steer_deadzone` 0.15, `steer_sensitivity` 1.0, ramp 4.0/s) are
## provisional starting points pending M3 device profiles and play testing;
## `configure()` applies a validated set atomically and returns false without
## changing anything when any value is invalid.
##
## Scope limits: no device enumeration, player-slot ownership, joining,
## remapping, saved presets, assists, reverse/brake rules, gears or camera/
## menu actions. Those belong to later M1/M3 slices and adapters.

## Provisional default analog deadzone in [0, 1).
const DEFAULT_STEER_DEADZONE := 0.15
## Provisional default analog sensitivity multiplier, > 0.
const DEFAULT_STEER_SENSITIVITY := 1.0
## Provisional default digital steering ramp rate in full-lock units/second.
const DEFAULT_DIGITAL_RAMP_PER_SECOND := 4.0

var _steer_deadzone := DEFAULT_STEER_DEADZONE
var _steer_sensitivity := DEFAULT_STEER_SENSITIVITY
var _digital_ramp_per_second := DEFAULT_DIGITAL_RAMP_PER_SECOND
var _digital_steer := 0.0
var _reset_held := false
var _reset_suppress_until_release := false


## Replace all tuning values atomically. Returns false and changes nothing
## when any value is nonfinite or out of range: deadzone in [0, 1),
## sensitivity > 0, ramp rate > 0.
func configure(
	p_steer_deadzone: float,
	p_steer_sensitivity: float,
	p_digital_ramp_per_second: float
) -> bool:
	if not _is_finite(p_steer_deadzone):
		return false
	if not _is_finite(p_steer_sensitivity) or p_steer_sensitivity <= 0.0:
		return false
	if not _is_finite(p_digital_ramp_per_second) or p_digital_ramp_per_second <= 0.0:
		return false
	if p_steer_deadzone < 0.0 or p_steer_deadzone >= 1.0:
		return false
	_steer_deadzone = p_steer_deadzone
	_steer_sensitivity = p_steer_sensitivity
	_digital_ramp_per_second = p_digital_ramp_per_second
	return true


func get_steer_deadzone() -> float:
	return _steer_deadzone


func get_steer_sensitivity() -> float:
	return _steer_sensitivity


func get_digital_ramp_per_second() -> float:
	return _digital_ramp_per_second


## Discard held steering/reset state. Call on focus loss, pause,
## reassignment or reconnect, before the next tick. A reset input held at the
## last sample keeps its held level for edge purposes until release, so a
## continuing hold is not a new press; a genuinely new press after the clear
## emits normally. Repeated clears keep an armed fresh-press requirement until
## release. Tuning values persist.
func clear_lifecycle_state() -> void:
	_digital_steer = 0.0
	if not _reset_suppress_until_release:
		_reset_suppress_until_release = _reset_held
	_reset_held = false


## Normalize one tick of already-routed raw input into a fresh command.
## Returns `null` when `p_dt` is nonfinite/negative or any analog raw value is
## nonfinite; stored state is left unchanged on rejection.
func sample(
	p_steer: float,
	p_throttle: float,
	p_brake: float,
	p_handbrake: float,
	p_reset_pressed: bool,
	p_dt: float,
	p_steer_left: bool = false,
	p_steer_right: bool = false
) -> DriverCommand:
	if not _is_finite(p_dt) or p_dt < 0.0:
		return null
	if not _four_finite(p_steer, p_throttle, p_brake, p_handbrake):
		return null

	var digital_candidate := move_toward(
		_digital_steer,
		_digital_target(p_steer_left, p_steer_right),
		_digital_ramp_per_second * p_dt
	)
	var reset_edge := false
	var next_reset_held := _reset_held
	var next_suppress := _reset_suppress_until_release
	if next_suppress:
		next_reset_held = p_reset_pressed
		if not p_reset_pressed:
			next_suppress = false
	else:
		reset_edge = p_reset_pressed and not _reset_held
		next_reset_held = p_reset_pressed

	var steer: float
	if p_steer_left or p_steer_right or digital_candidate != 0.0:
		steer = digital_candidate
	else:
		steer = _normalize_analog_steer(p_steer)

	var command := DriverCommand.create(
		steer, p_throttle, p_brake, p_handbrake, reset_edge
	)
	if command == null:
		return null

	_digital_steer = digital_candidate
	_reset_held = next_reset_held
	_reset_suppress_until_release = next_suppress
	return command


func _digital_target(p_left: bool, p_right: bool) -> float:
	if p_left and not p_right:
		return -1.0
	if p_right and not p_left:
		return 1.0
	return 0.0


func _normalize_analog_steer(p_value: float) -> float:
	var magnitude := absf(p_value)
	if magnitude <= _steer_deadzone:
		return 0.0
	magnitude = (magnitude - _steer_deadzone) / (1.0 - _steer_deadzone)
	return signf(p_value) * clampf(magnitude * _steer_sensitivity, 0.0, 1.0)


static func _four_finite(a: float, b: float, c: float, d: float) -> bool:
	return _is_finite(a) and _is_finite(b) and _is_finite(c) and _is_finite(d)


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
