class_name BuildingEntity
extends Node2D

const GROUP_BUILDING_ENTITIES := "building_entities"
const GROUP_BUILDING_COLLISION_BODIES := "building_collision_bodies"
const WORLD_COLLISION_LAYER := 1

var _visual: Node2D
var _collision_body: StaticBody2D
var _collision_shape: CollisionShape2D

var _instance: Dictionary = {}
var _definition: Dictionary = {}
var _origin_cell := Vector2i.ZERO
var _footprint_cells := Vector2i.ZERO
var _world_rect := Rect2()
var _is_configured := false


func configure(map_model: RefCounted, instance: Dictionary, definition: Dictionary) -> Dictionary:
	_bind_child_nodes()
	var validation := _validate_inputs(map_model, instance, definition)
	if not validation.ok:
		return validation

	_instance = instance.duplicate(true)
	_definition = definition.duplicate(true)
	_origin_cell = _vector2i_from_dictionary(instance.origin_cell)
	_footprint_cells = Vector2i(int(definition.footprint_cells.width), int(definition.footprint_cells.height))
	var rect_size := Vector2(_footprint_cells) * float(map_model.cell_size)
	var top_left: Vector2 = map_model.origin + Vector2(_origin_cell) * float(map_model.cell_size)
	_world_rect = Rect2(top_left, rect_size)
	global_position = top_left
	name = "BuildingEntity_%s" % get_source_instance_id()

	_visual.configure(rect_size, Color(String(definition.prototype_color)))
	_configure_collision(rect_size)
	_configure_debug_groups()
	_is_configured = true

	return _success()


func _bind_child_nodes() -> void:
	_visual = get_node("Visual") as Node2D
	_collision_body = get_node("CollisionBody") as StaticBody2D
	_collision_shape = get_node("CollisionBody/CollisionShape2D") as CollisionShape2D


func is_configured() -> bool:
	return _is_configured


func get_source_instance_id() -> String:
	return String(_instance.get("instance_id", ""))


func get_building_instance_id() -> String:
	return get_source_instance_id()


func get_entity_id() -> String:
	return get_source_instance_id()


func get_definition_id() -> String:
	return String(_instance.get("definition_id", ""))


func get_entity_type() -> String:
	return "building"


func get_display_name() -> String:
	return String(_definition.get("display_name", ""))


func get_origin_cell() -> Vector2i:
	return _origin_cell


func get_footprint_cells() -> Vector2i:
	return _footprint_cells


func get_world_rect() -> Rect2:
	return Rect2(global_position, _world_rect.size)


func is_selectable() -> bool:
	return bool(_definition.get("selectable", false))


func is_interactable() -> bool:
	return bool(_definition.get("interactable", false))


func get_collision_body() -> StaticBody2D:
	return _collision_body


func get_visual_node() -> Node2D:
	return _visual


func get_debug_footprint_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(_origin_cell.y, _origin_cell.y + _footprint_cells.y):
		for x in range(_origin_cell.x, _origin_cell.x + _footprint_cells.x):
			cells.append(Vector2i(x, y))
	return cells


func _configure_collision(rect_size: Vector2) -> void:
	_collision_body.name = "CollisionBody"
	_collision_body.position = rect_size * 0.5
	_collision_body.collision_layer = WORLD_COLLISION_LAYER
	_collision_body.collision_mask = WORLD_COLLISION_LAYER
	_collision_body.add_to_group(GROUP_BUILDING_COLLISION_BODIES)
	_collision_body.set_meta("instance_id", get_source_instance_id())
	_collision_body.set_meta("definition_id", get_definition_id())
	_collision_body.set_meta("origin_cell", _origin_cell)
	_collision_body.set_meta("footprint_width", _footprint_cells.x)
	_collision_body.set_meta("footprint_height", _footprint_cells.y)
	_collision_body.set_meta("world_rect", get_world_rect())

	var rectangle := RectangleShape2D.new()
	rectangle.size = rect_size
	_collision_shape.shape = rectangle


func _configure_debug_groups() -> void:
	add_to_group(GROUP_BUILDING_ENTITIES)
	add_to_group("debug_building_footprints")
	add_to_group("debug_entity_labels")
	_collision_body.add_to_group("debug_building_collision")


func _validate_inputs(map_model: RefCounted, instance: Dictionary, definition: Dictionary) -> Dictionary:
	if map_model == null:
		return _failure("BuildingEntity requires a map model.")
	for field in ["instance_id", "definition_id", "origin_cell"]:
		if not instance.has(field):
			return _failure("BuildingEntity source instance is missing required field '%s'." % field)
	for field in ["id", "display_name", "footprint_cells", "prototype_color", "selectable", "interactable"]:
		if not definition.has(field):
			return _failure("BuildingEntity source definition is missing required field '%s'." % field)
	if String(instance.definition_id) != String(definition.id):
		return _failure("BuildingEntity instance '%s' references definition '%s' but received definition '%s'." % [instance.instance_id, instance.definition_id, definition.id])
	if not _is_vector2i_dictionary(instance.origin_cell):
		return _failure("BuildingEntity instance '%s' origin_cell must contain integer x and y fields." % instance.instance_id)
	if not _is_footprint_dictionary(definition.footprint_cells):
		return _failure("BuildingEntity definition '%s' footprint_cells must contain positive integer width and height fields." % definition.id)
	return _success()


func _vector2i_from_dictionary(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.x), int(value.y))


func _is_vector2i_dictionary(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	return value.has("x") and value.has("y") and _is_integer_number(value.x) and _is_integer_number(value.y)


func _is_footprint_dictionary(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	return value.has("width") and value.has("height") \
		and _is_integer_number(value.width) \
		and _is_integer_number(value.height) \
		and int(value.width) > 0 \
		and int(value.height) > 0


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	return is_equal_approx(float(value), float(int(value)))


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
