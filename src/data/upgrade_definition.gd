class_name UpgradeDefinition
extends DefinitionIdentity
## Typed upgrade definition for the M0.2 slice.
##
## One resource describes one car's one category at one level (stock, 1 or 2).
## Schema version, stable semantic identity, revision, display name and
## lifecycle status come from DefinitionIdentity. This class adds the explicit
## car semantic ID, category, level, per-level credit price and deterministic
## stock-relative effect values.
##
## Effects are fixed by docs/GAME_DESIGN.md "Upgrades" and computed from the
## integer level against stock. They are never compounded per purchase and
## never depend on purchase order. There are no authored coefficient fields:
## the coefficients below are constants of the design contract, so an upgrade
## record cannot carry an invented multiplier. Any change to these formulas is
## a contract revision, not a field value.
##
## This slice stores identity, car/category/level/price and a pure effect
## summary only. It creates no production car or upgrade content and owns no
## purchase, credit, garage, loadout or save logic. Presentation description,
## icon and garage text stay deferred; see DEFERRED_PRESENTATION_FIELDS_V1.
## See src/data/README.md for the surrounding slice boundaries.

## Upgrade category. Engine, Tires and Chassis are the three documented
## categories, each with levels 0, 1 and 2.
enum Category { ENGINE, TIRES, CHASSIS }

const LEVEL_MIN := 0
const LEVEL_MAX := 2

## Credit price per level from docs/GAME_DESIGN.md "Upgrades": stock is free,
## level 1 costs 800 credits and level 2 costs another 1600 credits. The
## level 2 price is incremental, not cumulative: fully upgrading one car costs
## 3 * (800 + 1600) = 7200 credits.
const PRICE_BY_LEVEL := [0, 800, 1600]

## Design coefficients from docs/GAME_DESIGN.md "Upgrades". Additive-to-stock
## formulas evaluated once at level L in 0/1/2; never compounded.
const ENGINE_ACCELERATION_COEFFICIENT := 0.03
const ENGINE_TOP_SPEED_CAP_COEFFICIENT := 0.015
const TIRES_LATERAL_DAMPING_COEFFICIENT := 0.05
const CHASSIS_YAW_GAIN_COEFFICIENT := 0.04
const CHASSIS_IMPACT_SPEED_LOSS_COEFFICIENT := 0.05

## Presentation fields this slice deliberately does not represent. The
## inherited display_name covers the short label; a later presentation slice
## owns the full description, icon and garage text.
const DEFERRED_PRESENTATION_FIELDS_V1 := [
	"presentation.description",
	"presentation.icon",
	"presentation.garage_blurb",
]

## Explicit stable semantic ID of the car this upgrade applies to. This uses
## the CarDefinition.definition_id vocabulary from
## schemas/common.schema.json#/$defs/stable_id, not a display name. It must
## never be renamed to follow a car rename.
@export var car_id: String = ""
## Which of the three documented categories this record upgrades.
@export var category: Category = Category.ENGINE
## Purchased level: 0 (stock), 1 or 2.
@export var level: int = 0
## Incremental credit price for this level; must equal PRICE_BY_LEVEL[level].
@export var price_credits: int = 0


## Diagnostics for this class's own fields. `validate()` prepends every
## DefinitionIdentity diagnostic (schema_version, definition_id, revision,
## display_name, status), so a malformed inherited field is attributed to its
## own path. Validation never clamps, substitutes or repairs authored content.
func validate_upgrade() -> Array[String]:
	var diagnostics := validate_identity()
	if not is_valid_definition_id(car_id):
		diagnostics.append(
			"car_id: malformed '%s' (expected stable semantic ID matching %s)"
			% [car_id, DEFINITION_ID_PATTERN]
		)
	if not Category.values().has(category):
		diagnostics.append(
			"category: out-of-range value %s; expected one of %s"
			% [str(category), _enum_value_names(Category)]
		)
	if level < LEVEL_MIN or level > LEVEL_MAX:
		diagnostics.append(
			"level: out-of-range value %d; expected %d, %d or %d"
			% [level, LEVEL_MIN, 1, LEVEL_MAX]
		)
	else:
		var expected_price := int(PRICE_BY_LEVEL[level])
		if price_credits != expected_price:
			diagnostics.append(
				"price_credits: %d does not match level %d (expected %d)"
				% [price_credits, level, expected_price]
			)
	_validate_effect_finiteness(diagnostics)
	return diagnostics


func validate() -> Array[String]:
	return validate_upgrade()


func is_valid() -> bool:
	return validate().is_empty()


## Pure, total effect summary for this record.
##
## For an in-domain category and level it returns a Dictionary with the keys
## `category` (lowercase name) and `level`, plus exactly the two documented
## stock-relative factors for that category:
##
## - Engine: `acceleration_multiplier` = 1 + 0.03L and
##   `top_speed_cap_multiplier` = 1 + 0.015L.
## - Tires: `grip_lateral_damping_multiplier` = 1 + 0.05L and
##   `drift_exit_blend_seconds_divisor` = the same factor. Drift-state lateral
##   damping, entry threshold and target slip range are deliberately absent:
##   the design says Tires do not change them, so this resource must not imply
##   an opinion about them.
## - Chassis: `steering_yaw_response_gain_multiplier` = 1 + 0.04L and
##   `impact_speed_loss_factor` = 1 - 0.05L.
##
## Every factor applies once to the stock value at this level; none is
## compounded across levels or purchases. The method never mutates the
## resource, writes nothing and computes no physics. An out-of-domain category
## or out-of-range level returns an empty Dictionary instead of a fabricated
## effect. Callers must run `validate()`/`is_valid()` first; a valid record
## always yields both of its category's factors.
func effect_summary() -> Dictionary:
	if not Category.values().has(category) or level < LEVEL_MIN or level > LEVEL_MAX:
		return {}
	match category:
		Category.ENGINE:
			return {
				"category": "engine",
				"level": level,
				"acceleration_multiplier": 1.0 + ENGINE_ACCELERATION_COEFFICIENT * level,
				"top_speed_cap_multiplier": 1.0 + ENGINE_TOP_SPEED_CAP_COEFFICIENT * level,
			}
		Category.TIRES:
			var tire_factor := 1.0 + TIRES_LATERAL_DAMPING_COEFFICIENT * level
			return {
				"category": "tires",
				"level": level,
				"grip_lateral_damping_multiplier": tire_factor,
				"drift_exit_blend_seconds_divisor": tire_factor,
			}
		Category.CHASSIS:
			return {
				"category": "chassis",
				"level": level,
				"steering_yaw_response_gain_multiplier":
					1.0 + CHASSIS_YAW_GAIN_COEFFICIENT * level,
				"impact_speed_loss_factor":
					1.0 - CHASSIS_IMPACT_SPEED_LOSS_COEFFICIENT * level,
			}
	return {}


## There are no exported float coefficients to validate, so finiteness applies
## to the computed effect values. A bounded level keeps them finite; the check
## stays as a guard if the coefficients or bounds change later. An invalid
## category or level produces no summary and is diagnosed by the caller's
## field checks above.
func _validate_effect_finiteness(diagnostics: Array[String]) -> void:
	if not Category.values().has(category) or level < LEVEL_MIN or level > LEVEL_MAX:
		return
	var summary := effect_summary()
	for key in summary.keys():
		var value: Variant = summary[key]
		if typeof(value) == TYPE_FLOAT and not _finite(float(value)):
			diagnostics.append(
				"effects.%s: nonfinite (%s)" % [String(key), str(value)]
			)


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
