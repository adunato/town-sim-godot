class_name DebugOverlayFixtureEntity
extends Node2D

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
