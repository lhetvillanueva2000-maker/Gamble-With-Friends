extends Node
## Main: composition root and run-flow orchestrator.
##
##   Main (Node)                 <- this script
##   ├── World (Node3D)          <- FloorStreamer swaps levels in here
##   └── UI (CanvasLayer)
##       └── HUD (hud.tscn)      <- persists across level swaps
##
## The World/UI split is what makes streaming clean: levels come and go
## under World while the HUD, autoloads, and (later) the WebRTC session
## live on untouched.
##
## Run flow:
##   lobby -> board limo (floor starts streaming) -> doors close
##   -> 5-minute timer locks in -> ride masks the load -> swap_now()
##   -> players drop onto the floor's arrival spawns -> exit elevator
##   -> back to the lobby.

## The ride is never shorter than this, even if the floor loads instantly —
## it sells the transition and guarantees the doors-closed beat.
const MIN_RIDE_SEC := 4.0

@onready var _world: Node3D = $World
@onready var _hud: Hud = $UI/HUD

## Quota target for the floor currently being played (0 = not on a floor).
## Scaled by QuotaMath from the floor's base quota and the crew's hoard.
var _quota_target := 0


func _ready() -> void:
	Economy.cash_changed.connect(_on_cash_changed)
	_hud.set_bank_balance(Economy.cash)
	FloorStreamer.register_level_container(_world)
	FloorStreamer.level_swapped.connect(_on_level_swapped)
	# The lobby is deliberately tiny (a parking lot of boxes), so a
	# synchronous load at boot is imperceptible.
	FloorStreamer.swap_now(FloorStreamer.LOBBY_SCENE)


func _on_level_swapped(_path: String, level: Node) -> void:
	_place_players(level)

	for node: Node in get_tree().get_nodes_in_group(&"limo"):
		var limo := node as Limo
		if limo != null and not limo.departed.is_connected(_on_limo_departed):
			limo.departed.connect(_on_limo_departed)

	var casino_floor := level as CasinoFloor
	if casino_floor != null:
		# Dynamic quota: the floor's base target inflated by the crew's
		# hoarded surplus — earning too much makes the house greedier.
		_quota_target = QuotaMath.scaled_quota(
			casino_floor.quota_target, Economy.lifetime_earned, Economy.quota_paid
		)
		_hud.set_quota(Economy.cash, _quota_target)
		casino_floor.exit_requested.connect(_on_floor_exit_requested)
	else:
		_quota_target = 0


func _on_limo_departed(destination_path: String) -> void:
	# The 5-minute run is locked in the moment the doors close — riding,
	# not walking the floor, is when the clock starts. (Host-replicated in
	# the WebRTC phases; every peer starts from the same signal.)
	_hud.start_round_timer()

	var ride_start_ms := Time.get_ticks_msec()
	var ok: bool = await FloorStreamer.wait_until_ready(destination_path)
	if not ok:
		push_error("Main: '%s' failed to stream; aborting departure." % destination_path)
		return

	var elapsed := float(Time.get_ticks_msec() - ride_start_ms) / 1000.0
	if elapsed < MIN_RIDE_SEC:
		await get_tree().create_timer(MIN_RIDE_SEC - elapsed).timeout

	FloorStreamer.swap_now(destination_path)


func _on_cash_changed(balance: int) -> void:
	_hud.set_bank_balance(balance)
	if _quota_target > 0:
		_hud.set_quota(balance, _quota_target)


func _on_floor_exit_requested() -> void:
	# Phase 3 loop closure: the exit elevator rides back to the lobby.
	# Later phases branch here (next floor up, cash-out, game over).
	var ok: bool = await FloorStreamer.wait_until_ready(FloorStreamer.LOBBY_SCENE)
	if ok:
		FloorStreamer.swap_now(FloorStreamer.LOBBY_SCENE)


## Move every node in the "players" group onto the new level's spawn
## markers (cardboard boxes in the lobby, the arrival dock on floors).
func _place_players(level: Node) -> void:
	var game_level := level as GameLevel
	if game_level == null:
		return
	var spawns := game_level.get_spawn_points()
	if spawns.is_empty():
		return
	var players := get_tree().get_nodes_in_group(&"players")
	for i in players.size():
		var player := players[i] as Node3D
		if player != null:
			player.global_position = spawns[i % spawns.size()].global_position
