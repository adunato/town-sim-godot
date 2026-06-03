class_name DebugOverlayFixtureEntity
extends Node2D

const IdentityComponentScript := preload("res://scripts/entities/components/identity_component.gd")

var debug_footprint_cells: Array[Vector2i] = []
var proximity_radius := 0.0
var entity_id := ""
var display_name := ""
var entity_type := ""


func get_debug_footprint_cells() -> Array[Vector2i]:
	return debug_footprint_cells


func get_proximity_radius() -> float:
	return proximity_radius


func get_entity_id() -> String:
	return entity_id


func get_display_name() -> String:
	return display_name


func get_entity_type() -> String:
	return entity_type


func configure_identity(new_entity_id: String, new_display_name: String, new_entity_type: String) -> void:
	entity_id = new_entity_id
	display_name = new_display_name
	entity_type = new_entity_type
	var identity := get_node_or_null("IdentityComponent")
	if identity == null:
		identity = IdentityComponentScript.new()
		identity.name = "IdentityComponent"
		add_child(identity)
	identity.call("configure", entity_id, entity_type, display_name)
