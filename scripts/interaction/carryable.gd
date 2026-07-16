class_name Carryable
extends RigidBody3D
## Physical prop that can be carried in a PlayerHand and thrown. Expects
## one Interactable child (the pickup zone); on ready it claims that zone
## as an E-action grab and wires it to the requesting player's hand.
##
## While held: physics frozen, collision muted (no shoving teammates with
## a crate), pickup zone disabled, node reparented under the hand. On
## release everything is restored and the body is handed back to the
## current level.

signal picked_up(hand: PlayerHand)
signal released(hand: PlayerHand)

@export var display_name := "ITEM"

var held_by: PlayerHand = null

var _pickup_zone: Interactable = null
var _saved_layer := 0
var _saved_mask := 0


func _ready() -> void:
	for child: Node in get_children():
		if child is Interactable:
			_pickup_zone = child
			break
	if _pickup_zone == null:
		push_warning("Carryable '%s' has no Interactable pickup zone." % name)
		return
	_pickup_zone.action = &"action_pickup"
	_pickup_zone.prompt_text = "PICK UP %s" % display_name
	_pickup_zone.interacted.connect(_on_pickup_requested)


func _on_pickup_requested(interactor: Interactor) -> void:
	if interactor.hand != null:
		interactor.hand.pick_up(self)


## Called by PlayerHand.pick_up() — don't call directly.
func attach_to(hand: PlayerHand) -> void:
	if held_by != null:
		return
	held_by = hand
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	freeze = true
	if _pickup_zone != null:
		_pickup_zone.enabled = false
	reparent(hand)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	picked_up.emit(hand)


## Called by PlayerHand._release() — don't call directly.
func detach(impulse: Vector3 = Vector3.ZERO) -> void:
	if held_by == null:
		return
	var hand := held_by
	held_by = null
	var world: Node = FloorStreamer.current_level
	if world == null:
		world = get_tree().current_scene
	reparent(world)
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if _pickup_zone != null:
		_pickup_zone.enabled = true
	if impulse != Vector3.ZERO:
		apply_central_impulse(impulse)
	released.emit(hand)
