extends PopupPanel

signal start_pressed(base_file_path : String)
signal cancel_pressed

const BASE_PATH := "user://"
const DEFAULT_DIR := "snapshots"
const DEFAULT_SUBDIR := ""
const DEFAULT_NAME := "snapshot"

var file_extension := ".png"
var file_suffixes : PackedStringArray = []

@onready var dir_text_edit: TextEdit = %DirTextEdit
@onready var subdir_text_edit: TextEdit = %SubdirTextEdit
@onready var name_text_edit: TextEdit = %NameTextEdit
@onready var start_button: Button = %StartButton
@onready var cancel_button: Button = %CancelButton


func _ready() -> void:
	about_to_popup.connect(_on_about_to_popup)
	start_button.pressed.connect(_on_StartButton_pressed)
	cancel_button.pressed.connect(cancel_pressed.emit)
	visibility_changed.connect(_on_visibility_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_accept"):
		start_button.pressed.emit()


func _on_about_to_popup() -> void:
	if not dir_text_edit.text:
		dir_text_edit.placeholder_text = DEFAULT_DIR
	if not subdir_text_edit.text:
		subdir_text_edit.placeholder_text = DEFAULT_SUBDIR
	if not name_text_edit.text:
		name_text_edit.placeholder_text = DEFAULT_NAME


func _on_visibility_changed() -> void:
	if visible:
		name_text_edit.grab_focus()


# ---------------------------------------------------------------------------


func get_save_dir() -> String:
	var dir := dir_text_edit.text
	if not dir:
		dir = DEFAULT_DIR
	dir = dir.validate_filename()
	var subdir := subdir_text_edit.text
	if not subdir:
		subdir = DEFAULT_SUBDIR
	subdir = subdir.validate_filename()

	return BASE_PATH.path_join(dir).path_join(subdir)


func get_save_file_path(p_name : String, p_dir : String) -> String:
	if not DirAccess.dir_exists_absolute(p_dir):
		var result := DirAccess.make_dir_recursive_absolute(p_dir)
		if result != OK:
			push_error("Error %s creating directory at %s" % [result, p_dir])
			return ""

	var base_file_path = p_dir.path_join(p_name)
	var i := 1
	while files_exist(base_file_path):
		base_file_path = p_dir.path_join(p_name + str(i).pad_zeros(2))
		i += 1
		if i > 99:
			push_error("Unable to create file %s at path %s" % [p_name, p_dir])
			return ""
	return base_file_path


func files_exist(p_base_path : String) -> bool:
	for suffix in file_suffixes:
		var p := p_base_path + suffix + file_extension
		if FileAccess.file_exists(p):
			return true
	return false


func _on_StartButton_pressed() -> void:
	var dir := get_save_dir()
	var file_name := name_text_edit.text
	if not file_name:
		file_name = DEFAULT_NAME
	var base_file_path := get_save_file_path(file_name, dir)
	if not base_file_path:
		cancel_pressed.emit()
	else:
		start_pressed.emit(base_file_path)
