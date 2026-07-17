extends Node
## GameManager (autoload, registered LAST so every other singleton exists
## before it runs). The thin coordination layer above all Phase 1–8
## systems: it owns the device performance profile and the coarse game
## state, and NOTHING else — money stays in Economy, RNG in TableRng,
## scenes in FloorStreamer. Systems ask GameManager questions; it never
## reaches into them.
##
## Autoload load order (project.godot [autoload], top to bottom):
##   InputSetup       actions exist before anything reads them
##   SettingsManager  overlays saved rebinds onto InputSetup defaults
##   FloorStreamer    scene streaming (no dependencies)
##   Economy          wallets (RPC-ready even offline)
##   NetSession       transport; pushes late-join sync into Economy/TableRng
##   TableRng         shared RNG; snapshots Economy state
##   BetLedger        reads TableRng-driven results, heals BodyStates
##   GameManager      this — coordinates all of the above

signal profile_detected(profile: int)
signal state_changed(previous: int, next: int)

enum DeviceProfile { DESKTOP, HIGH_END_MOBILE, LOW_END_MOBILE }
enum GameState { BOOT, LOBBY, RIDING, ON_FLOOR }

## At or below these, a mobile device is treated as low-end.
const LOW_END_MAX_CORES := 4
const LOW_END_MAX_PHYSICAL_BYTES: int = 3 * 1024 * 1024 * 1024

var device_profile: int = DeviceProfile.DESKTOP
var state: int = GameState.BOOT


## Called once by BootSplash before anything visual spawns. Heuristic on
## purpose: core count everywhere, physical RAM where the platform reports
## it (Android native does; web returns 0 and falls back to cores alone).
func detect_device_profile() -> void:
	var mobile := OS.has_feature("mobile") \
		or OS.has_feature("web_android") or OS.has_feature("web_ios")
	if not mobile:
		device_profile = DeviceProfile.DESKTOP
	else:
		var cores := OS.get_processor_count()
		var physical := int(OS.get_memory_info().get("physical", 0))
		var weak_cpu := cores > 0 and cores <= LOW_END_MAX_CORES
		var weak_ram := physical > 0 and physical <= LOW_END_MAX_PHYSICAL_BYTES
		device_profile = (
			DeviceProfile.LOW_END_MOBILE if (weak_cpu or weak_ram)
			else DeviceProfile.HIGH_END_MOBILE
		)
	profile_detected.emit(device_profile)


## Content scalers ask this. Current consumers: CasinoFloor drops the
## additive neon halos (pure overdraw) on low-end devices.
func is_low_end() -> bool:
	return device_profile == DeviceProfile.LOW_END_MOBILE


func profile_name() -> String:
	match device_profile:
		DeviceProfile.LOW_END_MOBILE:
			return "LOW-END MOBILE"
		DeviceProfile.HIGH_END_MOBILE:
			return "HIGH-END MOBILE"
		_:
			return "DESKTOP"


func set_state(next: int) -> void:
	if next == state:
		return
	var previous := state
	state = next
	state_changed.emit(previous, next)
