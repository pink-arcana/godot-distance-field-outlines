extends Button

@export var minimize_control : Control

@export var maximized_icon : Texture2D
@export var minimized_icon : Texture2D

func _ready() -> void:
	update()


func _toggled(_toggled_on: bool) -> void:
	update()


func update() -> void:
	if minimize_control:
		minimize_control.visible = button_pressed
	if button_pressed:
		icon = maximized_icon
	else:
		icon = minimized_icon
