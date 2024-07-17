shader_type canvas_item;

uniform sampler2D df_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D color_texture : source_color, filter_nearest, repeat_disable;

uniform float input_outline_distance;
uniform float distance_denominator;
uniform vec4 input_outline_color;
uniform vec4 background_color : source_color;
uniform bool use_background_color;
uniform float min_outline_alpha;
uniform float min_outline_distance;
uniform int effect_id;
uniform float smoothing_distance;

// Effect IDs
// Values should match OutlineEffect enum.
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

#include "includes/utils.gdshaderinc"

// ---------------------------------------------------------------------------
// 2D Noise function adapted from Morgan McGuire @morgan3d (BSD license)
// https://www.shadertoy.com/view/4dS3Wd
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.13);
    p3 += dot(p3, p3.yzx + 3.333);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
	float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}
// ---------------------------------------------------------------------------

float remap(float p_value, float p_in_min, float p_in_max, float p_out_min, float p_out_max) {
    return p_out_min + (p_out_max - p_out_min) * (p_value - p_in_min)/(p_in_max - p_in_min);
}

void fragment() {
	vec2 texture_size = vec2(textureSize(df_texture, 0));
	vec2 pixel_size = 1.0/texture_size;
	vec2 tex_coord = UV / pixel_size;

	// Our DF texture is in the same color space we rendered it,
	// so we do not need to adjust it.
	vec4 df_color = textureLod(df_texture, UV, 0.0);
	float dist_n = df_color.r;
    float dist = dist_n * distance_denominator;

	vec4 outline_color = input_outline_color;
	float outline_distance = input_outline_distance;

	// We will keep our color_texture color in SRGB.
	// Since we are in a CanvasItem shader here, our output should be
	// what is rendered to the screen without additional conversions.
	vec4 viewport_color = use_background_color ? background_color : textureLod(color_texture, UV, 0.0);

	// ---------------------------------------------------------------------------
    // OUTLINE EFFECTS
    // Basic examples of outline anti-aliasing and special effects.
    // For more distance field anti-aliasing functions,
    // see https://drewcassidy.me/2020/06/26/sdf-antialiasing/

    vec4 color = vec4(1.0);
    color.a = viewport_color.a;

    if (effect_id == FX_NONE) {
        float outline_mix = dist <= outline_distance ? 1.0 : 0.0;
        color.rgb = mix(viewport_color.rgb, outline_color.rgb, outline_mix * outline_color.a);

    } else if (effect_id == FX_BOX_BLUR) {
        // A basic example of anti-aliasing to test neighbor sampling.
        // For most cases, hardware sampling and/or a more advanced algorithm is probably preferred.
        float neighbor_sum = 0.0;

        for (int i = 0; i < KERNEL_OFFSETS.length(); i++) {
            ivec2 neighbor_coord = ivec2(tex_coord + KERNEL_OFFSETS[i]);
            float neighbor_dist = texelFetch(df_texture, neighbor_coord, 0).r * distance_denominator;
            float neighbor_outline_mix = neighbor_dist <= outline_distance ? 1.0 : 0.0;
            neighbor_sum += neighbor_outline_mix;
        }

        float outline_mix  = neighbor_sum / float(KERNEL_OFFSETS.length());
        color.rgb = mix(viewport_color.rgb, outline_color.rgb, outline_mix * outline_color.a);

    } else if (effect_id == FX_SMOOTHING) {
        // Subtracting only will make outlines thinner, but ensure that smoothing doesn't break
        // on outlines that are power of 2's and therefore at the edge of their JFA offset.
        float dist_min = outline_distance - smoothing_distance * 2.0;
        float dist_max = outline_distance;
        float outline_mix = 1.0 - smoothstep(dist_min, dist_max, dist);
        color.rgb = mix(viewport_color.rgb, outline_color.rgb, outline_mix * outline_color.a);

	} else if (effect_id == FX_SUBPIXEL) {
        float outline_mix = dist <= outline_distance ? 1.0 : 0.0;
        bool is_at_edge = dist < ceil(outline_distance + 0.0001) && dist >= floor(outline_distance);
        float fract_dist = dist - outline_distance;
        outline_mix = is_at_edge ? 1.0 - fract_dist : outline_mix;
        color.rgb = mix(viewport_color.rgb, outline_color.rgb, outline_mix * outline_color.a);



    } else if (effect_id == FX_PADDING || effect_id == FX_INVERTED) {
        // This section creates a framework for controlling the inside
        // and edges of outlines separately.
        bool invert_outlines = false;
        bool inner_outline = false;
        vec4 inner_color = background_color;
        float edge_width = 10.0;
        float inner_mix = 0.0;

        if (effect_id == FX_PADDING) {
            inner_outline = true;
            edge_width = max(1.0, outline_distance * 0.5);
        }

        if (effect_id == FX_INVERTED) {
            invert_outlines = true;
            inner_outline = true;
            inner_color = viewport_color;
            edge_width = max(1.0, outline_distance * 0.25);
        }

        float outline_mix = dist <= outline_distance ? 1.0 : 0.0;

        if (inner_outline) {
            bool is_at_edge = dist <= outline_distance && dist > outline_distance - edge_width;
            outline_mix = is_at_edge ? 1.0 : 0.0;
            inner_mix = dist <= outline_distance && !is_at_edge ? 1.0 : 0.0;
        }

        outline_mix = invert_outlines ? 1.0 - outline_mix : outline_mix;

        color.rgb = mix(viewport_color.rgb, outline_color.rgb, outline_mix * outline_color.a);
        color.rgb = inner_outline ? mix(color.rgb, inner_color.rgb, (inner_mix - outline_mix) * outline_color.a) : color.rgb;

    } else if (effect_id == FX_SKETCH) {
        // Looks best at medium outline widths (~16-64px at 1080p).
		// Numbers can be tweaked to vary the effect
		// and have it work better at different distances.
        float outline_mix = 0.0;
        if (dist <= outline_distance) {
            float max_dist = 0.2 * outline_distance + 5.0 * (noise(UV * 15.0));
            float min_sketch_dist = 0.5 * outline_distance + outline_distance/1.5 * (noise((UV + 0.5) * 25.0));
            float max_sketch_dist = 1.0 * outline_distance - outline_distance/2.0 * (noise((UV + 0.25) * 30.0));

            outline_mix = dist < max_dist ? 1.0 : 0.0;
            outline_mix += dist < max_sketch_dist && dist >= min_sketch_dist ? 1.0 : 0.0;
        }
        color.rgb = mix(viewport_color.rgb, outline_color.rgb, outline_mix * outline_color.a);

    } else if (effect_id == FX_NEON_GLOW) {
        // adapted from:
        // https://shaderfun.com/2018/07/01/signed-distance-fields-part-7-some-simple-effects/
        color.rgb = viewport_color.rgb;
        if (dist <= outline_distance) {
            float value = 1.0 - dist / outline_distance;
            vec4 glow_low = outline_color;
            vec4 glow_high = vec4(1.0,1.0,1.0,1.0); // white
            float neon_power = 4.0;
            color.rgb = mix(color.rgb, glow_low.rgb, value * glow_low.a);
            color.rgb += pow(value, neon_power) * glow_high.rgb;
        }

    } else if (effect_id == FX_RAINBOW_ANIMATION) {
        // Colors from https://www.flagcolorcodes.com/pride-rainbow
        // and pre-converted to linear RGB.
        // The RAINBOW array is ordered as red, purple, blue, etc.
        // But colors are displayed as red, orange, yellow, etc.
        const vec4 RAINBOW[6] = {
            vec4(0.775, 0.000, 0.000, 1.0),
            vec4(0.171, 0.022, 0.223, 1.0),
            vec4(0.017, 0.051, 0.270, 1.0),
            vec4(0.000, 0.215, 0.019, 1.0),
            vec4(0.999, 0.846, 0.000, 1.0),
            vec4(0.999, 0.262, 0.000, 1.0)};

        // Time loops every MAX_TIME msec, so we will fade to black before
        // the time is up. Could be looped by syncing the
        // animation with the start/end times.
        const float MAX_TIME = 20000.0;
        const float FADE_TIME = 3000.0;
        const float SPEED = 0.75;

		float time = float(int(TIME * 1000.0) % int(MAX_TIME));

        float fade_mix = smoothstep(MAX_TIME - FADE_TIME, MAX_TIME, time);
        float t_offset = SPEED * time * 0.001;
        float stripe_width = max(10.0, outline_distance / float(RAINBOW.length()));

        vec4 rainbow_color = background_color;

        if (dist < outline_distance) {
            int idx = 0;
            float dist_fract = 0.0;

            float dist_offset = stripe_width * t_offset;
            float start_offset = mod(dist_offset, stripe_width);
            int idx_offset = int(floor(dist_offset / stripe_width));

            for (int i = 0; i < idx_offset + 1; i++) {
                float d_max = max(start_offset + float(i) * stripe_width, 1.0);
                int idx = int(mod(float(i - idx_offset), float(RAINBOW.length())));
                if (dist < d_max) {
                    rainbow_color = RAINBOW[idx];
                    break;
                }
            }
        }
        color.rgb = mix(rainbow_color.rgb, viewport_color.rgb, fade_mix);
		color = linear_to_srgb(color);

    } else if (effect_id == FX_STEPPED_DISTANCE_FIELD) {
        // Adapted from Disk - distance 2D Copyright 2020 Inigo Quilez
        // MIT License: https://www.shadertoy.com/view/3ltSW2
        color.rgb = viewport_color.rgb;
        float stripe_width = 64.0;

        if (dist <= outline_distance) {
            float d = mod(dist, stripe_width)/stripe_width;
            vec3 col = outline_color.rgb;
            col *= 1.0 - exp(-2.0*abs(d));
            col *= 0.9 + 0.2*cos(50.0*d);
            col = mix(col, vec3(1.0), 1.0-smoothstep(0.0,0.01,abs(d)));
            color.rgb = mix(color.rgb, col, outline_color.a);
        }

    } else if (effect_id == FX_RAW_DISTANCE_FIELD) {
        color.rgb = mix(vec3(0.0), vec3(1.0), dist_n);
    }

	COLOR = color;
}
