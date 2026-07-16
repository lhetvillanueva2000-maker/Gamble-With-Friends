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

## Phase 3 — Building Architecture & Flow

### What's in this phase

| File | Purpose |
|---|---|
| `scenes/main.tscn` + `scripts/main.gd` | Composition root: `World` (streamed levels) / `UI` (persistent HUD) split, run-flow orchestration |
| `scripts/autoload/floor_streamer.gd` | Threaded background level streaming + single-resident-level scene swapping |
| `scripts/levels/game_level.gd` | Base class for streamable levels (spawn-point contract) |
| `scenes/levels/lobby.tscn` + `lobby.gd` | Hub: cardboard-box spawns, shop truck, Meat Grinder, docked limo |
| `scenes/levels/limo.tscn` + `limo.gd` | Transition capsule: boarding tracking, load kickoff, departure signal |
| `scenes/levels/floors/casino_floor_base.tscn` + `casino_floor.gd` | Modular linear floor kit (4 sections, occluder dividers) |
| `floor_01..04.tscn` | Inherited scenes overriding `floor_number` / `quota_target` / `min_bet` |

### Scene structural trees

```
Main (Node)                                  — main.gd
├── World (Node3D)          ← FloorStreamer swaps exactly one level here
└── UI (CanvasLayer)
    └── HUD (hud.tscn)      ← persists across every swap

Lobby (Node3D : GameLevel)                   — lobby.gd
├── WorldEnvironment / Sun (DirectionalLight3D)
├── Ground (StaticBody3D → CollisionShape3D + MeshInstance3D)
├── SpawnCrates (Node3D)     — Crate01..06 + Spawn01..06 (Marker3D, "player_spawn")
├── ShopTruck (Node3D)       — Body + ShopTrigger (Area3D)
├── MeatGrinder (Node3D)     — Body + Hopper (Marker3D) + DepositTrigger (Area3D)
└── LimoDock → Limo (limo.tscn instance)

Limo (Node3D)                                — limo.gd
├── Body (MeshInstance3D)
├── Cabin
│   ├── CabinTrigger (Area3D)   — boarding detection
│   └── Seats — Seat01..06 (Marker3D)
└── DriverPrompt (Area3D)       — manual-departure interact (later phase)

CasinoFloor (Node3D : GameLevel)             — casino_floor.gd, base for floors 1–4
├── WorldEnvironment / Ground (StaticBody3D)
├── Sections (linear along -Z, one section ≈ 26 m)
│   ├── Section01Arrival  — ArrivalDock + Spawn01..06 ("player_spawn")
│   ├── Section02Tables   — TableAnchors (4× Marker3D)
│   ├── Section03Pit      — TableAnchors (3× Marker3D)
│   └── Section04Exit     — ExitTrigger (Area3D, the exit elevator)
└── Occluders — Divider01..03 (MeshInstance3D + OccluderInstance3D/BoxOccluder3D)
```

Floors 1–4 are **inherited scenes** of the base — same kit, different exports:
Floor 1 "Street Slots" ($5 min / $5k quota) → Floor 2 "Card Room" ($25/$15k)
→ Floor 3 "High-Roller Pit" ($100/$40k) → Floor 4 "The Vault" ($500/$100k).

### Background streaming & the limo transition

`FloorStreamer` wraps `ResourceLoader.load_threaded_request()` (with
`use_sub_threads=true` so meshes/textures parse in parallel) and polls
`load_threaded_get_status()` once per frame, emitting `load_progress` /
`load_ready` / `load_failed`. The flow:

1. **First player steps into the limo cabin** → `Limo` calls
   `FloorStreamer.request_load(destination)`. The whole boarding window
   masks the load.
2. **Doors close** (`auto_depart_when_full` or `request_departure()`) →
   `departed` fires → `Main` **starts the 5-minute HUD timer** — the clock
   locks in at departure, not arrival.
3. `Main` awaits `wait_until_ready()`, enforces a minimum ride beat
   (4 s) so instant loads still feel like a ride, then calls `swap_now()`.
4. `swap_now()` **frees the lobby before instancing the floor** — exactly
   one level is ever resident — and `level_swapped` drops every node in the
   `players` group onto the floor's arrival spawns. The exit elevator's
   trigger streams the lobby back the same way.

### Linear layouts & aggressive occlusion culling

- Floors are **sausages, not open halls**: four ~26 m sections in a straight
  line along −Z. From any point the player can see at most the current
  section and one doorway — never the whole floor.
- Dividers between sections alternate left/right (an S-bend chokepoint), so
  the sightline through a doorway is broken by the *next* divider. Each
  divider carries an `OccluderInstance3D` with a `BoxOccluder3D` matching
  its wall; with `occlusion_culling/use_occlusion_culling=true` Godot's
  CPU raster culls everything behind it — table meshes, chip stacks, NPCs
  in sections 2–4 cost nothing while you stand in section 1.
- Occlusion culling is CPU-side (works with the Compatibility renderer on
  Android and web). Occluders are separate low-poly boxes, not the visual
  meshes, so the raster stays cheap.
- Memory floor: one streamed level resident at a time, ETC2/ASTC compressed
  textures, and the modular kit means all four floors share the same
  sub-resources — a floor is layout data, not four unique geometry sets.

## Phase 4 — Environmental Details & Interactions

### What's in this phase

| File | Purpose |
|---|---|
| `scripts/interaction/interactable.gd` | Reusable Area3D interaction target: focus signals, action binding, shared outline highlight |
| `scripts/interaction/interactor.gd` | Camera-mounted RayCast3D probe: focusing, HUD prompt, input routing, hand context |
| `scripts/interaction/carryable.gd` + `player_hand.gd` | Physical carry pipeline: freeze/reparent pickup, drop, aim-directed throw |
| `shaders/interact_outline.gdshader` | One-pass grow/cull_front hover outline (Compatibility-safe) |
| `scripts/autoload/economy.gd` | Shared crew wallets: run cash (quota bank) + shop tickets |
| `scripts/shop/shop_item.gd`, `shop_bin.gd`, `shop_truck.gd` + `scenes/items/shop_crate.tscn` | The physical truck shopping loop |
| `scripts/levels/meat_grinder.gd` | The Lobby Body Shredder |

### The interaction pipeline

`Interactor` (a RayCast3D under the player camera, areas-only) focuses
whatever `Interactable` the crosshair rests on. Focus applies a **single
shared ShaderMaterial** as `material_overlay` to every mesh under the
target's `highlight_root` — the shader grows vertices along normals with
front-face culling, giving a shell outline in one pass with no viewports or
post-processing. Focus also drives the Phase 1 HUD prompt through the `hud`
group, with the key label resolved through Phase 2's rebind-aware
`get_action_key_label()`.

Each `Interactable` declares which InputMap `action` triggers it
(`interact`/LMB for buttons and panels, `action_pickup`/E for grabs), and
`interact()` passes the Interactor as context — targets reach the player
via `interactor.player` and their carry slot via `interactor.hand`.
`Carryable` (RigidBody3D) + `PlayerHand` complete the pipeline: pickup
freezes physics, mutes collision, and reparents into the hand; E drops
gently, LMB throws along the camera aim with a mass-scaled impulse. Since
everything runs on InputMap actions, the Phase 2 touch overlay drives all
of it with zero extra code.

### The truck shopping system

Fully physical, no menus: grab a `ShopItem` off the shelf anchors, throw it
into the **Bin** (an Area3D continuously tracking which ShopItems rest
inside), then press the physical **Buy button** (an `Interactable`).
Checkout prices the bin at that instant, calls
`Economy.try_spend_tickets()` (atomic check-and-deduct), and on success
marks the items `purchased` and respawns them fanned out of the
**Retrieval Drawer** — from where the crew must carry them to the limo by
hand. Insufficient tickets emits `purchase_failed` and changes nothing.

**Penalty rule:** when the limo departs, anything still in the truck's
custody is lost. Unpurchased stock was never charged and just despawns;
*purchased* items left in the bin or drawer are **forfeited — the tickets
stay spent** (an optional `forfeit_refund_ratio` export can grant a partial
salvage refund; default 0 = full loss). Items in someone's hand are exempt:
they're leaving with the player. Buy it, carry it, or lose it.

### The Meat Grinder

Stepping (or being thrown) into the hopper's `EntryTrigger` starts the
grind: the avatar is pinned at the hopper and its processing disabled, the
machine chews for `grind_duration`, then `Economy.deposit_cash(cash_per_body)`
pays the shared bank, `cash_extracted` fires, and the physical avatar is
freed from the tree — gone for the run. Respawn/spectator policy is
deliberately left to the host logic of a later phase via the
`victim_destroyed` signal. Carryables tossed in are destroyed for nothing:
the machine only pays for meat.

### Running it

Open in **Godot 4.3+**, press Play — `main.tscn` boots into the lobby with
the HUD idle at 5:00. `InputSetup` registers all actions, `SettingsManager`
overlays saved rebinds and applies mouse/accessibility/touch settings, and
`FloorStreamer` waits for the first limo boarding to start streaming. (No
player controller exists yet — add any `CharacterBody3D` to the `players`
group and the spawn/limo/exit flow picks it up.)
