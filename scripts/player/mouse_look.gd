class_name MouseLook
extends Node
## Pointer-lock-compliant first/third-person look controller.
##
## Attach anywhere on the player rig and assign:
##   yaw_node   — rotates around Y (usually the CharacterBody3D itself)
##   pitch_node — rotates around X (usually the camera arm / Camera3D)
##
## Works identically on desktop, HTML5 pointer lock, and Android physical
## mice because it only consumes InputEventMouseMotion.relative while the
## mouse is captured. Sensitivity is normalized against a 1080p-high window
## so a half-screen swipe turns the player the same amount on a 5.5" phone,
## a 1440p monitor, or a resized browser canvas.

@export var yaw_node: Node3D
@export var pitch_node: Node3D
@export_range(0.02, 1.0, 0.01) var sensitivity_deg_per_px := 0.14
@export_range(1.0, 89.9, 0.1) var pitch_limit_deg := 89.0

## Browsers can emit one enormous relative delta the frame pointer lock is
## re-acquired (the OS cursor "teleports" back into the canvas). Any single
## event beyond this many reference pixels is clamped, killing the camera
## snap without affecting fast-but-legitimate flicks.
const MAX_EVENT_TRAVEL_PX := 120.0

const REFERENCE_HEIGHT_PX := 1080.0


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventMouseMotion:
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if yaw_node == null or pitch_node == null:
		return

	# Normalize to the reference resolution, then clamp re-lock spikes.
	var window_height := float(DisplayServer.window_get_size().y)
	if window_height <= 0.0:
		return
	var motion: Vector2 = event.relative * (REFERENCE_HEIGHT_PX / window_height)
	motion = motion.limit_length(MAX_EVENT_TRAVEL_PX)

	yaw_node.rotate_y(deg_to_rad(-motion.x * sensitivity_deg_per_px))

	var pitch_limit := deg_to_rad(pitch_limit_deg)
	pitch_node.rotation.x = clampf(
		pitch_node.rotation.x - deg_to_rad(motion.y * sensitivity_deg_per_px),
		-pitch_limit,
		pitch_limit
	)
