class_name Interactor
extends RayCast3D
## Camera-mounted interaction probe. Mount as a child of the player's
## Camera3D pointing forward; it focuses whatever Interactable the
## crosshair rests on, drives the shared outline + HUD prompt, and routes
## input to the focused target — passing itself as context so targets can
## reach the player and their hand.
##
## Held-item input (when nothing is focused):
##   E   -> gentle drop      LMB -> throw along the camera aim

signal focus_changed(interactable: Interactable)

## The player body this probe belongs to (context for interactables).
@export var player: Node3D
## The hand items are carried in (context for pickups).
@export var hand: PlayerHand
@export_range(0.5, 6.0, 0.1) var reach := 2.6

var _focused: Interactable = null


func _ready() -> void:
	collide_with_areas = true
	collide_with_bodies = false
	target_position = Vector3(0.0, 0.0, -reach)


func _physics_process(_delta: float) -> void:
	if _focused != null and not is_instance_valid(_focused):
		_focused = null
		get_tree().call_group(&"hud", "hide_interact_prompt")

	var hit: Interactable = null
	if is_colliding():
		hit = get_collider() as Interactable
		if hit != null and not hit.enabled:
			hit = null
	if hit != _focused:
		_set_focused(hit)


func _unhandled_input(event: InputEvent) -> void:
	if _focused != null and event.is_action_pressed(_focused.action):
		get_viewport().set_input_as_handled()
		_focused.interact(self)
		return

	if hand != null and hand.is_holding():
		if event.is_action_pressed(&"action_pickup"):
			get_viewport().set_input_as_handled()
			hand.drop()
		elif event.is_action_pressed(&"interact"):
			get_viewport().set_input_as_handled()
			hand.throw()


func _set_focused(next: Interactable) -> void:
	if _focused != null and is_instance_valid(_focused):
		_focused.set_focused(self, false)
	_focused = next
	if _focused != null:
		_focused.set_focused(self, true)
		get_tree().call_group(
			&"hud", "show_interact_prompt",
			_focused.prompt_text, _focused.action_key_label()
		)
	else:
		get_tree().call_group(&"hud", "hide_interact_prompt")
	focus_changed.emit(_focused)
