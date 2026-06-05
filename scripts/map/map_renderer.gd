class_name MapRenderer
extends Node2D

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")
const BuildingDataRegistryScript := preload("res://scripts/buildings/building_data_registry.gd")
const ProceduralBuildingPlacerScript := preload("res://scripts/buildings/procedural_building_placer.gd")

const DEFAULT_CONFIG_PATH := GridMapModelScript.DEFAULT_CONFIG_PATH
const TERRAIN_LAYER_NAME := "TerrainTileMapLayer"
const PLAY_TILESET_PATH := "res://resources/tilesets/play_cells.tres"
const PLAY_TILE_PATHS: PackedStringArray = [
	"res://assets/tiles/play/grass_a.png",
	"res://assets/tiles/play/grass_b.png",
]
const PLAY_TILE_SOURCE_A := 0
const PLAY_TILE_SOURCE_B := 1
const TILE_SIZE := 32
const TILE_ATLAS_COORDS := Vector2i.ZERO
const CELL_FILL_A := Color(0.55, 0.78, 0.42, 1.0)
const CELL_FILL_B := Color(0.51, 0.75, 0.39, 1.0)
const CELL_BORDER := Color(0.27, 0.48, 0.24, 0.28)
const MAP_BOUNDARY := Color(0.20, 0.42, 0.18, 0.92)
const CELL_BORDER_WIDTH := 1.0
const MAP_BOUNDARY_WIDTH := 3.0

@export var config_path := DEFAULT_CONFIG_PATH

var _map_model: RefCounted
var _load_error := ""
var _placement_error := ""
var _building_instances: Array[Dictionary] = []
var _building_definitions_by_id: Dictionary = {}
var _terrain_layer: TileMapLayer
var _play_tile_set: TileSet


func _ready() -> void:
	z_index = -100
	_ensure_terrain_layer()
	if _map_model == null:
		load_default_map()


func load_default_map(report_errors: bool = true) -> Dictionary:
	var model := GridMapModelScript.new()
	var result: Dictionary = model.load_from_file(config_path)
	if not result.ok:
		_load_error = result.error
		if report_errors:
			push_error("MapRenderer failed to load map config '%s': %s" % [config_path, _load_error])
		queue_redraw()
		return result

	set_map_model(model)
	return result


func set_map_model(map_model: RefCounted) -> void:
	_map_model = map_model
	_load_error = ""
	_generate_buildings()
	_populate_terrain_layer()
	queue_redraw()


func has_map_model() -> bool:
	return _map_model != null


func get_load_error() -> String:
	return _load_error


func get_placement_error() -> String:
	return _placement_error


func get_building_instances() -> Array[Dictionary]:
	var instances: Array[Dictionary] = []
	for instance in _building_instances:
		instances.append(instance.duplicate(true))
	return instances


func get_generated_building_rects() -> Dictionary:
	var rects: Dictionary = {}
	for instance in _building_instances:
		rects[String(instance.instance_id)] = get_building_rect(instance)
	return rects


func get_building_rect(instance: Dictionary) -> Rect2:
	if _map_model == null:
		return Rect2()
	if not _building_definitions_by_id.has(String(instance.definition_id)):
		return Rect2()

	var definition: Dictionary = _building_definitions_by_id[String(instance.definition_id)]
	var origin_cell := _vector2i_from_dictionary(instance.origin_cell)
	var footprint_size := Vector2i(int(definition.footprint_cells.width), int(definition.footprint_cells.height))
	var top_left: Vector2 = _map_model.origin + Vector2(origin_cell) * float(_map_model.cell_size)
	var size: Vector2 = Vector2(footprint_size) * float(_map_model.cell_size)
	return Rect2(top_left, size)


func get_map_bounds() -> Rect2:
	if _map_model == null:
		return Rect2()

	var map_size := Vector2(_map_model.grid_width, _map_model.grid_height) * float(_map_model.cell_size)
	return Rect2(_map_model.origin, map_size)


func get_cell_rect(cell: Vector2i) -> Rect2:
	if _map_model == null:
		return Rect2()

	var top_left: Vector2 = _map_model.origin + Vector2(cell) * float(_map_model.cell_size)
	return Rect2(top_left, Vector2.ONE * float(_map_model.cell_size))


func get_cell_fill_color(cell: Vector2i) -> Color:
	return CELL_FILL_A if (cell.x + cell.y) % 2 == 0 else CELL_FILL_B


func get_cell_border_color() -> Color:
	return CELL_BORDER


func get_map_boundary_color() -> Color:
	return MAP_BOUNDARY


func get_cell_border_width() -> float:
	return CELL_BORDER_WIDTH


func get_map_boundary_width() -> float:
	return MAP_BOUNDARY_WIDTH


func get_terrain_layer() -> TileMapLayer:
	_ensure_terrain_layer()
	return _terrain_layer


func get_terrain_tile_source_id(cell: Vector2i) -> int:
	return PLAY_TILE_SOURCE_A if (cell.x + cell.y) % 2 == 0 else PLAY_TILE_SOURCE_B


func get_populated_terrain_tile_count() -> int:
	_ensure_terrain_layer()
	return _terrain_layer.get_used_cells().size()


func _draw() -> void:
	if _map_model == null:
		return

	_draw_grid_lines()
	_draw_map_boundary()


func _ensure_terrain_layer() -> void:
	if _terrain_layer != null and is_instance_valid(_terrain_layer):
		return

	_terrain_layer = get_node_or_null(TERRAIN_LAYER_NAME) as TileMapLayer
	if _terrain_layer == null:
		_terrain_layer = TileMapLayer.new()
		_terrain_layer.name = TERRAIN_LAYER_NAME
		add_child(_terrain_layer)
	_terrain_layer.tile_set = _get_play_tile_set()
	_terrain_layer.z_index = 0


func _get_play_tile_set() -> TileSet:
	if _play_tile_set != null:
		return _play_tile_set

	_play_tile_set = TileSet.new()
	_play_tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for source_id in range(PLAY_TILE_PATHS.size()):
		_play_tile_set.add_source(_build_atlas_source(PLAY_TILE_PATHS[source_id]), source_id)
	return _play_tile_set


func _build_atlas_source(path: String) -> TileSetAtlasSource:
	var image := Image.new()
	var load_result := image.load(path)
	if load_result != OK:
		push_error("MapRenderer failed to load play tile image '%s': %s" % [path, error_string(load_result)])
	var texture := ImageTexture.create_from_image(image)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.create_tile(TILE_ATLAS_COORDS)
	return source


func _populate_terrain_layer() -> void:
	_ensure_terrain_layer()
	_terrain_layer.clear()
	if _map_model == null:
		return

	_terrain_layer.position = _map_model.origin
	for y in range(_map_model.grid_height):
		for x in range(_map_model.grid_width):
			var cell := Vector2i(x, y)
			_terrain_layer.set_cell(cell, get_terrain_tile_source_id(cell), TILE_ATLAS_COORDS)


func _generate_buildings() -> void:
	_placement_error = ""
	_building_instances.clear()
	_building_definitions_by_id.clear()

	if _map_model == null or _map_model.building_placement_config.is_empty():
		return

	var registry := BuildingDataRegistryScript.new()
	var definitions_result: Dictionary = registry.load_definitions()
	if not definitions_result.ok:
		_placement_error = definitions_result.error
		push_error("MapRenderer failed to load building definitions: %s" % _placement_error)
		return

	for definition in registry.get_definitions():
		_building_definitions_by_id[String(definition.id)] = definition.duplicate(true)

	var placer := ProceduralBuildingPlacerScript.new()
	var placement_result: Dictionary = placer.generate(_map_model, registry, _map_model.building_placement_config)
	if not placement_result.ok:
		_placement_error = placement_result.error
		push_error("MapRenderer failed to generate building placement: %s" % _placement_error)
		return

	for instance in placement_result.instances:
		_building_instances.append(instance.duplicate(true))


func _draw_grid_lines() -> void:
	var width := float(_map_model.grid_width * _map_model.cell_size)
	var height := float(_map_model.grid_height * _map_model.cell_size)
	for x in range(_map_model.grid_width + 1):
		var column_x: float = _map_model.origin.x + float(x * _map_model.cell_size)
		draw_line(Vector2(column_x, _map_model.origin.y), Vector2(column_x, _map_model.origin.y + height), CELL_BORDER, CELL_BORDER_WIDTH)
	for y in range(_map_model.grid_height + 1):
		var row_y: float = _map_model.origin.y + float(y * _map_model.cell_size)
		draw_line(Vector2(_map_model.origin.x, row_y), Vector2(_map_model.origin.x + width, row_y), CELL_BORDER, CELL_BORDER_WIDTH)


func _draw_map_boundary() -> void:
	draw_rect(get_map_bounds(), MAP_BOUNDARY, false, MAP_BOUNDARY_WIDTH)


func _vector2i_from_dictionary(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.x), int(value.y))
