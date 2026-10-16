# AGENTS.md — SplashUI decision memory

Read this first. Durable decisions, conventions, and SMART goals for agent sessions.

## Project

SplashUI is a macOS app (Swift/AppKit + a single `WKWebView`, LCARS/TNG themed) that
controls the Splash 1.3.0 standalone LLM engine: it launches or adopts the engine
(`python …/server/server` or `install/launcher.py serve`), polls a 1s tick, and renders
it in a borderless 520px panel. Key surfaces: status screen (telemetry, channels 01–05,
tray pill, prefill/ETA display) and the Settings screen (channel 06: global engine/port/key
settings, model folders, profiles). `~/Library/Application Support/SplashUI/config.json`
(0600, atomic, schema-versioned) is the **single source of configuration** — the 9 legacy
`SPLASH_*` env vars are retired. Architecture: pure logic in `Sources/ui_logic.swift`
(injected FS closures, testable without AppKit), AppKit/WebKit I/O shell in
`Sources/main.swift`, all UI in `Resources/panel.html`. No new processes, ports, or
dependencies (swiftc + WebKit + Foundation only).

## Durable decisions (binding)

- **Never auto-restart** (D5): config changes take effect only on restart; the app
  **prompts** (with in-flight request count) and the user explicitly confirms. Saving or
  activating a profile never restarts the engine.
- **No `SPLASH_*` env override** (D9): the app reads none of the 9 documented env vars —
  no precedence, no env-override indicator. `config.json` only. (The engine *child* still
  receives `SPLASH_API_KEY` as its own env — internal plumbing, not env-var support.)
  `planLaunch` and its pipeline take **no env parameter** and read no environment.
- **Engine version = what the panel package was built against (1.3.0), never a newer
  system version** (e.g. a 1.3.1 Homebrew keg). Auto discovery is *order*, never version
  preference; newer engines are surfaced as a blocked/unrunnable verdict, not promoted.
- **Engine version detected from the kit's `release.json`, never user-set** (D16).
- **`restart_required` is computed, never stored** (D13): compare the current plan
  signature (kit + version + argv + key) against the last successful plan. The baseline
  must be stamped on **BOTH** launch and adopt paths (`ServerProc.launch` and
  `ServerProc.adopt`) — an adopted engine must get a baseline too, or `restart_required`
  stays null. Self-clears after a successful restart or reverted edit.
- **ANE default ON is non-negotiable** — all compute cores are required; never disable it
  in defaults, seeds, or tests.
- **Frozen status-display rules** (do not touch without explicit direction):
  - Prefill = `PRE xx%` in the **system tray** (top of status display + notification bar);
    it tracks real prefill progress — never 100% before prefill completes. tok/t/s is a
    generation-phase metric; never show it for prefill.
  - ETA lives in the **notification badge** at the top of the screen — duplicate it there,
    never relocate it. It carries a **drop shadow** for readability; keep it when restyling.
  - ANE status: active = colored percentage only (green = on, red = not), inactive =
    `OFF`. **Never a textual "ON" label** — the color/percentage encodes the state.
- **Port and API key are global-only** (D6), shared by all profiles. The API key is never
  rendered (masked in UI; on-disk file is 0600).
- **Profile activation commits unsaved draft edits first** (D14): one validated atomic
  save, then active-id change + `last_used_at` stamp. Profile metadata flushes on the next
  explicit save only — no background or per-tick writes of the 0600 file (D15).
- **Unrunnable model/runtime combos**: save allowed (peach `UNRUNNABLE — <reason>` cap with
  the actionable fix), start refused pre-flight (D4). Unknown engine version →
  latest-authored mapping with a visible `FALLBACK MAPPING` indicator (D3); the kit's
  `serve_options.py` parse is validation assist only, **never emits argv**.
- **LCARS theme discipline**: shipped "vivid classic" palette is canonical; ≤3–4 colors
  each with assigned meaning (blue = structure/nav, lavender = primary content,
  ice/teal = values/metrics, **peach = warning**, **green = healthy/action**, red =
  error). New settings surfaces use **channel 06, blue accent `#4455ff`**; 14px cap
  buttons; only 3 font sizes (25/16/11px); flat styled fields, never unstyled native
  widgets; collapsed option groups with `N SET` summaries; animations independent, no
  loops (0.45s transitions).
- **Config writes**: 0700 dir, 0600 file, tmp → fsync → chmod → rename (atomic). Seed on
  first run only when the file is **absent** (not corrupt); re-arms on deletion (D10).

## Testing rules (the big lesson — do not skip)

**NEVER verify UI by screenshot-and-hope.** The panel is a borderless NSPanel: invisible
to AX, no CDP, auto-dismisses on focus loss, and the display can rescale mid-session —
visual checks burned three agent budgets before the deterministic harness existed.

- Primary gate: `./run_tests.sh` — Swift pure-logic suite **and** the Node+jsdom DOM
  layer (`npm ci --prefix Tests/ui` once, then it runs inside `run_tests.sh`). The jsdom
  runner loads the real `panel.html` + script with a fake bridge and asserts DOM/draft
  state.
- Live proof: `Tests/ui/live_smoke.sh` (`--round-trips` for save/restart transitions)
  against a real running engine via the opt-in `SPLASHUI_SMOKE` env-gated hooks.
  **Assertions are the gate; screenshots are evidence only.**
- Live smokes must be **deterministic against the machine, not just the app**: input-
  isolated (suppress stray physical keyboard/click events into the focused panel) and
  **re-assert values at every save step**, not only at init.
- **Restore machine state after every live run**: config bytes byte-identical (sha256),
  engine pid/port untouched, no stray app processes. The smoke script does the
  backup/restore — never bypass it.
- Swift trap worth remembering: `NSNumber` bridges to `Bool` for *any* number — JSON
  decoding must test `is NSNumber` and discriminate `CFBoolean` via `CFGetTypeID`
  before `as? Bool`, or every number parses as true/false.

## Active SMART goals

### Goal: Every UI surface ships with its DOM assertions
- **Specific**: each new/changed UI surface lands with passing `panel.test.mjs` DOM
  assertions (and `run_tests.sh` green) in the same commit; no screenshot is the primary
  verification of any acceptance criterion.
- **Measurable**: 0 stories requiring a dedicated "smoke agent" or visual QA pass;
  100% of acceptance criteria covered by an executable assertion.
- **Achievable**: the harness exists and is fast (seconds, no app/engine needed); the last
  four UI stories (S5c/S6a/S6b/S7) each took 4–11 minutes of verification vs hours
  screenshot-based.
- **Relevant**: screenshot-and-hope verification of the NSPanel burned ~3 agent budgets
  (issue #5, S5) — the panel is invisible to AX/CDP and auto-dismisses.
- **Time-bound**: review at the end of the next UI feature.
- **Status**: open
- **Created**: 2026-10-15
- **Source**: issue #5 retrospective (S5, PR #6)

### Goal: Live smoke stays a minutes-scale gate
- **Specific**: any `live_smoke.sh` run completes in under 10 minutes per story, is
  input-isolated, re-asserts at every save step, and ends with the machine restored
  (config sha256 byte-identical, engine untouched).
- **Measurable**: ≤10 min wall time per live smoke; 0 machine-state deviations; 0
  physical-input contaminations (stray events logged but never applied).
- **Achievable**: current round-trip runs complete in 1–2 minutes end to end (close-out
  run: 49/49 assertions, ~1 s save windows).
- **Relevant**: live smokes pre-harness took hours; a stray keyboard 'r' once corrupted a
  live run (S5) and an un-stamped adopt path hid a real bug until the smoke asserted it.
- **Time-bound**: review at the end of the next UI feature.
- **Status**: open
- **Created**: 2026-10-15
- **Source**: issue #5 retrospective (S5/S5c, PR #6)

### Goal: Verify plan-affecting behavior on both engine paths
- **Specific**: any change touching launch plans, restart-required, or config baseline is
  verified against **both** `ServerProc.launch` and `ServerProc.adopt` paths (live
  assertions pin the adopt baseline as `false`, not `null`).
- **Measurable**: 0 plan/restart bugs reported after close-out; adopt-path assertion
  present in the live suite (currently `adoption stamps restart baseline`).
- **Achievable**: the live harness already drives real adopt sessions; extending it per
  story is a minutes task.
- **Relevant**: `restart_required` was null in adopted sessions because the plan baseline
  was stamped only in `launch()` — caught by the live smoke, fixed in the S5 work.
- **Time-bound**: review at the end of the next UI feature.
- **Status**: open
- **Created**: 2026-10-15
- **Source**: issue #5 retrospective (S5, PR #6)
