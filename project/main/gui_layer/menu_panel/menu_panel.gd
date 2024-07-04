extends PanelContainer

const MIN_UI_SCALE := 0.5
const MAX_UI_SCALE := 1.5

@onready var decrease_ui_scale_button: Button = %DecreaseUIScaleButton
@onready var increase_ui_scale_button: Button = %IncreaseUIScaleButton


func _ready() -> void:
	decrease_ui_scale_button.pressed.connect(change_ui_scale.bind(false))
	increase_ui_scale_button.pressed.connect(change_ui_scale.bind(true))


func change_ui_scale(p_increase : bool) -> void:
	var current_scale = get_tree().root.content_scale_factor
	var change : float = 0.0
	if current_scale >= 1.0 && p_increase:
		change = 0.5
	elif current_scale < 1.0 && p_increase:
		change = 0.25
	elif current_scale >= 1.5 && not p_increase:
		change = -0.5
	elif current_scale < 1.5 && not p_increase:
		change = -0.25

	var new_scale = clamp(
			current_scale + change,
			MIN_UI_SCALE,
			MAX_UI_SCALE,
		)

	get_tree().root.content_scale_factor = new_scale

	if new_scale >= MAX_UI_SCALE:
		increase_ui_scale_button.disabled = true
	else:
		increase_ui_scale_button.disabled = false

	if new_scale <= MIN_UI_SCALE:
		decrease_ui_scale_button.disabled = true
	else:
		decrease_ui_scale_button.disabled = false
