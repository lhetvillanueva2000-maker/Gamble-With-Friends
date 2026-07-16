shader_type spatial;
// Ultra-cheap stylized environment surface. Unshaded: no light loops, no
// shadow atlas, no depth prepass work — depth comes from three fakes that
// cost a handful of ALU ops per fragment:
//   1. vertex colors (bake zone/AO tints on the mesh in Blender),
//   2. half-lambert against a constant "light" direction (no Light3D),
//   3. a vertical gradient that grounds geometry near the floor.
// Share ONE ShaderMaterial per floor across every architectural mesh —
// CasinoFloor does this automatically from the floor palette.
render_mode unshaded, cull_back;

uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
// 1.0 = multiply in mesh vertex colors, 0.0 = ignore them.
uniform float use_vertex_color : hint_range(0.0, 1.0) = 1.0;
// Fake directional shading (world space); tweak per scene, never per mesh.
uniform vec3 fake_light_dir = vec3(0.35, 0.8, 0.45);
uniform float shade_strength : hint_range(0.0, 1.0) = 0.35;
// Darkening near y=0, gone by y=grounding_height. Cheap contact shadow.
uniform float ground_darken : hint_range(0.0, 1.0) = 0.25;
uniform float grounding_height = 2.0;

varying vec3 v_normal_ws;
varying float v_height_ws;

void vertex() {
	v_normal_ws = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_height_ws = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 col = base_color.rgb * mix(vec3(1.0), COLOR.rgb, use_vertex_color);

	// Half-lambert: wraps light around, so nothing goes pitch black.
	float ndl = dot(v_normal_ws, normalize(fake_light_dir)) * 0.5 + 0.5;
	col *= mix(1.0 - shade_strength, 1.0, ndl);

	float grounded = clamp(v_height_ws / max(grounding_height, 0.001), 0.0, 1.0);
	col *= mix(1.0 - ground_darken, 1.0, grounded);

	ALBEDO = col;
}
