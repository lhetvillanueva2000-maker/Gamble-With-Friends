# web/ — Web-specific wrappers

Files here are layered on top of (or referenced by) the HTML5 export, not
imported by Godot:

- **Custom HTML shell** (`shell.html`, optional): set it in the Web export
  preset (`html/custom_html_shell`) to control the loading screen, canvas
  styling for itch.io embeds, and mobile-browser viewport meta tags.
- **`coi-serviceworker.js`** (optional): drop-in shim that fakes COOP/COEP
  cross-origin isolation on hosts that can't set headers (GitHub Pages),
  enabling `variant/thread_support=true` builds. Only adopt it after
  testing on iOS Safari — the shim's first-load reload can be disruptive.
- **Deploy styling**: itch.io page CSS snippets, PWA icons if
  `progressive_web_app` is ever enabled.

The default pipeline (see `.github/workflows/web-deploy.yml`) uses Godot's
stock shell with threads disabled, which runs on every host with zero
special headers.
