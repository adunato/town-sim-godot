class_name TerrainRenderer2D
extends Polygon2D

const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")

const TERRAIN_TYPE_1_TEXTURE_PATH := "res://assets/Textures/mud.png"
const TERRAIN_TYPE_2_TEXTURE_PATH := "res://assets/Textures/rocky_grass.png"
const TERRAIN_SHADER_PATH := "res://shaders/terrain/terrain_binary_mask.gdshader"

@export var terrain_type_1_texture: Texture2D
@export var terrain_type_2_texture: Texture2D
@export_range(1.0, 1024.0, 1.0) var texture_repeat_world_size := 256.0

var _terrain_data: RefCounted
var _terrain_mask_texture: ImageTexture
var _terrain_material: ShaderMaterial
var _surface_bounds := Rect2()


func _ready() -> void:
	z_index = -90
	_load_default_textures()
	_ensure_shader_material()


func set_terrain_data(terrain_data: RefCounted) -> Dictionary:
	if terrain_data == null:
		_terrain_data = null
		_terrain_mask_texture = null
		_surface_bounds = Rect2()
		polygon = PackedVector2Array()
		uv = PackedVector2Array()
		return _failure("TerrainRenderer2D requires generated terrain data.")

	_terrain_data = terrain_data
	_surface_bounds = _terrain_data.get_world_bounds()

	var texture_validation := validate_texture_inputs()
	if not texture_validation.ok:
		return texture_validation

	var mask_result := _build_binary_mask_texture()
	if not mask_result.ok:
		return mask_result

	_configure_surface_geometry()
	var shader_result := _configure_shader_parameters()
	if not shader_result.ok:
		return shader_result
	return _success()


func has_terrain_data() -> bool:
	return _terrain_data != null


func get_rendered_bounds() -> Rect2:
	return _surface_bounds


func get_rendered_cell_count() -> int:
	if _terrain_data == null:
		return 0

	return _terrain_data.cells.size()


func get_draw_surface_count() -> int:
	if _terrain_data == null or polygon.size() == 0 or material == null:
		return 0

	return 1


func uses_shader_material() -> bool:
	return material is ShaderMaterial


func get_terrain_mask_texture() -> Texture2D:
	return _terrain_mask_texture


func get_terrain_mask_size() -> Vector2i:
	if _terrain_mask_texture == null:
		return Vector2i.ZERO

	return _terrain_mask_texture.get_size()


func get_cell_draw_rect(cell: Vector2i) -> Dictionary:
	if _terrain_data == null:
		return _failure("TerrainRenderer2D has no generated terrain data.")

	var lookup: Dictionary = _terrain_data.get_cell(cell)
	if not lookup.ok:
		return lookup

	return _success({"rect": lookup.cell.footprint})


func get_cell_mask_uv_rect(cell: Vector2i) -> Dictionary:
	if _terrain_data == null:
		return _failure("TerrainRenderer2D has no generated terrain data.")
	if not _terrain_data.is_cell_in_bounds(cell):
		return _failure("Terrain cell %s is outside terrain bounds." % cell)

	var mask_size := Vector2(float(_terrain_data.grid_width), float(_terrain_data.grid_height))
	return _success({
		"rect": Rect2(Vector2(cell) / mask_size, Vector2.ONE / mask_size),
	})


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


func get_shader_parameter_value(parameter_name: StringName) -> Variant:
	if _terrain_material == null:
		return null

	return _terrain_material.get_shader_parameter(parameter_name)


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


func _configure_surface_geometry() -> void:
	position = _surface_bounds.position
	color = Color.WHITE
	texture = terrain_type_1_texture
	var size := _surface_bounds.size
	polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		size,
		Vector2(0.0, size.y),
	])
	uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		size,
		Vector2(0.0, size.y),
	])


func _configure_shader_parameters() -> Dictionary:
	_ensure_shader_material()
	if _terrain_material == null:
		return _failure("TerrainRenderer2D failed to configure shader material: %s" % TERRAIN_SHADER_PATH)

	_terrain_material.set_shader_parameter("terrain_type_1_texture", terrain_type_1_texture)
	_terrain_material.set_shader_parameter("terrain_type_2_texture", terrain_type_2_texture)
	_terrain_material.set_shader_parameter("terrain_mask", _terrain_mask_texture)
	_terrain_material.set_shader_parameter("terrain_world_origin", _surface_bounds.position)
	_terrain_material.set_shader_parameter("terrain_world_size", _surface_bounds.size)
	_terrain_material.set_shader_parameter("texture_repeat_world_size", texture_repeat_world_size)
	material = _terrain_material
	return _success()


func _build_binary_mask_texture() -> Dictionary:
	if _terrain_data == null:
		return _failure("TerrainRenderer2D requires terrain data before building a terrain mask.")

	var image := Image.create(_terrain_data.grid_width, _terrain_data.grid_height, false, Image.FORMAT_RGBA8)
	for cell in _terrain_data.cells:
		var mask_value := 0.0
		if cell.terrain_type == TerrainCellScript.TERRAIN_TYPE_2:
			mask_value = 1.0
		elif cell.terrain_type != TerrainCellScript.TERRAIN_TYPE_1:
			return _failure("TerrainRenderer2D cannot build mask for unknown terrain type '%s' at %s." % [cell.terrain_type, cell.coordinate])

		image.set_pixel(cell.coordinate.x, cell.coordinate.y, Color(mask_value, mask_value, mask_value, 1.0))

	_terrain_mask_texture = ImageTexture.create_from_image(image)
	return _success()


func _ensure_shader_material() -> void:
	if _terrain_material != null:
		return

	var shader := load(TERRAIN_SHADER_PATH) as Shader
	if shader == null:
		push_error("TerrainRenderer2D failed to load terrain shader: %s" % TERRAIN_SHADER_PATH)
		return

	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = shader


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
