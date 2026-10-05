// 落叶堆：暗橙底色 + 径向羽化 + 两层 value noise 打碎边缘，读作堆积的落叶而非色块。
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 pile_color : source_color = vec4(0.30, 0.19, 0.10, 1.0);
uniform float edge_softness : hint_range(0.0, 1.0) = 0.28;

varying vec2 pile_uv;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	pile_uv = UV;
}

void fragment() {
	vec2 p = pile_uv - vec2(0.5);
	float r = length(p);
	// 两层噪声：低频决定轮廓起伏，高频做内部斑驳。
	float body = vnoise(pile_uv * 5.0) * 0.55 + vnoise(pile_uv * 13.0) * 0.45;
	float edge = 1.0 - smoothstep(0.5 - edge_softness - body * 0.14, 0.5, r + body * 0.06);
	float shade = 0.82 + body * 0.36;
	ALBEDO = pile_color.rgb * shade;
	ALPHA = edge * 0.9;
}
