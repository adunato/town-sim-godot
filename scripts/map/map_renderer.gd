class_name MapRenderer
extends Node2D

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")

const DEFAULT_CONFIG_PATH := GridMapModelScript.DEFAULT_CONFIG_PATH
const CELL_FILL_A := Color(0.55, 0.78, 0.42, 1.0)
const CELL_FILL_B := Color(0.51, 0.75, 0.39, 1.0)
const CELL_BORDER := Color(0.27, 0.48, 0.24, 0.28)
const MAP_BOUNDARY := Color(0.20, 0.42, 0.18, 0.92)
const CELL_BORDER_WIDTH := 1.0
const MAP_BOUNDARY_WIDTH := 3.0

@export var config_path := DEFAULT_CONFIG_PATH

var _map_model: RefCounted
var _load_error := ""


func _ready() -> void:
	z_index = -100
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
	queue_redraw()


func has_map_model() -> bool:
	return _map_model != null


func get_load_error() -> String:
	return _load_error


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


func _draw() -> void:
	if _map_model == null:
		return

	_draw_cells()
	_draw_cell_borders()
	_draw_map_boundary()


func _draw_cells() -> void:
	for y in range(_map_model.grid_height):
		for x in range(_map_model.grid_width):
			var cell := Vector2i(x, y)
			draw_rect(get_cell_rect(cell), get_cell_fill_color(cell), true)


func _draw_cell_borders() -> void:
	for y in range(_map_model.grid_height):
		for x in range(_map_model.grid_width):
			draw_rect(get_cell_rect(Vector2i(x, y)), CELL_BORDER, false, CELL_BORDER_WIDTH)


func _draw_map_boundary() -> void:
	draw_rect(get_map_bounds(), MAP_BOUNDARY, false, MAP_BOUNDARY_WIDTH)
