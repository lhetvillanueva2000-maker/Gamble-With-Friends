class_name Player
extends CharacterBody3D
## First-person player controller — the viewpoint into the 3D world and the
## driver of the Phase 1-6 systems (InputSetup movement, MouseLook, the
## Interactor/PlayerHand pipeline, BodyState debuffs).
##
## Structure (see player.tscn):
##   Player (CharacterBody3D, group "players")
##   ├── Collision (CapsuleShape3D)
##   ├── Head (Node3D, eye height)  <- MouseLook pitches this
##   │   ├── Camera3D               <- the missing camera; renders the world
##   │   ├── Interactor (RayCast3D)
##   │   └── Hand (PlayerHand)
##   ├── MouseLook (yaw = Player, pitch = Head)
##   └── BodyState
##
## Movement is yaw-relative and scaled by BodyState.speed_multiplier, so a
## legless avatar (Meat Grinder) actually walks slower.

@export var walk_speed := 5.0
@export var jump_velocity := 4.6
@export var accel := 14.0
@export var air_accel := 3.0

@onready var _head: Node3D = $Head
@onready var _body_state: BodyState = $BodyState

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _menu_open := false


func _ready() -> void:
	add_to_group(&"players")
	# Grab the mouse for look control. On web this completes on the first
	# click (browser pointer-lock rule, handled by InputSetup).
	InputSetup.request_mouse_capture()
	InputSetup.mouse_capture_lost.connect(_on_capture_lost)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"menu_pause"):
		_toggle_menu()


func _physics_process(delta: float) -> void:
	# Gravity.
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed(&"jump") and not _menu_open:
		velocity.y = jump_velocity

	# Yaw-relative WASD, zeroed while a menu holds the cursor.
	var input := Vector2.ZERO if _menu_open else InputSetup.get_move_vector()
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y))
	wish.y = 0.0
	wish = wish.normalized() * walk_speed * _body_state.speed_multiplier

	var rate := accel if is_on_floor() else air_accel
	velocity.x = move_toward(velocity.x, wish.x, rate * delta * walk_speed)
	velocity.z = move_toward(velocity.z, wish.z, rate * delta * walk_speed)

	move_and_slide()


func _toggle_menu() -> void:
	_menu_open = not _menu_open
	if _menu_open:
		InputSetup.release_mouse()
	else:
		InputSetup.request_mouse_capture()


## The platform yanked the pointer (browser Escape, alt-tab). Treat it as
## opening the menu so movement stops and the cursor is free.
func _on_capture_lost() -> void:
	_menu_open = true
