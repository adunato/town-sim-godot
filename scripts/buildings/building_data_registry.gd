class_name BuildingDataRegistry
extends RefCounted

const DEFAULT_DEFINITIONS_PATH := "res://data/buildings/building_definitions.json"
const DEFAULT_INSTANCES_PATH := "res://data/maps/prototype_building_instances.json"

var definitions_source_path: String = ""
var instances_source_path: String = ""
var map_id: String = ""

var _definitions_by_id: Dictionary = {}
var _instances_by_id: Dictionary = {}
var _definition_order: PackedStringArray = []
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


func load_all(definitions_path: String = DEFAULT_DEFINITIONS_PATH, instances_path: String = DEFAULT_INSTANCES_PATH) -> Dictionary:
	var definitions_result := load_definitions(definitions_path)
	if not definitions_result.ok:
		return definitions_result

	var instances_result := load_instances(instances_path)
	if not instances_result.ok:
		return instances_result

	var reference_result := validate_instance_references(instances_path)
	if not reference_result.ok:
		return reference_result

	return _success({
		"definition_count": definitions_result.definition_count,
		"instance_count": instances_result.instance_count,
	})


func has_definition(definition_id: String) -> bool:
	return _definitions_by_id.has(definition_id)


func get_definition(definition_id: String) -> Dictionary:
	if not has_definition(definition_id):
		return _failure("Unknown building definition id '%s'." % definition_id)

	return _success({"definition": _definitions_by_id[definition_id].duplicate(true)})


func get_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for definition_id in _definition_order:
		definitions.append(_definitions_by_id[definition_id].duplicate(true))
	return definitions


func get_instances() -> Array[Dictionary]:
	var instances: Array[Dictionary] = []
	for instance_id in _instance_order:
		instances.append(_instances_by_id[instance_id].duplicate(true))
	return instances


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


func validate_loaded_data() -> Dictionary:
	if _definitions_by_id.is_empty():
		return _failure("No building definitions are loaded.")

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


func _validate_definition(definition: Dictionary, source_name: String, index: int) -> Dictionary:
	var location := "%s definitions[%d]" % [source_name, index]
	for field in ["id", "display_name", "footprint_cells", "prototype_color", "selectable", "interactable"]:
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
	if typeof(definition.prototype_color) != TYPE_STRING or not _is_valid_hex_color(String(definition.prototype_color)):
		return _failure("%s field 'prototype_color' must use #RRGGBB format." % location)
	if typeof(definition.selectable) != TYPE_BOOL:
		return _failure("%s field 'selectable' must be a boolean." % location)
	if typeof(definition.interactable) != TYPE_BOOL:
		return _failure("%s field 'interactable' must be a boolean." % location)

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
