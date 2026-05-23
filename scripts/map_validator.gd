extends RefCounted
class_name MapValidator

static func validate_catalogue(catalogue: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not catalogue.has("tile_size") or not _is_number(catalogue["tile_size"]):
		errors.append("tileset catalogue must define numeric tile_size")
	if not catalogue.has("tiles") or typeof(catalogue["tiles"]) != TYPE_DICTIONARY:
		errors.append("tileset catalogue must define a tiles dictionary")
		return errors

	for tile_id in catalogue["tiles"].keys():
		var tile = catalogue["tiles"][tile_id]
		if typeof(tile) != TYPE_DICTIONARY:
			errors.append("tile '%s' must be an object" % tile_id)
			continue
		if not tile.has("atlas") or typeof(tile["atlas"]) != TYPE_ARRAY or tile["atlas"].size() != 2:
			errors.append("tile '%s' must define atlas as [x, y]" % tile_id)
		if not tile.has("walkable") or typeof(tile["walkable"]) != TYPE_BOOL:
			errors.append("tile '%s' must define boolean walkable" % tile_id)
	return errors


static func validate_map(map_data: Dictionary, catalogue: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(_validate_dimensions(map_data))
	if not errors.is_empty():
		return errors

	var width := int(map_data["width"])
	var height := int(map_data["height"])
	var tiles: Array = map_data["tiles"]
	var catalogue_tiles: Dictionary = catalogue.get("tiles", {})

	for y in range(height):
		var row = tiles[y]
		for x in range(width):
			var tile_id = row[x]
			if typeof(tile_id) != TYPE_STRING:
				errors.append("tile at [%d, %d] must be a string ID" % [x, y])
			elif not catalogue_tiles.has(tile_id):
				errors.append("tile at [%d, %d] references unknown tile ID '%s'" % [x, y, tile_id])

	var spawn_errors := _validate_spawn(map_data, catalogue_tiles, width, height)
	errors.append_array(spawn_errors)
	if _count_walkable_tiles(tiles, catalogue_tiles) == 0:
		errors.append("map must contain at least one walkable tile")
	elif spawn_errors.is_empty():
		errors.append_array(_validate_walkable_path(tiles, catalogue_tiles, map_data["player_spawn"]))
	return errors


static func _validate_dimensions(map_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not map_data.has("width") or not _is_number(map_data["width"]):
		errors.append("map must define numeric width")
	if not map_data.has("height") or not _is_number(map_data["height"]):
		errors.append("map must define numeric height")
	if not map_data.has("tiles") or typeof(map_data["tiles"]) != TYPE_ARRAY:
		errors.append("map must define a tiles array")
	if not errors.is_empty():
		return errors

	var width := int(map_data["width"])
	var height := int(map_data["height"])
	var tiles: Array = map_data["tiles"]
	if width <= 0:
		errors.append("map width must be greater than zero")
	if height <= 0:
		errors.append("map height must be greater than zero")
	if tiles.size() != height:
		errors.append("map height is %d but tiles has %d rows" % [height, tiles.size()])
		return errors

	for y in range(height):
		if typeof(tiles[y]) != TYPE_ARRAY:
			errors.append("map row %d must be an array" % y)
		elif tiles[y].size() != width:
			errors.append("map width is %d but row %d has %d columns" % [width, y, tiles[y].size()])
	return errors


static func _validate_spawn(map_data: Dictionary, catalogue_tiles: Dictionary, width: int, height: int) -> Array[String]:
	var errors: Array[String] = []
	if not map_data.has("player_spawn") or typeof(map_data["player_spawn"]) != TYPE_ARRAY or map_data["player_spawn"].size() != 2:
		errors.append("map must define player_spawn as [x, y]")
		return errors

	var spawn := Vector2i(int(map_data["player_spawn"][0]), int(map_data["player_spawn"][1]))
	if spawn.x < 0 or spawn.y < 0 or spawn.x >= width or spawn.y >= height:
		errors.append("player_spawn [%d, %d] is outside map bounds" % [spawn.x, spawn.y])
		return errors

	var tile_id: String = map_data["tiles"][spawn.y][spawn.x]
	if catalogue_tiles.has(tile_id) and not bool(catalogue_tiles[tile_id].get("walkable", false)):
		errors.append("player_spawn [%d, %d] is on non-walkable tile '%s'" % [spawn.x, spawn.y, tile_id])
	return errors


static func _count_walkable_tiles(tiles: Array, catalogue_tiles: Dictionary) -> int:
	var count := 0
	for row in tiles:
		for tile_id in row:
			if catalogue_tiles.has(tile_id) and bool(catalogue_tiles[tile_id].get("walkable", false)):
				count += 1
	return count


static func _validate_walkable_path(tiles: Array, catalogue_tiles: Dictionary, player_spawn: Array) -> Array[String]:
	var errors: Array[String] = []
	var walkable_tiles := {}
	for y in range(tiles.size()):
		for x in range(tiles[y].size()):
			var tile_id = tiles[y][x]
			if catalogue_tiles.has(tile_id) and bool(catalogue_tiles[tile_id].get("walkable", false)):
				walkable_tiles[Vector2i(x, y)] = true

	var spawn := Vector2i(int(player_spawn[0]), int(player_spawn[1]))
	if not walkable_tiles.has(spawn):
		return errors

	var visited := {}
	var pending: Array = [spawn]
	while not pending.is_empty():
		var current: Vector2i = pending.pop_back()
		if visited.has(current):
			continue
		visited[current] = true
		for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = current + direction
			if walkable_tiles.has(next) and not visited.has(next):
				pending.append(next)

	if visited.size() < walkable_tiles.size():
		errors.append("walkable path is not continuous from player_spawn: %d of %d walkable tiles connected" % [visited.size(), walkable_tiles.size()])
	return errors


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
