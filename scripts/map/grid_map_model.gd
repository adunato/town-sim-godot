class_name GridMapModel
extends RefCounted

const DEFAULT_CONFIG_PATH := "res://data/maps/prototype_map.json"
const STATE_BLOCKED := "blocked"
const STATE_OCCUPIED := "occupied"
const STATE_RESERVED := "reserved"
const STATE_PROTECTED := "protected"

var grid_width: int = 0
var grid_height: int = 0
var cell_size: int = 0
var origin: Vector2 = Vector2.ZERO
var seed: int = 0
var player_spawn_cell: Vector2i = Vector2i.ZERO
var building_placement_config: Dictionary = {}

var _cell_states: Dictionary = {}


func load_from_file(config_path: String = DEFAULT_CONFIG_PATH) -> Dictionary:
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return _failure("Unable to read map config '%s': %s" % [config_path, error_string(FileAccess.get_open_error())])

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("Map config '%s' must be a JSON object." % config_path)

	return initialize_from_config(parsed, config_path)


func initialize_from_config(config: Dictionary, source_name: String = "<memory>") -> Dictionary:
	var validation := _validate_config(config, source_name)
	if not validation.ok:
		return validation

	grid_width = int(config.grid_width)
	grid_height = int(config.grid_height)
	cell_size = int(config.cell_size)
	origin = _vector2_from_dictionary(config.origin)
	seed = int(config.seed)
	player_spawn_cell = _vector2i_from_dictionary(config.player_spawn_cell)
	building_placement_config = config.get("building_placement", {}).duplicate(true)
	_cell_states.clear()

	var spawn_result := reserve_rect(player_spawn_cell, Vector2i.ONE, STATE_RESERVED)
	if not spawn_result.ok:
		return spawn_result

	var protect_result := reserve_rect(player_spawn_cell, Vector2i.ONE, STATE_PROTECTED, true)
	if not protect_result.ok:
		return protect_result

	return _success()


func world_to_cell(world_position: Vector2) -> Dictionary:
	var local_position := world_position - origin
	var cell := Vector2i(floori(local_position.x / float(cell_size)), floori(local_position.y / float(cell_size)))
	if not is_cell_in_bounds(cell):
		return _failure("World position %s is outside map bounds." % world_position, {"cell": cell})

	return _success({"cell": cell})


func cell_to_world(cell: Vector2i) -> Dictionary:
	if not is_cell_in_bounds(cell):
		return _failure("Cell %s is outside map bounds." % cell)

	var world_position := origin + (Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size)
	return _success({"world_position": world_position})


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_height


func is_world_position_in_bounds(world_position: Vector2) -> bool:
	return world_to_cell(world_position).ok


func reserve_rect(top_left: Vector2i, size: Vector2i, state: String = STATE_RESERVED, overwrite_protected: bool = false) -> Dictionary:
	if not _is_known_state(state):
		return _failure("Unknown cell state '%s'." % state)
	if size.x <= 0 or size.y <= 0:
		return _failure("Reservation rectangle size must be positive, got %s." % size)

	var cells: Array[Vector2i] = []
	for y in range(top_left.y, top_left.y + size.y):
		for x in range(top_left.x, top_left.x + size.x):
			var cell := Vector2i(x, y)
			if not is_cell_in_bounds(cell):
				return _failure("Reservation rectangle includes out-of-bounds cell %s." % cell)
			if is_protected(cell) and not overwrite_protected:
				return _failure("Reservation rectangle conflicts with protected cell %s." % cell)
			cells.append(cell)

	for cell in cells:
		_set_cell_state(cell, state, true)

	return _success({"cells": cells})


func is_walkable(cell: Vector2i) -> bool:
	if not is_cell_in_bounds(cell):
		return false

	return not is_blocked(cell) and not is_occupied(cell) and not is_reserved(cell)


func is_blocked(cell: Vector2i) -> bool:
	return _has_cell_state(cell, STATE_BLOCKED)


func is_occupied(cell: Vector2i) -> bool:
	return _has_cell_state(cell, STATE_OCCUPIED)


func is_reserved(cell: Vector2i) -> bool:
	return _has_cell_state(cell, STATE_RESERVED)


func is_protected(cell: Vector2i) -> bool:
	return _has_cell_state(cell, STATE_PROTECTED)


func _validate_config(config: Dictionary, source_name: String) -> Dictionary:
	for field in ["grid_width", "grid_height", "cell_size", "origin", "seed", "player_spawn_cell"]:
		if not config.has(field):
			return _failure("Map config '%s' is missing required field '%s'." % [source_name, field])

	if not _is_integer_number(config.grid_width):
		return _failure("Map config '%s' field 'grid_width' must be an integer." % source_name)
	if int(config.grid_width) <= 0:
		return _failure("Map config '%s' field 'grid_width' must be positive." % source_name)

	if not _is_integer_number(config.grid_height):
		return _failure("Map config '%s' field 'grid_height' must be an integer." % source_name)
	if int(config.grid_height) <= 0:
		return _failure("Map config '%s' field 'grid_height' must be positive." % source_name)

	if not _is_integer_number(config.cell_size):
		return _failure("Map config '%s' field 'cell_size' must be an integer." % source_name)
	if int(config.cell_size) <= 0:
		return _failure("Map config '%s' field 'cell_size' must be positive." % source_name)

	if not _is_integer_number(config.seed):
		return _failure("Map config '%s' field 'seed' must be an integer." % source_name)

	if not _is_vector_dictionary(config.origin):
		return _failure("Map config '%s' field 'origin' must contain numeric x and y fields." % source_name)
	if not _is_vector_dictionary(config.player_spawn_cell):
		return _failure("Map config '%s' field 'player_spawn_cell' must contain numeric x and y fields." % source_name)

	var spawn_cell := _vector2i_from_dictionary(config.player_spawn_cell)
	var config_width := int(config.grid_width)
	var config_height := int(config.grid_height)
	if spawn_cell.x < 0 or spawn_cell.y < 0 or spawn_cell.x >= config_width or spawn_cell.y >= config_height:
		return _failure("Map config '%s' player_spawn_cell %s is outside map bounds." % [source_name, spawn_cell])

	return _success()


func _set_cell_state(cell: Vector2i, state: String, value: bool) -> void:
	var key := _cell_key(cell)
	if not _cell_states.has(key):
		_cell_states[key] = {}

	_cell_states[key][state] = value


func _has_cell_state(cell: Vector2i, state: String) -> bool:
	if not is_cell_in_bounds(cell):
		return false

	var key := _cell_key(cell)
	return _cell_states.has(key) and _cell_states[key].get(state, false)


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _is_known_state(state: String) -> bool:
	return state == STATE_BLOCKED or state == STATE_OCCUPIED or state == STATE_RESERVED or state == STATE_PROTECTED


func _is_vector_dictionary(value: Variant) -> bool:
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


func _vector2_from_dictionary(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


func _vector2i_from_dictionary(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.x), int(value.y))


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
