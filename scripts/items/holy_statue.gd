class_name HolyStatue
extends ShopItem
## Loss-insurance idol from the shop truck. While physically HELD at a
## table (PlayerHand — you gamble one-handed), a portion of every losing
## stake is refunded before settlement.
##
## Balance containment: each blessed loss burns one charge; at zero the
## statue crumbles. So the Duck Race printer (see duck_race.gd) runs at
## most `charges` losses deep before you're buying another statue — the
## exploit is a discoverable strategy with a ticket cost, not a faucet.

signal charge_consumed(remaining: int)
signal crumbled

## Fraction of a losing stake refunded (0.6 = lose only 40%).
@export_range(0.0, 1.0, 0.05) var loss_refund_ratio := 0.6
@export var charges := 5


func consume_charge() -> void:
	charges -= 1
	charge_consumed.emit(charges)
	if charges <= 0:
		crumbled.emit()
		queue_free()
