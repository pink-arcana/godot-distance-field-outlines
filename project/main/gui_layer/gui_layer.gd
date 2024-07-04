extends CanvasLayer

const HIDE_UI_TIME := 0.25
const SHOW_UI_TIME := 0.5
const MIN_ALPHA := 0.0

var tween : Tween

@onready var hide_panels_web : Array[Control] = [%FPSPanel, %ExitPanel]

@onready var hide_panels_3d_input : Array[Control] = [%ScenePanel, %FPSPanel, %InputPanel]



func _ready() -> void:
	if OS.has_feature("web"):
		for control in hide_panels_web:
			control.hide()

	Events.gimbal_input_capture_changed.connect(_on_Events_gimbal_input_capture_changed)


func _on_Events_gimbal_input_capture_changed(p_value : bool) -> void:
	if tween:
		tween.kill()

	tween = create_tween()
	tween.set_parallel(true)
	var tween_time := HIDE_UI_TIME if p_value else SHOW_UI_TIME
	var final_val := MIN_ALPHA if p_value else 1.0

	for panel in hide_panels_3d_input:
		tween.tween_property(panel, "modulate:a", final_val, tween_time)
