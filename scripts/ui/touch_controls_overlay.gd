class_name TouchControlsOverlay
extends Control
## Fallback on-screen controls for touch devices: a floating virtual
## joystick (bottom-left) plus MENU / PICK UP / INTERACT buttons
## (bottom-right). Built entirely in code so no scene edits are needed to
## restyle or extend it.
##
## Visibility policy comes from SettingsManager.touch_controls_mode:
##  - ALWAYS_ON / OFF are absolute.
##  - AUTO swaps live with the last-used device: the overlay appears on the
##    first touch and vanishes the moment a physical key or real mouse is
##    used — which is exactly what happens when a Bluetooth keyboard/mouse
##    disconnects from an Android tablet mid-session.

const FED_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_back",
	&"interact", &"action_pickup", &"menu_pause",
]

var _joystick: VirtualJoystick


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_joystick()
	_build_buttons()
	SettingsManager.touch_settings_changed.connect(_refresh_visibility)
	_refresh_visibility()


func _input(event: InputEvent) -> void:
	if SettingsManager.touch_controls_mode != SettingsManager.TouchControlsMode.AUTO:
		return
	if event is InputEventScreenTouch:
		_set_overlay_visible(true)
	elif event is InputEventKey or _is_physical_mouse(event):
		_set_overlay_visible(false)


func _refresh_visibility() -> void:
	_set_overlay_visible(SettingsManager.touch_controls_wanted())


func _set_overlay_visible(value: bool) -> void:
	if visible == value:
		return
	visible = value
	if not value:
		# Never let a half-held stick or button keep an action pressed.
		_joystick.reset()
		for action: StringName in FED_ACTIONS:
			Input.action_release(action)


## Touch-synthesized mouse events (emulate_mouse_from_touch) carry
## DEVICE_ID_EMULATION — only genuine hardware mice may hide the overlay.
static func _is_physical_mouse(event: InputEvent) -> bool:
	if event is not InputEventMouseButton and event is not InputEventMouseMotion:
		return false
	return event.device != InputEvent.DEVICE_ID_EMULATION


func _build_joystick() -> void:
	_joystick = VirtualJoystick.new()
	_joystick.name = "VirtualJoystick"
	_joystick.anchor_top = 1.0
	_joystick.anchor_bottom = 1.0
	_joystick.offset_left = 48.0
	_joystick.offset_top = -400.0
	_joystick.offset_right = 400.0
	_joystick.offset_bottom = -48.0
	add_child(_joystick)


func _build_buttons() -> void:
	var column := VBoxContainer.new()
	column.name = "ActionButtons"
	column.anchor_left = 1.0
	column.anchor_right = 1.0
	column.anchor_top = 1.0
	column.anchor_bottom = 1.0
	column.offset_left = -336.0
	column.offset_top = -424.0
	column.offset_right = -48.0
	column.offset_bottom = -48.0
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override(&"separation", 24)
	add_child(column)

	column.add_child(_make_action_button("MENU", &"menu_pause"))
	column.add_child(_make_action_button("PICK UP", &"action_pickup"))
	column.add_child(_make_action_button("INTERACT", &"interact"))


## Buttons press/release the real InputMap action, so gameplay code cannot
## tell a screen tap from the E key or a mouse click.
static func _make_action_button(label: String, action: StringName) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(288.0, 96.0)
	button.modulate = Color(1.0, 1.0, 1.0, 0.85)
	button.add_theme_font_size_override(&"font_size", 30)
	button.button_down.connect(func() -> void: Input.action_press(action))
	button.button_up.connect(func() -> void: Input.action_release(action))
	return button
