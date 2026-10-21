# Deterministic panel UI tests

Use DOM state, not screenshots, AX, OCR, or screen coordinates. Paths use the
repository's existing capitalized `Tests/` directory (important on Linux).

## Primary: Node + jsdom (no app, engine, GUI, or config writes)

Requires Node 18+ (developed with Node 22.12.0). Install the pinned, test-only
dependency once, then run whenever editing the panel:

```sh
npm ci --prefix Tests/ui
node Tests/ui/panel.test.mjs
# or: npm test --prefix Tests/ui
```

The runner loads **the real `Resources/panel.html` and its script**, with jsdom's
HTML parser, real event dispatch, and an in-memory `window.webkit` bridge. Only
canvas drawing, scrolling and timers are stubbed; timers are explicitly flushed,
not slept. It asserts draft/input population (including both manual-path reads),
dirty comparison/revert, full ConfigDoc saves and preserved unknown fields/key,
key masking (including input properties), rejected saves, restart-required display,
folder status/count/add/delete/scan, browse callbacks, cfg retention across ticks,
and first-run show-once/dismiss/CTA persistence commands. Screen assertions cover
telemetry-only status, hamburger/back navigation and scroll reset, settings control
ownership, and the first-run CTA's settings target. Native menu labels/selectors
are source-asserted (not synthesized mouse-event proof). Profile assertions cover
list/ACTIVE caps, add/remove/clone/rename, duplicate-name rejection, metadata,
scanned source/kind/verdict model choices, drafter overrides and validation facts,
focused-input preservation and D15 metadata flushing. S6b adds contract-gated KV cache
controls, independently collapsed groups, requires-disabled reasons, invalid-field and
debounced COMMIT gating, atomic draft activation, ACTIVE/last-used updates, restart
prompt/count, revert clearing, and explicit confirmation through the existing restart
command. Every assertion and the final count are JSON lines; any failure exits nonzero.

The bridge fixture supplies computed restart state; it does **not** prove Swift's
producer. Swift regressions and the live layer cover that boundary. `run_tests.sh`
runs this layer when Node and scoped jsdom are installed, otherwise prints an
explicit skip. It never downloads dependencies during a test run.

## Secondary: real WKWebView + Swift bridge

Requires macOS, an active graphical login, Node 18+, `lsof`, and screen-recording
permission for `screencapture`. It does not require jsdom. First build the app and
quit any existing **SplashUI app** without stopping the already-serving engine:

```sh
./build.sh
Tests/ui/live_smoke.sh                 # read-only integration assertions
Tests/ui/live_smoke.sh --round-trips   # port/ANE + profile/model + option/activation transactions
```

The runner refuses to launch unless exactly one engine already owns the configured
port and no SplashUI app is running. The round-trip fixture must begin on 8123 with
ANE enabled. It launches the built binary **once** using the opt-in `SPLASHUI_SMOKE`
hooks, awaits `live_assertions.js`, and asserts actual DOM/CF draft/Swift tick state:
status-only telemetry, hamburger/back navigation in the same viewport, internal
settings scrolling with a reachable shared footer, form population, manual path,
external-engine PID, engine resolution, masked key, completed folder rows and a
PRESENT lmstudio row with models. The hook starts on status (channel 01), then
switches to settings through the real hamburger handler. Polling waits for
predicates, not arbitrary delays.

The smoke-only JS captures and ignores trusted physical keyboard/click events so
typing elsewhere cannot contaminate the key panel; synthetic test events still
exercise its actual handlers. Ignored event types/targets (never typed text) are
recorded in result JSON. Both manual-path reads and the persisted ANE tick value
are checked at every save, not only at initialization.

Round trips additionally await each actual save response and
computed `restart_required`: **false -> true -> false -> true -> false**. No Start,
Stop or Restart command is sent. A 4.5-second watchdog bounds the 8199 window; the
original port is continuously probed for 200-with-key / 401-without-key during the
run. The adopted-plan baseline is an app-session UX assumption, not a claim that an
external process's entire argv was inspected; edits after adoption require restart.
The live `adoption stamps restart baseline` assertion deliberately requires false,
not null, before editing: it pins `ServerProc.adopt()` itself rather than merely
simulating it. Adoption stamps the already-computed current plan in memory;
subsequent port/ANE edits compare against that signature. Reverting a change or a
successful explicit restart clears the comparison. Nothing is persisted to config,
and neither adopting nor saving automatically restarts an external engine.

S6a round trips also create a profile (restart stays **false**), clone/remove it
in the draft, then edit the **current active profile's model** and save (restart
becomes **true**). Reverting the profiles and model makes it **false** again.
This distinguishes inert profile creation from a launch-relevant model edit;
selection is never activation. Live assertions check the settings list, metadata,
folder-derived picker and real package drafter outcome. The screenshot is taken
with the profile area visible, but remains evidence only.

S6b uses `#profileDetailSlot` for option groups and `#profileActivationSlot` for
activation/restart controls. `CF.profileId` selects an editor, not an active profile;
`cfSelectedProfile()` exposes its draft and `cfBuildDoc()` builds the full candidate.
The required `config.activate` bridge command carries that full doc plus `profileId`:
one atomic save commits draft edits, changes the active id and stamps last-used.
The existing computed plan signature drives both the shared footer and the prompt;
only explicit confirmation sends the existing `restart` command. No schema change.
Live smoke clones the active profile, edits KV format, validates and activates it,
asserts the ACTIVE cap/last-used/prompt and `restart_required: true`, then activates the
original profile and asserts `false` before removing the clone. It never confirms a
restart. Final suites: 103 DOM assertions and 42 live round-trip assertions.

A private `/tmp/splashui-live-*` directory retains JSON per-assertion results,
step snapshots, app log, one screenshot **as evidence only**, and a final summary
with the config SHA-256 and engine PID/HTTP checks. The script backs up config bytes
and permissions before launch; success, failure, timeout and catchable interruption
terminate only the app PID it launched and restore those exact bytes/permissions.
Never use SIGKILL on the runner itself: no process can trap it. Sensitive backups
and generated hook files are mode 0600 inside a mode-0700 directory.

Both layers compare `#manualPath.value` with `CF.draft.manualPath` after config-get
readiness. `CF.draft` is authoritative for saving (`cfBuildDoc` consumes it); the
input must agree after synchronous `cfInit` / `cfSyncForm`, so disagreement is a
real assertion failure rather than something to explain away from a screenshot.
