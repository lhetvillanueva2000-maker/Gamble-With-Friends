extends Node
## InputSetup (autoload singleton).
##
## Builds the entire KBM InputMap programmatically at boot so every peer in a
## WebRTC session — desktop browser, Android + physical mouse, or native
## desktop — runs from an identical, deterministic action set. Also owns the
## cross-platform mouse-capture state machine:
##
##  - HTML5: browsers only grant pointer lock inside a user-gesture callback,
##    and reserve Escape to force-release it (Godot never sees that keypress).
##    We therefore complete deferred capture requests on the next click and
##    watch for capture loss every frame, surfacing it as a signal the game
##    treats exactly like a pause request.
##  - Android: a physical mouse delivers InputEventMouseMotion.relative while
##    MOUSE_MODE_CAPTURED, same as desktop. Touch is translated to mouse
##    events by `input_devices/pointing/emulate_mouse_from_touch`, so the
##    "interact" (left click) action fires from taps with zero extra code.

## Mouse capture was acquired (pointer lock granted on web).
signal mouse_captured
## Mouse capture was lost while gameplay still wanted it (browser Escape,
## Android system gesture, alt-tab). Open the pause menu when this fires.
signal mouse_capture_lost

## Movement uses physical keycodes: on AZERTY/QWERTZ layouts the keys under
## the player's fingers stay WASD-positioned. Arrow keys are duplicated in.
const KEY_ACTIONS: Dictionary = {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"action_pickup": [KEY_E],
	&"menu_pause": [KEY_ESCAPE],
	&"menu_scoreboard": [KEY_TAB],
}

const MOUSE_ACTIONS: Dictionary = {
	&"interact": MOUSE_BUTTON_LEFT,
}

var _is_web: bool = OS.has_feature("web")
var _want_capture := false
var _was_captured := false


func _ready() -> void:
	# Keep watching capture state even while the SceneTree is paused
	# (the pause menu is exactly when we need to re-capture on resume).
	process_mode = Node.PROCESS_MODE_ALWAYS
	register_default_actions()


## Registers (or deterministically rebuilds) every default KBM action.
## Safe to call again later, e.g. "Reset to defaults" in a settings menu.
func register_default_actions() -> void:
	for action: StringName in KEY_ACTIONS:
		_ensure_action(action)
		for keycode: Key in KEY_ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)

	for action: StringName in MOUSE_ACTIONS:
		_ensure_action(action)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_ACTIONS[action]
		InputMap.action_add_event(action, ev)


func _ensure_action(action: StringName) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		# 0.2 deadzone: keys are digital anyway, but the virtual joystick
		# feeds these actions with analog strength (Phase 2).
		InputMap.add_action(action, 0.2)


## WASD/arrow movement as a normalized 2D vector (x = strafe, y = forward).
func get_move_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


## Ask for relative-mouse (pointer lock) mode. On desktop and Android this is
## immediate. On the web it succeeds immediately only when called from inside
## an input callback (e.g. a "Play" button press); otherwise it stays pending
## and completes on the player's next click — see _unhandled_input().
func request_mouse_capture() -> void:
	_want_capture = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Release the pointer for menus / betting UI. Also clears any pending
## capture so a stray click doesn't re-lock while a menu is open.
func release_mouse() -> void:
	_want_capture = false
	Input.set_mouse_mode(_free_mouse_mode())


## Which mode a *free* cursor uses. CONFINED keeps the visible cursor inside
## the window (a fast drag toward a bet button can't slide onto a second
## monitor); the browser owns the cursor outside pointer lock, so web always
## gets plain VISIBLE.
func _free_mouse_mode() -> Input.MouseMode:
	if _is_web:
		return Input.MOUSE_MODE_VISIBLE
	var settings: Node = get_node_or_null(^"/root/SettingsManager")
	if settings != null and settings.mouse_confine_to_window:
		return Input.MOUSE_MODE_CONFINED
	return Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Web: finish a pending pointer-lock request on the next user gesture.
	if _want_capture and not is_mouse_captured():
		if event is InputEventMouseButton and event.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(_delta: float) -> void:
	var captured := is_mouse_captured()
	if captured == _was_captured:
		return
	_was_captured = captured
	if captured:
		mouse_captured.emit()
	elif _want_capture:
		# The platform yanked the pointer (browser Escape, Android home
		# gesture, focus loss). Treat it as an implicit pause request —
		# this is the ONLY reliable Escape signal on HTML5.
		mouse_capture_lost.emit()
