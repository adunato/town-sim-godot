class_name BuildingEntitySpawner
extends Node2D

const BuildingEntityScene := preload("res://scenes/buildings/building_entity.tscn")

var _building_entities: Array[Node] = []


func build_from_instances(map_model: RefCounted, registry: RefCounted, instances: Array[Dictionary]) -> Dictionary:
	clear_building_entities()

	if map_model == null:
		return _failure("Building entity generation requires a map model.")
	if registry == null:
		return _failure("Building entity generation requires a building data registry.")

	var seen_ids: Dictionary = {}
	for instance in instances:
		if not instance.has("instance_id"):
			clear_building_entities()
			return _failure("Building entity source instance is missing required field 'instance_id'.")

		var instance_id := String(instance.instance_id)
		if seen_ids.has(instance_id):
			clear_building_entities()
			return _failure("Building entity source instance id '%s' is duplicated." % instance_id)
		seen_ids[instance_id] = true

		var entity_result := _create_entity_for_instance(map_model, registry, instance)
		if not entity_result.ok:
			clear_building_entities()
			return entity_result
		_building_entities.append(entity_result.entity)

	return _success({"entity_count": _building_entities.size()})


func clear_building_entities() -> void:
	for entity in _building_entities:
		if is_instance_valid(entity):
			entity.queue_free()
	_building_entities.clear()

	for child in get_children():
		child.queue_free()


func get_building_entities() -> Array[Node]:
	var entities: Array[Node] = []
	for entity in _building_entities:
		if is_instance_valid(entity):
			entities.append(entity)
	return entities


func get_collision_bodies() -> Array[StaticBody2D]:
	var bodies: Array[StaticBody2D] = []
	for entity in get_building_entities():
		bodies.append(entity.get_collision_body())
	return bodies


func _create_entity_for_instance(map_model: RefCounted, registry: RefCounted, instance: Dictionary) -> Dictionary:
	if not instance.has("definition_id"):
		return _failure("Building entity instance '%s' is missing required field 'definition_id'." % instance.get("instance_id", "<unknown>"))

	var resolved_result: Dictionary = registry.call("resolve_instance_visual_profile", instance)
	if not resolved_result.ok:
		return _failure("Building entity instance '%s' could not resolve building visual data: %s" % [instance.get("instance_id", "<unknown>"), resolved_result.error])

	var entity := BuildingEntityScene.instantiate()
	if entity == null:
		return _failure("Unable to instantiate BuildingEntity scene.")

	add_child(entity)
	var configure_result: Dictionary = entity.configure(map_model, instance, resolved_result.definition, resolved_result.visual_profile)
	if not configure_result.ok:
		entity.queue_free()
		return configure_result

	return _success({"entity": entity})


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
