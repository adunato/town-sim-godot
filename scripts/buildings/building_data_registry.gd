class_name BuildingDataRegistry
extends RefCounted

const DEFAULT_DEFINITIONS_PATH := "res://data/buildings/building_definitions.json"
const DEFAULT_VISUAL_PROFILES_PATH := "res://data/buildings/building_visual_profiles.json"
const DEFAULT_INSTANCES_PATH := "res://data/maps/prototype_building_instances.json"

const SUPPORTED_ANCHORS: Array[String] = [
	"footprint_top_left",
	"footprint_center",
	"footprint_bottom_center",
]
const SUPPORTED_Y_SORT_ORIGINS: Array[String] = [
	"footprint_bottom_center",
	"footprint_center",
]

var definitions_source_path: String = ""
var visual_profiles_source_path: String = ""
var instances_source_path: String = ""
var map_id: String = ""

var _definitions_by_id: Dictionary = {}
var _visual_profiles_by_id: Dictionary = {}
var _instances_by_id: Dictionary = {}
var _definition_order: PackedStringArray = []
var _visual_profile_order: PackedStringArray = []
var _instance_order: PackedStringArray = []


func load_definitions(definitions_path: String = DEFAULT_DEFINITIONS_PATH) -> Dictionary:
	var parsed_result := _load_json_object(definitions_path, "Building definitions")
	if not parsed_result.ok:
		return parsed_result

	var validation := validate_definitions_data(parsed_result.data, definitions_path)
	if not validation.ok:
		return validation

	_definitions_by_id.clear()
	_definition_order.clear()
	definitions_source_path = definitions_path

	for definition in parsed_result.data.definitions:
		var definition_id := String(definition.id)
		_definitions_by_id[definition_id] = definition.duplicate(true)
		_definition_order.append(definition_id)

	return _success({"definition_count": _definition_order.size()})


func load_visual_profiles(visual_profiles_path: String = DEFAULT_VISUAL_PROFILES_PATH) -> Dictionary:
	var parsed_result := _load_json_object(visual_profiles_path, "Building visual profiles")
	if not parsed_result.ok:
		return parsed_result

	var validation := validate_visual_profiles_data(parsed_result.data, visual_profiles_path)
	if not validation.ok:
		return validation

	_visual_profiles_by_id.clear()
	_visual_profile_order.clear()
	visual_profiles_source_path = visual_profiles_path

	for profile in parsed_result.data.profiles:
		var profile_id := String(profile.id)
		_visual_profiles_by_id[profile_id] = profile.duplicate(true)
		_visual_profile_order.append(profile_id)

	return _success({"visual_profile_count": _visual_profile_order.size()})


func load_instances(instances_path: String = DEFAULT_INSTANCES_PATH) -> Dictionary:
	var parsed_result := _load_json_object(instances_path, "Building instances")
	if not parsed_result.ok:
		return parsed_result

	var validation := validate_instances_data(parsed_result.data, instances_path)
	if not validation.ok:
		return validation

	_instances_by_id.clear()
	_instance_order.clear()
	instances_source_path = instances_path
	map_id = String(parsed_result.data.get("map_id", ""))

	for instance in parsed_result.data.instances:
		var instance_id := String(instance.instance_id)
		_instances_by_id[instance_id] = instance.duplicate(true)
		_instance_order.append(instance_id)

	return _success({"instance_count": _instance_order.size()})


func load_all(
	definitions_path: String = DEFAULT_DEFINITIONS_PATH,
	instances_path: String = DEFAULT_INSTANCES_PATH,
	visual_profiles_path: String = DEFAULT_VISUAL_PROFILES_PATH
) -> Dictionary:
	var definitions_result := load_definitions(definitions_path)
	if not definitions_result.ok:
		return definitions_result

	var visual_profiles_result := load_visual_profiles(visual_profiles_path)
	if not visual_profiles_result.ok:
		return visual_profiles_result

	var instances_result := load_instances(instances_path)
	if not instances_result.ok:
		return instances_result

	var reference_result := validate_loaded_data()
	if not reference_result.ok:
		return reference_result

	return _success({
		"definition_count": definitions_result.definition_count,
		"visual_profile_count": visual_profiles_result.visual_profile_count,
		"instance_count": instances_result.instance_count,
	})


func has_definition(definition_id: String) -> bool:
	return _definitions_by_id.has(definition_id)


func has_visual_profile(profile_id: String) -> bool:
	return _visual_profiles_by_id.has(profile_id)


func get_definition(definition_id: String) -> Dictionary:
	if not has_definition(definition_id):
		return _failure("Unknown building definition id '%s'." % definition_id)

	return _success({"definition": _definitions_by_id[definition_id].duplicate(true)})


func get_visual_profile(profile_id: String) -> Dictionary:
	if not has_visual_profile(profile_id):
		return _failure("Unknown building visual profile id '%s'." % profile_id)

	return _success({"visual_profile": _visual_profiles_by_id[profile_id].duplicate(true)})


func get_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for definition_id in _definition_order:
		definitions.append(_definitions_by_id[definition_id].duplicate(true))
	return definitions


func get_visual_profiles() -> Array[Dictionary]:
	var visual_profiles: Array[Dictionary] = []
	for profile_id in _visual_profile_order:
		visual_profiles.append(_visual_profiles_by_id[profile_id].duplicate(true))
	return visual_profiles


func get_instances() -> Array[Dictionary]:
	var instances: Array[Dictionary] = []
	for instance_id in _instance_order:
		instances.append(_instances_by_id[instance_id].duplicate(true))
	return instances


func resolve_definition_visual_profile(definition: Dictionary) -> Dictionary:
	if not definition.has("id"):
		return _failure("Building definition record is missing required field 'id'.")
	if not definition.has("visual_profile_id"):
		return _failure("Building definition '%s' is missing required field 'visual_profile_id'." % definition.get("id", "<unknown>"))

	var profile_id := String(definition.visual_profile_id)
	var profile_result := get_visual_profile(profile_id)
	if not profile_result.ok:
		return _failure("Building definition '%s' references unknown visual_profile_id '%s'." % [definition.id, profile_id])

	var footprint_result := validate_visual_profile_footprint_match(definition, profile_result.visual_profile)
	if not footprint_result.ok:
		return footprint_result

	return _success({
		"definition": definition.duplicate(true),
		"visual_profile": profile_result.visual_profile,
	})


func resolve_instance_definition(instance_record: Dictionary) -> Dictionary:
	if not instance_record.has("definition_id"):
		return _failure("Building instance record is missing required field 'definition_id'.")

	var definition_id := String(instance_record.definition_id)
	var definition_result := get_definition(definition_id)
	if not definition_result.ok:
		return _failure("Building instance '%s' references unknown definition_id '%s'." % [instance_record.get("instance_id", "<unknown>"), definition_id])

	return _success({
		"instance": instance_record.duplicate(true),
		"definition": definition_result.definition,
	})


func resolve_instance_visual_profile(instance_record: Dictionary) -> Dictionary:
	var definition_result := resolve_instance_definition(instance_record)
	if not definition_result.ok:
		return definition_result

	var visual_result := resolve_definition_visual_profile(definition_result.definition)
	if not visual_result.ok:
		return _failure("Building instance '%s' could not resolve visual profile: %s" % [instance_record.get("instance_id", "<unknown>"), visual_result.error])

	return _success({
		"instance": definition_result.instance,
		"definition": definition_result.definition,
		"visual_profile": visual_result.visual_profile,
	})


func validate_loaded_data() -> Dictionary:
	if _definitions_by_id.is_empty():
		return _failure("No building definitions are loaded.")
	if _visual_profiles_by_id.is_empty():
		return _failure("No building visual profiles are loaded.")

	for definition_id in _definition_order:
		var visual_result := resolve_definition_visual_profile(_definitions_by_id[definition_id])
		if not visual_result.ok:
			return visual_result

	for instance_id in _instance_order:
		var reference_result := resolve_instance_definition(_instances_by_id[instance_id])
		if not reference_result.ok:
			return reference_result

	return _success()


func validate_definitions_data(data: Dictionary, source_name: String) -> Dictionary:
	if not data.has("schema_version"):
		return _failure("%s is missing required field 'schema_version'." % source_name)
	if not _is_integer_number(data.schema_version):
		return _failure("%s field 'schema_version' must be an integer." % source_name)
	if int(data.schema_version) != 1:
		return _failure("%s field 'schema_version' must be 1." % source_name)
	if not data.has("definitions"):
		return _failure("%s is missing required field 'definitions'." % source_name)
	if typeof(data.definitions) != TYPE_ARRAY:
		return _failure("%s field 'definitions' must be an array." % source_name)
	if data.definitions.is_empty():
		return _failure("%s field 'definitions' must contain at least one building definition." % source_name)

	var seen_ids: Dictionary = {}
	for index in range(data.definitions.size()):
		var definition: Variant = data.definitions[index]
		if typeof(definition) != TYPE_DICTIONARY:
			return _failure("%s definitions[%d] must be an object." % [source_name, index])

		var validation := _validate_definition(definition, source_name, index)
		if not validation.ok:
			return validation

		var definition_id := String(definition.id)
		if seen_ids.has(definition_id):
			return _failure("%s definition id '%s' is duplicated." % [source_name, definition_id])
		seen_ids[definition_id] = true

	return _success()


func validate_visual_profiles_data(data: Dictionary, source_name: String) -> Dictionary:
	if not data.has("schema_version"):
		return _failure("%s is missing required field 'schema_version'." % source_name)
	if not _is_integer_number(data.schema_version):
		return _failure("%s field 'schema_version' must be an integer." % source_name)
	if int(data.schema_version) != 1:
		return _failure("%s field 'schema_version' must be 1." % source_name)
	if not data.has("profiles"):
		return _failure("%s is missing required field 'profiles'." % source_name)
	if typeof(data.profiles) != TYPE_ARRAY:
		return _failure("%s field 'profiles' must be an array." % source_name)
	if data.profiles.is_empty():
		return _failure("%s field 'profiles' must contain at least one visual profile." % source_name)

	var seen_ids: Dictionary = {}
	for index in range(data.profiles.size()):
		var profile: Variant = data.profiles[index]
		if typeof(profile) != TYPE_DICTIONARY:
			return _failure("%s profiles[%d] must be an object." % [source_name, index])

		var validation := _validate_visual_profile(profile, source_name, index)
		if not validation.ok:
			return validation

		var profile_id := String(profile.id)
		if seen_ids.has(profile_id):
			return _failure("%s visual profile id '%s' is duplicated." % [source_name, profile_id])
		seen_ids[profile_id] = true

	return _success()


func validate_instances_data(data: Dictionary, source_name: String) -> Dictionary:
	if not data.has("schema_version"):
		return _failure("%s is missing required field 'schema_version'." % source_name)
	if not _is_integer_number(data.schema_version):
		return _failure("%s field 'schema_version' must be an integer." % source_name)
	if int(data.schema_version) != 1:
		return _failure("%s field 'schema_version' must be 1." % source_name)
	if not data.has("map_id"):
		return _failure("%s is missing required field 'map_id'." % source_name)
	if typeof(data.map_id) != TYPE_STRING or String(data.map_id).strip_edges().is_empty():
		return _failure("%s field 'map_id' must be a non-empty string." % source_name)
	if not data.has("instances"):
		return _failure("%s is missing required field 'instances'." % source_name)
	if typeof(data.instances) != TYPE_ARRAY:
		return _failure("%s field 'instances' must be an array." % source_name)

	var seen_ids: Dictionary = {}
	for index in range(data.instances.size()):
		var instance: Variant = data.instances[index]
		if typeof(instance) != TYPE_DICTIONARY:
			return _failure("%s instances[%d] must be an object." % [source_name, index])

		var validation := _validate_instance(instance, source_name, index)
		if not validation.ok:
			return validation

		var instance_id := String(instance.instance_id)
		if seen_ids.has(instance_id):
			return _failure("%s instance id '%s' is duplicated." % [source_name, instance_id])
		seen_ids[instance_id] = true

	return _success()


func validate_instance_references(source_name: String = "<loaded instances>") -> Dictionary:
	for instance_id in _instance_order:
		var instance: Dictionary = _instances_by_id[instance_id]
		var definition_id := String(instance.definition_id)
		if not has_definition(definition_id):
			return _failure("%s instance id '%s' references unknown definition_id '%s'." % [source_name, instance_id, definition_id])

	return _success()


func validate_visual_profile_references(source_name: String = "<loaded definitions>") -> Dictionary:
	for definition_id in _definition_order:
		var definition: Dictionary = _definitions_by_id[definition_id]
		var profile_id := String(definition.visual_profile_id)
		if not has_visual_profile(profile_id):
			return _failure("%s definition id '%s' references unknown visual_profile_id '%s'." % [source_name, definition_id, profile_id])
		var footprint_result := validate_visual_profile_footprint_match(definition, _visual_profiles_by_id[profile_id])
		if not footprint_result.ok:
			return footprint_result

	return _success()


func validate_visual_profile_footprint_match(definition: Dictionary, profile: Dictionary) -> Dictionary:
	if not definition.has("footprint_cells") or not profile.has("expected_footprint_cells"):
		return _failure("Cannot compare building footprint to visual profile footprint because required fields are missing.")
	var definition_footprint := _footprint_to_vector(definition.footprint_cells)
	var expected_footprint := _footprint_to_vector(profile.expected_footprint_cells)
	if definition_footprint != expected_footprint:
		return _failure("Building definition '%s' footprint %s does not match visual profile '%s' expected footprint %s." % [definition.get("id", "<unknown>"), definition_footprint, profile.get("id", "<unknown>"), expected_footprint])
	return _success()


func _validate_definition(definition: Dictionary, source_name: String, index: int) -> Dictionary:
	var location := "%s definitions[%d]" % [source_name, index]
	for field in ["id", "display_name", "footprint_cells", "visual_profile_id", "prototype_color", "selectable", "interactable"]:
		if not definition.has(field):
			return _failure("%s is missing required field '%s'." % [location, field])

	if typeof(definition.id) != TYPE_STRING or String(definition.id).strip_edges().is_empty():
		return _failure("%s field 'id' must be a non-empty string." % location)
	if String(definition.id) != String(definition.id).to_lower():
		return _failure("%s field 'id' must be lowercase." % location)
	if not _is_valid_identifier(String(definition.id)):
		return _failure("%s field 'id' must contain only lowercase letters, numbers, and underscores." % location)
	if typeof(definition.display_name) != TYPE_STRING or String(definition.display_name).strip_edges().is_empty():
		return _failure("%s field 'display_name' must be a non-empty string." % location)
	if not _is_footprint_dictionary(definition.footprint_cells):
		return _failure("%s field 'footprint_cells' must contain positive integer width and height fields." % location)
	if typeof(definition.visual_profile_id) != TYPE_STRING or String(definition.visual_profile_id).strip_edges().is_empty():
		return _failure("%s field 'visual_profile_id' must be a non-empty string." % location)
	if typeof(definition.prototype_color) != TYPE_STRING or not _is_valid_hex_color(String(definition.prototype_color)):
		return _failure("%s field 'prototype_color' must use #RRGGBB format." % location)
	if typeof(definition.selectable) != TYPE_BOOL:
		return _failure("%s field 'selectable' must be a boolean." % location)
	if typeof(definition.interactable) != TYPE_BOOL:
		return _failure("%s field 'interactable' must be a boolean." % location)

	return _success()


func _validate_visual_profile(profile: Dictionary, source_name: String, index: int) -> Dictionary:
	var location := "%s profiles[%d]" % [source_name, index]
	for field in ["id", "texture_path", "anchor", "pixel_offset", "y_sort_origin", "expected_footprint_cells"]:
		if not profile.has(field):
			return _failure("%s is missing required field '%s'." % [location, field])

	if typeof(profile.id) != TYPE_STRING or String(profile.id).strip_edges().is_empty():
		return _failure("%s field 'id' must be a non-empty string." % location)
	if not _is_valid_identifier(String(profile.id)):
		return _failure("%s field 'id' must contain only lowercase letters, numbers, and underscores." % location)
	if typeof(profile.texture_path) != TYPE_STRING or String(profile.texture_path).strip_edges().is_empty():
		return _failure("%s field 'texture_path' must be a non-empty string." % location)
	if not String(profile.texture_path).begins_with("res://"):
		return _failure("%s field 'texture_path' must use a res:// path." % location)
	if not FileAccess.file_exists(String(profile.texture_path)):
		return _failure("%s field 'texture_path' references missing resource '%s'." % [location, profile.texture_path])
	var image := Image.new()
	var image_error := image.load(String(profile.texture_path))
	if image_error != OK:
		return _failure("%s field 'texture_path' must reference a readable image resource." % location)
	if not _is_valid_source_rect(profile.get("source_rect", null), image.get_width(), image.get_height()):
		return _failure("%s field 'source_rect' must be null or contain non-negative integer x/y and positive width/height inside the texture." % location)
	if typeof(profile.anchor) != TYPE_STRING or not SUPPORTED_ANCHORS.has(String(profile.anchor)):
		return _failure("%s field 'anchor' uses unsupported value '%s'." % [location, profile.get("anchor", "")])
	if not _is_vector2i_dictionary(profile.pixel_offset):
		return _failure("%s field 'pixel_offset' must contain integer x and y fields." % location)
	if typeof(profile.y_sort_origin) != TYPE_STRING or not SUPPORTED_Y_SORT_ORIGINS.has(String(profile.y_sort_origin)):
		return _failure("%s field 'y_sort_origin' uses unsupported value '%s'." % [location, profile.get("y_sort_origin", "")])
	if not _is_footprint_dictionary(profile.expected_footprint_cells):
		return _failure("%s field 'expected_footprint_cells' must contain positive integer width and height fields." % location)

	return _success()


func _validate_instance(instance: Dictionary, source_name: String, index: int) -> Dictionary:
	var location := "%s instances[%d]" % [source_name, index]
	for field in ["instance_id", "definition_id", "origin_cell"]:
		if not instance.has(field):
			return _failure("%s is missing required field '%s'." % [location, field])

	if typeof(instance.instance_id) != TYPE_STRING or String(instance.instance_id).strip_edges().is_empty():
		return _failure("%s field 'instance_id' must be a non-empty string." % location)
	if typeof(instance.definition_id) != TYPE_STRING or String(instance.definition_id).strip_edges().is_empty():
		return _failure("%s field 'definition_id' must be a non-empty string." % location)
	if not _is_vector2i_dictionary(instance.origin_cell):
		return _failure("%s field 'origin_cell' must contain integer x and y fields." % location)

	return _success()


func _load_json_object(path: String, label: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Unable to read %s file '%s': %s" % [label.to_lower(), path, error_string(FileAccess.get_open_error())])

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("%s file '%s' must be a JSON object." % [label, path])

	return _success({"data": parsed})


func _is_footprint_dictionary(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false

	return value.has("width") and value.has("height") \
		and _is_integer_number(value.width) \
		and _is_integer_number(value.height) \
		and int(value.width) > 0 \
		and int(value.height) > 0


func _is_vector2i_dictionary(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false

	return value.has("x") and value.has("y") \
		and _is_integer_number(value.x) \
		and _is_integer_number(value.y)


func _is_valid_source_rect(value: Variant, texture_width: int, texture_height: int) -> bool:
	if value == null:
		return true
	if typeof(value) != TYPE_DICTIONARY:
		return false
	if not value.has("x") or not value.has("y") or not value.has("width") or not value.has("height"):
		return false
	if not _is_integer_number(value.x) or not _is_integer_number(value.y) or not _is_integer_number(value.width) or not _is_integer_number(value.height):
		return false
	var rect := Rect2i(int(value.x), int(value.y), int(value.width), int(value.height))
	if rect.position.x < 0 or rect.position.y < 0 or rect.size.x <= 0 or rect.size.y <= 0:
		return false
	return rect.position.x + rect.size.x <= texture_width and rect.position.y + rect.size.y <= texture_height


func _footprint_to_vector(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.width), int(value.height))


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false

	return is_equal_approx(float(value), float(int(value)))


func _is_valid_identifier(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-z0-9_]+$")
	return regex.search(value) != null


func _is_valid_hex_color(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^#[0-9A-Fa-f]{6}$")
	return regex.search(value) != null


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true}
	result.merge(extra, true)
	return result


func _failure(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"error": message,
	}
	result.merge(extra, true)
	return result
