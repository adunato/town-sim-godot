class_name ProximityController
extends Node2D

signal proximity_changed(snapshot: Dictionary)

@export var proximity_radius := 82.0

var _player: Node
var _entity_owner: Node
var _highlight_controller: Node
var _nearby_entities: Dictionary = {}
var _last_entered_entity_ids: Array[String] = []
var _last_left_entity_ids: Array[String] = []
var _is_configured := false


func _ready() -> void:
	add_to_group("debug_proximity")
	set_physics_process(false)


func _physics_process(_delta: float) -> void:
	_update_proximity_state()


func configure(player: Node, entity_owner: Node, highlight_controller: Node, debug_overlay: Node = null) -> Dictionary:
	if player == null:
		return _failure("ProximityController requires a player.")
	if not player.has_method("get_world_position") and not player is Node2D:
		return _failure("ProximityController player must expose get_world_position or be a Node2D.")
	if entity_owner == null:
		return _failure("ProximityController requires an entity owner.")
	if highlight_controller == null:
		return _failure("ProximityController requires a highlight controller.")
	if not highlight_controller.has_method("set_highlight_input"):
		return _failure("ProximityController highlight controller must expose set_highlight_input.")
	if proximity_radius <= 0.0:
		return _failure("ProximityController proximity_radius must be greater than zero.")

	_player = player
	_entity_owner = entity_owner
	_highlight_controller = highlight_controller
	_nearby_entities.clear()
	_last_entered_entity_ids.clear()
	_last_left_entity_ids.clear()
	_is_configured = true
	set_physics_process(true)

	if debug_overlay != null and debug_overlay.has_method("set_proximity_snapshot_source"):
		debug_overlay.call("set_proximity_snapshot_source", self)

	_update_proximity_state()
	return _success()


func is_configured() -> bool:
	return _is_configured


func is_entity_nearby(entity: Node) -> bool:
	if entity == null:
		return false
	return bool(_nearby_entities.get(entity, false))


func get_proximity_snapshot() -> Dictionary:
	return {
		"proximity_radius": proximity_radius,
		"player_world_position": _get_player_world_position(),
		"nearby_entity_ids": _get_nearby_entity_ids(),
	}


func get_proximity_radius() -> float:
	return proximity_radius


func get_last_entered_entity_ids() -> Array[String]:
	return _last_entered_entity_ids.duplicate()


func get_last_left_entity_ids() -> Array[String]:
	return _last_left_entity_ids.duplicate()


func get_proximity_distance_to_rect(player_position: Vector2, entity_rect: Rect2) -> float:
	var nearest_point := Vector2(
		clampf(player_position.x, entity_rect.position.x, entity_rect.position.x + entity_rect.size.x),
		clampf(player_position.y, entity_rect.position.y, entity_rect.position.y + entity_rect.size.y)
	)
	return player_position.distance_to(nearest_point)


func force_update_for_validation() -> void:
	_update_proximity_state()


func _update_proximity_state() -> void:
	if not _is_configured:
		return

	var previous_nearby := _nearby_entities.duplicate()
	var next_nearby: Dictionary = {}
	var player_position := _get_player_world_position()
	global_position = player_position

	for entity in _get_target_entities():
		if not _entity_has_required_contract(entity):
			continue
		var proximity_target := entity.get_node_or_null("ProximityTargetComponent")
		var world_rect: Rect2 = proximity_target.call("get_proximity_rect")
		var distance := get_proximity_distance_to_rect(player_position, world_rect)
		if distance <= proximity_radius:
			next_nearby[entity] = true

	_last_entered_entity_ids.clear()
	_last_left_entity_ids.clear()

	for entity in next_nearby.keys():
		if not previous_nearby.has(entity):
			_last_entered_entity_ids.append(_get_entity_id(entity))
			_set_nearby_highlight(entity, true)

	for entity in previous_nearby.keys():
		if not next_nearby.has(entity) and is_instance_valid(entity):
			_last_left_entity_ids.append(_get_entity_id(entity))
			_set_nearby_highlight(entity, false)

	_nearby_entities = next_nearby
	if not _last_entered_entity_ids.is_empty() or not _last_left_entity_ids.is_empty():
		proximity_changed.emit(get_proximity_snapshot())


func _get_player_world_position() -> Vector2:
	if _player == null:
		return Vector2.ZERO
	if _player.has_method("get_world_position"):
		return _player.call("get_world_position")
	if _player is Node2D:
		return (_player as Node2D).global_position
	return Vector2.ZERO


func _get_target_entities() -> Array[Node]:
	if _entity_owner == null:
		return []
	if _entity_owner.has_method("get_entity_targets"):
		var owner_entities: Array[Node] = []
		for entity in _entity_owner.call("get_entity_targets"):
			if entity is Node:
				owner_entities.append(entity)
		return owner_entities

	var entities: Array[Node] = []
	for child in _entity_owner.get_children():
		if child is Node:
			entities.append(child)
	return entities


func _entity_has_required_contract(entity: Node) -> bool:
	return entity != null \
		and entity.get_node_or_null("ProximityTargetComponent") != null \
		and entity.get_node_or_null("IdentityComponent") != null


func _set_nearby_highlight(entity: Node, enabled: bool) -> void:
	if _highlight_controller == null or not is_instance_valid(_highlight_controller):
		return
	_highlight_controller.call("set_highlight_input", entity, &"nearby", enabled)


func _get_nearby_entity_ids() -> Array[String]:
	var ids: Array[String] = []
	for entity in _nearby_entities.keys():
		if is_instance_valid(entity):
			ids.append(_get_entity_id(entity))
	ids.sort()
	return ids


func _get_entity_id(entity: Node) -> String:
	if entity == null:
		return ""
	var identity := entity.get_node_or_null("IdentityComponent")
	if identity != null:
		return String(identity.call("get_entity_id"))
	return entity.name


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
