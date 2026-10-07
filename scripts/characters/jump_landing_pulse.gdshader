shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity : hint_range(0.0,1.0) = 0.0;
void fragment() {
	float radius = length((UV-vec2(0.5))*2.0);
	float ring = smoothstep(0.52,0.66,radius)*(1.0-smoothstep(0.74,0.95,radius));
	ALBEDO = vec3(0.78,0.82,0.88);
	ALPHA = ring*opacity;
}
