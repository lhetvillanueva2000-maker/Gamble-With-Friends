class_name PlayerHand
extends Node3D
## Single-slot carry point. Mount in front of the player camera; picked-up
## Carryables are parented here and move with the view until dropped or
## thrown. One item at a time — juggling loot is a design constraint, not
## a missing feature.

signal held_changed(item: Carryable)

## Launch speed (m/s) given to thrown items, along the hand's -Z.
@export_range(1.0, 20.0, 0.5) var throw_speed := 7.0

var held: Carryable = null


func is_holding() -> bool:
	if held != null and not is_instance_valid(held):
		held = null
	return held != null


func pick_up(item: Carryable) -> bool:
	if is_holding() or item == null or item.held_by != null:
		return false
	item.attach_to(self)
	held = item
	held_changed.emit(held)
	return true


## Gentle release at the hand's position (E while holding).
func drop() -> void:
	_release(Vector3.ZERO)


## Launch along the camera aim (LMB while holding) — this is how items get
## into the shop bin and the grinder hopper.
func throw() -> void:
	if not is_holding():
		return
	_release(-global_transform.basis.z * throw_speed * held.mass)


func _release(impulse: Vector3) -> void:
	if not is_holding():
		return
	var item := held
	held = null
	item.detach(impulse)
	held_changed.emit(null)
