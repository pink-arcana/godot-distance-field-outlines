extends Button


@export var normal_icon : Texture2D
@export var hover_icon : Texture2D
@export var pressed_icon : Texture2D


func _ready() -> void:
	mouse_entered.connect(
		func():
			icon = hover_icon
	)

	mouse_exited.connect(
		func():
			icon = normal_icon
	)

	button_down.connect(
		func():
			icon = pressed_icon
	)

	button_up.connect(
		func():
			icon = normal_icon
	)
