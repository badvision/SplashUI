# SplashUI

A menu-bar UI + lifecycle manager for running [Splash](https://github.com/incoai/splash) —
Inco AI's local inference engine for Apple silicon — as a **standalone service**, with no
LM Studio required.

You get:

- An OpenAI-compatible API on `127.0.0.1:8123` serving Qwen3.8-27B (Splash-tuned, with
  DFlash-2 speculative decoding)
- A menu-bar app (SplashUI) that owns the engine's lifecycle and shows a live telemetry
  panel: decode rate, TTFT, ITL, KV cache, SSD prefix cache, system memory/swap, and a
  per-request log — every counter has hover help

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
  -d '{"model":"incoai/Qwen3.8-27B-Splash","stream":true,"messages":[{"role":"user","content":"hi"}]}'
```

Point any OpenAI-compatible client at `http://127.0.0.1:8123/v1` with the key above.

## Configuration (environment)

`start.sh` passes these to the UI; all have defaults.

| Variable               | Default                                        | Meaning                          |
|------------------------|------------------------------------------------|----------------------------------|
| `SPLASH_PORT`          | `8123`                                         | engine listen port               |
| `SPLASH_KEY`           | `splash-standalone-1`                          | API key (loopback-only service)  |
| `SPLASH_MODEL_ROOT`    | `~/SplashUI/models/incoai/Qwen3.8-27B-Splash`  | model dir (falls back to the LM Studio copy if present) |
| `SPLASH_MAX_CACHE_DISK`| `100g`                                         | SSD prefix-cache cap             |
| `SPLASH_IDLE_RELEASE`  | `240m`                                         | unload an idle model after this  |
| `SPLASH_VERSION`       | `1.2.1`                                        | engine release pin               |
| `SPLASHUI_HOME`        | `~/SplashUI`                                   | install root (kit + models)      |

## How it works

- `start.sh` is a **full reset**: it stops any UI + server on the port, starts a fresh
  server (timestamped log, `/tmp/splashui.log` symlink), waits for `ready`, then launches
  the app, which **adopts** the running server (the panel marks it "external").
- The app polls `/status` (1 s) and `/metrics` (1 s) and renders the panel in a
  WKWebView. The decode readout is the *committed* output rate: counter delta divided by
  the real elapsed time between samples. DFlash-2 draft tokens that fail verification do
  not count, so it matches the per-request tok/s in the completion log.
- The engine port is the ground truth: the app only *launches* a server when the port is
  not actually serving, and only treats it as *gone* when the port stops answering.
- No launchd persistence: quit the app and supervision goes with it (the server keeps
  serving). `start.sh` is the canonical way back.

## Upgrading the engine

Change `SPLASH_VERSION` and re-run `install.sh`. The pinned 1.2.1 argv
(`--persistent-cache --max-cache-disk --idle-release`, `python -m server.server`) is
known-good; verify the CLI of any newer release before pointing `start.sh` at it.

## License

MIT (this UI + scripts). The Splash engine is Apache-2.0 ([incoai/splash](https://github.com/incoai/splash));
the model is Inco AI's, distributed on Hugging Face under its own license.
