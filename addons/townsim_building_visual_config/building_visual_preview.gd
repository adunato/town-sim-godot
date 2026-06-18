@tool
class_name BuildingVisualPreview
extends Control

const DEFAULT_CELL_SIZE := 32
const GRID_FILL := Color(0.14, 0.18, 0.16, 1.0)
const GRID_LINE := Color(0.55, 0.68, 0.56, 0.55)
const SPRITE_TINT := Color(1.0, 1.0, 1.0, 0.86)
const ANCHOR_COLOR := Color(0.95, 0.18, 0.16, 1.0)
const OFFSET_COLOR := Color(0.15, 0.58, 0.96, 1.0)
const Y_SORT_COLOR := Color(0.95, 0.74, 0.18, 1.0)
const BOUNDS_COLOR := Color(0.70, 0.35, 0.92, 1.0)

var _definition: Dictionary = {}
var _profile: Dictionary = {}
var _texture: Texture2D
var _texture_path := ""


func _ready() -> void:
	custom_minimum_size = Vector2(520, 320)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func set_preview_data(definition: Dictionary, profile: Dictionary) -> void:
	_definition = definition.duplicate(true)
	_profile = profile.duplicate(true)
	_load_texture()
	queue_redraw()


func _load_texture() -> void:
	var next_path := String(_profile.get("texture_path", ""))
	if next_path == _texture_path:
		return
	_texture_path = next_path
	_texture = null
	if _texture_path.is_empty():
		return
	var image := Image.new()
	if image.load(_texture_path) != OK:
		return
	_texture = ImageTexture.create_from_image(image)


func _draw() -> void:
	if _definition.is_empty() or _profile.is_empty():
		return

	var footprint_size := _footprint_size()
	if footprint_size.x <= 0 or footprint_size.y <= 0:
		return

	var footprint_rect := Rect2(Vector2.ZERO, footprint_size * float(DEFAULT_CELL_SIZE))
	var source_rect := _source_rect()
	var render_size := _render_size(source_rect.size)
	var sprite_position := _sprite_position(footprint_rect.size, render_size)
	var sprite_rect := Rect2(sprite_position, render_size)
	var visual_bounds := _visual_bounds(sprite_rect)
	var content_rect := footprint_rect.merge(sprite_rect).merge(visual_bounds).grow(24.0)
	var fit := _fit_rect(content_rect)

	_draw_footprint(footprint_size, fit)
	if _texture != null:
		draw_texture_rect_region(_texture, _transform_rect(sprite_rect, fit), source_rect, SPRITE_TINT)

	draw_rect(_transform_rect(visual_bounds, fit), BOUNDS_COLOR, false, 2.0)
	_draw_marker(_transform_point(_anchor_point(footprint_rect.size, String(_profile.get("anchor", ""))), fit), ANCHOR_COLOR, 6.0)
	_draw_marker(_transform_point(sprite_position, fit), OFFSET_COLOR, 4.0)

	var y_sort_y := _y_sort_origin_y(footprint_rect.size, String(_profile.get("y_sort_origin", "")))
	var start := _transform_point(Vector2(footprint_rect.position.x, y_sort_y), fit)
	var end := _transform_point(Vector2(footprint_rect.end.x, y_sort_y), fit)
	draw_line(start, end, Y_SORT_COLOR, 2.0)


func _draw_footprint(footprint_size: Vector2, fit: Dictionary) -> void:
	for y in range(int(footprint_size.y)):
		for x in range(int(footprint_size.x)):
			var rect := Rect2(Vector2(x, y) * float(DEFAULT_CELL_SIZE), Vector2.ONE * float(DEFAULT_CELL_SIZE))
			draw_rect(_transform_rect(rect, fit), GRID_FILL, true)
			draw_rect(_transform_rect(rect, fit), GRID_LINE, false, 1.0)


func _draw_marker(center: Vector2, color: Color, radius: float) -> void:
	draw_circle(center, radius, color)
	draw_line(center + Vector2(-radius * 1.8, 0.0), center + Vector2(radius * 1.8, 0.0), Color.WHITE, 1.0)
	draw_line(center + Vector2(0.0, -radius * 1.8), center + Vector2(0.0, radius * 1.8), Color.WHITE, 1.0)


func _fit_rect(content_rect: Rect2) -> Dictionary:
	var available := size - Vector2(24, 24)
	var scale: float = min(available.x / maxf(content_rect.size.x, 1.0), available.y / maxf(content_rect.size.y, 1.0))
	scale = clampf(scale, 0.25, 4.0)
	var offset: Vector2 = (size - content_rect.size * scale) * 0.5 - content_rect.position * scale
	return {"scale": scale, "offset": offset}


func _transform_point(point: Vector2, fit: Dictionary) -> Vector2:
	return point * float(fit.scale) + Vector2(fit.offset)


func _transform_rect(rect: Rect2, fit: Dictionary) -> Rect2:
	return Rect2(_transform_point(rect.position, fit), rect.size * float(fit.scale))


func _footprint_size() -> Vector2:
	var footprint: Dictionary = _definition.get("footprint_cells", {})
	return Vector2(float(footprint.get("width", 0)), float(footprint.get("height", 0)))


func _source_rect() -> Rect2:
	if _texture == null:
		return Rect2(Vector2.ZERO, Vector2.ONE * float(DEFAULT_CELL_SIZE))
	var source_rect: Variant = _profile.get("source_rect", null)
	if typeof(source_rect) == TYPE_DICTIONARY:
		return Rect2(
			Vector2(float(source_rect.get("x", 0)), float(source_rect.get("y", 0))),
			Vector2(float(source_rect.get("width", _texture.get_width())), float(source_rect.get("height", _texture.get_height())))
		)
	return Rect2(Vector2.ZERO, Vector2(_texture.get_width(), _texture.get_height()))


func _render_size(source_size: Vector2) -> Vector2:
	var render_size: Variant = _profile.get("render_size", null)
	if typeof(render_size) == TYPE_DICTIONARY:
		return Vector2(float(render_size.get("width", source_size.x)), float(render_size.get("height", source_size.y)))
	return source_size


func _visual_bounds(sprite_rect: Rect2) -> Rect2:
	var bounds: Variant = _profile.get("visual_bounds", null)
	if typeof(bounds) == TYPE_DICTIONARY:
		return Rect2(
			Vector2(float(bounds.get("x", 0)), float(bounds.get("y", 0))),
			Vector2(float(bounds.get("width", 1)), float(bounds.get("height", 1)))
		)
	return sprite_rect


func _sprite_position(rect_size: Vector2, source_size: Vector2) -> Vector2:
	var anchor := String(_profile.get("anchor", ""))
	var anchor_point := _anchor_point(rect_size, anchor)
	var source_anchor := _source_anchor(source_size, anchor)
	var offset: Dictionary = _profile.get("pixel_offset", {})
	return anchor_point - source_anchor + Vector2(int(offset.get("x", 0)), int(offset.get("y", 0)))


func _anchor_point(rect_size: Vector2, anchor: String) -> Vector2:
	match anchor:
		"footprint_top_left":
			return Vector2.ZERO
		"footprint_center":
			return rect_size * 0.5
		"footprint_bottom_center":
			return Vector2(rect_size.x * 0.5, rect_size.y)
		_:
			return Vector2(rect_size.x * 0.5, rect_size.y)


func _source_anchor(source_size: Vector2, anchor: String) -> Vector2:
	match anchor:
		"footprint_top_left":
			return Vector2.ZERO
		"footprint_center":
			return source_size * 0.5
		"footprint_bottom_center":
			return Vector2(source_size.x * 0.5, source_size.y)
		_:
			return Vector2(source_size.x * 0.5, source_size.y)


func _y_sort_origin_y(rect_size: Vector2, y_sort_origin: String) -> float:
	match y_sort_origin:
		"footprint_center":
			return rect_size.y * 0.5
		"footprint_bottom_center":
			return rect_size.y
		_:
			return rect_size.y
