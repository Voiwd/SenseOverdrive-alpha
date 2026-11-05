shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 panels[16];
uniform int panel_count = 0;
uniform float blur_lod : hint_range(0.0, 5.0) = 2.5;
void fragment() {
 float mask = 0.0;
 for (int i = 0; i < panel_count; i++) {
  vec2 extent = panels[i].zw / SCREEN_PIXEL_SIZE;
  vec2 p = (SCREEN_UV - panels[i].xy - panels[i].zw * 0.5) / SCREEN_PIXEL_SIZE;
  vec2 q = abs(p) - extent * 0.5 + 14.0;
  float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 14.0;
  mask = max(mask, 1.0 - smoothstep(-1.0, 1.0, d));
 }
 if (mask <= 0.0) { discard; }
 COLOR = vec4(textureLod(screen, SCREEN_UV, blur_lod).rgb, mask);
}
