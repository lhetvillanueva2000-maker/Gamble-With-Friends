shader_type spatial;
// Fake neon tube surface. Reads as "emissive" with zero glow pipeline:
// fragments facing the camera whiten into a hot core while grazing angles
// keep the saturated hue — exactly how a real tube reads on camera.
// Pair with neon_halo.gdshader on a quad behind it for the light spill.
// Unshaded and opaque: no lights, no transparency sorting, no bloom.
render_mode unshaded, cull_back;

uniform vec4 neon_color : source_color = vec4(1.0, 0.2, 0.3, 1.0);
// How much of the view-facing area whitens into the hot core.
uniform float core_strength : hint_range(0.0, 1.0) = 0.8;
uniform float core_tightness : hint_range(0.5, 4.0) = 2.0;
// 0 = steady sign. ~6.0 with depth 0.4 = faulty, about-to-die flicker.
uniform float pulse_speed = 0.0;
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = pow(facing, core_tightness) * core_strength;
	vec3 col = mix(neon_color.rgb * 0.85, vec3(1.0), core);

	float pulse = 1.0 - pulse_depth * (0.5 + 0.5 * sin(TIME * pulse_speed))
			* step(0.001, pulse_speed);
	ALBEDO = col * pulse;
}
