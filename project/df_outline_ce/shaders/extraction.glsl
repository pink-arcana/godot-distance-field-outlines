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
layout(rg16f, set = 2, binding = 0) uniform restrict writeonly image2D out_image;
layout(r16f, set = 2, binding = 2) uniform restrict writeonly image2D depth_image;

const float X_KERNEL[9] = {
	-1.0, 0.0, 1.0,
	-2.0, 0.0, 2.0,
	-1.0, 0.0, 1.0};

const float Y_KERNEL[9] = {
	-1.0, -2.0, -1.0,
	0.0, 0.0, 0.0,
	1.0, 2.0, 1.0};


// Here, we are using coordinates in texture space,
// so the offset between adjacent coordinates is equal to the values in KERNEL_OFFSETS.
// We do not need to adjust for texel size.
vec4[9] get_image_colors(ivec2 p_image_coord) {
	vec4 colors[9];
	for (int i = 0; i < KERNEL_OFFSETS.length(); i++) {
		ivec2 offset = KERNEL_OFFSETS[i];
		ivec2 coord = p_image_coord + offset;

		// If the neighbor coordinate is outside of our texture,
		// we will sample the nearest edge texel's color instead.
		// (Repeat modes aren't relevant for imageLoad or texel fetches.)
		coord = ivec2(
			clamp(coord.x, 0, int(scene.data.viewport_size.x) - 1),
			clamp(coord.y, 0, int(scene.data.viewport_size.y) - 1));

		colors[i] = imageLoad(color_image, coord);
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


// Because the seed position may be on either side of the edge,
// we will get the minimum depth from neighboring texels.
highp float get_seed_depth(ivec2 p_seed_coord) {
	highp float min_depth = get_linear_depth(p_seed_coord);

	// Skipping corners or using only corners is not measurably faster,
	// and results are visibly worse.
	for (int i = 0; i < NEIGHBOR_OFFSETS.length(); i++) {
		ivec2 neighbor_coord = p_seed_coord + NEIGHBOR_OFFSETS[i];
		// Convert depth to linar for correct comparison.
		highp float depth = get_linear_depth(neighbor_coord);
		min_depth = depth < min_depth ? depth : min_depth;
	}

	// Convert to normalized depth value.
	return get_depth_value(min_depth);
}


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

	vec4 image_colors[9] = get_image_colors(image_coord);
	vec4 gx = get_axis_gradient(image_colors, X_KERNEL);
	vec4 gy = get_axis_gradient(image_colors, Y_KERNEL);
	vec4 sobel_magnitude = sqrt(gx * gx + gy * gy);
	float max_sobel = max(sobel_magnitude.r, max(sobel_magnitude.g, sobel_magnitude.b));

	bool is_seed = max_sobel > df.data.sobel_threshold;
	// ---------------------------------------------------------------------------
	// ---------------------------------------------------------------------------

	highp float seed_depth = 1.0;
	if (DEPTH_FADE_MODE != DEPTH_FADE_MODE_NONE) {
		seed_depth = get_seed_depth(image_coord);
		imageStore(depth_image, image_coord, vec4(seed_depth));
	}

	// We use vec2(1.0,1.0) to indicate an invalid coordinate (i.e. not a seed), and pack
	// our valid coordinates into a range of [0.0,0.99].
	highp vec2 seed_packed = is_seed ? pack_coord(image_coord, ivec2(scene.data.viewport_size)) : INVALID_SEED;
	imageStore(out_image, image_coord, vec4(seed_packed, 0.0, 0.0));
}
