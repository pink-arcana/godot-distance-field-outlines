extends Node

signal recording_started(record : PerformanceRecord)
signal recording_completed(record : PerformanceRecord)

enum Mode {
	NONE,
	CONTINUOUS_RECORDING,
	SINGLE_START,
	SINGLE_RECORDING,
	SINGLE_COMPLETED,
}

var _mode : Mode = Mode.NONE :
	set(value):
		_mode = value
		_mode_frame_count = 0

var _mode_frame_count : int = 0
var _last_tick := 0
var _thread := Thread.new()

var _context : Dictionary
var _performance_record : PerformanceRecord

var start_delay_frame_count : int = 150
var single_recording_frame_count : int = 150
var continuous_record_frame_count : int = 150


func _ready() -> void:
	if OS.has_feature("web"):
		set_process(false)
		return

	_thread.start(
		func():
			# From Debug Menu addon:
			# Disable _thread safety checks as they interfere with this add-on.
			# This only affects this particular _thread, not other _thread instances in the project.
			# See <https://github.com/godotengine/godot/pull/78000> for details.
			# Use a Callable so that this can be ignored on Godot 4.0 without causing a script error
			# (_thread safety checks were added in Godot 4.1).
			if Engine.get_version_info()["hex"] >= 0x040100:
				Callable(Thread, "set_thread_safety_checks_enabled").call(false)

			# Enable required time measurements to display CPU/GPU frame time information.
			# These lines are time-consuming operations, so run them in a separate _thread.
			RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
			_update_context()
	)


func _exit_tree() -> void:
	_thread.wait_to_finish()


func _update_context(p_params := {}) -> void:
	_context = p_params.duplicate(true)

	var viewport := get_viewport()
	var viewport_render_size := Vector2i()
	if viewport.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
		viewport_render_size = viewport.get_visible_rect().size
	else:
		# Window size matches viewport size.
		viewport_render_size = viewport.size

	_context["render_size"] = viewport_render_size
	_context["editor_version"] = Engine.get_version_info().string
	_context["project_version"] = ProjectSettings.get_setting("application/config/version")

	var adapter_string := ""
	# Make "NVIDIA Corporation" and "NVIDIA" be considered identical
	# (required when using OpenGL to avoid redundancy).
	if RenderingServer.get_video_adapter_vendor().trim_suffix(" Corporation") \
			in RenderingServer.get_video_adapter_name():
		# Avoid repeating vendor name before adapter name.
		# Trim redundant suffix sometimes reported by NVIDIA graphics cards when using OpenGL.
		adapter_string = RenderingServer.get_video_adapter_name().trim_suffix("/PCIe/SSE2")
	else:
		adapter_string = RenderingServer.get_video_adapter_vendor() + " - " \
				+ RenderingServer.get_video_adapter_name().trim_suffix("/PCIe/SSE2")
	_context["adapter"] = adapter_string

	# Graphics driver version information isn't always availble.
	var driver_info := OS.get_video_adapter_driver_info()
	var driver_info_string := ""
	if driver_info.size() >= 2:
		driver_info_string = driver_info[1]
	else:
		driver_info_string = "(unknown)"
	_context["driver_info"] = driver_info_string

	var rendering_method := str(ProjectSettings.get_setting_with_override(
			"rendering/renderer/rendering_method"
	))
	var rendering_method_string := rendering_method
	match rendering_method:
		"forward_plus":
			rendering_method_string = "Forward+"
		"mobile":
			rendering_method_string = "Forward Mobile"
		"gl_compatibility":
			rendering_method_string = "Compatibility"
	_context["renderer"] = rendering_method_string

	var rendering_driver := str(ProjectSettings.get_setting_with_override(
			"rendering/rendering_device/driver"
	))
	var graphics_api_string := rendering_driver
	if rendering_method != "gl_compatibility":
		if rendering_driver == "d3d12":
			graphics_api_string = "Direct3D 12"
		elif rendering_driver == "metal":
			graphics_api_string = "Metal"
		elif rendering_driver == "vulkan":
			if OS.has_feature("macos") or OS.has_feature("ios"):
				graphics_api_string = "Vulkan via MoltenVK"
			else:
				graphics_api_string = "Vulkan"
	else:
		if rendering_driver == "opengl3_angle":
			graphics_api_string = "OpenGL via ANGLE"
		elif OS.has_feature("mobile") or rendering_driver == "opengl3_es":
			graphics_api_string = "OpenGL ES"
		elif OS.has_feature("web"):
			graphics_api_string = "WebGL"
		elif rendering_driver == "opengl3":
			graphics_api_string = "OpenGL"
	_context["graphics_api"] = graphics_api_string


func _process(_delta: float) -> void:
	_mode_frame_count += 1

	if _mode == Mode.SINGLE_START:
		if _mode_frame_count >= start_delay_frame_count:
			_change_mode(Mode.SINGLE_RECORDING)
	elif _mode == Mode.SINGLE_RECORDING:
		if _mode_frame_count > single_recording_frame_count:
			_change_mode(Mode.SINGLE_COMPLETED)
			return

	var current_tick := Time.get_ticks_usec()

	if _performance_record:
		var viewport_rid := get_viewport().get_viewport_rid()
		var frametime := (current_tick - _last_tick) * 0.001
		var frametime_cpu := RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) \
				 + RenderingServer.get_frame_setup_time_cpu()
		var frametime_gpu := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		_performance_record.add_frame(frametime, frametime_cpu, frametime_gpu)

	_last_tick = current_tick


func _change_mode(p_mode : Mode) -> void:
	_mode = p_mode

	match p_mode:
		Mode.NONE:
			_performance_record = null
		Mode.CONTINUOUS_RECORDING:
			_performance_record = PerformanceRecord.new(continuous_record_frame_count, false, _context)
			recording_started.emit(_performance_record)
		Mode.SINGLE_START:
			_performance_record = null
		Mode.SINGLE_RECORDING:
			_performance_record = PerformanceRecord.new(single_recording_frame_count, true, _context)
			recording_started.emit(_performance_record)
		Mode.SINGLE_COMPLETED:
			recording_completed.emit(_performance_record)
			_change_mode(Mode.NONE)



# ---------------------------------------------------------------------------
# PUBLIC FUNCTIONS
# ---------------------------------------------------------------------------

func start_continuous_recording(p_params := {}) -> void:
	_update_context(p_params)
	_change_mode(Mode.CONTINUOUS_RECORDING)


func start_single_recording(p_params := {}) -> void:
	_update_context(p_params)
	_change_mode(Mode.SINGLE_START)
