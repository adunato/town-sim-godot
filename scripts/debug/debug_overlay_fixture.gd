extends Node

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")
const FixtureEntityScript := preload("res://scripts/debug/debug_overlay_fixture_entity.gd")

@onready var _debug_overlay := $World/DebugOverlay
@onready var _debug_readout := $UI/DebugReadout
@onready var _fixture_nodes := $World/FixtureNodes

var _map_model: RefCounted


func _ready() -> void:
	_map_model = GridMapModelScript.new()
	var load_result: Dictionary = _map_model.load_from_file()
	if not load_result.ok:
		push_error(load_result.error)
		return

	_add_cell_state_fixtures()
	_add_building_fixture()
	_add_player_fixture()
	_add_entity_fixtures()

	_debug_overlay.set_map_model(_map_model)
	_debug_readout.set_seed(_map_model.seed)
	_debug_overlay.debug_state_changed.connect(_debug_readout.set_overlay_state)
	_debug_overlay.toggle_overlay()
	_debug_readout.set_overlay_state(_debug_overlay.is_overlay_enabled(), _debug_overlay.current_mode, _debug_overlay.get_legend_entries())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay") or _is_key_pressed(event, KEY_F3):
		_debug_overlay.toggle_overlay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_debug_overlay") or _is_key_pressed(event, KEY_F4):
		_debug_overlay.cycle_mode()
		get_viewport().set_input_as_handled()


func _add_cell_state_fixtures() -> void:
	_map_model.reserve_rect(Vector2i(4, 2), Vector2i.ONE, "blocked")
	_map_model.reserve_rect(Vector2i(6, 6), Vector2i(2, 2), "occupied")
	_map_model.reserve_rect(Vector2i(9, 2), Vector2i.ONE, "reserved")
	_map_model.reserve_rect(Vector2i(10, 2), Vector2i.ONE, "protected", true)


func _add_building_fixture() -> void:
	var building := _new_fixture_entity("MockBuilding", _cell_center(Vector2i(6, 6)))
	var footprint_cells: Array[Vector2i] = [Vector2i(6, 6), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7)]
	building.debug_footprint_cells = footprint_cells
	building.entity_id = "building.mock-shop"
	building.display_name = "Mock Shop"
	building.entity_type = "building"
	building.add_to_group("debug_building_footprints")
	building.add_to_group("debug_building_collision")
	building.add_to_group("debug_entity_labels")

	var static_body := StaticBody2D.new()
	static_body.name = "CollisionBody"
	building.add_child(static_body)

	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64.0, 64.0)
	collision.shape = shape
	static_body.add_child(collision)


func _add_player_fixture() -> void:
	var player := _new_fixture_entity("MockPlayer", _cell_center(Vector2i(3, 5)))
	player.proximity_radius = 82.0
	player.entity_id = "player.fixture"
	player.display_name = "Fixture Player"
	player.entity_type = "player"
	player.add_to_group("debug_player_collision")
	player.add_to_group("debug_proximity")
	player.add_to_group("debug_entity_labels")

	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape"
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	collision.shape = shape
	player.add_child(collision)


func _add_entity_fixtures() -> void:
	var hovered := _new_fixture_entity("MockHoveredEntity", _cell_center(Vector2i(13, 4)))
	hovered.entity_id = "npc.hovered"
	hovered.display_name = "Hovered NPC"
	hovered.entity_type = "npc"
	hovered.add_to_group("debug_hovered_target")
	hovered.add_to_group("debug_entity_labels")

	var selected := _new_fixture_entity("MockSelectedEntity", _cell_center(Vector2i(17, 8)))
	selected.entity_id = "npc.selected"
	selected.display_name = "Selected NPC"
	selected.entity_type = "npc"
	selected.add_to_group("debug_selected_target")
	selected.add_to_group("debug_entity_labels")


func _new_fixture_entity(node_name: String, world_position: Vector2) -> Node2D:
	var entity = FixtureEntityScript.new()
	entity.name = node_name
	entity.global_position = world_position
	_fixture_nodes.add_child(entity)
	return entity


func _cell_center(cell: Vector2i) -> Vector2:
	return _map_model.origin + (Vector2(cell) + Vector2(0.5, 0.5)) * float(_map_model.cell_size)


func _is_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode
