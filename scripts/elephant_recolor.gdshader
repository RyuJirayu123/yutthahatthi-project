shader_type canvas_item;
render_mode blend_disabled, unshaded;
// Recolours the elephant sprite sheet for one ElephantDef, keeping the painted shading: the red
// cloth (and crest and jewels) becomes `cloth`, the blue-grey skin `skin`, the gold trim `trim`.
// ElephantRig renders the sheet through this once per elephant (blend_disabled keeps the alpha
// exact in the offscreen pass).

uniform vec4 cloth = vec4(0.78, 0.1, 0.12, 1.0);
uniform vec4 skin = vec4(0.45, 0.47, 0.55, 1.0);
uniform vec4 trim = vec4(0.91, 0.7, 0.23, 1.0);

// typical colours in the painted sheet (hue, saturation, value) and the skin's mid value
const vec3 SRC_CLOTH = vec3(0.979, 0.76, 0.72);
const vec3 SRC_GOLD = vec3(0.103, 0.55, 0.86);
const float SRC_SKIN_V = 0.55;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// 1 when hue `h` is within `w` of `c` (hue wraps round), fading out over the outer part
float hue_near(float h, float c, float w) {
	float d = abs(fract(h - c + 0.5) - 0.5);
	return 1.0 - smoothstep(w * 0.6, w, d);
}

// a painted pixel of hsv `px` moved from the sheet's colour `src` to `dst`, keeping its shade
vec3 shift(vec3 px, vec3 src, vec3 dst) {
	vec3 t = rgb2hsv(dst);
	return hsv2rgb(vec3(t.x, clamp(px.y * t.y / src.y, 0.0, 1.0), clamp(px.z * t.z / src.z, 0.0, 1.0)));
}

void fragment() {
	vec4 px = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(px.rgb);
	float wc = hue_near(hsv.x, SRC_CLOTH.x, 0.07) * smoothstep(0.28, 0.42, hsv.y) * smoothstep(0.12, 0.25, hsv.z);
	float ws = hue_near(hsv.x, 0.63, 0.16) * (1.0 - smoothstep(0.26, 0.4, hsv.y));
	float wg = hue_near(hsv.x, SRC_GOLD.x, 0.06) * smoothstep(0.3, 0.45, hsv.y) * smoothstep(0.3, 0.45, hsv.z);
	vec3 col = px.rgb;
	col = mix(col, clamp(skin.rgb * (hsv.z / SRC_SKIN_V), 0.0, 1.0), ws);
	col = mix(col, shift(hsv, SRC_CLOTH, cloth.rgb), wc);
	col = mix(col, shift(hsv, SRC_GOLD, trim.rgb), wg);
	COLOR = vec4(col, px.a);
}
