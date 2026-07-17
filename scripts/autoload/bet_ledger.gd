extends Node
## BetLedger (autoload): replicated record of every resolved table bet,
## per-player win streaks, and the body-restoration rule.
##
## Tables (host-side) broadcast results with rpc_record_bet; every peer
## updates streaks from the identical replicated stream, so streak state
## needs no extra sync. The restoration rule also runs identically
## everywhere for the same reason.

signal bet_recorded(peer_id: int, game_id: StringName, stake: int, delta: int, won: bool)
signal win_streak_changed(peer_id: int, streak: int)
signal body_part_restored(healer_peer_id: int, patient_peer_id: int)

## Consecutive wins a HEALTHY teammate needs to trigger a restoration.
const RESTORATION_STREAK := 3

var _streaks: Dictionary = {}


@rpc("authority", "call_local", "reliable")
func rpc_record_bet(peer_id: int, game_id: StringName, stake: int,
		delta: int, won: bool) -> void:
	var streak := (int(_streaks.get(peer_id, 0)) + 1) if won else 0
	_streaks[peer_id] = streak
	bet_recorded.emit(peer_id, game_id, stake, delta, won)
	win_streak_changed.emit(peer_id, streak)
	if won and streak >= RESTORATION_STREAK:
		_try_restoration(peer_id)


func win_streak(peer_id: int) -> int:
	return int(_streaks.get(peer_id, 0))


## Restoration rule: a HEALTHY player (no shredded parts — the casino only
## honors miracles from the whole) who wins RESTORATION_STREAK consecutive
## table bets restores one body part on the most-damaged crew member, and
## the streak is spent.
func _try_restoration(healer_peer_id: int) -> void:
	var healer := _find_body(healer_peer_id)
	if healer == null or not healer.is_healthy():
		return

	var patient: BodyState = null
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var body := _body_of(node)
		if body != null and body.shredded_count() > 0:
			if patient == null or body.shredded_count() > patient.shredded_count():
				patient = body
	if patient == null:
		return

	if patient.restore_next_part():
		_streaks[healer_peer_id] = 0
		win_streak_changed.emit(healer_peer_id, 0)
		body_part_restored.emit(healer_peer_id, patient.peer_id)


func _find_body(peer_id: int) -> BodyState:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var body := _body_of(node)
		if body != null and body.peer_id == peer_id:
			return body
	return null


func _body_of(player: Node) -> BodyState:
	for child: Node in player.get_children():
		if child is BodyState:
			return child as BodyState
	return null
