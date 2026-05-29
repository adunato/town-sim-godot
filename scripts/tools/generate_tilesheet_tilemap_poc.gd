extends SceneTree

const DEFAULT_INPUT := "res://data/poc/tilesheet_tilemap_poc.json"

func _init() -> void:
	var input_path := _get_input_path()
	var result := generate_from_json(input_path)
	if result != OK:
		printerr("Tilesheet tilemap POC generation failed with error code: %s" % result)
		quit(result)
		return
	print("Generated tilesheet tilemap POC from %s" % input_path)
	quit(OK)


func _get_input_path() -> String:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--input" and index + 1 < args.size():
			return args[index + 1]
	return DEFAULT_INPUT


func generate_from_json(input_path: String) -> Error:
	if not FileAccess.file_exists(input_path):
		printerr("Missing input JSON: %s" % input_path)
		return ERR_FILE_NOT_FOUND

	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	if typeof(data) != TYPE_DICTIONARY:
		printerr("Input JSON must be an object: %s" % input_path)
		return ERR_PARSE_ERROR

	var atlas: Dictionary = data.get("atlas", {})
	var output: Dictionary = data.get("output", {})
	var tiles: Array = data.get("tiles", [])
	var cells: Array = data.get("cells", [])
	var atlas_path := String(atlas.get("path", ""))
	var tileset_path := String(output.get("tileset", ""))
	var scene_path := String(output.get("scene", ""))
	var tile_size: Vector2i = _array_to_vector2i(atlas.get("tile_size", [16, 16]))
	var atlas_size: Vector2i = _array_to_vector2i(atlas.get("size", [128, 64]))
	var rect_origin := String(atlas.get("rect_origin", "top_left"))

	if atlas_path.is_empty() or tileset_path.is_empty() or scene_path.is_empty():
		printerr("Input JSON must define atlas.path, output.tileset, and output.scene")
		return ERR_INVALID_DATA

	var texture: Texture2D
	if bool(atlas.get("generate_placeholder", false)):
		texture = _generate_placeholder_atlas(atlas_path, atlas_size, tiles)
	else:
		texture = _load_texture_from_image(atlas_path)
	if texture == null:
		printerr("Failed to load atlas texture: %s" % atlas_path)
		return ERR_CANT_OPEN

	var tileset := TileSet.new()
	tileset.tile_size = tile_size
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = tile_size

	var id_to_atlas_coords: Dictionary = {}
	for tile_data in tiles:
		var tile: Dictionary = tile_data
		var rect: Rect2i = _array_to_rect2i(tile.get("rect", [0, 0, tile_size.x, tile_size.y]))
		if rect_origin == "bottom_left":
			rect.position.y = atlas_size.y - rect.position.y - rect.size.y
		if rect.size != tile_size:
			printerr("POC supports one fixed tile size. Tile %s has rect size %s." % [tile.get("name", tile.get("id", "?")), rect.size])
			return ERR_INVALID_DATA
		if rect.position.x % tile_size.x != 0 or rect.position.y % tile_size.y != 0:
			printerr("Tile rect must align to the atlas grid: %s" % tile)
			return ERR_INVALID_DATA
		var atlas_coords := Vector2i(int(rect.position.x / tile_size.x), int(rect.position.y / tile_size.y))
		source.create_tile(atlas_coords)
		id_to_atlas_coords[int(tile.get("id", 0))] = atlas_coords

	var source_id: int = tileset.add_source(source)
	var save_tileset_error: Error = _save_resource(tileset, tileset_path)
	if save_tileset_error != OK:
		return save_tileset_error

	var root := Node2D.new()
	root.name = "TilesheetTilemapPoc"
	var layer := TileMapLayer.new()
	layer.name = "Terrain"
	layer.tile_set = tileset
	root.add_child(layer)
	layer.owner = root

	for cell_data in cells:
		var cell: Dictionary = cell_data
		var tile_id: int = int(cell.get("tile", -1))
		if not id_to_atlas_coords.has(tile_id):
			printerr("Cell references unknown tile id: %s" % tile_id)
			return ERR_INVALID_DATA
		var coords := Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0)))
		layer.set_cell(coords, source_id, id_to_atlas_coords[tile_id], 0)

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = Vector2(64, 40)
	camera.zoom = Vector2(4, 4)
	camera.enabled = true
	root.add_child(camera)
	camera.owner = root

	var scene := PackedScene.new()
	var pack_error: Error = scene.pack(root)
	if pack_error != OK:
		printerr("Failed to pack scene: %s" % scene_path)
		return pack_error

	return _save_resource(scene, scene_path)


func _generate_placeholder_atlas(path: String, size: Vector2i, tiles: Array) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("#23313d"))
	var tile_size := Vector2i(16, 16)
	for tile_data in tiles:
		var tile: Dictionary = tile_data
		var rect: Rect2i = _array_to_rect2i(tile.get("rect", [0, 0, tile_size.x, tile_size.y]))
		var color := Color(String(tile.get("color", "#ff00ff")))
		image.fill_rect(rect, color)
		_draw_tile_grid(image, rect, color.darkened(0.25))
		_draw_tile_detail(image, rect, int(tile.get("id", 0)), color.lightened(0.2))
	_ensure_parent_dir(path)
	var error: Error = image.save_png(path)
	if error != OK:
		printerr("Failed to save placeholder atlas: %s" % path)
		return null
	return ImageTexture.create_from_image(image)


func _load_texture_from_image(path: String) -> Texture2D:
	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		printerr("Failed to load image file %s: %s" % [path, error])
		return null
	return ImageTexture.create_from_image(image)


func _draw_tile_grid(image: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		image.set_pixel(x, rect.position.y, color)
		image.set_pixel(x, rect.position.y + rect.size.y - 1, color)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		image.set_pixel(rect.position.x, y, color)
		image.set_pixel(rect.position.x + rect.size.x - 1, y, color)


func _draw_tile_detail(image: Image, rect: Rect2i, tile_id: int, color: Color) -> void:
	var center := rect.position + Vector2i(int(rect.size.x / 2), int(rect.size.y / 2))
	var radius: int = 2 + tile_id % 4
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var pos := Vector2i(x, y)
			if rect.has_point(pos) and pos.distance_to(center) <= radius:
				image.set_pixel(x, y, color)


func _array_to_vector2i(value: Variant) -> Vector2i:
	var items: Array = value
	return Vector2i(int(items[0]), int(items[1]))


func _array_to_rect2i(value: Variant) -> Rect2i:
	var items: Array = value
	return Rect2i(int(items[0]), int(items[1]), int(items[2]), int(items[3]))


func _save_resource(resource: Resource, path: String) -> Error:
	_ensure_parent_dir(path)
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		printerr("Failed to save resource %s: %s" % [path, error])
	return error


func _ensure_parent_dir(resource_path: String) -> void:
	var global_path := ProjectSettings.globalize_path(resource_path)
	var directory := global_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
