class_name Limo
extends Node3D
## The transition capsule between the lobby and a casino floor. Boarding it
## is what triggers the background floor load, and departing is what locks
## in the 5-minute round timer — so by the time the "ride" ends, the
## destination is already resident in memory and the drop-in is seamless.
##
## Multiplayer note: in the WebRTC phases the HOST owns expected_players
## (from the lobby roster) and replicates request_departure(); this node's
## API is already shaped for that.

signal boarding_changed(aboard: int, expected: int)
## Doors closed, ride started. Main reacts by starting the round timer and
## swapping to `destination_path` once the stream is ready.
signal departed(destination_path: String)

@export_range(1, 4) var destination_floor := 1
## Players expected this run (set from the session roster later).
@export_range(1, 6) var expected_players := 1
## Depart automatically the moment everyone is seated.
@export var auto_depart_when_full := true

var _aboard: Array[Node3D] = []
var _has_departed := false

@onready var _seats: Node3D = $Cabin/Seats
@onready var _cabin_trigger: Area3D = $Cabin/CabinTrigger


func _ready() -> void:
	add_to_group(&"limo")
	_cabin_trigger.body_entered.connect(_on_cabin_entered)
	_cabin_trigger.body_exited.connect(_on_cabin_exited)


func destination_path() -> String:
	return FloorStreamer.floor_scene_path(destination_floor)


## Manual departure hook (driver-seat interact in a later phase, or the
## host's replicated go-signal). No-op with an empty cabin.
func request_departure() -> void:
	if _has_departed or _aboard.is_empty():
		return
	_has_departed = true
	_seat_passengers()
	departed.emit(destination_path())


func _on_cabin_entered(body: Node3D) -> void:
	if _has_departed or not body.is_in_group(&"players") or body in _aboard:
		return
	_aboard.append(body)
	if _aboard.size() == 1:
		# First boot in the cabin starts the background load — the rest of
		# the boarding window masks the streaming time entirely.
		FloorStreamer.request_load(destination_path())
	boarding_changed.emit(_aboard.size(), expected_players)
	if auto_depart_when_full and _aboard.size() >= expected_players:
		request_departure()


func _on_cabin_exited(body: Node3D) -> void:
	if _has_departed or body not in _aboard:
		return
	_aboard.erase(body)
	boarding_changed.emit(_aboard.size(), expected_players)


## Pin everyone to a seat so nobody is left straddling the door when the
## level swaps under their feet.
func _seat_passengers() -> void:
	var seat_count := _seats.get_child_count()
	if seat_count == 0:
		return
	for i in _aboard.size():
		var seat := _seats.get_child(mini(i, seat_count - 1)) as Node3D
		if seat != null:
			_aboard[i].global_position = seat.global_position
