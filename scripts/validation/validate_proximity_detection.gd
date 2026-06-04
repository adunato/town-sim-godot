extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const IdentityComponentScript := preload("res://scripts/entities/components/identity_component.gd")
const ProximityTargetComponentScript := preload("res://scripts/entities/components/proximity_target_component.gd")
const ProximityControllerScript := preload("res://scripts/entities/proximity_controller.gd")
const DebugOverlayScript := preload("res://scripts/debug/debug_overlay.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_proximity_detection.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	await _verify_distance_rule()
	await _verify_controller_state_and_highlight_wiring()
	await _verify_snapshot_and_debug_source()
	await _verify_main_scene_integration()
	await _verify_no_interaction_behavior()


func _verify_distance_rule() -> void:
	var controller := ProximityControllerScript.new()
	var rect := Rect2(Vector2(100, 100), Vector2(50, 40))

	_expect(controller.get_proximity_distance_to_rect(Vector2(110, 120), rect) == 0.0, "inside rectangle distance should be zero")
	_expect(controller.get_proximity_distance_to_rect(Vector2(90, 120), rect) == 10.0, "edge distance should measure to nearest rectangle side")
	_expect(is_equal_approx(controller.get_proximity_distance_to_rect(Vector2(90, 90), rect), sqrt(200.0)), "corner distance should measure to nearest rectangle corner")
	_expect(controller.get_proximity_distance_to_rect(Vector2(125, 170), rect) == 30.0, "vertical distance should measure to nearest rectangle side")


func _verify_controller_state_and_highlight_wiring() -> void:
	var player := MockPlayer.new(Vector2.ZERO)
	var buildings := MockBuildingsOwner.new()
	var highlight := MockHighlightController.new()
	var building := MockBuildingEntity.new("building.one", Rect2(Vector2(100, 100), Vector2(60, 60)))
	var controller := ProximityControllerScript.new()
	controller.proximity_radius = 25.0

	get_root().add_child(player)
	get_root().add_child(buildings)
	get_root().add_child(highlight)
	get_root().add_child(controller)
	buildings.add_building(building)
	await process_frame

	var configure_result: Dictionary = controller.configure(player, buildings, highlight)
	_expect(configure_result.ok, "ProximityController should configure with player, entity owner, and highlight controller")
	_expect(not controller.is_entity_nearby(building), "building should start outside range")
	_expect(controller.get_last_entered_entity_ids().is_empty(), "outside startup should not record an enter transition")

	player.world_position = Vector2(90, 130)
	controller.force_update_for_validation()
	_expect(controller.is_entity_nearby(building), "building should become nearby when player reaches radius")
	_expect(controller.get_last_entered_entity_ids().has("building.one"), "enter transition should name building.one")
	_expect(highlight.get_flag(building, &"nearby"), "enter transition should set nearby highlight input")

	var snapshot: Dictionary = controller.get_proximity_snapshot()
	_expect(float(snapshot.get("proximity_radius", 0.0)) == 25.0, "snapshot should include configured radius")
	_expect(snapshot.get("player_world_position", Vector2.ZERO) == Vector2(90, 130), "snapshot should include current player position")
	var nearby_ids := _string_array_from_variant(snapshot.get("nearby_entity_ids", []))
	_expect(nearby_ids == ["building.one"], "snapshot should include stable nearby building IDs")

	player.world_position = Vector2.ZERO
	controller.force_update_for_validation()
	_expect(not controller.is_entity_nearby(building), "building should leave range when player moves away")
	_expect(controller.get_last_left_entity_ids().has("building.one"), "leave transition should name building.one")
	_expect(not highlight.get_flag(building, &"nearby"), "leave transition should clear nearby highlight input")

	controller.queue_free()
	player.queue_free()
	buildings.queue_free()
	highlight.queue_free()
	await process_frame


func _verify_snapshot_and_debug_source() -> void:
	var overlay := DebugOverlayScript.new()
	var source := MockSnapshotSource.new()
	get_root().add_child(overlay)
	get_root().add_child(source)
	await process_frame

	_expect(overlay.has_method("set_proximity_snapshot_source"), "DebugOverlay should expose set_proximity_snapshot_source")
	overlay.call("set_proximity_snapshot_source", source)
	var snapshot: Dictionary = overlay.call("_read_proximity_snapshot")
	_expect(float(snapshot.get("proximity_radius", 0.0)) == 32.0, "DebugOverlay should read proximity radius from snapshot source")
	_expect(snapshot.get("player_world_position", Vector2.ZERO) == Vector2(4, 8), "DebugOverlay should read player position from snapshot source")
	_expect(_string_array_from_variant(snapshot.get("nearby_entity_ids", [])) == ["building.debug"], "DebugOverlay should read nearby entity IDs from snapshot source")

	overlay.queue_free()
	source.queue_free()
	await process_frame


func _verify_main_scene_integration() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await physics_frame

	_expect(scene.has_node("World/ProximityController"), "startup scene should contain World/ProximityController")
	if not scene.has_node("World/ProximityController"):
		scene.queue_free()
		await process_frame
		return

	var controller := scene.get_node("World/ProximityController")
	_expect(controller.has_method("is_entity_nearby"), "startup ProximityController should expose is_entity_nearby")
	_expect(controller.has_method("get_proximity_snapshot"), "startup ProximityController should expose get_proximity_snapshot")
	_expect(controller.call("is_configured"), "startup ProximityController should be configured")
	if scene.has_node("World/Buildings"):
		var buildings := scene.get_node("World/Buildings")
		var entities: Array[Node] = buildings.call("get_building_entities")
		for entity in entities:
			_expect(entity.get_node_or_null("ProximityTargetComponent") != null, "startup building should expose ProximityTargetComponent")
			_expect(entity.get_node_or_null("IdentityComponent") != null, "startup building should expose IdentityComponent for proximity IDs")

	var snapshot: Dictionary = controller.call("get_proximity_snapshot")
	_expect(float(snapshot.get("proximity_radius", 0.0)) > 0.0, "startup proximity snapshot should include positive radius")
	_expect(snapshot.has("player_world_position"), "startup proximity snapshot should include player_world_position")
	_expect(snapshot.has("nearby_entity_ids"), "startup proximity snapshot should include nearby_entity_ids")

	scene.queue_free()
	await process_frame
	await process_frame


func _verify_no_interaction_behavior() -> void:
	_expect(not InputMap.has_action("interact_entity"), "proximity feature should not add right-click interaction input")
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	_expect(not main_source.contains("_apply_interaction"), "proximity feature should not add interaction handling to main.gd")
	_expect(not main_source.contains("interaction log"), "proximity feature should not add interaction log behavior")


func _string_array_from_variant(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(String(item))
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


class MockPlayer:
	extends Node2D

	var world_position := Vector2.ZERO

	func _init(initial_position: Vector2) -> void:
		world_position = initial_position

	func get_world_position() -> Vector2:
		return world_position


class MockBuildingEntity:
	extends Node2D

	var _entity_id: String
	var _world_rect := Rect2()

	func _init(entity_id: String, world_rect: Rect2) -> void:
		_entity_id = entity_id
		_world_rect = world_rect
		var identity := IdentityComponentScript.new()
		identity.name = "IdentityComponent"
		add_child(identity)
		identity.configure(_entity_id, "building", _entity_id)
		var proximity_target := ProximityTargetComponentScript.new()
		proximity_target.name = "ProximityTargetComponent"
		add_child(proximity_target)
		proximity_target.configure(_world_rect)


class MockBuildingsOwner:
	extends Node

	var _buildings: Array[Node] = []

	func add_building(building: Node) -> void:
		_buildings.append(building)
		add_child(building)

	func get_building_entities() -> Array[Node]:
		return get_entity_targets()

	func get_entity_targets() -> Array[Node]:
		var result: Array[Node] = []
		for building in _buildings:
			if is_instance_valid(building):
				result.append(building)
		return result


class MockHighlightController:
	extends Node

	var flags: Dictionary = {}

	func set_highlight_input(building: Node, input_flag: StringName, enabled: bool) -> Dictionary:
		var building_flags: Dictionary = flags.get(building, {})
		if enabled:
			building_flags[input_flag] = true
		else:
			building_flags.erase(input_flag)
		flags[building] = building_flags
		return {"ok": true}

	func get_flag(building: Node, input_flag: StringName) -> bool:
		return bool(flags.get(building, {}).get(input_flag, false))


class MockSnapshotSource:
	extends Node

	func get_proximity_snapshot() -> Dictionary:
		return {
			"proximity_radius": 32.0,
			"player_world_position": Vector2(4, 8),
			"nearby_entity_ids": ["building.debug"],
		}
