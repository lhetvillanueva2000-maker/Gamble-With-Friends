class_name MeatGrinder
extends Node3D
## The Lobby Body Shredder. Step (or get thrown) into the hopper and the
## machine converts the physical avatar into cash for the crew bank —
## the last-resort quota filler. Carryable props tossed in are destroyed
## for nothing: the machine only pays for meat.
##
## Respawn/spectator policy is deliberately NOT decided here — later
## phases (host logic) connect to victim_destroyed and choose.

signal grind_started(victim: Node3D)
signal cash_extracted(amount: int, victim: Node3D)
signal victim_destroyed(victim: Node3D)

## Cash paid into the shared bank per player body.
@export var cash_per_body := 500
## How long the machine chews before paying out.
@export_range(0.2, 5.0, 0.1) var grind_duration := 1.2

@onready var _entry_trigger: Area3D = $EntryTrigger
@onready var _hopper: Marker3D = $Hopper

var _victims: Array[Node3D] = []


func _ready() -> void:
	_entry_trigger.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body in _victims:
		return
	if body.is_in_group(&"players"):
		_victims.append(body)
		_grind_player(body)
	elif body is Carryable and (body as Carryable).held_by == null:
		_victims.append(body)
		_grind_item(body as Carryable)


func _grind_player(victim: Node3D) -> void:
	grind_started.emit(victim)
	# The avatar is inside the machine: pin it in the hopper and cut all
	# of its input/physics processing so it can't wiggle back out.
	victim.global_position = _hopper.global_position
	victim.process_mode = Node.PROCESS_MODE_DISABLED

	await get_tree().create_timer(grind_duration).timeout
	if not is_instance_valid(victim):
		return

	# Phase 6: avatars carrying a BodyState are shredded one part at a
	# time (legs first, head last) and ejected still alive — debuffed but
	# grindable again. Only the final part costs them the whole avatar.
	var body := _body_state_of(victim)
	if body != null:
		var part_value := body.shred_next_part()
		if part_value > 0:
			Economy.deposit_cash(part_value)
			cash_extracted.emit(part_value, victim)
			if not body.is_fully_shredded():
				_eject(victim)
				return
		victim_destroyed.emit(victim)
		victim.queue_free()
		return

	# No BodyState component: Phase 4 whole-body payout.
	Economy.deposit_cash(cash_per_body)
	cash_extracted.emit(cash_per_body, victim)
	victim_destroyed.emit(victim)
	victim.queue_free()


func _eject(victim: Node3D) -> void:
	victim.global_position = global_position + Vector3(2.0, 0.5, 2.0)
	victim.process_mode = Node.PROCESS_MODE_INHERIT
	_victims.erase(victim)


func _body_state_of(victim: Node3D) -> BodyState:
	for child: Node in victim.get_children():
		if child is BodyState:
			return child as BodyState
	return null


func _grind_item(item: Carryable) -> void:
	grind_started.emit(item)
	await get_tree().create_timer(grind_duration * 0.5).timeout
	if is_instance_valid(item):
		victim_destroyed.emit(item)
		item.queue_free()
