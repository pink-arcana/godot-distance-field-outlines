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
	Column.NODE_PASS_TIME : "Change\n(Time - Previous)",
	Column.CE_PASS_TIME : "Change\n(Time - Previous)",
}

const TOTAL_FRAME_TIME := PerformanceRecord.Type.TOTAL
const EMPTY := "---"

const WIDTHS : PackedInt32Array = [0,2,4,8,16,32,64,128,256,512,1024]

@export var base_bg_color : Color
@export var node_bg_color : Color
@export var ce_bg_color : Color

var _base_frame_time : float
var _width_items := {} # {width : TreeItem}

var node_times : PackedFloat32Array = []
var ce_times : PackedFloat32Array = []

func _ready() -> void:
	clear()
	ce_times.clear()
	node_times.clear()
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
	#var pass_time : float = frame_time_diff / float(pass_count)

	var frame_time_str := str(snappedf(frame_time, 0.01))
	var frame_time_diff_str := str(snappedf(frame_time_diff, 0.01))
	#var pass_time_str := str(snappedf(pass_time, 0.01))

	#print("width", width)

	var item : TreeItem = _width_items[width]
	item.set_text(Column.PASS_COUNT, str(pass_count))

	var scene_type : DemoScene.SceneType = context["scene_type"]
	var color := Color.WHITE

	var dict := {
			"width": str(width),
			"frame_time": frame_time_str,
			"diff_time": frame_time_diff_str,
			#"pass_time": pass_time_str,
	}

	var frame_time_template := "Frame time: {frame_time}"
	var diff_template := "Increase over base: {diff_time}"
	var pass_template := "Change: {pass_time}"

	if scene_type == DemoScene.SceneType.NODE:
		dict["type"] = "Node"
		var ft_increase_string : String
		if node_times.is_empty():
			ft_increase_string = "---"
		else:
			var ft_increase : float = frame_time - node_times[node_times.size() - 1]
			ft_increase_string = str(snappedf(ft_increase, 0.01))
		node_times.append(frame_time)
		dict["pass_time"] = ft_increase_string

		item.set_text(Column.NODE_FRAME_TIME, frame_time_str)
		item.set_text(Column.NODE_FRAME_TIME_DIFF, frame_time_diff_str)
		item.set_text(Column.NODE_PASS_TIME, ft_increase_string)

		item.set_tooltip_text(Column.NODE_FRAME_TIME, frame_time_template.format(dict))
		item.set_tooltip_text(Column.NODE_FRAME_TIME_DIFF, diff_template.format(dict))
		item.set_tooltip_text(Column.NODE_PASS_TIME, pass_template.format(dict))

		color = node_bg_color
		item.set_custom_bg_color(Column.NODE_FRAME_TIME, color, true)
		item.set_custom_bg_color(Column.NODE_FRAME_TIME_DIFF, color, true)
		item.set_custom_bg_color(Column.NODE_PASS_TIME, color, true)

	elif scene_type == DemoScene.SceneType.COMPOSITOR_EFFECT:
		dict["type"] = "CompositorEffect"
		var ft_increase_string : String
		if ce_times.is_empty():
			#print("empty ce_times", ce_times)
			ft_increase_string = "---"
		else:
			#print("ce_times", ce_times)
			var ft_increase : float = frame_time - ce_times[ce_times.size() - 1]
			ft_increase_string = str(snappedf(ft_increase, 0.01))
		ce_times.append(frame_time)
		dict["pass_time"] = ft_increase_string

		item.set_text(Column.CE_FRAME_TIME, frame_time_str)
		item.set_text(Column.CE_FRAME_TIME_DIFF, frame_time_diff_str)
		item.set_text(Column.CE_PASS_TIME, ft_increase_string)

		item.set_tooltip_text(Column.CE_FRAME_TIME, frame_time_template.format(dict))
		item.set_tooltip_text(Column.CE_FRAME_TIME_DIFF, diff_template.format(dict))
		item.set_tooltip_text(Column.CE_PASS_TIME, pass_template.format(dict))

		color = ce_bg_color
		item.set_custom_bg_color(Column.CE_FRAME_TIME, color, true)
		item.set_custom_bg_color(Column.CE_FRAME_TIME_DIFF, color, true)
		item.set_custom_bg_color(Column.CE_PASS_TIME, color, true)
