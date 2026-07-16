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

	Economy.deposit_cash(cash_per_body)
	cash_extracted.emit(cash_per_body, victim)
	victim_destroyed.emit(victim)
	# The physical avatar is gone for the rest of the run.
	victim.queue_free()


func _grind_item(item: Carryable) -> void:
	grind_started.emit(item)
	await get_tree().create_timer(grind_duration * 0.5).timeout
	if is_instance_valid(item):
		victim_destroyed.emit(item)
		item.queue_free()
