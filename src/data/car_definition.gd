class_name CarDefinition
extends DefinitionIdentity
## Typed car definition for the M0.2 slice.
##
## Car units are metres/kg/seconds, local +Y up, -Z forward, origin at the
## ground projection of the axle midpoint, wheel pivots at local axle centers
## (docs/TECHNICAL_DESIGN.md, "Content contracts"). The dimensional limits are
## that section's initial envelopes and schemas/handling_config.schema.json:
## length 3.6-4.8 m, width 1.7-2.2 m, height 1.0-1.8 m. Wheelbase, ground
## clearance and jump envelope are nullable in the source contract; in this
## typed resource they are `null` when undetermined rather than a fake zero.
##
## This slice stores only identity, the dimensional/contact envelope, intact
## mass, a typed handling reference and explicit draft/completeness
## semantics. Presentation meshes/LODs/paints/icons, engine top speed,
## upgrades, detachable parts, surface modifiers, drift/surge/drafting/
## airborne/contact-cap tunables and all track/event content remain later
## slices; `DEFERRED_FIELDS_V1` names the deferred car fields so a draft can
## never be mistaken for production-complete data. See src/data/README.md.

enum ContactProxyShape { ROUNDED_BOX, CONVEX_HULL }
## Content coverage, distinct from lifecycle `status`: DRAFT is an early
## structural placeholder, INCOMPLETE has some authored fields but declared
## gaps. COMPLETE is reserved for a later full-car definition; this M0.2
## partial slice refuses it because `DEFERRED_FIELDS_V1` are not representable
## in these classes yet. A false COMPLETE therefore never validates and
## `is_complete()` never claims it.
enum Completeness { DRAFT, INCOMPLETE, COMPLETE }

const MIN_LENGTH_M := 3.6
const MAX_LENGTH_M := 4.8
const MIN_WIDTH_M := 1.7
const MAX_WIDTH_M := 2.2
const MIN_HEIGHT_M := 1.0
const MAX_HEIGHT_M := 1.8

## Car content fields deliberately absent from this slice. Later slices own
## them; listing them here keeps draft/completeness claims inspectable.
const DEFERRED_FIELDS_V1 := [
	"presentation.mesh_id",
	"presentation.lod_ids",
	"presentation.paints",
	"presentation.icon",
	"engine.top_speed_kmh",
	"upgrades.levels",
	"detachable_parts",
	"handling.drift",
	"handling.surge",
	"handling.drafting",
	"handling.airborne",
	"handling.contact_caps",
	"handling.surfaces",
]

@export var length_m := 0.0
@export var width_m := 0.0
@export var height_m := 0.0
## Null means undetermined; a number must be positive and no greater than
## `length_m`.
@export var wheelbase_m: Variant = null
## Null means undetermined; a number must be non-negative and no greater than
## `height_m`.
@export var ground_clearance_m: Variant = null
## Null means undetermined; a number must be non-negative.
@export var jump_envelope_m: Variant = null
## Intact mass in kg. Cosmetic damage never changes this value.
@export var mass_kg := 0.0
## Simplified rounded-box/convex-hull contact proxy derived from the declared
## dimensions; rendering detail cannot change contact.
@export var contact_proxy_shape: ContactProxyShape = ContactProxyShape.ROUNDED_BOX
## Roof/underside description for the simplified hull; null means the recipe
## has not determined it yet.
@export var contact_roof: Variant = null
@export var contact_underside: Variant = null
## Typed handling dependency. A car without one does not validate.
@export var handling: HandlingDefinition = null
@export var completeness: Completeness = Completeness.DRAFT
@export_multiline var completeness_note: String = ""
## Explicit list of fields remaining for later slices.
@export var deferred_fields: PackedStringArray = PackedStringArray()


func validate_car() -> Array[String]:
	var diagnostics := validate_identity()
	diagnostics.append_array(_validate_dimensions())
	if handling == null:
		diagnostics.append("handling: missing typed handling reference")
	else:
		# Full handling validation, not only its physical subset: identity,
		# schema version, revision and display name defects in a referenced
		# handling make the car invalid too.
		diagnostics.append_array(handling.validate())
	diagnostics.append_array(_validate_completeness())
	return diagnostics


func validate() -> Array[String]:
	return validate_car()


func is_complete() -> bool:
	# Guard the invariant rather than trusting the enum: COMPLETE is refused by
	# this partial slice, so an invalid record can never report completion.
	return completeness == Completeness.COMPLETE and is_valid()


func _validate_dimensions() -> Array[String]:
	var diagnostics: Array[String] = []
	_validate_bounded(
		"dimensions.length_m", length_m, MIN_LENGTH_M, MAX_LENGTH_M, diagnostics
	)
	_validate_bounded("dimensions.width_m", width_m, MIN_WIDTH_M, MAX_WIDTH_M, diagnostics)
	_validate_bounded("dimensions.height_m", height_m, MIN_HEIGHT_M, MAX_HEIGHT_M, diagnostics)

	if wheelbase_m != null:
		var wheelbase: Variant = _as_float("dimensions.wheelbase_m", wheelbase_m, diagnostics)
		if wheelbase != null:
			if wheelbase <= 0.0:
				diagnostics.append(
					"dimensions.wheelbase_m: non-positive %s; expected > 0" % str(wheelbase)
				)
			elif _finite(length_m) and wheelbase > length_m:
				diagnostics.append(
					"dimensions.wheelbase_m: %s exceeds length_m %s"
					% [str(wheelbase), str(length_m)]
				)

	if ground_clearance_m != null:
		var clearance: Variant = _as_float("dimensions.ground_clearance_m", ground_clearance_m, diagnostics)
		if clearance != null:
			if clearance < 0.0:
				diagnostics.append(
					"dimensions.ground_clearance_m: negative %s; expected >= 0" % str(clearance)
				)
			elif _finite(height_m) and clearance > height_m:
				diagnostics.append(
					"dimensions.ground_clearance_m: %s exceeds height_m %s"
					% [str(clearance), str(height_m)]
				)

	if jump_envelope_m != null:
		var jump: Variant = _as_float("dimensions.jump_envelope_m", jump_envelope_m, diagnostics)
		if jump != null and jump < 0.0:
			diagnostics.append(
				"dimensions.jump_envelope_m: negative %s; expected >= 0" % str(jump)
			)

	if not _finite(mass_kg):
		diagnostics.append("mass_kg: nonfinite (%s)" % str(mass_kg))
	elif mass_kg <= 0.0:
		diagnostics.append("mass_kg: non-positive %s; expected > 0" % str(mass_kg))

	diagnostics.append_array(_validate_contact_description("contact_roof", contact_roof))
	diagnostics.append_array(_validate_contact_description("contact_underside", contact_underside))
	return diagnostics


func _validate_completeness() -> Array[String]:
	var diagnostics: Array[String] = []
	if completeness == Completeness.DRAFT or completeness == Completeness.INCOMPLETE:
		if completeness_note.strip_edges().is_empty():
			diagnostics.append(
				"completeness_note: required when completeness is draft or incomplete"
			)
		if deferred_fields.is_empty():
			diagnostics.append(
				"deferred_fields: required when completeness is draft or incomplete"
			)
	elif completeness == Completeness.COMPLETE:
		diagnostics.append(
			"completeness: COMPLETE cannot be claimed by this M0.2 partial slice; "
			+ "DEFERRED_FIELDS_V1 are not yet representable"
		)
		if not deferred_fields.is_empty():
			diagnostics.append(
				"deferred_fields: empty required when completeness is complete"
			)
	for index in range(deferred_fields.size()):
		if String(deferred_fields[index]).strip_edges().is_empty():
			diagnostics.append("deferred_fields[%d]: empty entry" % index)
	return diagnostics


func _validate_contact_description(field_path: String, value: Variant) -> Array[String]:
	var diagnostics: Array[String] = []
	if value != null and typeof(value) != TYPE_STRING:
		diagnostics.append(
			"%s: expected a string description or null, got %s"
			% [field_path, type_string(typeof(value))]
		)
	return diagnostics


func _validate_bounded(
	field_path: String,
	value: float,
	minimum: float,
	maximum: float,
	diagnostics: Array[String]
) -> void:
	if not _finite(value):
		diagnostics.append("%s: nonfinite (%s)" % [field_path, str(value)])
		return
	if value < minimum:
		diagnostics.append(
			"%s: %s is below the documented envelope minimum %s m"
			% [field_path, str(value), str(minimum)]
		)
	elif value > maximum:
		diagnostics.append(
			"%s: %s is above the documented envelope maximum %s m"
			% [field_path, str(value), str(maximum)]
		)


func _as_float(field_path: String, value: Variant, diagnostics: Array[String]) -> Variant:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		diagnostics.append(
			"%s: expected a number or null, got %s"
			% [field_path, type_string(typeof(value))]
		)
		return null
	var numeric := float(value)
	if not _finite(numeric):
		diagnostics.append("%s: nonfinite (%s)" % [field_path, str(numeric)])
		return null
	return numeric


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
