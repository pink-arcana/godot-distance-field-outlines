shader_type spatial;
render_mode blend_mix, unshaded;

uniform uint depth_layer = 524288; // layer 20
uniform float depth_max = 40.0;

varying float camera_distance_n;

void vertex() {
	camera_distance_n = distance(NODE_POSITION_WORLD + VERTEX, CAMERA_POSITION_WORLD)/depth_max;	
}

void fragment() {
	bool render_depth = (CAMERA_VISIBLE_LAYERS & depth_layer) == depth_layer;
	ALBEDO = vec3(camera_distance_n, 0.0, 0.0);
	ALPHA = render_depth ? 1.0 : 0.0;
}
