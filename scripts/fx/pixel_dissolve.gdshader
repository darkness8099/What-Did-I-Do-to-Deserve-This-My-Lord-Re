shader_type canvas_item;
// Death dissolve shared by every pre-rendered sprite: texels vanish one by one in a random
// order as `progress` goes 0 -> 1, each flashing pale just before it goes. Works per texel of
// the atlas, so it stays pixel-exact at any zoom.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.94, 0.78);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453);
}

void fragment() {
	if (progress > 0.0) {
		vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE);
		float h = hash(texel) * 0.88;          // every texel is gone by progress = 0.88
		if (h < progress) {
			COLOR.a = 0.0;
		} else if (h < progress + 0.10) {
			COLOR.rgb = mix(COLOR.rgb, flash_color, 0.65);
		}
	}
}
