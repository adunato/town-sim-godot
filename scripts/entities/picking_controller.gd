class_name PickingController
extends Node

signal hover_changed(snapshot: Dictionary)

const EMPTY_PICKING_RESULT := {
	"has_target": false,
}

var _buildings_owner: Node
var _hovered_target: Node
var _hover_snapshot: Dictionary = EMPTY_PICKING_RESULT.duplicate(true)


func configure(buildings_owner: Node) -> Dictionary:
	if buildings_owner == null:
		return _failure("PickingController requires a buildings owner.")
	_buildings_owner = buildings_owner
	clear_hover()
	return _success()


func pick_at_screen_position(screen_position: Vector2) -> Dictionary:
	return pick_at_world_point(screen_to_world_position(screen_position))


func pick_at_world_point(world_point: Vector2) -> Dictionary:
	var candidates := _pickable_entities_containing(world_point)
	if candidates.is_empty():
		return EMPTY_PICKING_RESULT.duplicate(true)

	candidates.sort_custom(_compare_pickable_entities)
	return _build_picking_result(candidates[candidates.size() - 1])


func screen_to_world_position(screen_position: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return screen_position
	return viewport.get_canvas_transform().affine_inverse() * screen_position


func update_hover_at_screen_position(screen_position: Vector2) -> Dictionary:
	return update_hover_from_result(pick_at_screen_position(screen_position))


func update_hover_from_result(picking_result: Dictionary) -> Dictionary:
	var next_target: Node = null
	if bool(picking_result.get("has_target", false)):
		next_target = picking_result.get("target", null) as Node

	if next_target == _hovered_target:
		return _success({"changed": false})

	_disconnect_hovered_target()
	_hovered_target = next_target
	if _hovered_target != null and not _hovered_target.tree_exiting.is_connected(_on_hovered_target_tree_exiting):
		_hovered_target.tree_exiting.connect(_on_hovered_target_tree_exiting)

	_hover_snapshot = _build_picking_result(_hovered_target) if _hovered_target != null else EMPTY_PICKING_RESULT.duplicate(true)
	hover_changed.emit(_hover_snapshot.duplicate(true))
	return _success({"changed": true})


func clear_hover() -> bool:
	if _hovered_target == null and not bool(_hover_snapshot.get("has_target", false)):
		return false
	_disconnect_hovered_target()
	_hovered_target = null
	_hover_snapshot = EMPTY_PICKING_RESULT.duplicate(true)
	hover_changed.emit(_hover_snapshot.duplicate(true))
	return true


func get_hovered_target() -> Node:
	_refresh_hovered_target()
	return _hovered_target


func get_hover_snapshot() -> Dictionary:
	_refresh_hovered_target()
	return _hover_snapshot.duplicate(true)


func _pickable_entities_containing(world_point: Vector2) -> Array[Node]:
	var matches: Array[Node] = []
	for entity in _get_building_entities():
		if not _is_pickable_building_entity(entity):
			continue
		var world_rect: Rect2 = entity.call("get_world_rect")
		if world_rect.has_point(world_point):
			matches.append(entity)
	return matches


func _get_building_entities() -> Array[Node]:
	if _buildings_owner == null:
		return []
	if _buildings_owner.has_method("get_building_entities"):
		var owner_entities: Array[Node] = []
		for entity in _buildings_owner.call("get_building_entities"):
			if entity is Node:
				owner_entities.append(entity)
		return owner_entities

	var child_entities: Array[Node] = []
	for child in _buildings_owner.get_children():
		if child is Node:
			child_entities.append(child)
	return child_entities


func _is_pickable_building_entity(entity: Node) -> bool:
	return entity != null \
		and entity.has_method("get_world_rect") \
		and entity.has_method("get_entity_id") \
		and entity.has_method("get_entity_type") \
		and entity.has_method("get_display_name") \
		and entity.has_method("is_selectable") \
		and entity.has_method("is_interactable")


func _compare_pickable_entities(first: Node, second: Node) -> bool:
	var first_index := first.get_index() if first != null else -1
	var second_index := second.get_index() if second != null else -1
	if first_index != second_index:
		return first_index < second_index
	return String(first.call("get_entity_id")) < String(second.call("get_entity_id"))


func _build_picking_result(target: Node) -> Dictionary:
	if target == null:
		return EMPTY_PICKING_RESULT.duplicate(true)

	return {
		"has_target": true,
		"target": target,
		"entity_id": String(target.call("get_entity_id")),
		"entity_type": String(target.call("get_entity_type")),
		"display_name": String(target.call("get_display_name")),
		"selectable": bool(target.call("is_selectable")),
		"interactable": bool(target.call("is_interactable")),
		"world_rect": target.call("get_world_rect"),
	}


func _refresh_hovered_target() -> void:
	if _hovered_target == null:
		return
	if not is_instance_valid(_hovered_target) or not _hovered_target.is_inside_tree() or not _is_pickable_building_entity(_hovered_target):
		clear_hover()


func _disconnect_hovered_target() -> void:
	if _hovered_target != null and is_instance_valid(_hovered_target):
		if _hovered_target.tree_exiting.is_connected(_on_hovered_target_tree_exiting):
			_hovered_target.tree_exiting.disconnect(_on_hovered_target_tree_exiting)


func _on_hovered_target_tree_exiting() -> void:
	clear_hover()


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
