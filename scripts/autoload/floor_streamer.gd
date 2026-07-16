extends Node
## FloorStreamer (autoload): background level streaming for casino floors.
##
## Uses ResourceLoader.load_threaded_request() so a whole floor scene
## (geometry, materials, compressed textures) is parsed and uploaded on
## worker threads while the game keeps rendering at full frame rate — the
## limo ride IS the loading screen. Exactly ONE level is ever resident:
## swap_now() frees the outgoing scene before instancing the incoming one,
## which is the single biggest memory lever on low-end Android devices.
##
## Typical flow (driven by Main + Limo):
##   1. Player steps into the limo  -> request_load(floor path)
##   2. Doors close, timer locks in -> await wait_until_ready(path)
##   3. Ride finishes               -> swap_now(path) frees lobby, adds floor
##
## The streamer never decides WHEN to swap — it only reports readiness.

signal load_started(scene_path: String)
## progress is 0.0–1.0, suitable for a limo-interior progress dial.
signal load_progress(scene_path: String, progress: float)
signal load_ready(scene_path: String)
signal load_failed(scene_path: String)
signal level_swapped(scene_path: String, level: Node)

const LOBBY_SCENE := "res://scenes/levels/lobby.tscn"
const FLOOR_SCENES: Dictionary = {
	1: "res://scenes/levels/floors/floor_01.tscn",
	2: "res://scenes/levels/floors/floor_02.tscn",
	3: "res://scenes/levels/floors/floor_03.tscn",
	4: "res://scenes/levels/floors/floor_04.tscn",
}

var current_level: Node = null
var current_level_path := ""

var _container: Node = null
var _pending_path := ""
var _last_result_path := ""
var _last_result_ok := false


func _ready() -> void:
	set_process(false)


## Main registers the Node3D all streamed levels are parented under.
func register_level_container(container: Node) -> void:
	_container = container


func floor_scene_path(floor_number: int) -> String:
	return FLOOR_SCENES.get(floor_number, "")


## Kicks off a threaded load. Safe to call repeatedly with the same path;
## a request for a DIFFERENT path while one is in flight is rejected —
## the game flow only ever needs one destination at a time.
func request_load(path: String) -> void:
	if path.is_empty():
		push_error("FloorStreamer: empty scene path requested.")
		return
	if _pending_path == path:
		return
	if not _pending_path.is_empty():
		push_warning(
			"FloorStreamer: ignoring request for %s while %s is still loading."
			% [path, _pending_path]
		)
		return
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		_record(path, true)
		load_ready.emit(path)
		return

	# use_sub_threads=true: dependencies (meshes, textures, materials) are
	# distributed across multiple worker threads for the fastest wall-clock
	# load — important when hiding the load inside a short limo ride.
	var err := ResourceLoader.load_threaded_request(path, "PackedScene", true)
	if err != OK:
		push_error("FloorStreamer: load_threaded_request(%s) failed (error %d)." % [path, err])
		_record(path, false)
		load_failed.emit(path)
		return
	_pending_path = path
	set_process(true)
	load_started.emit(path)


func _process(_delta: float) -> void:
	if _pending_path.is_empty():
		set_process(false)
		return

	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_pending_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not progress.is_empty():
				load_progress.emit(_pending_path, float(progress[0]))
		ResourceLoader.THREAD_LOAD_LOADED:
			var path := _pending_path
			_pending_path = ""
			set_process(false)
			_record(path, true)
			load_progress.emit(path, 1.0)
			load_ready.emit(path)
		_:
			# THREAD_LOAD_FAILED or THREAD_LOAD_INVALID_RESOURCE: report and
			# stop — the caller decides whether to retry or fall back.
			var path := _pending_path
			_pending_path = ""
			set_process(false)
			_record(path, false)
			push_error("FloorStreamer: threaded load of %s failed (status %d)." % [path, status])
			load_failed.emit(path)


## Coroutine: resolves true once `path` is fully loaded, false if the load
## failed. Starts the request itself if nobody has yet.
func wait_until_ready(path: String) -> bool:
	if path.is_empty():
		return false
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		return true
	if _pending_path != path:
		request_load(path)
		if _pending_path != path:
			# Request was rejected or failed synchronously.
			return _last_result_path == path and _last_result_ok
	while _pending_path == path:
		await get_tree().process_frame
	return _last_result_path == path and _last_result_ok


## Frees the current level and instances `path` in its place. Call only
## after wait_until_ready()/load_ready in normal flow — if the load is
## still in progress this blocks the main thread until it finishes (that's
## load_threaded_get()'s documented behavior), which defeats the streaming.
func swap_now(path: String) -> Node:
	if _container == null:
		push_error("FloorStreamer: no level container registered.")
		return null

	var packed: PackedScene = null
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(path)
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		push_warning("FloorStreamer: swap_now(%s) called mid-load; blocking main thread." % path)
		packed = ResourceLoader.load_threaded_get(path)
	else:
		# Never requested (e.g. the tiny lobby at boot): synchronous load.
		packed = load(path) as PackedScene

	if packed == null:
		push_error("FloorStreamer: could not obtain PackedScene for %s." % path)
		load_failed.emit(path)
		return null

	# Free the outgoing level FIRST so both floors are never resident
	# together — peak memory stays at one-floor-plus-a-PackedScene.
	if current_level != null:
		current_level.queue_free()
		current_level = null
		current_level_path = ""

	var level := packed.instantiate()
	_container.add_child(level)
	current_level = level
	current_level_path = path
	level_swapped.emit(path, level)
	return level


func _record(path: String, ok: bool) -> void:
	_last_result_path = path
	_last_result_ok = ok
