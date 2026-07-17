class_name BodyState
extends Node
## Body-integrity state machine for one player avatar. Mount as a child of
## the player body (in the "players" group) and set peer_id.
##
## The machine's states are the power set of intact parts; transitions are
## shred_next_part() (Meat Grinder) and restore_next_part() (BetLedger's
## restoration rule). Debuffs are exposed as computed properties the
## controller/voice systems read every frame — no polling of raw state:
##
##   speed_multiplier  -> multiply into max move speed (legs gone = 0.45)
##   throw_multiplier  -> multiply into PlayerHand.throw_speed per lost arm
##   voice_modulated   -> voice chat applies ring-mod/pitch (head gone)

## Grind order is fixed: the machine takes the cheap meat first and the
## head last. Values are what the grinder pays the shared bank per part.
enum Part { LEGS, LEFT_ARM, RIGHT_ARM, HEAD }

signal part_shredded(part: int)
signal part_restored(part: int)

const GRIND_ORDER := [Part.LEGS, Part.LEFT_ARM, Part.RIGHT_ARM, Part.HEAD]
const PART_VALUE := {
	Part.LEGS: 350,
	Part.LEFT_ARM: 200,
	Part.RIGHT_ARM: 200,
	Part.HEAD: 450,
}

const LEGS_SPEED_MULTIPLIER := 0.45
const ARM_THROW_MULTIPLIER := 0.5

@export var peer_id := 1

var _shredded: Dictionary = {}  # Part -> true

## Movement debuff: the controller multiplies its max speed by this.
var speed_multiplier: float:
	get:
		return LEGS_SPEED_MULTIPLIER if is_shredded(Part.LEGS) else 1.0

## Voice debuff flag: the voice-chat pipeline ring-mods when true.
var voice_modulated: bool:
	get:
		return is_shredded(Part.HEAD)

## Throw debuff: each missing arm halves PlayerHand launch speed.
var throw_multiplier: float:
	get:
		var multiplier := 1.0
		if is_shredded(Part.LEFT_ARM):
			multiplier *= ARM_THROW_MULTIPLIER
		if is_shredded(Part.RIGHT_ARM):
			multiplier *= ARM_THROW_MULTIPLIER
		return multiplier


func is_shredded(part: int) -> bool:
	return _shredded.get(part, false)


func shredded_count() -> int:
	return _shredded.size()


func is_healthy() -> bool:
	return _shredded.is_empty()


func is_fully_shredded() -> bool:
	return _shredded.size() >= GRIND_ORDER.size()


## Grinder transition: consumes the next intact part in GRIND_ORDER.
## Returns the part's cash value, or -1 when there is nothing left to take.
func shred_next_part() -> int:
	for part: int in GRIND_ORDER:
		if not is_shredded(part):
			_shredded[part] = true
			part_shredded.emit(part)
			return PART_VALUE[part]
	return -1


## Restoration transition: heals in REVERSE grind order (head first), so
## the scariest debuff clears first. Returns false if already whole.
func restore_next_part() -> bool:
	for i in range(GRIND_ORDER.size() - 1, -1, -1):
		var part: int = GRIND_ORDER[i]
		if is_shredded(part):
			_shredded.erase(part)
			part_restored.emit(part)
			return true
	return false
