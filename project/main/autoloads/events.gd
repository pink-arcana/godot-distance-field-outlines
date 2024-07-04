extends Node

const DEBUG_ENABLED := false


signal gimbal_input_capture_changed(value : bool)

signal scene_change_requested(
		demo_scene : DemoScene,
		scene_type : DemoScene.SceneType,
	)


signal scene_loaded(
		demo_scene : DemoScene,
		scene_type : DemoScene.SceneType,
		jf_calc : JFCalculator,
	)

signal settings_changed

signal website_requested(url : String)

signal state_change_requested(state : Main.State)
signal state_changed(state : Main.State)

signal test_performance_requested

var debug_ignore_signals := PackedStringArray([])


func _ready() -> void:
	if not OS.is_debug_build() or not DEBUG_ENABLED:
		return

	for signal_dict in get_signal_list():
		var signal_name : String = signal_dict.name
		if signal_name in debug_ignore_signals:
			continue
		connect(signal_name, _debug_print_event.bind(signal_name))


func _debug_print_event(arg1 = "", arg2 = "", arg3 = "", arg4 = "") -> void:
	if arg4:
		var template := "[Events] %s(%s, %s, %s)"
		print(template % [arg4, arg1, arg2, arg3])
	elif arg3:
		var template := "[Events] %s(%s, %s)"
		print(template % [arg3, arg1, arg2])
	elif arg2:
		var template := "[Events] %s(%s)"
		print(template % [arg2, arg1])
	else:
		var template := "[Events] %s"
		print(template % arg1)
