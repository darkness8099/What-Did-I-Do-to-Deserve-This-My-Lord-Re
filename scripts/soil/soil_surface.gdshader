shader_type canvas_item;
// Soil surface by nutrient (sample for task ART-003). One quad covers the whole map.
//
// nutrient_tex has one texel per cell: R = nutrient shown for that cell, G = 1 if the
// cell is soil. Nothing here knows about creatures; cost does not depend on their number.
//
// Two effects, joined without a break:
//   1..9   green moss spreading over the soil: how green a block is tells how much it holds
//   10+    the moss is complete; pale gold veins appear on it and thicken up to 16
// Above 16 is a placeholder (veins plus a gold wash); the top look will be designed apart.
//
// The patterns come from noise that runs across the whole map, so no two blocks look the
// same and nothing repeats per cell.

uniform sampler2D nutrient_tex : filter_linear, repeat_disable;
uniform vec2 grid_size = vec2(40.0, 24.0);
uniform float soften : hint_range(0.0, 1.0) = 0.35;      // 0: each block on its own; 1: neighbours blend
uniform float outline : hint_range(0.0, 1.0) = 1.0;     // dark rim round moss and veins
uniform float edge_wobble : hint_range(0.0, 0.5) = 0.28; // cells; how ragged the join between blocks is
uniform float moss_scale = 2.6;                          // moss patches per cell
uniform float vein_scale = 2.3;

uniform vec3 moss_dark : source_color = vec3(0.27, 0.43, 0.21);
uniform vec3 moss_light : source_color = vec3(0.39, 0.57, 0.27);
uniform vec3 moss_rim : source_color = vec3(0.12, 0.19, 0.10);
uniform vec3 gold : source_color = vec3(0.95, 0.80, 0.42);
uniform vec3 gold_rim : source_color = vec3(0.33, 0.25, 0.09);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Gradient noise (smooth, no blocky lattice), returned in about 0..1.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a0 = hash(i) * 6.2831853;
	float a1 = hash(i + vec2(1.0, 0.0)) * 6.2831853;
	float a2 = hash(i + vec2(0.0, 1.0)) * 6.2831853;
	float a3 = hash(i + vec2(1.0, 1.0)) * 6.2831853;
	float n0 = dot(vec2(cos(a0), sin(a0)), f);
	float n1 = dot(vec2(cos(a1), sin(a1)), f - vec2(1.0, 0.0));
	float n2 = dot(vec2(cos(a2), sin(a2)), f - vec2(0.0, 1.0));
	float n3 = dot(vec2(cos(a3), sin(a3)), f - vec2(1.0, 1.0));
	return mix(mix(n0, n1, u.x), mix(n2, n3, u.x), u.y) * 0.7 + 0.5;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v / 0.9375;
}

void fragment() {
	vec2 cu = UV * grid_size;                       // position in cells
	// Noise is read on a turned copy of the map so its lattice never lines up with the cells.
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * cu;
	vec4 cell = texelFetch(nutrient_tex, ivec2(floor(cu)), 0);
	float soil = cell.g;
	// Block borders are read through a small wobble, so where two neighbours differ the
	// join is a ragged line instead of a ruler-straight one. Never reads across into a
	// cell that is not soil.
	vec2 wob = (vec2(vnoise(q * 1.9), vnoise(q * 1.9 + 31.0)) - 0.5) * 2.0 * edge_wobble;
	vec4 near = texelFetch(nutrient_tex, ivec2(floor(cu + wob)), 0);
	float own = mix(cell.r, near.r, near.g);
	float n = mix(own, texture(nutrient_tex, UV).r, soften);

	// --- effect one: moss coverage, 0 at nutrient 0, complete at 9
	float cover = clamp(n / 9.0, 0.0, 1.0);
	// fbm bunches up round 0.5; stretching it makes coverage rise evenly from 1 to 9.
	float f = clamp((fbm(q * moss_scale) - 0.30) / 0.40, 0.0, 1.0);
	float th = mix(0.96, 0.03, cover);
	float present = smoothstep(0.0, 0.8, n);
	float moss = smoothstep(th, th + 0.03, f) * present;
	float moss_edge = smoothstep(th - 0.09, th - 0.05, f) * present;
	float tone = smoothstep(0.50, 0.54, fbm(q * 3.2 + 3.0));
	vec3 col = moss_rim;
	float a = moss_edge * 0.8 * outline;
	col = mix(col, mix(moss_dark, moss_light, tone), moss);
	a = max(a, moss);

	// --- effect two: gold veins, from 10 up, full width at 16
	float g = clamp((n - 9.0) / 7.0, 0.0, 1.0);
	vec2 wp = q * vein_scale + vec2(fbm(q * 1.3), fbm(q * 1.3 + 5.0)) * 1.2;
	float ridge = 1.0 - abs(2.0 * vnoise(wp) - 1.0);
	float w = 0.03 + 0.11 * g;
	float on = step(0.001, g);
	float vein = smoothstep(1.0 - w, 1.0 - w + 0.03, ridge) * on;
	float vein_edge = smoothstep(1.0 - w - 0.07, 1.0 - w - 0.04, ridge) * on;
	col = mix(col, gold_rim, vein_edge * outline);
	col = mix(col, gold, vein);
	a = max(a, max(vein, vein_edge * outline));

	// --- placeholder above 16: a gold wash over everything
	float over = clamp((n - 16.0) / 6.0, 0.0, 1.0);
	col = mix(col, gold, over * 0.6);

	COLOR = vec4(col, a * soil);
}
