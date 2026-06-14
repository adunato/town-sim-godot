extends SceneTree

const HEIGHT_CONTRAST_PREVIEW := 2.75

const HEIGHT_MAPS := [
	{
		"source": "res://assets/Textures/mud.png",
		"raw_output": "res://assets/Textures/derived_height/mud_height_from_diffuse.png",
		"preview_output": "res://assets/Textures/derived_height/mud_height_contrast_preview.png",
	},
	{
		"source": "res://assets/Textures/rocky_grass.png",
		"raw_output": "res://assets/Textures/derived_height/rocky_grass_height_from_diffuse.png",
		"preview_output": "res://assets/Textures/derived_height/rocky_grass_height_contrast_preview.png",
	},
]


func _initialize() -> void:
	var failures: Array[String] = []
	for height_map: Dictionary in HEIGHT_MAPS:
		failures.append_array(_write_height_map(height_map))

	if failures.is_empty():
		print("generate_terrain_height_maps.gd: generated diffuse-derived terrain height maps")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)


func _write_height_map(height_map: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	var source_path: String = height_map.source
	var raw_output_path: String = height_map.raw_output
	var preview_output_path: String = height_map.preview_output

	var source_image := Image.new()
	var load_result := source_image.load(source_path)
	if load_result != OK:
		return ["Unable to load terrain diffuse texture '%s': %s" % [source_path, error_string(load_result)]]

	var raw_height_image := Image.create(source_image.get_width(), source_image.get_height(), false, Image.FORMAT_RGBA8)
	var preview_height_image := Image.create(source_image.get_width(), source_image.get_height(), false, Image.FORMAT_RGBA8)

	for y in range(source_image.get_height()):
		for x in range(source_image.get_width()):
			var source_color := source_image.get_pixel(x, y)
			var luminance := _diffuse_luminance(source_color)
			var preview_value := clampf((luminance - 0.5) * HEIGHT_CONTRAST_PREVIEW + 0.5, 0.0, 1.0)
			raw_height_image.set_pixel(x, y, Color(luminance, luminance, luminance, 1.0))
			preview_height_image.set_pixel(x, y, Color(preview_value, preview_value, preview_value, 1.0))

	failures.append_array(_save_png(raw_height_image, raw_output_path))
	failures.append_array(_save_png(preview_height_image, preview_output_path))
	return failures


func _diffuse_luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _save_png(image: Image, path: String) -> Array[String]:
	var dir_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_result != OK:
		return ["Unable to create height map directory for '%s': %s" % [path, error_string(dir_result)]]

	var save_result := image.save_png(path)
	if save_result != OK:
		return ["Unable to save height map '%s': %s" % [path, error_string(save_result)]]

	return []
