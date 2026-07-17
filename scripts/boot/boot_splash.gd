extends Control
## BootSplash: the real entry point (project main scene). Three jobs:
##  1. Detect the device performance profile before anything visual spawns.
##  2. Precache the composition root and the lobby on worker threads while
##     the splash is on screen — Main's first swap_now() becomes a cache
##     hit instead of a first-frame stall (worst on WebGL2, where shader
##     compilation piles onto scene instantiation).
##  3. Hand off to main.tscn (the menu slots in here in a later phase).

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const PRECACHE_PATHS: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/levels/lobby.tscn",
]
## Splash never flashes away faster than this, even on a hot desktop.
const MIN_SPLASH_SEC := 0.6

@onready var _progress: ProgressBar = %Progress
@onready var _status: Label = %Status

var _boot_started_ms := 0


func _ready() -> void:
	_boot_started_ms = Time.get_ticks_msec()
	GameManager.detect_device_profile()
	_status.text = "DEVICE PROFILE: %s" % GameManager.profile_name()
	for path in PRECACHE_PATHS:
		ResourceLoader.load_threaded_request(path, "PackedScene", true)


func _process(_delta: float) -> void:
	var total := 0.0
	var all_done := true
	for path in PRECACHE_PATHS:
		var progress: Array = []
		match ResourceLoader.load_threaded_get_status(path, progress):
			ResourceLoader.THREAD_LOAD_LOADED:
				total += 1.0
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				all_done = false
				if not progress.is_empty():
					total += float(progress[0])
			_:
				# Failed precache is non-fatal: change_scene_to_file below
				# just loads synchronously instead.
				total += 1.0
	_progress.value = total / float(PRECACHE_PATHS.size()) * 100.0

	var elapsed := float(Time.get_ticks_msec() - _boot_started_ms) / 1000.0
	if all_done and elapsed >= MIN_SPLASH_SEC:
		set_process(false)
		GameManager.set_state(GameManager.GameState.LOBBY)
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)
