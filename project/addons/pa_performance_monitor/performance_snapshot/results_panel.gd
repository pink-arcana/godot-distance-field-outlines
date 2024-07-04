extends PopupPanel

signal close_pressed

const AVERAGE := "average"
const MIN := "min"
const MAX := "max"

var dir_path : String

@onready var title_label: Label = %TitleLabel
@onready var date_time_label: Label = %DateTimeLabel
@onready var context_container: GridContainer = %ContextContainer
@onready var times_container: GridContainer = %TimesContainer
@onready var close_button: Button = %CloseButton
@onready var open_dir_button: Button = %OpenDirButton


func _ready() -> void:
	close_button.pressed.connect(close_pressed.emit)
	open_dir_button.pressed.connect(_on_OpenDirButton_pressed)


func update(p_record : PerformanceRecord, p_base_path : String) -> void:
	var dir_only := str(p_base_path + ".png").get_base_dir().trim_prefix("user://")
	dir_path = OS.get_user_data_dir() + "/" + dir_only
	title_label.text = p_base_path.rsplit("/", true, 1)[1].replace("_", " ").capitalize()
	date_time_label.text = Time.get_datetime_string_from_system(false, true)
	_update_context(p_record.get_context())
	_update_times(p_record)


func _update_context(p_context : Dictionary) -> void:
	for child in context_container.get_children():
		child.hide()
		child.queue_free()

	var context := p_context
	for key in context:
		var display_label := Label.new()
		display_label.text = str(key).replace("_", " ").capitalize()
		context_container.add_child(display_label)

		var value_label := Label.new()
		value_label.text = str(context[key])
		context_container.add_child(value_label)


func _update_times(p_record : PerformanceRecord) -> void:
	for child in times_container.get_children():
		child.hide()
		child.queue_free()

	var type_header := Label.new()
	type_header.text = "Type"
	times_container.add_child(type_header)

	var time_header := Label.new()
	time_header.text = "Average (Min - Max)"
	times_container.add_child(time_header)

	var types := {
		PerformanceRecord.Type.TOTAL: "Total",
		PerformanceRecord.Type.CPU: "CPU",
		PerformanceRecord.Type.GPU: "GPU",
	}

	for type in types:
		var name_label := Label.new()
		name_label.text = types[type]
		times_container.add_child(name_label)

		var average_text := p_record.get_average_string(type)
		var min_text := p_record.get_min_string(type)
		var max_text := p_record.get_max_string(type)

		var time_label := Label.new()
		time_label.text = "%s (%s - %s)" % [average_text, min_text, max_text]
		times_container.add_child(time_label)


func _on_OpenDirButton_pressed() -> void:
	prints("Opening...", dir_path)
	var result := OS.shell_open(dir_path)
	if result != OK:
		printerr("Error opening path: %s" % dir_path)
