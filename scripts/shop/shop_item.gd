class_name ShopItem
extends Carryable
## A priced, physically-carried piece of shop stock. Unpurchased copies
## live on the truck shelf; once bought they respawn in the retrieval
## drawer flagged `purchased` and become the crew's property — if they can
## be bothered to carry them to the limo.

@export var price := 15

var purchased := false


func mark_purchased() -> void:
	purchased = true
	if _pickup_zone != null:
		_pickup_zone.prompt_text = "PICK UP %s (PAID)" % display_name
