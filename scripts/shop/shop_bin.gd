class_name ShopBin
extends Area3D
## The truck's checkout bin: an Area3D that continuously tracks which
## ShopItems are physically resting inside it. Buying is priced from
## whatever is in the bin AT THE MOMENT the button is pressed — throw it
## in, walk to the button, pay.

signal contents_changed(item_count: int, total_price: int)

var _items: Array[ShopItem] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	var item := body as ShopItem
	if item != null and item not in _items:
		_items.append(item)
		_emit_contents()


func _on_body_exited(body: Node3D) -> void:
	var item := body as ShopItem
	if item != null and item in _items:
		_items.erase(item)
		_emit_contents()


func get_items() -> Array[ShopItem]:
	_prune()
	return _items.duplicate()


func get_unpurchased_items() -> Array[ShopItem]:
	_prune()
	var result: Array[ShopItem] = []
	for item: ShopItem in _items:
		if not item.purchased:
			result.append(item)
	return result


func total_price() -> int:
	var total := 0
	for item: ShopItem in get_unpurchased_items():
		total += item.price
	return total


func _prune() -> void:
	_items = _items.filter(
		func(item: ShopItem) -> bool: return is_instance_valid(item)
	)


func _emit_contents() -> void:
	_prune()
	contents_changed.emit(_items.size(), total_price())
