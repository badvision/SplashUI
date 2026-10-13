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

Click the menu-bar icon to show/hide the panel. `./stop.sh` tears everything down.

## Using the API

```sh
curl http://127.0.0.1:8123/v1/chat/completions \
  -H "x-api-key: splash-standalone-1" -H "Content-Type: application/json" \
  -d '{"model":"mlx-community/Qwen3.8-27B-4bit","stream":true,"messages":[{"role":"user","content":"hi"}]}'
```

Point any OpenAI-compatible client at `http://127.0.0.1:8123/v1` with the key above.

## Configuration (environment)

`start.sh` passes these to the UI; all have defaults. The same variables apply when launching `build/SplashUI.app` directly from Finder (e.g. via the shell or a wrapper). The UI finds the engine by **discovery**, in order: `SPLASH_KIT_DIR` → `SPLASHUI_HOME/kit/splash-$SPLASH_VERSION-arm64-macos26` → a Homebrew install (`brew install incoai/tap/splash`) as the last-resort fallback; `SPLASHUI_HOME` defaults to `~/SplashUI` (the `./install.sh` default). A **model dir** is found the same way — `SPLASH_MODEL_ROOT` → `SPLASHUI_HOME/models/<id>` → `~/.lmstudio/models/<id>`. A 1.3.0-style engine loads that dir positionally (reusing an installed model, never re-downloading); the 1.3.1+ engine (the Homebrew keg) loads by Hugging Face id and *cannot read* the 1.3.0 package format, so **when a local model dir is present the Homebrew fallback is skipped** — picking it would ignore the model and re-download it — and if no 1.3.0-style engine is found the app reports exactly that. When nothing resolves, the menu bar stays up and shows the missing paths (with every location it tried) instead of quitting; a failed launch retries every 30 s (10 attempts), so an install fixed while the app is running takes effect on the next attempt.

| Variable               | Default                                        | Meaning                          |
|------------------------|------------------------------------------------|----------------------------------|
| `SPLASH_PORT`          | `8123`                                         | engine listen port               |
| `SPLASH_KEY`           | `splash-standalone-1`                          | API key (loopback-only service)  |
| `SPLASH_MODEL_ROOT`    | *(none — UI assumes no location)*<sup>†</sup>  | model dir                      |
| `SPLASH_MAX_CACHE_DISK`| `100g`                                         | SSD prefix-cache cap             |
| `SPLASH_IDLE_RELEASE`  | `240m`                                         | unload an idle model after this  |
| `SPLASH_ANE`           | `on`                                           | GPU + Neural-Engine prefill split (`off` = GPU-only) |
| `SPLASH_VERSION`       | `1.3.0`                                        | engine release pin               |
| `SPLASHUI_HOME`        | `~/SplashUI`<sup>†</sup>                       | install root (kit + models)    |
| `SPLASH_KIT_DIR`       | *(none)* — derived from `SPLASHUI_HOME` when set | point at an existing Splash engine install |

<sup>†</sup> The UI's default install root is `~/SplashUI`, matching `./install.sh` and `start.sh`; it errors actionably when nothing is found.

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
    Consequently, when a local model dir is present the app does not fall back to the Homebrew
    keg (it would re-download the model); it asks for a 1.3.0-style engine instead.
- The app polls `/status` (1 s) and `/metrics` (1 s) and renders the panel in a
  WKWebView. The decode readout is the *committed* output rate: counter delta divided by
  the real elapsed time between samples. DFlash-2 draft tokens that fail verification do
  not count, so it matches the per-request tok/s in the completion log.
- In-flight work comes from live scheduler/frontend counters even when the engine emits
  no `Request` log line. Without a known prompt size, Prefill shows cumulative work
  since prefill started (`N tok · R tok/s`), not a fabricated percentage; until the
  metrics baseline arrives, the count is unknown (`…`). When a real
  request log supplies the input size, the existing uncached-tail percentage remains
  available. The last prefill sample is held for up to 15 s after prefill ends.
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
