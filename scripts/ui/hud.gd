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
const TIMER_CRITICAL_SEC := 10.0
const TIMER_BLINK_PERIOD := 0.6

@onready var _bank_value: Label = %BankValue
@onready var _timer_value: Label = %TimerValue
@onready var _quota_value: Label = %QuotaValue
@onready var _interact_prompt: Label = %InteractPrompt

## All three top-bar panels share this one StyleBoxFlat sub-resource, so a
## single write restyles bank, timer, and quota together.
@onready var _panel_style: StyleBoxFlat = \
	$SafeArea/Content/TopBar/BankPanel.get_theme_stylebox(&"panel") as StyleBoxFlat

var _time_remaining := ROUND_LENGTH_SEC
var _timer_running := false


func _ready() -> void:
	SettingsManager.accessibility_settings_changed.connect(_apply_panel_opacity)
	_apply_panel_opacity()
	set_bank_balance(0)
	set_quota(0, 10_000)
	_render_timer()
	_interact_prompt.hide()
	# The 5-minute countdown is started by Main the moment the limo departs;
	# until then the label idles at the full round length.


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
	_bank_value.add_theme_color_override(
		&"font_color",
		GamePalette.UI_CASH_DEBT if amount < 0 else GamePalette.UI_CASH_POSITIVE
	)


func set_quota(current: int, target: int) -> void:
	_quota_value.text = "$%s / $%s" % [
		_format_thousands(current),
		_format_thousands(target),
	]


## key_label reflects live rebinds ("E", "F", "LMB"...) via the Interactor.
func show_interact_prompt(action_text: String = "INTERACT", key_label: String = "E") -> void:
	_interact_prompt.text = "[%s]  %s" % [key_label, action_text]
	_interact_prompt.show()


func hide_interact_prompt() -> void:
	_interact_prompt.hide()


## --- Internals -----------------------------------------------------------


func _render_timer() -> void:
	var total := int(ceilf(_time_remaining))
	@warning_ignore("integer_division")
	_timer_value.text = "%d:%02d" % [total / 60, total % 60]
	_timer_value.add_theme_color_override(&"font_color", _timer_color())


## Escalating urgency: normal -> warning at 60 s -> blinking critical at 10 s.
func _timer_color() -> Color:
	if _time_remaining <= TIMER_CRITICAL_SEC:
		var blink_on := fmod(_time_remaining, TIMER_BLINK_PERIOD) < TIMER_BLINK_PERIOD * 0.5
		return GamePalette.UI_TIMER_CRITICAL if blink_on else GamePalette.UI_TIMER_WARNING
	if _time_remaining <= TIMER_WARNING_SEC:
		return GamePalette.UI_TIMER_WARNING
	return GamePalette.UI_TIMER_NORMAL


## Accessibility: background panel opacity slider (UI scale is applied
## globally by SettingsManager via content_scale_factor — nothing to do
## here, containers re-flow on their own).
func _apply_panel_opacity() -> void:
	var color := _panel_style.bg_color
	color.a = SettingsManager.panel_opacity
	_panel_style.bg_color = color


static func _format_thousands(value: int) -> String:
	var negative := value < 0
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.substr(0, digits.length() - 3)
	out = digits + out
	return "-" + out if negative else out
