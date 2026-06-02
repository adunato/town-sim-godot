class_name BuildingCollisionSpawner
extends Node2D

const GROUP_BUILDING_COLLISION_BODIES := "building_collision_bodies"
const WORLD_COLLISION_LAYER := 1

var _collision_bodies: Array[StaticBody2D] = []


func build_from_instances(map_model: RefCounted, registry: RefCounted, instances: Array[Dictionary]) -> Dictionary:
	clear_collision_bodies()

	if map_model == null:
		return _failure("Building collision generation requires a map model.")
	if registry == null:
		return _failure("Building collision generation requires a building data registry.")

	for instance in instances:
		var body_result := _create_body_for_instance(map_model, registry, instance)
		if not body_result.ok:
			clear_collision_bodies()
			return body_result
		_collision_bodies.append(body_result.body)

	return _success({"body_count": _collision_bodies.size()})


func clear_collision_bodies() -> void:
	for body in _collision_bodies:
		if is_instance_valid(body):
			body.queue_free()
	_collision_bodies.clear()

	for child in get_children():
		child.queue_free()


func get_collision_bodies() -> Array[StaticBody2D]:
	var bodies: Array[StaticBody2D] = []
	for body in _collision_bodies:
		if is_instance_valid(body):
			bodies.append(body)
	return bodies


func calculate_world_rect(map_model: RefCounted, instance: Dictionary, definition: Dictionary) -> Rect2:
	var origin_cell := _vector2i_from_dictionary(instance.origin_cell)
	var footprint_width := int(definition.footprint_cells.width)
	var footprint_height := int(definition.footprint_cells.height)
	var top_left: Vector2 = map_model.origin + Vector2(origin_cell) * float(map_model.cell_size)
	var size := Vector2(footprint_width, footprint_height) * float(map_model.cell_size)
	return Rect2(top_left, size)


func _create_body_for_instance(map_model: RefCounted, registry: RefCounted, instance: Dictionary) -> Dictionary:
	if not instance.has("instance_id"):
		return _failure("Building collision instance is missing required field 'instance_id'.")
	if not instance.has("definition_id"):
		return _failure("Building collision instance '%s' is missing required field 'definition_id'." % instance.get("instance_id", "<unknown>"))
	if not instance.has("origin_cell"):
		return _failure("Building collision instance '%s' is missing required field 'origin_cell'." % instance.get("instance_id", "<unknown>"))

	var definition_result: Dictionary = registry.call("get_definition", String(instance.definition_id))
	if not definition_result.ok:
		return _failure("Building collision instance '%s' references unknown definition_id '%s'." % [instance.instance_id, instance.definition_id])

	var definition: Dictionary = definition_result.definition
	var world_rect := calculate_world_rect(map_model, instance, definition)
	var body := StaticBody2D.new()
	body.name = "BuildingCollision_%s" % String(instance.instance_id)
	body.position = world_rect.get_center()
	body.collision_layer = WORLD_COLLISION_LAYER
	body.collision_mask = WORLD_COLLISION_LAYER
	body.add_to_group(GROUP_BUILDING_COLLISION_BODIES)
	body.set_meta("instance_id", String(instance.instance_id))
	body.set_meta("definition_id", String(instance.definition_id))
	body.set_meta("origin_cell", _vector2i_from_dictionary(instance.origin_cell))
	body.set_meta("footprint_width", int(definition.footprint_cells.width))
	body.set_meta("footprint_height", int(definition.footprint_cells.height))
	body.set_meta("world_rect", world_rect)

	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rectangle := RectangleShape2D.new()
	rectangle.size = world_rect.size
	shape.shape = rectangle
	body.add_child(shape)
	add_child(body)

	return _success({"body": body})


func _vector2i_from_dictionary(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.x), int(value.y))


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
