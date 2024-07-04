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

layout(constant_id = 0) const int OFFSET = 1;
layout(constant_id = 1) const bool LAST_PASS = false;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
}
scene;

layout(set = 0, binding = 1, std140) uniform DFOutlineBlock {
	DFOutlineData data;
} df;

layout(set = 0, binding = 3) uniform sampler2D depth_texture;
layout(set = 1, binding = 0) uniform sampler2D in_sampler;
layout(rg16f, set = 1, binding = 1) uniform restrict writeonly image2D out_image;


const ivec2 NEIGHBORS[8] = {
	ivec2(-1,-1), ivec2(0,-1), ivec2(1,-1),
	ivec2(-1,0), ivec2(1,0),
	ivec2(-1,1), ivec2(0,1), ivec2(1,1) };

// Neighbors without corners - faster, but slightly degrades result.
// const ivec2 NEIGHBORS[5] = {
// 	ivec2(0,-1),
// 	ivec2(-1,0), ivec2(0,0), ivec2(1,0),
// 	ivec2(0,1) };

const float EPSILON = 0.001;
const highp vec2 INVALID_SEED = vec2(1.0, 1.0);


highp float get_linear_depth(highp vec2 p_uv, highp mat4 p_inv_projection_matrix) {
	highp float depth = textureLod(depth_texture, p_uv, 0.0).r;
	highp vec3 ndc = vec3((p_uv * 2.0) - 1.0, depth);
	highp vec4 view = p_inv_projection_matrix * vec4(ndc, 1.0);
	return -(view.xyz / view.w).z;
}


// In testing @ 1024px/1080p, this function is slightly faster (0.01-0.02ms) than calculating coord_a - coord_b,
// and then using dot() for distance squared.
float dist_squared(ivec2 p_coord_a, ivec2 p_coord_b) {
	vec2 coord_a = vec2(p_coord_a);
	vec2 coord_b = vec2(p_coord_b);
	return (coord_a.x - coord_b.x) * (coord_a.x - coord_b.x) + (coord_a.y - coord_b.y) * (coord_a.y - coord_b.y);
}


// We will round to ivec2 for accuracy. Unpacking coords to highp vec2
// prevented the seed coords from keeping distances of 0.0.
ivec2 unpack_coord(highp vec2 p_uv, ivec2 p_viewport_size) {
	const float UV_PACK_SCALE = 0.99;
	return ivec2(round(p_uv * (p_viewport_size / UV_PACK_SCALE) - 0.5));
}


void main() {
	SceneData scene_data = scene.data;
	ivec2 viewport_size = ivec2(scene_data.viewport_size);
	highp mat4 inv_projection_matrix = scene_data.inv_projection_matrix;
	float distance_denominator = df.data.distance_denominator;
	float depth_fade_end = df.data.depth_fade_end;
	ivec2 image_coord = ivec2(gl_GlobalInvocationID.xy);

	// Previously stored coords of the nearest outline seed texel.
	highp vec2 seed_packed = texelFetch(in_sampler, image_coord, 0).rg;
	bool valid_seed = seed_packed.x < INVALID_SEED.x - EPSILON;
	ivec2 seed_coord = unpack_coord(seed_packed, viewport_size);

	// Using distance squared lets us skip square roots required to calculate distance.
	float min_dist_sq = valid_seed ? dist_squared(image_coord, seed_coord) : 1000000.0;

	for (int i = 0; i < NEIGHBORS.length(); i++) {
		ivec2 neighbor_coord = (NEIGHBORS[i] * OFFSET) + image_coord;
		neighbor_coord = ivec2(
			clamp(neighbor_coord.x, 0, viewport_size.x - 1),
			clamp(neighbor_coord.y, 0, viewport_size.y - 1));

		highp vec2 neighbor_seed_packed = texelFetch(in_sampler, neighbor_coord, 0).rg;

		bool valid_neighbor_seed = neighbor_seed_packed.x < INVALID_SEED.x - EPSILON;
		ivec2 neighbor_seed_coord = unpack_coord(neighbor_seed_packed, viewport_size);
		float dist_sq = dist_squared(image_coord, neighbor_seed_coord);
		bool shorter_dist = valid_neighbor_seed && (dist_sq < min_dist_sq);
		min_dist_sq = shorter_dist ? dist_sq : min_dist_sq;
		seed_coord = shorter_dist ? neighbor_seed_coord : seed_coord;
		seed_packed = shorter_dist ? neighbor_seed_packed : seed_packed;
		valid_seed = shorter_dist ? true : valid_seed;
	}


	vec4 color = vec4(0.0);
	if (LAST_PASS) {
		// If this is the last JF pass, we will output a distance field texture.
		// In the red channel, we will store the non-squared distance,
		// and normalize it by dividing by distance_denominator.
		// If we do not have a valid seed, we assign the maximum distance (1.0).
		float min_dist_n = valid_seed ? sqrt(min_dist_sq) / distance_denominator : 1.0;

		// In the green channel, we will store the depth of the seed position,
		// and normalize it relative to depth_fade_end.
		highp vec2 seed_uv = (vec2(seed_coord) + 0.5)/viewport_size;
		float linear_depth = get_linear_depth(seed_uv, inv_projection_matrix);
		float depth_n = valid_seed ? linear_depth / depth_fade_end : 1.0;

		color.rg = vec2(min_dist_n, depth_n);

	} else {
		// If this is an intermediate JF pass, we will store the coord of the closest outline seed.
		// If no neighboring seeds were found at the offset for this pass,
		// this coord will be unchanged from our input.
		// This means that, if we did not have a valid initial seed, and we also failed to find one,
		// INVALID_SEED will continue to be passed on.
		color.rg = seed_packed;
	}

	imageStore(out_image, image_coord, color);
}
