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


func configure(rect_size: Vector2, fill_color: Color) -> void:
	_rect = Rect2(Vector2.ZERO, rect_size)
	_default_fill_color = fill_color
	_default_outline_color = BUILDING_OUTLINE
	_default_outline_width = BUILDING_OUTLINE_WIDTH
	_fill_color = fill_color
	_outline_color = _default_outline_color
	_outline_width = _default_outline_width
	queue_redraw()


func get_visual_rect() -> Rect2:
	return Rect2(global_position, _rect.size)


func set_highlight_color(fill_color: Color, outline_color: Color, outline_width: float) -> void:
	_fill_color = fill_color
	_outline_color = outline_color
	_outline_width = outline_width
	queue_redraw()


func reset_highlight() -> void:
	_fill_color = _default_fill_color
	_outline_color = _default_outline_color
	_outline_width = _default_outline_width
	queue_redraw()


func _draw() -> void:
	if _rect.size == Vector2.ZERO:
		return

	draw_rect(_rect, _fill_color, true)
	draw_rect(_rect, _outline_color, false, _outline_width)
