// 正交下视相机的"夜空"天幕：按世界高度做垂直渐变，unshaded 不吃光照与雾。
// 低世界高度在画面上沿（相机俯角导致），所以渐变方向是"世界 y 越低 = 天上越亮"。
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec4 top_color : source_color = vec4(0.165, 0.239, 0.373, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.043, 0.075, 0.133, 1.0);
// 世界 y 渐变区间：低端=天顶亮色，高端=地线暗色
uniform float grad_top_y : hint_range(-60.0, 20.0) = -46.0;
uniform float grad_bottom_y : hint_range(-40.0, 30.0) = 12.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float t = clamp((world_y - grad_top_y) / (grad_bottom_y - grad_top_y), 0.0, 1.0);
	t = t * t * (3.0 - 2.0 * t); // smoothstep，过渡柔和
	ALBEDO = mix(top_color.rgb, bottom_color.rgb, t).rgb;
}
