@tool
class_name DFOutlineCE
extends CompositorEffect


const EXTRACTION_SHADER_PATH := "res://df_outline_ce/extraction.glsl"
const JF_PASS_SHADER_PATH := "res://df_outline_ce/jf_pass.glsl"
const OVERLAY_SHADER_PATH := "res://df_outline_ce/overlay.glsl"

const JF_CONSTANT_OFFSET : int = 0
const JF_CONSTANT_LAST_PASS : int = 1
const OVERLAY_CONSTANT_EFFECT_ID : int = 0
const OVERLAY_CONSTANT_DEPTH_FADE : int = 1

const LOCAL_WORKGROUP_SIZE : int = 16

@export var outline_settings : DFOutlineSettings :
	set(value):
		outline_settings = value
		setup_outline_settings()

@export_subgroup("Debug")
@export var print_jfa_updates : bool = false :
	set(value):
		print_jfa_updates = value
		if jf_calc:
			jf_calc.debug_print_values = print_jfa_updates

## Reports when the UBO or push constant is resized to meet layout requirements.
## This tells us how much reserved data we need to allocate
## in our GLSL shaders.
@export var print_buffer_resize : bool = false

var rd : RenderingDevice

var context : StringName = "DFOutlineCE"
var texture : StringName = "texture"
var pong_texture : StringName = "pongtexture"

var global_uniform_buffer : RID
var nearest_sampler : RID
var linear_sampler : RID
var extraction_shader : RID
var extraction_pipeline : RID
var jf_pass_shader : RID
var jf_pass_pipelines := {} # {offset int : pipeline RID}
var overlay_shader : RID
var overlay_pipeline : RID

var jf_calc : JFCalculator

# min_jf_calc is used for calculating the min outline distance
# when we are modulating distance by depth.
# We are using it only to avoid rewriting our outline-width-to-viewport-size
# normalizations. It has no effect on JFA passes.
var min_jf_calc : JFCalculator

var has_printed_push_constant_size := false
var has_printed_ubo_size := false

var global_uniform_buffer_dirty := false


func _init():
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
	RenderingServer.call_on_render_thread(_initialize_compute)


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		# Pipeline RIDs will be automatically freed
		# along with their shaders.
		var rids_to_cleanup : Array[RID]= [
			global_uniform_buffer,
			linear_sampler,
			nearest_sampler,
			extraction_shader,
			jf_pass_shader,
			overlay_shader,
		]

		for rid in rids_to_cleanup:
			if rid.is_valid():
				rd.free_rid(rid)


func _initialize_compute() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd:
		return

	#region Create samplers
	var sampler_state : RDSamplerState = RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	nearest_sampler = rd.sampler_create(sampler_state)

	sampler_state = RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler = rd.sampler_create(sampler_state)
	#endregion

	#region Create shaders
	var shader_file := load(EXTRACTION_SHADER_PATH)
	var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
	extraction_shader = rd.shader_create_from_spirv(shader_spirv)
	if extraction_shader.is_valid():
		extraction_pipeline = rd.compute_pipeline_create(extraction_shader)

	# JF pass and overlay pipelines will have constants attached,
	# so we will create them later.
	shader_file = load(JF_PASS_SHADER_PATH)
	shader_spirv = shader_file.get_spirv()
	jf_pass_shader = rd.shader_create_from_spirv(shader_spirv)

	shader_file = load(OVERLAY_SHADER_PATH)
	shader_spirv = shader_file.get_spirv()
	overlay_shader = rd.shader_create_from_spirv(shader_spirv)
	#endregion


func _render_callback(
		p_effect_callback_type : EffectCallbackType,
		p_render_data : RenderData,
	) -> void:

	if outline_settings.outline_width < 0.0001:
		# Stop here if we are not going to draw an outline.
		return

	if not rd or not p_effect_callback_type == effect_callback_type:
		return

	var render_scene_buffers : RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	var render_scene_data : RenderSceneDataRD = p_render_data.get_render_scene_data()

	if not render_scene_buffers or not render_scene_data:
		return

	#region Calculate render size, invocations and JF requirements
	var render_size : Vector2i = render_scene_buffers.get_internal_size()
	if render_size.x == 0 or render_size.y == 0:
		return

	var groups := Vector2i(
		ceil(((float(render_size.x) - 1) / LOCAL_WORKGROUP_SIZE) + 1),
		ceil(((float(render_size.y) - 1) / LOCAL_WORKGROUP_SIZE) + 1),
	)

	var render_size_changed := jf_calc.set_render_size(render_size)
	if render_size_changed:
		global_uniform_buffer_dirty = true
		var _changed := min_jf_calc.set_render_size(render_size)

		# Determine need to create JF pass pipelines here, rather than later in JF pass section,
		# since this code will only be executed if the render size changes,
		# rather than every frame.
		var step_offsets := jf_calc.get_all_step_offsets()
		for i in step_offsets.size():
			var offset : int = step_offsets[i]
			var last_pass : bool = (i == step_offsets.size() - 1)
			if not jf_pass_pipelines.has(offset):
				create_jf_pass_pipeline(offset, last_pass)
	#endregion

	#region Create global uniform buffer
	# On my desktop GPU, the global uniform buffer is highly performant,
	# and the variables function as constants for branching purposes.
	#
	# However, Arm warns that on their chips, UBO's are limited to 128 bytes (like push constants),
	# and uniforms cannot function as constants. To accommodate hardware like this,
	# we will prefer specialization constants for branching,
	# and use this buffer to store variables that will not cause branching.
	if not global_uniform_buffer.is_valid() or global_uniform_buffer_dirty:
		if global_uniform_buffer.is_valid():
			rd.free_rid(global_uniform_buffer)

		# Overlay pipeline depends on settings.
		update_overlay_pipeline()

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

		global_uniform_buffer = create_uniform_buffer(data)
		global_uniform_buffer_dirty = false

	if not rd.compute_pipeline_is_valid(overlay_pipeline):
		update_overlay_pipeline()
	#endregion

	#region Create texture buffers
	# On choosing texture formats:
	# 16-bit SFLOAT is not precise enough to store screen coords.
	# 32-bit SFLOAT is, but is slower.
	# 16-bit UNORM is, and is faster than 32-bit SFLOAT.
	# From DFOutlineNode, we know that, if the coords are integers,
	# a 3-channel 8-bit UNORM is also sufficient up to certain screen sizes.
	#
	# A 16-bit SNORM would allow us to store invalid UVs as negative numbers.
	# However, mapping UVs to [0,1.0] in SNORM decreased precision.
	# UNORM with UVs mapped to [0,0.99] (with 1.0 to indicate invalid)
	# seems to preserve adequate precision at 1920 x 1080.
	#
	# We are re-using one of the ping-pong 2-channel JFA pass textures
	# for the distance field.
	# In brief testing, creating a new R16_UNORM texture was ~0.1ms faster,
	# and going further to an R8_UNORM should be sufficient for the distance field.
	# However, using a different texture format would require maintaining
	# a separate compute shader for the last JFA pass.
	#
	# If neighbor sampling is not required in the overlay shader,
	# the last JFA pass can be combined with the overlay shader, and the additional
	# texture would not be needed. This would mean losing the distance field
	# in RenderDoc for debugging. But it can be rendered to the screen using the
	# OutlineEffect.
	const JF_TEXTURE_FORMAT := RenderingDevice.DATA_FORMAT_R16G16_UNORM
	const TEXTURE_SAMPLES := RenderingDevice.TextureSamples.TEXTURE_SAMPLES_1
	const TEXTURE_LAYER_COUNT : int = 1
	const TEXTURE_MIPMAP_COUNT : int = 1
	const TEXTURE_LAYER : int = 0
	const TEXTURE_MIPMAP : int = 0
	const TEXTURE_IS_UNIQUE : bool = true

	if render_scene_buffers.has_texture(context, texture):
		if render_size_changed:
			# Clear all textures under this context.
			render_scene_buffers.clear_context(context)

	if not render_scene_buffers.has_texture(context, texture):
		var usage_bits : int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
			| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT

		render_scene_buffers.create_texture(
			context,
			texture,
			JF_TEXTURE_FORMAT,
			usage_bits,
			TEXTURE_SAMPLES,
			render_size,
			TEXTURE_LAYER_COUNT,
			TEXTURE_MIPMAP_COUNT,
			TEXTURE_IS_UNIQUE)

		render_scene_buffers.create_texture(
			context,
			pong_texture,
			JF_TEXTURE_FORMAT,
			usage_bits,
			TEXTURE_SAMPLES,
			render_size,
			TEXTURE_LAYER_COUNT,
			TEXTURE_MIPMAP_COUNT,
			TEXTURE_IS_UNIQUE)
	#endregion

	for view in render_scene_buffers.get_view_count():
		#region Create global uniform set and shared texture uniforms
		const GLOBAL_UNIFORM_BUFFER_BINDING : int = 1
		var global_uniform_buffer_uniform : RDUniform = get_uniform_buffer_uniform(
				global_uniform_buffer,
				GLOBAL_UNIFORM_BUFFER_BINDING,
			)

		const COLOR_IMAGE_BINDING : int = 2
		var color_image : RID = render_scene_buffers.get_color_layer(view)
		var color_image_uniform : RDUniform = get_image_uniform(
				color_image,
				COLOR_IMAGE_BINDING,
			)

		# It appears that depth must be used as a sampler due to the
		# usage bits set for its image.
		const DEPTH_IMAGE_BINDING : int = 3
		var depth_image : RID = render_scene_buffers.get_depth_layer(view)
		var depth_image_uniform : RDUniform = get_sampler_uniform(
				depth_image,
				nearest_sampler,
				DEPTH_IMAGE_BINDING,
			)

		# See https://github.com/godotengine/godot/pull/80214#issuecomment-1953258434
		var scene_data_buffer : RID = render_scene_data.get_uniform_buffer()
		var scene_data_buffer_uniform := RDUniform.new()
		scene_data_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		scene_data_buffer_uniform.binding = 0
		scene_data_buffer_uniform.add_id(scene_data_buffer)

		var global_uniform_set_list : Array[RDUniform] = [
				scene_data_buffer_uniform,
				global_uniform_buffer_uniform,
				color_image_uniform,
				depth_image_uniform,
			]

		const TEXTURE_SAMPLER_BINDING := 0
		const TEXTURE_IMAGE_BINDING := 1

		var texture_image : RID = render_scene_buffers.get_texture_slice(
				context,
				texture,
				TEXTURE_LAYER,
				TEXTURE_MIPMAP,
				TEXTURE_LAYER_COUNT,
				TEXTURE_MIPMAP_COUNT,
			)
		var texture_image_uniform : RDUniform = get_image_uniform(texture_image, TEXTURE_IMAGE_BINDING)
		var texture_sampler : RDUniform = get_sampler_uniform(texture_image, linear_sampler, TEXTURE_SAMPLER_BINDING)

		var pong_texture_image : RID = render_scene_buffers.get_texture_slice(
				context,
				pong_texture,
				TEXTURE_LAYER,
				TEXTURE_MIPMAP,
				TEXTURE_LAYER_COUNT,
				TEXTURE_MIPMAP_COUNT,
			)
		var pong_image_uniform : RDUniform = get_image_uniform(pong_texture_image, TEXTURE_IMAGE_BINDING)
		var pong_texture_sampler : RDUniform = get_sampler_uniform(pong_texture_image, linear_sampler, TEXTURE_SAMPLER_BINDING)

		var uniform_set_lists : Array[Array]
		#endregion

		#region Extraction pass
		uniform_set_lists = [
				global_uniform_set_list,
				[texture_image_uniform],
			]

		run_compute_shader(
				extraction_shader,
				extraction_pipeline,
				groups,
				uniform_set_lists,
			)
		#endregion

		#region Jump flood passes
		var in_sampler : RDUniform = texture_sampler
		var out_image_uniform : RDUniform = pong_image_uniform

		var step_offsets : PackedInt32Array = jf_calc.get_step_offsets()

		for i in step_offsets.size():
			var offset : int = step_offsets[i]
			var pipeline : RID = jf_pass_pipelines.get(offset, RID())
			if not pipeline.is_valid():
				printerr("No valid JF pass pipeline found for offset: %s" % offset)
				continue

			# To avoid creating new uniform objects
			# for the ping-pong textures in each pass,
			# we will keep the bindings the same but swap the sets.
			uniform_set_lists = [
				global_uniform_set_list,
				[in_sampler, out_image_uniform],
			]

			run_compute_shader(
				jf_pass_shader,
				pipeline,
				groups,
				uniform_set_lists,
			)

			# Swap the ping-pong textures at end of each pass.
			if out_image_uniform == texture_image_uniform:
				in_sampler = texture_sampler
				out_image_uniform = pong_image_uniform
			else:
				in_sampler = pong_texture_sampler
				out_image_uniform = texture_image_uniform
		#endregion

		#region Overlay pass
		# We will use the last output image sampler as our input,
		# which has already been reassigned to in_sampler.

		uniform_set_lists = [
			global_uniform_set_list,
			[in_sampler],
		]

		run_compute_shader(
				overlay_shader,
				overlay_pipeline,
				groups,
				uniform_set_lists,
			)
		#endregion


# The parameter `p_push_constant` takes a PackedFloat32Array and resizes
# it to meet layout requirements. Push constants use std430, so the items
# don't require padding for alignment. But it appears the total size must be
# a multiple of 16 bytes.
func run_compute_shader(
			p_shader : RID,
			p_pipeline : RID,
			p_groups : Vector2i,
			p_uniform_sets : Array[Array],
			p_push_constant := PackedFloat32Array(),
		) -> void:

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, p_pipeline)

	for idx in p_uniform_sets.size():
		var uniforms : Array = p_uniform_sets[idx]
		rd.compute_list_bind_uniform_set(
				compute_list,
				UniformSetCacheRD.get_cache(
						p_shader,
						idx,
						uniforms,
					),
				idx,
			)

	if not p_push_constant.is_empty():
		var byte_array := p_push_constant.to_byte_array()
		var size_before := byte_array.size()
		if byte_array.size() % 16:
			byte_array.resize(ceili(float(byte_array.size())/16.0) * 16)
			if print_buffer_resize && not has_printed_push_constant_size:
				var size_change := byte_array.size() - size_before
				print("Push constant resized from %s to %s." % [size_before, byte_array.size()])
				print("\tBytes added: %s = %s floats." % [size_change, float(size_change)/4.0])
				has_printed_push_constant_size = true

		rd.compute_list_set_push_constant(
				compute_list,
				byte_array,
				byte_array.size(),
			)

	rd.compute_list_dispatch(compute_list, p_groups.x, p_groups.y, 1)
	rd.compute_list_end()


# Individual assignments in a uniform buffer must be aligned to 16 bytes.
# However, you can assign the whole buffer to a struct, and that struct can contain
# elements aligned at 4 bytes (== one 32-bit float, which is the smallest data size
# for uniforms).
#
# Vector4's must be aligned to 16 bytes, so it is best to put them first in the list.
#
# Automatic conversion for Vector2's and Vector3's is not included here
# because (1) we don't need them, and, (2) if we did, we should probably convert
# them to Vector4 manually so we can keep track of their alignment.
func create_uniform_buffer(p_data : Array) -> RID:
	var buffer_data : PackedByteArray

	for value in p_data:
		var type := typeof(value)
		var byte_array : PackedByteArray
		match type:
			TYPE_INT:
				# PackedInt32Array does not convert the values as expected.
				byte_array = PackedFloat32Array([float(value)]).to_byte_array()
			TYPE_BOOL:
				byte_array = PackedFloat32Array([float(value)]).to_byte_array()
			TYPE_FLOAT:
				byte_array = PackedFloat32Array([value]).to_byte_array()
			TYPE_COLOR:
				byte_array = PackedColorArray([value]).to_byte_array()
			TYPE_VECTOR4:
				byte_array = PackedVector4Array([value]).to_byte_array()
			TYPE_VECTOR4I:
				byte_array = PackedVector4Array([Vector4(value)]).to_byte_array()
			_:
				push_error("[DFOutlineCE:create_uniform_buffer()] Unhandled data type found: %s" % type)
				continue

		buffer_data.append_array(byte_array)

	var size_before := buffer_data.size()

	# Resize to a multiple of 16 bytes.
	if buffer_data.size() % 16:
		var divisor := floori(float(buffer_data.size()) / 16.0)
		buffer_data.resize((divisor + 1) * 16)

	if print_buffer_resize && not has_printed_ubo_size:
		var size_change := buffer_data.size() - size_before
		print("UBO buffer resized from %s to %s." % [size_before, buffer_data.size()])
		print("\tBytes added: %s = %s floats." % [size_change, float(size_change)/4.0])
		has_printed_ubo_size = true

	return rd.uniform_buffer_create(buffer_data.size(), buffer_data)


func get_uniform_buffer_uniform(p_rid : RID, p_binding : int) -> RDUniform:
	var uniform  := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = p_binding
	uniform.add_id(p_rid)
	return uniform


func get_image_uniform(p_image_rid : RID, p_binding : int = 0) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = p_binding
	uniform.add_id(p_image_rid)
	return uniform


func get_sampler_uniform(
			p_image_rid : RID,
			p_sampler : RID = linear_sampler,
			p_binding : int = 0,
		) -> RDUniform:
	var uniform : RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = p_binding
	uniform.add_id(p_sampler)
	uniform.add_id(p_image_rid)
	return uniform


func setup_outline_settings() -> void:
	if not outline_settings.changed.is_connected(make_ubo_dirty):
		outline_settings.changed.connect(make_ubo_dirty)
	if not outline_settings.outline_width_changed.is_connected(update_jf_calcs):
		outline_settings.outline_width_changed.connect(update_jf_calcs)
	update_jf_calcs()


func update_jf_calcs() -> void:
	if jf_calc:
		jf_calc.set_outline_width(outline_settings.outline_width, outline_settings.viewport_size)
	if min_jf_calc:
		min_jf_calc.set_outline_width(outline_settings.min_outline_width, outline_settings.viewport_size)
	global_uniform_buffer_dirty = true


func update_overlay_pipeline() -> void:
	if not overlay_shader.is_valid():
		printerr("Overlay shader is invalid")
		return

	if rd.compute_pipeline_is_valid(overlay_pipeline):
		rd.free_rid(overlay_pipeline)

	var effect_id_constant := RDPipelineSpecializationConstant.new()
	effect_id_constant.constant_id = OVERLAY_CONSTANT_EFFECT_ID
	effect_id_constant.value = outline_settings.outline_effect as int
	var depth_fade_constant := RDPipelineSpecializationConstant.new()
	depth_fade_constant.constant_id = OVERLAY_CONSTANT_DEPTH_FADE
	depth_fade_constant.value = outline_settings.depth_fade_mode as int
	overlay_pipeline = rd.compute_pipeline_create(
			overlay_shader,
			[effect_id_constant, depth_fade_constant],
	)


func create_jf_pass_pipeline(p_offset : int, p_last_pass : bool) -> void:
	if not jf_pass_shader.is_valid():
		printerr("JF pass shader is invalid")
		return

	var offset_constant := RDPipelineSpecializationConstant.new()
	offset_constant.constant_id = JF_CONSTANT_OFFSET
	offset_constant.value = p_offset
	var last_pass_constant := RDPipelineSpecializationConstant.new()
	last_pass_constant.constant_id = JF_CONSTANT_LAST_PASS
	last_pass_constant.value = p_last_pass
	jf_pass_pipelines[p_offset] = rd.compute_pipeline_create(
			jf_pass_shader,
			[offset_constant, last_pass_constant],
	)


func make_ubo_dirty() -> void:
	global_uniform_buffer_dirty = true
