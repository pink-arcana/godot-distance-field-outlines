#[compute]
#version 450

// define DEBUG

#include "includes/scene_data.glsl"
#include "includes/scene_data_helpers.glsl"
#include "includes/df_header.glsl"

layout(constant_id = 0) const int EXTRACTION_TYPE = 0;
layout(constant_id = 1) const int DEPTH_FADE_MODE = 0;

#ifdef DEBUG
layout(rgba16f, set = 1, binding = 1) uniform restrict writeonly image2D debug_image;
#endif // DEBUG

layout(rg16f, set = 0, binding = 1) uniform restrict readonly image2D color_image;
layout(rg16ui, set = 2, binding = 1) uniform restrict writeonly uimage2D out_image;
layout(r16f, set = 2, binding = 2) uniform restrict writeonly image2D depth_image;

const float X_KERNEL[9] = {
	-1.0, 0.0, 1.0,
	-2.0, 0.0, 2.0,
	-1.0, 0.0, 1.0};

const float Y_KERNEL[9] = {
	-1.0, -2.0, -1.0,
	0.0, 0.0, 0.0,
	1.0, 2.0, 1.0};


// Adapted from High Quality Post Process Outline by EMBYR (Hannah "EMBYR" Crawford)
// MIT license
// https://godotshaders.com/shader/high-quality-post-process-outline/

// UNIFORMS
const vec4 outlineColor = vec4(0.0, 0.0, 0.0, 0.78);
const float depth_threshold = 0.025;
const float normal_threshold = 0.5;
const float normal_smoothing = 0.25;

const float max_distance = 75.0;
const float min_distance = 2.0;

const float grazing_fresnel_power = 5.0;
const float grazing_angle_mask_power = 1.0;
const float grazing_angle_modulation_factor = 50.0;

// STRUCTS
// Changed from vec2 to ivec2 for imageLoad sampling.
struct UVNeighbors {
	ivec2 center;
	ivec2 left;     ivec2 right;     ivec2 up;          ivec2 down;
	ivec2 top_left; ivec2 top_right; ivec2 bottom_left; ivec2 bottom_right;
};

struct NeighborDepthSamples {
	float c_d;
	float l_d;  float r_d;  float u_d;  float d_d;
	float tl_d; float tr_d; float bl_d; float br_d;
};

// Removed width and aspect since current setup only samples integer coordinates,
// and outlines are widened later in JFA passes.
UVNeighbors getNeighbors(ivec2 center) {
	ivec2 h_offset = ivec2(1, 0);
	ivec2 v_offset = ivec2(0, 1);
	UVNeighbors n;
	n.center = center;
	n.left   = center - h_offset;
	n.right  = center + h_offset;
	n.up     = center - v_offset;
	n.down   = center + v_offset;
	n.top_left     = center - (h_offset - v_offset);
	n.top_right    = center + (h_offset - v_offset);
	n.bottom_left  = center - (h_offset + v_offset);
	n.bottom_right = center + (h_offset + v_offset);
	return n;
}


float getMinimumDepth(NeighborDepthSamples ds){
	return min(ds.c_d, min(ds.l_d, min(ds.r_d, min(ds.u_d, min(ds.d_d, min(ds.tl_d, min(ds.tr_d, min(ds.bl_d, ds.br_d))))))));
}


float getLinearDepth(float depth, vec2 uv, mat4 inv_proj) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

// Modified to use get_linear_depth() from scene_data_helpers.glsl
NeighborDepthSamples getLinearDepthSamples(UVNeighbors uvs) {
	NeighborDepthSamples result;
	result.c_d  = get_linear_depth(uvs.center);
	result.l_d  = get_linear_depth(uvs.left);
	result.r_d  = get_linear_depth(uvs.right);
	result.u_d  = get_linear_depth(uvs.up);
	result.d_d  = get_linear_depth(uvs.down);
	result.tl_d = get_linear_depth(uvs.top_left);
	result.tr_d = get_linear_depth(uvs.top_right);
	result.bl_d = get_linear_depth(uvs.bottom_left);
	result.br_d = get_linear_depth(uvs.bottom_right);
	return result;
}


float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0 )), amount);
}


float getGrazingAngleModulation(vec3 pixel_normal, vec3 view) {
	float x = clamp(((fresnel(grazing_fresnel_power, pixel_normal, view) - 1.0) / grazing_angle_mask_power) + 1.0, 0.0, 1.0);
	return (x + grazing_angle_modulation_factor) + 1.0;
}

float detectEdgesDepth(NeighborDepthSamples depth_samples, vec3 pixel_normal, vec3 view) {
	float n_total =
		depth_samples.l_d +
		depth_samples.r_d +
		depth_samples.u_d +
		depth_samples.d_d +
		depth_samples.tl_d +
		depth_samples.tr_d +
		depth_samples.bl_d +
		depth_samples.br_d;

	float t = depth_threshold * getGrazingAngleModulation(pixel_normal, view);
	return step(t, n_total - (depth_samples.c_d * 8.0));
}


float detectEdgesNormal(UVNeighbors uvs) {
	vec3 n_u = get_normal_roughness_color(uvs.up).xyz;
	vec3 n_d = get_normal_roughness_color(uvs.down).xyz;
	vec3 n_l = get_normal_roughness_color(uvs.left).xyz;
	vec3 n_r = get_normal_roughness_color(uvs.right).xyz;
	vec3 n_tl = get_normal_roughness_color(uvs.top_left).xyz;
	vec3 n_tr = get_normal_roughness_color(uvs.top_right).xyz;
	vec3 n_bl = get_normal_roughness_color(uvs.bottom_left).xyz;
	vec3 n_br = get_normal_roughness_color(uvs.bottom_right).xyz;

	vec3 normalFiniteDifference0 = n_tr - n_bl;
	vec3 normalFiniteDifference1 = n_tl - n_br;
	vec3 normalFiniteDifference2 = n_l - n_r;
	vec3 normalFiniteDifference3 = n_u - n_d;

	float edgeNormal = sqrt(
		dot(normalFiniteDifference0, normalFiniteDifference0) +
		dot(normalFiniteDifference1, normalFiniteDifference1) +
		dot(normalFiniteDifference2, normalFiniteDifference2) +
		dot(normalFiniteDifference3, normalFiniteDifference3)
	);

	return smoothstep(normal_threshold - normal_smoothing, normal_threshold + normal_smoothing, edgeNormal);
}


// Because the seed position may be on either side of the edge,
// we will get the minimum depth from neighboring texels.
// highp float get_seed_depth(ivec2 p_seed_coord) {
// 	highp float min_depth = get_linear_depth(p_seed_coord);

// 	// Skipping corners or using only corners is not measurably faster,
// 	// and results are visibly worse.
// 	for (int i = 0; i < NEIGHBOR_OFFSETS.length(); i++) {
// 		ivec2 neighbor_coord = p_seed_coord + NEIGHBOR_OFFSETS[i];
// 		// Convert depth to linar for correct comparison.
// 		highp float depth = get_linear_depth(neighbor_coord);
// 		min_depth = depth < min_depth ? depth : min_depth;
// 	}

// 	// Convert to normalized depth value.
// 	return get_depth_value(min_depth);
// }


void main() {
	ivec2 image_coord = ivec2(gl_GlobalInvocationID.xy);

	// ---------------------------------------------------------------------------
	// ---------------------------------------------------------------------------
	// Here, we use Sobel convolutions to identify texels where the color changes quickly.
	// We then use those coordinates as the seeds for our Jump Flooding Algorithm.

	// You can replace this section with a custom algorithm to detect outlines.
	// Depth and normal-roughness buffers are available to use.

	// For a simple way to get the normal-roughness, use:
	// vec4 normal_roughness_color = get_normal_roughness_color(image_coord);

	// And, for the linear depth value, use:
	// float depth = get_linear_depth(image_coord);

	// Transform matrices are also available, along with other helpful
	// variables like viewport_size, time, and camera_visible_layers.
	// They come from Godot's built-in SceneData uniform buffer object (UBO).
	// See scene_data.glsl for the full list.

	// Access SceneData variables like this:
	// highp mat4 inv_proj_matrix = scene.data.inv_projection_matrix;

	// (To see how the buffers and SceneData were implemented, see scene_data_helpers.glsl
	// and base_compositor_effect.gd.)
	// ---------------------------------------------------------------------------

	UVNeighbors n = getNeighbors(image_coord);
	NeighborDepthSamples depth_samples = getLinearDepthSamples(n);
	vec3 pixel_normal = get_normal_roughness_color(image_coord).xyz;

	// Is this the equivalent of Spatial shader's VIEW?
	vec3 view = -scene.data.view_matrix[2].xyz;

	float depthEdges = detectEdgesDepth(depth_samples, pixel_normal, view);
	float normEdges = min(detectEdgesNormal(n), 1.0);
	float max_edges = max(depthEdges, normEdges);

	// Arbitrary threshold to consider a texel part of the outline.
	const float EDGE_THRESHOLD = 0.1;
	bool is_seed = max_edges > EDGE_THRESHOLD;
	// ---------------------------------------------------------------------------
	// ---------------------------------------------------------------------------

	if (DEPTH_FADE_MODE != DEPTH_FADE_MODE_NONE) {
		float min_d = getMinimumDepth(depth_samples);
		float depth_value = get_depth_value(min_d);
		imageStore(depth_image, image_coord, vec4(depth_value));
	}

	imageStore(out_image, image_coord, ivec4(is_seed ? image_coord : INVALID_COORD, 0, 0));
}
