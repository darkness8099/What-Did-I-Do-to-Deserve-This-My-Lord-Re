shader_type canvas_item;
// Effects shared by every pre-rendered sprite. Each one is a 0..1 uniform the owner drives;
// they work per texel of the atlas, so they stay pixel-exact at any zoom. Add new effects
// here, with the same convention, rather than writing one shader per creature.
//
//   wither   - colours dry out towards a dull yellow-brown (weak or dying plants).
//   flash    - the whole sprite goes pale for a moment (being hit).
//   dissolve - texels vanish one by one in a random order, each flashing pale just before
//              it goes (death).

uniform float wither : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform vec3 wither_color : source_color = vec3(0.66, 0.58, 0.30);
uniform vec3 flash_color : source_color = vec3(1.0, 0.94, 0.78);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453);
}

void fragment() {
	if (wither > 0.0) {
		// keep the light and dark of the artwork, swap the hue, and dim it a little
		float lum = dot(COLOR.rgb, vec3(0.30, 0.59, 0.11));
		vec3 dry = wither_color * (0.35 + 1.25 * lum);
		COLOR.rgb = mix(COLOR.rgb, dry, wither * 0.85) * (1.0 - 0.15 * wither);
	}
	if (flash > 0.0) {
		COLOR.rgb = mix(COLOR.rgb, flash_color, flash);
	}
	if (dissolve > 0.0) {
		vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE);
		float h = hash(texel) * 0.88;          // every texel is gone by dissolve = 0.88
		if (h < dissolve) {
			COLOR.a = 0.0;
		} else if (h < dissolve + 0.10) {
			COLOR.rgb = mix(COLOR.rgb, flash_color, 0.65);
		}
	}
}
