extends Node2D
class_name MapLoader

@export_file("*.json") var tileset_catalogue_path := "res://data/tileset_catalogue.json"
@export_file("*.json") var map_path := "res://data/map_001.json"

var tile_size := 32
var map_data: Dictionary = {}
var tileset_catalogue: Dictionary = {}
var walkability_grid: Array = []

@onready var tiles_root := Node2D.new()


func _ready() -> void:
	tiles_root.name = "GeneratedTiles"
	add_child(tiles_root)
	load_map()


func load_map() -> void:
	_clear_tiles()
	tileset_catalogue = _load_json_dictionary(tileset_catalogue_path)
	map_data = _load_json_dictionary(map_path)
	if tileset_catalogue.is_empty() or map_data.is_empty():
		return

	var errors := MapValidator.validate_catalogue(tileset_catalogue)
	errors.append_array(MapValidator.validate_map(map_data, tileset_catalogue))
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		return

	tile_size = int(tileset_catalogue["tile_size"])
	_build_walkability_grid()
	_render_fallback_map()


func is_tile_walkable(tile_pos: Vector2i) -> bool:
	if tile_pos.y < 0 or tile_pos.y >= walkability_grid.size():
		return false
	if tile_pos.x < 0 or tile_pos.x >= walkability_grid[tile_pos.y].size():
		return false
	return bool(walkability_grid[tile_pos.y][tile_pos.x])


func world_to_tile(world_pos: Vector2) -> Vector2i:
	var local_pos := to_local(world_pos)
	return Vector2i(floori(local_pos.x / tile_size), floori(local_pos.y / tile_size))


func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return to_global(Vector2(tile_pos.x * tile_size + tile_size / 2.0, tile_pos.y * tile_size + tile_size / 2.0))


func get_player_spawn_world() -> Vector2:
	var spawn := Vector2i(int(map_data["player_spawn"][0]), int(map_data["player_spawn"][1]))
	return tile_to_world(spawn)


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("JSON file does not exist: %s" % path)
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("Could not parse JSON file: %s" % path)
		return {}
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON root must be an object: %s" % path)
		return {}
	return parsed


func _build_walkability_grid() -> void:
	walkability_grid.clear()
	var catalogue_tiles: Dictionary = tileset_catalogue["tiles"]
	for row in map_data["tiles"]:
		var walkability_row: Array[bool] = []
		for tile_id in row:
			walkability_row.append(bool(catalogue_tiles[tile_id].get("walkable", false)))
		walkability_grid.append(walkability_row)


func _render_fallback_map() -> void:
	var catalogue_tiles: Dictionary = tileset_catalogue["tiles"]
	var tiles: Array = map_data["tiles"]
	for y in range(tiles.size()):
		for x in range(tiles[y].size()):
			var tile_id: String = tiles[y][x]
			var tile_definition: Dictionary = catalogue_tiles[tile_id]
			var tile_node := Polygon2D.new()
			tile_node.name = "Tile_%d_%d_%s" % [x, y, tile_id]
			tile_node.position = Vector2(x * tile_size, y * tile_size)
			tile_node.polygon = PackedVector2Array([
				Vector2.ZERO,
				Vector2(tile_size, 0),
				Vector2(tile_size, tile_size),
				Vector2(0, tile_size)
			])
			tile_node.color = Color.html(tile_definition.get("fallback_color", "#FF00FF"))
			tiles_root.add_child(tile_node)


func _clear_tiles() -> void:
	for child in tiles_root.get_children():
		child.queue_free()
