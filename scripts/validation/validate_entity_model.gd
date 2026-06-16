extends SceneTree

const BuildingDataRegistryScript := preload("res://scripts/buildings/building_data_registry.gd")
const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")
const MainScene := preload("res://scenes/main.tscn")
const MapRendererScript := preload("res://scripts/map/map_renderer.gd")
const BuildingEntitySpawnerScript := preload("res://scripts/buildings/building_entity_spawner.gd")

const RECT_TOLERANCE := 0.01
const WORLD_COLLISION_LAYER := 1

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_entity_model.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var fixture := _build_entity_fixture()
	if not fixture.ok:
		_expect(false, fixture.error)
		return

	_verify_entity_contract(fixture)
	await _verify_startup_scene()


func _build_entity_fixture() -> Dictionary:
	var model := GridMapModelScript.new()
	var map_result: Dictionary = model.load_from_file()
	if not map_result.ok:
		return _failure("prototype_map.json should load for entity validation: %s" % map_result.get("error", ""))

	var registry := BuildingDataRegistryScript.new()
	var definitions_result: Dictionary = registry.load_definitions()
	if not definitions_result.ok:
		return _failure("building definitions should load for entity validation: %s" % definitions_result.get("error", ""))
	var visual_profiles_result: Dictionary = registry.load_visual_profiles()
	if not visual_profiles_result.ok:
		return _failure("building visual profiles should load for entity validation: %s" % visual_profiles_result.get("error", ""))

	var renderer := MapRendererScript.new()
	get_root().add_child(renderer)
	renderer.set_map_model(model)
	if not renderer.get_placement_error().is_empty():
		return _failure("map renderer should generate building placement: %s" % renderer.get_placement_error())

	var spawner := BuildingEntitySpawnerScript.new()
	get_root().add_child(spawner)
	var instances := renderer.get_building_instances()
	var entity_result: Dictionary = spawner.build_from_instances(model, registry, instances)
	if not entity_result.ok:
		return _failure("building entity generation should succeed: %s" % entity_result.get("error", ""))

	return {
		"ok": true,
		"model": model,
		"registry": registry,
		"renderer": renderer,
		"spawner": spawner,
		"instances": instances,
	}


func _verify_entity_contract(fixture: Dictionary) -> void:
	var model: RefCounted = fixture.model
	var registry: RefCounted = fixture.registry
	var spawner: Node = fixture.spawner
	var instances: Array[Dictionary] = fixture.instances
	var entities: Array[Node] = spawner.call("get_building_entities")

	_expect(entities.size() == instances.size(), "expected %d building entities, got %d" % [instances.size(), entities.size()])

	var seen_ids: Dictionary = {}
	for instance in instances:
		var entity := _find_entity_for_instance(entities, String(instance.instance_id))
		_expect(entity != null, "missing building entity for instance '%s'" % instance.instance_id)
		if entity == null:
			continue

		var entity_id: String = entity.call("get_source_instance_id")
		_expect(not seen_ids.has(entity_id), "duplicate building entity id '%s'" % entity_id)
		seen_ids[entity_id] = true

		var definition_result: Dictionary = registry.call("get_definition", String(instance.definition_id))
		_expect(definition_result.ok, "definition lookup should succeed for '%s'" % instance.definition_id)
		if not definition_result.ok:
			continue

		var definition: Dictionary = definition_result.definition
		var expected_rect := _expected_world_rect(model, instance, definition)
		_verify_public_api(entity, instance, definition, expected_rect)
		_verify_capability_components(entity, instance, definition, expected_rect)
		_verify_visual(entity, definition, expected_rect)
		_verify_collision(entity, instance, definition, expected_rect)


func _verify_public_api(entity: Node, instance: Dictionary, definition: Dictionary, expected_rect: Rect2) -> void:
	_expect(entity.call("is_configured"), "building entity '%s' should be configured" % instance.instance_id)
	_expect(entity.call("get_source_instance_id") == String(instance.instance_id), "entity instance_id should match '%s'" % instance.instance_id)
	_expect(entity.call("get_building_instance_id") == String(instance.instance_id), "building instance API should match '%s'" % instance.instance_id)
	_expect(entity.call("get_entity_id") == String(instance.instance_id), "entity_id should derive from instance_id '%s'" % instance.instance_id)
	_expect(entity.call("get_definition_id") == String(instance.definition_id), "entity definition_id should match '%s'" % instance.definition_id)
	_expect(entity.call("get_entity_type") == "building", "entity_type should be building for '%s'" % instance.instance_id)
	_expect(entity.call("get_display_name") == String(definition.display_name), "display_name should match definition for '%s'" % instance.instance_id)
	_expect(entity.call("get_origin_cell") == _vector2i_from_dictionary(instance.origin_cell), "origin_cell should match source instance for '%s'" % instance.instance_id)
	_expect(entity.call("get_footprint_cells") == Vector2i(int(definition.footprint_cells.width), int(definition.footprint_cells.height)), "footprint_cells should match source definition for '%s'" % instance.instance_id)
	_expect(_rects_equal_approx(entity.call("get_world_rect"), expected_rect), "world_rect should match source data for '%s'" % instance.instance_id)
	_expect(entity.call("is_selectable") == bool(definition.selectable), "selectable flag should match definition for '%s'" % instance.instance_id)
	_expect(entity.call("is_interactable") == bool(definition.interactable), "interactable flag should match definition for '%s'" % instance.instance_id)


func _verify_capability_components(entity: Node, instance: Dictionary, definition: Dictionary, expected_rect: Rect2) -> void:
	var identity := entity.get_node_or_null("IdentityComponent")
	var pickable := entity.get_node_or_null("PickableComponent")
	var selectable := entity.get_node_or_null("SelectableComponent")
	var highlightable := entity.get_node_or_null("HighlightableComponent")
	var proximity_target := entity.get_node_or_null("ProximityTargetComponent")
	var interactable := entity.get_node_or_null("InteractableComponent")
	_expect(identity != null, "building entity '%s' should have IdentityComponent" % instance.instance_id)
	_expect(pickable != null, "building entity '%s' should have PickableComponent" % instance.instance_id)
	_expect(selectable != null, "building entity '%s' should have SelectableComponent" % instance.instance_id)
	_expect(highlightable != null, "building entity '%s' should have HighlightableComponent" % instance.instance_id)
	_expect(proximity_target != null, "building entity '%s' should have ProximityTargetComponent" % instance.instance_id)
	_expect(interactable != null, "building entity '%s' should have InteractableComponent" % instance.instance_id)
	if identity != null:
		_expect(String(identity.call("get_entity_id")) == String(instance.instance_id), "identity component entity_id should match '%s'" % instance.instance_id)
		_expect(String(identity.call("get_entity_type")) == "building", "identity component entity_type should be building for '%s'" % instance.instance_id)
		_expect(String(identity.call("get_display_name")) == String(definition.display_name), "identity component display_name should match '%s'" % instance.instance_id)
	if pickable != null:
		_expect(_rects_equal_approx(pickable.call("get_world_rect"), expected_rect), "pickable component world_rect should match '%s'" % instance.instance_id)
	if selectable != null:
		_expect(bool(selectable.call("is_selectable")) == bool(definition.selectable), "selectable component flag should match '%s'" % instance.instance_id)
	if highlightable != null:
		_expect(highlightable.call("get_resolved_highlight_state") == &"default", "highlightable component should start default for '%s'" % instance.instance_id)
	if proximity_target != null:
		_expect(_rects_equal_approx(proximity_target.call("get_proximity_rect"), expected_rect), "proximity target component rect should match '%s'" % instance.instance_id)
	if interactable != null:
		_expect(bool(interactable.call("is_interactable")) == bool(definition.interactable), "interactable component flag should match '%s'" % instance.instance_id)


func _verify_visual(entity: Node, definition: Dictionary, expected_rect: Rect2) -> void:
	var visual: Node = entity.call("get_visual_node")
	_expect(visual != null, "building entity '%s' should expose a visual node" % entity.call("get_source_instance_id"))
	if visual == null:
		return
	_expect(visual.get_parent() == entity, "building entity '%s' should own its visual node" % entity.call("get_source_instance_id"))
	_expect(_rects_equal_approx(visual.call("get_visual_rect"), expected_rect), "visual rect should match world rect for '%s'" % entity.call("get_source_instance_id"))
	_expect(entity.call("get_visual_profile_id") == String(definition.visual_profile_id), "building entity '%s' should expose the resolved visual profile id" % entity.call("get_source_instance_id"))
	_expect(visual.call("get_visual_profile_id") == String(definition.visual_profile_id), "visual node should expose visual profile id for '%s'" % entity.call("get_source_instance_id"))
	_expect(visual.call("get_sprite_node") is Sprite2D, "visual node should create a Sprite2D for '%s'" % entity.call("get_source_instance_id"))
	_expect(String(visual.call("get_texture_path")).begins_with("res://"), "visual node should retain texture path for '%s'" % entity.call("get_source_instance_id"))


func _verify_collision(entity: Node, instance: Dictionary, definition: Dictionary, expected_rect: Rect2) -> void:
	var body: StaticBody2D = entity.call("get_collision_body")
	_expect(body != null, "building entity '%s' should expose a collision body" % entity.call("get_source_instance_id"))
	if body == null:
		return
	_expect(body.get_parent() == entity, "building entity '%s' should own its collision body" % entity.call("get_source_instance_id"))
	_expect(body.get_meta("instance_id", "") == String(instance.instance_id), "collision metadata instance_id should match '%s'" % instance.instance_id)
	_expect(body.get_meta("definition_id", "") == String(instance.definition_id), "collision metadata definition_id should match '%s'" % instance.definition_id)
	_expect(body.get_meta("origin_cell", Vector2i(-1, -1)) == _vector2i_from_dictionary(instance.origin_cell), "collision metadata origin_cell should match '%s'" % instance.instance_id)
	_expect(body.get_meta("footprint_width", -1) == int(definition.footprint_cells.width), "collision metadata footprint_width should match '%s'" % instance.instance_id)
	_expect(body.get_meta("footprint_height", -1) == int(definition.footprint_cells.height), "collision metadata footprint_height should match '%s'" % instance.instance_id)
	_expect(_rects_equal_approx(body.get_meta("world_rect", Rect2()), expected_rect), "collision metadata world_rect should match '%s'" % instance.instance_id)

	var shape_nodes := _collision_shape_children(body)
	_expect(shape_nodes.size() == 1, "collision body '%s' should have exactly one CollisionShape2D" % instance.instance_id)
	if shape_nodes.size() == 1:
		var collision_shape := shape_nodes[0]
		_expect(collision_shape.shape is RectangleShape2D, "collision body '%s' should use RectangleShape2D" % instance.instance_id)
		if collision_shape.shape is RectangleShape2D:
			var rectangle := collision_shape.shape as RectangleShape2D
			_expect(_vectors_equal_approx(rectangle.size, expected_rect.size), "collision shape size for '%s' expected %s, got %s" % [instance.instance_id, expected_rect.size, rectangle.size])
			_expect(_vectors_equal_approx(body.global_position, expected_rect.get_center()), "collision body position for '%s' expected %s, got %s" % [instance.instance_id, expected_rect.get_center(), body.global_position])

	_expect(body.collision_layer == WORLD_COLLISION_LAYER, "building collision layer should use world collision layer")
	_expect(body.collision_mask == WORLD_COLLISION_LAYER, "building collision mask should use world collision layer")


func _verify_startup_scene() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await physics_frame

	_expect(scene.has_node("World/Buildings"), "startup scene should contain World/Buildings")
	_expect(not scene.has_node("World/BuildingCollisions"), "startup scene should not rely on detached World/BuildingCollisions")
	if scene.has_node("World/Buildings") and scene.has_node("World/Map"):
		var buildings := scene.get_node("World/Buildings")
		var map := scene.get_node("World/Map")
		var entities: Array[Node] = buildings.call("get_building_entities")
		var instances: Array[Dictionary] = map.call("get_building_instances")
		_expect(entities.size() == instances.size(), "startup scene should create one building entity per generated building instance")
		for entity in entities:
			_expect(entity.get_parent() == buildings, "building entity '%s' should be owned by World/Buildings" % entity.call("get_source_instance_id"))
			_expect(entity.get_node_or_null("IdentityComponent") != null, "startup building '%s' should expose identity through component" % entity.call("get_source_instance_id"))
			_expect(entity.get_node_or_null("PickableComponent") != null, "startup building '%s' should expose picking through component" % entity.call("get_source_instance_id"))
			_expect(entity.get_node_or_null("SelectableComponent") != null, "startup building '%s' should expose selection through component" % entity.call("get_source_instance_id"))
			_expect(entity.get_node_or_null("HighlightableComponent") != null, "startup building '%s' should expose highlighting through component" % entity.call("get_source_instance_id"))
			_expect(entity.get_node_or_null("ProximityTargetComponent") != null, "startup building '%s' should expose proximity through component" % entity.call("get_source_instance_id"))
			_expect(entity.get_node_or_null("InteractableComponent") != null, "startup building '%s' should expose interaction availability through component" % entity.call("get_source_instance_id"))

	scene.queue_free()
	await process_frame
	await process_frame


func _find_entity_for_instance(entities: Array[Node], instance_id: String) -> Node:
	for entity in entities:
		if entity.call("get_source_instance_id") == instance_id:
			return entity
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
