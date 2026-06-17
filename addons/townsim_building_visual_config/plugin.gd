@tool
extends EditorPlugin

const BuildingVisualConfigDock := preload("res://addons/townsim_building_visual_config/building_visual_config_dock.gd")

const TOOL_NAME := "TownSim Building Visual Configuration"

var _dock: Control
var _bottom_button: Button


func _enter_tree() -> void:
	_dock = BuildingVisualConfigDock.new()
	_dock.name = TOOL_NAME
	_bottom_button = add_control_to_bottom_panel(_dock, TOOL_NAME)
	add_tool_menu_item(TOOL_NAME, _show_building_visual_config)
	make_bottom_panel_item_visible(_dock)


func _exit_tree() -> void:
	remove_tool_menu_item(TOOL_NAME)
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null
	_bottom_button = null


func _show_building_visual_config() -> void:
	if _dock != null:
		make_bottom_panel_item_visible(_dock)
