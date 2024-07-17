extends Control


const ACTION_NAME := "performance_snapshot"
const RESULTS_FILE_SUFFIX := "_result"
const SCREENSHOT_FILE_SUFFIX := "_screenshot"
const FILE_EXTENSION := ".png"

enum State {
	NONE,
	WAITING,
	SAVE_PANEL,
	RECORDING,
	RESULTS_PANEL,
}

@export var frames_to_wait := 10
@export var frames_to_record := 1000

var state := State.WAITING :
	set(value):
		if state == value:
			return
		state = value
		if mouse_block_control:
			if state == State.WAITING:
				mouse_block_control.hide()
			else:
				mouse_block_control.show()
var base_file_path : String


@onready var mouse_block_control: Control = %MouseBlockControl
@onready var save_panel: PopupPanel = %SavePanel
@onready var results_panel: PopupPanel = %ResultsPanel


func _ready() -> void:
	if OS.has_feature("web"):
		set_process_input(false)
		save_panel.queue_free()
		results_panel.queue_free()
		return

	save_panel.file_suffixes = [RESULTS_FILE_SUFFIX, SCREENSHOT_FILE_SUFFIX]
	save_panel.file_extension = FILE_EXTENSION
	save_panel.start_pressed.connect(_on_SavePanel_start_pressed)
	save_panel.cancel_pressed.connect(_on_SavePanel_cancel_pressed)
	results_panel.close_pressed.connect(_on_ResultsPanel_close_pressed)

	save_panel.set_flag(Window.FLAG_POPUP, false)
	save_panel.hide()

	results_panel.set_flag(Window.FLAG_POPUP, false)
	results_panel.hide()



func _input(event: InputEvent) -> void:
	if not state == State.WAITING:
		return

	if event.is_action_pressed(ACTION_NAME):
		state = State.SAVE_PANEL
		save_panel.popup_centered_clamped()


func _on_SavePanel_start_pressed(p_file_path : String) -> void:
	save_panel.hide()
	base_file_path = p_file_path
	state = State.RECORDING
	if not PerformanceMonitor.recording_completed.is_connected(_on_PerformanceMonitor_recording_completed):
		PerformanceMonitor.recording_completed.connect(_on_PerformanceMonitor_recording_completed)
	PerformanceMonitor.start_delay_frame_count = frames_to_wait
	PerformanceMonitor.single_recording_frame_count = frames_to_record
	PerformanceMonitor.start_single_recording()


func _on_SavePanel_cancel_pressed() -> void:
	save_panel.hide()
	state = State.WAITING


func _on_PerformanceMonitor_recording_completed(p_record : PerformanceRecord) -> void:
	if PerformanceMonitor.recording_completed.is_connected(_on_PerformanceMonitor_recording_completed):
		PerformanceMonitor.recording_completed.disconnect(_on_PerformanceMonitor_recording_completed)

	var screenshot_image := get_viewport().get_texture().get_image()
	var file_path := base_file_path + SCREENSHOT_FILE_SUFFIX + FILE_EXTENSION
	var result := screenshot_image.save_png(file_path)
	if result != OK:
		printerr("Error %s saving screenshot at %s" % [result, file_path])

	state = State.RESULTS_PANEL
	results_panel.update(p_record, base_file_path)

	if not results_panel.visibility_changed.is_connected(_on_ResultsPanel_visibility_changed):
		results_panel.visibility_changed.connect(_on_ResultsPanel_visibility_changed)
	results_panel.popup_centered_clamped()


func _on_ResultsPanel_visibility_changed() -> void:
	if results_panel.visibility_changed.is_connected(_on_ResultsPanel_visibility_changed):
		results_panel.visibility_changed.disconnect(_on_ResultsPanel_visibility_changed)

	if not results_panel.visible:
		return

	await RenderingServer.frame_post_draw

	var results_image := get_viewport().get_texture().get_image()
	var file_path := base_file_path + RESULTS_FILE_SUFFIX + FILE_EXTENSION
	var result := results_image.save_png(file_path)
	if result != OK:
		printerr("Error %s saving results at %s" % [result, file_path])


func _on_ResultsPanel_close_pressed() -> void:
	results_panel.hide()
	state = State.WAITING
