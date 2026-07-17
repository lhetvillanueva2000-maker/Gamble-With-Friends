class_name DuckRace
extends TableGame
## Duck Race: pick 1 of 4 ducks; the winner pays 4× total (3× profit).
##
## The base game is the casino's ONLY exactly-fair table:
##   EV = p·(m−1)·s − (1−p)·s = 0.25·3s − 0.75·s = 0
##
## THE HOLY STATUE SYNERGY (the "safe-bet multiplier exploit"):
## With a held statue refunding fraction r of losses, any table's EV is
##   EV = p·(m−1)·s − (1−p)·(1−r)·s
## and the break-even refund for any game is
##   r* = 1 − p·(m−1) / (1−p)
## For the Duck Race p=0.25, m=4 gives p·(m−1) = (1−p) = 0.75, so r* = 0:
## ANY refund at all tips the fair game strictly positive —
##   EV = 0.75·r·s          (r=0.6 → +45% of stake per race, guaranteed
##                           in expectation)
## That's the whole exploit: loss insurance is worthless on house-edge
## tables you should't be playing anyway, but on the one fair table it is
## a money printer. Containment: statue charges burn per blessed loss and
## table_max_payout caps a single win.

const DUCK_COUNT := 4


func _init() -> void:
	game_id = &"duck_race"
	table_max_payout = 3_000


func win_probability() -> float:
	return 1.0 / float(DUCK_COUNT)


func payout_multiple() -> float:
	return float(DUCK_COUNT)


## Full race resolution (host-only): one shared-RNG draw decides the
## winning duck for the whole table, so simultaneous bettors on different
## ducks all settle from the same race.
func race(bettor: Node3D, peer_id: int, stake: int, picked_duck: int) -> Dictionary:
	if stake <= 0:
		return {"rejected": true}
	var statue := _held_statue(bettor)
	var refund := statue.loss_refund_ratio if statue != null else 0.0
	TableRng.record_bet_checkpoint({"game": game_id, "peer": peer_id, "stake": stake})
	var winning_duck := TableRng.rng.randi_range(0, DUCK_COUNT - 1)
	var won := winning_duck == clampi(picked_duck, 0, DUCK_COUNT - 1)
	var delta := _settle(peer_id, stake, won, refund, statue)
	return {"won": won, "delta": delta, "winning_duck": winning_duck}


## The exploit's expected profit per race with a held statue.
static func expected_value(stake: float, refund_ratio: float) -> float:
	return 0.75 * refund_ratio * stake
