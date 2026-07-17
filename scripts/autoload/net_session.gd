extends Node
## NetSession (autoload): WebRTC mesh lifecycle for 1–6 players.
##
## Godot's high-level multiplayer runs over WebRTCMultiplayerPeer in mesh
## mode: every peer connects to every other, and the HOST is peer 1 — the
## authority for every autoload @rpc in the project. Signaling (exchanging
## SDP offers and ICE candidates) requires an external channel; Phase 7's
## lobby service supplies it, and this scaffold exposes exactly the hooks
## it must call.
##
## Single-player: without a session Godot uses OfflineMultiplayerPeer,
## under which every @rpc with call_local executes purely locally and
## multiplayer.is_server() is true — so all Phase 6 game logic runs
## unchanged with zero setup.

signal session_started(is_host: bool)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const MAX_PLAYERS := 6
const HOST_ID := 1
const DEFAULT_ICE_SERVERS := [{"urls": ["stun:stun.l.google.com:19302"]}]

var _mesh: WebRTCMultiplayerPeer = null


func is_host() -> bool:
	return multiplayer.is_server()


func local_peer_id() -> int:
	return multiplayer.get_unique_id()


func host_session() -> Error:
	return _start(HOST_ID)


## `assigned_peer_id` (2..MAX_PLAYERS+1) comes from the signaling service.
func join_session(assigned_peer_id: int) -> Error:
	return _start(assigned_peer_id)


## Signaling glue: call once per remote peer. Wire the returned
## connection's session_description_created / ice_candidate_created signals
## into your signaling channel, and feed the remote peer's answers back via
## set_remote_description() / add_ice_candidate(). The mesh promotes the
## data channels automatically once ICE completes.
func add_remote_peer(peer_id: int) -> WebRTCPeerConnection:
	if _mesh == null:
		push_error("NetSession: no active session — call host_session()/join_session() first.")
		return null
	var connection := WebRTCPeerConnection.new()
	connection.initialize({"iceServers": DEFAULT_ICE_SERVERS})
	_mesh.add_peer(connection, peer_id)
	return connection


func _start(peer_id: int) -> Error:
	_mesh = WebRTCMultiplayerPeer.new()
	var err := _mesh.create_mesh(peer_id)
	if err != OK:
		push_error("NetSession: create_mesh(%d) failed (error %d)." % [peer_id, err])
		return err
	multiplayer.multiplayer_peer = _mesh
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if peer_id == HOST_ID:
		TableRng.host_initialize()
	session_started.emit(peer_id == HOST_ID)
	return OK


func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)
	if is_host():
		# Late-join snapshot: push current truth to the newcomer only.
		Economy.rpc_sync_wallets.rpc_id(
			peer_id,
			Economy.cash, Economy.tickets,
			Economy.lifetime_earned, Economy.quota_paid
		)
		TableRng.rpc_set_seed.rpc_id(peer_id, TableRng.rng.seed, TableRng.rng.state)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)
