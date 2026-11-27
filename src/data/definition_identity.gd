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
## segment followed by dot-separated segments.
const DEFINITION_ID_PATTERN := "^[a-z][a-z0-9_]*(?:\\.[a-z0-9_-]+)*$"

## Major.minor.patch with no leading zeros; semantic ordering is the recipe
## layer's concern, not this slice's.
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


func status_name() -> String:
	return Status.keys()[status]


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


static func _matches(pattern: String, value: String) -> bool:
	if value.is_empty():
		return false
	return RegEx.create_from_string(pattern).search(value) != null
