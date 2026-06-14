class_name TerrainCell
extends RefCounted

const TERRAIN_TYPE_1 := "terrain_1"
const TERRAIN_TYPE_2 := "terrain_2"

var coordinate: Vector2i = Vector2i.ZERO
var noise_value: float = 0.0
var terrain_type: String = TERRAIN_TYPE_1
var footprint: Rect2 = Rect2()


func initialize(cell_coordinate: Vector2i, sampled_noise_value: float, assigned_terrain_type: String, world_footprint: Rect2) -> Dictionary:
	if not is_known_terrain_type(assigned_terrain_type):
		return _failure("Unknown terrain type '%s' for terrain cell %s." % [assigned_terrain_type, cell_coordinate])

	coordinate = cell_coordinate
	noise_value = sampled_noise_value
	terrain_type = assigned_terrain_type
	footprint = world_footprint

	return _success()


static func terrain_type_for_noise(sampled_noise_value: float, threshold: float) -> String:
	if sampled_noise_value < threshold:
		return TERRAIN_TYPE_1

	return TERRAIN_TYPE_2


static func is_known_terrain_type(value: String) -> bool:
	return value == TERRAIN_TYPE_1 or value == TERRAIN_TYPE_2


func to_debug_dictionary() -> Dictionary:
	return {
		"coordinate": {"x": coordinate.x, "y": coordinate.y},
		"noise_value": noise_value,
		"terrain_type": terrain_type,
		"footprint": {
			"x": footprint.position.x,
			"y": footprint.position.y,
			"width": footprint.size.x,
			"height": footprint.size.y,
		},
	}


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
