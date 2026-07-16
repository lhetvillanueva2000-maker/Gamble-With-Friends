shader_type spatial;
// Fake bloom halo: an additive camera-facing quad with a procedural radial
// gradient. This replaces WorldEnvironment glow entirely — screen-space
// bloom needs downsample/upsample chains that kill mobile WebGL2, while
// this is one flat quad, no texture fetch, a few ALU ops.
//
// Usage: QuadMesh (sized ~1.3x the sign) placed just in front of the neon
// tube. The shader billboards it toward the camera, preserving node scale.
// depth_draw_never keeps it out of the depth buffer (halos never occlude);
// the depth TEST stays on, so walls still hide it.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 halo_color : source_color = vec4(1.0, 0.2, 0.3, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.8;
// Higher = tighter hotspot, softer skirt.
uniform float falloff : hint_range(1.0, 6.0) = 2.6;
// Match these to the paired neon_tube so tube and spill flicker together.
uniform float pulse_speed = 0.0;
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.25;

void vertex() {
	// Camera-facing billboard, node scale preserved.
	mat4 mv = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	mv[0] *= length(MODEL_MATRIX[0].xyz);
	mv[1] *= length(MODEL_MATRIX[1].xyz);
	mv[2] *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = mv;
}

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;
	float glow = pow(clamp(1.0 - d, 0.0, 1.0), falloff);

	float pulse = 1.0 - pulse_depth * (0.5 + 0.5 * sin(TIME * pulse_speed))
			* step(0.001, pulse_speed);
	ALBEDO = halo_color.rgb * glow * intensity * pulse;
	ALPHA = glow;
}
