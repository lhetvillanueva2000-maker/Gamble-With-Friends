extends Node
## NetSession (autoload): multiplayer session lifecycle for 1–6 players,
## with per-platform transport fallback.
##
## TRANSPORT POLICY
##  - Web build: WebRTC ONLY. Browsers cannot open UDP sockets (no ENet),
##    and raw TCP WebSockets suffer head-of-line blocking. WebRTC's SCTP
##    data channels give UDP-like delivery inside the browser sandbox.
##    Signaling must run over Secure WebSockets (wss://) — an HTTPS page
##    may not open insecure ws:// (mixed-content rules).
##  - Native (Android/desktop): WebRTC when the lobby contains browser
##    peers (cross-play), via the webrtc-native GDExtension. For
##    native-only lobbies and LAN, ENet (UDP) is the better fallback:
##    lower latency, no signaling server needed on LAN. WebSockets remain
##    a last-resort TCP fallback for UDP-hostile networks (hotel Wi-Fi).
##
## Whatever the transport, the high-level MultiplayerPeer is the same to
## the rest of the game: host = peer 1 = authority, and every Phase 6 RPC
## (Economy/TableRng/BetLedger) works unchanged. Single-player uses the
## default OfflineMultiplayerPeer and needs none of this.

signal session_started(is_host: bool)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

enum Transport { WEBRTC, ENET, WEBSOCKET }

const MAX_PLAYERS := 6
const HOST_ID := 1
const DEFAULT_ICE_SERVERS := [{"urls": ["stun:stun.l.google.com:19302"]}]
const ENET_DEFAULT_PORT := 24565

var _mesh: WebRTCMultiplayerPeer = null


func is_host() -> bool:
	return multiplayer.is_server()


func local_peer_id() -> int:
	return multiplayer.get_unique_id()


## Which transport this build should use for a given lobby composition.
func preferred_transport(cross_play_with_web: bool) -> Transport:
	if OS.has_feature("web"):
		return Transport.WEBRTC
	return Transport.WEBRTC if cross_play_with_web else Transport.ENET


## --- WebRTC (web + cross-play) --------------------------------------------


func host_session() -> Error:
	return _start_webrtc(HOST_ID)


## `assigned_peer_id` (2..MAX_PLAYERS+1) comes from the signaling service.
func join_session(assigned_peer_id: int) -> Error:
	return _start_webrtc(assigned_peer_id)


## Signaling glue: call once per remote peer. Wire the returned
## connection's session_description_created / ice_candidate_created signals
## into your signaling channel (wss://), and feed the remote peer's answers
## back via set_remote_description() / add_ice_candidate(). The mesh
## promotes the data channels automatically once ICE completes.
func add_remote_peer(peer_id: int) -> WebRTCPeerConnection:
	if _mesh == null:
		push_error("NetSession: no active WebRTC session.")
		return null
	var connection := WebRTCPeerConnection.new()
	connection.initialize({"iceServers": DEFAULT_ICE_SERVERS})
	_mesh.add_peer(connection, peer_id)
	return connection


func _start_webrtc(peer_id: int) -> Error:
	_mesh = WebRTCMultiplayerPeer.new()
	var err := _mesh.create_mesh(peer_id)
	if err != OK:
		push_error("NetSession: create_mesh(%d) failed (error %d)." % [peer_id, err])
		return err
	multiplayer.multiplayer_peer = _mesh
	_finish_setup(peer_id == HOST_ID)
	return OK


## --- ENet fallback (native-only lobbies / LAN) ----------------------------


func host_session_enet(port: int = ENET_DEFAULT_PORT) -> Error:
	if OS.has_feature("web"):
		push_error("NetSession: ENet (UDP) is unavailable in browsers — use WebRTC.")
		return ERR_UNAVAILABLE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		push_error("NetSession: ENet host failed on port %d (error %d)." % [port, err])
		return err
	_mesh = null
	multiplayer.multiplayer_peer = peer
	_finish_setup(true)
	return OK


func join_session_enet(address: String, port: int = ENET_DEFAULT_PORT) -> Error:
	if OS.has_feature("web"):
		push_error("NetSession: ENet (UDP) is unavailable in browsers — use WebRTC.")
		return ERR_UNAVAILABLE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("NetSession: ENet join %s:%d failed (error %d)." % [address, port, err])
		return err
	_mesh = null
	multiplayer.multiplayer_peer = peer
	_finish_setup(false)
	return OK


## --- Shared wiring ---------------------------------------------------------


func _finish_setup(is_host_session: bool) -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if is_host_session:
		TableRng.host_initialize()
	session_started.emit(is_host_session)


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
