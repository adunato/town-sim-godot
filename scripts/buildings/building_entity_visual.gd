class_name BuildingEntityVisual
extends Node2D

const BUILDING_OUTLINE := Color(0.15, 0.11, 0.08, 0.95)
const BUILDING_OUTLINE_WIDTH := 2.0

var _rect := Rect2()
var _default_fill_color := Color.WHITE
var _default_outline_color := BUILDING_OUTLINE
var _default_outline_width := BUILDING_OUTLINE_WIDTH
var _fill_color := Color.WHITE
var _outline_color := BUILDING_OUTLINE
var _outline_width := BUILDING_OUTLINE_WIDTH
var _visual_profile: Dictionary = {}
var _sprite: Sprite2D
var _texture_path := ""
var _y_sort_origin_local_y := 0
var _highlight_active := false


func configure(rect_size: Vector2, fill_color: Color, visual_profile: Dictionary = {}) -> Dictionary:
	_rect = Rect2(Vector2.ZERO, rect_size)
	_default_fill_color = fill_color
	_default_outline_color = BUILDING_OUTLINE
	_default_outline_width = BUILDING_OUTLINE_WIDTH
	_fill_color = fill_color
	_outline_color = _default_outline_color
	_outline_width = _default_outline_width
	_visual_profile = visual_profile.duplicate(true)
	_texture_path = ""
	_y_sort_origin_local_y = int(round(rect_size.y))
	_highlight_active = false
	_clear_sprite()

	if not visual_profile.is_empty():
		var sprite_result := _configure_sprite(rect_size, visual_profile)
		if not sprite_result.ok:
			return sprite_result

	queue_redraw()
	return _success()


func get_visual_rect() -> Rect2:
	return Rect2(global_position, _rect.size)


func get_sprite_node() -> Sprite2D:
	return _sprite


func get_visual_profile_id() -> String:
	return String(_visual_profile.get("id", ""))


func get_texture_path() -> String:
	return _texture_path


func get_y_sort_origin_local_y() -> int:
	return _y_sort_origin_local_y


func set_highlight_color(fill_color: Color, outline_color: Color, outline_width: float) -> void:
	_fill_color = fill_color
	_outline_color = outline_color
	_outline_width = outline_width
	_highlight_active = true
	if _sprite != null:
		_sprite.modulate = fill_color
	queue_redraw()


func reset_highlight() -> void:
	_fill_color = _default_fill_color
	_outline_color = _default_outline_color
	_outline_width = _default_outline_width
	_highlight_active = false
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	queue_redraw()


func _configure_sprite(rect_size: Vector2, visual_profile: Dictionary) -> Dictionary:
	for field in ["id", "texture_path", "anchor", "pixel_offset", "y_sort_origin", "render_size"]:
		if not visual_profile.has(field):
			return _failure("Visual profile is missing required field '%s'." % field)

	var image := Image.new()
	var image_error := image.load(String(visual_profile.texture_path))
	if image_error != OK:
		return _failure("Visual profile '%s' texture_path '%s' did not load as an image." % [visual_profile.id, visual_profile.texture_path])

	var texture := ImageTexture.create_from_image(image)
	var sprite_texture: Texture2D = texture
	var source_size := Vector2(texture.get_width(), texture.get_height())
	if visual_profile.get("source_rect", null) != null:
		var source_rect_result := _source_rect_from_profile(visual_profile.source_rect, texture)
		if not source_rect_result.ok:
			return _failure("Visual profile '%s' has invalid source_rect: %s" % [visual_profile.id, source_rect_result.error])
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = source_rect_result.rect
		sprite_texture = atlas
		source_size = source_rect_result.rect.size

	var render_size := _render_size_from_profile(visual_profile)
	_sprite = Sprite2D.new()
	_sprite.name = "ProfileSprite"
	_sprite.centered = false
	_sprite.texture = sprite_texture
	_sprite.scale = Vector2(render_size.x / source_size.x, render_size.y / source_size.y)
	_sprite.position = _sprite_position_for_profile(rect_size, render_size, visual_profile)
	_sprite.y_sort_enabled = true
	_y_sort_origin_local_y = _local_y_for_y_sort_rule(rect_size, String(visual_profile.y_sort_origin))
	z_as_relative = false
	z_index = int(round(global_position.y)) + _y_sort_origin_local_y
	_texture_path = String(visual_profile.texture_path)
	add_child(_sprite)
	return _success()


func _clear_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.queue_free()
	_sprite = null


func _sprite_position_for_profile(rect_size: Vector2, source_size: Vector2, visual_profile: Dictionary) -> Vector2:
	var anchor_point := _anchor_point_for_rule(rect_size, String(visual_profile.anchor))
	var source_anchor := _source_anchor_for_rule(source_size, String(visual_profile.anchor))
	var offset := Vector2(int(visual_profile.pixel_offset.x), int(visual_profile.pixel_offset.y))
	return anchor_point - source_anchor + offset


func _render_size_from_profile(visual_profile: Dictionary) -> Vector2:
	return Vector2(float(visual_profile.render_size.width), float(visual_profile.render_size.height))


func _anchor_point_for_rule(rect_size: Vector2, anchor: String) -> Vector2:
	match anchor:
		"footprint_top_left":
			return Vector2.ZERO
		"footprint_center":
			return rect_size * 0.5
		"footprint_bottom_center":
			return Vector2(rect_size.x * 0.5, rect_size.y)
		_:
			return Vector2(rect_size.x * 0.5, rect_size.y)


func _source_anchor_for_rule(source_size: Vector2, anchor: String) -> Vector2:
	match anchor:
		"footprint_top_left":
			return Vector2.ZERO
		"footprint_center":
			return source_size * 0.5
		"footprint_bottom_center":
			return Vector2(source_size.x * 0.5, source_size.y)
		_:
			return Vector2(source_size.x * 0.5, source_size.y)


func _local_y_for_y_sort_rule(rect_size: Vector2, y_sort_origin: String) -> int:
	match y_sort_origin:
		"footprint_center":
			return int(round(rect_size.y * 0.5))
		"footprint_bottom_center":
			return int(round(rect_size.y))
		_:
			return int(round(rect_size.y))


func _source_rect_from_profile(value: Variant, texture: Texture2D) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("source_rect must be an object.")
	for field in ["x", "y", "width", "height"]:
		if not value.has(field) or not _is_integer_number(value[field]):
			return _failure("source_rect.%s must be an integer." % field)
	var rect := Rect2i(int(value.x), int(value.y), int(value.width), int(value.height))
	if rect.position.x < 0 or rect.position.y < 0 or rect.size.x <= 0 or rect.size.y <= 0:
		return _failure("source_rect must have non-negative x/y and positive width/height.")
	if rect.position.x + rect.size.x > texture.get_width() or rect.position.y + rect.size.y > texture.get_height():
		return _failure("source_rect must fit inside the texture.")
	return _success({"rect": Rect2(Vector2(rect.position), Vector2(rect.size))})


func _draw() -> void:
	if _rect.size == Vector2.ZERO:
		return

	if _sprite == null:
		draw_rect(_rect, _fill_color, true)
	if _sprite == null or _highlight_active:
		draw_rect(_rect, _outline_color, false, _outline_width)


func is_highlight_outline_visible() -> bool:
	return _sprite == null or _highlight_active


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	return is_equal_approx(float(value), float(int(value)))


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
