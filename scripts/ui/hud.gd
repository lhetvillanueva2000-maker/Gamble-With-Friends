class_name Hud
extends Control
## Casino Crawler round HUD: shared bank balance, 5-minute round timer, and
## quota tracker, all living inside a SafeAreaContainer so nothing is ever
## clipped by a notch or hole-punch.
##
## Multiplayer note: this node only DISPLAYS state. The host replicates
## bank/quota/timer values over the WebRTC mesh and every peer calls the
## setters below — the HUD itself holds no authority.

## Emitted once when the round timer hits zero.
signal round_timer_expired

const ROUND_LENGTH_SEC := 300.0
const TIMER_WARNING_SEC := 60.0
const TIMER_NORMAL_COLOR := Color(0.93, 0.96, 1.0)
const TIMER_WARNING_COLOR := Color(0.96, 0.32, 0.26)

## Physical screens smaller than this (diagonal inches) get a readability
## boost on top of the canvas_items stretch scale.
const SMALL_SCREEN_DIAGONAL_IN := 6.0
const SMALL_SCREEN_UI_BOOST := 1.15

@onready var _bank_value: Label = %BankValue
@onready var _timer_value: Label = %TimerValue
@onready var _quota_value: Label = %QuotaValue
@onready var _interact_prompt: Label = %InteractPrompt

var _time_remaining := ROUND_LENGTH_SEC
var _timer_running := false


func _ready() -> void:
	_apply_small_screen_boost()
	set_bank_balance(0)
	set_quota(0, 10_000)
	_render_timer()
	_interact_prompt.hide()
	# Phase 1 demo: start counting immediately. Later phases start this from
	# the host's replicated round-start message instead.
	start_round_timer()


func _process(delta: float) -> void:
	if not _timer_running:
		return
	_time_remaining = maxf(_time_remaining - delta, 0.0)
	_render_timer()
	if _time_remaining == 0.0:
		_timer_running = false
		round_timer_expired.emit()


## --- Public API (called from replicated game state) ---------------------


func start_round_timer(length_sec: float = ROUND_LENGTH_SEC) -> void:
	_time_remaining = length_sec
	_timer_running = true
	_render_timer()


func set_bank_balance(amount: int) -> void:
	_bank_value.text = "$%s" % _format_thousands(amount)


func set_quota(current: int, target: int) -> void:
	_quota_value.text = "$%s / $%s" % [
		_format_thousands(current),
		_format_thousands(target),
	]


func show_interact_prompt(action_text: String = "INTERACT") -> void:
	_interact_prompt.text = "[E]  %s" % action_text
	_interact_prompt.show()


func hide_interact_prompt() -> void:
	_interact_prompt.hide()


## --- Internals -----------------------------------------------------------


func _render_timer() -> void:
	var total := int(ceilf(_time_remaining))
	@warning_ignore("integer_division")
	_timer_value.text = "%d:%02d" % [total / 60, total % 60]
	_timer_value.add_theme_color_override(
		&"font_color",
		TIMER_WARNING_COLOR if _time_remaining <= TIMER_WARNING_SEC else TIMER_NORMAL_COLOR
	)


## On a 5.5" phone the canvas_items stretch already shrinks the 1080p layout
## to fit, which can push 24 px labels below comfortable reading size. If the
## physical panel is small, scale the whole content up ~15% — everything
## re-flows because the layout is pure containers/anchors.
func _apply_small_screen_boost() -> void:
	if not OS.has_feature("mobile") and not _is_mobile_browser():
		return
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return
	var diagonal_in := Vector2(DisplayServer.screen_get_size()).length() / float(dpi)
	if diagonal_in > 0.0 and diagonal_in < SMALL_SCREEN_DIAGONAL_IN:
		get_window().content_scale_factor = SMALL_SCREEN_UI_BOOST


func _is_mobile_browser() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios")


static func _format_thousands(value: int) -> String:
	var negative := value < 0
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.substr(0, digits.length() - 3)
	out = digits + out
	return "-" + out if negative else out
