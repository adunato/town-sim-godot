class_name TerrainBlendMaskBuilder
extends RefCounted

const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")


func build(terrain_data: RefCounted, pixels_per_cell: int, blend_width_cells: float) -> Dictionary:
	if terrain_data == null:
		return _failure("TerrainBlendMaskBuilder requires terrain data.")
	if pixels_per_cell <= 0:
		return _failure("TerrainBlendMaskBuilder pixels_per_cell must be positive.")
	if blend_width_cells <= 0.0:
		return _failure("TerrainBlendMaskBuilder blend_width_cells must be positive.")

	var image := Image.create(
		terrain_data.grid_width * pixels_per_cell,
		terrain_data.grid_height * pixels_per_cell,
		false,
		Image.FORMAT_RGBA8
	)
	var terrain_types_by_coordinate := {}
	for cell in terrain_data.cells:
		if not TerrainCellScript.is_known_terrain_type(cell.terrain_type):
			return _failure("TerrainBlendMaskBuilder cannot build mask for unknown terrain type '%s' at %s." % [cell.terrain_type, cell.coordinate])
		terrain_types_by_coordinate[cell.coordinate] = cell.terrain_type

	for cell in terrain_data.cells:
		_write_cell_blend_mask(image, terrain_data, cell.coordinate, terrain_types_by_coordinate, pixels_per_cell, blend_width_cells)

	return _success({"texture": ImageTexture.create_from_image(image)})


func _write_cell_blend_mask(
	image: Image,
	terrain_data: RefCounted,
	cell_coordinate: Vector2i,
	terrain_types_by_coordinate: Dictionary,
	pixels_per_cell: int,
	blend_width_cells: float
) -> void:
	var base_value := _mask_value_for_terrain_type(terrain_types_by_coordinate.get(cell_coordinate, TerrainCellScript.TERRAIN_TYPE_1))
	var edge_blend_width: float = clamp(blend_width_cells * 0.35, 0.125, 0.5)
	var has_left_boundary := _is_opposite_terrain(terrain_data, cell_coordinate + Vector2i.LEFT, base_value, terrain_types_by_coordinate)
	var has_right_boundary := _is_opposite_terrain(terrain_data, cell_coordinate + Vector2i.RIGHT, base_value, terrain_types_by_coordinate)
	var has_top_boundary := _is_opposite_terrain(terrain_data, cell_coordinate + Vector2i.UP, base_value, terrain_types_by_coordinate)
	var has_bottom_boundary := _is_opposite_terrain(terrain_data, cell_coordinate + Vector2i.DOWN, base_value, terrain_types_by_coordinate)
	var first_x_pixel := cell_coordinate.x * pixels_per_cell
	var first_y_pixel := cell_coordinate.y * pixels_per_cell

	for y_offset in range(pixels_per_cell):
		var y_position := (float(y_offset) + 0.5) / float(pixels_per_cell)
		for x_offset in range(pixels_per_cell):
			var x_position := (float(x_offset) + 0.5) / float(pixels_per_cell)
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


func _is_opposite_terrain(terrain_data: RefCounted, neighbor_coordinate: Vector2i, base_value: float, terrain_types_by_coordinate: Dictionary) -> bool:
	if not terrain_data.is_cell_in_bounds(neighbor_coordinate):
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
