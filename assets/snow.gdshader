shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const float GRAZING_FADE_BOOST = 4.0; // Wider alignment band at grazing angles
const float HUE_SHIFT = 2.0; // How fast colour turns as you rotate
const float SPARKLE_FADE = 0.15; // Alignment band width

group_uniforms surface;
uniform vec4 albedo : source_color;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float rim : hint_range(0.0, 1.0, 0.01) = 0.07;
uniform float rim_tint : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float sss_strength : hint_range(0.0, 1.0, 0.01) = 0.4;

group_uniforms normals;
uniform sampler2D normal_coarse : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_fine : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(-4.0, 4.0) = 1.0;
uniform float fine_weight : hint_range(0.0, 1.0, 0.01) = 0.4;
uniform vec3 coarse_scale = vec3(0.2);
uniform vec3 fine_scale = vec3(4.0);

group_uniforms sparkle;
uniform float sparkle_scale : hint_range(1.0, 200.0, 0.5) = 40.0;
uniform float sparkle_size : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform float sparkle_threshold : hint_range(0.0, 1.0, 0.01) = 0.8;
uniform float sparkle_amount : hint_range(0.0, 20.0) = 6.0;
uniform float sparkle_tint : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float sparkle_fade_start : hint_range(0.1, 10.0) = 1.0;
uniform float sparkle_fade_end : hint_range(1.0, 10.0) = 6.0;

group_uniforms triplanar;
uniform float blend_sharpness : hint_range(0.0, 150.0, 0.001) = 1.0;

varying vec3 triplanar_pos;
varying vec3 power_normal;

void vertex() {
	vec3 normal = NORMAL;

	TANGENT = vec3(0.0, 0.0, -1.0) * abs(normal.x);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.y);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.z);
	TANGENT = normalize(TANGENT);

	BINORMAL = vec3(0.0, 1.0, 0.0) * abs(normal.x);
	BINORMAL += vec3(0.0, 0.0, -1.0) * abs(normal.y);
	BINORMAL += vec3(0.0, 1.0, 0.0) * abs(normal.z);
	BINORMAL = normalize(BINORMAL);

	power_normal = pow(abs(NORMAL), vec3(blend_sharpness));
	power_normal /= dot(power_normal, vec3(1.0));
	triplanar_pos = VERTEX * vec3(1.0, -1.0, 1.0);
}

vec4 triplanar(sampler2D tex, vec3 weights, vec3 pos) {
	vec4 samp = vec4(0.0);
	samp += texture(tex, pos.xy) * weights.z;
	samp += texture(tex, pos.xz) * weights.y;
	samp += texture(tex, pos.zy * vec2(-1.0, 1.0)) * weights.x;
	return samp;
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

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = metallic;
	RIM = rim;
	RIM_TINT = rim_tint;
	SSS_STRENGTH = sss_strength;

	vec3 coarse = triplanar(normal_coarse, power_normal, triplanar_pos * coarse_scale).rgb;
	vec3 fine = triplanar(normal_fine, power_normal, triplanar_pos * fine_scale).rgb;

	NORMAL_MAP = mix(coarse, fine, fine_weight);
	NORMAL_MAP_DEPTH = normal_scale;

	float dist;
	vec3 seed;
	nearest_crystal(triplanar_pos * sparkle_scale, dist, seed);

	float depth = length(VERTEX);
	float size = sparkle_size * max(depth, 1.0);
	float mask = 1.0 - smoothstep(0.0, size, dist);
	vec3 crystal_normal = normalize(NORMAL + (seed * 2.0 - 1.0));

	float grazing = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float align = 1.0 - abs(dot(crystal_normal, normalize(VIEW)));
	float fade = mix(SPARKLE_FADE, SPARKLE_FADE * GRAZING_FADE_BOOST, grazing);
	float glint = smoothstep(sparkle_threshold, sparkle_threshold + fade, align);

	float hue = seed.b + align * HUE_SHIFT;
	vec3 spectrum = 0.5 + 0.5 * cos(6.2831 * (hue + vec3(0.0, 0.33, 0.67)));
	vec3 tint = mix(vec3(1.0), spectrum, sparkle_tint);
	float t = clamp((depth - sparkle_fade_start) / (sparkle_fade_end - sparkle_fade_start), 0.0, 1.0);
	float distance_fade = pow(1.0 - t, 2.2);

	EMISSION = tint * glint * mask * distance_fade * sparkle_amount;
}
