shader_type canvas_item;
// Treffer-Blitz und Glitch-Effekt (Zeilenversatz) für Kämpfer.

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec4 split = vec4(0.0);
	if (glitch > 0.0) {
		float row = floor(uv.y * 30.0);
		float n = hash(row);
		if (n < glitch * 0.7) {
			uv.x += (n - 0.35) * 0.06 * glitch;
		}
		split = texture(TEXTURE, uv + vec2(0.01 * glitch, 0.0));
	}
	vec4 c = texture(TEXTURE, uv);
	if (glitch > 0.0) {
		c.r = max(c.r, split.r * split.a * glitch);
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	COLOR = c * COLOR;
}
