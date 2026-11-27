class_name DefinitionIdentity
extends Resource
## Versioned stable semantic identity shared by the M0.2 typed definitions.
##
## This mirrors the stable-ID, schema-version, revision and status vocabulary
## of schemas/common.schema.json and schemas/handling_config.schema.json:
## display names may change, stable semantic IDs and revisions must not.
## It also pins the documented units and local frame so runtime resources and
## authored recipes cannot drift apart silently.
##
## This slice carries identity only. It holds no physical content, computes no
## content hash, and is not a track, event, upgrade, ghost or AI definition.

enum Status { PROVISIONAL, MEASURED, FROZEN, SUPERSEDED, EXAMPLE }

## Contract revision implemented by this class. Any other value is rejected
## with a diagnostic; there is no automatic migration.
const SUPPORTED_SCHEMA_VERSION := "1.0.0"

## Same grammar as common.schema.json `stable_id`: one lowercase leading
## segment followed by dot-separated segments. Validation applies it as a
## whole-string match; the pattern itself stays aligned with the JSON schema,
## whose regex-engine `$` handling of a final line feed varies by validator.
const DEFINITION_ID_PATTERN := "^[a-z][a-z0-9_]*(?:\\.[a-z0-9_-]+)*$"

## Major.minor.patch with no leading zeros; semantic ordering is the recipe
## layer's concern, not this slice's. This typed-resource requirement is stricter
## than schemas/handling_config.schema.json, whose source `revision` is any
## nonempty string; the runtime vocabulary is the numeric triplet above.
const REVISION_PATTERN := "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"

## Documented units and local frame from docs/TECHNICAL_DESIGN.md
## ("Content contracts"): metres/kg/seconds, +Y up, -Z forward, origin at the
## ground projection of the axle midpoint, wheel pivots at local axle centers.
const UNIT_LENGTH := "m"
const UNIT_MASS := "kg"
const UNIT_TIME := "s"
const UNIT_ANGLE := "deg"
const FRAME_FORWARD := "-Z"
const FRAME_UP := "+Y"
const FRAME_ORIGIN := "ground_projection_of_axle_midpoint"

@export var schema_version: String = SUPPORTED_SCHEMA_VERSION
## Stable semantic ID. Never rename an existing ID to change its meaning.
@export var definition_id: String = ""
## Content revision in major.minor.patch form.
@export var revision: String = "0.1.0"
@export var display_name: String = ""
@export var status: Status = Status.PROVISIONAL
@export_multiline var notes: String = ""


## Identity diagnostics only. Subclasses append their own field diagnostics.
func validate_identity() -> Array[String]:
	var diagnostics: Array[String] = []
	if schema_version != SUPPORTED_SCHEMA_VERSION:
		diagnostics.append(
			"schema_version: unsupported '%s' (supported: %s)"
			% [schema_version, SUPPORTED_SCHEMA_VERSION]
		)
	if not is_valid_definition_id(definition_id):
		diagnostics.append(
			"definition_id: malformed '%s' (expected stable semantic ID matching %s)"
			% [definition_id, DEFINITION_ID_PATTERN]
		)
	if not is_valid_revision(revision):
		diagnostics.append(
			"revision: malformed '%s' (expected MAJOR.MINOR.PATCH without leading zeros)"
			% revision
		)
	if not Status.values().has(status):
		diagnostics.append(
			"status: out-of-range value %s; expected one of %s"
			% [str(status), _enum_value_names(Status)]
		)
	if display_name.is_empty():
		diagnostics.append("display_name: empty")
	return diagnostics


func validate() -> Array[String]:
	return validate_identity()


func is_valid() -> bool:
	return validate().is_empty()


## Stable key for logs and cross-references; not a content hash.
func identity_key() -> String:
	return "%s/%s@%s" % [schema_version, definition_id, revision]


## Lifecycle name for logs. An integer-backed enum can hold an out-of-domain
## value through direct assignment or a malformed `.tres`; this stays total and
## reports INVALID rather than indexing outside `Status.keys()`. The typed
## uppercase names intentionally differ from the lowercase JSON vocabulary
## (`provisional|measured|frozen|superseded|example`); see schemas.
func status_name() -> String:
	var names := Status.keys()
	if status < 0 or status >= names.size():
		return "INVALID"
	return names[status]


func documented_units() -> Dictionary:
	return {
		"length": UNIT_LENGTH,
		"mass": UNIT_MASS,
		"time": UNIT_TIME,
		"angle": UNIT_ANGLE,
	}


func documented_frame() -> Dictionary:
	return {
		"forward": FRAME_FORWARD,
		"up": FRAME_UP,
		"origin": FRAME_ORIGIN,
	}


static func is_valid_definition_id(value: String) -> bool:
	return _matches(DEFINITION_ID_PATTERN, value)


static func is_valid_revision(value: String) -> bool:
	return _matches(REVISION_PATTERN, value)


## Require a match that spans the entire value. A bare `search()` would accept
## a prefix when `$` stops before a final line feed (`"car.comet\n"`), letting
## malformed identities enter `identity_key()` verbatim.
static func _matches(pattern: String, value: String) -> bool:
	if value.is_empty():
		return false
	for match in RegEx.create_from_string(pattern).search_all(value):
		if match.get_start() == 0 and match.get_end() == value.length():
			return true
	return false


static func _enum_value_names(values: Dictionary) -> String:
	var names: PackedStringArray = []
	for key in values.keys():
		names.append(String(key))
	return ", ".join(names)
