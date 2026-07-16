# Gamble With Friends — Casino Crawler

A 1–6 player WebRTC P2P casino-crawler adaptation for **Android (native)** and
**Web (HTML5/WebGL2)**, built on Godot 4's **Compatibility (GLES3)** renderer.

## Phase 1 — Input Map & Mobile-Friendly UI Layout

### What's in this phase

| File | Purpose |
|---|---|
| `project.godot` | Compatibility renderer on all platforms, `canvas_items`/`expand` stretch, touch→mouse emulation, MSDF fonts |
| `scripts/autoload/input_setup.gd` | Autoload that programmatically registers the full KBM InputMap and owns cross-platform pointer-lock state |
| `scripts/player/mouse_look.gd` | Pointer-lock-compliant look controller (resolution-normalized, browser re-lock spike clamping) |
| `scripts/ui/safe_area_container.gd` | `MarginContainer` that pads the HUD out of notches/hole-punches via `get_display_safe_area()` + `get_display_cutouts()` |
| `scripts/ui/hud.gd` + `scenes/ui/hud.tscn` | Responsive HUD: shared bank balance, 5-minute round timer, quota tracker, interact prompt |

### Default bindings

| Action | Bound to |
|---|---|
| `move_forward/back/left/right` | WASD **and** arrow keys (physical keycodes → layout-independent) |
| Looking | Mouse motion while captured (handled in `MouseLook`, not the InputMap — Godot 4 actions can't bind relative motion) |
| `interact` | Left mouse button (taps too, via `emulate_mouse_from_touch`) |
| `action_pickup` | E |
| `menu_pause` | Escape¹ |
| `menu_scoreboard` | Tab |

¹ On HTML5 the browser reserves Escape to exit pointer lock and Godot never
receives the keypress. `InputSetup` detects the resulting capture loss every
frame and emits `mouse_capture_lost` — connect the pause menu to **both** the
`menu_pause` action and that signal and Escape behaves identically everywhere.

### Pointer lock / mouse capture rules

- Call `InputSetup.request_mouse_capture()` to enter gameplay look mode. On
  desktop/Android it's immediate; on the web it completes on the next click
  if not already inside a user-gesture callback (a browser security rule).
- Call `InputSetup.release_mouse()` when opening betting UI or menus.
- Android physical mice deliver relative motion under `MOUSE_MODE_CAPTURED`
  exactly like desktop, so `MouseLook` needs no per-platform code.

### HUD node hierarchy

```
HUD (Control, full-rect, mouse_filter = IGNORE)          — hud.gd
└── SafeArea (MarginContainer)                           — safe_area_container.gd
    └── Content (Control, full-rect)
        ├── TopBar (HBoxContainer, anchored top-wide)
        │   ├── BankPanel (PanelContainer, felt stylebox)
        │   │   └── BankRow (HBox) → BankTitle + %BankValue
        │   ├── SpacerLeft (Control, expand)
        │   ├── TimerPanel (PanelContainer)
        │   │   └── %TimerValue ("5:00", turns red under 60 s)
        │   ├── SpacerRight (Control, expand)
        │   └── QuotaPanel (PanelContainer)
        │       └── QuotaRow (HBox) → QuotaTitle + %QuotaValue
        └── %InteractPrompt (Label, anchored bottom-center)
```

### Safe zones (notches & hole-punches)

`SafeAreaContainer` recomputes its four margins on every viewport resize:

1. `DisplayServer.get_display_safe_area()` gives the OS-guaranteed
   unobstructed rect (translated from screen to window space).
2. `DisplayServer.get_display_cutouts()` is unioned in, because some devices
   report a hole-punch without shrinking the safe area — each cutout extends
   the margin of whichever window edge it touches.
3. Both APIs return **physical pixels**; the margins are divided by the
   viewport's final-transform scale to convert into `canvas_items` units.
4. A `min_margin_px` floor keeps cosmetic breathing room on cutout-free
   screens, so desktop looks intentional rather than edge-glued.

Because bank/timer/quota all live inside `SafeArea`, they can never render
under a camera cutout regardless of device or orientation. (For Android,
enable *Edge to Edge / render under cutouts* in the export preset so the game
draws fullscreen while the HUD respects the insets.)

### Responsive scaling (5.5" phone → 24" desktop browser)

Three cooperating layers:

- **`canvas_items` stretch, `expand` aspect, 1920×1080 base.** The UI is
  authored once at 1080p; Godot scales the canvas to the window height and
  `expand` grants wider screens (19.5:9 phones, ultrawide browsers) extra
  horizontal canvas instead of black bars. The `HBoxContainer` spacers absorb
  the extra width, so the timer stays centered and bank/quota hug the corners.
- **MSDF fonts** (`gui/theme/default_font_multichannel_signed_distance_field`)
  keep glyph edges crisp at *any* scale factor — no blurry text on a 4K
  monitor or a DPR-3 phone.
- **Small-screen boost.** `hud.gd` measures the physical diagonal via
  `DisplayServer.screen_get_dpi()` / `screen_get_size()`; under 6 inches it
  raises `content_scale_factor` by 15%, lifting the 22–44 px labels back to
  comfortable physical reading size. Everything re-flows automatically
  because the layout is pure containers and anchors — no absolute positions.

## Phase 2 — Customizable Controls & Settings Save System

### What's in this phase

| File | Purpose |
|---|---|
| `scripts/autoload/settings_manager.gd` | ConfigFile-backed persistence to `user://settings.cfg` with corruption quarantine, key rebinding, mouse/accessibility/touch settings |
| `scripts/ui/virtual_joystick.gd` | Floating-origin thumbstick that feeds the `move_*` actions with analog strength |
| `scripts/ui/touch_controls_overlay.gd` | Code-built overlay (joystick + MENU/PICK UP/INTERACT buttons) with AUTO/ALWAYS_ON/OFF visibility |

### Persistence model

- `user://settings.cfg` resolves to app-private storage on Android and the
  IndexedDB-backed filesystem on HTML5 — one path, every platform. Saves are
  **debounced** (max one disk write per 0.4 s while sliders drag) and force-
  flushed on `NOTIFICATION_APPLICATION_PAUSED` / `FOCUS_OUT` / `WM_CLOSE_REQUEST`,
  because mobile OSes kill backgrounded apps without warning.
- **Corruption handling:** a file that fails `ConfigFile.load()` is renamed to
  `settings.corrupt.cfg` and defaults are restored — the game never fails to
  boot over a bad config. Every value read back is type-checked and clamped
  (`_read_float/_read_int/_read_bool`), so a hand-edited file can't inject
  bad state. Only primitives are written — rebinds are stored as physical
  keycodes, never serialized `InputEventKey` objects (deserializing objects
  from a user-editable file is an injection vector).

### Settings surface

| Section | Keys | Applied via |
|---|---|---|
| `[bindings]` | one physical keycode per rebound action | `InputMap` override on top of `InputSetup` defaults |
| `[mouse]` | `sensitivity` (0.1–5), `raw_input`, `confine_to_window` | `MouseLook` multiplier, `Input.use_accumulated_input`, `MOUSE_MODE_CONFINED` for the free cursor (no-op on web) |
| `[accessibility]` | `ui_scale` (0.5–1.5), `panel_opacity` (0–1) | `content_scale_factor` (multiplied with the small-screen boost, now owned by SettingsManager), shared HUD panel StyleBox alpha |
| `[touch]` | `controls_mode` (AUTO / ALWAYS_ON / OFF) | `TouchControlsOverlay` visibility |

### Key rebinding flow

Controls menu calls `SettingsManager.begin_key_capture(&"action_pickup")`,
the next keypress is bound (Escape cancels) and reported via
`key_capture_finished(action, success)`. Labels come from
`get_action_key_label()`, which translates physical keycodes through the
player's real layout. `reset_bindings()` restores Phase 1 defaults.

### Touch fallback (KBM disconnected)

In AUTO mode the overlay appears on the first touch and hides the moment a
physical key or a *real* mouse is used — touch-synthesized mouse events are
filtered out by `device == InputEvent.DEVICE_ID_EMULATION`. So when a
Bluetooth keyboard/mouse drops off an Android tablet mid-run, the next
screen tap brings up thumb controls with no menu digging. The joystick and
buttons drive the real InputMap actions (`Input.action_press` with analog
strength), so gameplay code cannot tell touch from KBM. Hiding the overlay
force-releases every fed action so movement can never stick "on".

> Gameplay note: read `interact` in `_unhandled_input()`, not by polling
> `Input.is_action_just_pressed()` — taps consumed by UI buttons still update
> the global action state, but they never reach `_unhandled_input`.

### Running it

Open in **Godot 4.3+**, press Play — the HUD scene is the main scene for this
phase. `InputSetup` registers all actions at boot, `SettingsManager` then
overlays saved rebinds and applies mouse/accessibility/touch settings, so any
later gameplay scene can immediately read `InputSetup.get_move_vector()` and
the actions above.
