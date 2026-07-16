shader_type spatial;
// Lightweight hover outline for interactables. Applied as a
// material_overlay: front faces are culled and vertices pushed out along
// their normals, leaving a thin unshaded shell around the mesh. One pass,
// no post-processing, no extra viewport — safe for the Compatibility
// renderer on low-end Android and WebGL2.
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float outline_width : hint_range(0.005, 0.1) = 0.025;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
