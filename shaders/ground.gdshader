shader_type spatial;
render_mode diffuse_burley;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Original procedural one-metre grid: no textures or external assets.
	vec2 cell = abs(fract(world_position.xz - 0.5) - 0.5);
	vec2 edge_width = max(fwidth(world_position.xz), vec2(0.001));
	vec2 line = 1.0 - smoothstep(vec2(0.012), vec2(0.012) + edge_width, cell);
	float grid = max(line.x, line.y);
	float checker = mod(floor(world_position.x / 5.0) + floor(world_position.z / 5.0), 2.0);
	vec3 ground = mix(vec3(0.31, 0.40, 0.33), vec3(0.34, 0.43, 0.36), checker);
	ALBEDO = mix(ground, vec3(0.20, 0.29, 0.23), grid * 0.5);
	ROUGHNESS = 0.95;
}
