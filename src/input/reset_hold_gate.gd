class_name ResetHoldGate
extends RefCounted
## Pure one-second reset hold gate for the M1.1 input seam.
##
## Consumes normalized `DriverCommand` levels once per fixed tick and exposes a
## single latched reset action. The gate fires exactly once after a continuous
## `HOLD_SECONDS_S` of eligible `reset_held` level, matching the explicit
## one-second hold in docs/GAME_DESIGN.md:49. Releasing early clears progress;
## holding after firing never repeats; releasing and pressing again rearms.
##
## The gate keys on `reset_held`, never on the `reset_requested` press edge, so
## a stale edge cannot advance or fire it. Invalid input is refused atomically:
## a nonfinite or negative dt, a null command, or a command that fails
## `is_normalized()` returns false without changing accumulated progress or the
## fired latch. Zero dt is valid but neither advances nor fires. Call
## `clear_lifecycle_state()` on focus loss, pause, reassignment or reconnect to
## cancel progress.
##
## Scope limits: this component times the hold only. It does not place a car,
## choose a route anchor, mutate a body, integrate RaceSession, or implement the
## Practice pause menu's immediate reset path, which remains a separate future
## caller. No M1 acceptance claim.

## Continuous eligible held time required before the action fires.
const HOLD_SECONDS_S := 1.0

var _progress_s := 0.0
var _fired := false


## Cancel accumulated progress and rearm the gate. Tuning-free counterpart of
## the input layer's lifecycle clear; callers should invoke both together.
func clear_lifecycle_state() -> void:
	_progress_s = 0.0
	_fired = false


## Advance the gate by one tick.
##
## `p_command` must be a finite, normalized `DriverCommand`; `p_dt` must be
## finite and nonnegative. Returns true only on the tick where a continuous
## eligible hold first reaches `HOLD_SECONDS_S`. Invalid input returns false and
## leaves all gate state unchanged.
func sample(p_command: DriverCommand, p_dt: float) -> bool:
	if not _is_valid_dt(p_dt):
		return false
	if p_command == null or not p_command.is_normalized():
		return false

	if not p_command.reset_held:
		_progress_s = 0.0
		_fired = false
		return false
	if _fired:
		return false
	if p_dt > 0.0:
		_progress_s += p_dt
		if _progress_s >= HOLD_SECONDS_S:
			_fired = true
			return true
	return false


static func _is_valid_dt(p_dt: float) -> bool:
	return not is_nan(p_dt) and not is_inf(p_dt) and p_dt >= 0.0
