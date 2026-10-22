shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform sampler2D art_texture : source_color, filter_linear, repeat_disable;
uniform vec4 appearance_tint : source_color = vec4(1.0);
uniform float scene_light_mix : hint_range(0.0,1.0) = 0.82;
// HD2D 角色光：月光来向的轮廓光 + 暗部吸入夜色，让像素人物贴进场景色温。
uniform vec4 rim_color : source_color = vec4(0.62, 0.72, 0.98, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.4;
uniform vec2 rim_direction = vec2(-1.0, 0.35);
uniform float rim_thickness : hint_range(0.5, 4.0) = 1.5;
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.70, 0.95, 1.0);
uniform float shadow_tint_amount : hint_range(0.0, 1.0) = 0.32;
void vertex() {
	// 与 Sprite3D 原来的 FIXED_Y 相同，偏移和世界身高仍由原节点决定。
	// 阴影pass的INV_VIEW_MATRIX来自灯光；主摄像机矩阵保证同一张竖直薄片投影。
	vec3 camera_right = normalize(vec3(MAIN_CAM_INV_VIEW_MATRIX[0].x,0.0,MAIN_CAM_INV_VIEW_MATRIX[0].z));
	vec3 up = vec3(0.0,1.0,0.0);
	vec3 front = normalize(cross(camera_right,up));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(camera_right,0.0),vec4(up,0.0),vec4(front,0.0),MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec4 art = texture(art_texture,UV) * appearance_tint;
	ALPHA = art.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// 暗部向冷夜色收敛：按原画亮度混 shadow_tint，亮部保留原画色温。
	float lum = dot(art.rgb, vec3(0.2126,0.7152,0.0722));
	float tint_w = (1.0 - smoothstep(0.04, 0.5, lum)) * shadow_tint_amount;
	art.rgb = mix(art.rgb, art.rgb * shadow_tint.rgb, tint_w);
	// 逐像素混合原画自发光与场景漫反射，保留原画明暗；不做频率分离。
	ALBEDO = art.rgb * scene_light_mix;
	vec3 emission = art.rgb * vec3(0.87,0.85,0.82) * (1.0-scene_light_mix);
	// 朝光侧轮廓光：沿 rim_direction 取贴图外侧 alpha，薄片人物也有立体边缘；
	// 双采样取 min 抑制图集相邻帧渗透。
	vec2 texel = 1.0 / vec2(textureSize(art_texture, 0));
	vec2 dir = normalize(rim_direction + vec2(0.00001));
	float out_a = texture(art_texture, UV - dir * texel * rim_thickness).a;
	out_a = min(out_a, texture(art_texture, UV - dir * texel * rim_thickness * 2.0).a);
	float rim = clamp(art.a * (1.0 - out_a), 0.0, 1.0);
	emission += rim_color.rgb * rim * rim_strength;
	EMISSION = emission;
	ROUGHNESS = 1.0;
}
void light() {
	// 包裹漫反射兼容薄片人物；真实光源的方向、距离和遮挡继续参与。
	float wrap = clamp((dot(NORMAL,LIGHT)+0.5)/1.5,0.0,1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap / PI;
}
