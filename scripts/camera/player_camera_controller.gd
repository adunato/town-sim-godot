class_name PlayerCameraController
extends Camera2D

const MODE_CENTERED_PLAYER := &"centered_player"
const NO_MAP_MODEL_ERROR := "PlayerCameraController has no map model assigned."
const UNSUPPORTED_MODE_ERROR := "PlayerCameraController only supports centered_player mode."

@export var active_mode: StringName = MODE_CENTERED_PLAYER
@export var initial_zoom: Vector2 = Vector2.ONE

var _map_model: RefCounted
var _map_world_rect: Rect2 = Rect2()
var _configured := false


func _ready() -> void:
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)


func configure_for_map(map_model: RefCounted) -> Dictionary:
	if active_mode != MODE_CENTERED_PLAYER:
		return _failure("%s Got '%s'." % [UNSUPPORTED_MODE_ERROR, active_mode])
	if map_model == null:
		return _failure(NO_MAP_MODEL_ERROR)
	if not _map_model_has_required_contract(map_model):
		return _failure("Map model is missing grid dimensions, cell size, or origin.")
	if initial_zoom.x <= 0.0 or initial_zoom.y <= 0.0:
		return _failure("initial_zoom must be positive on both axes.")

	_map_model = map_model
	_configured = true
	zoom = initial_zoom
	make_current()
	_apply_map_limits()

	return _success()


func is_configured() -> bool:
	return _configured


func get_map_world_rect() -> Rect2:
	return _map_world_rect


func get_visible_world_size() -> Vector2:
	var viewport_size := Vector2(get_viewport_rect().size)
	return Vector2(viewport_size.x / zoom.x, viewport_size.y / zoom.y)


func get_camera_limits_rect() -> Rect2:
	return Rect2(
		Vector2(float(limit_left), float(limit_top)),
		Vector2(float(limit_right - limit_left), float(limit_bottom - limit_top))
	)


func get_active_mode() -> StringName:
	return active_mode


func get_limited_camera_center_for_world_position(world_position: Vector2) -> Vector2:
	var half_visible := get_visible_world_size() * 0.5
	var min_center := Vector2(float(limit_left), float(limit_top)) + half_visible
	var max_center := Vector2(float(limit_right), float(limit_bottom)) - half_visible

	return Vector2(
		clampf(world_position.x, min_center.x, max_center.x),
		clampf(world_position.y, min_center.y, max_center.y)
	)


func _apply_map_limits() -> void:
	if _map_model == null:
		return

	_map_world_rect = _calculate_map_world_rect(_map_model)
	limit_left = roundi(_map_world_rect.position.x)
	limit_top = roundi(_map_world_rect.position.y)
	limit_right = roundi(_map_world_rect.position.x + _map_world_rect.size.x)
	limit_bottom = roundi(_map_world_rect.position.y + _map_world_rect.size.y)


func _calculate_map_world_rect(map_model: RefCounted) -> Rect2:
	return Rect2(
		map_model.origin,
		Vector2(map_model.grid_width, map_model.grid_height) * float(map_model.cell_size)
	)


func _map_model_has_required_contract(map_model: RefCounted) -> bool:
	return map_model.get("origin") is Vector2 \
		and typeof(map_model.get("grid_width")) == TYPE_INT \
		and typeof(map_model.get("grid_height")) == TYPE_INT \
		and typeof(map_model.get("cell_size")) == TYPE_INT


func _on_viewport_size_changed() -> void:
	if _configured:
		_apply_map_limits()


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
