@tool
class_name DFOutlineCE
extends BaseCompositorEffect

const EXTRACTION_SHADER_PATH := "res://df_outline_ce/shaders/extraction.glsl"
const JF_PASS_SHADER_PATH := "res://df_outline_ce/shaders/jf_pass.glsl"
const OVERLAY_SHADER_PATH := "res://df_outline_ce/shaders/overlay.glsl"

## Also update #define DEBUG in glsl shaders.
const USE_DEBUG_IMAGE = false

# Set 1 bindings
const DF_DATA_UBO_BINDING := 0
const DEBUG_IMAGE_BINDING := 1

# Set 2 bindings
const JF_IN_IMAGE_BINDING := 0
const JF_OUT_IMAGE_BINDING := 1
const DEPTH_IMAGE_BINDING := 2
const DF_IMAGE_BINDING := 3

# Specialization constant bindings
const JF_CONSTANT_OFFSET : int = 0
const JF_CONSTANT_LAST_PASS : int = 1
const JF_CONSTANT_DEPTH_FADE : int = 2
const OVERLAY_CONSTANT_EFFECT_ID : int = 0
const OVERLAY_CONSTANT_DEPTH_FADE : int = 1
const EXTRACTION_CONSTANT_METHOD_ID : int = 0
const EXTRACTION_CONSTANT_DEPTH_FADE : int = 1


@export var outline_settings : DFOutlineSettings :
	set(value):
		outline_settings = value
		setup_outline_settings()

@export_subgroup("DF Debug")
@export var print_jfa_updates : bool = false :
	set(value):
		print_jfa_updates = value
		if jf_calc:
			jf_calc.debug_print_values = print_jfa_updates


var context : StringName = "DFOutlineCE"

var texture_a : StringName = "TextureA"
var texture_a_in_image_uniform : RDUniform
var texture_a_out_image_uniform : RDUniform

var texture_b : StringName = "TextureB"
var texture_b_in_image_uniform : RDUniform
var texture_b_out_image_uniform : RDUniform

var depth_texture : StringName = "DepthTexture"
var depth_image_uniform : RDUniform

var df_texture : StringName = "DFTexture"
var df_image_uniform : RDUniform

var debug_texture : StringName = "DebugTexture"
var debug_image_uniform : RDUniform

var df_data_ubo : RID
var df_data_ubo_uniform : RDUniform

var extraction_shader : RID
var extraction_pipeline : RID
var jf_pass_shader : RID
var jf_pass_pipelines := {} # {offset int : pipeline RID}
var overlay_shader : RID
var overlay_pipeline : RID

var jf_calc : JFCalculator

# Used for calculating the min outline distance.
# It has no effect on JFA passes.
var min_jf_calc : JFCalculator

var settings_dirty := false

# Called from _init().
func _initialize_resource() -> void:
	if not outline_settings:
		outline_settings = DFOutlineSettings.new()
	setup_outline_settings()

	jf_calc = JFCalculator.new(JFCalculator.EXPAND_SYMMETRICALLY)
	jf_calc.debug_print_values = print_jfa_updates
	min_jf_calc = JFCalculator.new(JFCalculator.EXPAND_SYMMETRICALLY)
	min_jf_calc.debug_print_values = false
	update_jf_calcs()

	access_resolved_color = true
	access_resolved_depth = true
	needs_normal_roughness = true


# Called on render thread after _init().
func _initialize_render() -> void:
	# Pipelines will have specialization constants attached,
	# so we will create them later.
	extraction_shader = create_shader(EXTRACTION_SHADER_PATH)
	jf_pass_shader = create_shader(JF_PASS_SHADER_PATH)
	overlay_shader = create_shader(OVERLAY_SHADER_PATH)


# Called at beginning of _render_callback(), after updating/validating rd references.
# Use this function to setup textures or uniforms that do not depend on the view.
func _render_setup() -> void:
	if not df_data_ubo.is_valid() or settings_dirty:
		create_global_uniform_buffer()
		create_extraction_pipeline()
		create_overlay_pipeline()

	if not rd.compute_pipeline_is_valid(overlay_pipeline):
		create_overlay_pipeline()

	if not rd.compute_pipeline_is_valid(extraction_pipeline):
		create_extraction_pipeline()

	if not render_scene_buffers.has_texture(context, texture_a):
		create_textures()


# Called for each view. Setup uniforms that depend on view,
# and run compute shaders from here.
func _render_view(p_view : int) -> void:
	var scene_uniform_set : Array[RDUniform] = get_scene_uniform_set(p_view)
	var df_uniform_set : Array[RDUniform] = [df_data_ubo_uniform]
	if USE_DEBUG_IMAGE:
		df_uniform_set.append(debug_image_uniform)

	var uniform_sets : Array[Array]

	# EXTRACTION PASS
	uniform_sets = [
		scene_uniform_set,
		df_uniform_set,
		[texture_a_out_image_uniform, depth_image_uniform],
	]

	run_compute_shader(
		"DF: Extraction",
		extraction_shader,
		extraction_pipeline,
		uniform_sets,
	)

	# JUMP FLOODING PASSES
	var in_image_uniform : RDUniform = texture_a_in_image_uniform
	var out_image_uniform : RDUniform = texture_b_out_image_uniform

	var step_offsets : PackedInt32Array = jf_calc.get_step_offsets()

	for i in step_offsets.size():
		var offset : int = step_offsets[i]
		var pipeline : RID = jf_pass_pipelines.get(offset, RID())
		if not pipeline.is_valid():
			printerr("No valid JF pass pipeline found for offset: %s" % offset)
			continue

		uniform_sets = [
			scene_uniform_set,
			df_uniform_set,
			[in_image_uniform, out_image_uniform, depth_image_uniform, df_image_uniform],
		]

		run_compute_shader(
			"DF: Jump Flooding - %spx" % offset,
			jf_pass_shader,
			pipeline,
			uniform_sets,
		)

		# Swap the textures at end of each pass.
		if out_image_uniform == texture_a_out_image_uniform:
			in_image_uniform = texture_a_in_image_uniform
			out_image_uniform = texture_b_out_image_uniform
		else:
			in_image_uniform = texture_b_in_image_uniform
			out_image_uniform = texture_a_out_image_uniform


	# OVERLAY PASS
	uniform_sets = [
		scene_uniform_set,
		df_uniform_set,
		[df_image_uniform],
	]

	run_compute_shader(
		"DF: Overlay",
		overlay_shader,
		overlay_pipeline,
		uniform_sets,
	)


# ---------------------------------------------------------------------------


func _render_size_changed() -> void:
	# Clear all textures under this context.
	# This will trigger creation of new textures.
	render_scene_buffers.clear_context(context)
	make_settings_dirty()

	var _changed = jf_calc.set_render_size(render_size)
	_changed = min_jf_calc.set_render_size(render_size)

	update_jf_pass_pipelines()


func setup_outline_settings() -> void:
	if not outline_settings.changed.is_connected(make_settings_dirty):
		outline_settings.changed.connect(make_settings_dirty)
	if not outline_settings.outline_width_changed.is_connected(update_jf_calcs):
		outline_settings.outline_width_changed.connect(update_jf_calcs)
	if not outline_settings.depth_fade_mode_changed.is_connected(reset_jf_pass_pipelines):
		outline_settings.depth_fade_mode_changed.connect(reset_jf_pass_pipelines)
	update_jf_calcs()


func update_jf_calcs() -> void:
	if jf_calc:
		jf_calc.set_outline_width(outline_settings.outline_width, outline_settings.viewport_size)
	if min_jf_calc:
		min_jf_calc.set_outline_width(outline_settings.min_outline_width, outline_settings.viewport_size)
	settings_dirty = true


func reset_jf_pass_pipelines() -> void:
	jf_pass_pipelines.clear()
	update_jf_pass_pipelines()


func update_jf_pass_pipelines() -> void:
	var step_offsets := jf_calc.get_all_step_offsets()
	for i in step_offsets.size():
		var offset : int = step_offsets[i]
		var last_pass : bool = (i == step_offsets.size() - 1)
		if not jf_pass_pipelines.has(offset):
			create_jf_pass_pipeline(offset, last_pass)


func create_extraction_pipeline() -> void:
	if rd.compute_pipeline_is_valid(extraction_pipeline):
		rd.free_rid(extraction_pipeline)

	extraction_pipeline = create_pipeline(
			extraction_shader,
			{
				EXTRACTION_CONSTANT_METHOD_ID : 0, # TODO
				EXTRACTION_CONSTANT_DEPTH_FADE : outline_settings.depth_fade_mode as int,
			}
	)


func create_jf_pass_pipeline(p_offset : int, p_last_pass : bool) -> void:
	var prev_pipeline : RID = jf_pass_pipelines.get(p_offset, RID())
	if rd.compute_pipeline_is_valid(prev_pipeline):
		rd.free_rid(prev_pipeline)

	jf_pass_pipelines[p_offset] = create_pipeline(
			jf_pass_shader,
			{
				JF_CONSTANT_OFFSET : p_offset,
				JF_CONSTANT_LAST_PASS : p_last_pass,
				JF_CONSTANT_DEPTH_FADE : outline_settings.depth_fade_mode as int,
			}
	)


func create_overlay_pipeline() -> void:
	if rd.compute_pipeline_is_valid(overlay_pipeline):
		rd.free_rid(overlay_pipeline)

	overlay_pipeline = create_pipeline(
			overlay_shader,
			{
				OVERLAY_CONSTANT_EFFECT_ID : outline_settings.outline_effect as int,
				OVERLAY_CONSTANT_DEPTH_FADE : outline_settings.depth_fade_mode as int,
			}
	)


func create_global_uniform_buffer() -> void:
	if df_data_ubo.is_valid():
		free_rid(df_data_ubo)

	# IMPORTANT: Order must match DFOutlineData UBO layouts in the glsl shaders.
	# Vector4's must come first or they get misaligned
	# if the smaller 4-byte variables are not in groups of 4 (16 bytes).
	var data : Array = [
			outline_settings.outline_color, # vec4
			outline_settings.background_color, # vec4

			jf_calc.get_outline_distance(), # float
			jf_calc.get_distance_denominator(), # float

			outline_settings.use_background_color, # bool

			outline_settings.sobel_threshold, # float

			outline_settings.depth_fade_start, # float
			outline_settings.depth_fade_end, # float
			outline_settings.min_outline_alpha, # float
			minf(min_jf_calc.get_outline_distance(), jf_calc.get_outline_distance()), # float

			outline_settings.smoothing_distance, # float
	]

	df_data_ubo = create_uniform_buffer(data)
	df_data_ubo_uniform = get_uniform_buffer_uniform(df_data_ubo, DF_DATA_UBO_BINDING)
	settings_dirty = false


func create_textures() -> void:
	const JF_TEXTURE_FORMAT := RenderingDevice.DATA_FORMAT_R16G16_UINT

	var texture_a_image : RID = create_simple_texture(
			context,
			texture_a,
			JF_TEXTURE_FORMAT,
	)
	texture_a_in_image_uniform = get_image_uniform(
			texture_a_image,
			JF_IN_IMAGE_BINDING,
	)
	texture_a_out_image_uniform = get_image_uniform(
			texture_a_image,
			JF_OUT_IMAGE_BINDING,
	)


	var texture_b_image : RID = create_simple_texture(
			context,
			texture_b,
			JF_TEXTURE_FORMAT,
	)
	texture_b_in_image_uniform = get_image_uniform(
			texture_b_image,
			JF_IN_IMAGE_BINDING,
	)
	texture_b_out_image_uniform = get_image_uniform(
			texture_b_image,
			JF_OUT_IMAGE_BINDING,
	)


	var depth_image : RID = create_simple_texture(
		context,
		depth_texture,
		RenderingDevice.DATA_FORMAT_R16_UNORM,
	)
	depth_image_uniform = get_image_uniform(depth_image, DEPTH_IMAGE_BINDING)


	var df_image : RID = create_simple_texture(
		context,
		df_texture,
		RenderingDevice.DATA_FORMAT_R16G16_UNORM,
	)
	df_image_uniform = get_image_uniform(df_image, DF_IMAGE_BINDING)



	# DEBUG TEXTURE
	if USE_DEBUG_IMAGE:
		var debug_texture_image : RID = create_simple_texture(
				context,
				debug_texture,
				RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
				RenderingDevice.TEXTURE_USAGE_STORAGE_BIT,
			)

		debug_image_uniform = get_image_uniform(debug_texture_image, DEBUG_IMAGE_BINDING)


func make_settings_dirty() -> void:
	settings_dirty = true
