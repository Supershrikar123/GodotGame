shader_type canvas_item;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 line_color : source_color = vec4(0.0, 1.0, 0.4, 1.0); // Phosphor Green
uniform float line_thickness = 1.5;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 pixel_size = line_thickness / vec2(textureSize(depth_texture, 0));

    float d_center = texture(depth_texture, uv).x;
    float d_left = texture(depth_texture, uv - vec2(pixel_size.x, 0.0)).x;
    float d_right = texture(depth_texture, uv + vec2(pixel_size.x, 0.0)).x;
    float d_up = texture(depth_texture, uv - vec2(0.0, pixel_size.y)).x;
    float d_down = texture(depth_texture, uv + vec2(0.0, pixel_size.y)).x;

    // Calculate difference in depth to find the edges
    float edge = abs(d_center - d_left) + abs(d_center - d_right) + abs(d_center - d_up) + abs(d_center - d_down);

    if (edge > 0.00005) {
        COLOR = line_color; // Draw the green outline
    } else {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0); // Fill everything else pitch black
    }
}