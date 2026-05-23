extends Node2D

const PlayerScene := preload("res://scenes/Player.tscn")

@onready var map_loader: Node = $MapLoader
@onready var debug_overlay: Node2D = $DebugOverlay

var player


func _ready() -> void:
	if map_loader.is_loaded:
		_spawn_player()
	else:
		map_loader.map_loaded.connect(_spawn_player, CONNECT_ONE_SHOT)


func _spawn_player() -> void:
	player = PlayerScene.instantiate()
	player.name = "Player"
	add_child(player)
	player.global_position = map_loader.get_player_spawn_world()
	player.setup(map_loader)
	debug_overlay.setup(map_loader, player)
