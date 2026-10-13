shader_type canvas_item;

// overlay = false: uses the node's own UV for warping.
// overlay = true: uses SCREEN_UV, for a full-screen overlay over everything beneath it.
uniform bool overlay = false;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float scanlines_opacity : hint_range(0.0, 1.0) = 0.4;
uniform float scanlines_width : hint_range(0.0, 0.5) = 0.25;
uniform float grille_opacity : hint_range(0.0, 1.0) = 0.3;

// Your game's resolution
uniform vec2 screen_size = vec2(1920.0, 1080.0);
uniform float pixel_size : hint_range(1.0, 8.0) = 2.0;

uniform bool pixelate = true;

uniform float static_noise_intensity : hint_range(0.0, 1.0) = 0.06;

uniform float aberration : hint_range(-1.0, 1.0) = 0.03;
uniform float brightness = 1.4;
uniform bool discolor = true;

uniform float warp_amount : hint_range(0.0, 5.0) = 1.0;
uniform bool clip_warp = false;

uniform float vignette_intensity = 0.4;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.5;

// CRT Curvature & Bezel Line Controls
uniform float bezel_line_opacity : hint_range(0.0, 1.0) = 0.7;
uniform float glass_highlight_opacity : hint_range(0.0, 1.0) = 0.4;

vec2 random(vec2 uv) {
uv = vec2(dot(uv, vec2(127.1, 311.7)),
         dot(uv, vec2(269.5, 183.3)));
return -1.0 + 2.0 * fract(sin(uv) * 43758.5453123);
}

vec2 warp(vec2 uv) {
vec2 delta = uv - 0.5;
float delta2 = dot(delta.xy, delta.xy);
float delta4 = delta2 * delta2;
float delta_offset = delta4 * warp_amount;

return uv + delta * delta_offset;
}

// Calculates the smooth rounded screen bounds
float border(vec2 uv) {
float radius = min(warp_amount, 0.08);
radius = max(min(min(abs(radius * 2.0), 1.0), 1.0), 1e-5);
vec2 abs_uv = abs(uv * 2.0 - 1.0) - vec2(1.0, 1.0) + radius;
float dist = length(max(vec2(0.0), abs_uv)) / radius;
float square = smoothstep(0.96, 1.0, dist);
return clamp(1.0 - square, 0.0, 1.0);
}

// Creates the dark inner shadow line (bezel casing edge)
float bezel_shadow_line(vec2 uv) {
float radius = min(warp_amount, 0.08);
radius = max(min(min(abs(radius * 2.0), 1.0), 1.0), 1e-5);
vec2 abs_uv = abs(uv * 2.0 - 1.0) - vec2(1.0, 1.0) + radius;
float dist = length(max(vec2(0.0), abs_uv)) / radius;
// Creates a thin ring line right near the corner edge
return smoothstep(0.85, 0.97, dist) * (1.0 - smoothstep(0.97, 1.0, dist));
}

// Creates the bright glass refraction/highlight line on the curve
float glass_highlight_line(vec2 uv) {
float radius = min(warp_amount, 0.08);
radius = max(min(min(abs(radius * 2.0), 1.0), 1.0), 1e-5);
vec2 abs_uv = abs(uv * 2.0 - 1.0) - vec2(1.0, 1.0) + radius;
float dist = length(max(vec2(0.0), abs_uv)) / radius;
// Inner glowing edge line simulating curved glass glare
return smoothstep(0.75, 0.90, dist) * (1.0 - smoothstep(0.90, 0.96, dist));
}

float vignette(vec2 uv) {
uv *= 1.0 - uv.xy;
float vig = uv.x * uv.y * 15.0;
return pow(vig, vignette_intensity * vignette_opacity);
}

void fragment() {
vec2 resolution = screen_size / max(pixel_size, 1.0);

vec2 uv = overlay ? warp(SCREEN_UV) : warp(UV);
vec2 text_uv = uv;

if (pixelate) {
text_uv = ceil(uv * resolution) / resolution;
}

vec4 text;
text.r = texture(screen_texture, text_uv + vec2(aberration, 0.0) * 0.1).r;
text.g = texture(screen_texture, text_uv - vec2(aberration, 0.0) * 0.1).g;
text.b = texture(screen_texture, text_uv).b;
text.a = 1.0;

float r = text.r;
float g = text.g;
float b = text.b;

uv = warp(UV);

if (grille_opacity > 0.0) {
float g_r = smoothstep(0.85, 0.95, abs(sin(uv.x * (resolution.x * 3.14159265))));
r = mix(r, r * g_r, grille_opacity);

float g_g = smoothstep(0.85, 0.95, abs(sin(1.05 + uv.x * (resolution.x * 3.14159265))));
g = mix(g, g * g_g, grille_opacity);

float b_b = smoothstep(0.85, 0.95, abs(sin(2.1 + uv.x * (resolution.x * 3.14159265))));
b = mix(b, b * b_b, grille_opacity);
}

text.r = clamp(r * brightness, 0.0, 1.0);
text.g = clamp(g * brightness, 0.0, 1.0);
text.b = clamp(b * brightness, 0.0, 1.0);

if (scanlines_opacity > 0.0) {
float scanlines = smoothstep(scanlines_width, scanlines_width + 0.5, abs(sin(uv.y * (resolution.y * 3.14159265))));
text.rgb = mix(text.rgb, text.rgb * vec3(scanlines), scanlines_opacity);
}

if (static_noise_intensity > 0.0) {
text.rgb += clamp(random((ceil(uv * resolution) / resolution) + fract(TIME)).x, 0.0, 1.0) * static_noise_intensity;
}

// Apply physical CRT bezel shadow line
if (bezel_line_opacity > 0.0) {
float shadow = bezel_shadow_line(uv);
text.rgb = mix(text.rgb, vec3(0.0), shadow * bezel_line_opacity);
}

// Apply curved glass reflection highlight line
if (glass_highlight_opacity > 0.0) {
float highlight = glass_highlight_line(uv);
text.rgb = mix(text.rgb, vec3(1.0), highlight * glass_highlight_opacity);
}

text.rgb *= border(uv);
text.rgb *= vignette(uv);

if (clip_warp) {
text.a = border(uv);
}

if (discolor) {
vec3 greyscale = vec3(text.r + text.g + text.b) / 3.0;
text.rgb = mix(text.rgb, greyscale, 0.5);

float midpoint = pow(0.5, 2.2);
text.rgb = (text.rgb - vec3(midpoint)) * 1.2 + midpoint;
}

COLOR = text;
}