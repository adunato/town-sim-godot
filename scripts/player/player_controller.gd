class_name PlayerController
extends CharacterBody2D

const NO_MAP_MODEL_ERROR := "PlayerController has no map model assigned."

@export var movement_speed := 160.0
@export var visual_radius := 12.0
@export var visual_color := Color(0.12, 0.32, 0.82, 1.0)

var _map_model: RefCounted


func _ready() -> void:
	queue_redraw()


func _physics_process(_delta: float) -> void:
	velocity = get_movement_velocity_for_direction(get_input_direction())
	move_and_slide()


func _draw() -> void:
	draw_circle(Vector2.ZERO, visual_radius, visual_color)


func set_map_model(map_model: RefCounted) -> void:
	_map_model = map_model


func get_world_position() -> Vector2:
	return global_position


func get_current_grid_cell() -> Dictionary:
	if _map_model == null:
		return {
			"ok": false,
			"error": NO_MAP_MODEL_ERROR,
		}

	return _map_model.world_to_cell(global_position)


func get_input_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func get_movement_velocity_for_direction(direction: Vector2) -> Vector2:
	if direction.length() > 1.0:
		direction = direction.normalized()

	return direction * movement_speed
