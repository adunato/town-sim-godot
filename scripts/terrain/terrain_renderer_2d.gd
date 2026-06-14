class_name TerrainRenderer2D
extends Polygon2D

const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")

const TERRAIN_TYPE_1_TEXTURE_PATH := "res://assets/Textures/mud.png"
const TERRAIN_TYPE_2_TEXTURE_PATH := "res://assets/Textures/rocky_grass.png"
const TERRAIN_SHADER_PATH := "res://shaders/terrain/terrain_binary_mask.gdshader"
const MASK_PIXELS_PER_CELL := 8
const HEIGHT_ROUTE_GENERATED_FROM_DIFFUSE := "generated_from_diffuse_luminance"

@export var terrain_type_1_texture: Texture2D
@export var terrain_type_2_texture: Texture2D
@export_range(1.0, 1024.0, 1.0) var texture_repeat_world_size := 256.0
@export_range(0.25, 8.0, 0.25) var blend_width_cells := 1.5
@export_range(0.0, 1.0, 0.05) var height_blend_influence := 0.45
@export_range(0.25, 4.0, 0.05) var height_blend_contrast := 1.5

var _terrain_data: RefCounted
var _terrain_mask_texture: ImageTexture
var _terrain_type_1_height_texture: ImageTexture
var _terrain_type_2_height_texture: ImageTexture
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
		_terrain_type_1_height_texture = null
		_terrain_type_2_height_texture = null
		_surface_bounds = Rect2()
		polygon = PackedVector2Array()
		uv = PackedVector2Array()
		return _failure("TerrainRenderer2D requires generated terrain data.")

	_terrain_data = terrain_data
	_surface_bounds = _terrain_data.get_world_bounds()

	var texture_validation := validate_texture_inputs()
	if not texture_validation.ok:
		return texture_validation

	var blend_validation := validate_blend_settings()
	if not blend_validation.ok:
		return blend_validation

	var height_validation := validate_height_settings()
	if not height_validation.ok:
		return height_validation

	var height_result := _build_generated_height_textures()
	if not height_result.ok:
		return height_result

	var mask_result := _build_blend_mask_texture()
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


func get_height_input_route() -> String:
	return HEIGHT_ROUTE_GENERATED_FROM_DIFFUSE


func get_height_brightness_convention() -> String:
	return "diffuse_luminance_brighter_is_higher"


func get_terrain_height_texture(terrain_type: String) -> Texture2D:
	if terrain_type == TerrainCellScript.TERRAIN_TYPE_1:
		return _terrain_type_1_height_texture
	if terrain_type == TerrainCellScript.TERRAIN_TYPE_2:
		return _terrain_type_2_height_texture

	return null


func get_terrain_height_texture_size(terrain_type: String) -> Vector2i:
	var height_texture := get_terrain_height_texture(terrain_type)
	if height_texture == null:
		return Vector2i.ZERO

	return height_texture.get_size()


func get_height_aware_mask_value(regular_mask: float, terrain_1_height: float, terrain_2_height: float) -> float:
	var clamped_mask := clampf(regular_mask, 0.0, 1.0)
	var boundary_weight := 1.0 - smoothstep(0.0, 0.75, absf(clamped_mask - 0.5) * 2.0)
	var contrasted_1_height := clampf((terrain_1_height - 0.5) * height_blend_contrast + 0.5, 0.0, 1.0)
	var contrasted_2_height := clampf((terrain_2_height - 0.5) * height_blend_contrast + 0.5, 0.0, 1.0)
	var height_delta := contrasted_2_height - contrasted_1_height
	return clampf(clamped_mask + height_delta * height_blend_influence * boundary_weight, 0.0, 1.0)


func get_generated_height_sample(terrain_type: String, uv_coordinate: Vector2) -> Dictionary:
	var height_texture := get_terrain_height_texture(terrain_type)
	if height_texture == null:
		return _failure("TerrainRenderer2D has no generated height texture for '%s'." % terrain_type)

	var image := height_texture.get_image()
	var wrapped_uv := Vector2(uv_coordinate.x - floorf(uv_coordinate.x), uv_coordinate.y - floorf(uv_coordinate.y))
	var sample_pixel := Vector2i(
		clampi(int(floorf(wrapped_uv.x * float(image.get_width()))), 0, image.get_width() - 1),
		clampi(int(floorf(wrapped_uv.y * float(image.get_height()))), 0, image.get_height() - 1)
	)
	return _success({"value": image.get_pixel(sample_pixel.x, sample_pixel.y).r})


func get_terrain_mask_value(cell: Vector2i) -> Dictionary:
	if _terrain_mask_texture == null:
		return _failure("TerrainRenderer2D has no generated terrain blend mask.")
	if _terrain_data == null:
		return _failure("TerrainRenderer2D has no generated terrain data.")
	if not _terrain_data.is_cell_in_bounds(cell):
		return _failure("Terrain cell %s is outside terrain bounds." % cell)

	var mask_image := _terrain_mask_texture.get_image()
	var sample_pixel := Vector2i(
		cell.x * MASK_PIXELS_PER_CELL + MASK_PIXELS_PER_CELL / 2,
		cell.y * MASK_PIXELS_PER_CELL + MASK_PIXELS_PER_CELL / 2
	)
	return _success({"value": mask_image.get_pixel(sample_pixel.x, sample_pixel.y).r})


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


func validate_blend_settings() -> Dictionary:
	if blend_width_cells <= 0.0:
		return _failure("TerrainRenderer2D blend_width_cells must be positive.")

	return _success()


func validate_height_settings() -> Dictionary:
	if height_blend_influence < 0.0 or height_blend_influence > 1.0:
		return _failure("TerrainRenderer2D height_blend_influence must be between 0.0 and 1.0.")
	if height_blend_contrast <= 0.0:
		return _failure("TerrainRenderer2D height_blend_contrast must be positive.")

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
	_terrain_material.set_shader_parameter("terrain_type_1_height", _terrain_type_1_height_texture)
	_terrain_material.set_shader_parameter("terrain_type_2_height", _terrain_type_2_height_texture)
	_terrain_material.set_shader_parameter("terrain_world_origin", _surface_bounds.position)
	_terrain_material.set_shader_parameter("terrain_world_size", _surface_bounds.size)
	_terrain_material.set_shader_parameter("texture_repeat_world_size", texture_repeat_world_size)
	_terrain_material.set_shader_parameter("height_blend_influence", height_blend_influence)
	_terrain_material.set_shader_parameter("height_blend_contrast", height_blend_contrast)
	material = _terrain_material
	return _success()


func _build_generated_height_textures() -> Dictionary:
	var terrain_1_result := _build_height_texture_from_diffuse(terrain_type_1_texture, TerrainCellScript.TERRAIN_TYPE_1)
	if not terrain_1_result.ok:
		return terrain_1_result
	var terrain_2_result := _build_height_texture_from_diffuse(terrain_type_2_texture, TerrainCellScript.TERRAIN_TYPE_2)
	if not terrain_2_result.ok:
		return terrain_2_result

	_terrain_type_1_height_texture = terrain_1_result.texture
	_terrain_type_2_height_texture = terrain_2_result.texture
	return _success()


func _build_height_texture_from_diffuse(diffuse_texture: Texture2D, terrain_type: String) -> Dictionary:
	if diffuse_texture == null:
		return _failure("TerrainRenderer2D cannot generate height data for '%s' without a diffuse texture." % terrain_type)

	var diffuse_image := diffuse_texture.get_image()
	if diffuse_image == null or diffuse_image.is_empty():
		return _failure("TerrainRenderer2D cannot generate height data for '%s' from an empty diffuse texture." % terrain_type)

	var height_image := Image.create(diffuse_image.get_width(), diffuse_image.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(diffuse_image.get_height()):
		for x in range(diffuse_image.get_width()):
			var source_color := diffuse_image.get_pixel(x, y)
			var luminance := source_color.r * 0.2126 + source_color.g * 0.7152 + source_color.b * 0.0722
			height_image.set_pixel(x, y, Color(luminance, luminance, luminance, 1.0))

	return _success({"texture": ImageTexture.create_from_image(height_image)})


func _build_blend_mask_texture() -> Dictionary:
	if _terrain_data == null:
		return _failure("TerrainRenderer2D requires terrain data before building a terrain blend mask.")

	var image := Image.create(
		_terrain_data.grid_width * MASK_PIXELS_PER_CELL,
		_terrain_data.grid_height * MASK_PIXELS_PER_CELL,
		false,
		Image.FORMAT_RGBA8
	)
	var terrain_types_by_coordinate := {}
	for cell in _terrain_data.cells:
		if not TerrainCellScript.is_known_terrain_type(cell.terrain_type):
			return _failure("TerrainRenderer2D cannot build mask for unknown terrain type '%s' at %s." % [cell.terrain_type, cell.coordinate])
		terrain_types_by_coordinate[cell.coordinate] = cell.terrain_type

	for cell in _terrain_data.cells:
		_write_cell_blend_mask(image, cell.coordinate, terrain_types_by_coordinate)

	_terrain_mask_texture = ImageTexture.create_from_image(image)
	return _success()


func _write_cell_blend_mask(image: Image, cell_coordinate: Vector2i, terrain_types_by_coordinate: Dictionary) -> void:
	var base_value := _mask_value_for_terrain_type(terrain_types_by_coordinate.get(cell_coordinate, TerrainCellScript.TERRAIN_TYPE_1))
	var edge_blend_width: float = clamp(blend_width_cells * 0.35, 0.125, 0.5)
	var has_left_boundary := _is_opposite_terrain(cell_coordinate + Vector2i.LEFT, base_value, terrain_types_by_coordinate)
	var has_right_boundary := _is_opposite_terrain(cell_coordinate + Vector2i.RIGHT, base_value, terrain_types_by_coordinate)
	var has_top_boundary := _is_opposite_terrain(cell_coordinate + Vector2i.UP, base_value, terrain_types_by_coordinate)
	var has_bottom_boundary := _is_opposite_terrain(cell_coordinate + Vector2i.DOWN, base_value, terrain_types_by_coordinate)
	var first_x_pixel := cell_coordinate.x * MASK_PIXELS_PER_CELL
	var first_y_pixel := cell_coordinate.y * MASK_PIXELS_PER_CELL

	for y_offset in range(MASK_PIXELS_PER_CELL):
		var y_position := (float(y_offset) + 0.5) / float(MASK_PIXELS_PER_CELL)
		for x_offset in range(MASK_PIXELS_PER_CELL):
			var x_position := (float(x_offset) + 0.5) / float(MASK_PIXELS_PER_CELL)
			var nearest_boundary_distance := _nearest_cell_boundary_distance(
				x_position,
				y_position,
				has_left_boundary,
				has_right_boundary,
				has_top_boundary,
				has_bottom_boundary
			)
			var mask_value := base_value
			if nearest_boundary_distance >= 0.0:
				var base_weight := smoothstep(0.0, edge_blend_width, nearest_boundary_distance)
				mask_value = lerpf(0.5, base_value, base_weight)
			image.set_pixel(
				first_x_pixel + x_offset,
				first_y_pixel + y_offset,
				Color(mask_value, mask_value, mask_value, 1.0)
			)


func _is_opposite_terrain(neighbor_coordinate: Vector2i, base_value: float, terrain_types_by_coordinate: Dictionary) -> bool:
	if not _terrain_data.is_cell_in_bounds(neighbor_coordinate):
		return false

	var neighbor_value := _mask_value_for_terrain_type(terrain_types_by_coordinate.get(neighbor_coordinate, TerrainCellScript.TERRAIN_TYPE_1))
	return not is_equal_approx(neighbor_value, base_value)


func _nearest_cell_boundary_distance(
	x_position: float,
	y_position: float,
	has_left_boundary: bool,
	has_right_boundary: bool,
	has_top_boundary: bool,
	has_bottom_boundary: bool
) -> float:
	var nearest_distance := -1.0
	if has_left_boundary:
		nearest_distance = x_position
	if has_right_boundary:
		nearest_distance = _min_boundary_distance(nearest_distance, 1.0 - x_position)
	if has_top_boundary:
		nearest_distance = _min_boundary_distance(nearest_distance, y_position)
	if has_bottom_boundary:
		nearest_distance = _min_boundary_distance(nearest_distance, 1.0 - y_position)

	return nearest_distance


func _min_boundary_distance(current_distance: float, candidate_distance: float) -> float:
	if current_distance < 0.0:
		return candidate_distance
	return minf(current_distance, candidate_distance)


func _mask_value_for_terrain_type(terrain_type: String) -> float:
	if terrain_type == TerrainCellScript.TERRAIN_TYPE_2:
		return 1.0

	return 0.0


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
