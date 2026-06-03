class_name PickableComponent
extends Node

var _world_rect := Rect2()


func configure(world_rect: Rect2) -> Dictionary:
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return _failure("PickableComponent requires a positive world_rect size.")
	_world_rect = world_rect
	return _success()


func get_world_rect() -> Rect2:
	return _world_rect


func contains_world_point(world_point: Vector2) -> bool:
	return _world_rect.has_point(world_point)


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
