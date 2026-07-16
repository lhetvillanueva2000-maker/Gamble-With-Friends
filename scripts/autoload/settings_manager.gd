extends Node
## SettingsManager (autoload, registered AFTER InputSetup so defaults exist
## before saved overrides are applied on top).
##
## Persists every player-configurable option through Godot's ConfigFile to
## `user://settings.cfg`. `user://` resolves to app-private storage on
## Android and to the IndexedDB-backed emscripten filesystem on HTML5
## (Godot flushes IndexedDB shortly after each write), so a single code
## path covers every target platform.
##
## Design rules:
##  - Live values are plain properties; their setters clamp, apply the
##    engine-side effect immediately, persist, and emit a section signal.
##    UI panels pull current values in _ready() and subscribe to signals.
##  - Only PRIMITIVES are written to disk (ints/floats/bools). ConfigFile
##    can serialize whole Objects, but deserializing objects from a
##    user-editable file is an injection vector — key rebinds are therefore
##    stored as bare physical keycodes, not InputEventKey resources.
##  - A corrupted file is quarantined to settings.corrupt.cfg and defaults
##    are restored; the game never fails to boot over a bad config.

signal mouse_settings_changed
signal accessibility_settings_changed
signal touch_settings_changed
signal binding_changed(action: StringName)
signal key_capture_finished(action: StringName, success: bool)

enum TouchControlsMode {
	AUTO,       ## Show when the last input was touch, hide when KBM is used.
	ALWAYS_ON,  ## Force the overlay (e.g. player prefers thumb controls).
	OFF,        ## Never show, even on pure touch devices.
}

const SETTINGS_PATH := "user://settings.cfg"
const CORRUPT_BACKUP_PATH := "user://settings.corrupt.cfg"
const CONFIG_VERSION := 1
const SAVE_DEBOUNCE_SEC := 0.4

const SECTION_META := "meta"
const SECTION_BINDINGS := "bindings"
const SECTION_MOUSE := "mouse"
const SECTION_ACCESSIBILITY := "accessibility"
const SECTION_TOUCH := "touch"

const MOUSE_SENSITIVITY_MIN := 0.1
const MOUSE_SENSITIVITY_MAX := 5.0
const UI_SCALE_MIN := 0.5
const UI_SCALE_MAX := 1.5

const DEFAULT_MOUSE_SENSITIVITY := 1.0
const DEFAULT_RAW_INPUT := true
const DEFAULT_CONFINE_TO_WINDOW := true
const DEFAULT_UI_SCALE := 1.0
const DEFAULT_PANEL_OPACITY := 0.82

## Physical screens smaller than this diagonal (inches) get an extra UI
## boost multiplied into the accessibility scale (moved here from the HUD
## in Phase 1 — device-level scaling is this manager's job now).
const SMALL_SCREEN_DIAGONAL_IN := 6.0
const SMALL_SCREEN_UI_BOOST := 1.15

## --- Live settings -------------------------------------------------------

var mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY:
	set(value):
		mouse_sensitivity = clampf(value, MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)
		_persist(SECTION_MOUSE, "sensitivity", mouse_sensitivity)
		mouse_settings_changed.emit()

## true = per-event motion (Input.use_accumulated_input off) for the most
## responsive aim; false = engine-accumulated motion (one merged event per
## frame, cheaper on low-end phones).
var mouse_raw_input := DEFAULT_RAW_INPUT:
	set(value):
		mouse_raw_input = value
		Input.use_accumulated_input = not mouse_raw_input
		_persist(SECTION_MOUSE, "raw_input", mouse_raw_input)
		mouse_settings_changed.emit()

## Keep the free (non-captured) cursor confined to the game window so a
## fast drag toward a bet button can't slide onto a second monitor.
## Ignored on web — outside pointer lock the browser owns the cursor.
var mouse_confine_to_window := DEFAULT_CONFINE_TO_WINDOW:
	set(value):
		mouse_confine_to_window = value
		_reapply_free_mouse_mode()
		_persist(SECTION_MOUSE, "confine_to_window", mouse_confine_to_window)
		mouse_settings_changed.emit()

## Accessibility: whole-UI scale, 0.5x–1.5x.
var ui_scale := DEFAULT_UI_SCALE:
	set(value):
		ui_scale = clampf(value, UI_SCALE_MIN, UI_SCALE_MAX)
		_apply_ui_scale()
		_persist(SECTION_ACCESSIBILITY, "ui_scale", ui_scale)
		accessibility_settings_changed.emit()

## Accessibility: background opacity of HUD panels (0 = fully transparent).
var panel_opacity := DEFAULT_PANEL_OPACITY:
	set(value):
		panel_opacity = clampf(value, 0.0, 1.0)
		_persist(SECTION_ACCESSIBILITY, "panel_opacity", panel_opacity)
		accessibility_settings_changed.emit()

var touch_controls_mode: int = TouchControlsMode.AUTO:
	set(value):
		touch_controls_mode = clampi(value, TouchControlsMode.AUTO, TouchControlsMode.OFF)
		_persist(SECTION_TOUCH, "controls_mode", touch_controls_mode)
		touch_settings_changed.emit()

var _config := ConfigFile.new()
var _suspend_persist := false
var _save_pending := false
var _capture_action: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()


func _notification(what: int) -> void:
	# Mobile OSes may kill a backgrounded app without warning — flush any
	# pending write the moment we lose the foreground.
	match what:
		NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_APPLICATION_FOCUS_OUT, \
		NOTIFICATION_WM_CLOSE_REQUEST:
			if _save_pending:
				save_now()


## --- Key rebinding -------------------------------------------------------


## Rebinds `action` to the key in `event`, replacing its keyboard events
## (mouse-button events on the action are preserved). Returns false for
## unknown actions or events carrying no usable keycode.
func rebind_action_key(action: StringName, event: InputEventKey) -> bool:
	if not InputSetup.KEY_ACTIONS.has(action):
		push_warning("SettingsManager: '%s' is not a rebindable action." % action)
		return false
	var keycode := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if keycode == KEY_NONE:
		return false
	_apply_key_override(action, keycode)
	_persist(SECTION_BINDINGS, action, keycode)
	binding_changed.emit(action)
	return true


## "Press any key" flow for the controls menu: call this, then the next key
## the player presses is bound to `action` (Escape cancels). The result is
## reported through key_capture_finished(action, success).
func begin_key_capture(action: StringName) -> void:
	if not InputSetup.KEY_ACTIONS.has(action):
		push_warning("SettingsManager: cannot capture for unknown action '%s'." % action)
		return
	_capture_action = action


func cancel_key_capture() -> void:
	_capture_action = &""


func is_capturing_key() -> bool:
	return _capture_action != &""


## Restores every action to the Phase 1 defaults and erases saved overrides.
func reset_bindings() -> void:
	InputSetup.register_default_actions()
	if _config.has_section(SECTION_BINDINGS):
		_config.erase_section(SECTION_BINDINGS)
	queue_save()
	for action: StringName in InputSetup.KEY_ACTIONS:
		binding_changed.emit(action)


## Human-readable key name for controls-menu labels ("E", "Shift", "F"...),
## translated from the physical key to the player's actual keyboard layout.
func get_action_key_label(action: StringName) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		var keycode := key.keycode
		if key.physical_keycode != KEY_NONE:
			keycode = DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
		return OS.get_keycode_string(keycode)
	return ""


func _unhandled_key_input(event: InputEvent) -> void:
	if _capture_action == &"":
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	var action := _capture_action
	_capture_action = &""
	if key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
		key_capture_finished.emit(action, false)
		return
	key_capture_finished.emit(action, rebind_action_key(action, key))


## --- Touch fallback ------------------------------------------------------


## Whether the touch overlay should currently exist at all. In AUTO the
## overlay itself additionally shows/hides live based on the last-used
## input device (see TouchControlsOverlay).
func touch_controls_wanted() -> bool:
	match touch_controls_mode:
		TouchControlsMode.ALWAYS_ON:
			return true
		TouchControlsMode.OFF:
			return false
		_:
			return DisplayServer.is_touchscreen_available()


## --- Saving --------------------------------------------------------------


## Debounced save: slider drags produce dozens of changes per second; disk
## (or IndexedDB) sees at most one write per SAVE_DEBOUNCE_SEC.
func queue_save() -> void:
	if _suspend_persist or _save_pending:
		return
	_save_pending = true
	get_tree().create_timer(SAVE_DEBOUNCE_SEC).timeout.connect(save_now)


func save_now() -> void:
	_save_pending = false
	_config.set_value(SECTION_META, "version", CONFIG_VERSION)
	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: could not write %s (error %d)." % [SETTINGS_PATH, err])


## --- Internals -----------------------------------------------------------


func _load_settings() -> void:
	_config = ConfigFile.new()
	if FileAccess.file_exists(SETTINGS_PATH):
		var err := _config.load(SETTINGS_PATH)
		if err != OK:
			push_warning(
				"SettingsManager: %s is corrupted (error %d) — quarantining it and restoring defaults."
				% [SETTINGS_PATH, err]
			)
			_config = ConfigFile.new()
			_quarantine_corrupt_file()

	# Route loaded values through the setters so they are clamped, applied
	# to the engine, and announced — but not re-written to disk.
	_suspend_persist = true
	mouse_sensitivity = _read_float(
		SECTION_MOUSE, "sensitivity",
		DEFAULT_MOUSE_SENSITIVITY, MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX
	)
	mouse_raw_input = _read_bool(SECTION_MOUSE, "raw_input", DEFAULT_RAW_INPUT)
	mouse_confine_to_window = _read_bool(
		SECTION_MOUSE, "confine_to_window", DEFAULT_CONFINE_TO_WINDOW
	)
	ui_scale = _read_float(
		SECTION_ACCESSIBILITY, "ui_scale", DEFAULT_UI_SCALE, UI_SCALE_MIN, UI_SCALE_MAX
	)
	panel_opacity = _read_float(
		SECTION_ACCESSIBILITY, "panel_opacity", DEFAULT_PANEL_OPACITY, 0.0, 1.0
	)
	touch_controls_mode = _read_int(
		SECTION_TOUCH, "controls_mode",
		TouchControlsMode.AUTO, TouchControlsMode.AUTO, TouchControlsMode.OFF
	)
	_apply_saved_bindings()
	_suspend_persist = false


func _apply_saved_bindings() -> void:
	for action: StringName in InputSetup.KEY_ACTIONS:
		if not _config.has_section_key(SECTION_BINDINGS, action):
			continue
		var raw: Variant = _config.get_value(SECTION_BINDINGS, action)
		# Hand-edited or damaged entries are skipped, never trusted.
		if typeof(raw) != TYPE_INT or raw <= 0:
			continue
		_apply_key_override(action, raw as Key)
		binding_changed.emit(action)


func _apply_key_override(action: StringName, keycode: Key) -> void:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var new_event := InputEventKey.new()
	new_event.physical_keycode = keycode
	InputMap.action_add_event(action, new_event)


func _apply_ui_scale() -> void:
	get_window().content_scale_factor = ui_scale * _small_screen_boost()


func _small_screen_boost() -> float:
	var is_mobile := OS.has_feature("mobile") \
		or OS.has_feature("web_android") or OS.has_feature("web_ios")
	if not is_mobile:
		return 1.0
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return 1.0
	var diagonal_in := Vector2(DisplayServer.screen_get_size()).length() / float(dpi)
	if diagonal_in > 0.0 and diagonal_in < SMALL_SCREEN_DIAGONAL_IN:
		return SMALL_SCREEN_UI_BOOST
	return 1.0


## If the cursor is currently free, re-resolve VISIBLE vs CONFINED through
## InputSetup (which owns mouse-mode policy). Captured mode is untouched.
func _reapply_free_mouse_mode() -> void:
	var mode := Input.get_mouse_mode()
	if mode == Input.MOUSE_MODE_VISIBLE or mode == Input.MOUSE_MODE_CONFINED:
		InputSetup.release_mouse()


func _persist(section: String, key: String, value: Variant) -> void:
	if _suspend_persist:
		return
	_config.set_value(section, key, value)
	queue_save()


func _quarantine_corrupt_file() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.file_exists(CORRUPT_BACKUP_PATH.get_file()):
		dir.remove(CORRUPT_BACKUP_PATH.get_file())
	if dir.rename(SETTINGS_PATH.get_file(), CORRUPT_BACKUP_PATH.get_file()) != OK:
		dir.remove(SETTINGS_PATH.get_file())


## Typed, clamped readers: a hand-edited config can hold any Variant, so
## every value is validated before it touches engine state.
func _read_float(section: String, key: String, default_value: float,
		min_value: float, max_value: float) -> float:
	var raw: Variant = _config.get_value(section, key, default_value)
	if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
		return clampf(float(raw), min_value, max_value)
	return default_value


func _read_int(section: String, key: String, default_value: int,
		min_value: int, max_value: int) -> int:
	var raw: Variant = _config.get_value(section, key, default_value)
	if typeof(raw) == TYPE_INT:
		return clampi(raw, min_value, max_value)
	return default_value


func _read_bool(section: String, key: String, default_value: bool) -> bool:
	var raw: Variant = _config.get_value(section, key, default_value)
	if typeof(raw) == TYPE_BOOL:
		return raw
	return default_value
