shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D color_texture : filter_nearest, repeat_disable;
uniform float sobel_threshold;

const float X_KERNEL[9] = {
	-1.0, 0.0, 1.0,
	-2.0, 0.0, 2.0,
	-1.0, 0.0, 1.0};

const float Y_KERNEL[9] = {
	-1.0, -2.0, -1.0,
	0.0, 0.0, 0.0,
	1.0, 2.0, 1.0};


#include "includes/utils.gdshaderinc"


// We receive the SubViewport's color texture in SRGB colorspace.
// Converting it to linear here should make the outlines as close as possible
// to our CompositorEffect shader.
vec4[9] get_neighbor_colors(vec2 p_tex_coord, vec2 p_texture_size) {
	vec4 colors[9];
	for (int i = 0; i < KERNEL_OFFSETS.length(); i++) {
		vec2 offset = KERNEL_OFFSETS[i];
		vec2 neighbor_coord = p_tex_coord + offset;
		neighbor_coord.x = clamp(neighbor_coord.x, 0.0, p_texture_size.x - 1.0);
		neighbor_coord.y = clamp(neighbor_coord.y, 0.0, p_texture_size.y - 1.0);
		colors[i] = srgb_to_linear(texelFetch(color_texture, ivec2(neighbor_coord), 0));
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

void fragment() {
	highp vec2 texture_size = vec2(textureSize(color_texture, 0));
	highp vec2 pixel_size = 1.0/texture_size;
	highp vec2 tex_coord = UV / pixel_size;

	// ---------------------------------------------------------------------------
	// Here, we use Sobel convolutions to identify texels where the color changes quickly.
	// We then use those coordinates as the seeds for our Jump Flooding Algorithm.
	// This section can be replaced with any custom algorithm to detect outlines.
	vec4 neighbor_colors[9] = get_neighbor_colors(tex_coord, texture_size);
	vec4 gx = get_axis_gradient(neighbor_colors, X_KERNEL);
	vec4 gy = get_axis_gradient(neighbor_colors, Y_KERNEL);
	vec4 sobel_magnitude = sqrt(gx * gx + gy * gy);
	float max_sobel = max(sobel_magnitude.r, max(sobel_magnitude.g, sobel_magnitude.b));
	bool is_seed = max_sobel > sobel_threshold;
	// ---------------------------------------------------------------------------

	CoordData coord_data = CoordData(tex_coord, is_seed);
	COLOR = coord_to_color(coord_data, texture_size);
}
