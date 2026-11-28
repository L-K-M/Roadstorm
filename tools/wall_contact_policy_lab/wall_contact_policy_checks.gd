class_name WallContactPolicyLabChecks
extends RefCounted
## Focused behaviour checks for the provisional pure WallContactPolicy.
##
## The suite drives the real policy API (new_state, make_input, evaluate,
## retire, decision_name, refusal_name) through committed-tick scenarios and
## checks decisions, publish flags, event/episode/contact identity, cumulative
## counters and state serialization, not merely the ok flag. It exercises the
## pure component only: no DriveLab, no physics bodies, no cosmetic consumer
## and no M1.8 acceptance claim. A behavioural mismatch with the documented
## contract is reported as a failing check, never repaired here.

const Policy := preload("res://src/simulation/wall_contact_policy.gd")

## Summary schema tag for this laboratory.
const SUMMARY_SCHEMA := "roadstorm.wall_contact_policy_lab.summary.v1"
## Road-plane response normal shared by every scenario unless stated.
const UP := Vector3.UP
## Primary car id used by every scenario.
const CAR_ID := "car_a"
## Second car id used only for the car-car pass-through scenario.
const OTHER_CAR_ID := "car_b"
## Severity above the onset floor, so an onset publishes.
const ONSET_SEVERITY_M_S := 3.0
## Severity above the repeat floor, used for repeat-spacing probes.
const REPEAT_SEVERITY_M_S := 5.0
## Legal zero severity: a witness that opens an episode without publishing.
const ZERO_SEVERITY_M_S := 0.0
## Severity below both floors, used for the long low-delta grind.
const LOW_DELTA_SEVERITY_M_S := 0.4
## Length of the low-delta grind run in ticks.
const LOW_DELTA_RUN_TICKS := 180
## Published-event ceiling asserted for the grind run. The contract expects a
## single onset; seven is the loud upper bound used by the lab gate.
const MAX_PUBLISHED_IN_RUN := 7
## Severity probes after the onset in the repeat-spacing scenario.
const REPEAT_PROBE_TICKS := 40
## Region index of "left" in the policy region vocabulary.
const REGION_LEFT := 2


class Case extends RefCounted:
	var name := ""
	var checks := 0
	var failures: Array[String] = []
	var measurements: Dictionary = {}

	func check(condition: bool, message: String) -> void:
		checks += 1
		if not condition:
			failures.append(message)

	func equal(actual: Variant, expected: Variant, message: String) -> void:
		checks += 1
		if actual != expected:
			failures.append("%s (got %s expected %s)" % [message, str(actual), str(expected)])

	func close(actual: float, expected: float, tolerance: float, message: String) -> void:
		checks += 1
		if absf(actual - expected) > tolerance:
			failures.append(
				"%s (got %.9f expected %.9f tol %.9f)" % [message, actual, expected, tolerance]
			)

	func vector_close(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
		checks += 1
		if actual.distance_to(expected) > tolerance:
			failures.append(
				"%s (got %s expected %s tol %.9f)" % [message, str(actual), str(expected), tolerance]
			)

	func measure(key: String, value: Variant) -> void:
		measurements[key] = value

	func expects_ok(result: Dictionary, message: String) -> bool:
		checks += 1
		if not bool(result.get("ok", false)):
			failures.append(
				"%s: expected acceptance, got %s (%s)" % [
					message,
					str(result.get("code_name", "missing")),
					str(result.get("error", "missing")),
				]
			)
			return false
		return true

	func expects_refusal(result: Dictionary, expected_code_name: String, message: String) -> void:
		checks += 1
		if bool(result.get("ok", true)):
			failures.append(message + ": expected a refusal, got ok")
			return
		equal(str(result.get("code_name", "missing")), expected_code_name, message + " (code_name)")
		equal(
			Policy.refusal_name(int(result.get("code", -1))),
			expected_code_name,
			message + " (refusal enum round trip)"
		)
		checks += 1
		if str(result.get("error", "")).strip_edges().is_empty():
			failures.append(message + ": refusal carried no error text")
		checks += 1
		if typeof(result.get("diagnostic", null)) != TYPE_DICTIONARY:
			failures.append(message + ": refusal carried no structured diagnostic")

	func expects_decision(result: Dictionary, expected_name: String, message: String) -> void:
		equal(
			str(result.get("decision_name", "missing")),
			expected_name,
			message + " (decision_name)"
		)
		equal(
			Policy.decision_name(int(result.get("decision", -1))),
			expected_name,
			message + " (decision enum round trip)"
		)

	func expects_counters(actual: Dictionary, expected: Dictionary, label: String) -> void:
		for key in Policy.COUNTER_KEYS:
			var wanted := int(expected.get(key, 0))
			var got := int(actual.get(key, -1))
			equal(got, wanted, "%s: counter %s" % [label, key])

	func result() -> Dictionary:
		return {
			"case": name,
			"pass": failures.is_empty(),
			"checks": checks,
			"checks_failed": failures.size(),
			"failures": failures.duplicate(),
			"measurements": measurements.duplicate(),
		}


func run_all() -> Dictionary:
	var case_results: Array[Dictionary] = []
	var total_checks := 0
	var total_failures := 0
	for call in [
		Callable(self, "_case_onset_publishes_and_zero_onset_suppresses"),
		Callable(self, "_case_low_delta_run_does_not_flood"),
		Callable(self, "_case_repeat_requires_minimum_spacing"),
		Callable(self, "_case_same_tick_retry_replays_and_conflict_refuses"),
		Callable(self, "_case_gap_closes_then_reopens_with_new_episode_id"),
		Callable(self, "_case_pass_through_leaves_state_and_retire_resets"),
	]:
		var result: Dictionary = call.call()
		case_results.append(result)
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		print(
			"WALL_CONTACT_POLICY_LAB_CASE ",
			JSON.stringify({
				"case": result["case"],
				"checks": result["checks"],
				"checks_failed": result["checks_failed"],
				"pass": result["pass"],
			})
		)
	return {
		"schema": SUMMARY_SCHEMA,
		"pass": total_failures == 0,
		"cases": case_results.size(),
		"cases_passed": case_results.size() - _failed_case_count(case_results),
		"checks": total_checks,
		"checks_failed": total_failures,
		"case_results": case_results.duplicate(),
	}


func _failed_case_count(case_results: Array[Dictionary]) -> int:
	var failed := 0
	for result in case_results:
		if not bool(result["pass"]):
			failed += 1
	return failed


## Scenario 1: a severity-3 onset publishes exactly one nonempty event id and
## episode key with an empty contact id, while a legal zero onset opens an
## episode, suppresses, and allocates no event id.
func _case_onset_publishes_and_zero_onset_suppresses() -> Dictionary:
	var c := Case.new()
	c.name = "onset_publishes_and_zero_onset_suppresses"

	var state: Variant = Policy.new_state(0)
	var onset: Dictionary = Policy.evaluate(
		state, Policy.make_input(CAR_ID, 0, true, ONSET_SEVERITY_M_S, UP)
	)
	if c.expects_ok(onset, "severity-3 onset evaluate"):
		c.expects_decision(onset, "publish_onset", "severity-3 onset")
		c.equal(onset["publish"], true, "severity-3 onset publishes")
		c.equal(
			onset["event_id"],
			"%s.0.0.0" % Policy.DEFAULT_EVENT_ID_PREFIX,
			"severity-3 onset event id"
		)
		c.check(not str(onset["event_id"]).is_empty(), "severity-3 onset event id is nonempty")
		c.equal(onset["episode_key"], "0:0", "severity-3 onset episode key")
		c.check(not str(onset["episode_key"]).is_empty(), "severity-3 onset episode key is nonempty")
		c.equal(onset["contact_id"], "", "wall onset contact id stays empty")
		c.equal(onset["episode_seq"], 0, "severity-3 onset episode seq")
		c.equal(onset["event_seq"], 0, "severity-3 onset event seq")
		c.equal(onset["idempotent_retry"], false, "fresh onset is not a replayed retry")
		c.equal(onset["scope_generation"], 0, "onset scope generation")
		c.equal(onset["severity_m_s"], float(ONSET_SEVERITY_M_S), "onset echoes severity")
		c.equal(onset["region"], Policy.REGION_UNSET, "default region sentinel")
		c.expects_counters(
			onset["counters"],
			{
				"contact_ticks": 1,
				"published_events": 1,
				"episodes_opened": 1,
				"episodes_closed": 0,
				"suppressed_onset": 0,
				"suppressed_repeat": 0,
			},
			"severity-3 onset"
		)

	var serialized: Dictionary = onset["state"].to_dictionary()
	c.equal(serialized["schema"], Policy.POLICY_STATE_SCHEMA, "state serialization schema tag")
	c.equal(serialized["scope_generation"], 0, "serialized scope generation")
	c.equal(serialized["counters"]["published_events"], 1, "serialized published events")
	var car_record: Dictionary = serialized["cars"][CAR_ID]
	c.equal(car_record["episode_active"], true, "serialized episode active")
	c.equal(car_record["episode_seq"], 0, "serialized episode seq")
	c.equal(car_record["event_seq"], 0, "serialized event seq")
	c.equal(car_record["published_in_episode"], true, "serialized published flag")
	c.equal(car_record["last_contact_tick"], 0, "serialized last contact tick")
	c.equal(car_record["last_publish_tick"], 0, "serialized last publish tick")
	c.equal(car_record["last_tick"], 0, "serialized ordering watermark")
	var last_normal: Array = car_record["last_normal"]
	c.close(float(last_normal[0]), UP.x, 1.0e-9, "serialized last normal x")
	c.close(float(last_normal[1]), UP.y, 1.0e-9, "serialized last normal y")
	c.close(float(last_normal[2]), UP.z, 1.0e-9, "serialized last normal z")
	c.equal(car_record["counters"]["published_events"], 1, "serialized per-car published events")

	var zero_state: Variant = Policy.new_state(0)
	var zero: Dictionary = Policy.evaluate(
		zero_state, Policy.make_input(CAR_ID, 0, true, ZERO_SEVERITY_M_S, UP)
	)
	if c.expects_ok(zero, "legal zero onset evaluate"):
		c.expects_decision(zero, "suppress_onset", "legal zero onset")
		c.equal(zero["publish"], false, "legal zero onset does not publish")
		c.equal(zero["event_id"], "", "legal zero onset allocates no event id")
		c.equal(zero["event_seq"], -1, "legal zero onset allocates no event seq")
		c.equal(zero["episode_key"], "0:0", "legal zero onset still opens an episode")
		c.expects_counters(
			zero["counters"],
			{
				"contact_ticks": 1,
				"published_events": 0,
				"episodes_opened": 1,
				"suppressed_onset": 1,
				"suppressed_low_delta": 1,
			},
			"legal zero onset"
		)

	return c.result()


## Scenario 2: 180 consecutive low-delta wall ticks open one episode and never
## flood the cosmetic stream. The contract allows a single onset and never more
## than seven published events; counters and ids are checked, not just ok.
func _case_low_delta_run_does_not_flood() -> Dictionary:
	var c := Case.new()
	c.name = "low_delta_run_does_not_flood"

	var state: Variant = Policy.new_state(0)
	var published := 0
	var event_ids: Array = []
	var episode_keys: Dictionary = {}
	for tick in range(LOW_DELTA_RUN_TICKS):
		var severity := float(ONSET_SEVERITY_M_S) if tick == 0 else float(LOW_DELTA_SEVERITY_M_S)
		var result: Dictionary = Policy.evaluate(
			state, Policy.make_input(CAR_ID, tick, true, severity, UP)
		)
		state = result["state"]
		if not c.expects_ok(result, "low-delta tick %d" % tick):
			continue
		if bool(result["publish"]):
			published += 1
			event_ids.append(str(result["event_id"]))
		if not str(result["episode_key"]).is_empty():
			episode_keys[str(result["episode_key"])] = true
		if tick == 0:
			c.expects_decision(result, "publish_onset", "low-delta run tick 0")
		else:
			c.expects_decision(result, "suppress_repeat", "low-delta run tick %d" % tick)
			c.equal(result["publish"], false, "low-delta tick %d does not publish" % tick)
			c.equal(result["event_id"], "", "low-delta tick %d allocates no event id" % tick)

	c.measure("published_events", published)
	c.measure("ticks", LOW_DELTA_RUN_TICKS)
	c.equal(published, 1, "the low-delta run publishes exactly one onset")
	c.check(
		published <= MAX_PUBLISHED_IN_RUN,
		"the low-delta run must never publish more than %d events (got %d)" % [
			MAX_PUBLISHED_IN_RUN, published,
		]
	)
	c.equal(event_ids.size(), 1, "one event id allocated across the run")
	c.check(_all_unique(event_ids), "event ids allocated across the run are unique")
	c.equal(episode_keys.size(), 1, "the whole run stays inside one episode")
	c.check(episode_keys.has("0:0"), "the single episode key is 0:0")

	c.expects_counters(
		state.counters(),
		{
			"contact_ticks": LOW_DELTA_RUN_TICKS,
			"published_events": 1,
			"episodes_opened": 1,
			"episodes_closed": 0,
			"suppressed_onset": 0,
			"suppressed_repeat": LOW_DELTA_RUN_TICKS - 1,
			"suppressed_low_delta": LOW_DELTA_RUN_TICKS - 1,
			"observing_ticks": 0,
			"idle_ticks": 0,
		},
		"low-delta run"
	)
	var car: Variant = state.cars[CAR_ID]
	c.equal(car.event_seq, 0, "run ends on the onset event seq")
	c.equal(car.published_in_episode, true, "run keeps the episode published flag")
	c.equal(car.last_contact_tick, LOW_DELTA_RUN_TICKS - 1, "run advances the contact tick")
	c.equal(car.last_tick, LOW_DELTA_RUN_TICKS - 1, "run advances the ordering watermark")

	return c.result()


## Scenario 3: a qualifying repeat (severity at or above the repeat floor) may
## publish only once the minimum repeat spacing has elapsed since the last
## published event of the episode.
func _case_repeat_requires_minimum_spacing() -> Dictionary:
	var c := Case.new()
	c.name = "repeat_requires_minimum_spacing"

	var state: Variant = Policy.new_state(0)
	var onset: Dictionary = Policy.evaluate(
		state, Policy.make_input(CAR_ID, 0, true, ONSET_SEVERITY_M_S, UP)
	)
	if not c.expects_ok(onset, "repeat-spacing onset"):
		return c.result()
	state = onset["state"]

	var first_repeat_tick := -1
	var repeat_ids: Array = []
	for tick in range(1, REPEAT_PROBE_TICKS + 1):
		var result: Dictionary = Policy.evaluate(
			state, Policy.make_input(CAR_ID, tick, true, REPEAT_SEVERITY_M_S, UP)
		)
		state = result["state"]
		if not c.expects_ok(result, "repeat probe tick %d" % tick):
			continue
		if str(result["decision_name"]) == "publish_repeat":
			if first_repeat_tick < 0:
				first_repeat_tick = tick
			repeat_ids.append(str(result["event_id"]))
		else:
			c.expects_decision(result, "suppress_repeat", "repeat probe tick %d" % tick)
			c.equal(result["publish"], false, "repeat probe tick %d does not publish" % tick)
			c.equal(result["event_id"], "", "repeat probe tick %d allocates no event id" % tick)

	c.measure("first_repeat_tick", first_repeat_tick)
	c.equal(
		first_repeat_tick,
		Policy.MIN_REPEAT_SPACING_TICKS,
		"a qualifying repeat publishes only after the minimum spacing"
	)
	c.equal(repeat_ids.size(), 1, "one repeat published inside the probe window")
	c.equal(
		str(repeat_ids[0]) if not repeat_ids.is_empty() else "",
		"%s.0.0.1" % Policy.DEFAULT_EVENT_ID_PREFIX,
		"repeat event id sequence"
	)
	c.expects_counters(
		state.counters(),
		{
			"contact_ticks": REPEAT_PROBE_TICKS + 1,
			"published_events": 2,
			"episodes_opened": 1,
			"episodes_closed": 0,
			"suppressed_repeat": REPEAT_PROBE_TICKS - 1,
			"suppressed_low_delta": REPEAT_PROBE_TICKS - 1,
		},
		"repeat-spacing run"
	)

	return c.result()


## Scenario 4: an identical same-tick retry replays the cached decision without
## allocating counters or identity, and a conflicting same-tick input refuses
## without mutating the state.
func _case_same_tick_retry_replays_and_conflict_refuses() -> Dictionary:
	var c := Case.new()
	c.name = "same_tick_retry_replays_and_conflict_refuses"

	var state: Variant = Policy.new_state(0)
	var onset: Dictionary = Policy.evaluate(
		state, Policy.make_input(CAR_ID, 0, true, ONSET_SEVERITY_M_S, UP)
	)
	if not c.expects_ok(onset, "retry-scenario onset"):
		return c.result()
	var settled: Variant = onset["state"]
	var before: Dictionary = settled.to_dictionary()
	var before_counters: Dictionary = settled.counters()

	var retry: Dictionary = Policy.evaluate(
		settled, Policy.make_input(CAR_ID, 0, true, ONSET_SEVERITY_M_S, UP)
	)
	if c.expects_ok(retry, "identical same-tick retry"):
		c.equal(retry["idempotent_retry"], true, "identical retry is replayed")
		c.expects_decision(retry, "publish_onset", "replayed retry")
		c.equal(retry["publish"], true, "replayed retry keeps the publish flag")
		c.equal(retry["event_id"], onset["event_id"], "replayed retry reuses the event id")
		c.equal(retry["episode_key"], onset["episode_key"], "replayed retry reuses the episode key")
		c.equal(retry["episode_seq"], onset["episode_seq"], "replayed retry episode seq")
		c.equal(retry["event_seq"], onset["event_seq"], "replayed retry event seq")
		c.equal(retry["counters"], before_counters, "replayed retry allocates no counters")
		c.equal(
			retry["state"].to_dictionary(),
			before,
			"replayed retry leaves the state serialization identical"
		)
	c.expects_counters(
		before_counters,
		{"contact_ticks": 1, "published_events": 1, "episodes_opened": 1},
		"after replayed retry"
	)

	var conflict: Dictionary = Policy.evaluate(
		settled, Policy.make_input(CAR_ID, 0, true, 4.0, UP)
	)
	c.expects_refusal(conflict, "conflicting_same_tick_input", "conflicting same-tick input")
	c.expects_decision(conflict, "none", "conflicting same-tick decision")
	c.equal(conflict["publish"], false, "conflicting retry does not publish")
	c.equal(conflict["event_id"], "", "conflicting retry allocates no event id")
	c.equal(conflict["idempotent_retry"], false, "conflicting retry is not a replay")
	c.check(
		conflict["diagnostic"].has("previous_input") and conflict["diagnostic"].has("input"),
		"conflicting retry diagnostic carries both inputs"
	)
	c.equal(
		conflict["state"].to_dictionary(),
		before,
		"conflicting retry leaves the state content-identical"
	)
	c.expects_counters(
		conflict["state"].counters(),
		{"contact_ticks": 1, "published_events": 1, "episodes_opened": 1},
		"after conflicting retry"
	)

	var retry_after_refusal: Dictionary = Policy.evaluate(
		settled, Policy.make_input(CAR_ID, 0, true, ONSET_SEVERITY_M_S, UP)
	)
	if c.expects_ok(retry_after_refusal, "identical retry after a refused conflict"):
		c.equal(
			retry_after_refusal["idempotent_retry"],
			true,
			"the refused conflict did not corrupt the retry cache"
		)

	return c.result()


## Scenario 5: a no-witness gap longer than the contact gap budget closes the
## episode, and the next qualifying contact opens a new episode with a new
## episode id.
func _case_gap_closes_then_reopens_with_new_episode_id() -> Dictionary:
	var c := Case.new()
	c.name = "gap_closes_then_reopens_with_new_episode_id"

	var state: Variant = Policy.new_state(0)
	var onset: Dictionary = Policy.evaluate(
		state, Policy.make_input(CAR_ID, 0, true, ONSET_SEVERITY_M_S, UP)
	)
	if not c.expects_ok(onset, "gap-scenario onset"):
		return c.result()
	state = onset["state"]
	var first_event_id := str(onset["event_id"])
	var first_episode_key := str(onset["episode_key"])

	var closed_tick := -1
	for tick in range(1, Policy.MAX_CONTACT_GAP_TICKS + 2):
		var result: Dictionary = Policy.evaluate(
			state, Policy.make_input(CAR_ID, tick, false, ZERO_SEVERITY_M_S, UP)
		)
		state = result["state"]
		if not c.expects_ok(result, "no-witness tick %d" % tick):
			continue
		if tick <= Policy.MAX_CONTACT_GAP_TICKS:
			c.expects_decision(result, "continue_observing", "no-witness tick %d" % tick)
			c.equal(result["publish"], false, "observing tick %d does not publish" % tick)
			c.equal(result["event_id"], "", "observing tick %d allocates no event id" % tick)
		else:
			c.expects_decision(result, "episode_closed", "no-witness tick %d" % tick)
			c.equal(result["episode_key"], "", "closed tick carries no episode key")
			c.equal(result["episode_seq"], -1, "closed tick carries no episode seq")
			c.equal(result["event_id"], "", "closed tick allocates no event id")
			closed_tick = tick
	c.equal(
		closed_tick,
		Policy.MAX_CONTACT_GAP_TICKS + 1,
		"the episode closes one tick past the gap budget"
	)
	c.expects_counters(
		state.counters(),
		{
			"contact_ticks": 1,
			"published_events": 1,
			"episodes_opened": 1,
			"episodes_closed": 1,
			"observing_ticks": Policy.MAX_CONTACT_GAP_TICKS,
			"idle_ticks": 0,
		},
		"gap run before reopen"
	)

	var reopen_tick := Policy.MAX_CONTACT_GAP_TICKS + 2
	var reopened: Dictionary = Policy.evaluate(
		state, Policy.make_input(CAR_ID, reopen_tick, true, ONSET_SEVERITY_M_S, UP)
	)
	if c.expects_ok(reopened, "qualifying contact after the gap"):
		c.expects_decision(reopened, "publish_onset", "contact after the gap")
		c.equal(reopened["episode_key"], "0:1", "the reopened episode key")
		c.check(
			str(reopened["episode_key"]) != first_episode_key,
			"the reopened episode key differs from the closed one"
		)
		c.check(
			str(reopened["event_id"]) != first_event_id,
			"the reopened event id differs from the closed one"
		)
		c.equal(
			reopened["event_id"],
			"%s.0.1.0" % Policy.DEFAULT_EVENT_ID_PREFIX,
			"the reopened event id"
		)
	c.expects_counters(
		reopened["state"].counters(),
		{
			"contact_ticks": 2,
			"published_events": 2,
			"episodes_opened": 2,
			"episodes_closed": 1,
			"observing_ticks": Policy.MAX_CONTACT_GAP_TICKS,
		},
		"gap run after reopen"
	)

	return c.result()


## Scenario 6: a nonempty other_car_id is a car-car pass-through that leaves
## the wall state untouched, and retire() advances the scope generation,
## clears the active episode and never reissues identity.
func _case_pass_through_leaves_state_and_retire_resets() -> Dictionary:
	var c := Case.new()
	c.name = "pass_through_leaves_state_and_retire_resets"

	var state: Variant = Policy.new_state(0)
	var onset: Dictionary = Policy.evaluate(
		state, Policy.make_input(CAR_ID, 0, true, ONSET_SEVERITY_M_S, UP)
	)
	if not c.expects_ok(onset, "pass-through scenario onset"):
		return c.result()
	state = onset["state"]
	var before: Dictionary = state.to_dictionary()

	# Argument 7 of make_input() is the integer region index; region names
	# are accepted by evaluate() only, never through the typed input builder.
	var passthrough: Dictionary = Policy.evaluate(
		state, Policy.make_input(CAR_ID, 1, true, 9.0, UP, OTHER_CAR_ID, REGION_LEFT)
	)
	if c.expects_ok(passthrough, "car-car pass-through evaluate"):
		c.expects_decision(passthrough, "pass_through", "car-car pass-through")
		c.equal(passthrough["publish"], false, "pass-through does not publish")
		c.equal(passthrough["event_id"], "", "pass-through allocates no event id")
		c.equal(passthrough["contact_id"], "", "pass-through allocates no contact id")
		c.equal(passthrough["episode_key"], "", "pass-through carries no episode key")
		c.equal(passthrough["episode_seq"], -1, "pass-through carries no episode seq")
		c.equal(passthrough["event_seq"], -1, "pass-through carries no event seq")
		c.equal(passthrough["idempotent_retry"], false, "pass-through is not a replay")
		c.equal(
			passthrough["diagnostic"]["other_car_id"],
			OTHER_CAR_ID,
			"pass-through diagnostic names the other car"
		)
		c.check(
			not str(passthrough["diagnostic"]["reason"]).is_empty(),
			"pass-through diagnostic carries a reason"
		)
		c.equal(passthrough["region"], REGION_LEFT, "integer region index passes through unchanged")
		c.equal(
			passthrough["state"].to_dictionary(),
			before,
			"pass-through leaves the wall state untouched"
		)
	var car: Variant = state.cars[CAR_ID]
	c.equal(car.episode_active, true, "pass-through keeps the wall episode open")
	c.equal(car.last_tick, 0, "pass-through does not advance the ordering watermark")
	c.equal(car.last_contact_tick, 0, "pass-through does not advance the contact tick")
	c.equal(car.last_publish_tick, 0, "pass-through does not advance the publish tick")

	var retired_result: Dictionary = Policy.retire(state, 5)
	if c.expects_ok(retired_result, "retire evaluate"):
		c.equal(retired_result["code_name"], "none", "retire code name")
		c.equal(retired_result["scope_generation"], 5, "retire reports the new generation")
		c.equal(
			retired_result["diagnostic"]["episodes_closed"],
			1,
			"retire closes the one active episode"
		)
	var retired: Variant = retired_result["state"]
	c.equal(retired.scope_generation, 5, "retire advances the scope generation")
	var retired_car: Variant = retired.cars[CAR_ID]
	c.equal(retired_car.scope_generation, 5, "retire advances the per-car generation")
	c.equal(retired_car.episode_active, false, "retire clears the active episode")
	c.equal(retired_car.episode_counter, -1, "retire clears the episode counter")
	c.equal(retired_car.episode_seq, -1, "retire clears the episode seq")
	c.equal(retired_car.event_seq, -1, "retire clears the event seq")
	c.equal(retired_car.published_in_episode, false, "retire clears the published flag")
	c.equal(retired_car.last_contact_tick, -1, "retire clears the contact tick")
	c.equal(retired_car.last_publish_tick, -1, "retire clears the publish tick")
	c.equal(retired_car.last_tick, -1, "retire clears the retry cache and watermark")
	c.expects_counters(
		retired.counters(),
		{
			"contact_ticks": 1,
			"published_events": 1,
			"episodes_opened": 1,
			"episodes_closed": 1,
			"observing_ticks": 0,
			"idle_ticks": 0,
		},
		"after retire"
	)
	var retired_record: Dictionary = retired.to_dictionary()
	c.equal(retired_record["scope_generation"], 5, "serialized retired generation")
	c.equal(
		retired_record["cars"][CAR_ID]["episode_active"],
		false,
		"serialized retired episode flag"
	)
	c.equal(
		retired_record["cars"][CAR_ID]["last_tick"],
		-1,
		"serialized retired ordering watermark"
	)
	c.equal(
		retired_record["counters"]["episodes_closed"],
		1,
		"serialized retired closed episodes"
	)

	var fresh: Dictionary = Policy.evaluate(
		retired, Policy.make_input(CAR_ID, 0, true, ONSET_SEVERITY_M_S, UP)
	)
	if c.expects_ok(fresh, "contact inside the retired scope"):
		c.equal(fresh["scope_generation"], 5, "evaluate inherits the retired generation")
		c.equal(fresh["episode_key"], "5:0", "episode identity restarts in the new generation")
		c.equal(
			fresh["event_id"],
			"%s.5.0.0" % Policy.DEFAULT_EVENT_ID_PREFIX,
			"event id in the new generation"
		)
		c.check(
			str(fresh["event_id"]) != str(onset["event_id"]),
			"the retired scope never reissues an old event id"
		)

	var regressed: Dictionary = Policy.retire(retired, 4)
	c.expects_refusal(regressed, "scope_generation_regressed", "retire with an older generation")
	c.equal(
		regressed["diagnostic"]["current_generation"],
		5,
		"regressed retire reports the current generation"
	)
	c.equal(
		regressed["diagnostic"]["requested_generation"],
		4,
		"regressed retire reports the requested generation"
	)
	c.equal(
		regressed["state"].to_dictionary(),
		retired_record,
		"regressed retire leaves the state content-identical"
	)

	return c.result()


func _all_unique(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value):
			return false
		seen[value] = true
	return true
