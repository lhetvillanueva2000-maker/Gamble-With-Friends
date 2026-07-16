class_name GamePalette
## Central visual language: every color in the game comes from here.
## Static constants only — never instanced. The aesthetic is
## "retro-ominous casino": near-black blues, brass gold, and one loud
## neon accent per floor that gets meaner as the stakes climb.

## --- Core UI -------------------------------------------------------------

const UI_PANEL_BG := Color("0d141c")        ## HUD panel felt (matches hud.tscn)
const UI_GOLD := Color("d9ae35")            ## titles, borders, brass trim
const UI_TEXT := Color("edf5ff")            ## primary readout text

const UI_CASH_POSITIVE := Color("7ce08a")   ## bank balance in the black
const UI_CASH_DEBT := Color("ff5f52")       ## bank balance in debt

const UI_TIMER_NORMAL := Color("edf5ff")    ## > 60 s remaining
const UI_TIMER_WARNING := Color("f55142")   ## <= 60 s
const UI_TIMER_CRITICAL := Color("ff2e1f")  ## <= 10 s (blinks against WARNING)

const UI_TICKETS := Color("e8b84b")         ## shop ticket amber

## --- Floor atmospheres ----------------------------------------------------
## Each floor: background (fog/void), ambient (Environment ambient light),
## surface (architecture tint for the flat env shader), and two neons.

const FLOOR_PALETTES: Dictionary = {
	1: {  # Street Slots — dingy olive daylight bleeding into acid neon
		"name": "Street Slots",
		"background": Color("101208"),
		"ambient": Color("3a4224"),
		"surface": Color("2e5e3a"),
		"neon_primary": Color("b4ff3c"),    # acid green
		"neon_secondary": Color("ffd23f"),  # sodium yellow
	},
	2: {  # Card Room — smoke-stained teal, brass fittings
		"name": "Card Room",
		"background": Color("071214"),
		"ambient": Color("1e3b3d"),
		"surface": Color("1f4e44"),
		"neon_primary": Color("2fe6de"),    # cold cyan
		"neon_secondary": Color("e8a23d"),  # brass
	},
	3: {  # High-Roller Pit — bruised violet, hungry magenta
		"name": "High-Roller Pit",
		"background": Color("120818"),
		"ambient": Color("3a2450"),
		"surface": Color("3d2b5e"),
		"neon_primary": Color("c44bff"),    # violet
		"neon_secondary": Color("ff4ba8"),  # magenta
	},
	4: {  # The Vault — blood red and gold; the house always collects
		"name": "The Vault",
		"background": Color("160406"),
		"ambient": Color("4a1214"),
		"surface": Color("571c22"),
		"neon_primary": Color("ff2e3f"),    # blood red
		"neon_secondary": Color("ffc94b"),  # payout gold
	},
}


static func floor_palette(floor_number: int) -> Dictionary:
	return FLOOR_PALETTES.get(clampi(floor_number, 1, 4), FLOOR_PALETTES[1])
