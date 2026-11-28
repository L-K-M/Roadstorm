class_name WallContactPolicy
extends RefCounted
## Provisional M1.8 wall-contact episode policy (pure component).
##
## This is the provisional wall-contact emission policy proposed in
## `work/agents/coordinator/m18-contact-policy-longcat-20261128/report.md`
## sections 2-4. It is a pure decision component: it owns no `Node`, no clock,
## no scene, no physics body, no ledger and no laboratory type. All per-car
## episode state travels inside an immutable-ish `PolicyState` value that the
## caller supplies and receives back, so a future race coordinator, DriveLab or
## a headless test can all drive the same state machine without sharing mutable
## globals.
##
## Authority boundary (report section 2.1). `WallImpactProducer` stays a pure
## per-witness mapper and keeps publishing a legal exact-zero severity event;
## this policy decides whether a witness enters the cosmetic event stream at
## all. Nothing here writes to `ImpactEvent.Ledger`, allocates a shared car-car
## `contact_id`, reads the adapter, or advances simulation. The caller remains
## responsible for the accepted-object/tick/fingerprint gates that decide which
## committed witness is authoritative in the first place.
##
## The public entry points are `new_state()`, `evaluate()`, `retire()`,
## `decision_name()` and `refusal_name()`. `evaluate()` is a pure function of
## `(prior state, committed-tick input) -> (new state, decision, identity)`.
##
## Provisional constants (report section 2.2; every value is a cosmetic
## heuristic, not a physics result):
##
##   * `PUBLISH_FLOOR_M_S` 0.5 m/s: onset publish floor. 94% of measured
##     grind witnesses sit below it, so it removes the measured noise tail.
##   * `REPEAT_DELTA_M_S` 2.0 m/s: repeat publish floor, equal to the design's
##     loosen threshold (`docs/GAME_DESIGN.md:57`), so a published repeat
##     always has cosmetic meaning.
##   * `MIN_REPEAT_SPACING_TICKS` 30 ticks (0.5 s at 60 Hz): the design's
##     per-car effect cooldown; caps the severe-repeat rate per episode.
##   * `MAX_CONTACT_GAP_TICKS` 6 ticks (0.1 s): bridges solver dropouts without
##     merging clearly separate contacts.
##   * `NORMAL_COMPAT_ANGLE_DEG` 35 degrees: uncalibrated continuity tolerance
##     for the road-plane response normal. It must be replaced by pinned corner
##     measurements before M1.8 closure (report sections 4 and 6).
##
## Documented limits, stated honestly:
##
##   * Episode continuity is heuristic. There is no persistent wall or contact
##     identity in the adapter (report section 6, gap 1), so sliding along
##     collinear segments, crossing a joint or moving between similar faces can
##     merge or split episodes incorrectly.
##   * Identity is a naming convention, not a new contract field. `event_id`
##     carries `<prefix>.<scope_generation>.<episode_seq>.<event_seq>` and
##     `episode_key` carries `<scope_generation>:<episode_seq>`. `contact_id`
##     is always the empty string: it is reserved for pairing the two car-car
##     perspectives, and `ImpactEvent.Ledger` refuses a second retained record
##     with the same nonempty (`contact_id`, `primary_car_id`) pair, so a
##     multi-event wall session must not reuse it. A first-class episode field
##     would need contract review (report section 6, gap 3).
##   * Suppression changes what a cosmetic consumer accumulates. A continuous
##     grind is presented as one physical contact whose meaningful hits are the
##     onset plus spaced severe repeats. Whether raw grind accumulation must
##     count is a product decision that is not written down yet.
##   * The policy cannot see physics. `has_wall_witness`, `severity_m_s` and
##     `response_normal` are trusted caller inputs; the adapter's one-winner
##     wall selection per tick means a multi-contact tick's race-level event
##     count is undefined here.
##   * This component is not M1.8 acceptance and has no cosmetic consumer yet.

## Provisional onset publish floor, metres per second.
const PUBLISH_FLOOR_M_S := 0.5
## Provisional repeat publish floor, metres per second.
const REPEAT_DELTA_M_S := 2.0
## Provisional minimum spacing between published repeats in one episode.
const MIN_REPEAT_SPACING_TICKS := 30
## Provisional maximum no-witness gap inside one episode, in ticks.
const MAX_CONTACT_GAP_TICKS := 6
## Provisional response-normal compatibility angle, degrees.
const NORMAL_COMPAT_ANGLE_DEG := 35.0
## Default `event_id` prefix when the caller supplies none.
const DEFAULT_EVENT_ID_PREFIX := "wall_event"

## Angle comparison slack, degrees. Keeps a boundary-normal decision stable
## against the last bits of an `acos` round trip.
const NORMAL_COMPAT_ANGLE_EPSILON_DEG := 1.0e-9
## A supplied response normal shorter than this is treated as degenerate.
const NORMAL_MIN_LENGTH := 1.0e-6

## Sentinel for a region the caller did not supply. Mirrors the ordering of
## `ImpactEvent.ContactRegion` without depending on that type.
const REGION_UNSET := -1
## Sentinel meaning "inherit the scope generation from the policy state".
const SCOPE_GENERATION_INHERIT := -1

## Recognised region names, parallel to `ImpactEvent.REGION_NAMES`.
const REGION_NAMES: Array[String] = ["front", "rear", "left", "right"]

## Committed-tick input keys. `make_input()` builds a well-formed dictionary;
## `evaluate()` reads exactly these keys.
const INPUT_PRIMARY_CAR_ID := "primary_car_id"
const INPUT_TICK_INDEX := "tick_index"
const INPUT_HAS_WALL_WITNESS := "has_wall_witness"
const INPUT_SEVERITY_M_S := "severity_m_s"
const INPUT_RESPONSE_NORMAL := "response_normal"
const INPUT_OTHER_CAR_ID := "other_car_id"
const INPUT_REGION := "region"
const INPUT_EVENT_ID_PREFIX := "event_id_prefix"
const INPUT_SCOPE_GENERATION := "scope_generation"
## Keys every input must carry. `evaluate()` refuses anything else as an
## unknown key, so the contract is closed.
const REQUIRED_INPUT_KEYS: Array[String] = [
	INPUT_PRIMARY_CAR_ID,
	INPUT_TICK_INDEX,
	INPUT_HAS_WALL_WITNESS,
	INPUT_SEVERITY_M_S,
	INPUT_RESPONSE_NORMAL,
]
const INPUT_KEYS: Array[String] = [
	INPUT_PRIMARY_CAR_ID,
	INPUT_TICK_INDEX,
	INPUT_HAS_WALL_WITNESS,
	INPUT_SEVERITY_M_S,
	INPUT_RESPONSE_NORMAL,
	INPUT_OTHER_CAR_ID,
	INPUT_REGION,
	INPUT_EVENT_ID_PREFIX,
	INPUT_SCOPE_GENERATION,
]


## What the caller should do with one committed tick for one primary car.
##
## Exactly one of `PUBLISH_ONSET`, `PUBLISH_REPEAT` and `PASS_THROUGH` carries a
## nonempty `event_id`. The suppressing and non-contact decisions carry none,
## because a suppressed tick allocates no event ID and writes no ledger entry.
enum Decision {
	## No witness and no open episode: nothing happened, nothing to do.
	NONE = 0,
	## Witness below the onset floor: an episode opened, nothing published.
	SUPPRESS_ONSET,
	## Witness at or above the onset floor: a new episode published its onset.
	PUBLISH_ONSET,
	## Continuing episode, witness did not qualify: nothing published.
	SUPPRESS_REPEAT,
	## Continuing episode, witness qualified: a spaced repeat published.
	PUBLISH_REPEAT,
	## No witness, episode still inside the gap budget: keep observing.
	CONTINUE_OBSERVING,
	## No witness and the gap budget expired: the episode closed this tick.
	EPISODE_CLOSED,
	## Nonempty `other_car_id`: not a wall contact, wall state untouched.
	PASS_THROUGH,
}

const DECISION_NAMES := {
	Decision.NONE: "none",
	Decision.SUPPRESS_ONSET: "suppress_onset",
	Decision.PUBLISH_ONSET: "publish_onset",
	Decision.SUPPRESS_REPEAT: "suppress_repeat",
	Decision.PUBLISH_REPEAT: "publish_repeat",
	Decision.CONTINUE_OBSERVING: "continue_observing",
	Decision.EPISODE_CLOSED: "episode_closed",
	Decision.PASS_THROUGH: "pass_through",
}

## Stable refusal codes. Every refusal also carries `code_name`, a readable
## `error`, a structured `diagnostic`, and a state that is content-identical to
## the prior state: a refusal never applies a partial update.
enum Refusal {
	NONE = 0,
	BAD_STATE,
	BAD_INPUT,
	BAD_CAR_ID,
	BAD_TICK_INDEX,
	BAD_SEVERITY,
	BAD_RESPONSE_NORMAL,
	BAD_REGION,
	BAD_EVENT_ID_PREFIX,
	BAD_SCOPE_GENERATION,
	TICK_OUT_OF_ORDER,
	CONFLICTING_SAME_TICK_INPUT,
	SCOPE_GENERATION_MISMATCH,
	SCOPE_GENERATION_REGRESSED,
}

const REFUSAL_NAMES := {
	Refusal.NONE: "none",
	Refusal.BAD_STATE: "bad_state",
	Refusal.BAD_INPUT: "bad_input",
	Refusal.BAD_CAR_ID: "bad_car_id",
	Refusal.BAD_TICK_INDEX: "bad_tick_index",
	Refusal.BAD_SEVERITY: "bad_severity",
	Refusal.BAD_RESPONSE_NORMAL: "bad_response_normal",
	Refusal.BAD_REGION: "bad_region",
	Refusal.BAD_EVENT_ID_PREFIX: "bad_event_id_prefix",
	Refusal.BAD_SCOPE_GENERATION: "bad_scope_generation",
	Refusal.TICK_OUT_OF_ORDER: "tick_out_of_order",
	Refusal.CONFLICTING_SAME_TICK_INPUT: "conflicting_same_tick_input",
	Refusal.SCOPE_GENERATION_MISMATCH: "scope_generation_mismatch",
	Refusal.SCOPE_GENERATION_REGRESSED: "scope_generation_regressed",
}

const COUNTER_KEYS: Array[String] = [
	"contact_ticks",
	"published_events",
	"suppressed_low_delta",
	"suppressed_onset",
	"suppressed_repeat",
	"episodes_opened",
	"episodes_closed",
	"observing_ticks",
	"idle_ticks",
]


## Per-primary-car wall episode state. One instance per car id inside
## `PolicyState.cars`; it is always copied, never shared.
class CarEpisodeState extends RefCounted:
	## Scope generation this car's sequences belong to.
	var scope_generation := 0
	## Whether an episode is currently open for this car.
	var episode_active := false
	## Last allocated episode sequence inside this scope generation.
	var episode_counter := -1
	## Sequence of the open episode; -1 while inactive.
	var episode_seq := -1
	## Last allocated event sequence inside the open episode; -1 until the
	## first published event of the episode.
	var event_seq := -1
	## Whether the open episode has published at least one event. Drives the
	## repeat-spacing test: a suppressed onset still allows the first
	## qualifying repeat to publish as `event_seq = 0`.
	var published_in_episode := false
	## Committed tick of the most recent wall witness.
	var last_contact_tick := -1
	## Normalized road-plane response normal of that witness.
	var last_normal := Vector3.ZERO
	## Tick of the most recent published event in this episode; -1 if none.
	var last_publish_tick := -1
	## Highest committed tick already evaluated for this car. The ordering
	## watermark and the same-tick idempotency key.
	var last_tick := -1
	## Normalized input of the last evaluated tick, for exact retry detection.
	var last_input: Dictionary = {}
	## Decision and identity produced for that tick, replayed verbatim on an
	## identical retry.
	var last_decision := Decision.NONE
	var last_identity: Dictionary = {}
	## Cumulative counters for this car. They are lifetime totals and are not
	## reset by `retire()`; a caller that wants per-scope telemetry diffs them.
	var counters: Dictionary = WallContactPolicy._new_counters()

	func copy() -> CarEpisodeState:
		var cloned := CarEpisodeState.new()
		cloned.scope_generation = scope_generation
		cloned.episode_active = episode_active
		cloned.episode_counter = episode_counter
		cloned.episode_seq = episode_seq
		cloned.event_seq = event_seq
		cloned.published_in_episode = published_in_episode
		cloned.last_contact_tick = last_contact_tick
		cloned.last_normal = last_normal
		cloned.last_publish_tick = last_publish_tick
		cloned.last_tick = last_tick
		cloned.last_input = last_input.duplicate()
		cloned.last_decision = last_decision
		cloned.last_identity = last_identity.duplicate()
		cloned.counters = counters.duplicate()
		return cloned

	func to_dictionary() -> Dictionary:
		return {
			"scope_generation": scope_generation,
			"episode_active": episode_active,
			"episode_counter": episode_counter,
			"episode_seq": episode_seq,
			"event_seq": event_seq,
			"published_in_episode": published_in_episode,
			"last_contact_tick": last_contact_tick,
			"last_normal": WallContactPolicy._vector_to_array(last_normal),
			"last_publish_tick": last_publish_tick,
			"last_tick": last_tick,
			"counters": counters.duplicate(),
		}

	func bump(counter: String) -> void:
		if counters.has(counter):
			counters[counter] = int(counters[counter]) + 1

	func episode_key() -> String:
		if not episode_active:
			return ""
		return "%d:%d" % [scope_generation, episode_seq]


## All per-car wall episode state for one scope generation.
##
## A scope generation is one configured laboratory/race scope. `retire()`
## advances it and closes every open episode, so identity keys are never
## reused across scopes.
class PolicyState extends RefCounted:
	var scope_generation := 0
	var cars: Dictionary = {}

	func copy() -> PolicyState:
		var cloned := PolicyState.new()
		cloned.scope_generation = scope_generation
		cloned.cars = {}
		for car_id in cars:
			var car: CarEpisodeState = cars[car_id]
			cloned.cars[car_id] = car.copy() if car != null else null
		return cloned

	func car_ids() -> Array[String]:
		var ids: Array[String] = []
		for car_id in cars:
			ids.append(str(car_id))
		ids.sort()
		return ids

	## Cumulative counters summed over every car seen so far.
	func counters() -> Dictionary:
		var totals := WallContactPolicy._new_counters()
		for car_id in cars:
			var car: CarEpisodeState = cars[car_id]
			if car == null:
				continue
			for key in COUNTER_KEYS:
				totals[key] = int(totals[key]) + int(car.counters.get(key, 0))
		return totals

	func to_dictionary() -> Dictionary:
		var car_records := {}
		for car_id in cars:
			var car: CarEpisodeState = cars[car_id]
			car_records[str(car_id)] = car.to_dictionary() if car != null else {}
		return {
			"schema": POLICY_STATE_SCHEMA,
			"scope_generation": scope_generation,
			"counters": counters(),
			"cars": car_records,
		}


## Schema tag for the serialized state view. Informational only: the state is
## not a persisted contract and is not validated against a schema document.
const POLICY_STATE_SCHEMA := "roadstorm.wall_contact_policy.state.v1"


# --- Public API --------------------------------------------------------------


## A fresh state for one scope generation.
static func new_state(p_scope_generation := 0) -> PolicyState:
	var state := PolicyState.new()
	state.scope_generation = _validated_generation(p_scope_generation)
	return state


## Build a well-formed committed-tick input dictionary.
##
## `response_normal` is the road-plane projected normal actually used by the
## wall response, exactly as `WallImpactProducer` publishes it; it is
## normalized here and compared bit-exactly for retry detection.
static func make_input(
	p_primary_car_id: String,
	p_tick_index: int,
	p_has_wall_witness: bool,
	p_severity_m_s: float,
	p_response_normal: Vector3,
	p_other_car_id := "",
	p_region := REGION_UNSET,
	p_event_id_prefix := DEFAULT_EVENT_ID_PREFIX,
	p_scope_generation := SCOPE_GENERATION_INHERIT
) -> Dictionary:
	return {
		INPUT_PRIMARY_CAR_ID: p_primary_car_id,
		INPUT_TICK_INDEX: p_tick_index,
		INPUT_HAS_WALL_WITNESS: p_has_wall_witness,
		INPUT_SEVERITY_M_S: p_severity_m_s,
		INPUT_RESPONSE_NORMAL: p_response_normal,
		INPUT_OTHER_CAR_ID: p_other_car_id,
		INPUT_REGION: p_region,
		INPUT_EVENT_ID_PREFIX: p_event_id_prefix,
		INPUT_SCOPE_GENERATION: p_scope_generation,
	}


## Advance the scope generation and close every open episode.
##
## This is the explicit reset path (laboratory `configure()`, grid restart,
## recovery). It clears per-car episode bookkeeping and the same-tick retry
## cache, so old identity keys are never reissued, and leaves the cumulative
## counters alone. A generation lower than the current one is refused.
static func retire(p_state: PolicyState, p_scope_generation: int) -> Dictionary:
	var prior := _require_state(p_state)
	if prior == null:
		return _refuse(Refusal.BAD_STATE, "null or wrong-type policy state", {})
	if not _is_integer(p_scope_generation):
		return _refuse(
			Refusal.BAD_SCOPE_GENERATION,
			"scope generation must be an integer",
			{"scope_generation": p_scope_generation}
		)
	if int(p_scope_generation) < 0:
		return _refuse(
			Refusal.BAD_SCOPE_GENERATION,
			"negative scope generation",
			{"scope_generation": p_scope_generation}
		)
	var next_generation := int(p_scope_generation)
	if next_generation < prior.scope_generation:
		return _refuse(
			Refusal.SCOPE_GENERATION_REGRESSED,
			"scope generation cannot move backwards; use retire() with a newer generation",
			{
				"current_generation": prior.scope_generation,
				"requested_generation": next_generation,
			},
			prior
		)

	var state := prior.copy()
	state.scope_generation = next_generation
	var closed := 0
	for car_id in state.cars:
		var car: CarEpisodeState = state.cars[car_id]
		if car == null:
			continue
		car.scope_generation = next_generation
		if car.episode_active:
			car.bump("episodes_closed")
			closed += 1
		car.episode_active = false
		car.episode_counter = -1
		car.episode_seq = -1
		car.event_seq = -1
		car.published_in_episode = false
		car.last_contact_tick = -1
		car.last_normal = Vector3.ZERO
		car.last_publish_tick = -1
		# A new scope owns a fresh retry cache and ordering watermark.
		car.last_tick = -1
		car.last_input = {}
		car.last_decision = Decision.NONE
		car.last_identity = {}
	return {
		"ok": true,
		"code": Refusal.NONE,
		"code_name": refusal_name(Refusal.NONE),
		"error": "",
		"diagnostic": {"episodes_closed": closed},
		"scope_generation": next_generation,
		"state": state,
	}


## Evaluate one committed tick for one primary car.
##
## `p_input` must carry `primary_car_id`, `tick_index`, `has_wall_witness`,
## `severity_m_s` and `response_normal`; `other_car_id`, `region`,
## `event_id_prefix` and `scope_generation` are optional. The returned
## dictionary always carries `ok`, `code`, `code_name`, `error`, `diagnostic`,
## `decision`, `decision_name`, `publish`, `state`, `identity`, `counters` and
## `idempotent_retry`. On refusal `state` is a content-identical copy of the
## prior state, so no partial update is observable.
static func evaluate(p_state: PolicyState, p_input: Variant) -> Dictionary:
	var prior := _require_state(p_state)
	if prior == null:
		return _refuse(Refusal.BAD_STATE, "null or wrong-type policy state", {})
	if typeof(p_input) != TYPE_DICTIONARY:
		return _refuse(
			Refusal.BAD_INPUT,
			"input must be a dictionary built by make_input()",
			{"input_type": type_string(typeof(p_input))},
			prior
		)
	var input: Dictionary = p_input
	for key in REQUIRED_INPUT_KEYS:
		if not input.has(key):
			return _refuse(
				Refusal.BAD_INPUT,
				"input is missing the required key " + str(key),
				{"missing_key": str(key)},
				prior
			)
	for key in input:
		if not INPUT_KEYS.has(str(key)):
			return _refuse(
				Refusal.BAD_INPUT,
				"input carries an unknown key; the contract is closed",
				{"unknown_key": str(key)},
				prior
			)

	var car_id: String = input[INPUT_PRIMARY_CAR_ID]
	if typeof(car_id) != TYPE_STRING or car_id.is_empty():
		return _refuse(
			Refusal.BAD_CAR_ID,
			"primary car id must be a nonempty string",
			{"primary_car_id": car_id},
			prior
		)

	var tick_index: int = input[INPUT_TICK_INDEX]
	if not _is_integer(tick_index) or int(tick_index) < 0:
		return _refuse(
			Refusal.BAD_TICK_INDEX,
			"tick index must be a nonnegative integer",
			{"tick_index": tick_index},
			prior
		)
	tick_index = int(tick_index)

	var has_wall_witness: bool = input[INPUT_HAS_WALL_WITNESS]
	if typeof(has_wall_witness) != TYPE_BOOL:
		return _refuse(
			Refusal.BAD_INPUT,
			"has_wall_witness must be a bool",
			{"has_wall_witness": has_wall_witness},
			prior
		)

	var severity: float = input[INPUT_SEVERITY_M_S]
	if typeof(severity) != TYPE_FLOAT and typeof(severity) != TYPE_INT:
		return _refuse(
			Refusal.BAD_SEVERITY,
			"severity must be a finite number",
			{"severity_m_s": severity},
			prior
		)
	severity = float(severity)
	if not is_finite(severity) or severity < 0.0:
		return _refuse(
			Refusal.BAD_SEVERITY,
			"severity must be finite and nonnegative",
			{"severity_m_s": severity},
			prior
		)

	var normal: Vector3 = input[INPUT_RESPONSE_NORMAL]
	if typeof(normal) != TYPE_VECTOR3:
		return _refuse(
			Refusal.BAD_RESPONSE_NORMAL,
			"response normal must be a Vector3",
			{"response_normal": normal},
			prior
		)
	if not _finite_vector(normal) or normal.length() < NORMAL_MIN_LENGTH:
		return _refuse(
			Refusal.BAD_RESPONSE_NORMAL,
			"response normal must be finite and non-degenerate",
			{"response_normal": normal},
			prior
		)
	normal = normal.normalized()

	var other_car_id: String = input[INPUT_OTHER_CAR_ID]
	if typeof(other_car_id) != TYPE_STRING:
		return _refuse(
			Refusal.BAD_INPUT,
			"other_car_id must be a string",
			{"other_car_id": other_car_id},
			prior
		)

	var region := _validated_region(input[INPUT_REGION])
	if not bool(region["ok"]):
		return _refuse(
			Refusal.BAD_REGION,
			str(region["error"]),
			{"region": input[INPUT_REGION]},
			prior
		)

	var event_id_prefix: String = input[INPUT_EVENT_ID_PREFIX]
	if typeof(event_id_prefix) != TYPE_STRING or event_id_prefix.is_empty():
		return _refuse(
			Refusal.BAD_EVENT_ID_PREFIX,
			"event id prefix must be a nonempty string",
			{"event_id_prefix": event_id_prefix},
			prior
		)

	var generation: int = prior.scope_generation
	var requested_generation: Variant = input[INPUT_SCOPE_GENERATION]
	if _is_integer(requested_generation) and int(requested_generation) != SCOPE_GENERATION_INHERIT:
		generation = int(requested_generation)
		if generation < 0:
			return _refuse(
				Refusal.BAD_SCOPE_GENERATION,
				"negative scope generation",
				{"scope_generation": generation},
				prior
			)
		if generation != prior.scope_generation:
			return _refuse(
				Refusal.SCOPE_GENERATION_MISMATCH,
				"scope generation disagrees with the policy state; use retire() to advance it",
				{
					"state_generation": prior.scope_generation,
					"input_generation": generation,
				},
				prior
			)
	elif not _is_integer(requested_generation):
		return _refuse(
			Refusal.BAD_SCOPE_GENERATION,
			"scope generation must be an integer or the inherit sentinel",
			{"scope_generation": requested_generation},
			prior
		)

	# Normalized input used for exact same-tick idempotency and conflict
	# detection. Vector comparison is bit-exact, so any float difference in a
	# retried normal or severity is a conflict, never a silent merge.
	var normalized := {
		INPUT_PRIMARY_CAR_ID: car_id,
		INPUT_TICK_INDEX: tick_index,
		INPUT_HAS_WALL_WITNESS: has_wall_witness,
		INPUT_SEVERITY_M_S: severity,
		INPUT_RESPONSE_NORMAL: normal,
		INPUT_OTHER_CAR_ID: other_car_id,
		INPUT_REGION: int(region["region"]),
		INPUT_EVENT_ID_PREFIX: event_id_prefix,
	}

	# Car-car pass-through: the wall state is not read and not written.
	if not other_car_id.is_empty():
		return {
			"ok": true,
			"code": Refusal.NONE,
			"code_name": refusal_name(Refusal.NONE),
			"error": "",
			"diagnostic": {
				"reason": "nonempty other_car_id is not a wall contact",
				"other_car_id": other_car_id,
			},
			"decision": Decision.PASS_THROUGH,
			"decision_name": decision_name(Decision.PASS_THROUGH),
			"publish": false,
			"idempotent_retry": false,
			"primary_car_id": car_id,
			"tick_index": tick_index,
			"scope_generation": generation,
			"episode_key": "",
			"episode_seq": -1,
			"event_seq": -1,
			"event_id": "",
			"contact_id": "",
			"severity_m_s": severity,
			"response_normal": normal,
			"region": int(region["region"]),
			"counters": prior.counters(),
			"state": prior.copy(),
		}

	var state := prior.copy()
	var car := _car(state, car_id)

	# Same-tick handling: an identical retry replays the cached decision, and a
	# different input for an already evaluated tick refuses.
	if car.last_tick >= 0 and tick_index < car.last_tick:
		return _refuse(
			Refusal.TICK_OUT_OF_ORDER,
			"tick index moved backwards for this primary car",
			{
				"primary_car_id": car_id,
				"last_tick_index": car.last_tick,
				"tick_index": tick_index,
			},
			prior
		)
	if car.last_tick == tick_index:
		if car.last_input == normalized:
			return _cached_decision(state, car, car_id, tick_index, generation, normalized)
		return _refuse(
			Refusal.CONFLICTING_SAME_TICK_INPUT,
			"this tick was already evaluated with different input for this car",
			{
				"primary_car_id": car_id,
				"tick_index": tick_index,
				"previous_input": car.last_input.duplicate(),
				"input": normalized,
			},
			prior
		)

	var decision := Decision.NONE
	var published := false
	var closed_before_open := false
	var identity := {}

	if has_wall_witness:
		car.bump("contact_ticks")
		var compatible := false
		if car.episode_active:
			var gap := tick_index - car.last_contact_tick
			compatible = gap <= MAX_CONTACT_GAP_TICKS and _normal_compatible(
				car.last_normal, normal
			)
			if not compatible:
				# Separation longer than the gap budget, or a response normal
				# that identifies a different struck surface.
				car.bump("episodes_closed")
				car.episode_active = false
				car.published_in_episode = false
				closed_before_open = true
		if not compatible:
			car.episode_counter += 1
			car.episode_seq = car.episode_counter
			car.event_seq = -1
			car.published_in_episode = false
			car.episode_active = true
			car.last_contact_tick = tick_index
			car.last_normal = normal
			car.last_publish_tick = -1
			car.bump("episodes_opened")
			if severity >= PUBLISH_FLOOR_M_S:
				decision = Decision.PUBLISH_ONSET
				published = true
				car.event_seq = 0
				car.published_in_episode = true
				car.last_publish_tick = tick_index
				car.bump("published_events")
			else:
				# Even and zero contacts open an episode; they never publish.
				decision = Decision.SUPPRESS_ONSET
				car.bump("suppressed_low_delta")
				car.bump("suppressed_onset")
		else:
			# Continuing episode: contact bookkeeping always advances, even
			# when the witness is suppressed.
			car.last_contact_tick = tick_index
			car.last_normal = normal
			var spaced := (
				not car.published_in_episode
				or (tick_index - car.last_publish_tick) >= MIN_REPEAT_SPACING_TICKS
			)
			if severity >= REPEAT_DELTA_M_S and spaced:
				decision = Decision.PUBLISH_REPEAT
				published = true
				car.event_seq += 1
				car.published_in_episode = true
				car.last_publish_tick = tick_index
				car.bump("published_events")
			else:
				decision = Decision.SUPPRESS_REPEAT
				car.bump("suppressed_low_delta")
				car.bump("suppressed_repeat")
	elif car.episode_active:
		var gap := tick_index - car.last_contact_tick
		if gap > MAX_CONTACT_GAP_TICKS:
			car.bump("episodes_closed")
			car.episode_active = false
			car.episode_seq = -1
			car.event_seq = -1
			car.published_in_episode = false
			decision = Decision.EPISODE_CLOSED
		else:
			car.bump("observing_ticks")
			decision = Decision.CONTINUE_OBSERVING
	else:
		car.bump("idle_ticks")
		decision = Decision.NONE

	identity = _identity(
		generation,
		car,
		car_id,
		tick_index,
		severity,
		normal,
		int(region["region"]),
		published,
		event_id_prefix
	)

	car.last_tick = tick_index
	car.last_input = normalized
	car.last_decision = decision
	car.last_identity = identity

	return {
		"ok": true,
		"code": Refusal.NONE,
		"code_name": refusal_name(Refusal.NONE),
		"error": "",
		"diagnostic": {
			"closed_before_open": closed_before_open,
			"episode_key": identity.get("episode_key", ""),
		},
		"decision": decision,
		"decision_name": decision_name(decision),
		"publish": published,
		"idempotent_retry": false,
		"primary_car_id": car_id,
		"tick_index": tick_index,
		"scope_generation": generation,
		"episode_key": identity.get("episode_key", ""),
		"episode_seq": identity.get("episode_seq", -1),
		"event_seq": identity.get("event_seq", -1),
		"event_id": identity.get("event_id", ""),
		"contact_id": "",
		"severity_m_s": severity,
		"response_normal": normal,
		"region": int(region["region"]),
		"counters": state.counters(),
		"state": state,
	}


## Stable name for a `Decision` value.
static func decision_name(p_decision: int) -> String:
	if not DECISION_NAMES.has(p_decision):
		return "invalid"
	return str(DECISION_NAMES[p_decision])


## Stable name for a `Refusal` value.
static func refusal_name(p_code: int) -> String:
	if not REFUSAL_NAMES.has(p_code):
		return "invalid"
	return str(REFUSAL_NAMES[p_code])


# --- Internals ---------------------------------------------------------------


static func _new_counters() -> Dictionary:
	var counters := {}
	for key in COUNTER_KEYS:
		counters[key] = 0
	return counters


static func _vector_to_array(p_vector: Vector3) -> Array:
	return [p_vector.x, p_vector.y, p_vector.z]


static func _is_integer(p_value: Variant) -> bool:
	return typeof(p_value) == TYPE_INT


static func _finite_vector(p_vector: Vector3) -> bool:
	return (
		is_finite(p_vector.x)
		and is_finite(p_vector.y)
		and is_finite(p_vector.z)
	)


static func _validated_generation(p_generation: Variant) -> int:
	if not _is_integer(p_generation) or int(p_generation) < 0:
		return 0
	return int(p_generation)


static func _require_state(p_state: Variant) -> PolicyState:
	if typeof(p_state) != TYPE_OBJECT:
		return null
	if p_state == null:
		return null
	if not (p_state is PolicyState):
		return null
	return p_state


static func _car(p_state: PolicyState, p_car_id: String) -> CarEpisodeState:
	if not p_state.cars.has(p_car_id):
		var car := CarEpisodeState.new()
		car.scope_generation = p_state.scope_generation
		p_state.cars[p_car_id] = car
	var car: CarEpisodeState = p_state.cars[p_car_id]
	if car == null:
		car = CarEpisodeState.new()
		car.scope_generation = p_state.scope_generation
		p_state.cars[p_car_id] = car
	return car


## Road-plane response-normal compatibility. Two normals within
## `NORMAL_COMPAT_ANGLE_DEG` describe the same struck surface.
static func _normal_compatible(p_previous: Vector3, p_current: Vector3) -> bool:
	if p_previous == Vector3.ZERO or p_current == Vector3.ZERO:
		return false
	var angle_deg := rad_to_deg(p_previous.angle_to(p_current))
	return angle_deg <= NORMAL_COMPAT_ANGLE_DEG + NORMAL_COMPAT_ANGLE_EPSILON_DEG


static func _validated_region(p_region: Variant) -> Dictionary:
	if p_region == null:
		return {"ok": true, "region": REGION_UNSET}
	match typeof(p_region):
		TYPE_INT:
			var value := int(p_region)
			if value < REGION_UNSET or value >= REGION_NAMES.size():
				return {
					"ok": false,
					"error": "region integer is outside the ContactRegion vocabulary",
				}
			return {"ok": true, "region": value}
		TYPE_STRING:
			var name := str(p_region)
			if name.is_empty():
				return {"ok": true, "region": REGION_UNSET}
			var index := REGION_NAMES.find(name)
			if index < 0:
				return {
					"ok": false,
					"error": "region name is not one of " + str(REGION_NAMES),
				}
			return {"ok": true, "region": index}
	return {"ok": false, "error": "region must be an integer, a region name or null"}


static func _identity(
	p_generation: int,
	p_car: CarEpisodeState,
	p_car_id: String,
	p_tick_index: int,
	p_severity: float,
	p_normal: Vector3,
	p_region: int,
	p_published: bool,
	p_event_id_prefix: String
) -> Dictionary:
	var episode_key := ""
	var event_seq := -1
	var event_id := ""
	if p_car.episode_active:
		episode_key = "%d:%d" % [p_generation, p_car.episode_seq]
		event_seq = p_car.event_seq
		if p_published:
			event_id = "%s.%d.%d.%d" % [
				p_event_id_prefix,
				p_generation,
				p_car.episode_seq,
				p_car.event_seq,
			]
	return {
		"primary_car_id": p_car_id,
		"tick_index": p_tick_index,
		"scope_generation": p_generation,
		"episode_key": episode_key,
		"episode_seq": p_car.episode_seq if p_car.episode_active else -1,
		"event_seq": event_seq,
		"event_id": event_id,
		# Always empty on the wall path: `contact_id` pairs the two car-car
		# perspectives and is never invented for a wall session.
		"contact_id": "",
		"severity_m_s": p_severity,
		"response_normal": p_normal,
		"region": p_region,
	}


static func _cached_decision(
	p_state: PolicyState,
	p_car: CarEpisodeState,
	p_car_id: String,
	p_tick_index: int,
	p_generation: int,
	p_normalized: Dictionary
) -> Dictionary:
	var identity: Dictionary = p_car.last_identity
	return {
		"ok": true,
		"code": Refusal.NONE,
		"code_name": refusal_name(Refusal.NONE),
		"error": "",
		"diagnostic": {"replayed": true},
		"decision": p_car.last_decision,
		"decision_name": decision_name(int(p_car.last_decision)),
		"publish": str(identity.get("event_id", "")) != "",
		"idempotent_retry": true,
		"primary_car_id": p_car_id,
		"tick_index": p_tick_index,
		"scope_generation": p_generation,
		"episode_key": identity.get("episode_key", ""),
		"episode_seq": identity.get("episode_seq", -1),
		"event_seq": identity.get("event_seq", -1),
		"event_id": identity.get("event_id", ""),
		"contact_id": "",
		"severity_m_s": p_normalized[INPUT_SEVERITY_M_S],
		"response_normal": p_normalized[INPUT_RESPONSE_NORMAL],
		"region": identity.get("region", REGION_UNSET),
		"counters": p_state.counters(),
		"state": p_state,
	}


static func _refuse(
	p_code: int,
	p_error: String,
	p_diagnostic: Dictionary,
	p_state: Variant = null
) -> Dictionary:
	var state: PolicyState = null
	if p_state != null and p_state is PolicyState:
		state = (p_state as PolicyState).copy()
	return {
		"ok": false,
		"code": p_code,
		"code_name": refusal_name(p_code),
		"error": p_error,
		"diagnostic": p_diagnostic.duplicate(),
		"decision": Decision.NONE,
		"decision_name": decision_name(Decision.NONE),
		"publish": false,
		"idempotent_retry": false,
		"state": state,
		"identity": {},
		"counters": {},
		"contact_id": "",
		"event_id": "",
	}
