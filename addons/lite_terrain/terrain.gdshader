shader_type spatial;
render_mode cull_disabled;
uniform sampler2D layer_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D weight_map : filter_linear, repeat_disable;
uniform float terrain_size = 128.0;
uniform float tile_size = 4.0;
uniform vec2 brush_center;
uniform float brush_radius = 4.0;
uniform bool brush_visible = false;
uniform int brush_shape = 0;
varying vec2 terrain_xz;
void vertex() { terrain_xz = VERTEX.xz; }
void fragment() {
	vec4 w = texture(weight_map, (terrain_xz + vec2(0.5)) / (terrain_size + 1.0));
	float weight_sum = dot(w, vec4(1.0));
	if (weight_sum < 0.001) { w = vec4(1.0, 0.0, 0.0, 0.0); }
	else { w /= weight_sum; }
	vec2 uv = terrain_xz / tile_size;
	ALBEDO = texture(layer_0, uv).rgb * w.r + texture(layer_1, uv).rgb * w.g + texture(layer_2, uv).rgb * w.b + texture(layer_3, uv).rgb * w.a;
	ROUGHNESS = 0.92;
	vec2 delta = abs(terrain_xz - brush_center);
	float d = length(delta);
	if (brush_shape == 2) { d = max(delta.x, delta.y); }
	if (brush_shape == 3) { d = delta.x + delta.y; }
	if (brush_visible) {
		float ring = 1.0 - smoothstep(0.06, 0.15, abs(d - brush_radius));
		ALBEDO = mix(ALBEDO, vec3(0.15, 0.9, 1.0), ring);
		EMISSION = vec3(0.05, 0.4, 0.5) * ring;
	}
}
