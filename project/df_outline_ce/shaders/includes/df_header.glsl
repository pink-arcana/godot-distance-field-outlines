struct DFData {
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

layout(set = 1, binding = 0, std140) uniform DFDataBlock {
	DFData data;
} df;


// ---------------------------------------------------------------------------

const float EPSILON = 0.001;
const ivec2 INVALID_COORD = ivec2(32000, 32000);

// Effect IDs
// Values should match OutlineEffect enum in OutlineSettings class.
const int FX_NONE = 0;
const int FX_BOX_BLUR = 1;
const int FX_SMOOTHING = 2;
const int FX_SUBPIXEL = 3;
const int FX_PADDING = 4;
const int FX_INVERTED = 5;
const int FX_SKETCH = 6;
const int FX_NEON_GLOW = 7;
const int FX_RAINBOW_ANIMATION = 8;
const int FX_STEPPED_DISTANCE_FIELD = 9;
const int FX_RAW_DISTANCE_FIELD = 10;

// Depth fade mode
// Values should match DepthFadeMode enum in OutlineSettings class.
const int DEPTH_FADE_MODE_NONE = 0;
const int DEPTH_FADE_MODE_ALPHA = 1;
const int DEPTH_FADE_MODE_WIDTH = 2;
const int DEPTH_FADE_MODE_ALPHA_AND_WIDTH = 3;


const ivec2 KERNEL_OFFSETS[9] = {
	ivec2(-1,-1), ivec2(0,-1), ivec2(1,-1),
	ivec2(-1,0), ivec2(0,0), ivec2(1,0),
	ivec2(-1,1), ivec2(0,1), ivec2(1,1) };


const ivec2 NEIGHBOR_OFFSETS[8] = {
	ivec2(-1,-1), ivec2(0,-1), ivec2(1,-1),
	ivec2(-1,0), ivec2(1,0),
	ivec2(-1,1), ivec2(0,1), ivec2(1,1) };


const ivec2 CORNER_OFFSETS[4] = {
	ivec2(-1,-1), ivec2(1,-1),
	ivec2(-1,1), ivec2(1,1) };


float dist_squared(ivec2 p_coord_a, ivec2 p_coord_b) {
	vec2 coord_a = vec2(p_coord_a);
	vec2 coord_b = vec2(p_coord_b);
	return (coord_a.x - coord_b.x) * (coord_a.x - coord_b.x) + (coord_a.y - coord_b.y) * (coord_a.y - coord_b.y);
}


float remap(float p_value, float p_in_min, float p_in_max, float p_out_min, float p_out_max) {
    return p_out_min + (p_out_max - p_out_min) * (p_value - p_in_min)/(p_in_max - p_in_min);
}


float get_depth_value(float p_depth) {
	return smoothstep(df.data.depth_fade_start, df.data.depth_fade_end, p_depth);
}


float get_outline_distance(float p_depth_value, int p_mode) {
    if (p_mode == DEPTH_FADE_MODE_WIDTH || p_mode == DEPTH_FADE_MODE_ALPHA_AND_WIDTH) {
		return remap(1.0 - p_depth_value, 0.0, 1.0, df.data.min_outline_distance, df.data.outline_distance);
    } else {
        return df.data.outline_distance;
    }
}


float get_outline_alpha(float p_depth_value, int p_mode) {
    if (p_mode == DEPTH_FADE_MODE_ALPHA || p_mode == DEPTH_FADE_MODE_ALPHA_AND_WIDTH) {
        return remap(1.0 - p_depth_value, 0.0, 1.0, df.data.min_outline_alpha, df.data.outline_color.a);
    } else {
        return df.data.outline_color.a;
    }
}




