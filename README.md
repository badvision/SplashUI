# SplashUI

A menu-bar UI + lifecycle manager for running [Splash](https://github.com/incoai/splash) —
Inco AI's local inference engine for Apple silicon — as a **standalone service**.

<img width="515" height="895" alt="image" src="https://github.com/user-attachments/assets/f2f76cd3-1932-48d4-8634-c612b21463df" />

You get:

- An OpenAI-compatible API on `127.0.0.1:8123` serving Qwen3.8-27B (Splash-tuned, with
  DFlash-2 speculative decoding)
- A menu-bar app (SplashUI) that owns the engine's lifecycle and shows a live telemetry
  panel: decode rate, TTFT, ITL, KV cache, ANE split, SSD prefix cache, system memory/swap, and a
  per-request log — every counter has hover help
- LCARS-style console: elbow framing, numbered rails in the classic LCARS palette
  (orange, lilac, ice blue, honey), condensed readouts, and segmented meters — local
  macOS fonts only, no web font downloads

## Requirements

- Apple silicon (arm64), macOS 14 or newer
- ~16 GB of disk for the model (installed to `~/SplashUI/models`)
- 32 GB+ unified memory recommended (the engine holds weights + KV in RAM)
- Xcode Command Line Tools (`xcode-select --install`) for building the UI

The engine itself and the model are fetched by `install.sh` — this repo contains only
the UI + lifecycle scripts.

## Quick start

```sh
./install.sh   # engine release (pinned, sha256-verified) + model; idempotent
./build.sh     # builds build/SplashUI.app
./start.sh     # starts the engine server, then the menu-bar UI (adopts it)
```

Click the menu-bar icon to show/hide live status. Right-click it for **Open Status**,
**Settings…**, or **Quit SplashUI**. The status screen's upper-right hamburger also
opens the separate Settings screen; its **STATUS** cap returns to telemetry.
Settings scrolls internally, with the shared restart control always reachable.
`./stop.sh` tears everything down.

## Using the API

```sh
curl http://127.0.0.1:8123/v1/chat/completions \
  -H "x-api-key: splash-standalone-1" -H "Content-Type: application/json" \
  -d '{"model":"mlx-community/Qwen3.8-27B-4bit","stream":true,"messages":[{"role":"user","content":"hi"}]}'
```

Point any OpenAI-compatible client at `http://127.0.0.1:8123/v1` with the key above.

## Configuration

The menu-bar app (`build/SplashUI.app`) reads all engine/model/profile configuration from
**`config.json`** — its in-app Settings surface (panel section 06) owns the values. The file
lives at `~/Library/Application Support/SplashUI/config.json` (created with documented defaults
on first run) and is the single source of truth. The app reads no environment variables — the
pre-panel `SPLASH_*` env vars are deprecated and no longer have any effect on the app.

Profiles expose the resolved runtime's startup options in GENERAL / MODEL / MEMORY / API
tabs. GENERAL holds profile identity, compute settings and launch preview; MEMORY also
contains cache settings. Unsupported flags stay hidden without deleting saved values.
Every change auto-saves after debounced validation; unsupported combinations remain
saveable with warnings. Settings expands to 820px while status stays 520px, using one
shared header and one-row footer. Existing common model folders are discovered automatically;
nonexistent folders are omitted, and manual additions must point to real directories.
ACTIVATE PROFILE atomically commits the whole draft and stamps that profile's last-used
time. It does **not** restart the engine: a restart-required prompt shows the current
in-flight request count, and **CONFIRM RESTART** explicitly applies the changed plan.
The shared **RESTART** footer button flashes while changes await restart and opens this prompt. Reverting to the running plan
clears it without restarting. Port and the masked API key remain global-only.

`./install.sh` still reads a couple of its own vars for the one-shot install (it predates the
panel and is unaffected). `start.sh` no longer exports any of them — it launches its own engine
directly from a fixed argv (see "How it works"); the menu-bar app ignores env and reads
`config.json`.

The environment variables formerly documented here are retired. Each one maps to a
`config.json` setting (edit these in the panel's Settings section, or in the file directly):

| Retired env var        | config.json replacement                                                                 |
|------------------------|-----------------------------------------------------------------------------------------|
| `SPLASH_KIT_DIR`       | `globals.engine.manual_path` (with `globals.engine.mode: "manual"`)                     |
| `SPLASHUI_HOME`        | retired — AUTO discovers installed Homebrew versions, not an assumed SplashUI kit      |
| `SPLASH_VERSION`       | not user-facing — version read from the installed kit's `release.json`                  |
| `SPLASH_PORT`          | `globals.port`                                                                          |
| `SPLASH_KEY`           | `globals.api_key`                                                                       |
| `SPLASH_MODEL_ROOT`    | `globals.model_folders` plus the active profile's `model` choice (`profiles[].model`)   |
| `SPLASH_MAX_CACHE_DISK`| profile option `max_cache_disk`                                                         |
| `SPLASH_IDLE_RELEASE`  | profile option `idle_release`                                                           |
| `SPLASH_ANE`           | profile option `ane` (default on)                                                       |

## How it works

- `start.sh` is a **full reset**: it stops any UI + server on the port, starts a fresh
  server (timestamped log, `/tmp/splashui.log` symlink), waits for `ready`, then launches
  the app, which **adopts** the running server (the panel marks it "external").
- The engine is an "engine kit" — a directory holding `engine/splash`, a bundled
  `python`, and the `server` package. Both the release tarball's kit dir and a Homebrew
  keg's `libexec/` are exactly that. The launch contract is keyed to the kit's on-disk
  `release.json` version:
  - **1.3.0-style** (tarball install): runs the bundled python in module form
    (`-m server.server <model-dir> --tokenizer <model-dir> --binary ./engine/splash`)
    and passes the **on-disk model dir positionally**, so an already-installed model is
    reused — never re-downloaded. A model dir is required; without one the UI names the
    locations it tried.
  - **1.3.1+** (the Homebrew keg): runs the kit's own `install/launcher.py serve --model
    mlx-community/Qwen3.8-27B-4bit` (the same thing the brew formula's `splash` shim does
    under the hood). It loads the model **by id** — a one-time download it manages itself.
    It refuses the 1.3.0 Splash-package id (`incoai/Qwen3.8-27B-Splash`) outright — "Splash
    no longer loads" that prebuilt format — so a 1.3.0 model dir is not usable by it either.
  AUTO selects the highest valid installed Homebrew Splash version (numeric ordering,
  Apple-silicon and Intel prefixes); the old SplashUI-local kit is not an automatic default.
  MANUAL uses exactly the chosen path. Model/runtime incompatibilities remain visible
  eligibility errors rather than silently selecting another engine. VALID has no build-version note.
- The app polls `/status` (1 s) and `/metrics` (1 s) and renders the panel in a
  WKWebView. The decode readout is the *committed* output rate: counter delta divided by
  the real elapsed time between samples. DFlash-2 draft tokens that fail verification do
  not count, so it matches the per-request tok/s in the completion log.
  no `Request` log line. Prefill shows a percentage of the request's uncached tail plus a
  completion ETA (`~12 s`) autoregressed from the prefill rate — the live per-prefill
  sample, falling back to the 15 s latch, then the engine's session prefill rate — so it
  climbs from the start even on a warm idle engine; tok/s stays a separate live readout.
  The tray/pill read `NN%` once a percentage is available. The last prefill sample is
  held for up to 15 s after prefill ends.
- Recent request rows prefer an explicit log id; otherwise a single app-side sequence,
  seeded once from the engine's terminal counters, numbers both Done and Cancelled rows.
  These display ids are unique across terminal kinds and do not depend on status/log
  timing. Engine footprint is OS process RSS (`ps`, KiB converted to bytes), distinct
  from Eng mem, which is the engine's own memory accounting.
- The engine port is the ground truth: the app only *launches* a server when the port is
  not actually serving, and only treats it as *gone* when the port stops answering.
- No launchd persistence: quit the app and supervision goes with it (the server keeps
  serving). `start.sh` is the canonical way back.

## Upgrading the engine

Change `SPLASH_VERSION` and re-run `install.sh`. The UI reads the installed kit's
`release.json` version and switches to that release's launch contract automatically:
1.3.0-style runs `python -m server.server <MODEL_DIR> --model <OWNER/REPO> --tokenizer <MODEL_DIR>/tokenizer` (the model dir is
passed positionally and reused — no download); 1.3.1+ (the Homebrew keg) runs the kit's
`install/launcher.py serve --model <id>`. 1.3.0 splits
dense-model prefill across GPU and Neural Engine by default (`SPLASH_ANE` controls it)
and speaks native protocol 8, so the server must restart on upgrade. Verify the CLI of
any newer release before pointing `start.sh` at it.

## License

MIT (this UI + scripts). The Splash engine is Apache-2.0 ([incoai/splash](https://github.com/incoai/splash));
the model is Inco AI's, distributed on Hugging Face under its own license.
