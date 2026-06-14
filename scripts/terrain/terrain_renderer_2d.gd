class_name TerrainRenderer2D
extends Node2D

const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")
const TERRAIN_TYPE_1_TEXTURE_PATH := "res://assets/Textures/mud.png"
const TERRAIN_TYPE_2_TEXTURE_PATH := "res://assets/Textures/rocky_grass.png"

@export var terrain_type_1_texture: Texture2D
@export var terrain_type_2_texture: Texture2D
@export_range(1.0, 512.0, 1.0) var texture_repeat_world_size := 128.0

var _terrain_data: RefCounted


func _ready() -> void:
	z_index = -90
	_load_default_textures()


func set_terrain_data(terrain_data: RefCounted) -> Dictionary:
	if terrain_data == null:
		_terrain_data = null
		queue_redraw()
		return _failure("TerrainRenderer2D requires generated terrain data.")

	_terrain_data = terrain_data
	queue_redraw()
	return _success()


func has_terrain_data() -> bool:
	return _terrain_data != null


func get_rendered_bounds() -> Rect2:
	if _terrain_data == null:
		return Rect2()

	return _terrain_data.get_world_bounds()


func get_rendered_cell_count() -> int:
	if _terrain_data == null:
		return 0

	return _terrain_data.cells.size()


func get_cell_draw_rect(cell: Vector2i) -> Dictionary:
	if _terrain_data == null:
		return _failure("TerrainRenderer2D has no generated terrain data.")

	var lookup: Dictionary = _terrain_data.get_cell(cell)
	if not lookup.ok:
		return lookup

	return _success({"rect": lookup.cell.footprint})


func get_texture_for_terrain_type(terrain_type: String) -> Texture2D:
	if terrain_type == TerrainCellScript.TERRAIN_TYPE_1:
		return terrain_type_1_texture
	if terrain_type == TerrainCellScript.TERRAIN_TYPE_2:
		return terrain_type_2_texture

	return null


func get_texture_path_for_terrain_type(terrain_type: String) -> String:
	if terrain_type == TerrainCellScript.TERRAIN_TYPE_1:
		return TERRAIN_TYPE_1_TEXTURE_PATH
	if terrain_type == TerrainCellScript.TERRAIN_TYPE_2:
		return TERRAIN_TYPE_2_TEXTURE_PATH

	return ""


func get_texture_region_for_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position / texture_repeat_world_size, rect.size / texture_repeat_world_size)


func validate_texture_inputs(load_defaults := true) -> Dictionary:
	if load_defaults:
		_load_default_textures()
	if terrain_type_1_texture == null:
		return _failure("TerrainRenderer2D missing texture input for terrain_1: %s" % TERRAIN_TYPE_1_TEXTURE_PATH)
	if terrain_type_2_texture == null:
		return _failure("TerrainRenderer2D missing texture input for terrain_2: %s" % TERRAIN_TYPE_2_TEXTURE_PATH)
	if texture_repeat_world_size <= 0.0:
		return _failure("TerrainRenderer2D texture_repeat_world_size must be positive.")

	return _success()


func _load_default_textures() -> void:
	if terrain_type_1_texture == null:
		terrain_type_1_texture = _load_texture_from_image(TERRAIN_TYPE_1_TEXTURE_PATH)
	if terrain_type_2_texture == null:
		terrain_type_2_texture = _load_texture_from_image(TERRAIN_TYPE_2_TEXTURE_PATH)


func _load_texture_from_image(path: String) -> Texture2D:
	var image := Image.new()
	var load_result := image.load(path)
	if load_result != OK:
		push_error("TerrainRenderer2D failed to load terrain texture '%s': %s" % [path, error_string(load_result)])
		return null

	return ImageTexture.create_from_image(image)


func _draw() -> void:
	if _terrain_data == null:
		return

	var validation := validate_texture_inputs()
	if not validation.ok:
		return

	for cell in _terrain_data.cells:
		var texture := get_texture_for_terrain_type(cell.terrain_type)
		if texture == null:
			continue
		draw_texture_rect(texture, cell.footprint, true)


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
