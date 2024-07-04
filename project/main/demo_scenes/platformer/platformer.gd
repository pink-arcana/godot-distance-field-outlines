extends Node3D

const ANIMATION_TRACK := "main"

@export var disable_animation := false
@export var sky_forward : Environment
@export var sky_compatibility : Environment
@onready var world_environment: WorldEnvironment = %WorldEnvironment

func _ready() -> void:
	if Demo.forward_plus_rendering:
		world_environment.environment = sky_forward
	else:
		world_environment.environment = sky_compatibility

	if disable_animation:
		return

	for child in find_children("*", "AnimationPlayer", true, false):
		if child is AnimationPlayer:
			child.play(ANIMATION_TRACK)
