shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D in_texture : hint_screen_texture, filter_nearest, repeat_disable;

uniform float distance_denominator;
uniform float offset;
uniform bool last_pass;

#include "includes/utils.gdshaderinc"


float dist_squared(highp vec2 coord_a, highp vec2 coord_b) {
	return pow(coord_a.x - coord_b.x, 2.0) + pow(coord_a.y - coord_b.y, 2.0);
}


void fragment() {
	vec2 texture_size = vec2(textureSize(in_texture, 0));
	vec2 pixel_size = 1.0/texture_size;
	vec2 tex_coord = UV / pixel_size;

	// We receive the same values from the screen that we wrote to it,
	// without any colorspace conversions. So we do not need to convert to linear
	// colorspace here.
	vec4 seed_color = texelFetch(in_texture, ivec2(tex_coord), 0);
	CoordData coord_data = color_to_coord(seed_color, texture_size);

	bool valid_seed = coord_data.valid_seed;

	highp vec2 seed_coord = coord_data.coord;
	highp float min_dist_sq = valid_seed ? dist_squared(tex_coord, seed_coord) : 1000000.0;

	for (int i = 0; i < NEIGHBOR_OFFSETS.length(); i++) {
		highp vec2 neighbor_coord = (NEIGHBOR_OFFSETS[i] * offset) + tex_coord;
		neighbor_coord = vec2(
			clamp(neighbor_coord.x, 0.0, texture_size.x - 1.0),
			clamp(neighbor_coord.y, 0.0, texture_size.y - 1.0));

		vec4 neighbor_color = texelFetch(in_texture, ivec2(neighbor_coord), 0);
		CoordData neighbor_cd = color_to_coord(neighbor_color, texture_size);
		float dist_sq = dist_squared(tex_coord, neighbor_cd.coord);
		bool shorter_dist = neighbor_cd.valid_seed && dist_sq < min_dist_sq;
		min_dist_sq = shorter_dist ? dist_sq : min_dist_sq;
		seed_coord = shorter_dist ? neighbor_cd.coord : seed_coord;
		seed_color = shorter_dist ? neighbor_color : seed_color;
		valid_seed = shorter_dist ? true : valid_seed;
	}

	COLOR = vec4(0.0, 0.0, 0.0, 1.0);

	if (last_pass) {
		// If this is the last JF pass, we will output a distance field texture.
		// In the red channel, we will store the non-squared distance,
		// and normalize it by dividing by distance_denominator.
		// If we do not have a valid seed, we assign the maximum distance (1.0).
		float min_dist_n = valid_seed ? sqrt(min_dist_sq) / distance_denominator : 1.0;
		vec2 seed_uv = seed_coord * pixel_size;
		COLOR.r = min_dist_n;
	} else {
		COLOR = seed_color;
	}
}
