@icon("res://addons/pa_graph_rect/graph_rect/graph_rect.svg")
class_name GraphRect
extends Control

var graph_rect_panel_scene : PackedScene = load("res://addons/pa_graph_rect/graph_rect/graph_rect_panel.tscn")

const THEME_TYPE := "GraphRect"

enum LineStyle {
	SOLID,
	DASHED,
}


class Series extends RefCounted:
	var display_name : String
	var color : Color
	var line_style : LineStyle
	var draw_points : bool
	var categories : PackedInt32Array
	var y_values : PackedFloat32Array
	var positions : PackedVector2Array

	func _init(
			p_display_name := "Series",
			p_color := Color.BLACK,
			p_line_style := LineStyle.SOLID,
			p_draw_points := true,
		) -> void:

		display_name = p_display_name
		color = p_color
		line_style = p_line_style
		draw_points = p_draw_points

	func add_point(p_category_idx : int, p_y_value : float, p_position : Vector2) -> void:
		categories.append(p_category_idx)
		y_values.append(p_y_value)
		positions.append(p_position)

	func size() -> int:
		return categories.size()

const INVALID_ID := -1

@export var use_default_theme : bool = true



@export var title := "" :
	set(value):
		title = value
		_update_labels()

@export var x_title := "" :
	set(value):
		x_title = value
		_update_labels()

@export var y_title := "" :
	set(value):
		y_title = value
		_update_labels()

@export var show_legend : bool = true :
	set(value):
		show_legend = value
		_update_legend()

@export var y_min : float = 0.0 :
	set(value):
		y_min = value
		_set_graph_data("y_min", value)

@export var y_max : float = 16.0 :
	set(value):
		y_max = value
		_set_graph_data("y_max", value)

@export var y_grid_interval : float = 1.0 :
	set(value):
		y_grid_interval = value
		_set_graph_data("y_grid_interval", value)


var focus_label_offset := Vector2(10.0, -30.0)
var focus_label : Label
var focus_series : Series
var focus_point : int

var plot_rect_margin := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _x_distance : float = 1.0

var content_rect : Rect2
var plot_rect : Rect2

var _graph_data := {
	"x_categories": [], # Applies to all series.
	"y_max": 10.0,
	"y_min": 0.0,
	"y_grid_interval": 0.0,
	"series_dict": {},
}


var graph_rect_panel : PanelContainer
var graph_rect_plot : GraphRectPlot


func _ready() -> void:
	if use_default_theme:
		theme = load("res://addons/pa_graph_rect/graph_rect/graph_rect_theme.tres")

	graph_rect_panel = graph_rect_panel_scene.instantiate()
	graph_rect_panel.add_theme_stylebox_override("panel", get_theme_stylebox("background", THEME_TYPE))
	add_child(graph_rect_panel)

	_graph_data["y_grid_interval"] = y_grid_interval
	_graph_data["y_max"] = y_max
	_graph_data["y_min"] = y_min
	graph_rect_plot = graph_rect_panel.get_node("%Plot")
	graph_rect_plot.update_graph_data(_graph_data)
	graph_rect_plot.positions_changed.connect(_update_point_positions)

	focus_label = Label.new()
	focus_label.theme_type_variation = "TooltipLabel"
	focus_label.visible = false
	add_child(focus_label)

	_update_labels()
	_update_legend()


func _update_labels() -> void:
	if not graph_rect_panel:
		return

	var title_label := graph_rect_panel.get_node("%TitleLabel")
	if title_label:
		if title:
			title_label.text = title
			title_label.show()
		else:
			title_label.hide()

	var x_label := graph_rect_panel.get_node("%XAxisLabel")
	if x_label:
		if x_title:
			x_label.text = x_title
			x_label.show()
		else:
			x_label.hide()

	var y_label := graph_rect_panel.get_node("%YAxisLabel")
	if y_label:
		if y_title:
			y_label.text = y_title
			y_label.show()
		else:
			y_label.hide()


func _update_legend() -> void:
	var legend_container := graph_rect_panel.get_node("%LegendContainer")
	legend_container.add_theme_stylebox_override("panel", get_theme_stylebox("legend", THEME_TYPE))
	var grid_container := graph_rect_panel.get_node("%LegendGridContainer")
	for child in grid_container.get_children():
		child.queue_free()

	if not show_legend:
		legend_container.hide()
		return

	legend_container.show()

	for series : Series in _graph_data.series_dict.values():
		var label := Label.new()
		label.theme_type_variation = "GraphRectLegendLabel"
		label.text = series.display_name
		var line_height : int = label.get_line_height()

		var color_rect := ColorRect.new()
		color_rect.color = series.color
		color_rect.custom_minimum_size = Vector2(line_height, line_height)

		grid_container.add_child(color_rect)
		grid_container.add_child(label)


func _set_graph_data(p_key : String, p_value : Variant) -> void:
	assert(_graph_data.has(p_key))
	_graph_data[p_key] = p_value
	if graph_rect_plot:
		graph_rect_plot.update_graph_data(_graph_data)


# ---------------------------------------------------------------------------
# PUBLIC FUNCTIONS
# ---------------------------------------------------------------------------

func set_categories(p_x_categories : Array) -> void:
	_set_graph_data("x_categories", p_x_categories)


# Returns series id.
func add_series(
		p_display_name := "",
		p_color := Color.BLACK,
		p_line_style := LineStyle.SOLID,
		p_draw_points := true,
		p_id : int = -1,
	) -> int:

	var id := p_id
	if id == -1:
		id = 0
		while _graph_data.series_dict.has(id):
			id += 1
	elif _graph_data.series_dict.has(id):
		push_error("ID already exists: %s" % id)
		return INVALID_ID

	var series := Series.new(p_display_name, p_color, p_line_style, p_draw_points)
	_graph_data.series_dict[id] = series
	graph_rect_plot.update_graph_data(_graph_data)
	_update_legend()
	return id


func add_values(p_id : int, p_dict : Dictionary) -> void:
	var series : Series = _graph_data.series_dict.get(p_id, null)
	if not series:
		push_error("No series with id: %s" % p_id)
		return

	for category in p_dict:
		var category_idx : int = _graph_data.x_categories.find(category)
		if category_idx == -1:
			push_error("No category found for %s" % category)
			continue

		var y_value : float = p_dict[category]
		var pos := Vector2(
				graph_rect_plot.get_x_pos(category_idx),
				graph_rect_plot.get_y_pos(y_value),
		)
		series.add_point(category_idx, y_value, pos)

	graph_rect_plot.update_graph_data(_graph_data)
	queue_redraw()



func _update_point_positions() -> void:
	for series : Series in _graph_data.series_dict.values():
		for i in series.size():
			series.positions[i] = Vector2(
					graph_rect_plot.get_x_pos(series.categories[i]),
					graph_rect_plot.get_y_pos(series.y_values[i])
			)
