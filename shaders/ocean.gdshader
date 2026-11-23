shader_type spatial;
// Low-poly sea: rolling waves with flat facets, whitecaps on the crests in rough weather.
// The weather scene (scripts/weather_fx.gd) tweens these uniforms.

uniform vec3 water_color : source_color = vec3(0.12, 0.38, 0.6);
uniform vec3 foam_color : source_color = vec3(0.9, 0.95, 1.0);
// How high the waves roll out at sea (metres)
uniform float wave_height = 0.3;
uniform float wave_speed = 1.0;
// 0 = no whitecaps, 1 = storm
uniform float choppiness = 0.0;
// Water this close to the island centre stays calm, so the harbour and coves stay flat
uniform float calm_radius = 40.0;

// Whitecap amount per triangle (flat, so the foam comes in low-poly patches)
varying flat float foam;

float waves(vec2 p, float t) {
	float h = sin(dot(p, vec2(0.11, 0.05)) + t * 1.1);
	h += 0.6 * sin(dot(p, vec2(-0.07, 0.14)) + t * 1.4);
	h += 0.35 * sin(dot(p, vec2(0.19, -0.16)) + t * 2.1);
	return h / 1.95;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amp = wave_height * (0.15 + 0.85 * smoothstep(calm_radius, calm_radius + 35.0, length(w.xz)));
	float h = waves(w.xz, TIME * wave_speed);
	// Whitecaps on the top of the swell where the short chop also peaks, only out at sea
	float chop = sin(dot(w.xz, vec2(0.55, 0.42)) + TIME * 2.7) * sin(dot(w.xz, vec2(-0.38, 0.61)) - TIME * 2.2);
	foam = smoothstep(0.2, 0.8, h) * smoothstep(0.35, 0.75, chop) * smoothstep(calm_radius, calm_radius + 20.0, length(w.xz));
	// Waves only ever go down from sea level, so the harbour and deep-sea patches always show
	VERTEX.y += (h - 1.0) * amp;
}

void fragment() {
	// Flat facets, to match the Kenney blocks
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	float f = step(0.5, foam) * choppiness;
	ALBEDO = mix(water_color, foam_color, f);
	ROUGHNESS = mix(0.2, 0.7, f);
	SPECULAR = 0.6;
}
