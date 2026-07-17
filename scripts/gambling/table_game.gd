class_name TableGame
extends Node3D
## Base class for every casino table. Subclasses declare their odds
## (win_probability / payout_multiple); this class owns the bet lifecycle:
##
##   checkpoint -> draw from TableRng -> settle integer money -> replicate
##
## HOST-ONLY resolution: only the host calls resolve_bet()/subclass rolls,
## consuming the shared RNG in a strict order; results reach every peer
## through Economy (wallets) and BetLedger (streaks). All money math is
## INTEGER — floats appear only in probabilities, never in balances, so
## peers can never drift apart by fractions of a chip.

signal bet_resolved(peer_id: int, stake: int, delta: int, won: bool)

@export var game_id: StringName = &"table"
## House limit: the largest single-settlement win this table pays out.
## This is the hard containment for every exploit loop in the game.
@export var table_max_payout := 5_000


## Chance the bettor wins. Override per game.
func win_probability() -> float:
	return 0.5


## Total returned on a win as a multiple of stake (2.0 = even money).
func payout_multiple() -> float:
	return 2.0


## Generic single-draw resolution. Host-only.
func resolve_bet(bettor: Node3D, peer_id: int, stake: int) -> Dictionary:
	if stake <= 0:
		return {"rejected": true}
	var statue := _held_statue(bettor)
	var refund := statue.loss_refund_ratio if statue != null else 0.0
	TableRng.record_bet_checkpoint({"game": game_id, "peer": peer_id, "stake": stake})
	var won := TableRng.rng.randf() < win_probability()
	var delta := _settle(peer_id, stake, won, refund, statue)
	return {"won": won, "delta": delta, "refund_ratio": refund}


## Shared settlement: integer money, house limit, statue insurance.
##   win:  +min(stake·(m−1), table_max_payout)
##   loss: −stake·(1−r)   (r = loss refund from a HELD Holy Statue)
func _settle(peer_id: int, stake: int, won: bool,
		refund_ratio: float, statue: HolyStatue) -> int:
	var delta: int
	if won:
		delta = mini(int(round(float(stake) * (payout_multiple() - 1.0))), table_max_payout)
	else:
		delta = -int(round(float(stake) * (1.0 - refund_ratio)))
		if statue != null:
			statue.consume_charge()
	Economy.rpc_request_cash_delta.rpc(delta, String(game_id))
	BetLedger.rpc_record_bet.rpc(peer_id, game_id, stake, delta, won)
	bet_resolved.emit(peer_id, stake, delta, won)
	return delta


## The Holy Statue only works while physically HELD at the table — carried
## in the bettor's PlayerHand, not in a pocket, not in the bin.
func _held_statue(bettor: Node3D) -> HolyStatue:
	if bettor == null:
		return null
	for node: Node in bettor.find_children("*", "Node3D", true, false):
		var hand := node as PlayerHand
		if hand != null and hand.is_holding() and hand.held is HolyStatue:
			return hand.held as HolyStatue
	return null
