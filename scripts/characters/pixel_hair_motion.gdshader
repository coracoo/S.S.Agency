shader_type canvas_item;
// 只移动已拆出的真实尾尖。源像素整数位移，根部固定，主体和脚点不动。
uniform vec2 canvas_size = vec2(192.0,160.0);
uniform float root_y = 64.0;
uniform float full_motion_y = 70.0;
uniform float offset_px = 0.0;
void fragment() {
	float row = floor(UV.y * canvas_size.y);
	float displacement = round(clamp((row - root_y) / (full_motion_y - root_y), 0.0, 1.0) * offset_px);
	vec2 sample_uv = UV - vec2(displacement / canvas_size.x, 0.0);
	COLOR = texture(TEXTURE, sample_uv);
}
