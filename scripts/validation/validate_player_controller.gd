extends SceneTree

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const MainScene := preload("res://scenes/main.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_player_controller.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var model := GridMapModelScript.new()
	var load_result: Dictionary = model.load_from_file()
	_expect(load_result.ok, "prototype_map.json should load for player validation: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	await _verify_player_scene(model)
	await _verify_startup_scene(model)
	_verify_input_actions()


func _verify_player_scene(model: RefCounted) -> void:
	var player := PlayerScene.instantiate()
	get_root().add_child(player)
	await process_frame

	_expect(player is CharacterBody2D, "Player scene root should be CharacterBody2D")
	_expect(player.name == "Player", "Player scene root should be named Player")
	_expect(player.get_script() != null and player.get_script().resource_path == "res://scripts/player/player_controller.gd", "Player scene root should use player_controller.gd")
	_expect(player.has_node("CollisionShape2D"), "Player scene should contain CollisionShape2D child")

	var collision_shape := player.get_node("CollisionShape2D")
	_expect(collision_shape is CollisionShape2D, "CollisionShape2D child should be a CollisionShape2D node")
	_expect(collision_shape.shape is CircleShape2D, "Player CollisionShape2D should use CircleShape2D")
	_expect(collision_shape.shape.radius == player.visual_radius, "Player collision radius should match visual radius")

	_verify_player_contract(player, model)
	_verify_movement_contract(player)

	player.queue_free()
	await process_frame
	await process_frame


func _verify_player_contract(player: Node, model: RefCounted) -> void:
	_expect(player.has_method("set_map_model"), "Player root should expose set_map_model")
	_expect(player.has_method("get_world_position"), "Player root should expose get_world_position")
	_expect(player.has_method("get_current_grid_cell"), "Player root should expose get_current_grid_cell")

	var missing_model_result: Dictionary = player.call("get_current_grid_cell")
	_expect(not missing_model_result.ok, "get_current_grid_cell should fail explicitly when no map model is assigned")

	player.call("set_map_model", model)
	var expected_position_result: Dictionary = model.cell_to_world(model.player_spawn_cell)
	_expect(expected_position_result.ok, "cell_to_world should accept player_spawn_cell")
	player.global_position = expected_position_result.world_position

	var position: Vector2 = player.call("get_world_position")
	_expect(position == expected_position_result.world_position, "get_world_position should return player global_position")

	var cell_result: Dictionary = player.call("get_current_grid_cell")
	_expect(cell_result.ok, "get_current_grid_cell should succeed when player is inside map bounds")
	_expect(cell_result.get("cell") == model.player_spawn_cell, "get_current_grid_cell expected %s, got %s" % [model.player_spawn_cell, cell_result.get("cell")])


func _verify_movement_contract(player: Node) -> void:
	_expect(player.has_method("get_movement_velocity_for_direction"), "Player root should expose movement velocity helper for validation")

	var right_velocity: Vector2 = player.call("get_movement_velocity_for_direction", Vector2.RIGHT)
	_expect(is_equal_approx(right_velocity.length(), player.movement_speed), "Cardinal movement speed should match movement_speed")

	var diagonal_velocity: Vector2 = player.call("get_movement_velocity_for_direction", Vector2.ONE)
	_expect(is_equal_approx(diagonal_velocity.length(), player.movement_speed), "Diagonal movement should be normalized to movement_speed")

	var idle_velocity: Vector2 = player.call("get_movement_velocity_for_direction", Vector2.ZERO)
	_expect(idle_velocity == Vector2.ZERO, "Zero input should produce zero velocity")


func _verify_startup_scene(model: RefCounted) -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame

	_expect(scene.has_node("World"), "main scene should contain World branch")
	_expect(scene.has_node("World/Player"), "main scene should contain World/Player")

	var player := scene.get_node("World/Player")
	_expect(player.name == "Player", "startup player instance should be named Player")
	_expect(player is CharacterBody2D, "startup player should be CharacterBody2D")

	var expected_position_result: Dictionary = model.cell_to_world(model.player_spawn_cell)
	_expect(expected_position_result.ok, "cell_to_world should accept configured spawn cell")
	_expect(player.global_position == expected_position_result.world_position, "startup player position expected %s, got %s" % [expected_position_result.world_position, player.global_position])

	var current_cell: Dictionary = player.call("get_current_grid_cell")
	_expect(current_cell.ok, "startup player should report current grid cell")
	_expect(current_cell.get("cell") == model.player_spawn_cell, "startup player current cell expected %s, got %s" % [model.player_spawn_cell, current_cell.get("cell")])

	scene.queue_free()
	await process_frame
	await process_frame


func _verify_input_actions() -> void:
	_expect(_action_has_key("move_up", KEY_W), "move_up should be bound to W")
	_expect(_action_has_key("move_down", KEY_S), "move_down should be bound to S")
	_expect(_action_has_key("move_left", KEY_A), "move_left should be bound to A")
	_expect(_action_has_key("move_right", KEY_D), "move_right should be bound to D")


func _action_has_key(action_name: StringName, keycode: Key) -> bool:
	if not InputMap.has_action(action_name):
		return false

	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.keycode == keycode:
			return true

	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
