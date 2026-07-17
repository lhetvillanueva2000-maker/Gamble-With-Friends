class_name StreetCraps
extends TableGame
## Street Craps: roll 2d6 against the house's 2d6, higher total wins even
## money — and the HOUSE WINS TIES. That tie rule is the entire edge:
##
##   P(tie)  = Σ_t P(total=t)² = 146/1296 ≈ 0.1127
##   P(win)  = (1 − P(tie)) / 2 ≈ 0.4437
##   EV(s)   = P(win)·s − (1−P(win))·s = −P(tie)·s ≈ −0.113·s
##
## THE DOUBLE-DOWN EXPLOIT (deliberate, discoverable):
## After the dice land there is a SETTLING_WINDOW during which
## double_down() re-settles the SAME roll against a fresh stake — no new
## RNG draw. A player who watches the dice and only doubles into wins
## converts an 11.3% house-edge table into a guaranteed-win loop.
##
## Engineering note: the fiction is "float precision error"; the
## implementation is a timing bug on purpose. All balances here are
## INTEGER math — a genuine float accumulation error would drift
## differently per platform/precision and desync the deterministic WebRTC
## lockstep, so we ship the fantasy without the poison.
##
## Containment (why "infinite" isn't): table_max_payout caps every single
## settlement, and each exploited window adds heat — at HEAT_LIMIT the pit
## boss "fixes the table" (window closes permanently) until the floor is
## streamed fresh, and doubled stakes get no statue insurance.

signal table_fixed

const SETTLING_WINDOW_SEC := 0.25
const HEAT_LIMIT := 3

var _last_player_total := 0
var _last_house_total := 0
var _last_won := false
var _settle_deadline_ms := 0
var _heat := 0


func _init() -> void:
	game_id = &"street_craps"
	table_max_payout = 4_000


func win_probability() -> float:
	return (1.0 - 146.0 / 1296.0) * 0.5


## Host-only. Rolls player vs house from the shared RNG and settles.
func roll_pass(bettor: Node3D, peer_id: int, stake: int) -> Dictionary:
	if stake <= 0:
		return {"rejected": true}
	var statue := _held_statue(bettor)
	var refund := statue.loss_refund_ratio if statue != null else 0.0
	TableRng.record_bet_checkpoint({"game": game_id, "peer": peer_id, "stake": stake})
	_last_player_total = _roll_2d6()
	_last_house_total = _roll_2d6()
	_last_won = _last_player_total > _last_house_total
	_settle_deadline_ms = Time.get_ticks_msec() + int(SETTLING_WINDOW_SEC * 1000.0)
	var delta := _settle(peer_id, stake, _last_won, refund, statue)
	return {
		"won": _last_won,
		"delta": delta,
		"player_total": _last_player_total,
		"house_total": _last_house_total,
	}


## THE BUG: inside the settling window the previous result is re-applied
## to a fresh stake without consuming the RNG. Host-only, like all rolls.
func double_down(peer_id: int, stake: int) -> Dictionary:
	if stake <= 0:
		return {"rejected": true}
	if _heat >= HEAT_LIMIT:
		return {"rejected": true, "reason": "table_fixed"}
	if Time.get_ticks_msec() > _settle_deadline_ms:
		return {"rejected": true, "reason": "window_missed"}

	_heat += 1
	var delta := _settle(peer_id, stake, _last_won, 0.0, null)
	if _heat >= HEAT_LIMIT:
		table_fixed.emit()
	return {
		"won": _last_won,
		"delta": delta,
		"heat": _heat,
		"reused_roll": [_last_player_total, _last_house_total],
	}


func heat() -> int:
	return _heat


func _roll_2d6() -> int:
	return TableRng.rng.randi_range(1, 6) + TableRng.rng.randi_range(1, 6)
