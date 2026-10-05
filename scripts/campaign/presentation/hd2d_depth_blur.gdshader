// Compatibility真实深度重建；清晰世界Z带保护可玩区与Sprite3D角色全身。
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
	vec3 world_position = (INV_VIEW_MATRIX * view_position).xyz;
	float far_amount = smoothstep(0.0, fade_distance, clear_far_z - world_position.z);
	float near_amount = smoothstep(0.0, fade_distance, world_position.z - clear_near_z);
	float blur_amount = max(far_amount, near_amount);
	if (effect_mode == 1 && blur_amount < 0.001) { discard; }
	vec3 sharp = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 result = sharp;
	if (effect_mode == 1 && blur_amount > 0.001) {
		// 实测llvmpipe空间屏幕纹理LOD不产生模糊，显式九点高斯核避免依赖mip。
		vec2 step_uv = vec2(blur_amount * max_blur_radius) / VIEWPORT_SIZE;
		result = sharp * 0.25;
		result += textureLod(screen_texture, SCREEN_UV + vec2(step_uv.x, 0.0), 0.0).rgb * 0.125;
		result += textureLod(screen_texture, SCREEN_UV - vec2(step_uv.x, 0.0), 0.0).rgb * 0.125;
		result += textureLod(screen_texture, SCREEN_UV + vec2(0.0, step_uv.y), 0.0).rgb * 0.125;
		result += textureLod(screen_texture, SCREEN_UV - vec2(0.0, step_uv.y), 0.0).rgb * 0.125;
		result += textureLod(screen_texture, SCREEN_UV + step_uv, 0.0).rgb * 0.0625;
		result += textureLod(screen_texture, SCREEN_UV - step_uv, 0.0).rgb * 0.0625;
		result += textureLod(screen_texture, SCREEN_UV + vec2(step_uv.x, -step_uv.y), 0.0).rgb * 0.0625;
		result += textureLod(screen_texture, SCREEN_UV + vec2(-step_uv.x, step_uv.y), 0.0).rgb * 0.0625;
	} else if (effect_mode == 2) {
		result = vec3(near_amount, 1.0 - blur_amount, far_amount);
	}
	ALBEDO = result;
	ALPHA = 1.0;
}
