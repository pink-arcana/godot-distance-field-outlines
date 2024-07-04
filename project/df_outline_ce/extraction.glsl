#[compute]
#version 450

struct SceneData {
	highp mat4 projection_matrix;
	highp mat4 inv_projection_matrix;
	highp mat4 inv_view_matrix;
	highp mat4 view_matrix;

	// only used for multiview
	highp mat4 projection_matrix_view[2];
	highp mat4 inv_projection_matrix_view[2];
	highp vec4 eye_offset[2];

	// Used for billboards to cast correct shadows.
	highp mat4 main_cam_inv_view_matrix;

	highp vec2 viewport_size;
	highp vec2 screen_pixel_size;

	// Use vec4s because std140 doesn't play nice with vec2s, z and w are wasted.
	highp vec4 directional_penumbra_shadow_kernel[32];
	highp vec4 directional_soft_shadow_kernel[32];
	highp vec4 penumbra_shadow_kernel[32];
	highp vec4 soft_shadow_kernel[32];

	mediump mat3 radiance_inverse_xform;

	mediump vec4 ambient_light_color_energy;

	mediump float ambient_color_sky_mix;
	bool use_ambient_light;
	bool use_ambient_cubemap;
	bool use_reflection_cubemap;

	highp vec2 shadow_atlas_pixel_size;
	highp vec2 directional_shadow_pixel_size;

	uint directional_light_count;
	mediump float dual_paraboloid_side;
	highp float z_far;
	highp float z_near;

	bool roughness_limiter_enabled;
	mediump float roughness_limiter_amount;
	mediump float roughness_limiter_limit;
	mediump float opaque_prepass_threshold;

	bool fog_enabled;
	uint fog_mode;
	highp float fog_density;
	highp float fog_height;
	highp float fog_height_density;

	highp float fog_depth_curve;
	highp float pad;
	highp float fog_depth_begin;

	mediump vec3 fog_light_color;
	highp float fog_depth_end;

	mediump float fog_sun_scatter;
	mediump float fog_aerial_perspective;
	highp float time;
	mediump float reflection_multiplier; // one normally, zero when rendering reflections

	vec2 taa_jitter;
	bool material_uv2_mode;
	float emissive_exposure_normalization;

	float IBL_exposure_normalization;
	bool pancake_shadows;
	uint camera_visible_layers;
	float pass_alpha_multiplier;
};

struct DFOutlineData {
	vec4 outline_color;
	vec4 background_color;
	float outline_distance;
	float distance_denominator;
	float use_background_color;
	float sobel_threshold;
	float depth_fade_start;
    float depth_fade_end;
    float min_outline_alpha;
    float min_outline_distance;
	float smoothing_distance;
	float res;
	float res2;
	float res3;
};

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
} scene;

layout(set = 0, binding = 1, std140) uniform DFOutlineBlock {
	DFOutlineData data;
} df;

layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2D color_image;
layout(rg16f, set = 1, binding = 1) uniform restrict writeonly image2D out_image;

const ivec2 NEIGHBORS[9] = {
	ivec2(-1,-1), ivec2(0,-1), ivec2(1,-1),
	ivec2(-1,0), ivec2(0,0), ivec2(1,0),
	ivec2(-1,1), ivec2(0,1), ivec2(1,1) };

const float X_KERNEL[9] = {
	-1.0, 0.0, 1.0,
	-2.0, 0.0, 2.0,
	-1.0, 0.0, 1.0};

const float Y_KERNEL[9] = {
	-1.0, -2.0, -1.0,
	0.0, 0.0, 0.0,
	1.0, 2.0, 1.0};

const highp vec2 INVALID_SEED = vec2(1.0, 1.0);

// Here, we are using coordinates in texture space,
// so the offset between adjacent coordinates is equal to the values in NEIGHBORS.
// We do not need to adjust for texel size.
vec4[9] get_neighbor_colors(ivec2 p_image_coord, ivec2 p_render_size) {
	vec4 colors[9];
	for (int i = 0; i < NEIGHBORS.length(); i++) {
		ivec2 offset = NEIGHBORS[i];
		ivec2 neighbor_coord = p_image_coord + offset;

		// If the neighbor coordinate is outside of our texture,
		// we will sample the nearest edge texel's color instead.
		// (Repeat modes aren't relevant for imageLoad or texel fetches.)
		neighbor_coord = ivec2(
			clamp(neighbor_coord.x, 0, p_render_size.x - 1),
			clamp(neighbor_coord.y, 0, p_render_size.y - 1));

		colors[i] = imageLoad(color_image, neighbor_coord);
	}
	return colors;
}


vec4 get_axis_gradient(vec4[9] p_colors, float[9] p_kernel) {
	vec4 gradient = vec4(0.0);
	for (int i = 0; i < p_colors.length(); i++) {
		gradient += p_colors[i] * p_kernel[i];
	}
	return gradient;
}


// Normalize and pack a texture-space coord for storage in a range of [0,UV_PACK_SCALE].
// We need to add 0.5 when normalizing coords derived from gl_GlobalInvocationID.
highp vec2 pack_coord(highp vec2 p_coord, ivec2 p_render_size) {
	const float UV_PACK_SCALE = 0.99;
	return (p_coord + 0.5) * (UV_PACK_SCALE / p_render_size);
}


void main() {
	ivec2 viewport_size = ivec2(scene.data.viewport_size);
	ivec2 image_coord = ivec2(gl_GlobalInvocationID.xy);

	// ---------------------------------------------------------------------------
	// Here, we use Sobel convolutions to identify texels where the color changes quickly.
	// We then use those coordinates as the seed for our Jump Flooding Algorithm.
	// This section can be replaced with a custom algorithm to detect outlines.

	// We will discard the alpha contribution to our sobel,
	// but still process the colors as vec4s because
	// vec3s can be inefficient on some hardware.
	vec4 neighbor_colors[9] = get_neighbor_colors(image_coord, viewport_size);
	vec4 gx = get_axis_gradient(neighbor_colors, X_KERNEL);
	vec4 gy = get_axis_gradient(neighbor_colors, Y_KERNEL);
	vec4 sobel_magnitude = sqrt(gx * gx + gy * gy);
	float max_sobel = max(sobel_magnitude.r, max(sobel_magnitude.g, sobel_magnitude.b));
	bool is_seed = max_sobel > df.data.sobel_threshold;
	// ---------------------------------------------------------------------------

	// We use 1.0 to indicate an invalid coordinate (i.e. not a seed), and pack
	// our valid coordinates into a range of [0.0,0.99].
	highp vec2 seed_packed = is_seed ? pack_coord(image_coord, viewport_size) : INVALID_SEED;
	vec4 color = vec4(seed_packed, 0.0, 0.0);
	imageStore(out_image, image_coord, color);
}
