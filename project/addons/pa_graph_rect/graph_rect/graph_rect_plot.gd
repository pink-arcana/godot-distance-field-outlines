class_name GraphRectPlot
extends Control

signal setup_completed
signal positions_changed
signal focus_point_changed(series : GraphRect.Series, point : int)

const THEME_TYPE := "GraphRect"

var _mouse_focus_radius := 30.0

var _graph_data : Dictionary
var _canvas_data : Dictionary

var _x_distance : float
var _x_label_offset : float
var _y_label_offset : float
var _axis_label_height : float

var _focus_series : GraphRect.Series = null
var _focus_point : int = -1

var _plot_rect : Rect2

var setup_complete := false :
	set(value):
		if setup_complete == value:
			return
		setup_complete = value
		if value:
			setup_completed.emit()


func _ready() -> void:
	_update_canvas_data.call_deferred()
	mouse_entered.connect(set_process.bind(true))
	mouse_exited.connect(set_process.bind(false))
	resized.connect(_update_alignments)


func update_graph_data(p_graph_data : Dictionary) -> void:
	_graph_data = p_graph_data
	_update_alignments()
	queue_redraw()


func _update_canvas_data() -> void:
	_canvas_data.plot_stylebox = get_theme_stylebox(&"plot", THEME_TYPE)
	_canvas_data.grid_color = get_theme_color(&"grid", THEME_TYPE)
	_canvas_data.grid_width = get_theme_constant(&"grid_width", THEME_TYPE)
	_canvas_data.axis_color = get_theme_color(&"axis", THEME_TYPE)
	_canvas_data.axis_width = get_theme_constant(&"axis_width", THEME_TYPE)
	_canvas_data.axis_label_color = get_theme_color(&"axis_label", THEME_TYPE)
	_canvas_data.axis_label_font = get_theme_font(&"axis_label", THEME_TYPE)
	_canvas_data.axis_label_font_size = get_theme_font_size(&"axis_label", THEME_TYPE)
	_canvas_data.axis_tick_size = get_theme_constant(&"axis_tick_size", THEME_TYPE)
	_canvas_data.series_width = get_theme_constant(&"series_width", THEME_TYPE)
	_canvas_data.series_dash_size = get_theme_constant(&"series_dash_size", THEME_TYPE)

	# Distance between plot and labels, and plot/labels and edge of panel.
	# X and Y values refer to the coordinates.
	_canvas_data.plot_margin = Vector2(10.0,10.0)

	# Extra pixels padding the end of the X and Y axes.
	# X and Y values refer to the axis.
	_canvas_data.plot_extension = Vector2(100.0, 25.0)

	_update_alignments()
	queue_redraw()

	setup_complete = true


# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _graph_data:
		return

	var mouse_pos = get_local_mouse_position()
	var next_focus_series : GraphRect.Series = null
	var next_focus_point : int = -1
	var min_dist : float = INF

	var max_dist := _mouse_focus_radius ** 2

	for series : GraphRect.Series in _graph_data.series_dict.values():
		if not series.draw_points:
			continue

		for i in series.size():
			var pos : Vector2 = series.positions[i]
			var dist := pos.distance_squared_to(mouse_pos)
			if dist < minf(min_dist, max_dist):
				min_dist = dist
				next_focus_series = series
				next_focus_point = i

	if _focus_series != next_focus_series || _focus_point != next_focus_point:
		_focus_series = next_focus_series
		_focus_point = next_focus_point
		focus_point_changed.emit(_focus_series, _focus_point)
		queue_redraw()


# ---------------------------------------------------------------------------

func _draw() -> void:
	if not setup_complete:
		return

	var rect := _plot_rect
	draw_style_box(_canvas_data.plot_stylebox, _plot_rect)

	#region Draw plot

	for i in _graph_data.x_categories.size():
		var x_pos := get_x_pos(i)

		# grid line
		draw_line(
				Vector2(x_pos, _plot_rect.position.y),
				Vector2(x_pos, _plot_rect.end.y),
				_canvas_data.grid_color,
				_canvas_data.grid_width,
		)

		# axis ticks
		# Will be underneath axis lines, but since they use the same color/width,
		# this is okay.
		draw_line(
				Vector2(x_pos, _plot_rect.end.y - _canvas_data.axis_tick_size/2.0),
				Vector2(x_pos, _plot_rect.end.y + _canvas_data.axis_tick_size/2.0),
				_canvas_data.axis_color,
				_canvas_data.axis_width,
		)

		# axis labels
		var text := str(_graph_data.x_categories[i])
		var alignment := HORIZONTAL_ALIGNMENT_CENTER
		var width := _x_distance

		var text_pos := Vector2(
				x_pos - width/2.0,
				_plot_rect.end.y + _canvas_data.plot_margin.x + _axis_label_height,
		)

		draw_string(
				_canvas_data.axis_label_font,
				text_pos,
				text,
				alignment,
				width,
				_canvas_data.axis_label_font_size,
				get_theme_color(&"axis_label", THEME_TYPE),
		)


	var y_grid_count := ceili(float(_graph_data.y_max - _graph_data.y_min) \
			/_graph_data.y_grid_interval) + 1

	for i in y_grid_count:
		var y_value : float = i * _graph_data.y_grid_interval
		var y_pos : float = get_y_pos(y_value)

		# grid line
		draw_line(
				Vector2(rect.position.x, y_pos),
				Vector2(rect.end.x, y_pos),
				_canvas_data.grid_color,
				_canvas_data.grid_width,
		)

		# axis tick
		draw_line(
				Vector2(rect.position.x - _canvas_data.axis_tick_size/2.0, y_pos),
				Vector2(rect.position.x + _canvas_data.axis_tick_size/2.0, y_pos),
				_canvas_data.axis_color,
				_canvas_data.axis_width,
		)

		var text := str(y_value).pad_decimals(1)
		var alignment := HORIZONTAL_ALIGNMENT_RIGHT

		var text_pos := Vector2(
				rect.position.x - _y_label_offset,
				y_pos + (0.25 * _axis_label_height), # Why does it need 0.25 and not 0.5?
		)
		var width : float = _y_label_offset - (_canvas_data.plot_margin.x + _canvas_data.axis_tick_size/2.0)

		draw_string(
				_canvas_data.axis_label_font,
				text_pos,
				text,
				alignment,
				width,
				_canvas_data.axis_label_font_size,
				_canvas_data.axis_label_color,
		)

	# Draw axis lines on top of grid
	draw_line(
			Vector2(rect.position.x, rect.end.y),
			Vector2(rect.end.x, rect.end.y),
			_canvas_data.axis_color,
			_canvas_data.axis_width,
	)

	draw_line(
			Vector2(rect.position.x, rect.end.y),
			Vector2(rect.position.x, rect.position.y),
			_canvas_data.axis_color,
			_canvas_data.axis_width,
	)

	#endregion

	#region Draw series
	for series : GraphRect.Series in _graph_data.series_dict.values():
		var positions := series.positions
		if positions.size() < 2:
			continue

		match series.line_style:
			GraphRect.LineStyle.SOLID:
				draw_polyline(
						series.positions,
						series.color,
						_canvas_data.series_width,
						true,
				)
			GraphRect.LineStyle.DASHED:
				for i in (series.size() - 1):
					draw_dashed_line(
							series.positions[i],
							series.positions[i+1],
							series.color,
							_canvas_data.series_width * 2.0,
							_canvas_data.series_dash_size,
							true,
							false,
					)

		if not series.draw_points:
			continue

		for i in series.size():
			var point_color := series.color
			var pos := series.positions[i]
			var point_radius : float = _canvas_data.series_width * 2.0

			if series == _focus_series && i == _focus_point:
				# Draw white outline circle first
				point_color = Color.WHITE
				draw_circle(pos, point_radius + 4.0, series.color, true, -1, true)

			draw_circle(pos, point_radius, point_color, true, -1, true)

	#endregion




func _update_alignments() -> void:
	if _canvas_data.is_empty() or _graph_data.is_empty():
		return

	var y_label_size : Vector2 = _canvas_data.axis_label_font.get_string_size(
			str(_graph_data.y_max).pad_decimals(1),
			HORIZONTAL_ALIGNMENT_RIGHT,
			-1,
			_canvas_data.axis_label_font_size,
	)

	_axis_label_height = y_label_size.y

	_y_label_offset = y_label_size.x + _canvas_data.plot_margin.x + _canvas_data.axis_tick_size/2.0
	_x_label_offset = _axis_label_height + _canvas_data.plot_margin.x + _canvas_data.axis_tick_size/2.0

	var plot_position := Vector2(
			_canvas_data.plot_margin.x + _y_label_offset,
			_canvas_data.plot_margin.y,
	)

	var plot_size := Vector2(
			get_rect().size.x - (plot_position.x + _canvas_data.plot_margin.x),
			get_rect().size.y - (plot_position.y + _canvas_data.plot_margin.y + _x_label_offset),
	)

	_plot_rect = Rect2(
			plot_position,
			plot_size,
	)

	# Will change when category count changes and when plot size changes.
	# NOTE: This only works for categories that start at 0.
	_x_distance = floorf((_plot_rect.size.x - _canvas_data.plot_extension.x) \
			/ (_graph_data.x_categories.size() - 1.0))

	positions_changed.emit()


func get_x_pos(p_category_idx : int) -> float:
	if _canvas_data.is_empty() or _graph_data.is_empty():
		return -1.0
	return _plot_rect.position.x + (p_category_idx * _x_distance)


func get_y_pos(p_value : float) -> float:
	if _canvas_data.is_empty() or _graph_data.is_empty():
		return -1.0

	var value_n : float = (p_value - float(_graph_data.y_min)) \
			/ float(_graph_data.y_max - _graph_data.y_min)
	return _plot_rect.end.y - ((_plot_rect.size.y - _canvas_data.plot_extension.y) * value_n)
