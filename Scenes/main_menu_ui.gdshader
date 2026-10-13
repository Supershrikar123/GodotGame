shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float curvature : hint_range(0.0, 10.0) = 4.0;
uniform float scanline_opacity : hint_range(0.0, 1.0) = 0.25;

vec2 curve(vec2 uv) {
	uv = (uv - 0.5) * 2.0;
	uv.x *= 1.0 + pow((abs(uv.y) / curvature), 2.0);
	uv.y *= 1.0 + pow((abs(uv.x) / curvature), 2.0);
	uv = (uv / 2.0) + 0.5;
	return uv;
}

void fragment() {
	vec2 curved_uv = curve(SCREEN_UV);
	
	// Black out outside the curved screen boundaries
	if (curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec4 text = texture(SCREEN_TEXTURE, curved_uv);
		
		// Add subtle CRT scanlines
		float scanline = sin(curved_uv.y * 600.0) * 0.5 + 0.5;
		text.rgb -= scanline * scanline_opacity * text.rgb;
		
		COLOR = text;
	}
}