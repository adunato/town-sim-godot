class_name TerrainConfig
extends RefCounted

const DEFAULT_CONFIG_PATH := "res://data/terrain/prototype_terrain_config.json"

var grid_width: int = 0
var grid_height: int = 0
var cell_size: int = 0
var origin: Vector2 = Vector2.ZERO
var seed: int = 0
var noise_scale: float = 0.0
var terrain_threshold: float = 0.0
var source_name: String = "<memory>"


func load_from_file(config_path: String = DEFAULT_CONFIG_PATH) -> Dictionary:
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return _failure("Unable to read terrain config '%s': %s" % [config_path, error_string(FileAccess.get_open_error())])

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("Terrain config '%s' must be a JSON object." % config_path)

	return initialize_from_config(parsed, config_path)


func initialize_from_config(config: Dictionary, config_source_name: String = "<memory>") -> Dictionary:
	var validation := _validate_config(config, config_source_name)
	if not validation.ok:
		return validation

	grid_width = int(config.grid_width)
	grid_height = int(config.grid_height)
	cell_size = int(config.cell_size)
	origin = _vector2_from_dictionary(config.origin)
	seed = int(config.seed)
	noise_scale = float(config.noise_scale)
	terrain_threshold = float(config.terrain_threshold)
	source_name = config_source_name

	return _success()


func get_world_bounds() -> Rect2:
	return Rect2(origin, Vector2(grid_width * cell_size, grid_height * cell_size))


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_height


func cell_footprint(cell: Vector2i) -> Dictionary:
	if not is_cell_in_bounds(cell):
		return _failure("Terrain cell %s is outside config '%s' bounds." % [cell, source_name])

	return _success({
		"footprint": Rect2(origin + Vector2(cell * cell_size), Vector2(cell_size, cell_size)),
	})


func _validate_config(config: Dictionary, config_source_name: String) -> Dictionary:
	for field in ["grid_width", "grid_height", "cell_size", "origin", "seed", "noise_scale", "terrain_threshold"]:
		if not config.has(field):
			return _failure("Terrain config '%s' is missing required field '%s'." % [config_source_name, field])

	if not _is_integer_number(config.grid_width):
		return _failure("Terrain config '%s' field 'grid_width' must be an integer." % config_source_name)
	if int(config.grid_width) <= 0:
		return _failure("Terrain config '%s' field 'grid_width' must be positive." % config_source_name)

	if not _is_integer_number(config.grid_height):
		return _failure("Terrain config '%s' field 'grid_height' must be an integer." % config_source_name)
	if int(config.grid_height) <= 0:
		return _failure("Terrain config '%s' field 'grid_height' must be positive." % config_source_name)

	if not _is_integer_number(config.cell_size):
		return _failure("Terrain config '%s' field 'cell_size' must be an integer." % config_source_name)
	if int(config.cell_size) <= 0:
		return _failure("Terrain config '%s' field 'cell_size' must be positive." % config_source_name)

	if not _is_integer_number(config.seed):
		return _failure("Terrain config '%s' field 'seed' must be an integer." % config_source_name)

	if not _is_vector_dictionary(config.origin):
		return _failure("Terrain config '%s' field 'origin' must contain numeric x and y fields." % config_source_name)

	if not _is_number(config.noise_scale):
		return _failure("Terrain config '%s' field 'noise_scale' must be numeric." % config_source_name)
	if float(config.noise_scale) <= 0.0:
		return _failure("Terrain config '%s' field 'noise_scale' must be positive." % config_source_name)

	if not _is_number(config.terrain_threshold):
		return _failure("Terrain config '%s' field 'terrain_threshold' must be numeric." % config_source_name)
	if float(config.terrain_threshold) < -1.0 or float(config.terrain_threshold) > 1.0:
		return _failure("Terrain config '%s' field 'terrain_threshold' must be between -1.0 and 1.0." % config_source_name)

	return _success()


func _is_vector_dictionary(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false

	return value.has("x") and value.has("y") \
		and _is_number(value.x) \
		and _is_number(value.y)


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false

	return is_equal_approx(float(value), float(int(value)))


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _vector2_from_dictionary(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


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
