// 夜雨水滩：深色釉面积水 + TIME 驱动的雨点涟漪法线扰动，
// 涟漪环扫过月光/灯笼高光时产生湿地面反光感。边缘径向羽化融入石板。
shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.075, 0.105, 0.155, 1.0);
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.4;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.08;

varying vec2 puddle_uv;

void vertex() {
	puddle_uv = UV;
}

void fragment() {
	vec2 p = puddle_uv - vec2(0.5);
	// 四组确定性圆心、错峰扩散的涟漪环；环带压法线，扫过高光产生闪动。
	float ripple = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 center = vec2(sin(fi * 17.31), cos(fi * 9.17)) * 0.27;
		float phase = fract(TIME * 0.42 + fi * 0.25);
		float dist = length(p - center);
		ripple += (1.0 - smoothstep(0.0, 0.045, abs(dist - phase * 0.42))) * (1.0 - phase);
	}
	NORMAL = normalize(NORMAL + vec3(0.0, 0.0, ripple * ripple_strength));
	ALBEDO = deep_color.rgb;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.55;
	// 径向羽化边缘，中心略实。
	float edge = 1.0 - smoothstep(0.32, 0.5, length(p));
	ALPHA = edge * 0.92;
}
