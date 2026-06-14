class_name TerrainData
extends RefCounted

const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")

var grid_width: int = 0
var grid_height: int = 0
var cell_size: int = 0
var origin: Vector2 = Vector2.ZERO
var seed: int = 0
var noise_scale: float = 0.0
var terrain_threshold: float = 0.0
var cells: Array = []

var _cells_by_key: Dictionary = {}


func initialize_from_config(config: RefCounted, generated_cells: Array) -> Dictionary:
	if generated_cells.size() != config.grid_width * config.grid_height:
		return _failure("Generated terrain cell count %d does not match expected grid count %d." % [generated_cells.size(), config.grid_width * config.grid_height])

	grid_width = config.grid_width
	grid_height = config.grid_height
	cell_size = config.cell_size
	origin = config.origin
	seed = config.seed
	noise_scale = config.noise_scale
	terrain_threshold = config.terrain_threshold
	cells = generated_cells.duplicate()
	_cells_by_key.clear()

	for cell in cells:
		if not is_cell_in_bounds(cell.coordinate):
			return _failure("Generated terrain cell %s is outside terrain bounds." % cell.coordinate)
		var key := _cell_key(cell.coordinate)
		if _cells_by_key.has(key):
			return _failure("Generated terrain includes duplicate cell %s." % cell.coordinate)
		_cells_by_key[key] = cell

	return _success()


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_height


func get_cell(cell: Vector2i) -> Dictionary:
	if not is_cell_in_bounds(cell):
		return _failure("Terrain cell %s is outside terrain bounds." % cell)

	var key := _cell_key(cell)
	if not _cells_by_key.has(key):
		return _failure("Terrain cell %s was not generated." % cell)

	return _success({"cell": _cells_by_key[key]})


func get_world_bounds() -> Rect2:
	return Rect2(origin, Vector2(grid_width * cell_size, grid_height * cell_size))


func count_by_terrain_type() -> Dictionary:
	var counts := {
		TerrainCellScript.TERRAIN_TYPE_1: 0,
		TerrainCellScript.TERRAIN_TYPE_2: 0,
	}
	for cell in cells:
		counts[cell.terrain_type] = int(counts.get(cell.terrain_type, 0)) + 1

	return counts


func terrain_type_row_preview(max_rows: int = 4, max_columns: int = 24) -> PackedStringArray:
	var rows := PackedStringArray()
	var row_count := mini(grid_height, max_rows)
	var column_count := mini(grid_width, max_columns)
	for y in range(row_count):
		var row := ""
		for x in range(column_count):
			var result := get_cell(Vector2i(x, y))
			if not result.ok:
				row += "?"
				continue
			var cell: RefCounted = result.cell
			row += "1" if cell.terrain_type == TerrainCellScript.TERRAIN_TYPE_1 else "2"
		rows.append(row)

	return rows


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


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
