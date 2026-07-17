# Build, Integration & Release Guide (Phase 9)

Zero-fluff workflow for binding the systems together and shipping
release packages. Companion to [PLATFORM_SPECS.md](PLATFORM_SPECS.md).

---

## 1. Architecture glue: autoloads & boot

### Autoload order (project.godot `[autoload]`, top = first loaded)

| # | Singleton | Responsibility | Why this position |
|---|---|---|---|
| 1 | `InputSetup` | Registers the InputMap, owns pointer lock | Actions must exist before anything reads them |
| 2 | `SettingsManager` | ConfigFile persistence, rebinds, accessibility | Overlays saved rebinds onto InputSetup defaults |
| 3 | `FloorStreamer` | Threaded level streaming, single-resident swap | No upward dependencies |
| 4 | `Economy` | Host-authoritative wallets (RPC even offline) | Consumed by everything below |
| 5 | `NetSession` | WebRTC/ENet transport lifecycle | Pushes late-join sync INTO Economy/TableRng |
| 6 | `TableRng` | Shared deterministic RNG + Time Machine buffer | Snapshots Economy state |
| 7 | `BetLedger` | Replicated bet stream, streaks, restoration | Reads results, heals BodyStates |
| 8 | `GameManager` | Device profile + coarse game state | Coordinator loads LAST — everyone exists first |

Rules that keep the graph sane: **autoloads never call *down* into scene
nodes** (they emit signals; scenes subscribe), and scene code never
assumes an autoload's `_ready()` order beyond this table.

### Boot flow (`scenes/boot/boot_splash.tscn` = main scene)

```
BootSplash._ready()
├─ GameManager.detect_device_profile()   # cores + physical RAM heuristic
│    └─ LOW_END_MOBILE → CasinoFloor skips neon halos (overdraw)
├─ load_threaded_request(main.tscn, lobby.tscn)   # precache on workers
BootSplash._process()                    # progress bar = mean progress
└─ all LOADED (≥0.6 s) → change_scene_to_file(main.tscn)
     └─ Main._ready() → FloorStreamer.swap_now(LOBBY)  # cache HIT — no stall
```

The splash absorbs the two worst first-frame costs — scene parse and
(on WebGL2) shader compilation — before the player can see a hitch.

---

## 2. Local Android APK compilation, step by step

### 2.1 One-time setup

1. **Godot 4.3+** (standard build) and **JDK 17** (`keytool`, `apksigner`
   need it): `sdk install java 17` or your distro's `openjdk-17-jdk`.
2. **Android SDK** — only these packages (no Android Studio needed):
   ```bash
   sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34" "cmdline-tools;latest"
   ```
3. **Export templates**: Editor → *Manage Export Templates* → Download
   (or `godot --headless --install-android-build-template` is NOT needed
   for non-Gradle exports — skip Gradle entirely, see 2.3).
4. **Editor paths**: Editor Settings → *Export → Android*:
   - `Android SDK Path` → your SDK root
   - `Debug Keystore` → generate one:
     ```bash
     keytool -genkeypair -v -keystore ~/debug.keystore -alias androiddebugkey \
       -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
       -dname "CN=Android Debug,O=Android,C=US"
     ```
5. **Release keystore** (guard this file; losing it = losing app identity):
   ```bash
   keytool -genkeypair -v -keystore release.keystore -alias gamblewf \
     -keyalg RSA -keysize 4096 -validity 9125
   ```

### 2.2 Export preset (committed in `export_presets.cfg`)

Low-end-focused settings, already configured:

| Setting | Value | Why |
|---|---|---|
| Architectures | **arm64-v8a only** | armeabi-v7a/x86 off ≈ −40% APK size; arm64 covers every Android 7+ phone that can run the game |
| Min SDK | 24 (Android 7.0) | Oldest GLES3 drivers worth supporting |
| Target SDK | 34 | Play Store requirement |
| Gradle build | **off** | Prebuilt template APK: faster, smaller, reproducible |
| Immersive mode | on | Fullscreen incl. cutout area (HUD handles insets) |
| `permissions/internet` | on | WebRTC needs it; nothing else granted |
| Renderer | forced by `project.godot`: `gl_compatibility` on all platforms | One rendering path everywhere |

### 2.3 Compile the release APK

```bash
# keys via env — never in files:
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/keys/release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=gamblewf
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='...'

godot --headless --path . --export-release "Android" build/android/GambleWithFriends.apk
```

`--export-release` is the size/perf switch: it strips the debug runtime,
disables the remote debugger/profiler hooks, excludes debug symbols from
the native libs, and exports scripts as **binary tokens** (GDScript is
compiled to its tokenized form, smaller and faster to load — the default
`editor/export/convert_text_resources_to_binary` also converts all .tscn/
.tres to binary). Verify no debug flags survived:

```bash
# a release APK must NOT be debuggable:
aapt2 dump badging build/android/GambleWithFriends.apk | grep -i debuggable && echo "FAIL" || echo "OK"
```

Signing (zipalign + apksigner) happens inside the export automatically.

---

## 3. Local Web compilation & server headers

### 3.1 Export

```bash
godot --headless --path . --export-release "Web" build/web/index.html
python3 -m http.server -d build/web 8060    # local test (threads-off build)
```

### 3.2 COOP/COEP — the crucial hosting decision

Threaded WASM needs `SharedArrayBuffer`, which browsers only enable on
**cross-origin isolated** pages. Two valid configurations:

**A. Threads OFF (our committed default — `variant/thread_support=false`)**
Runs on any static host with zero special headers, including GitHub
Pages. WebRTC itself does NOT need COOP/COEP — P2P works fine here.
Cost: engine runs single-threaded (audio mixed on the main thread,
streaming shares the core).

**B. Threads ON (smoothest on mobile browsers)** — flip
`variant/thread_support=true` and serve with:

```nginx
# nginx
location / {
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    types { application/wasm wasm; }
    gzip_static on;   # serves the .wasm.gz/.pck.gz sidecars from CI
}
```

```caddyfile
# Caddy
header {
    Cross-Origin-Opener-Policy same-origin
    Cross-Origin-Embedder-Policy require-corp
}
```

Per host:
- **itch.io**: upload the zip, tick *"SharedArrayBuffer support"* on the
  project page — itch sets COOP/COEP for you. Threads-ON builds work.
- **GitHub Pages**: cannot set response headers. Threads-OFF build, or
  ship `web/coi-serviceworker.js` (shim that fakes isolation; test iOS
  Safari before adopting — its first-load reload is visible).
- **Custom VPS**: config above; always HTTPS (pointer lock, wss
  signaling, and getUserMedia-based voice all require a secure context).
- Caveat: COEP `require-corp` forces every cross-origin subresource to
  opt in (CORP headers) — keep signaling on wss (not a fetched
  subresource) and avoid third-party CDN assets (we have none; the CSP
  story stays clean).

---

## 4. Real-device testing & debugging pipeline

### 4.1 Android via ADB

```bash
adb devices                                   # phone visible? (USB debugging on)
adb install -r build/android/GambleWithFriends-debug.apk   # -r = reinstall, keep data
adb shell am start -n com.casinocrawler.gamblewithfriends/com.godot.game.GodotApp

# The three logcat views that matter:
adb logcat -s godot                           # engine prints, push_error, GDScript stack traces
adb logcat --buffer=crash                     # native crash loops (SIGSEGV, GL driver aborts)
adb logcat -s godot -s Adreno -s Mali         # GPU driver whining (shader compile, OOM)

# Performance hiccups:
adb shell dumpsys gfxinfo com.casinocrawler.gamblewithfriends framestats  # frame timing histogram
adb shell dumpsys meminfo com.casinocrawler.gamblewithfriends            # RSS vs our budget

# Thread locks / ANRs ("Application Not Responding"):
adb logcat -s ActivityManager | grep -i anr   # the moment it happens
adb bugreport anr-bundle.zip                  # contains /data/anr traces: which thread held what

adb shell screenrecord /sdcard/run.mp4        # capture a hiccup, pull it, scrub frame by frame
```

Debug-signed builds also accept the **remote debugger**: run the editor,
Debug → *Deploy with Remote Debug*, and breakpoints/profiler work on the
phone over USB.

### 4.2 Mobile browsers (WASM + WebRTC handshake)

- **Android Chrome**: desktop Chrome → `chrome://inspect#devices` (USB) →
  *inspect* the tab. The console shows WASM instantiation errors
  (`RangeError: WebAssembly.Memory` = heap cap hit), COOP/COEP warnings
  ("SharedArrayBuffer is not defined" = headers missing but threads on),
  and mixed-content blocks (`ws://` on an HTTPS page — signaling must be
  `wss://`).
- **WebRTC handshake**: open `chrome://webrtc-internals` on the device
  (or the inspected tab) — live ICE candidate pairs and state
  transitions. `checking → disconnected/failed` with only `host`/`srflx`
  candidates on both sides = symmetric NAT, you need a TURN server.
  No remote candidates at all = signaling never delivered the SDP
  (check the wss connection first).
- **iOS Safari**: Settings → Safari → Advanced → *Web Inspector*, then
  macOS Safari → Develop → *(device)*. Watch for WKWebView memory kills
  (page reloads silently — that's the WASM heap, shrink textures).

---

## 5. Release checklist (copy per release)

```
[ ] git status clean on main; version bumped in export_presets.cfg
    (version/code +1, version/name) and project.godot config/version
[ ] Editor opens with zero script/scene errors; play from boot splash
    to Floor 1 and back (desktop)
[ ] Debug APK on the weakest real phone available:
    [ ] 60 fps in lobby & floor sections (gfxinfo framestats)
    [ ] no ANR through limo transitions (logcat -s ActivityManager)
    [ ] settings persist through force-kill (settings.cfg reload)
[ ] Web build threads-off in Chrome Android + iOS Safari:
    [ ] boots without console errors, pointer lock works on desktop
    [ ] 2-player WebRTC session connects (webrtc-internals: pair connected)
    [ ] Time Machine rollback verified in a live 2-peer bet
[ ] Cross-play: Android native peer + browser peer in one lobby
[ ] tag: git tag vX.Y.Z && git push origin vX.Y.Z
    -> Actions: signed APK on the Release, web deployed to Pages,
       itch.io html5 channel pushed (butler)
[ ] Install the RELEASE APK from the GitHub Release on a phone
    (debug and release signatures differ - uninstall the debug build first)
[ ] Smoke-test the deployed Pages/itch URL from a phone on cellular
    (real NAT, not your dev Wi-Fi)
```
