shader_type spatial;

uniform vec3 tint : source_color;
uniform sampler2D tex;
uniform float tiling : hint_range(0.0, 1.0) = 1.0;

uniform float metalic_value : hint_range(0.0, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	// Called for every vertex the material is visible on.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Texture projections are in world space, so their weights must be too.
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	// Called for every pixel the material is visible on.
	vec2 uv_x = world_position.zy * tiling; // Plano YZ (olhando de lado no eixo X)
    vec2 uv_y = world_position.xz * tiling; // Plano XZ (olhando de cima no eixo Y)
    vec2 uv_z = world_position.xy * tiling; // Plano XY (olhando de frente no eixo Z)
	
	vec4 tex_x = texture(tex, uv_x);
    vec4 tex_y = texture(tex, uv_y);
    vec4 tex_z = texture(tex, uv_z);
	
	vec3 weights = abs(normalize(world_normal));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec4 pixel = tex_x * weights.x + tex_y * weights.y + tex_z * weights.z;
	
	ALBEDO = pixel.rgb * tint;
	METALLIC = metalic_value;
	ROUGHNESS = roughness_value;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
