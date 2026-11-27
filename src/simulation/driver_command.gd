class_name DriverCommand
extends RefCounted
## Normalized driver command sampled once per physics tick.
##
## Contract (docs/TECHNICAL_DESIGN.md:61, docs/GAME_DESIGN.md:9,49):
##   * `steer` is normalized to [-1, 1]; positive turns right in the road plane;
##   * `throttle`, `brake` and `handbrake` are normalized to [0, 1];
##   * `reset_requested` is the press edge exposed by this M1.1 slice;
##   * `reset_held` is the held level that lets a later reset policy time the
##     design's explicit one-second hold. Other edge actions belong to later
##     slices.
##
## Values are clamped to their declared ranges. Nonfinite inputs are refused:
## `create()` returns `null` and `set_from_raw()` returns `false`. A rejected
## update leaves every stored field, including both reset flags, untouched. The
## pure motor never repairs an invalid command silently.
##
## Steering ramps, deadzones, sensitivity and device mapping are InputRouter /
## driver-layer concerns (docs/GAME_DESIGN.md:11-13); they are intentionally
## not part of this structure so the pure kernel receives a validated value.
## `handbrake` is accepted and clamped but inert in this slice: drift entry is
## reserved for M1.3 and later (see `ArcadeMotor`).

## Positive steers right in the road plane.
var steer := 0.0
## Normalized forward throttle in [0, 1].
var throttle := 0.0
## Normalized brake/reverse control in [0, 1].
var brake := 0.0
## Normalized handbrake in [0, 1]; inert in this M1.1 slice.
var handbrake := 0.0
## Press edge for reset (M1.1 slice: flag only; no body mutation here).
## True only on the tick where the input layer observes a fresh press.
var reset_requested := false
## Held reset level (M1.1 slice: flag only; no body mutation here). True while
## an eligible fresh press is held, false while released or suppressed after a
## lifecycle clear. Later reset integration can accumulate this level to time
## the explicit one-second hold from docs/GAME_DESIGN.md:49.
var reset_held := false


## Build a validated command. Returns `null` when any value is nonfinite.
static func create(
	p_steer := 0.0,
	p_throttle := 0.0,
	p_brake := 0.0,
	p_handbrake := 0.0,
	p_reset_requested := false,
	p_reset_held := false
) -> DriverCommand:
	var command := DriverCommand.new()
	if not command.set_from_raw(
		p_steer, p_throttle, p_brake, p_handbrake, p_reset_requested, p_reset_held
	):
		return null
	return command


## Validate and store raw values. Finite values are clamped; nonfinite values
## make the whole command invalid and leave the previous stored values intact.
func set_from_raw(
	p_steer: float,
	p_throttle: float,
	p_brake: float,
	p_handbrake: float,
	p_reset_requested: bool,
	p_reset_held := false
) -> bool:
	# Both reset flags are booleans: they have no range to clamp and no
	# nonfinite value to refuse. Assigning them only after the analog values
	# validate keeps the whole update atomic.
	if not _four_finite(p_steer, p_throttle, p_brake, p_handbrake):
		return false
	steer = clampf(p_steer, -1.0, 1.0)
	throttle = clampf(p_throttle, 0.0, 1.0)
	brake = clampf(p_brake, 0.0, 1.0)
	handbrake = clampf(p_handbrake, 0.0, 1.0)
	reset_requested = p_reset_requested
	reset_held = p_reset_held
	return true


func is_finite() -> bool:
	return _four_finite(steer, throttle, brake, handbrake)


## True when the command is finite and inside its declared normalized ranges.
## The motor refuses values outside these ranges even if a caller assigned the
## fields directly instead of using `create()`/`set_from_raw()`.
func is_normalized() -> bool:
	if not self.is_finite():
		return false
	const limit := 1.0 + 1e-9
	return (
		absf(steer) <= limit
		and throttle >= -1e-9
		and throttle <= limit
		and brake >= -1e-9
		and brake <= limit
		and handbrake >= -1e-9
		and handbrake <= limit
		and typeof(reset_requested) == TYPE_BOOL
		and typeof(reset_held) == TYPE_BOOL
	)


func copy() -> DriverCommand:
	var command := DriverCommand.new()
	command.steer = steer
	command.throttle = throttle
	command.brake = brake
	command.handbrake = handbrake
	command.reset_requested = reset_requested
	command.reset_held = reset_held
	return command


static func _four_finite(a: float, b: float, c: float, d: float) -> bool:
	return _is_finite(a) and _is_finite(b) and _is_finite(c) and _is_finite(d)


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
