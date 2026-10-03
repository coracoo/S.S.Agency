shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform sampler2D art_texture : source_color, filter_nearest, repeat_disable;
uniform float scene_light_mix : hint_range(0.0,1.0) = 0.38;
void vertex() {
	// 与 Sprite3D 原来的 FIXED_Y 相同，偏移和世界身高仍由原节点决定。
	vec3 camera_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = vec3(0.0,1.0,0.0);
	vec3 front = normalize(cross(camera_right,up));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(camera_right,0.0),vec4(up,0.0),vec4(front,0.0),MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec4 art = texture(art_texture,UV);
	ALPHA = art.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// 逐像素混合原画自发光与场景漫反射，保留原画明暗；不做频率分离。
	ALBEDO = art.rgb * scene_light_mix;
	EMISSION = art.rgb * vec3(0.77,0.82,0.95) * (1.0-scene_light_mix);
	ROUGHNESS = 1.0;
}
void light() {
	// 包裹漫反射兼容薄片人物；真实光源的方向、距离和遮挡继续参与。
	float wrap = clamp((dot(NORMAL,LIGHT)+0.5)/1.5,0.0,1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap / PI;
}
