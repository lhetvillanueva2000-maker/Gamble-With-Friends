extends Node
## Economy (autoload): the crew's two shared wallets.
##
##  - cash:    the run bank — what the quota is measured against. Fed by
##             table winnings and the Meat Grinder; shown on the HUD.
##  - tickets: the shop currency spent at the truck between runs.
##
## Multiplayer note: values here become host-authoritative in the WebRTC
## phases — peers render replicated balances and request spends via the
## same method names, so nothing built on this API changes.

signal cash_changed(balance: int)
signal tickets_changed(balance: int)

const STARTING_TICKETS := 100

var cash := 0:
	set(value):
		cash = maxi(value, 0)
		cash_changed.emit(cash)

var tickets := STARTING_TICKETS:
	set(value):
		tickets = maxi(value, 0)
		tickets_changed.emit(tickets)


func deposit_cash(amount: int) -> void:
	if amount > 0:
		cash += amount


## Atomic check-and-deduct; returns false (and changes nothing) if the
## crew can't afford it.
func try_spend_tickets(cost: int) -> bool:
	if cost < 0 or cost > tickets:
		return false
	tickets -= cost
	return true


func grant_tickets(amount: int) -> void:
	if amount > 0:
		tickets += amount
