class_name Lobby
extends GameLevel
## Between-runs hub. Players wake up inside cardboard boxes, buy gear at the
## shop truck, feed the quota shortfall to the Meat Grinder, and board the
## limo to start a run. Phase 3 wires the SPATIAL triggers; the shop
## inventory and grinder economy arrive with the gameplay phases.

signal shop_area_entered(body: Node3D)
signal shop_area_exited(body: Node3D)
signal grinder_area_entered(body: Node3D)
signal grinder_area_exited(body: Node3D)

@onready var _shop_trigger: Area3D = $ShopTruck/ShopTrigger
@onready var _grinder_trigger: Area3D = $MeatGrinder/DepositTrigger


func _ready() -> void:
	_shop_trigger.body_entered.connect(_on_shop_entered)
	_shop_trigger.body_exited.connect(_on_shop_exited)
	_grinder_trigger.body_entered.connect(_on_grinder_entered)
	_grinder_trigger.body_exited.connect(_on_grinder_exited)


func _on_shop_entered(body: Node3D) -> void:
	if body.is_in_group(&"players"):
		shop_area_entered.emit(body)


func _on_shop_exited(body: Node3D) -> void:
	if body.is_in_group(&"players"):
		shop_area_exited.emit(body)


func _on_grinder_entered(body: Node3D) -> void:
	if body.is_in_group(&"players"):
		grinder_area_entered.emit(body)


func _on_grinder_exited(body: Node3D) -> void:
	if body.is_in_group(&"players"):
		grinder_area_exited.emit(body)
