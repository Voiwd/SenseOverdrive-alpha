shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform bool pixelization_enabled = true;
uniform float virtual_height = 540.0;
uniform bool posterization_enabled = true;
uniform float color_levels = 32.0;
uniform bool contrast_enabled = true;
uniform float contrast = 1.0;
uniform bool saturation_enabled = true;
uniform float saturation = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	if (pixelization_enabled) {
		// A single size in physical pixels keeps pixels square at any aspect ratio.
		float pixel_size = max(1.0, 1.0 / (SCREEN_PIXEL_SIZE.y * virtual_height));
		vec2 step_uv = SCREEN_PIXEL_SIZE * pixel_size;
		uv = (floor(uv / step_uv) + 0.5) * step_uv;
	}
	vec3 color = textureLod(screen_texture, uv, 0.0).rgb;
	if (saturation_enabled) {
		float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
		color = mix(vec3(luminance), color, saturation);
	}
	if (contrast_enabled) {
		color = (color - 0.5) * contrast + 0.5;
	}
	color = clamp(color, vec3(0.0), vec3(1.0));
	if (posterization_enabled) {
		float steps = max(color_levels - 1.0, 1.0);
		color = floor(color * steps + 0.5) / steps;
	}
	COLOR = vec4(color, 1.0);
}
