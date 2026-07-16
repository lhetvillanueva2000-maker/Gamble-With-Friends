class_name ShopTruck
extends Node3D
## The lobby shop truck. Entirely physical, no menus:
##
##  1. Grab stock off the shelf (Carryable pickup) and throw it in the Bin.
##  2. Press the Buy button: the bin is priced, tickets are deducted
##     atomically, and the purchases respawn in the Retrieval Drawer.
##  3. Carry your goods out yourself — the truck doesn't deliver.
##
## Penalty rule: when the limo departs, anything still in the truck's
## custody is lost. Unpurchased stock was never charged, so it just
## despawns; PURCHASED items left behind are forfeited — the tickets stay
## spent, minus an optional salvage refund (forfeit_refund_ratio, default
## 0 = full loss). Buy it, carry it, or lose it.

signal purchase_completed(total_cost: int, items: Array[ShopItem])
signal purchase_failed(total_cost: int, tickets_available: int)
signal purchases_forfeited(lost_value: int, refunded_tickets: int)

## ShopItem scenes cycled across the shelf anchors at open.
@export var catalog: Array[PackedScene] = []
## Portion of a forfeited purchase's price returned as tickets.
@export_range(0.0, 1.0, 0.05) var forfeit_refund_ratio := 0.0

@onready var _bin: ShopBin = $Bin
@onready var _buy_button: Interactable = $BuyButton
@onready var _stock_anchors: Node3D = $Shelf/StockAnchors
@onready var _drawer_point: Marker3D = $RetrievalDrawer/DropPoint


func _ready() -> void:
	_buy_button.interacted.connect(_on_buy_pressed)
	_stock_shelf()
	# The limo joins its group during the same scene setup; defer so the
	# connection happens after every sibling is ready.
	_connect_limo.call_deferred()


func _stock_shelf() -> void:
	if catalog.is_empty():
		return
	var anchors := _stock_anchors.get_children()
	for i in anchors.size():
		var item := catalog[i % catalog.size()].instantiate() as ShopItem
		if item == null:
			push_warning("ShopTruck: catalog entry %d is not a ShopItem scene." % (i % catalog.size()))
			continue
		add_child(item)
		item.global_position = (anchors[i] as Node3D).global_position


func _connect_limo() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"limo"):
		var limo := node as Limo
		if limo != null and not limo.departed.is_connected(_on_limo_departed):
			limo.departed.connect(_on_limo_departed)


func _on_buy_pressed(_interactor: Interactor) -> void:
	var items := _bin.get_unpurchased_items()
	if items.is_empty():
		return
	var total := 0
	for item: ShopItem in items:
		total += item.price

	if not Economy.try_spend_tickets(total):
		purchase_failed.emit(total, Economy.tickets)
		return

	for i in items.size():
		var item := items[i]
		item.mark_purchased()
		# Fan purchases out of the drawer mouth so they don't spawn
		# intersecting and explode apart.
		@warning_ignore("integer_division")
		item.global_position = _drawer_point.global_position + Vector3(
			0.5 * float(i % 2) - 0.25,
			0.15 + 0.4 * float(i / 2),
			0.0
		)
		item.linear_velocity = Vector3.ZERO
		item.angular_velocity = Vector3.ZERO
	purchase_completed.emit(total, items)


func _on_limo_departed(_destination_path: String) -> void:
	# Everything still in the truck's custody: shelf/drawer leftovers are
	# children of this node; bin contents may have been reparented to the
	# level by a drop, so union both sets.
	var abandoned: Array[ShopItem] = []
	for node: Node in get_children():
		var item := node as ShopItem
		if item != null:
			abandoned.append(item)
	for item: ShopItem in _bin.get_items():
		if item not in abandoned:
			abandoned.append(item)

	var lost_value := 0
	for item: ShopItem in abandoned:
		if item.held_by != null:
			continue  # in someone's hand — it's leaving with them
		if item.purchased:
			lost_value += item.price
		item.queue_free()

	if lost_value > 0:
		var refund := int(float(lost_value) * forfeit_refund_ratio)
		if refund > 0:
			Economy.grant_tickets(refund)
		purchases_forfeited.emit(lost_value, refund)
