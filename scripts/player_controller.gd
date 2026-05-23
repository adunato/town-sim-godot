extends CharacterBody2D

@export var speed := 96.0

var map_loader: Node
var last_move_direction := Vector2.DOWN


func _ready() -> void:
	$Camera2D.make_current()


func setup(loader: Node) -> void:
	map_loader = loader


func _physics_process(delta: float) -> void:
	if map_loader == null or not map_loader.is_loaded:
		return

	var direction := _get_input_direction()
	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		return

	last_move_direction = direction
	var proposed_position := global_position + direction * speed * delta
	var proposed_tile: Vector2i = map_loader.world_to_tile(proposed_position)
	if map_loader.is_tile_walkable(proposed_tile):
		global_position = proposed_position
		velocity = direction * speed
	else:
		velocity = Vector2.ZERO


func get_current_tile() -> Vector2i:
	if map_loader == null:
		return Vector2i(-1, -1)
	return map_loader.world_to_tile(global_position)


func _get_input_direction() -> Vector2:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.x != 0.0:
		return Vector2(signf(direction.x), 0.0)
	if direction.y != 0.0:
		return Vector2(0.0, signf(direction.y))
	return Vector2.ZERO
