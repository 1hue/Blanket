shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back;

const float SUN_FADE = 0.4;
const float HUE_SWEEP = 0.6;
const float SPARKLE_SCALE = 40.0;

uniform float sparkle_size : hint_range(0.0, 0.5, 0.01) = 0.2;
uniform float crystal_spread : hint_range(0.0, 1.0, 0.01) = 0.31;
uniform float zone_threshold : hint_range(0.0, 1.0, 0.01) = 0.91;
uniform float sun_threshold : hint_range(0.0, 1.0, 0.01) = 0.93;
uniform float sun_amount : hint_range(0.0, 20.0) = 16.0;
uniform float sun_tint : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float sparkle_fade_start : hint_range(0.1, 10.0) = 1.0;
uniform float sparkle_fade_end : hint_range(1.0, 10.0) = 7.0;

varying vec3 triplanar_pos;
varying float view_depth;

void vertex() {
	triplanar_pos = VERTEX * vec3(1.0, -1.0, 1.0);
	view_depth = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

vec3 hash33(vec3 cell) {
	vec3 h = fract(cell * vec3(0.1031, 0.1030, 0.0973));
	h += dot(h, h.yxz + 33.33);
	return fract((h.xxy + h.yxx) * h.zyx);
}

// Nearest crystal in a 3x3x3 neighbourhood, with its own random orientation
void nearest_crystal(vec3 pos, out float dist, out vec3 seed) {
	vec3 cell = floor(pos);
	vec3 local = fract(pos);

	dist = 8.0;
	seed = vec3(0.0);

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 point = hash33(cell + offset);
				vec3 delta = offset + point - local;
				float d = dot(delta, delta);

				if (d < dist) {
					dist = d;
					seed = point;
				}
			}
		}
	}

	dist = sqrt(dist);
}

vec3 spectral(float t) {
	vec3 centre = vec3(0.8, 0.5, 0.2);
	vec3 d = (vec3(t) - centre) / 0.25;

	return exp(-d * d);
}

void fragment() {
	ALBEDO = vec3(0.0);
}

void light() {
	float dist;
	vec3 seed;
	nearest_crystal(triplanar_pos * SPARKLE_SCALE, dist, seed);

	float mask = 1.0 - smoothstep(0.0, sparkle_size, dist);
	vec3 crystal_normal = normalize(NORMAL + (seed * 2.0 - 1.0) * crystal_spread);
	vec3 half_vec = normalize(LIGHT + VIEW);

	// Where the sun reflects off the surface - no sparkle outside this
	float sun_zone = smoothstep(zone_threshold, 1.0, max(dot(NORMAL, half_vec), 0.0));

	// Inside it, the crystal's own tilt decides
	float align = max(dot(crystal_normal, half_vec), 0.0);
	float glint = smoothstep(sun_threshold, sun_threshold + SUN_FADE, align);

	// Where the crystal sits in its own visibility window - drives the colour sweep
	float sweep = (align - sun_threshold) / SUN_FADE;
	vec3 spectrum = spectral(fract(seed.b + sweep * HUE_SWEEP));
	vec3 tint = mix(vec3(1.0), spectrum, sun_tint);

	float t = clamp((view_depth - sparkle_fade_start) / (sparkle_fade_end - sparkle_fade_start), 0.0, 1.0);
	float distance_fade = pow(1.0 - t, 2.2);

	SPECULAR_LIGHT += tint * sun_zone * glint * mask * distance_fade * sun_amount * LIGHT_COLOR * ATTENUATION;
}
