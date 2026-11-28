shader_type spatial;
render_mode diffuse_burley;

varying vec3 world_position;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float meadow_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), u.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	// Broad irregular patches, soft middle-scale variation and fine turf grain.
	// No checkerboard, metre grid, textures or hard cell edges.
	float broad = meadow_noise(p * 0.065 + vec2(8.7, 3.1));
	float middle = meadow_noise(p * 0.48 + vec2(19.2, 5.8));
	float detail = meadow_noise(p * 3.2);
	float grain = meadow_noise(p * 23.0);
	// Derivative-aware attenuation keeps the small detail calm at a distance.
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float fine_weight = 1.0 - smoothstep(0.025, 0.16, footprint);
	vec3 green = mix(vec3(0.14, 0.27, 0.065), vec3(0.30, 0.43, 0.14), broad);
	green += (middle - 0.5) * vec3(0.055, 0.065, 0.025);
	green += (detail - 0.5) * vec3(0.033, 0.045, 0.015);
	green += (grain - 0.5) * vec3(0.045, 0.050, 0.020) * fine_weight;
	ALBEDO = green;
	ROUGHNESS = 0.97;
	SPECULAR = 0.18;
}
