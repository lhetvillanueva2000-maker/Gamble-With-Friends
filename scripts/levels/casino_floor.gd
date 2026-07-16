class_name CasinoFloor
extends GameLevel
## Base script shared by all four casino floors. Each floor scene inherits
## casino_floor_base.tscn and overrides the exports below — the geometry
## kit and section layout stay identical, only stakes and dressing change.

## A player reached the exit elevator at the end of the floor.
signal exit_requested

@export_range(1, 4) var floor_number := 1
## Shared-bank target the crew must hit before the timer expires.
@export var quota_target := 5_000
## Cheapest seat at any table on this floor — the stakes ladder.
@export var min_bet := 5

@onready var _exit_trigger: Area3D = $Sections/Section04Exit/ExitTrigger


func _ready() -> void:
	_exit_trigger.body_entered.connect(_on_exit_body_entered)


func _on_exit_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"players"):
		exit_requested.emit()
