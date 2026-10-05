// Compatibility真实深度重建；正式连续地图按相机视空间划分近、中、远。
// 全屏quad透明通道最早绘制；CanvasLayer和其他透明效果随后正常绘制。
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
// 0空操作、1景深、2深度检查（绿色清晰，红色近景，蓝色远景）、3屏幕拷贝诊断。
uniform int effect_mode = 1;
uniform float clear_far_z = -4.2;
uniform float clear_near_z = 3.8;
uniform float fade_distance = 3.4;
uniform float max_blur_radius = 6.0;
// 旧第二夜试点继续使用原世界Z带，连续寺域显式开启相机焦距。
uniform bool camera_focus_mode = false;
uniform float focus_near_distance = 10.0;
uniform float focus_far_distance = 16.1;
uniform float near_fade_distance = 3.8;
uniform float far_fade_distance = 5.0;
uniform float near_blur_radius = 8.0;
uniform float far_blur_radius = 4.5;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// Compatibility低精度屏幕拷贝存在往返量化；清晰区直接保留原帧缓冲。
	if (effect_mode == 0) { discard; }
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 view_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_position /= view_position.w;
	float far_amount;
	float near_amount;
	if (camera_focus_mode) {
		// 相机前方为负Z；这是沿视轴的真实距离，和物体世界Z或屏幕高度无关。
		float view_distance = -view_position.z;
		far_amount = smoothstep(0.0, far_fade_distance, view_distance - focus_far_distance);
		near_amount = smoothstep(0.0, near_fade_distance, focus_near_distance - view_distance);
	} else {
		vec3 world_position = (INV_VIEW_MATRIX * view_position).xyz;
		far_amount = smoothstep(0.0, fade_distance, clear_far_z - world_position.z);
		near_amount = smoothstep(0.0, fade_distance, world_position.z - clear_near_z);
	}
	float blur_amount = max(far_amount, near_amount);
	if (effect_mode == 1 && blur_amount < 0.001) { discard; }
	vec3 sharp = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 result = sharp;
	if (effect_mode == 1 && blur_amount > 0.001) {
		// Compatibility屏幕纹理不依赖mip。13点错位双环避免旧3×3核把木缝复制成整排横纹。
		// 权重0.20+4×0.125+8×0.0375=1；近环保留柔和主体，外环只贡献少量散焦。
		float radius = camera_focus_mode ? max(near_amount * near_blur_radius, far_amount * far_blur_radius) : blur_amount * max_blur_radius;
		vec2 step_uv = vec2(radius) / VIEWPORT_SIZE;
		result = sharp * 0.20;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(0.26, 0.22), 0.0).rgb * 0.125;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(-0.22, 0.26), 0.0).rgb * 0.125;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(-0.26, -0.22), 0.0).rgb * 0.125;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(0.22, -0.26), 0.0).rgb * 0.125;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(0.93, 0.36), 0.0).rgb * 0.0375;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(0.36, 0.93), 0.0).rgb * 0.0375;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(-0.36, 0.93), 0.0).rgb * 0.0375;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(-0.93, 0.36), 0.0).rgb * 0.0375;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(-0.93, -0.36), 0.0).rgb * 0.0375;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(-0.36, -0.93), 0.0).rgb * 0.0375;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(0.36, -0.93), 0.0).rgb * 0.0375;
		result += textureLod(screen_texture, SCREEN_UV + step_uv * vec2(0.93, -0.36), 0.0).rgb * 0.0375;
	} else if (effect_mode == 2) {
		result = vec3(near_amount, 1.0 - blur_amount, far_amount);
	}
	ALBEDO = result;
	ALPHA = 1.0;
}
