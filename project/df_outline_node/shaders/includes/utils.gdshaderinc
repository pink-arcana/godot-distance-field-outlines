const vec2 KERNEL_OFFSETS[9] = {
	vec2(-1.0,-1.0), vec2(0.0,-1.0), vec2(1.0,-1.0),
	vec2(-1.0,0.0), vec2(0.0,0.0), vec2(1.0,0.0),
	vec2(-1.0,1.0), vec2(0.0,1.0), vec2(1.0,1.0) };

const vec2 NEIGHBOR_OFFSETS[8] = {
	vec2(-1.0,-1.0), vec2(0.0,-1.0), vec2(1.0,-1.0),
	vec2(-1.0,0.0), vec2(1.0,0.0),
	vec2(-1.0,1.0), vec2(0.0,1.0), vec2(1.0,1.0) };

const vec2 INVALID_UV = vec2(-1.0,-1.0);
const float EPSILON = 0.001;

const highp float GRID_TEXELS = 256.0;

struct CoordData {
	highp vec2 coord;
	bool valid_seed;
};


float pack_grid_data(uvec3 in_vec) {
	bool invalid_coord = (in_vec.z == 0u);

	float x_val = float(in_vec.x * 10u);
	float y_val = float(in_vec.y * 1u);

	float out_f = (x_val + y_val)/256.0;
	return invalid_coord ? 1.0 : out_f;
}


uvec3 unpack_grid_data(float in_f) {
	bool invalid_coord = (in_f > 1.0 - 0.001);
	in_f = in_f * 256.0;
	return invalid_coord ? uvec3(0u, 0u, 0u) :
		uvec3(uint(floor(in_f/10.0)), uint(mod(in_f, 10.0)), 1u);
}


vec4 coord_to_color(CoordData coord_data, vec2 texture_size) {
	uvec2 grid_idx = uvec2(floor(coord_data.coord / GRID_TEXELS));
	float packed_grid_data = pack_grid_data(uvec3(grid_idx, coord_data.valid_seed ? 1u : 0u));

	highp vec2 grid_uv;
	highp vec2 grid_coord = mod(coord_data.coord, GRID_TEXELS);
	grid_uv = coord_data.valid_seed ? grid_coord / GRID_TEXELS : vec2(0.0);

	return vec4(grid_uv, packed_grid_data, 1.0);
}


CoordData color_to_coord(vec4 color, vec2 texture_size) {
	CoordData coord_data;
	uvec3 grid_data = unpack_grid_data(color.b);
	uvec2 grid_idx = grid_data.xy;
	//vec2 grid_count = ceil(texture_size / GRID_TEXELS);

	coord_data.valid_seed = grid_data.b == 1u ? true : false;

	if (coord_data.valid_seed) {
		highp vec2 uv = color.rg;
		highp vec2 grid_coord = uv * GRID_TEXELS;
		highp vec2 coord = grid_coord + (vec2(grid_idx) * (GRID_TEXELS));
		coord_data.coord = coord;
	} else {
		coord_data.coord = vec2(0.0, 0.0);
	}

	return coord_data;
}


// ---------------------------------------------------------------------------
// Adapted from: https://github.com/godotengine/godot-proposals/issues/9150
vec4 linear_to_srgb(vec4 color) {
	// If going to srgb, clamp from 0 to 1.
	color = clamp(color, vec4(0.0), vec4(1.0));
	const vec3 a = vec3(0.055f);
	color.rgb = mix(
		(vec3(1.0f) + a)
		* pow(color.rgb,
			vec3(1.0f / 2.4f)) - a, 12.92f * color.rgb,
			lessThan(color.rgb, vec3(0.0031308f)));
    return color;
}

vec4 srgb_to_linear(vec4 color) {
	color.rgb = mix(
		pow((color.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)),
		color.rgb * (1.0 / 12.92),
		lessThan(color.rgb, vec3(0.04045))
	);
    return color;
}
// ---------------------------------------------------------------------------
