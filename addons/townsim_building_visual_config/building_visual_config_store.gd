@tool
class_name BuildingVisualConfigStore
extends RefCounted

const BuildingDataRegistryScript := preload("res://scripts/buildings/building_data_registry.gd")

const DEFAULT_DEFINITIONS_PATH := "res://data/buildings/building_definitions.json"
const DEFAULT_VISUAL_PROFILES_PATH := "res://data/buildings/building_visual_profiles.json"

var definitions_path := DEFAULT_DEFINITIONS_PATH
var visual_profiles_path := DEFAULT_VISUAL_PROFILES_PATH

var _definitions_data: Dictionary = {}
var _visual_profiles_data: Dictionary = {}
var _registry: RefCounted


func load_data(
	next_definitions_path: String = DEFAULT_DEFINITIONS_PATH,
	next_visual_profiles_path: String = DEFAULT_VISUAL_PROFILES_PATH
) -> Dictionary:
	definitions_path = next_definitions_path
	visual_profiles_path = next_visual_profiles_path

	var definitions_result := _load_json_object(definitions_path, "building definitions")
	if not definitions_result.ok:
		return definitions_result
	var visual_profiles_result := _load_json_object(visual_profiles_path, "building visual profiles")
	if not visual_profiles_result.ok:
		return visual_profiles_result

	_registry = BuildingDataRegistryScript.new()
	var definitions_validation: Dictionary = _registry.call("validate_definitions_data", definitions_result.data, definitions_path)
	if not definitions_validation.ok:
		return definitions_validation
	var profiles_validation: Dictionary = _registry.call("validate_visual_profiles_data", visual_profiles_result.data, visual_profiles_path)
	if not profiles_validation.ok:
		return profiles_validation

	_definitions_data = definitions_result.data.duplicate(true)
	_visual_profiles_data = visual_profiles_result.data.duplicate(true)

	var load_definitions: Dictionary = _registry.call("load_definitions", definitions_path)
	if not load_definitions.ok:
		return load_definitions
	var load_profiles: Dictionary = _registry.call("load_visual_profiles", visual_profiles_path)
	if not load_profiles.ok:
		return load_profiles

	return _success({
		"definition_count": _definitions_data.definitions.size(),
		"visual_profile_count": _visual_profiles_data.profiles.size(),
	})


func get_supported_anchors() -> Array[String]:
	return BuildingDataRegistryScript.SUPPORTED_ANCHORS.duplicate()


func get_supported_y_sort_origins() -> Array[String]:
	return BuildingDataRegistryScript.SUPPORTED_Y_SORT_ORIGINS.duplicate()


func get_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for definition in _definitions_data.get("definitions", []):
		definitions.append(definition.duplicate(true))
	return definitions


func get_visual_profiles() -> Array[Dictionary]:
	var profiles: Array[Dictionary] = []
	for profile in _visual_profiles_data.get("profiles", []):
		profiles.append(profile.duplicate(true))
	return profiles


func get_definition(definition_id: String) -> Dictionary:
	for definition in _definitions_data.get("definitions", []):
		if String(definition.get("id", "")) == definition_id:
			return _success({"definition": definition.duplicate(true)})
	return _failure("Unknown building definition id '%s'." % definition_id)


func get_visual_profile(profile_id: String) -> Dictionary:
	for profile in _visual_profiles_data.get("profiles", []):
		if String(profile.get("id", "")) == profile_id:
			return _success({"visual_profile": profile.duplicate(true)})
	return _failure("Unknown building visual profile id '%s'." % profile_id)


func get_validation_messages(definition: Dictionary, profile: Dictionary) -> Array[String]:
	var messages: Array[String] = []
	if definition.is_empty():
		messages.append("Select a building definition.")
		return messages
	if profile.is_empty():
		messages.append("Select a visual profile.")
		return messages

	var definitions_data := _definitions_data.duplicate(true)
	var profiles_data := _visual_profiles_data.duplicate(true)
	_replace_record(definitions_data.definitions, definition)
	_replace_record(profiles_data.profiles, profile)

	var registry = BuildingDataRegistryScript.new()
	var definitions_validation: Dictionary = registry.call("validate_definitions_data", definitions_data, definitions_path)
	if not definitions_validation.ok:
		messages.append(String(definitions_validation.error))
	var profiles_validation: Dictionary = registry.call("validate_visual_profiles_data", profiles_data, visual_profiles_path)
	if not profiles_validation.ok:
		messages.append(String(profiles_validation.error))

	var assigned_profile_id := String(definition.get("visual_profile_id", ""))
	var assigned_profile := profile
	if String(profile.get("id", "")) != assigned_profile_id:
		var lookup := _find_record(profiles_data.profiles, assigned_profile_id)
		if lookup.is_empty():
			messages.append("Building definition '%s' references unknown visual_profile_id '%s'." % [definition.get("id", "<unknown>"), assigned_profile_id])
		else:
			assigned_profile = lookup

	if messages.is_empty():
		var footprint_result: Dictionary = registry.call("validate_visual_profile_footprint_match", definition, assigned_profile)
		if not footprint_result.ok:
			messages.append(String(footprint_result.error))

	return messages


func apply_definition_profile_id(definition_id: String, profile_id: String) -> Dictionary:
	for definition in _definitions_data.get("definitions", []):
		if String(definition.get("id", "")) == definition_id:
			definition.visual_profile_id = profile_id
			return _success()
	return _failure("Unknown building definition id '%s'." % definition_id)


func apply_visual_profile_fields(profile_id: String, fields: Dictionary) -> Dictionary:
	for profile in _visual_profiles_data.get("profiles", []):
		if String(profile.get("id", "")) == profile_id:
			for field in fields.keys():
				profile[field] = fields[field]
			return _success()
	return _failure("Unknown building visual profile id '%s'." % profile_id)


func save(
	target_definitions_path: String = definitions_path,
	target_visual_profiles_path: String = visual_profiles_path
) -> Dictionary:
	var definitions_result := _write_json_object(target_definitions_path, _definitions_data)
	if not definitions_result.ok:
		return definitions_result
	var profiles_result := _write_json_object(target_visual_profiles_path, _visual_profiles_data)
	if not profiles_result.ok:
		return profiles_result
	return _success()


func _replace_record(records: Array, record: Dictionary) -> void:
	var record_id := String(record.get("id", ""))
	for index in range(records.size()):
		if String(records[index].get("id", "")) == record_id:
			records[index] = record.duplicate(true)
			return


func _find_record(records: Array, record_id: String) -> Dictionary:
	for record in records:
		if String(record.get("id", "")) == record_id:
			return record.duplicate(true)
	return {}


func _load_json_object(path: String, label: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Unable to read %s file '%s': %s" % [label, path, error_string(FileAccess.get_open_error())])

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("%s file '%s' must be a JSON object." % [label.capitalize(), path])
	return _success({"data": parsed})


func _write_json_object(path: String, data: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("Unable to write JSON file '%s': %s" % [path, error_string(FileAccess.get_open_error())])
	file.store_string(JSON.stringify(data, "\t"))
	file.store_string("\n")
	return _success()


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
