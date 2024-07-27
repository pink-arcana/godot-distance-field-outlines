#[compute]
#version 450

// #define DEBUG

#include "includes/scene_data.glsl"
#include "includes/scene_data_helpers.glsl"
#include "includes/df_header.glsl"

layout(constant_id = 0) const int OFFSET = 1;
layout(constant_id = 1) const bool LAST_PASS = false;
layout(constant_id = 2) const int DEPTH_FADE_MODE = 0;

#ifdef DEBUG
layout(rgba16f, set = 1, binding = 1) uniform restrict writeonly image2D debug_image;
#endif // DEBUG

layout(rg16ui, set = 2, binding = 0) uniform restrict readonly uimage2D in_image;
layout(rg16ui, set = 2, binding = 1) uniform restrict writeonly uimage2D out_image;
layout(r16f, set = 2, binding = 2) uniform restrict readonly image2D depth_image;
layout(rg16f, set = 2, binding = 3) uniform restrict writeonly image2D df_image;

const float MAX_DEPTH = 1.0;
const float MAX_DISTANCE = 1000000000.0;

void main() {
	ivec2 viewport_size = ivec2(scene.data.viewport_size);
	ivec2 image_coord = ivec2(gl_GlobalInvocationID.xy);

	ivec2 seed_coord = INVALID_COORD;
	bool valid_seed = false;
	float seed_dist_sq = MAX_DISTANCE;
	highp float seed_depth = MAX_DEPTH;
	bool seed_inside_outline = false;

	for (int i = 0; i < KERNEL_OFFSETS.length(); i++) {
		ivec2 offset_coord = (KERNEL_OFFSETS[i] * OFFSET) + image_coord;
		offset_coord = ivec2(
			clamp(offset_coord.x, 0, viewport_size.x - 1),
			clamp(offset_coord.y, 0, viewport_size.y - 1));

		ivec2 offset_seed_coord = ivec2(imageLoad(in_image, offset_coord).rg);
		bool valid_offset_seed = offset_seed_coord != INVALID_COORD;
		float offset_seed_dist_sq = valid_offset_seed ? dist_squared(image_coord, offset_seed_coord) : MAX_DISTANCE;

		bool offset_seed_inside_outline = true;
		float offset_seed_outline_dist = 0.0;

		float offset_seed_depth = MAX_DEPTH;

		if (DEPTH_FADE_MODE != DEPTH_FADE_MODE_NONE) {
			offset_seed_depth = valid_offset_seed ? imageLoad(depth_image, offset_seed_coord).r : MAX_DEPTH;
			offset_seed_outline_dist = valid_offset_seed ? get_outline_distance(offset_seed_depth, DEPTH_FADE_MODE) : 0.0;
			float offset_outline_dist_sq = offset_seed_outline_dist * offset_seed_outline_dist;
			offset_seed_inside_outline = valid_offset_seed ? offset_seed_dist_sq <= offset_outline_dist_sq : false;
		}

		bool shorter_dist = offset_seed_dist_sq < seed_dist_sq;
		bool smaller_depth = offset_seed_depth < seed_depth;
		bool equal_depth = abs(offset_seed_depth - seed_depth) < EPSILON;

		bool use_offset_seed = valid_offset_seed && offset_seed_inside_outline && (
				smaller_depth || shorter_dist && equal_depth || !seed_inside_outline);

		seed_coord = use_offset_seed ? offset_seed_coord : seed_coord;
		seed_dist_sq = use_offset_seed ? offset_seed_dist_sq : seed_dist_sq;
		seed_depth = use_offset_seed ? offset_seed_depth : seed_depth;
		seed_inside_outline = use_offset_seed ? offset_seed_inside_outline : seed_inside_outline;
		valid_seed = use_offset_seed ? valid_offset_seed : valid_seed;
	}

	#ifdef DEBUG
	imageStore(debug_image, image_coord, vec4(valid_seed, sqrt(seed_dist_sq) <= 1.0, 0.0, 1.0));
	#endif // DEBUG


	if (LAST_PASS) {
		// If this is the last JF pass, we will output a distance field texture.
		// In the red channel, we will store the non-squared distance,
		// and normalize it by dividing by distance_denominator.
		// If we do not have a valid seed, we assign the maximum distance (1.0).
		float seed_dist_n = valid_seed ? sqrt(seed_dist_sq) / df.data.distance_denominator : 1.0;
		imageStore(df_image, image_coord, vec4(seed_dist_n, seed_depth, 0.0, 0.0));
	} else {
		// If this is an intermediate JF pass, we will store the coord of the closest outline seed.
		// If no seeds were found, we will be passing on INVALID_COORD.
		imageStore(out_image, image_coord, ivec4(seed_coord, 0, 0));
	}
}
