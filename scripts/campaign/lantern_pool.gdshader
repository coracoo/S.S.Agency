shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// 灯笼地面光池：暖色径向衰减 + 轻微呼吸，additive 贴地，不占真实光源与阴影预算。
uniform vec4 pool_color : source_color = vec4(1.0, 0.78, 0.45, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.5;
uniform float breathe : hint_range(0.0, 1.0) = 0.12;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float d = length(p);
	float glow = exp(-d * d * 3.4) * (1.0 - smoothstep(0.82, 1.0, d));
	float flicker = 1.0 + breathe * sin(TIME * 2.3) * sin(TIME * 3.7 + 1.3);
	ALBEDO = pool_color.rgb;
	ALPHA = glow * intensity * flicker;
}
