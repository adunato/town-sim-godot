class_name PickingController
extends Node

signal hover_changed(snapshot: Dictionary)

const EMPTY_PICKING_RESULT := {
	"has_target": false,
}

var _entity_owner: Node
var _hovered_target: Node
var _hover_snapshot: Dictionary = EMPTY_PICKING_RESULT.duplicate(true)


func configure(entity_owner: Node) -> Dictionary:
	if entity_owner == null:
		return _failure("PickingController requires an entity owner.")
	_entity_owner = entity_owner
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
	for entity in _get_target_entities():
		var pickable := entity.get_node_or_null("PickableComponent")
		if pickable == null:
			continue
		if bool(pickable.call("contains_world_point", world_point)):
			matches.append(entity)
	return matches


func _get_target_entities() -> Array[Node]:
	if _entity_owner == null:
		return []
	if _entity_owner.has_method("get_entity_targets"):
		var owner_entities: Array[Node] = []
		for entity in _entity_owner.call("get_entity_targets"):
			if entity is Node:
				owner_entities.append(entity)
		return owner_entities

	var child_entities: Array[Node] = []
	for child in _entity_owner.get_children():
		if child is Node:
			child_entities.append(child)
	return child_entities


func _is_pickable_entity(entity: Node) -> bool:
	return entity != null \
		and entity.get_node_or_null("PickableComponent") != null \
		and entity.get_node_or_null("IdentityComponent") != null


func _compare_pickable_entities(first: Node, second: Node) -> bool:
	var first_index := first.get_index() if first != null else -1
	var second_index := second.get_index() if second != null else -1
	if first_index != second_index:
		return first_index < second_index
	return _get_entity_id(first) < _get_entity_id(second)


func _build_picking_result(target: Node) -> Dictionary:
	if target == null:
		return EMPTY_PICKING_RESULT.duplicate(true)

	var identity := target.get_node_or_null("IdentityComponent")
	var pickable := target.get_node_or_null("PickableComponent")
	var selectable := target.get_node_or_null("SelectableComponent")
	var interactable := target.get_node_or_null("InteractableComponent")
	if identity == null or pickable == null:
		return EMPTY_PICKING_RESULT.duplicate(true)

	return {
		"has_target": true,
		"target": target,
		"entity_id": String(identity.call("get_entity_id")),
		"entity_type": String(identity.call("get_entity_type")),
		"display_name": String(identity.call("get_display_name")),
		"selectable": selectable != null and bool(selectable.call("is_selectable")),
		"interactable": interactable != null and bool(interactable.call("is_interactable")),
		"world_rect": pickable.call("get_world_rect"),
	}


func _refresh_hovered_target() -> void:
	if _hovered_target == null:
		return
	if not is_instance_valid(_hovered_target) or not _hovered_target.is_inside_tree() or not _is_pickable_entity(_hovered_target):
		clear_hover()


func _get_entity_id(entity: Node) -> String:
	var identity := entity.get_node_or_null("IdentityComponent")
	if identity == null:
		return ""
	return String(identity.call("get_entity_id"))


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
