@tool
extends Node

const EXTRACTION_SHADER_PATH := "res://df_outline_node/extraction.gdshader"
const JF_PASS_SHADER_PATH := "res://df_outline_node/jf_pass.gdshader"
const OVERLAY_SHADER_PATH := "res://df_outline_node/overlay.gdshader"

const DEPTH_SHADER_PATH := "res://df_outline_node/sub_viewports/spatial_depth_next_pass.gdshader"

const DEBUG_PRINT_DISPLAY_SIZES := false

## Delay in seconds between detecting a screen size change and
## updating node tree. Prevents lag when the user
## is resizing the window.
const RESIZE_DELAY : float = 0.25

## Delay in seconds between changing outline width and
## updating the node tree. Prevents errors from adding layers
## that are already entering the tree.
const WIDTH_CHANGE_DELAY : float = 0.1

const LAYER : String = "LAYER"
const SHADER_MATERIAL : String = "SHADER_MATERIAL"

@export var enabled : bool = true :
	set(value):
		if enabled == value:
			return
		enabled = value
		_update_layers()

@export var scene_camera : Camera3D :
	set(value):
		scene_camera = value
		update_configuration_warnings()
		if scene_camera:
			_setup_viewports()


@export_flags_3d_render var color_render_layers : int = 1 : # Layer 1
	set(value):
		color_render_layers = value
		update_configuration_warnings()
		_setup_viewports()


@export_flags_3d_render var depth_render_layer : int = 524288  : # Layer 20
	set(value):
		depth_render_layer = value
		update_configuration_warnings()
		_setup_viewports()

## Assigns a transparent material to the overlay slot of all MeshInstance3Ds
## in the current scene that renders the depth
## to depth_render_layer. Allows depth fade in Compatibility mode.
@export var assign_depth_materials : bool = true

@export var canvas_layer_start : int = 100

@export var outline_settings : DFOutlineSettings :
	set(value):
		outline_settings = value
		_setup_outline_settings()


@export_subgroup("Debug")
@export var print_jfa_updates : bool = false :
	set(value):
		print_jfa_updates = value
		if jf_calc:
			jf_calc.debug_print_values = print_jfa_updates

@export var preview_color_input : bool = false
@export var preview_depth_input : bool = false

# Using load to avoid preload errors in the editor.
var extraction_shader := load(EXTRACTION_SHADER_PATH)
var jf_pass_shader := load(JF_PASS_SHADER_PATH)
var overlay_shader := load(OVERLAY_SHADER_PATH)

var depth_shader := load(DEPTH_SHADER_PATH)

var _render_size : Vector2i
var _control_size : Vector2i

var jf_calc : JFCalculator

## Used for calculating the min outline distance
## when we are modulating outlines by depth.
## Has no effect on JFA passes.
var min_jf_calc : JFCalculator

var _color_rects : Array[ColorRect]
var _jf_pass_layers := {} # {offset (int) : layer (CanvasLayer)}
var _jf_pass_materials := {} # {offset (int) : material}
var _extraction_material : ShaderMaterial
var _overlay_material : ShaderMaterial

var _depth_material : ShaderMaterial

var _layers_container : Node
var _resize_timer: Timer
var _width_change_timer : Timer

var _next_layer_idx : int = -1
var _resize_queued := false
var _width_change_queued := false

@onready var color_sub_viewport: DFNodeSubViewport = %ColorSubViewport
@onready var depth_sub_viewport: DFNodeSubViewport = %DepthSubViewport


func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	if not scene_camera:
		warnings.append("Scene camera must be assigned.")
	if color_render_layers & depth_render_layer:
		warnings.append("Color layers cannot contain the depth layer.")
	if color_render_layers == 0:
		warnings.append("Color layers must have at least one layer assigned.")
	if depth_render_layer == 0:
		warnings.append("Depth layer must have at least one layer assigned.")
	return warnings

# ---------------------------------------------------------------------------
# INITIAL SETUP
# ---------------------------------------------------------------------------
func _ready() -> void:
	if Engine.is_editor_hint():
		# Disable any functionality in editor besides config warnings.
		return

	_setup_timers()

	if not outline_settings:
		outline_settings = DFOutlineSettings.new()
	_setup_outline_settings()
	if assign_depth_materials:
		_assign_depth_materials()

	_setup_viewports()


func _setup_outline_settings() -> void:
	if not outline_settings.outline_width_changed.is_connected(_update_outline_width):
		outline_settings.outline_width_changed.connect(_update_outline_width)
	if not outline_settings.changed.is_connected(_update_shader_params):
		outline_settings.changed.connect(_update_shader_params)
	_update_outline_width()
	_update_shader_params()


func _assign_depth_materials() -> void:
	# We will set depth_max later, along with other shader uniforms,
	# since it may change.
	_depth_material = ShaderMaterial.new()
	_depth_material.shader = depth_shader
	_depth_material.set_shader_parameter("depth_layer", depth_render_layer)

	for mesh_instance : MeshInstance3D in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		mesh_instance.material_overlay = _depth_material


func _setup_viewports() -> void:
	if not scene_camera:
		printerr("[DFOutlineNode] No Scene Camera assigned.")
		return

	if not is_node_ready():
		return

	# Ensure that the color viewport doesn't render depth.
	if color_render_layers & depth_render_layer:
		push_error("[DFOutlineNode] Color layers cannot contain the depth layer.")
		return

	color_sub_viewport.setup(scene_camera, color_render_layers)

	# The depth viewport's camera must see both color and depth.
	var depth_camera_layers := depth_render_layer + color_render_layers
	depth_sub_viewport.setup(scene_camera, depth_camera_layers)

	# We will connect to root's signal because
	# it is the only viewport that will emit size_changed
	# when the content_scale_factor is changed.
	if not get_tree().root.size_changed.is_connected(_on_Root_size_changed):
		get_tree().root.size_changed.connect(_on_Root_size_changed)

	_update_layers()


func _setup_timers() -> void:
	_resize_timer = Timer.new()
	_resize_timer.autostart = false
	_resize_timer.one_shot = true
	_resize_timer.timeout.connect(_on_ResizeTimer_timeout)
	add_child(_resize_timer)

	_width_change_timer = Timer.new()
	_width_change_timer.autostart = false
	_width_change_timer.one_shot = true
	_width_change_timer.timeout.connect(_on_WidthChangeTimer_timeout)
	add_child(_width_change_timer)


func _on_Root_size_changed() -> void:
	# If no timer is set, we will re-create our nodes immediately
	# to avoid lag. In _update_layers(), we will then start _resize_timer
	# to prevent frequent updates.
	if _resize_timer.is_stopped():
		_update_layers()
	else:
		_resize_queued = true


func _on_ResizeTimer_timeout() -> void:
	# If no resize is queued, we can ignore the timeout.
	if _resize_queued:
		_resize_queued = false
		_update_layers()




# ---------------------------------------------------------------------------
# LAYER CREATION
# ---------------------------------------------------------------------------

func _clear_layers() -> void:
	# Freeing their container will free all the CanvasLayer
	# and control nodes we've created.
	if _layers_container:
		_layers_container.queue_free()

	_color_rects.clear()
	_jf_pass_layers.clear()
	_jf_pass_materials.clear()
	_extraction_material = null
	_overlay_material = null
	jf_calc = null
	min_jf_calc = null

	_next_layer_idx = -1


# We call _update_layers() when the node is ready,
# and any time the viewport size or content scale factor is changed.
func _update_layers() -> void:
	if not _resize_timer:
		print("no resize timer")
		return

	_resize_timer.start(RESIZE_DELAY)

	if not is_node_ready() or Engine.is_editor_hint():
		return

	_clear_layers()
	if not enabled:
		return

	if not extraction_shader or not jf_pass_shader or not overlay_shader:
		printerr("[DFOutlineNode] Unable to load one or more shaders.")
		return

	if not scene_camera:
		printerr("[DFOutlineNode] No Scene Camera assigned.")
		return

	_layers_container = Node.new()

	add_child(_layers_container)

	if DEBUG_PRINT_DISPLAY_SIZES:
		print("[DFOutlineNode] Display sizes:")
		prints("scene_camera.get_viewport().size", scene_camera.get_viewport().size)
		prints("color_sub_viewport.size", color_sub_viewport.size)
		prints("root.size", get_tree().root.size)
		prints("root.content_scale_size", get_tree().root.content_scale_size)
		prints("root.content_scale_factor", get_tree().root.content_scale_factor)
		print()

	# If our window is the same size as the viewport width/height in
	# Project Settings, _render_size == _control_size.
	# If our window is resized, _render_size will reflect the actual displayed size,
	# but our initial control size will remain the same as the viewport size
	# in Project Settings.
	_render_size = color_sub_viewport.get_size()
	_control_size = get_tree().root.content_scale_size

	# In this project, we are using content_scale_factor to resize the UI.
	# But we want our post-processing layers to act like the 3D viewports
	# and remain unchanged. So we need to adjust the _control_size
	# for the content_scale_factor.
	#
	# (We will also set the color rects layouts to full rect
	# when we instantiate them.)
	var content_scale_factor := get_tree().root.content_scale_factor
	_control_size = _control_size/content_scale_factor

	jf_calc = JFCalculator.new(JFCalculator.EXPAND_SYMMETRICALLY)
	jf_calc.debug_print_values = print_jfa_updates
	jf_calc.set_outline_width(outline_settings.outline_width, outline_settings.viewport_size)
	jf_calc.set_render_size(_render_size)

	min_jf_calc = JFCalculator.new(JFCalculator.EXPAND_SYMMETRICALLY)
	min_jf_calc.debug_print_values = false
	min_jf_calc.set_outline_width(outline_settings.min_outline_width, outline_settings.viewport_size)
	min_jf_calc.set_render_size(_render_size)

	_add_extraction_layer()
	_add_jfa_layers()
	_add_overlay_layer()

	_update_shader_params()
	_update_jf_pass_layer_visibility()


func _add_extraction_layer() -> void:
	var layer_nodes : Dictionary = _add_post_process_layer(
			"Extraction",
			load(EXTRACTION_SHADER_PATH),
		)
	_extraction_material = layer_nodes[SHADER_MATERIAL]


func _add_jfa_layers() -> void:
	var step_offsets : PackedInt32Array = jf_calc.get_all_step_offsets()

	# Starts at greatest offset, then goes to smallest offset.
	# We will create layers for every offset based on our render size.
	# Later, we will remove the layers from the tree
	# that aren't needed for our outline size.
	for i in step_offsets.size():
		var offset : int = step_offsets[i]
		var last_pass := (i == step_offsets.size() - 1)

		var layer_nodes : Dictionary = _add_post_process_layer(
				"JFPass",
				jf_pass_shader,
			)

		_jf_pass_layers[offset] = layer_nodes[LAYER]
		_jf_pass_materials[offset] = layer_nodes[SHADER_MATERIAL]

		_set_shader_params(
			layer_nodes[SHADER_MATERIAL],
			{
				"offset": offset,
				"last_pass": last_pass,
				"depth_texture": depth_sub_viewport.get_texture() if depth_sub_viewport && last_pass else null,
			},
		)


func _add_overlay_layer() -> void:
	var layer_nodes : Dictionary = _add_post_process_layer(
			"Overlay",
			load(OVERLAY_SHADER_PATH),
		)
	_overlay_material = layer_nodes[SHADER_MATERIAL]


func _add_post_process_layer(
	p_name : String,
	p_shader : Shader) -> Dictionary:

	var layer : Node = CanvasLayer.new()
	layer.name = "%sLayer" % p_name
	layer.layer = _get_next_layer_idx()

	var control : Control
	control = ColorRect.new()

	# MOUSE_FILTER_IGNORE allows our mouse events to get to the 3D scene.
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.custom_minimum_size = _control_size
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.material = ShaderMaterial.new()
	control.material.shader = p_shader
	control.material.shader.resource_local_to_scene = true

	_color_rects.append(control)

	layer.ready.connect(layer.add_child.bind(control, true))

	_layers_container.add_child(layer, true)

	return {
			LAYER : layer,
			SHADER_MATERIAL : control.material,
	}


func _get_next_layer_idx() -> int:
	if _next_layer_idx == -1:
		_next_layer_idx = canvas_layer_start
	var prev_layer_idx := _next_layer_idx
	_next_layer_idx += 1
	return prev_layer_idx


# ---------------------------------------------------------------------------
# UPDATES
# ---------------------------------------------------------------------------

func _update_outline_width() -> void:
	if not is_node_ready() or not jf_calc:
		return

	if not _width_change_timer.is_stopped():
		_width_change_queued = true
		return

	# Prevent errors due to execution before timer is in tree.
	if _width_change_timer.is_inside_tree():
		_width_change_timer.start(WIDTH_CHANGE_DELAY)

	jf_calc.set_outline_width(outline_settings.outline_width, outline_settings.viewport_size)
	min_jf_calc.set_outline_width(outline_settings.min_outline_width, outline_settings.viewport_size)
	_update_jf_pass_layer_visibility()
	_update_shader_params()


# We will call _update_jf_pass_layer_visibility() after the layers are created,
# and any time the outline width is changed.
func _update_jf_pass_layer_visibility() -> void:
	var steps := jf_calc.get_step_offsets()

	for offset in _jf_pass_layers:
		var layer : CanvasLayer = _jf_pass_layers[offset]
		if not offset in steps:
			layer.hide()
			if layer.is_inside_tree():
				_layers_container.remove_child(layer)
		else:
			layer.show()
			if not layer.is_inside_tree():
				_layers_container.add_child(layer)
				_layers_container.move_child(layer, steps.find(offset) + 1)


# We will call _update_shader_params() after the layers are created,
# and any time a relevant setting is changed.
func _update_shader_params() -> void:
	if not is_node_ready():
		return

	if depth_sub_viewport:
		if outline_settings.depth_fade_mode == DFOutlineSettings.DepthFadeMode.NONE:
			depth_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		else:
			depth_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if _depth_material:
			_depth_material.set_shader_parameter("depth_max", outline_settings.depth_fade_end)

	if _extraction_material:
		_set_shader_params(
				_extraction_material,
				{
					"color_texture": color_sub_viewport.get_texture(),
					"sobel_threshold": outline_settings.sobel_threshold,
				},
			)

	for material in _jf_pass_materials.values():
		# Other JF Pass uniforms (offset, last_pass) are set when the layers are
		# created, and do not need to be updated again.
		_set_shader_params(
			material,
			{
				"distance_denominator": jf_calc.get_distance_denominator(),
			},
		)

	if _overlay_material:
		_set_shader_params(
				_overlay_material,
				{
					"color_texture": color_sub_viewport.get_texture(),
					"input_outline_distance": jf_calc.get_outline_distance(),
					"distance_denominator": jf_calc.get_distance_denominator(),
					"input_outline_color": outline_settings.outline_color,
					"background_color": outline_settings.background_color,
					"use_background_color": outline_settings.use_background_color,
					"depth_fade_mode": outline_settings.depth_fade_mode,
					"depth_fade_start": outline_settings.depth_fade_start,
					"depth_fade_end": outline_settings.depth_fade_end,
					"min_outline_alpha": outline_settings.min_outline_alpha,
					"min_outline_distance": min_jf_calc.get_outline_distance(),
					"effect_id": outline_settings.outline_effect,
					"smoothing_distance": outline_settings.smoothing_distance,
				},
			)


func _set_shader_params(p_material : ShaderMaterial, p_params : Dictionary) -> void:
	for param in p_params:
		var value = p_params.get(param, null)
		if value is ViewportTexture:
			p_material.resource_local_to_scene = true
		p_material.set_shader_parameter(param, value)


func _on_WidthChangeTimer_timeout() -> void:
	if _width_change_queued:
		_width_change_queued = false
		_update_outline_width()
