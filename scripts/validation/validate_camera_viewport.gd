extends SceneTree

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")
const MainScene := preload("res://scenes/main.tscn")
const PlayerCameraControllerScript := preload("res://scripts/camera/player_camera_controller.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_camera_viewport.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var model := GridMapModelScript.new()
	var load_result: Dictionary = model.load_from_file()
	_expect(load_result.ok, "prototype_map.json should load for camera validation: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame

	_verify_scene_contract(scene)
	_verify_camera_contract(scene, model)
	_verify_zoom_input_actions()
	_verify_zoom_steps_and_limits(scene)
	_verify_invalid_zoom_configuration(scene, model)
	_verify_map_size_supports_camera_panning(scene, model)
	await _verify_center_edge_and_corner_visibility(scene, model)
	_verify_screen_space_ui(scene)

	scene.queue_free()
	await process_frame
	await process_frame


func _verify_scene_contract(scene: Node) -> void:
	_expect(scene.has_node("World/Player"), "main scene should contain World/Player")
	_expect(scene.has_node("World/Player/PlayerCamera"), "Player scene should contain PlayerCamera")

	var camera := scene.get_node("World/Player/PlayerCamera")
	_expect(camera is Camera2D, "PlayerCamera should be a Camera2D")
	_expect(camera.get_script() == PlayerCameraControllerScript, "PlayerCamera should use player_camera_controller.gd")


func _verify_camera_contract(scene: Node, model: RefCounted) -> void:
	var camera := scene.get_node("World/Player/PlayerCamera")
	_expect(camera.call("is_configured"), "PlayerCamera should be configured during startup")
	_expect(camera.call("get_active_mode") == &"centered_player", "PlayerCamera active mode should be centered_player")
	_expect(camera.zoom == camera.initial_zoom, "PlayerCamera should apply initial_zoom at runtime")
	_expect(camera.is_current(), "PlayerCamera should be the current active camera")
	_expect(_camera_contract_excludes_padded_player(camera), "PlayerCamera contract should not expose padded_player or padding configuration")

	var expected_rect := Rect2(model.origin, Vector2(model.grid_width, model.grid_height) * float(model.cell_size))
	var actual_rect: Rect2 = camera.call("get_map_world_rect")
	_expect(actual_rect == expected_rect, "PlayerCamera map world rect expected %s, got %s" % [expected_rect, actual_rect])

	var limits_rect: Rect2 = camera.call("get_camera_limits_rect")
	_expect(limits_rect == expected_rect, "PlayerCamera limits expected %s, got %s" % [expected_rect, limits_rect])


func _verify_zoom_input_actions() -> void:
	_expect(InputMap.has_action("zoom_in"), "project should define zoom_in input action")
	_expect(InputMap.has_action("zoom_out"), "project should define zoom_out input action")
	_expect(_action_has_mouse_button("zoom_in", MOUSE_BUTTON_WHEEL_UP), "zoom_in should bind mouse-wheel up")
	_expect(_action_has_mouse_button("zoom_out", MOUSE_BUTTON_WHEEL_DOWN), "zoom_out should bind mouse-wheel down")


func _verify_zoom_steps_and_limits(scene: Node) -> void:
	var camera := scene.get_node("World/Player/PlayerCamera")
	var original_zoom: Vector2 = camera.zoom
	var original_step: float = camera.zoom_step
	var original_minimum: float = camera.minimum_zoom
	var original_maximum: float = camera.maximum_zoom

	camera.zoom_step = 0.25
	camera.minimum_zoom = 2.0
	camera.maximum_zoom = 4.0
	camera.zoom = Vector2(3.0, 3.0)

	camera.call("apply_zoom_step", 1)
	_expect(camera.zoom == Vector2(3.25, 3.25), "zoom_in should increase both axes by exactly zoom_step")
	camera.call("apply_zoom_step", -1)
	_expect(camera.zoom == Vector2(3.0, 3.0), "zoom_out should decrease both axes by exactly zoom_step")

	camera.zoom = Vector2(3.9, 3.9)
	camera.call("apply_zoom_step", 1)
	_expect(camera.zoom == Vector2(4.0, 4.0), "zoom_in should clamp uniformly at maximum_zoom")
	camera.zoom = Vector2(2.1, 2.1)
	camera.call("apply_zoom_step", -1)
	_expect(camera.zoom == Vector2(2.0, 2.0), "zoom_out should clamp uniformly at minimum_zoom")

	camera.zoom_step = original_step
	camera.minimum_zoom = original_minimum
	camera.maximum_zoom = original_maximum
	camera.zoom = original_zoom


func _verify_invalid_zoom_configuration(scene: Node, model: RefCounted) -> void:
	var camera := scene.get_node("World/Player/PlayerCamera")
	var original_zoom: Vector2 = camera.initial_zoom
	var original_step: float = camera.zoom_step
	var original_minimum: float = camera.minimum_zoom
	var original_maximum: float = camera.maximum_zoom

	camera.zoom_step = 0.0
	var result: Dictionary = camera.call("configure_for_map", model)
	_expect(not result.ok and String(result.error).contains("zoom_step"), "zero zoom_step should return a concrete configuration error")

	camera.zoom_step = original_step
	camera.minimum_zoom = 4.0
	camera.maximum_zoom = 2.0
	result = camera.call("configure_for_map", model)
	_expect(not result.ok and String(result.error).contains("minimum_zoom"), "minimum_zoom above maximum_zoom should return a concrete configuration error")

	camera.minimum_zoom = original_minimum
	camera.maximum_zoom = original_maximum
	camera.initial_zoom = Vector2(original_minimum - 0.1, original_minimum - 0.1)
	result = camera.call("configure_for_map", model)
	_expect(not result.ok and String(result.error).contains("initial_zoom"), "initial_zoom outside limits should return a concrete configuration error")

	camera.initial_zoom = original_zoom
	camera.zoom_step = original_step
	camera.minimum_zoom = original_minimum
	camera.maximum_zoom = original_maximum
	result = camera.call("configure_for_map", model)
	_expect(result.ok, "camera should reconfigure after restoring valid zoom settings")


func _verify_map_size_supports_camera_panning(scene: Node, model: RefCounted) -> void:
	var camera := scene.get_node("World/Player/PlayerCamera")
	var visible_size: Vector2 = camera.call("get_visible_world_size")
	var map_size := Vector2(model.grid_width, model.grid_height) * float(model.cell_size)

	_expect(map_size.x > visible_size.x * 1.5, "prototype_map.json width should be large enough to observe horizontal camera panning")
	_expect(map_size.y > visible_size.y * 1.5, "prototype_map.json height should be large enough to observe vertical camera panning")

	var spawn_position_result: Dictionary = model.cell_to_world(model.player_spawn_cell)
	_expect(spawn_position_result.ok, "player_spawn_cell should convert to a world position")
	if spawn_position_result.ok:
		var spawn_position: Vector2 = spawn_position_result.world_position
		var half_visible := visible_size * 0.5
		_expect(spawn_position.x > model.origin.x + half_visible.x, "player spawn should start far enough from the left edge for centered camera validation")
		_expect(spawn_position.y > model.origin.y + half_visible.y, "player spawn should start far enough from the top edge for centered camera validation")
		_expect(spawn_position.x < model.origin.x + map_size.x - half_visible.x, "player spawn should start far enough from the right edge for centered camera validation")
		_expect(spawn_position.y < model.origin.y + map_size.y - half_visible.y, "player spawn should start far enough from the bottom edge for centered camera validation")


func _verify_center_edge_and_corner_visibility(scene: Node, model: RefCounted) -> void:
	var player := scene.get_node("World/Player")
	var camera := scene.get_node("World/Player/PlayerCamera")
	var visible_size: Vector2 = camera.call("get_visible_world_size")
	var map_rect := Rect2(model.origin, Vector2(model.grid_width, model.grid_height) * float(model.cell_size))
	var center_position := map_rect.position + map_rect.size * 0.5

	player.global_position = center_position
	await process_frame
	_expect(camera.global_position == player.global_position, "PlayerCamera should share the player's global position in the middle of the map")
	_expect(camera.call("get_limited_camera_center_for_world_position", center_position) == center_position, "Camera center should not be clamped in the middle of the map")

	var edge_positions := [
		Vector2(map_rect.position.x + 16.0, center_position.y),
		Vector2(map_rect.end.x - 16.0, center_position.y),
		Vector2(center_position.x, map_rect.position.y + 16.0),
		Vector2(center_position.x, map_rect.end.y - 16.0),
		Vector2(map_rect.position.x + 16.0, map_rect.position.y + 16.0),
		Vector2(map_rect.end.x - 16.0, map_rect.end.y - 16.0),
	]

	for edge_position in edge_positions:
		_expect(_world_position_is_visible_after_limit(camera, edge_position, visible_size), "Player should remain visible near map edge or corner at %s" % edge_position)


func _verify_screen_space_ui(scene: Node) -> void:
	_expect(scene.has_node("UI"), "main scene should contain UI branch")
	_expect(scene.get_node("UI") is CanvasLayer, "UI branch should be a CanvasLayer")
	_expect(scene.get_node("UI").get_parent() == scene, "UI branch should not be parented under World")


func _camera_contract_excludes_padded_player(camera: Object) -> bool:
	if camera.has_method("configure_padded_player") or camera.has_method("set_padding"):
		return false

	for property in camera.get_property_list():
		var property_name := String(property.name).to_lower()
		if property_name.contains("padded_player") or property_name.contains("padding"):
			return false

	return true


func _action_has_mouse_button(action: StringName, button_index: MouseButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button_index:
			return true

	return false


func _world_position_is_visible_after_limit(camera: Node, world_position: Vector2, visible_size: Vector2) -> bool:
	var limited_center: Vector2 = camera.call("get_limited_camera_center_for_world_position", world_position)
	var screen_position := world_position - limited_center + visible_size * 0.5

	return screen_position.x >= 0.0 \
		and screen_position.y >= 0.0 \
		and screen_position.x <= visible_size.x \
		and screen_position.y <= visible_size.y


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
