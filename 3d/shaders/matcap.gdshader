shader_type spatial;
render_mode unshaded;


uniform sampler2D matcap : source_color, hint_default_black;
uniform sampler2D albedo_texture : source_color, filter_linear;
uniform vec4 base_color : source_color = vec4(1.0);

vec2 generate_matcap_uv(vec3 _normal, vec3 _node_position_view) {
	vec3 cross_space = cross(normalize(_node_position_view), _normal); // cross products the normal with it's base position
	vec2 mat_space = vec2(cross_space.y * 1.0, cross_space.x); // converts to a Vec2 UV, having to switch x and y
	mat_space *= vec2(-0.5, -0.5); // modifies the mat space's size to fit into uv coords, & flips it
	mat_space += vec2(0.5, 0.5); // transforms the mat space into uv coords
	return mat_space; // export the final uv's
}

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
	vec2 matcap_uv = (generate_matcap_uv(NORMAL, NODE_POSITION_VIEW)); // Matcap UV's
	vec3 _matcap = texture(matcap, matcap_uv).rgb; // Matcap Texture
	vec3 albedo = texture(albedo_texture, UV).rgb;
	ALBEDO = _matcap * base_color.rgb * albedo; // Sets the albedo to the matcap texture.
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
