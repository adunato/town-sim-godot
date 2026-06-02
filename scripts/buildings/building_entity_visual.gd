class_name BuildingEntityVisual
extends Node2D

const BUILDING_OUTLINE := Color(0.15, 0.11, 0.08, 0.95)
const BUILDING_OUTLINE_WIDTH := 2.0

var _rect := Rect2()
var _fill_color := Color.WHITE


func configure(rect_size: Vector2, fill_color: Color) -> void:
	_rect = Rect2(Vector2.ZERO, rect_size)
	_fill_color = fill_color
	queue_redraw()


func get_visual_rect() -> Rect2:
	return Rect2(global_position, _rect.size)


func _draw() -> void:
	if _rect.size == Vector2.ZERO:
		return

	draw_rect(_rect, _fill_color, true)
	draw_rect(_rect, BUILDING_OUTLINE, false, BUILDING_OUTLINE_WIDTH)
