# Platform Architecture, Optimization Guardrails & Hardware Specs

Phase 7 reference for shipping "Gamble with Friends" at 60 fps on cheap
Android phones and standard web browsers, without breaking the Phase 6
deterministic simulation.

---

## 1. Native Android vs. WebAssembly (HTML5/WebGL2)

Both exports run the same GDScript and the same Compatibility (GLES3)
renderer — the difference is everything *around* the engine.

| Layer | Native Android (arm64-v8a) | Web (WASM + WebGL2) |
|---|---|---|
| Code execution | Engine is AOT-compiled C++ running directly on the CPU | Engine compiled to wasm32 via Emscripten, executed by the browser's JIT inside a sandbox |
| Threading | Full OS threads: rendering, physics, resource loading, and `use_sub_threads` streaming all run on real cores | Threads need SharedArrayBuffer, which requires cross-origin isolation (COOP/COEP headers). Default Godot web export is **single-threaded** — streaming still works but shares the main thread |
| Graphics | GLES3 calls go straight to the vendor driver via EGL — one thin layer above the GPU | Every GL call crosses the JS/WASM boundary into WebGL2, is validated, then usually translated by ANGLE (→ D3D11 on Windows, Metal on macOS, Vulkan/GLES on Linux/Android). Two extra layers of overhead and validation per call — this is why the **< 80 draw call budget** matters double on web |
| Audio | Direct low-latency callback into AAudio/OpenSL ES (~10–20 ms) | WebAudio worklet with browser-controlled buffering (~40–100 ms), resampling, and an autoplay policy that requires a user gesture before sound starts |
| Memory | OS-managed, memory-mapped resources, ~1 GB+ usable | wasm32 linear heap (2–4 GB hard cap), no memory mapping; everything loads through the virtual FS. IndexedDB persistence is asynchronous |
| Filesystem | Direct file I/O | Virtual FS in memory + IndexedDB sync for `user://` |
| Frame pacing | Choreographer-driven vsync, predictable | `requestAnimationFrame` — tab throttling, browser compositor jitter |

**Why the native app runs smoother, concretely:** real multithreading (the
GL command stream and resource decoding don't fight the game loop for one
core), one driver layer instead of three, low-latency audio callbacks, and
AOT machine code with no JIT warm-up or GC pauses from the JS glue layer.
The web build is the *constraint-setter*: if it holds 60 fps in Chrome on a
mid-range phone, the native build has headroom to spare.

## 2. Network transport & fallback

Implemented in `scripts/autoload/net_session.gd`:

| Situation | Transport | Why |
|---|---|---|
| Any lobby containing a browser peer | **WebRTC mesh** (SCTP data channels) | The only UDP-like transport a browser can use. Cross-play baseline |
| Signaling for WebRTC | **Secure WebSockets (wss://)** | HTTPS pages may not open `ws://` (mixed content); wss also satisfies iOS Safari |
| Native-only lobby / LAN | **ENet (UDP)** fallback | Lower latency, no signaling server needed on LAN; browsers can't do it, natives shouldn't suffer without it |
| UDP-hostile networks (hotel/corporate Wi-Fi) | **WebSocketMultiplayerPeer** (TCP) last resort | Reliable-only; accept head-of-line blocking rather than no game |

All transports present the same `MultiplayerPeer` interface upward: host =
peer 1 = authority, and every Phase 6 RPC (Economy, TableRng, BetLedger)
works unchanged on all of them. `NetSession.preferred_transport()` encodes
the policy.

## 3. Heavy optimization guardrails

### Applied settings (project.godot / import)

- **Textures**: `import_etc2_astc=true` — ASTC on modern Android/ETC2
  everywhere else; VRAM-compressed textures stay compressed on the GPU.
  Author at 1024² max for props, 2048² only for atlases. Mipmaps on
  (they're a *speedup*: better cache locality at distance).
- **Shadows**: positional shadow atlas size 0, directional shadow 512 and
  unused — the art direction (Phase 5) fakes all shading, so the entire
  shadow pipeline is off.
- **Filtering/AA**: anisotropic 0, MSAA off, no screen-space AA — the
  flat-color look doesn't shimmer, so AA buys nothing.
- **Culling stack** (three layers, `casino_floor.gd`):
  1. S-bend occluders kill everything behind dividers (CPU raster).
  2. `visibility_range_end` ≈ 62 m fades any mesh two sections away even
     along an open sightline.
  3. `SectionActivator` volumes disable *cosmetic* processing and put
     decorative RigidBodies to sleep in sections with no players.
- **Physics**: static tables are `StaticBody3D`/`Area3D` (no per-tick
  cost); only thrown `Carryable`s simulate, and they sleep automatically
  at rest. Tick rate stays at the default 60 Hz (see guardrails).

### THE BOUNDARY — where optimization must STOP

These five rules are load-bearing. Break any of them and the Phase 6
deterministic sim desyncs in ways that are miserable to debug:

1. **Never scale the physics tick rate per device.**
   `physics/common/physics_ticks_per_second` stays 60 on every platform.
   Trigger-enter ordering (bins, hoppers, the limo cabin) must resolve in
   the same order for every peer; a 30 Hz "low-end mode" changes which
   frame a body enters an Area3D and therefore what the host validates.
2. **Never disable gameplay triggers.** `SectionActivator` may only touch
   its exported `cosmetics_root`. Bins, hoppers, exit elevators, cabin
   triggers, and Interactables stay monitoring at all times — a sleeping
   exit trigger is a softlock; a sleeping bin changes a purchase.
3. **Never draw from TableRng for cosmetics.** Particle jitter, card
   shuffle *visuals*, duck waddle animation — all of it uses a separate,
   local, unseeded RNG. One stray `TableRng.rng.randf()` on one peer
   shifts the shared state integer and silently corrupts every future
   bet on every machine.
4. **Never skip or reorder the bet pipeline.** Checkpoint → draw → settle
   → replicate, host-side, one bet at a time. No batching bets to "save
   RPCs", no resolving locally to "hide latency" — the Time Machine's
   undo buffer and the absolute-value wallet echoes both assume this
   exact sequence.
5. **Money stays integer; logic stays event-driven.** No float
   accumulation in balances (that's why the Street Craps "float bug" is
   actually a timing window), and no gameplay decisions derived from
   render-frame `delta` — a 45 fps phone and a 144 Hz desktop must agree
   on every outcome. Culling may hide meshes, but never `queue_free` a
   gameplay node or unload the active floor's logic.

Everything visual is fair game: fade it, sleep it, merge it, compress it.
Nothing that feeds the simulation is.

## 4. Hardware specifications

### Web / HTML5 (WebGL2)

| Component | Minimum | Recommended |
|---|---|---|
| CPU | Quad-core 1.6 GHz (2015+, x86-64 or ARM64) | Quad-core 2.4 GHz+ (2019+) |
| RAM | 4 GB system (≥ 512 MB free for the tab) | 8 GB system |
| GPU | Any WebGL2-capable: Intel HD 4000 / Adreno 505 / Mali-T760 | GTX 750 / RX 550 / Adreno 630 / Apple M1 |
| Browser | Chrome 90+ / Edge 90+ / Firefox 88+ / Safari 15.4+ | Current Chromium-based browser |
| OS | Windows 10, macOS 10.15, Ubuntu 20.04, Android 9, iOS 15.4 | Windows 11 / macOS 13+ |
| Network | 1 Mbps, WebRTC (UDP) not blocked; wss reachable | 5 Mbps, < 80 ms to peers |

### Native Android app

| Component | Minimum | Recommended |
|---|---|---|
| CPU | arm64-v8a octa-core 1.8 GHz (Snapdragon 450 / Helio P22 class) | Snapdragon 720G / Dimensity 700 class or better |
| RAM | 2 GB | 4 GB+ |
| GPU | OpenGL ES 3.0: Adreno 506 / Mali-G51 / PowerVR GE8320 | Adreno 618 / Mali-G76 or better |
| OS | Android 7.0 (API 24) | Android 12+ |
| Storage | 300 MB free | 500 MB free |
| Network | 1 Mbps; Wi-Fi or 4G | Wi-Fi / 5G, < 80 ms to peers |

Target: **60 fps sustained on the recommended tier, 60 fps typical /
never below 30 fps on the minimum tier**, with the web build treated as
the binding constraint.
