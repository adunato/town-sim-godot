class_name TerrainMaterialCatalog
extends RefCounted

const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")

const DEFAULT_CATALOG_PATH := "res://data/terrain/prototype_terrain_materials.json"
const HEIGHT_ROUTE_AUTHORED_TEXTURES := "authored_texture_maps"

var catalog_path := DEFAULT_CATALOG_PATH
var height_brightness_convention := "brighter_is_higher"
var texture_repeat_world_size := 256.0
var height_blend_influence := 1.2
var height_blend_contrast := 2.1

var _materials_by_terrain_type := {}


func load_from_file(path := DEFAULT_CATALOG_PATH) -> Dictionary:
	catalog_path = path
	if not FileAccess.file_exists(path):
		return _failure("Terrain material catalog does not exist: %s" % path)

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Unable to open terrain material catalog '%s': %s" % [path, error_string(FileAccess.get_open_error())])

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _failure("Terrain material catalog '%s' must contain a JSON object." % path)

	return load_from_dictionary(parsed, path)


func load_from_dictionary(catalog: Dictionary, source_name := "<dictionary>") -> Dictionary:
	_materials_by_terrain_type.clear()

	var version_result := _require_int(catalog, "schema_version", source_name)
	if not version_result.ok:
		return version_result
	if int(catalog.schema_version) != 1:
		return _failure("Terrain material catalog '%s' schema_version must be 1." % source_name)

	var brightness_result := _require_string(catalog, "height_brightness_convention", source_name)
	if not brightness_result.ok:
		return brightness_result
	height_brightness_convention = String(catalog.height_brightness_convention)
	if height_brightness_convention != "brighter_is_higher":
		return _failure("Terrain material catalog '%s' height_brightness_convention must be 'brighter_is_higher'." % source_name)

	var repeat_result := _require_number(catalog, "texture_repeat_world_size", source_name)
	if not repeat_result.ok:
		return repeat_result
	texture_repeat_world_size = float(catalog.texture_repeat_world_size)
	if texture_repeat_world_size <= 0.0:
		return _failure("Terrain material catalog '%s' texture_repeat_world_size must be positive." % source_name)

	if not catalog.has("height_blend") or not catalog.height_blend is Dictionary:
		return _failure("Terrain material catalog '%s' field 'height_blend' must be an object." % source_name)
	var height_blend: Dictionary = catalog.height_blend
	var influence_result := _require_number(height_blend, "influence", "%s height_blend" % source_name)
	if not influence_result.ok:
		return influence_result
	var contrast_result := _require_number(height_blend, "contrast", "%s height_blend" % source_name)
	if not contrast_result.ok:
		return contrast_result
	height_blend_influence = float(height_blend.influence)
	height_blend_contrast = float(height_blend.contrast)
	if height_blend_influence < 0.0 or height_blend_influence > 3.0:
		return _failure("Terrain material catalog '%s' height_blend.influence must be between 0.0 and 3.0." % source_name)
	if height_blend_contrast <= 0.0:
		return _failure("Terrain material catalog '%s' height_blend.contrast must be positive." % source_name)

	if not catalog.has("materials") or not catalog.materials is Array:
		return _failure("Terrain material catalog '%s' field 'materials' must be an array." % source_name)
	for index in range(catalog.materials.size()):
		var material_result := _load_material(catalog.materials[index], index, source_name)
		if not material_result.ok:
			return material_result
		var material: Dictionary = material_result.material
		_materials_by_terrain_type[material.terrain_type] = material

	for terrain_type in [TerrainCellScript.TERRAIN_TYPE_1, TerrainCellScript.TERRAIN_TYPE_2]:
		if not _materials_by_terrain_type.has(terrain_type):
			return _failure("Terrain material catalog '%s' must define material for %s." % [source_name, terrain_type])

	return _success()


func get_material_for_terrain_type(terrain_type: String) -> Dictionary:
	return _materials_by_terrain_type.get(terrain_type, {})


func has_material_for_terrain_type(terrain_type: String) -> bool:
	return _materials_by_terrain_type.has(terrain_type)


func get_material_count() -> int:
	return _materials_by_terrain_type.size()


func get_material_ids() -> Array[String]:
	var ids: Array[String] = []
	for material: Dictionary in _materials_by_terrain_type.values():
		ids.append(String(material.id))
	ids.sort()
	return ids


func _load_material(raw_material: Variant, index: int, source_name: String) -> Dictionary:
	if not raw_material is Dictionary:
		return _failure("Terrain material catalog '%s' materials[%d] must be an object." % [source_name, index])

	var material: Dictionary = raw_material
	for field in ["id", "terrain_type", "diffuse_texture", "height_texture"]:
		var string_result := _require_string(material, field, "%s materials[%d]" % [source_name, index])
		if not string_result.ok:
			return string_result
	if not TerrainCellScript.is_known_terrain_type(String(material.terrain_type)):
		return _failure("Terrain material catalog '%s' materials[%d] has unknown terrain_type '%s'." % [source_name, index, material.terrain_type])
	if _materials_by_terrain_type.has(String(material.terrain_type)):
		return _failure("Terrain material catalog '%s' defines terrain_type '%s' more than once." % [source_name, material.terrain_type])

	if not material.has("expected_size") or not material.expected_size is Dictionary:
		return _failure("Terrain material catalog '%s' materials[%d].expected_size must be an object." % [source_name, index])
	var expected_size: Dictionary = material.expected_size
	var width_result := _require_int(expected_size, "width", "%s materials[%d].expected_size" % [source_name, index])
	if not width_result.ok:
		return width_result
	var height_result := _require_int(expected_size, "height", "%s materials[%d].expected_size" % [source_name, index])
	if not height_result.ok:
		return height_result
	var expected_texture_size := Vector2i(int(expected_size.width), int(expected_size.height))
	if expected_texture_size.x <= 0 or expected_texture_size.y <= 0:
		return _failure("Terrain material catalog '%s' materials[%d].expected_size must be positive." % [source_name, index])

	var diffuse_path := String(material.diffuse_texture)
	var height_path := String(material.height_texture)
	var diffuse_texture := _load_texture(diffuse_path, "diffuse_texture", source_name, index)
	if not diffuse_texture.ok:
		return diffuse_texture
	var height_texture := _load_texture(height_path, "height_texture", source_name, index)
	if not height_texture.ok:
		return height_texture

	if Vector2i(diffuse_texture.texture.get_size()) != expected_texture_size:
		return _failure("Terrain material catalog '%s' materials[%d] diffuse texture size should be %s: %s" % [source_name, index, expected_texture_size, diffuse_path])
	if Vector2i(height_texture.texture.get_size()) != expected_texture_size:
		return _failure("Terrain material catalog '%s' materials[%d] height texture size should be %s: %s" % [source_name, index, expected_texture_size, height_path])

	return _success({
		"material": {
			"id": String(material.id),
			"terrain_type": String(material.terrain_type),
			"diffuse_path": diffuse_path,
			"height_path": height_path,
			"expected_size": expected_texture_size,
			"diffuse_texture": diffuse_texture.texture,
			"height_texture": height_texture.texture,
		}
	})


func _load_texture(path: String, field: String, source_name: String, material_index: int) -> Dictionary:
	if not ResourceLoader.exists(path, "Texture2D"):
		return _failure("Terrain material catalog '%s' materials[%d].%s does not exist as Texture2D: %s" % [source_name, material_index, field, path])
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture == null:
		return _failure("Terrain material catalog '%s' materials[%d].%s failed to load Texture2D: %s" % [source_name, material_index, field, path])
	return _success({"texture": texture})


func _require_string(data: Dictionary, field: String, source_name: String) -> Dictionary:
	if not data.has(field) or not data[field] is String or String(data[field]).is_empty():
		return _failure("Terrain material catalog '%s' field '%s' must be a non-empty string." % [source_name, field])
	return _success()


func _require_number(data: Dictionary, field: String, source_name: String) -> Dictionary:
	if not data.has(field) or not (data[field] is int or data[field] is float):
		return _failure("Terrain material catalog '%s' field '%s' must be a number." % [source_name, field])
	return _success()


func _require_int(data: Dictionary, field: String, source_name: String) -> Dictionary:
	if not data.has(field) or not (data[field] is int or data[field] is float):
		return _failure("Terrain material catalog '%s' field '%s' must be an integer." % [source_name, field])
	if int(data[field]) != float(data[field]):
		return _failure("Terrain material catalog '%s' field '%s' must be an integer." % [source_name, field])
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
