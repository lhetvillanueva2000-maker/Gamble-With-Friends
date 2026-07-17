class_name SectionActivator
extends Area3D
## Per-section activity gate: when no player is inside this volume, the
## section's COSMETIC subtree stops processing and its loose physics
## bodies are put to sleep. Size the CollisionShape3D to cover the whole
## section plus one doorway of margin so things wake before they're seen.
##
## HARD GUARDRAILS (this component is deliberately incapable of breaking
## the deterministic sim):
##  - Only `cosmetics_root` is ever disabled. Gameplay Area3D triggers
##    (bins, hoppers, exit elevators, table interactables) and table-game
##    logic nodes must NOT live under it — they stay hot at all times.
##  - Bet RESOLUTION is host-authoritative and event-driven (TableGame),
##    never physics-driven, so sleeping decorative bodies cannot change
##    an outcome or consume a TableRng draw.
##  - Nothing is freed or reparented; node paths stay stable for RPCs.

## The decorative subtree this gate may switch off: chip piles, bottles,
## animated signage, ambient particles. NEVER triggers or table logic.
@export var cosmetics_root: Node3D

var _players_inside := 0


func _ready() -> void:
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Sections start cold; the arrival section wakes on first overlap.
	_set_active.call_deferred(false)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"players"):
		return
	_players_inside += 1
	if _players_inside == 1:
		_set_active(true)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group(&"players"):
		return
	_players_inside = maxi(_players_inside - 1, 0)
	if _players_inside == 0:
		_set_active(false)


func _set_active(active: bool) -> void:
	if cosmetics_root == null:
		return
	cosmetics_root.process_mode = (
		Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	)
	for node: Node in cosmetics_root.find_children("*", "RigidBody3D", true, false):
		var rigid_body := node as RigidBody3D
		if active:
			rigid_body.sleeping = false
		else:
			rigid_body.sleeping = true
