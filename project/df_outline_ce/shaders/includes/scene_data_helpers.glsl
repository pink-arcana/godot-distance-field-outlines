// Set 0: Scene
layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
} scene;

// Color image uniform (binding = 1) should be defined separately with restrict
// writeonly/readonly params.
layout(set = 0, binding = 2) uniform sampler2D depth_sampler;
layout(set = 0, binding = 3) uniform sampler2D normal_roughness_sampler;

// Converts coord obtained from gl_GlobalInvocationID
// to normalize [0.0-1.0] for use in texture() sampling functions.
highp vec2 coord_to_uv(ivec2 p_coord) {
	return (vec2(p_coord) + 0.5)/scene.data.viewport_size;
}

// Uncompress the normal roughness texture values.
// Godot automatically applies this conversion for Spatial shaders.
// see: https://github.com/godotengine/godot-docs/issues/9591
highp vec4 unpack_normal_roughness(vec4 p_normal_roughness) {
	float roughness = p_normal_roughness.w;
	if (roughness > 0.5) {
		roughness = 1.0 - roughness;
	}
	roughness /= (127.0 / 255.0);
	return vec4(normalize(p_normal_roughness.xyz * 2.0 - 1.0) * 0.5 + 0.5, roughness);
}


highp vec4 get_normal_roughness_color(ivec2 p_coord) {
	return unpack_normal_roughness(texelFetch(normal_roughness_sampler, p_coord, 0));
}


highp float get_raw_depth(ivec2 p_coord) {
	return texelFetch(depth_sampler, p_coord, 0).r;
}


highp float raw_to_linear_depth(ivec2 p_coord, highp float p_raw_depth) {
	highp vec2 uv = coord_to_uv(p_coord);
	highp vec3 ndc = vec3((uv * 2.0) - 1.0, p_raw_depth);
	highp vec4 view = scene.data.inv_projection_matrix * vec4(ndc, 1.0);
	return -(view.xyz / view.w).z;
}


highp float get_linear_depth(ivec2 p_coord) {
    return raw_to_linear_depth(p_coord, get_raw_depth(p_coord));
}


