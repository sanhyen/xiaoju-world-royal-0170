shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled;

void fragment() {
    // Soft overlapping cloud curls between the tangible jade rails.
    float x = mod(UV.x, 3.8) - 1.9;
    float y = UV.y;
    float drift = sin(TIME * 0.32 + UV.x * 0.37) * 0.025;
    vec2 p = vec2(x, (y - 0.47 - drift) * 1.5);
    float curl = abs(length(p - vec2(-0.45, -0.12)) - 0.48);
    curl = min(curl, abs(length(p - vec2(0.26, -0.09)) - 0.34));
    curl = min(curl, abs(length(p - vec2(0.78, -0.18)) - 0.24));
    float line = 1.0 - smoothstep(0.018, 0.085, curl);
    float veil = smoothstep(0.0, 0.12, y) * (1.0 - smoothstep(0.87, 1.0, y));
    float wisps = pow(0.5 + 0.5 * sin(y * 21.0 + sin(UV.x * 1.1 - TIME * 0.16) * 2.4), 7.0);
    ALBEDO = mix(vec3(0.62, 0.82, 0.78), vec3(0.91, 0.94, 0.80), line);
    EMISSION = vec3(0.22, 0.42, 0.35) * (line * 0.28 + wisps * 0.08);
    ROUGHNESS = 0.76;
    ALPHA = veil * (0.075 + line * 0.46 + wisps * 0.10);
}
