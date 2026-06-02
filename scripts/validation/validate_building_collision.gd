extends SceneTree

const BuildingCollisionSpawnerScript := preload("res://scripts/buildings/building_collision_spawner.gd")
const BuildingDataRegistryScript := preload("res://scripts/buildings/building_data_registry.gd")
const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")
const MainScene := preload("res://scenes/main.tscn")
const MapRendererScript := preload("res://scripts/map/map_renderer.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")

const RECT_TOLERANCE := 0.01
const BLOCKING_PROBE_FRAMES := 90
const SLIDING_PROBE_FRAMES := 18

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_building_collision.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var fixture := _build_collision_fixture()
	if not fixture.ok:
		_expect(false, fixture.error)
		return

	_verify_collision_contract(fixture)
	await _verify_startup_scene()
	await _verify_player_blocking_probe(fixture)
	await _verify_player_sliding_probe(fixture)


func _build_collision_fixture() -> Dictionary:
	var model := GridMapModelScript.new()
	var map_result: Dictionary = model.load_from_file()
	if not map_result.ok:
		return _failure("prototype_map.json should load for building collision validation: %s" % map_result.get("error", ""))

	var registry := BuildingDataRegistryScript.new()
	var definitions_result: Dictionary = registry.load_definitions()
	if not definitions_result.ok:
		return _failure("building definitions should load for building collision validation: %s" % definitions_result.get("error", ""))

	var renderer := MapRendererScript.new()
	get_root().add_child(renderer)
	renderer.set_map_model(model)
	if not renderer.get_placement_error().is_empty():
		return _failure("map renderer should generate building placement: %s" % renderer.get_placement_error())

	var spawner := BuildingCollisionSpawnerScript.new()
	get_root().add_child(spawner)
	var instances := renderer.get_building_instances()
	var collision_result: Dictionary = spawner.build_from_instances(model, registry, instances)
	if not collision_result.ok:
		return _failure("building collision generation should succeed: %s" % collision_result.get("error", ""))

	return {
		"ok": true,
		"model": model,
		"registry": registry,
		"renderer": renderer,
		"spawner": spawner,
		"instances": instances,
	}


func _verify_collision_contract(fixture: Dictionary) -> void:
	var model: RefCounted = fixture.model
	var registry: RefCounted = fixture.registry
	var spawner: Node = fixture.spawner
	var instances: Array[Dictionary] = fixture.instances
	var bodies: Array[StaticBody2D] = spawner.call("get_collision_bodies")

	_expect(bodies.size() == instances.size(), "expected %d building collision bodies, got %d" % [instances.size(), bodies.size()])

	for instance in instances:
		var body := _find_body_for_instance(bodies, String(instance.instance_id))
		_expect(body != null, "missing building collision body for instance '%s'" % instance.instance_id)
		if body == null:
			continue

		var shape_nodes := _collision_shape_children(body)
		_expect(shape_nodes.size() == 1, "building collision body '%s' should have exactly one CollisionShape2D" % instance.instance_id)
		if shape_nodes.size() != 1:
			continue

		var collision_shape := shape_nodes[0]
		_expect(collision_shape.shape is RectangleShape2D, "building collision body '%s' should use RectangleShape2D" % instance.instance_id)

		var definition_result: Dictionary = registry.call("get_definition", String(instance.definition_id))
		_expect(definition_result.ok, "definition lookup should succeed for '%s'" % instance.definition_id)
		if not definition_result.ok:
			continue

		var expected_rect := _expected_world_rect(model, instance, definition_result.definition)
		_verify_metadata(body, instance, definition_result.definition, expected_rect)
		_verify_shape_alignment(body, collision_shape, expected_rect)
		_verify_layer_mask(body)


func _verify_metadata(body: StaticBody2D, instance: Dictionary, definition: Dictionary, expected_rect: Rect2) -> void:
	_expect(body.get_meta("instance_id", "") == String(instance.instance_id), "body metadata instance_id should match '%s'" % instance.instance_id)
	_expect(body.get_meta("definition_id", "") == String(instance.definition_id), "body metadata definition_id should match '%s'" % instance.definition_id)
	_expect(body.get_meta("origin_cell", Vector2i(-1, -1)) == _vector2i_from_dictionary(instance.origin_cell), "body metadata origin_cell should match '%s'" % instance.instance_id)
	_expect(body.get_meta("footprint_width", -1) == int(definition.footprint_cells.width), "body metadata footprint_width should match '%s'" % instance.instance_id)
	_expect(body.get_meta("footprint_height", -1) == int(definition.footprint_cells.height), "body metadata footprint_height should match '%s'" % instance.instance_id)
	_expect(_rects_equal_approx(body.get_meta("world_rect", Rect2()), expected_rect), "body metadata world_rect should match '%s'" % instance.instance_id)


func _verify_shape_alignment(body: StaticBody2D, collision_shape: CollisionShape2D, expected_rect: Rect2) -> void:
	var rectangle := collision_shape.shape as RectangleShape2D
	_expect(_vectors_equal_approx(rectangle.size, expected_rect.size), "collision shape size for '%s' expected %s, got %s" % [body.get_meta("instance_id"), expected_rect.size, rectangle.size])
	_expect(_vectors_equal_approx(body.global_position, expected_rect.get_center()), "collision body position for '%s' expected %s, got %s" % [body.get_meta("instance_id"), expected_rect.get_center(), body.global_position])


func _verify_layer_mask(body: StaticBody2D) -> void:
	var player := PlayerScene.instantiate()
	_expect((body.collision_layer & player.collision_mask) != 0, "building layer should intersect player mask")
	_expect((player.collision_layer & body.collision_mask) != 0, "player layer should intersect building mask")
	player.queue_free()


func _verify_startup_scene() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await physics_frame

	_expect(scene.has_node("World/BuildingCollisions"), "startup scene should contain World/BuildingCollisions")
	if scene.has_node("World/BuildingCollisions") and scene.has_node("World/Map"):
		var collisions := scene.get_node("World/BuildingCollisions")
		var map := scene.get_node("World/Map")
		var bodies: Array[StaticBody2D] = collisions.call("get_collision_bodies")
		var instances: Array[Dictionary] = map.call("get_building_instances")
		_expect(bodies.size() == instances.size(), "startup scene should create one collision body per generated building instance")

	scene.queue_free()
	await process_frame
	await process_frame


func _verify_player_blocking_probe(fixture: Dictionary) -> void:
	var body: StaticBody2D = fixture.spawner.call("get_collision_bodies")[0]
	var rect: Rect2 = body.get_meta("world_rect")
	var player := PlayerScene.instantiate()
	get_root().add_child(player)
	player.global_position = Vector2(rect.position.x - player.visual_radius - 6.0, rect.get_center().y)

	for _index in range(BLOCKING_PROBE_FRAMES):
		player.velocity = Vector2.RIGHT * player.movement_speed
		player.move_and_slide()
		await physics_frame

	var player_edge: float = player.global_position.x + player.visual_radius
	_expect(player_edge <= rect.position.x + RECT_TOLERANCE, "player blocking probe crossed building edge: player edge %f, building edge %f" % [player_edge, rect.position.x])
	player.queue_free()
	await process_frame


func _verify_player_sliding_probe(fixture: Dictionary) -> void:
	var body: StaticBody2D = fixture.spawner.call("get_collision_bodies")[0]
	var rect: Rect2 = body.get_meta("world_rect")
	var player := PlayerScene.instantiate()
	get_root().add_child(player)
	player.global_position = Vector2(rect.position.x - player.visual_radius - 6.0, rect.position.y + player.visual_radius + 4.0)
	var start_y: float = player.global_position.y

	for _index in range(SLIDING_PROBE_FRAMES):
		player.velocity = Vector2(1.0, 1.0).normalized() * player.movement_speed
		player.move_and_slide()
		await physics_frame

	var player_edge: float = player.global_position.x + player.visual_radius
	_expect(player_edge <= rect.position.x + RECT_TOLERANCE, "player sliding probe crossed building edge: player edge %f, building edge %f" % [player_edge, rect.position.x])
	_expect(player.global_position.y > start_y + 1.0, "player sliding probe should retain downward movement along building edge")
	player.queue_free()
	await process_frame


func _find_body_for_instance(bodies: Array[StaticBody2D], instance_id: String) -> StaticBody2D:
	for body in bodies:
		if body.get_meta("instance_id", "") == instance_id:
			return body
	return null


func _collision_shape_children(body: StaticBody2D) -> Array[CollisionShape2D]:
	var shapes: Array[CollisionShape2D] = []
	for child in body.get_children():
		if child is CollisionShape2D:
			shapes.append(child)
	return shapes


func _expected_world_rect(model: RefCounted, instance: Dictionary, definition: Dictionary) -> Rect2:
	var origin_cell := _vector2i_from_dictionary(instance.origin_cell)
	var size := Vector2(int(definition.footprint_cells.width), int(definition.footprint_cells.height)) * float(model.cell_size)
	return Rect2(model.origin + Vector2(origin_cell) * float(model.cell_size), size)


func _vector2i_from_dictionary(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.x), int(value.y))


func _rects_equal_approx(first: Rect2, second: Rect2) -> bool:
	return _vectors_equal_approx(first.position, second.position) and _vectors_equal_approx(first.size, second.size)


func _vectors_equal_approx(first: Vector2, second: Vector2) -> bool:
	return first.distance_to(second) <= RECT_TOLERANCE


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
