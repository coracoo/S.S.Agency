shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity : hint_range(0.0,1.0) = 0.36;
uniform float falloff : hint_range(0.5,4.0) = 3.2;
void fragment() {
	vec2 p = (UV-vec2(0.5))*2.0;
	float soft = exp(-dot(p,p)*falloff)*(1.0-smoothstep(0.72,1.0,length(p)));
	ALBEDO = vec3(0.035,0.044,0.068);
	ALPHA = soft*opacity;
}
