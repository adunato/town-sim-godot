class_name CapabilityResolver
extends RefCounted

const IdentityComponentScript := preload("res://scripts/entities/components/identity_component.gd")
const PickableComponentScript := preload("res://scripts/entities/components/pickable_component.gd")
const SelectableComponentScript := preload("res://scripts/entities/components/selectable_component.gd")
const HighlightableComponentScript := preload("res://scripts/entities/components/highlightable_component.gd")
const ProximityTargetComponentScript := preload("res://scripts/entities/components/proximity_target_component.gd")
const InteractableComponentScript := preload("res://scripts/entities/components/interactable_component.gd")

static func get_identity(entity: Node) -> Node:
	return _find_component(entity, IdentityComponentScript)


static func get_pickable(entity: Node) -> Node:
	return _find_component(entity, PickableComponentScript)


static func get_selectable(entity: Node) -> Node:
	return _find_component(entity, SelectableComponentScript)


static func get_highlightable(entity: Node) -> Node:
	return _find_component(entity, HighlightableComponentScript)


static func get_proximity_target(entity: Node) -> Node:
	return _find_component(entity, ProximityTargetComponentScript)


static func get_interactable(entity: Node) -> Node:
	return _find_component(entity, InteractableComponentScript)


static func _find_component(entity: Node, component_script: Script) -> Node:
	if entity == null:
		return null
	for child in entity.get_children():
		if child.get_script() == component_script:
			return child
	return null
