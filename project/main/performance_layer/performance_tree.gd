class_name PerformanceTree
extends Tree

var root : TreeItem

enum Column {
	WIDTH,
	PASS_COUNT,
	BASE_FRAME_TIME,
	NODE_FRAME_TIME,
	NODE_FRAME_TIME_DIFF,
	NODE_PASS_TIME,
	CE_FRAME_TIME,
	CE_FRAME_TIME_DIFF,
	CE_PASS_TIME,
	MAX,
}

var column_display_names := {
	Column.WIDTH : "Outline\nWidth",
	Column.PASS_COUNT : "Shader\nPasses",
	Column.BASE_FRAME_TIME : "Base\nTime",
	Column.NODE_FRAME_TIME : "Node\nTime",
	Column.CE_FRAME_TIME : "CompositorEffect\nTime",
	Column.NODE_FRAME_TIME_DIFF : "Increase over base\n(Node - Base)",
	Column.CE_FRAME_TIME_DIFF : "Increase over base\n(CE - Base)",
	Column.NODE_PASS_TIME : "Time per pass\n(Node - Base) / Passes",
	Column.CE_PASS_TIME : "Time per pass\n(CE - Base) / Passes",
}

const TOTAL_FRAME_TIME := PerformanceRecord.Type.TOTAL
const EMPTY := "---"

const WIDTHS : PackedInt32Array = [0,2,4,8,16,32,64,128,256,512,1024]

@export var base_bg_color : Color
@export var node_bg_color : Color
@export var ce_bg_color : Color

var _base_frame_time : float
var _width_items := {} # {width : TreeItem}

func _ready() -> void:
	clear()
	root = create_item()
	hide_root = true

	columns = Column.MAX as int

	for col in Column.size() - 1:
		var display_name : String = column_display_names.get(col as Column, Column.keys()[col])
		set_column_title(col, display_name)

	_create_items()


func _create_items() -> void:
	for i in WIDTHS.size():
		var width := WIDTHS[i]

		var item := root.create_child(i)
		item.set_text(Column.WIDTH, str(width))
		_width_items[width] = item

		for c in columns:
			item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_CENTER)


func add_baseline(p_record : PerformanceRecord) -> void:
	var record := p_record
	var item : TreeItem = _width_items[0]

	_base_frame_time = record.get_average(TOTAL_FRAME_TIME)

	for c in columns:
		var text := EMPTY
		if c == Column.BASE_FRAME_TIME:
			text = record.get_average_string(TOTAL_FRAME_TIME)
			item.set_custom_bg_color(c, base_bg_color, true)
		item.set_text(c, text)



func disable_compositor_effect() -> void:
	for item in _width_items:
		item.set_text(Column.CE_FRAME_TIME, EMPTY)
		item.set_text(Column.CE_FRAME_TIME_DIFF, EMPTY)
		item.set_text(Column.CE_PASS_TIME, EMPTY)


func add_record(p_record : PerformanceRecord) -> void:
	var record := p_record
	var context := record.get_context()
	var jf_calc : JFCalculator = context["jf_calc"]

	if not jf_calc:
		return

	var width := int(round(jf_calc.get_debug_dict()["_render_outline_width"]))
	var pass_count : int = 2 + jf_calc.get_step_offsets().size()
	var frame_time : float = record.get_average(TOTAL_FRAME_TIME)
	var frame_time_diff : float = frame_time - _base_frame_time
	var pass_time : float = frame_time_diff / pass_count

	var frame_time_str := str(frame_time).pad_decimals(2)
	var frame_time_diff_str := str(frame_time_diff).pad_decimals(2)
	var pass_time_str := str(pass_time).pad_decimals(2)

	var item : TreeItem = _width_items[width]
	item.set_text(Column.PASS_COUNT, str(pass_count))

	var scene_type : DemoScene.SceneType = context["scene_type"]
	var color := Color.WHITE

	var dict := {
			"width": str(width),
			"frame_time": frame_time_str,
			"diff_time": frame_time_diff_str,
			"pass_time": pass_time_str,
	}

	var frame_time_template := "{type}\nWidth: {width}\nFrame time: {frame_time}"
	var diff_template := "{type}\nWidth: {width}\nFrame time over base: {diff_time}"
	var pass_template := "{type}\nWidth: {width}\nTime per pass: {pass_time}"

	if scene_type == DemoScene.SceneType.NODE:
		dict["type"] = "Node"

		item.set_text(Column.NODE_FRAME_TIME, frame_time_str)
		item.set_text(Column.NODE_FRAME_TIME_DIFF, frame_time_diff_str)
		item.set_text(Column.NODE_PASS_TIME, pass_time_str)

		item.set_tooltip_text(Column.NODE_FRAME_TIME, frame_time_template.format(dict))
		item.set_tooltip_text(Column.NODE_FRAME_TIME_DIFF, diff_template.format(dict))
		item.set_tooltip_text(Column.NODE_PASS_TIME, pass_template.format(dict))

		color = node_bg_color
		item.set_custom_bg_color(Column.NODE_FRAME_TIME, color, true)
		item.set_custom_bg_color(Column.NODE_FRAME_TIME_DIFF, color, true)
		item.set_custom_bg_color(Column.NODE_PASS_TIME, color, true)

	elif scene_type == DemoScene.SceneType.COMPOSITOR_EFFECT:
		dict["type"] = "CompositorEffect"

		item.set_text(Column.CE_FRAME_TIME, frame_time_str)
		item.set_text(Column.CE_FRAME_TIME_DIFF, frame_time_diff_str)
		item.set_text(Column.CE_PASS_TIME, pass_time_str)

		item.set_tooltip_text(Column.CE_FRAME_TIME, frame_time_template.format(dict))
		item.set_tooltip_text(Column.CE_FRAME_TIME_DIFF, diff_template.format(dict))
		item.set_tooltip_text(Column.CE_PASS_TIME, pass_template.format(dict))

		color = ce_bg_color
		item.set_custom_bg_color(Column.CE_FRAME_TIME, color, true)
		item.set_custom_bg_color(Column.CE_FRAME_TIME_DIFF, color, true)
		item.set_custom_bg_color(Column.CE_PASS_TIME, color, true)
