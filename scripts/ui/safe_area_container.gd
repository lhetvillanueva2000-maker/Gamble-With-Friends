@tool
class_name SafeAreaContainer
extends MarginContainer
## Pads its children so HUD elements never sit under a phone notch,
## hole-punch camera, or curved corner — and is a clean no-op on desktop.
##
## Two data sources are combined:
##  1. DisplayServer.get_display_safe_area() — the OS-reported rect that is
##     guaranteed unobstructed (Android P+ insets, iOS safe area on web).
##  2. DisplayServer.get_display_cutouts() — individual cutout rects; some
##     devices report a hole-punch here without shrinking the safe area,
##     so we union them into whichever screen edge each cutout touches.
##
## Both APIs return PHYSICAL pixels, while under `canvas_items` stretch the
## UI lives in scaled canvas units — so margins are divided by the
## viewport's final transform scale before being applied.

## Breathing room (in canvas units) kept on every edge even when the screen
## has no cutouts at all, so panels never kiss the bezel.
@export_range(0, 64) var min_margin_px: int = 12


func _ready() -> void:
	_refresh()
	if not Engine.is_editor_hint():
		get_viewport().size_changed.connect(_refresh)


func _refresh() -> void:
	if Engine.is_editor_hint():
		_set_margins(min_margin_px, min_margin_px, min_margin_px, min_margin_px)
		return

	var window := get_window()
	var win_pos := Vector2(window.position)
	var win_size := Vector2(window.size)
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return

	# Safe area is in screen coordinates; translate into window space.
	# On mobile the window is fullscreen so this is usually a direct copy.
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var left := maxf(safe.position.x - win_pos.x, 0.0)
	var top := maxf(safe.position.y - win_pos.y, 0.0)
	var right := maxf((win_pos.x + win_size.x) - safe.end.x, 0.0)
	var bottom := maxf((win_pos.y + win_size.y) - safe.end.y, 0.0)

	# Fold in explicit cutouts (hole-punch cameras). Each cutout extends the
	# margin of the window edge it touches.
	for cutout: Rect2 in DisplayServer.get_display_cutouts():
		var r := Rect2(cutout.position - win_pos, cutout.size)
		if not Rect2(Vector2.ZERO, win_size).intersects(r):
			continue
		if r.position.x <= 0.0:
			left = maxf(left, r.end.x)
		if r.end.x >= win_size.x:
			right = maxf(right, win_size.x - r.position.x)
		if r.position.y <= 0.0:
			top = maxf(top, r.end.y)
		if r.end.y >= win_size.y:
			bottom = maxf(bottom, win_size.y - r.position.y)

	# Physical pixels -> canvas units (undo the canvas_items stretch scale).
	var canvas_scale := get_viewport().get_final_transform().get_scale()
	if canvas_scale.x <= 0.0 or canvas_scale.y <= 0.0:
		return
	_set_margins(
		maxi(int(ceilf(left / canvas_scale.x)), min_margin_px),
		maxi(int(ceilf(top / canvas_scale.y)), min_margin_px),
		maxi(int(ceilf(right / canvas_scale.x)), min_margin_px),
		maxi(int(ceilf(bottom / canvas_scale.y)), min_margin_px)
	)


func _set_margins(left: int, top: int, right: int, bottom: int) -> void:
	add_theme_constant_override(&"margin_left", left)
	add_theme_constant_override(&"margin_top", top)
	add_theme_constant_override(&"margin_right", right)
	add_theme_constant_override(&"margin_bottom", bottom)
