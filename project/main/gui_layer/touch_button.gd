extends Button

@export var action_name : StringName

@export var icon_normal : Texture2D
@export var icon_hover : Texture2D
@export var icon_pressed : Texture2D

var hovered : bool = false

var pressed_event : InputEvent
var unpressed_event : InputEvent

func _ready() -> void:
	if not action_name:
		push_warning("No action name set for TouchButton: %s")
		return

	pressed_event = InputEventAction.new()
	pressed_event.action = action_name
	pressed_event.pressed = true

	unpressed_event = InputEventAction.new()
	unpressed_event.action = action_name
	unpressed_event.pressed = false

	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	mouse_entered.connect(set_hovered.bind(true))
	mouse_exited.connect(set_hovered.bind(false))
	update_icon()


# is_hovered() gives opposite of expected results,
# so we will set our own.
func set_hovered(p_value) -> void:
	hovered = p_value
	update_icon()


func update_icon() -> void:
	if hovered:
		if button_pressed:
			icon = icon_pressed
		else:
			icon = icon_hover
	else:
		icon = icon_normal


func _on_button_down() -> void:
	if not pressed_event:
		return

	Input.parse_input_event(pressed_event)
	update_icon()


func _on_button_up() -> void:
	if not unpressed_event:
		return

	Input.parse_input_event(unpressed_event)
	update_icon()
