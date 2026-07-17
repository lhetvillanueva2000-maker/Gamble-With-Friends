extends Node
## TableRng (autoload): ONE deterministic RandomNumberGenerator shared by
## every peer, plus the Time Machine undo buffer.
##
## Determinism contract: the host randomizes once and pushes seed+state to
## everyone; from then on ONLY host-side bet resolution consumes draws, in
## a strict order, and results replicate through Economy/BetLedger. Because
## every peer holds the identical (seed, state) pair, a rollback is just
## "restore an earlier state integer" — the dice that were about to come
## up will come up again, but the erased bet never happened.
##
## Time Machine: before every bet resolution the table records a checkpoint
## (RNG state + wallet snapshot). The buffer keeps the last 3. Triggering
## the item asks the host, which broadcasts the authoritative restore.

signal seed_initialized(seed_value: int)
signal checkpoint_recorded(depth: int)
signal rolled_back(remaining_undos: int)

const MAX_SNAPSHOTS := 3

var rng := RandomNumberGenerator.new()

var _snapshots: Array[Dictionary] = []


## Host only: fresh entropy, then push to every peer (and to itself via
## call_local, which also clears the undo buffer).
func host_initialize() -> void:
	if not multiplayer.is_server():
		return
	rng.randomize()
	rpc_set_seed.rpc(rng.seed, rng.state)


@rpc("authority", "call_local", "reliable")
func rpc_set_seed(seed_value: int, state_value: int) -> void:
	rng.seed = seed_value
	rng.state = state_value
	_snapshots.clear()
	seed_initialized.emit(seed_value)


## Call IMMEDIATELY BEFORE consuming any draws for a bet. Tables do this
## for you (TableGame/StreetCraps/DuckRace all checkpoint first).
func record_bet_checkpoint(context: Dictionary = {}) -> void:
	_snapshots.append({
		"rng_state": rng.state,
		"cash": Economy.cash,
		"tickets": Economy.tickets,
		"lifetime_earned": Economy.lifetime_earned,
		"quota_paid": Economy.quota_paid,
		"context": context,
	})
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()
	checkpoint_recorded.emit(_snapshots.size())


func can_undo() -> bool:
	return not _snapshots.is_empty()


func undo_depth() -> int:
	return _snapshots.size()


## The Time Machine item calls this on ANY peer. The host validates and
## broadcasts the authoritative restore; nothing is popped here so the
## pop happens exactly once per peer inside rpc_apply_rollback (the host
## included, via call_local).
@rpc("any_peer", "call_local", "reliable")
func rpc_request_time_machine() -> void:
	if not multiplayer.is_server():
		return
	if _snapshots.is_empty():
		return
	var snap: Dictionary = _snapshots.back()
	rpc_apply_rollback.rpc(
		snap.rng_state, snap.cash, snap.tickets,
		snap.lifetime_earned, snap.quota_paid
	)


@rpc("authority", "call_local", "reliable")
func rpc_apply_rollback(rng_state: int, cash_value: int, tickets_value: int,
		lifetime_value: int, quota_paid_value: int) -> void:
	if not _snapshots.is_empty():
		_snapshots.pop_back()
	# The erased bet's draws return to the deck: same state integer means
	# the next randi() reproduces exactly what the undone bet consumed.
	rng.state = rng_state
	Economy.apply_authoritative(
		cash_value, tickets_value, lifetime_value, quota_paid_value
	)
	rolled_back.emit(_snapshots.size())
