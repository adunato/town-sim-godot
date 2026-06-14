class_name TerrainGenerator
extends RefCounted

const TerrainConfigScript := preload("res://scripts/terrain/terrain_config.gd")
const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")
const TerrainDataScript := preload("res://scripts/terrain/terrain_data.gd")


func generate(config: RefCounted) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.seed = config.seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 1.0 / config.noise_scale

	var cells: Array = []
	for y in range(config.grid_height):
		for x in range(config.grid_width):
			var coordinate := Vector2i(x, y)
			var sampled_noise_value := noise.get_noise_2d(float(x), float(y))
			var terrain_type: String = TerrainCellScript.terrain_type_for_noise(sampled_noise_value, config.terrain_threshold)
			var footprint_result: Dictionary = config.cell_footprint(coordinate)
			if not footprint_result.ok:
				return footprint_result

			var cell := TerrainCellScript.new()
			var cell_result: Dictionary = cell.initialize(coordinate, sampled_noise_value, terrain_type, footprint_result.footprint)
			if not cell_result.ok:
				return cell_result

			cells.append(cell)

	var terrain_data := TerrainDataScript.new()
	var data_result: Dictionary = terrain_data.initialize_from_config(config, cells)
	if not data_result.ok:
		return data_result

	return _success({"terrain_data": terrain_data})


func load_and_generate(config_path: String = TerrainConfigScript.DEFAULT_CONFIG_PATH) -> Dictionary:
	var config := TerrainConfigScript.new()
	var load_result: Dictionary = config.load_from_file(config_path)
	if not load_result.ok:
		return load_result

	return generate(config)


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true}
	result.merge(extra, true)
	return result
