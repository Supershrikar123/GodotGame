shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 line_color : source_color = vec4(0.0, 1.0, 0.4, 1.0); // Phosphor Green
uniform vec4 body_color : source_color = vec4(0.0, 0.0, 0.0, 1.0); // Pitch Black

void fragment() {
    vec3 fdx = dFdx(NORMAL);
    vec3 fdy = dFdy(NORMAL);
    float edge = length(fdx) + length(fdy);

    // Lower threshold from 0.4 down to 0.05 or 0.02 to capture subtle bevels
    if (edge > 0.1) {
        ALBEDO = line_color.rgb;
    } else {
        ALBEDO = body_color.rgb;
    }
}