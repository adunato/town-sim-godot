@tool
class_name BuildingConfigStore
extends RefCounted

const BuildingDataRegistryScript := preload("res://scripts/buildings/building_data_registry.gd")
const TerrainMaterialCatalogScript := preload("res://scripts/terrain/terrain_material_catalog.gd")

const DEFAULT_DEFINITIONS_PATH := "res://data/buildings/building_definitions.json"
const DEFAULT_VISUAL_PROFILES_PATH := "res://data/buildings/building_visual_profiles.json"
const DEFAULT_TERRAIN_CATALOG_PATH := "res://data/terrain/prototype_terrain_materials.json"

var definitions_path := DEFAULT_DEFINITIONS_PATH
var visual_profiles_path := DEFAULT_VISUAL_PROFILES_PATH
var terrain_catalog_path := DEFAULT_TERRAIN_CATALOG_PATH

var _persisted_definitions: Dictionary = {}
var _persisted_profiles: Dictionary = {}
var _working_definitions: Dictionary = {}
var _working_profiles: Dictionary = {}
var _terrain_materials: Array[Dictionary] = []


func load_data(
	next_definitions_path: String = DEFAULT_DEFINITIONS_PATH,
	next_visual_profiles_path: String = DEFAULT_VISUAL_PROFILES_PATH,
	next_terrain_catalog_path: String = DEFAULT_TERRAIN_CATALOG_PATH
) -> Dictionary:
	definitions_path = next_definitions_path
	visual_profiles_path = next_visual_profiles_path
	terrain_catalog_path = next_terrain_catalog_path

	var definitions_result := _load_json_object(definitions_path, "building definitions")
	if not definitions_result.ok:
		return definitions_result
	var profiles_result := _load_json_object(visual_profiles_path, "building visual profiles")
	if not profiles_result.ok:
		return profiles_result

	var validation := _validate_complete_data(definitions_result.data, profiles_result.data)
	if not validation.ok:
		return validation
	var terrain_result := _load_terrain_materials(terrain_catalog_path)
	if not terrain_result.ok:
		return terrain_result

	_persisted_definitions = definitions_result.data.duplicate(true)
	_persisted_profiles = profiles_result.data.duplicate(true)
	_working_definitions = _persisted_definitions.duplicate(true)
	_working_profiles = _persisted_profiles.duplicate(true)
	_terrain_materials = terrain_result.materials
	return _success({
		"definition_count": get_definitions().size(),
		"visual_profile_count": get_visual_profiles().size(),
		"terrain_material_count": _terrain_materials.size(),
	})


func reload() -> Dictionary:
	return load_data(definitions_path, visual_profiles_path, terrain_catalog_path)


func get_supported_anchors() -> Array[String]:
	return BuildingDataRegistryScript.SUPPORTED_ANCHORS.duplicate()


func get_supported_y_sort_origins() -> Array[String]:
	return BuildingDataRegistryScript.SUPPORTED_Y_SORT_ORIGINS.duplicate()


func get_definitions() -> Array[Dictionary]:
	return _duplicate_records(_working_definitions.get("definitions", []))


func get_visual_profiles() -> Array[Dictionary]:
	return _duplicate_records(_working_profiles.get("profiles", []))


func get_terrain_materials() -> Array[Dictionary]:
	return _duplicate_records(_terrain_materials)


func get_definition(definition_id: String) -> Dictionary:
	var definition := _find_record(_working_definitions.get("definitions", []), definition_id)
	if definition.is_empty():
		return _failure("Unknown building definition id '%s'." % definition_id)
	return _success({"definition": definition})


func get_visual_profile(profile_id: String) -> Dictionary:
	var profile := _find_record(_working_profiles.get("profiles", []), profile_id)
	if profile.is_empty():
		return _failure("Unknown building visual profile id '%s'." % profile_id)
	return _success({"visual_profile": profile})


func get_assigned_profile(definition_id: String) -> Dictionary:
	var definition_result := get_definition(definition_id)
	if not definition_result.ok:
		return definition_result
	return get_visual_profile(String(definition_result.definition.get("visual_profile_id", "")))


func get_terrain_material(material_id: String) -> Dictionary:
	var material := _find_record(_terrain_materials, material_id)
	if material.is_empty():
		return _failure("Unknown terrain material id '%s'." % material_id)
	return _success({"terrain_material": material})


func update_definition_fields(definition_id: String, fields: Dictionary) -> Dictionary:
	if fields.has("id"):
		return _failure("Building definition IDs are stable and read-only.")
	var definition := _find_record_reference(_working_definitions.get("definitions", []), definition_id)
	if definition.is_empty():
		return _failure("Unknown building definition id '%s'." % definition_id)
	for field in fields:
		definition[field] = fields[field]
	return _success({"definition": definition.duplicate(true), "dirty": is_dirty()})


func update_visual_profile_fields(profile_id: String, fields: Dictionary) -> Dictionary:
	if fields.has("id"):
		return _failure("Building visual profile IDs are stable and read-only.")
	var profile := _find_record_reference(_working_profiles.get("profiles", []), profile_id)
	if profile.is_empty():
		return _failure("Unknown building visual profile id '%s'." % profile_id)
	for field in fields:
		profile[field] = fields[field]
	return _success({"visual_profile": profile.duplicate(true), "dirty": is_dirty()})


func get_validation_messages() -> Array[String]:
	var result := _validate_complete_data(_working_definitions, _working_profiles)
	if result.ok:
		return []
	return [String(result.error)]


func is_dirty() -> bool:
	return _working_definitions != _persisted_definitions or _working_profiles != _persisted_profiles


func save(
	target_definitions_path: String = definitions_path,
	target_visual_profiles_path: String = visual_profiles_path
) -> Dictionary:
	var validation := _validate_complete_data(_working_definitions, _working_profiles)
	if not validation.ok:
		return _failure("Save blocked: %s" % validation.error)

	var definitions_result := _write_json_object(target_definitions_path, _working_definitions)
	if not definitions_result.ok:
		return definitions_result
	var profiles_result := _write_json_object(target_visual_profiles_path, _working_profiles)
	if not profiles_result.ok:
		return profiles_result

	if target_definitions_path == definitions_path and target_visual_profiles_path == visual_profiles_path:
		_persisted_definitions = _working_definitions.duplicate(true)
		_persisted_profiles = _working_profiles.duplicate(true)
	return _success()


func _validate_complete_data(definitions_data: Dictionary, profiles_data: Dictionary) -> Dictionary:
	var registry = BuildingDataRegistryScript.new()
	var definitions_validation: Dictionary = registry.call(
		"validate_definitions_data",
		definitions_data,
		definitions_path
	)
	if not definitions_validation.ok:
		return definitions_validation
	var profiles_validation: Dictionary = registry.call(
		"validate_visual_profiles_data",
		profiles_data,
		visual_profiles_path
	)
	if not profiles_validation.ok:
		return profiles_validation

	var profiles_by_id: Dictionary = {}
	for profile in profiles_data.get("profiles", []):
		profiles_by_id[String(profile.id)] = profile
	for definition in definitions_data.get("definitions", []):
		var profile_id := String(definition.visual_profile_id)
		if not profiles_by_id.has(profile_id):
			return _failure(
				"Building definition '%s' references unknown visual_profile_id '%s'."
				% [definition.id, profile_id]
			)
	return _success()


func _load_terrain_materials(path: String) -> Dictionary:
	var catalog = TerrainMaterialCatalogScript.new()
	var load_result: Dictionary = catalog.call("load_from_file", path)
	if not load_result.ok:
		return load_result
	var materials: Array[Dictionary] = []
	for terrain_type in ["terrain_1", "terrain_2"]:
		var material: Dictionary = catalog.call("get_material_for_terrain_type", terrain_type)
		if not material.is_empty():
			materials.append({
				"id": String(material.id),
				"terrain_type": String(material.terrain_type),
				"diffuse_path": String(material.diffuse_path),
			})
	materials.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	return _success({"materials": materials})


func _duplicate_records(records: Array) -> Array[Dictionary]:
	var duplicated: Array[Dictionary] = []
	for record in records:
		duplicated.append(record.duplicate(true))
	return duplicated


func _find_record(records: Array, record_id: String) -> Dictionary:
	var record := _find_record_reference(records, record_id)
	return record.duplicate(true) if not record.is_empty() else {}


func _find_record_reference(records: Array, record_id: String) -> Dictionary:
	for record in records:
		if String(record.get("id", "")) == record_id:
			return record
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
	var result := {"ok": false, "error": message}
	result.merge(extra, true)
	return result
