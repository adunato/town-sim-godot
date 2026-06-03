class_name ProximityController
extends Node2D

signal proximity_changed(snapshot: Dictionary)

const CapabilityResolverScript := preload("res://scripts/entities/capability_resolver.gd")

@export var proximity_radius := 82.0

var _player: Node
var _buildings_owner: Node
var _highlight_controller: Node
var _nearby_buildings: Dictionary = {}
var _last_entered_entity_ids: Array[String] = []
var _last_left_entity_ids: Array[String] = []
var _is_configured := false


func _ready() -> void:
	add_to_group("debug_proximity")
	set_physics_process(false)


func _physics_process(_delta: float) -> void:
	_update_proximity_state()


func configure(player: Node, buildings_owner: Node, highlight_controller: Node, debug_overlay: Node = null) -> Dictionary:
	if player == null:
		return _failure("ProximityController requires a player.")
	if not player.has_method("get_world_position") and not player is Node2D:
		return _failure("ProximityController player must expose get_world_position or be a Node2D.")
	if buildings_owner == null:
		return _failure("ProximityController requires a buildings owner.")
	if not buildings_owner.has_method("get_building_entities"):
		return _failure("ProximityController buildings owner must expose get_building_entities.")
	if highlight_controller == null:
		return _failure("ProximityController requires a highlight controller.")
	if not highlight_controller.has_method("set_highlight_input"):
		return _failure("ProximityController highlight controller must expose set_highlight_input.")
	if proximity_radius <= 0.0:
		return _failure("ProximityController proximity_radius must be greater than zero.")

	_player = player
	_buildings_owner = buildings_owner
	_highlight_controller = highlight_controller
	_nearby_buildings.clear()
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


func is_entity_nearby(building: Node) -> bool:
	if building == null:
		return false
	return bool(_nearby_buildings.get(building, false))


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


func get_proximity_distance_to_rect(player_position: Vector2, building_rect: Rect2) -> float:
	var nearest_point := Vector2(
		clampf(player_position.x, building_rect.position.x, building_rect.position.x + building_rect.size.x),
		clampf(player_position.y, building_rect.position.y, building_rect.position.y + building_rect.size.y)
	)
	return player_position.distance_to(nearest_point)


func force_update_for_validation() -> void:
	_update_proximity_state()


func _update_proximity_state() -> void:
	if not _is_configured:
		return

	var previous_nearby := _nearby_buildings.duplicate()
	var next_nearby: Dictionary = {}
	var player_position := _get_player_world_position()
	global_position = player_position

	for building in _get_building_entities():
		if not _building_has_required_contract(building):
			continue
		var proximity_target := CapabilityResolverScript.get_proximity_target(building)
		var world_rect: Rect2 = proximity_target.call("get_proximity_rect")
		var distance := get_proximity_distance_to_rect(player_position, world_rect)
		if distance <= proximity_radius:
			next_nearby[building] = true

	_last_entered_entity_ids.clear()
	_last_left_entity_ids.clear()

	for building in next_nearby.keys():
		if not previous_nearby.has(building):
			_last_entered_entity_ids.append(_get_entity_id(building))
			_set_nearby_highlight(building, true)

	for building in previous_nearby.keys():
		if not next_nearby.has(building) and is_instance_valid(building):
			_last_left_entity_ids.append(_get_entity_id(building))
			_set_nearby_highlight(building, false)

	_nearby_buildings = next_nearby
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


func _get_building_entities() -> Array[Node]:
	if _buildings_owner == null:
		return []
	var entities: Array[Node] = []
	for entity in _buildings_owner.call("get_building_entities"):
		if entity is Node:
			entities.append(entity)
	return entities


func _building_has_required_contract(building: Node) -> bool:
	return building != null \
		and CapabilityResolverScript.get_proximity_target(building) != null \
		and CapabilityResolverScript.get_identity(building) != null


func _set_nearby_highlight(building: Node, enabled: bool) -> void:
	if _highlight_controller == null or not is_instance_valid(_highlight_controller):
		return
	_highlight_controller.call("set_highlight_input", building, &"nearby", enabled)


func _get_nearby_entity_ids() -> Array[String]:
	var ids: Array[String] = []
	for building in _nearby_buildings.keys():
		if is_instance_valid(building):
			ids.append(_get_entity_id(building))
	ids.sort()
	return ids


func _get_entity_id(building: Node) -> String:
	var identity := CapabilityResolverScript.get_identity(building)
	if identity != null:
		return String(identity.call("get_entity_id"))
	if building != null:
		return building.name
	return ""


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
