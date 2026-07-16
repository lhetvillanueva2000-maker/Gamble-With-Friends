class_name VirtualJoystick
extends Control
## Floating-origin virtual thumbstick. Instead of drawing its own movement
## pipeline, it feeds the exact same move_* actions WASD is bound to via
## Input.action_press(action, strength) — so player code written against
## InputSetup.get_move_vector() / Input.get_vector() needs zero changes and
## analog strength (walk vs run) comes through the action deadzone system.
##
## Floating origin: the ring re-centers wherever the thumb first lands
## inside this control's rect, which plays far better than a fixed stick on
## large phone screens.

@export_range(40.0, 300.0, 1.0) var knob_travel_px := 120.0

const RING_FILL_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const RING_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const KNOB_COLOR := Color(0.85, 0.68, 0.21, 0.4)

const MOVE_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_back",
]

var _touch_index := -1
var _origin := Vector2.ZERO
var _vector := Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and _touch_index == -1:
			_touch_index = touch.index
			_origin = touch.position
			_update_vector(Vector2.ZERO)
			accept_event()
		elif not touch.pressed and touch.index == _touch_index:
			reset()
			accept_event()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _touch_index:
			_update_vector((drag.position - _origin) / knob_travel_px)
			accept_event()


## Releases the stick and zeroes all fed actions (also called by the overlay
## when it hides, so movement can never stick "on").
func reset() -> void:
	_touch_index = -1
	_update_vector(Vector2.ZERO)


func _update_vector(raw: Vector2) -> void:
	_vector = raw.limit_length(1.0)
	_feed(&"move_left", maxf(-_vector.x, 0.0))
	_feed(&"move_right", maxf(_vector.x, 0.0))
	_feed(&"move_forward", maxf(-_vector.y, 0.0))
	_feed(&"move_back", maxf(_vector.y, 0.0))
	queue_redraw()


static func _feed(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _draw() -> void:
	var center := _origin if _touch_index != -1 else size * 0.5
	draw_circle(center, knob_travel_px, RING_FILL_COLOR)
	draw_arc(center, knob_travel_px, 0.0, TAU, 48, RING_BORDER_COLOR, 3.0, true)
	draw_circle(center + _vector * knob_travel_px, knob_travel_px * 0.42, KNOB_COLOR)
