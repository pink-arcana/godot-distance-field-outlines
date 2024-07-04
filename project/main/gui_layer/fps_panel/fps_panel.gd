extends Control

const UPDATE_INTERVAL := 1.0

var record : PerformanceRecord

@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var context_container: GridContainer = %ContextContainer
#@onready var panel_v_box: VBoxContainer = %PanelVBox
@onready var content_panel: PanelContainer = %ContentPanel
@onready var panel_container: PanelContainer = %PanelContainer

@onready var fps_label: Label = %FPSLabel
@onready var total_label: Label = %TotalLabel
@onready var total_range_label: Label = %TotalRangeLabel
@onready var cpu_label: Label = %CPULabel
@onready var cpu_range_label: Label = %CPURangeLabel
@onready var gpu_label: Label = %GPULabel
@onready var gpu_range_label: Label = %GPURangeLabel

@onready var timer: Timer = %Timer

@onready var profile_button: Button = %ProfileButton


func _ready() -> void:
	reset()
	panel_container.visibility_changed.connect(reformat_for_content_scale)
	get_tree().root.size_changed.connect(reformat_for_content_scale)
	get_tree().root.size_changed.connect(restart_recording)
	profile_button.pressed.connect(_on_ProfileButton_pressed)
	Events.scene_loaded.connect(_on_Events_scene_loaded)
	Events.settings_changed.connect(restart_recording)
	PerformanceMonitor.recording_started.connect(_on_PerformanceMonitor_recording_started)

	reformat_for_content_scale()


func reset() -> void:
	timer.stop()
	fps_label.text = "---"
	total_label.text = "---"
	total_range_label.text = ""
	cpu_label.text = "---"
	cpu_range_label.text = ""
	gpu_label.text = "---"
	gpu_range_label.text = ""


func update_context_display() -> void:
	if not RenderingServer.frame_post_draw.is_connected(_finish_update_context):
		RenderingServer.frame_post_draw.connect(_finish_update_context)


func _finish_update_context() -> void:
	if RenderingServer.frame_post_draw.is_connected(_finish_update_context):
		RenderingServer.frame_post_draw.disconnect(_finish_update_context)

	for child in context_container.get_children():
		child.hide()
		child.queue_free()

	if not record:
		return

	var context := record.get_context()

	var total_passes : int = 0
	if Demo.jf_calc:
		total_passes = 2 + Demo.jf_calc.get_step_offsets().size()
	context["total_passes"] = total_passes

	var hidden_keys : PackedStringArray = [
			"total_frames",
			"driver info",
			"project_version",
	]
	if Demo.scene_type == DemoScene.SceneType.BASE:
		hidden_keys.append("total_passes")

	for key in context:
		if key in hidden_keys:
			continue

		var display_label := Label.new()
		display_label.text = str(key).replace("_", " ").capitalize()
		display_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		context_container.add_child(display_label)

		var value_label := Label.new()
		value_label.text = str(context[key])
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		context_container.add_child(value_label)



func update_display() -> void:
	if not visible or not record:
		return

	var total := PerformanceRecord.Type.TOTAL
	var cpu := PerformanceRecord.Type.CPU
	var gpu := PerformanceRecord.Type.GPU

	fps_label.text = str(round(record.get_frames_per_second()))
	total_label.text = record.get_average_string(total) + " ms"
	total_range_label.text = "(%s - %s)" % [
			record.get_min_string(total),
			record.get_max_string(total),
		]
	cpu_label.text = record.get_average_string(cpu) + " ms"
	cpu_range_label.text = "(%s - %s)" % [
			record.get_min_string(cpu),
			record.get_max_string(cpu),
		]
	gpu_label.text = record.get_average_string(gpu) + " ms"
	gpu_range_label.text = "(%s - %s)" % [
			record.get_min_string(gpu),
			record.get_max_string(gpu),
		]


func restart_recording() -> void:
	update_context_display.call_deferred()
	PerformanceMonitor.start_continuous_recording()


func _on_timer_timeout() -> void:
	update_display()


func _on_Events_scene_loaded(
		_demo_scene : DemoScene,
		_scene_type : DemoScene.SceneType,
		_jf_calc : JFCalculator,
	) -> void:

	restart_recording()


func _on_PerformanceMonitor_recording_started(p_record : PerformanceRecord) -> void:
	record = p_record
	reset()
	update_context_display.call_deferred()
	if not timer.is_inside_tree():
		timer.ready.connect(timer.start.bind(UPDATE_INTERVAL))
	else:
		timer.start(UPDATE_INTERVAL)


func _on_ProfileButton_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Measure performance at multiple outline widths for each mode?\nThis may take some time.\n"
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.get_label().theme_type_variation = "ConfirmationLabel"
	dialog.theme_type_variation = "ConfirmationDialog"
	dialog.confirmed.connect(Events.test_performance_requested.emit)
	add_child(dialog)
	dialog.popup_centered()


func reformat_for_content_scale() -> void:
	if not is_node_ready():
		return

	if not panel_container.visible:
		size_flags_vertical = SIZE_FILL
		return

	if get_tree().root.content_scale_factor > 1.0001:
		# Show scroll and expand
		size_flags_vertical = SIZE_EXPAND_FILL
		panel_container.size_flags_vertical = SIZE_EXPAND_FILL
		if not content_panel.get_parent() == scroll_container:
			content_panel.reparent(scroll_container)
		scroll_container.show()
	else:
		size_flags_vertical = SIZE_FILL
		panel_container.size_flags_vertical = SIZE_FILL
		if not content_panel.get_parent() == panel_container:
			content_panel.reparent(panel_container)
		scroll_container.hide()
