## Completed map (B–F), replacing the partial report

**Workspace:** not created. I have no shell, so `/tmp/agents/splashui-settings/iteration-N` does not exist. The parent should create it. No files were written.

Coverage: I read the whole design spec and all of B's required anchors. For C and D, some function bodies are still unread (noted inline). Nothing here was verified by running code.

---

## B. `Resources/panel.html`

### B1. Views and switch mechanism
- `#statusView` is `<main class="screen">` at ~line 170 (`#statusContent` at 170, `#header` at 171–173, `#statusPill` at 174, `#btnSettings` at 175, channels from ~177 on). It ends at line 256 `</main>`.
- `#settingsView` is `<main id="settingsView" class="screen" hidden>` at **line 257**.
- **Switch:** `window.showView = function(view)` at **351–356**. It sets `hidden` on `#statusView` and `#settingsView`, saves and restores `scrollTop`. Wired at 357 (`#btnSettings` → settings) and 358 (`#btnStatus` → status). The state is local to the WebView; Swift only triggers it via `window.showView('…')` (main.swift:578, 715, 739).

### B2. Full settings markup (verbatim structure, lines 257–302 and 303–335)
| Lines | Element | Ids / classes / behaviour |
|---|---|---|
| 258 | `#settingsHeader` | `<button id="btnStatus">Status</button>` + `<h1>Settings</h1>`. There is no profile/model header line. |
| 260–303 | `section.settings-panel[data-channel=06]` | Global block |
| 261 | `.sec-h` | "Global Settings" + `<span>config.json</span>` |
| 262–263 | `.sec-h` | "Engine" heading |
| 264–271 | `.frow` | `.capbtns` containing `#capAuto` (.cb) and `#capManual` (.cb); `#manualPath` text input; `#btnBrowseEngine` (.mini) |
| 272–274 | `.frow` | `#engPath` (.engpath), `#vCfg` (version, teal), `#engValid` (green) |
| 275–276 | `.tried` | `#engTried`, `#engFallback` (hidden) |
| 277–278 | `.sec-h` | "Model folders" |
| 279 | `#folderList` | rows built by `cfRenderFolders` (JS 578) |
| 280–284 | `.frow` | `#folderPath` text input, `#btnBrowseFolder` (.mini), `#btnAddFolder` (.mini) |
| 285–286 | `.sec-h` | "Network" |
| 287–291 | `.frow` | `<label>Port</label>`, `#cfgPort` number, `<label>API key</label>`, `#cfgKey` (readonly, masked) |
| 292–293 | `.sec-h` | "Compute" |
| 294–298 | `.frow` | `.capbtns` containing `#aneOn` (.cb.on) and `#aneOff` (.cb) |
| 299–302 | `.frow` | `#btnCfgSave` (.btn, Save, inline blue style) and `#cfgMsg` |
| 304–335 | `#profilesSlot` > `section.settings-panel[aria-label=Profiles]` | "Profiles" `.sec-h` with `#btnProfileAdd` (.mini) |
| 307 | `#profileList` | rows built by `cfRenderProfiles` (JS 745) |
| 308–322 | `#profileEditor` (hidden) | `.sec-h` "Profile editor"; `#profileName` input, `#btnProfileClone`, `#btnProfileRemove`; `#btnProfileModels` (.mini, "Choose model"); `#profileModels` (hidden list); `#profileDrafter` (.profile-chip); `#profileDraftRow` with `#profileDraftModel` input; `#profileLaunchMeta` (.profile-meta); `#profileDetailSlot` (filled by `cfRenderOptions`, JS 801); `#btnProfilesSave` "Commit" |
| ~323–325 | `#profileActivationSlot` | `#btnProfileActivate`; `#profileRestartPrompt` (hidden) with `#profileRestartText` and `#btnProfileRestart` |

Outside the view: `#cfgModal` at **line ~327–335** (first-run modal, `.card`, `#modalDismiss` "Later", `#modalCta` "Open Settings"). Shown by `cfFirstRun()` (JS 864).

**Missing from the current view vs spec:** no GENERAL/MEMORY/CACHE/COMPUTE/API tab row, no column-1/2/3 Finder layout, no folder source tags, no PRESENT/MISSING caps beyond a text status, no "+ ADD FOLDER" row (an input + Add button exists), no HOST input, no ALLOWED-HOST/ORIGIN fields, no WEB UI toggle, no eye toggle for the key, no model chooser modal (there is an inline `#profileModels` list), no `CANCEL`/`OK`, no ENGINE "VALID / UNRUNNABLE / FALLBACK" verdict cap beyond `#engValid` text.

### B3. JS → Swift command list (all `cmd(...)` callsites)
`cmd = (c,args) => window.webkit.messageHandlers.cmd.postMessage({cmd:c, ...args})` at **panel.html:519**.

| Callsite (line) | Command | Payload | Issued from |
|---|---|---|---|
| 530 | `start` | none | `#btnStart.onclick` |
| 531 | `stop` | none | `#btnStop.onclick` |
| 532 | `restart` | none | `#btnRestart.onclick` (if `cfg.restart_required !== true`); else reveals the settings prompt |
| 610 | `config.validate` | `{doc, validation_id}` | `cfValidate()` (607) via `cfDebouncedValidate()` (612) |
| 624 | `config.save` | `{doc}` | `cfSave()` (619); `#btnCfgSave.onclick` at 710 |
| 688 | `browse` | `{context:"engine"}` | `#btnBrowseEngine` |
| 693 | `browse` | `{context:"model_folder"}` | `#btnBrowseFolder` |
| 708 | `config.scan` | `{id}` | folder row `data-act="scan"` (~705–709) |
| 859 | `config.activate` | `{doc, profileId}` | `#btnProfileActivate` handler (~855–860) |
| 861 | `restart` | none | `#btnProfileRestart` |
| 871 | `config.firstRunDone` | none | `cfFirstRunDone()` (870) |
| 880 | `config.get` | none | one-shot at load |

**Not present in JS:** no `config.load` alias, no model-list request (models arrive in the tick), no profile CRUD command (add/clone/delete are JS-only drafts, persisted only through `config.save`/`config.activate`), no `config.cancel`/`discard`, no `browse` for a model.

### B4. Tick/status fields consumed (`window.update` at 518 → `render()` at 389)
`update` stores `S = d` and keeps the last `cfg` if absent (518). Swift sends via `window.update(json)` at main.swift:1487.

**Status fields** (`render`, 389–517): `state`, `model`, `server.launch_error`, `server.pid`, `server.launched_by_app`, `server.up_seconds`, `rates.decode_tps`, `rates.prefill_tps`, `prefill{pct,input,cached_pct,tps}`, `engine{ttft_p50_ms,itl_p50_ms,pressure,version,metal_healthy,loop_tick_ms}`, `ready`, `ctx`, `kv_fmt`, `ane{state,share}`, `kv{capacity_bytes,allocated_bytes,active_pages,cache_pages}`, `state_mem{bytes,active_lanes,entries}`, `eng_mem{current_bytes,peak_bytes,headroom_bytes,host_available_bytes}`, `ssd{bytes,quota}`, `cache{hits,cold_misses,reused_tokens}`, `sys{phys_bytes,wired_bytes,compressed_bytes,active_bytes,inactive_bytes,free_bytes}`, `req{active[],recent[],completed_total,failed_total,cancelled_total}`, `sched{queued,waiting_resources}`.

**Cfg fields** (`S.cfg`, consumed in `render` 499–500 and `cfRender` 640+, `cfRenderFolders` 578, `cfRenderProfiles` 745, `cfgSync`/`cfRender`):
`cfg.restart_required`, `cfg.restart_reason`, `cfg.in_flight`, `cfg.first_run`, `cfg.result{ok,errors,warnings}`, `cfg.engine{version,resolved,path,tried,valid,error,mode,manual_path,brew}`, `cfg.option_defs`, `cfg.mapping_fallback`, `cfg.mapping_used`, `cfg.registry_report`, `cfg.folders[]{id,path,source,models[],scanning,present,error}`, `cfg.profiles[]{id,name,model{source,id,dir},options,meta{created_at,last_used_at,last_successful_launch,last_failure},eligibility,eligibility_reason,drafter,kind}`, `cfg.active_profile`, `cfg.active_invalid`, `cfg.version_too_new`, `cfg.load_error`, `cfg.port`, `cfg.api_key_masked`, `cfg.picked{context,path}`.

**Gap:** `cfg.version_too_new` and `cfg.load_error` are in the payload but not visibly rendered in the settings markup (not verified by grep for consumers beyond the payload).

### B5. Status-screen footer (markup and CSS)
Markup, **lines 336–341**:
```
<div id="footer">
  <button class="btn gr" id="btnStart">Start</button>
  <button class="btn y" id="btnRestart">Restart</button>
  <button class="btn r" id="btnStop">Stop</button>
  <span style="display:inline-flex;flex-wrap:nowrap;white-space:nowrap">
    <span id="pidPill"><span class="h" id="pidLabel">PID</span><span class="h" id="pidNum">—</span></span>
    <span class="h" id="envPill">—</span>
  </span>
</div>
```
Note: `.btn.r` is referenced at 339 but no `.btn.r` rule appears in the grep output (only `.btn.gr` 133 and `.btn.y` 134). **Unverified** whether `.btn.r` is defined.

CSS: `#footer` 140 (grid `repeat(3,max-content) 1fr`, gap 5px, padding-left 64px, bottom 23px). `#footer::before` 141 (42px left border + 12px bottom border, radius `58px 38px`, the swoop). `#footer::after` 142 (12px bar). `#pidPill` 143, `#pidPill .h, #envPill` 144 (gray `#888` black text, display Condensed, 28px high, uppercase). `#pidLabel` 145 (left radius 14px).

Restart button text switches to `RESTART TO APPLY` at JS 500 when `cfg.restart_required` is true. The spec wants `RESTART NEEDED` as a red capsule at Row 1; not present.

### B6. Header
`#header` 171–173: `<div class="header-title">` `#hName` "Splash interface control", `#hModel`, `#statusPill`. CSS: `#header` 52–53 (`position:relative; grid 1fr; height 62px`), `#header::before` 52 (blue swoop), `#header .title` 29, `#btnSettings` 30–31. Settings header: `#settingsHeader` 34 (blue 25px display text), `#btnStatus` 35 (blue capsule, radius `14px 0 0 14px`).

---

## C. `Sources/ui_logic.swift`

### C1. Config schema (`configData` ~2302–2345; defaults 2349–2396)
- `configSchemaVersion = 1` (~2215).
- Top: `schema_version`, `globals`, `profiles[]`, `active_profile`, `first_run_shown`, `reserved` (unknown keys preserved).
- `globals`: `engine{mode:"auto"|"manual", manual_path, brew}`, `model_folders[]{id,path,source:"auto"|"manual"}`, `port` (default 8123), `api_key` (default `splash-standalone-1`). Network allowed-host/origin and web-UI toggle **do not exist** in the schema.
- Default folders (2350–2356): `lmstudio ~/.lmstudio/models`, `ollama ~/.ollama/models`, `hfhub ~/.cache/huggingface/hub`, `splash ~/Library/Application Support/Splash/models`, `installroot ~/SplashUI/models`, all `source:"auto"`.
- Profile model: `ProfileModel(source, id, dir)` 1925–1930 (sources include `lmstudio|ollama|hfhub|splash|installroot|u-<n>|hfid|none`).
- Profile: `id`, `name`, `model`, `options` (flat dict of `JSONValue`), `meta{createdAt, lastUsedAt, lastSuccessfulLaunch, lastFailure{at,message}}`.
- Default profile options (2366–2376): `persistent_cache:true`, `max_cache_disk:"100g"`, `idle_release:"240m"`, `ane:true`.
- Read: `decodeGlobals` 2110–2135ish, lenient per folder with dropped-list; `decodeProfiles`; `parse(_:)` ~2180–2210.
- Write: `configData(_:schemaVersion:)` 2302–2345, sorted keys, unknown top-level keys verbatim. `ConfigStore` atomic write (tmp→fsync→chmod 0600→rename) 2950–2978.

### C2. Engine discovery ladder
- `resolveKit(engine:home:isDir:isExecutable:brewKeg:kitVersion:)` at **ui_logic.swift:243–285**. Body not read in full; from the comments and the callers: auto mode is ordered manual path → install root → Homebrew keg → (kit registry per the design; **not confirmed in body**). `manual` mode uses only `manual_path`. Returns `(kit, version, tried, error)`.
- `firstRunConfig` 2396–2431: if a Homebrew keg with `libexec` exists, mode auto, brew true; keg version ≥1.3.1 → default model `hfid mlx-community/Qwen3.8-27B-4bit`; else the local 1.3.0 package. No runtime → mode manual, model `none`.
- `kitVersion(_ kit:)` 2651–2654 reads `release.json` `version`.

### C3. Launch plan and argv (`planLaunch` 1525–1640)
Order:
1. `parseConfig` (corrupt → error "last good config remains").
2. active profile by `doc.activeProfile` (missing → error).
3. `resolveKit` (2nd step; D9: no process env).
4. `contractFor(kr.version, launchRegistry)` 753–768 (D16).
5. Model: `profile.model`; `source "none"` or no id → error. Enumerates each `globals.modelFolders` via `enumerateModels` (395), first match by id wins; falls back to `classifyModelDir` (344) or hfid.
6. `eligibility(...)` 1353 (blocked/unrunnable → error with fix text).
7. `buildArgv(contract, profileValues:, model:, globals:)` 1255–1303. Options equal to `defValue` omitted unless `alwaysEmit`; secrets to env only (`SPLASH_API_KEY`); bool → bare flag; `requires` violation → warning issue.
8. Executable: `kit/python/bin/python` or `python3` else error.
9. **Signature (D13)** 1632–1637: `[kit, version] + argv + (SPLASH_API_KEY env if present)` joined by `\u{1F}`.

Plan output `LaunchConfig` (1466–1490): `workDir, executable, base, engineArgs, engineEnv, port, modelId, modelDir, version, tried, mappingFallback, profileId, profileName, signature, issues, error`.

### C4. `restart_required` (D13)
- Computed at tick time: `main.swift:1441` `restart = lastSuccessfulPlanSignature.map { plan.signature != $0 }`; `restart_reason` 1443–1445.
- Baseline stamped in `ServerProc` launch at **main.swift:196–198** (`lastSuccessfulPlanSignature = plan.signature`). Declared 93–95. The adopt path is claimed in AGENTS.md but the stamp was **not found** in the adopt function body by grep. **Unverified.** Per AGENTS.md this was fixed in S5 for adopt; re-check.
- ui_logic also has `restartRequired` placeholders: `configTickPayload` 2598–2599 always emits `NSNull`, overwritten by main.swift.

### C5. Model-folder scanning and chooser data
- `enumerateModels(folder:isDir:fileContents:listDir:)` 395–460: depth ≤2 scan. Returns `[ModelEntry]`.
- `ModelEntry` 359–365: `id` (owner/repo or name or ollama name), `dir`, `source` (folder id), plus `kind` (classified). **No size field, no file-count field.**
- `folderTickState(folder:...)` 466–484: returns `{id, path, source, models[], scanning, present, error}`. `models` = `modelTickState` per entry (1440–1460): includes `eligibility`, `eligibility_reason`, `drafter`, `kind`, `source`, `id`, `dir`.
- Background scan: `runFolderScan` main.swift:808–836 on a queue; cache `folderScanCache` keyed by folder id; `forceFolderScan` 793 (`config.scan`).
- **Gaps for the chooser:** no per-model **size** (`source · size` in spec §4 is ABSENT); no source-filter counts (computed in JS from `cfModels()` 719–721 — possible); no HF-id **search over downloaded models** (JS-only filter needed, models come from tick); no download/list-remote.

### C6. Unrunnable verdicts (D4) and contract registry
- `Eligibility.Verdict` 1268–1275 range: `runnable | unrunnable | blocked | unknown`. Table `eligibility` 1353–1420 (package/assembly/hfid by flavor; hfid on launcher requires `contract.familyRegistry[family]` else unrunnable). `unknown` is not a gate.
- Registry `launchRegistry` 741–751: `"1.3.0": contract130, "1.3.1": contract131, "1.3.2": contract132`.
- `contractFor` 753–768: exact match → `fallback:false`; otherwise **latest** authored contract with `fallback:true` (D3 "FALLBACK MAPPING"). Nil version → latest, fallback true.
- **1.3.0 pin:** no pin exists. A kit reporting `1.3.0` gets `contract130` exactly. A newer, unauthored version (e.g. 1.3.3) silently maps to **1.3.2** with `mapping_fallback = true` (not blocked). The spec rule "restart uses 1.3.0 not 1.3.1 present on system" is **not enforced by this code**. `version_too_new` is in the tick payload (`configTickPayload` parameter) but its computation in main.swift was not found.
- Spec blocks: `cfg.engine.valid` is emitted as NSNull (1397-era `configTickPayload` 2555–2563) and filled by main.swift:1429–1434 for `tried`/`error`.

---

## D. `Sources/main.swift`

### D1. Message routing
- `cfg.userContentController.add(self, name: "cmd")` at **533**, plus `"size"` at 534.
- `userContentController(_:didReceive:)` at **594–627**. Body must be `[String:Any]`, string bodies rejected.
- Handled commands (switch 603–627):

| cmd | Handler | Reply |
|---|---|---|
| `start` | `server.clearLaunchError(); server.launch()` (604) | tick only |
| `stop` | `server.stop()`, then `quitApp()` after 2 s (605–607) | — |
| `restart` | `server.stop()` then `launch()` after 1.5 s (608–612) | tick |
| `config.get` | `respondConfigGet()` (613, def 649): `configData` → `window.__cfgGet(json)` | `__cfgGet` |
| `config.save` | `respondConfigSave(body)` (614, def 661): `saveCandidate` (single writer) | `sendConfigResult(..., to: window.__cfgSave?)` |
| `config.activate` | `configStore.activateCandidate(data, profileId:)` (615–619) | `sendConfigResult` to `window.__cfgSave` |
| `config.validate` | `respondConfigValidate(body)` (620, def 671): `validateCandidate` | `sendConfigResult` |
| `browse` | `browse(context:)` (621, def 776): `NSOpenPanel`, `context` = engine or model_folder; result on next tick as `picked` | tick `picked` |
| `config.scan` | `forceFolderScan(id)` (622–623) | tick |
| `config.firstRunDone` | sets `doc.firstRunShown = true`, `saveCurrent()` (624–626) | tick |
| default | `break` (627) | — |

- **Missing (ABSENT):** `config.get` exists. **No** model-list command, no profile add/clone/delete commands (JS-only draft then `config.save`), no `profile.activate` alias, no `network` settings command, no `engine.adopt`, no `model.select`.
- `respondConfigGet` ~649–659, `respondConfigSave` 661–670, `respondConfigValidate` 671–688, `sendConfigResult` 689–696.
- **Unverified:** `window.__cfgSave` consumer. Grep for `__cfgSave` in panel.html was not run; it may be a dangling callback. Check before relying on `config.activate`/`config.save` reply.

### D2. Panel HTML serving and window plumbing
- `panel.html` loaded via `WKWebView` in `applicationDidFinishLaunching`; `loadFileURL` not located by grep (the grep for `loadFileURL|panel\.html` returned no matches in main.swift). **Unverified path**.
- `showPanel(view:)` 576–580: `pendingView = view`; if `webReady`, `window.showView('…')` (578). `openSettings` 574, `openStatus` 573.
- `webReady` set at 714; then `showView` + pending config eval + pending tick flushed (714–723).
- `applyPanelHeight` 841–848 (JS reports `size` → clamps 320…screen-120).
- Tick: built ~1380–1490; `cfgPayload` pushed to JS only when `cfgJSON != lastCfgJSON` (1478); send via `window.update(...)` at 1487 (or pendingTick).
- Tray: `updateTray(detail:...)` 1264–1286 by state; not in scope.

### D3. Config persistence
- `ConfigStore` (2930-ish) atomic write (see C1). `saveCandidate`, `validateCandidate`, `activateCandidate`, `saveCurrent`.
- `lastCfgJSON` 446: only re-send on change.
- Scan cache `folderScanCache` / `folderScanKey` / `folderScanInFlight` (main.swift ~795–836).

---

## E. Tests

- `run_tests.sh` (`/Users/brobert/Documents/code/SplashUI/run_tests.sh`): zsh, `swiftc -O Sources/ui_logic.swift Tests/main.swift -o /tmp/splashui-logic-test`, runs it, removes binary; then `node Tests/ui/panel.test.mjs` if `Tests/ui/node_modules/jsdom` exists, else SKIP.
- `Tests/ui/panel.test.mjs`:
  - 1–20: loads `panel.html`, asserts one inline script, builds `fixture` (`schema_version 1`, `active_profile p1`, `globals{engine{mode manual, manual_path /fixture/kit-1.3.0, brew false}, port 8123, api_key secret, model_folders[lmstudio, missing]}`, profiles p1, p2).
  - Harness (~ lines 80–103): `JSDOM` run, fake bridge `commands[]` captured from `messageHandlers.cmd.postMessage`, returns `{w, $, tick, commands, drain, flushTimers, change, save, reject, restarted, close, doc}`.
  - Assertion style: `check(name, fn)` with `assert.*` from `node:assert/strict`, `$('id')`, `change(id, value)`, `save()`.
  - Existing checks include `default screen is telemetry-only status` (107), `hamburger switches views without bridging or losing draft` (117), `all S5 controls live on the settings screen` (127; asserts `capAuto, capManual, manualPath, engValid, folderList, cfgPort, cfgKey, aneOn, btnCfgSave, cfgMsg` exist), `native menu exposes ordered ...` (413, grep-on-main.swift).
  - **New settings DOM assertions slot in** after line ~127 in the same `check` style, using the fixture. A new surface needs its ids in `fixture` and `$()` lookups.
- `Tests/ui/live_smoke.sh`: `exec node live_smoke.mjs`; accepts `--round-trips` only; requires macOS, a built `build/SplashUI.app`; uses the real `~/Library/Application Support/SplashUI/config.json` (no override); backs up and restores it. Round-trips: save/restart/adopt; adoption baseline assertion.

---

## F. Gap analysis (keyed to DESIGN_SPEC §1–§9)

Legend: EXISTING (anchor), PARTIAL (what is missing), ABSENT (backend work needed).

### §1 Screen structure
- **Header (blue swoop, "SPLASH SETTINGS", STATUS capsule, peach model bar, engine-state pill):** PARTIAL. `#settingsHeader` 258 has Status + "Settings" only (no "SPLASH SETTINGS" text, no peach bar, no model-name bar, no green state pill). Header CSS `#settingsHeader` 34 and `#btnStatus` 35 exist. Needs a peach bar element and profile/model text from `cfg.profiles`/`active_profile` (tick, EXISTING).
- **Left rail (lilac 06 + green 07 segments, channel numerals):** ABSENT. `.settings-panel` has `--accent #4455ff` (64) only; no lilac or green rail. `.section-heading`/`section > .label:first-child` 115–117 give a heading style only.
- **Section dividers (`section::after` broken-line):** ABSENT for settings. Status uses `section::after`? grep returned only `.track/.bar/.seg` 119–124 patterns and `.track::after` gradient 124. The broken-line divider class is **not** in the grep output. Treat as ABSENT/unverified.
- **Footer swoop C-band:** EXISTING on status (`#footer::before/::after` 140–142) and reused by DOM id `footer` (single element, outside both views, 336). The settings view shares the same footer. Spec wants the footer to mirror status (§7) — EXISTING.

### §2 Global section (06)
- **Heading "GLOBAL SETTINGS" lilac:** PARTIAL. `.sec-h` 66 blue color, text "Global Settings" 261 (not lilac, not uppercase by CSS? `.sec-h` has no `text-transform`; mixed case visible).
- **Column 1 ENGINE / FOLDERS / NETWORK selector (Finder-style):** ABSENT. Current layout is one vertical stack (261–302) with inline `.sec-h` headings. Needs a new column container and selection state.
- **ENGINE:** PARTIAL.
  - `AUTO|MANUAL` caps: EXISTING (`.capbtns .cb` 68–72, `#capAuto` 264 / `#capManual` 265). Selected colour is blue `#4455ff` 70, spec wants lilac for global.
  - Engine path pill + BROWSE: PARTIAL. `#manualPath` 266 + `#btnBrowseEngine` 268 exist. Not a dual pill; `.engpath` 86 is text only.
  - Discovery ladder line + detected version (teal) + arch/OS: PARTIAL. `#vCfg` 273 (teal) shows version; no arch/OS; no ladder line (the `#engTried` 276 `.tried` list exists, populated by JS from `cfg.engine.tried`).
  - `VALID` (green) / peach `UNRUNNABLE — reason` / `FALLBACK MAPPING`: PARTIAL. `#engValid` 274 (green, text only), `#engFallback` 276 (hidden). No peach UNRUNNABLE cap for the engine (`.warn-cap` 96 exists, peach).
  - "APPLIES ON NEXT RESTART" note: ABSENT as spec; the app shows `RESTART NEEDED` pill via `btnRestart` text (500) and profile prompt (750). Per spec §5/§6 this is a red pill, not a note. Restart-required *pill* missing in row 1 footer.
- **FOLDERS:** PARTIAL. `#folderList` 279 rows by `cfRenderFolders` (578–597) with PRESENT/MISSING/scan. Missing: per-row source tag (LM STUDIO / OLLAMA / HF HUB / SPLASH) — `source` is only `auto|manual`, not a display label; add display map. Missing: `+ ADD FOLDER` row (exists as input + Add button 280–284). Auto-detection on first run: ABSENT for folders — the defaults are seeded (2350–2356) regardless of presence; no "detected" flag shown.
- **NETWORK (HOST, PORT steppers, API KEY masked + eye, ALLOWED-HOST, ALLOWED-ORIGIN, WEB UI ON/OFF):**
  - PORT: PARTIAL. `#cfgPort` 288 (number, no steppers). Handler 689.
  - API KEY masked: PARTIAL. `#cfgKey` 290 readonly, masked by `api_key_masked` (tick). No eye toggle.
  - HOST: ABSENT in config schema (only `port`; `Cfg.host` in main.swift:9 is a constant `127.0.0.1`). Adding a config key `globals.host` is ABSENT.
  - ALLOWED-HOST / ALLOWED-ORIGIN: ABSENT (the `allowed_host`/`allowed_origin` OptionDefs exist in the contract at ui_logic 595–597 as `.append` engine args, **not** in config globals). Need a `globals.allowed_hosts` / `allowed_origins` list in the schema and UI, or reuse the OptionDef values — decide.
  - WEB UI ON|OFF: ABSENT. The OptionDef `--no-webui`/`web_ui` **not verified**; grep didn't surface one. Mark ABSENT.

### §3 Profiles section (07)
- **Profiles heading green:** PARTIAL. `.sec-h` 306 "Profiles" with `#btnProfileAdd` 306 (ADD PROFILE button inside heading row — spec says at bottom of list).
- **Column 1 profile list + "+ ADD PROFILE" at bottom:** PARTIAL. `#profileList` 307 built by `cfRenderProfiles` 745–770 (rows `.profile-row`, `data-profile-act=edit`). ADD is in the heading (306), not bottom. Active-profile dot: PARTIAL (`.profile-cap.runnable` "ACTIVE" text pill 748, not a dot). Selected row highlight: PARTIAL (no `.selected` class in grep).
- **Column 2 `PROFILE SETTINGS` title + five tabs GENERAL/MEMORY/CACHE/COMPUTE/API:** ABSENT. No tabs. `#profileEditor` 308 is a single vertical stack with `.sec-h` "Profile editor" 309 and `#profileDetailSlot` 320 filled by `cfRenderOptions` (801–839, flat groups via `option-group` 147–152).
- **Column 3 detail (open-bracket frame):** ABSENT (no frame CSS). Blocks 310–322 exist as flat rows.

### §3 — profile tabs in detail
- **GENERAL** (PROFILE label, ACTIVATE|CLONE|DELETE caps, model pill MODEL|name|CHANGE, drafter line, CREATED/USED line, LAUNCH PREVIEW box):
  - ACTIVATE: PARTIAL (`#btnProfileActivate` 323, plain `.mini`). CLONE/DELETE: PARTIAL (`#btnProfileClone` 310, `#btnProfileRemove` 310 `.mini.del`), not segmented caps.
  - Model pill MODEL|name|CHANGE: ABSENT as pill; `#btnProfileModels` 311 "Choose model" `.mini` + `#profileModels` list 312 (hidden) exists.
  - Drafter line: PARTIAL. `#profileDrafter` 313 (`.profile-chip`), populated by JS from `cfg.profiles[].drafter`. `#profileDraftRow` override input 314.
  - CREATED / USED: PARTIAL. `#profileLaunchMeta` 315 (`.profile-meta`), populated from `meta.created_at`/`last_used_at` (JS 748).
  - LAUNCH PREVIEW box: PARTIAL. No dedicated box. `cfg.profiles[].launch_preview`? Not in tick. Launch argv preview: **ABSENT** (the plan argv is not sent to the UI; `LaunchConfig.engineArgs` exists in Swift but not in tick). Add `preview{args[],restart}` per profile in the tick.
- **MEMORY / CACHE / COMPUTE / API (version-gated option set):** PARTIAL.
  - Option defs are EXISTING and version-gated: `profileOptionDefinitions(version:)` 2528–2535 → `cfg.option_defs`; grouped via `OptionDef.group` (`memory|cache|compute|network|model`, the `group` field in `OptionDef` 573–600). `cfRenderOptions` 801–839 renders by group in `option-group` 147–152 blocks. So the group data exists; the **tab UI** does not.
  - Stale-option preservation: EXISTING (`staleKeys`, 806–812).
  - ANE toggle: PARTIAL. ANE is `profile.options.ane` (bool) and a global `#aneOn/#aneOff` (289–298) in the global Compute block (not per profile, which conflicts with §3 / spec: compute is per-profile — **design conflict to flag**: spec §3 puts ANE in profile COMPUTE; current code puts it global at 292–298 and writes to `profiles[0]` 690).
  - KV cache size: EXISTING as `max_cache_disk`/`max_cache` option defs (593–595).

### §4 Model chooser modal
- **Overlay + blue-framed panel, CHOOSE MODEL title, × close:** ABSENT. Only `#cfgModal` (first-run) 327–335 pattern (`#cfgModal` CSS 110–114 is reusable: `position:fixed; inset:0; background rgba(3,3,6,.72)` — spec wants 70% black, close enough; `.card` border-top 6px blue 111).
- **Search input with HF-id filter over downloaded models:** ABSENT. JS filter over `cfModels()` 719–721 is possible with no backend change.
- **Source filter caps ALL·N / LM STUDIO·N / HF HUB·N:** ABSENT (counts derivable from `cfg.folders[].models`).
- **Model rows (name mono, source · size right, MATCH tag):** PARTIAL — no size (ABSENT in ModelEntry 359–365; need `size_bytes` added to `enumerateModels` 395 and `modelTickState`); name/source present.
- **Note line "HF ID MATCHES A DOWNLOADED MODEL…":** ABSENT (text only).
- **CANCEL / OK:** ABSENT. Current `#profileModels` selection (JS) — need to confirm how it sets `profile.model`; `cfg` select is immediate in the list, so spec "confirm with OK" is a behaviour change (JS only).

### §5 Behaviour (binding)
- **Everything auto-saves; no save buttons (D14/D15):** PARTIAL. `#btnCfgSave` 300 "Save" and `#btnProfilesSave` 322 "Commit" still exist — **violates spec** (must remove). `config.save` is the only writer (624).
- **Never auto-restart (D5); RESTART NEEDED pill; restart button armed; prompt with in-flight count:** PARTIAL. `btnRestart` text changes to "RESTART TO APPLY" (500); prompt in profile section `#profileRestartPrompt` 323–324 with `cfg.in_flight` (751). Missing the red RESTART NEEDED capsule in footer row 1. Restart semantics correct (532 gates on `restart_required` and reveals prompt).
- **Activation commits drafts first, one atomic save, then active-id + `last_used_at` stamp (D14):** EXISTING in Swift for activate (`activateCandidate` 615–619, `startupActivation` 2435-ish, `last_used_at` stamp per D13 comment). JS 855–860 sends `config.activate{doc, profileId}`. Reply path `window.__cfgSave` unverified.
- **Profile CRUD add/clone/delete persisted:** PARTIAL. Add/clone/remove are JS-only drafts (`cfNewProfile` 772–798) and persist only via `config.save`/`config.activate`. Backend: `activateCandidate`/`saveCandidate` exist; no dedicated add/clone/delete commands (design says persist through config; acceptable). Guard: delete active profile — check JS (remove button 310); guard not verified.
- **`restart_required` from plan signature, never stored (D13):** EXISTING (main.swift:1441–1445; signature 1632–1637; baseline 196–198). Adopt-path stamp **unverified**.
- **Unrunnable model/runtime: save allowed, peach `UNRUNNABLE — reason` cap, start refused pre-flight (D4):** EXISTING for profiles (`cfVerdict` 741–744 uses `.profile-cap.unrunnable` peach, 95). Start refusal: EXISTING (plan error → `launchError`; `start` 604). Engine-level peach cap: PARTIAL (`#engValid` text only).

### §6 Footer (blue swoop)
- **Green 07 divider on swoop arm line:** ABSENT (`#footer::before` is blue; no green divider).
- **Row 1: RESTART NEEDED red capsule (left, conditional), `( CONFIG ] [ V1 )` right-aligned:** ABSENT. Current footer is one row (336–341). Need new row: `cfg.restart_required` → red capsule; `CONFIG` dark cap and version cap (`cfg.engine.version`, teal/blue).
- **Row 2: `( START ] [ RESTART ] [ STOP )` segmented group, even, 3–4px gaps, square inner edges:** PARTIAL. Buttons 337–339 exist as `.btn` (rounded only at outer ends via `.btn:first-child`/`.btn:last-of-type` 135–136). Gap: `#footer` gap 5px (140) — close to 3–4px. `.btn.r` undefined (see B5). "Even margins" PID centering: ABSENT (PID group just follows grid; `grid repeat(3,max-content) 1fr`).
- **PID | <pid> dark segmented group centered:** PARTIAL. `#pidPill` 340 with `#pidLabel`/`#pidNum` (gray #888, black text per style 144; spec says dark — the existing gray is correct per AGENTS.md "PID pills black on gray" → keep gray; spec's "dark" conflicts with the project's pill notation; use existing gray).
- **APP-MANAGED dark capsule right-flush:** PARTIAL. `#envPill` 340 shows "APP-MANAGED"/"EXTERNAL"/"NOT RUNNING" (496), gray not dark.

### §7 Translation notes (fonts, sizes, colors)
- Fonts: EXISTING. `--display` / `--font` stacks in `:root` (panel.html 6–26 region; the grep shows `--display: "DIN Condensed","Avenir Next Condensed","Arial Narrow",sans-serif`, line ~14). Body font `Avenir Next` in `.tried`/`.engpath`/`#cfgModal p` (86, 113). Do **not** use the mock's font.
- Sizes: EXISTING 25px (`#settingsHeader` 34, `#header` title), 16px (`.section-heading` 115 uses 14px, `.btn` 132 uses 15px — conflicts with the 3-size rule; **design should use 25/16/11** — `.sec-h` 66 is 14px, `.btn` 15px, `.frow` labels 11px. Flag: existing sheet already uses 14/15/12/10/13 — the spec's 3-size rule is not what's shipped; engineer should map new text to 25/16/11 and not add sizes).
- Colors: EXISTING palette (see CSS list below).

### §8 Verification
- DOM test: EXISTING (`Tests/ui/panel.test.mjs`) — extend after line 127.
- Live smoke: EXISTING (`live_smoke.mjs`, `--round-trips`).
- Note: `./run_tests.sh` is the gate.

### §9 Out of scope
- Tray / notification surfaces; version-mapping table beyond needed; status telemetry.

---

## (a) New/changed Swift bridge commands (payload shapes)

Existing and sufficient: `config.get`, `config.save {doc}`, `config.validate {doc, validation_id}`, `config.activate {doc, profileId}`, `browse {context}`, `config.scan {id}`, `config.firstRunDone`, `start`, `stop`, `restart`.

**New / changed (needed by spec):**
1. `config.save` / `config.validate` — unchanged payload; **add** `globals.host`, `globals.allowed_hosts[]`, `globals.allowed_origins[]`, `globals.web_ui: bool` (schema change; `configData` 2302–2345, `decodeGlobals` 2110–2135, `validateConfig` 2459–2610). Swift JSON trap: discriminate `Bool` via CFGetTypeID for `web_ui`.
2. **New** `model.list {}` → optional, since models already come in tick `cfg.folders[].models`; instead **change tick**: add `size_bytes` (number|null) per model in `modelTickState` (1440–1460) and `enumerateModels`/`ModelEntry` (359–365, 395–460) via `fileSize` injection (new closure param; keep pure, D1 T1 closures).
3. **Tick change** (`main.swift:1380–1490`): add `cfg.profiles[].preview{args:[String], restart:Bool}` built from `planLaunch` per profile (LAUNCH PREVIEW). Requires running `planLaunch` per profile (currently only active).
4. **Tick change**: add `cfg.engine.arch`, `cfg.engine.os`, `cfg.engine.verdict` (`valid|unrunnable|fallback`) and `cfg.engine.ladder[]` (from `resolveKit` tried list). `cfg.engine.version` exists.
5. **Tick change**: `cfg.restart_required` exists (1442); add `cfg.restart_pending_summary` not needed.
6. **Config key** `profiles[].options.ane` exists; per spec ANE is per profile. Remove global `aneOn/aneOff` from globals (handlers 690–692; global block 292–298) — or keep global only as a view. **Decide**; spec says per profile.
7. **Profile CRUD**: no new Swift command needed if JS drafts persist via `config.save`/`config.activate`. If the engineer wants Swift-side clone/delete, add `profile.clone {id}`, `profile.delete {id}`, `profile.add {template}` (ABSENT). Spec §5 says "add from a template" — **template list ABSENT** (no template definitions in ui_logic; defaults only in `defaultConfig` 2349–2396).
8. **Model chooser**: JS-only (search filter over tick models). No new command. For `size`, see (2).
9. **Remove** `#btnCfgSave` and `#btnProfilesSave` (no command change).

## (b) Recommended implementation order
1. Fix pure logic first (Swift tests `run_tests.sh`): schema additions (host, allowed_hosts/origins, web_ui with CFBoolean discrimination), `size_bytes` in ModelEntry, per-profile preview in tick, engine arch/os/verdict in tick. Add `Tests/main.swift` cases.
2. Panel layout skeleton: header peach bar + green/lilac rail + 06/07 section structure, reusing `.sec-h`, `.capbtns`, `.frow`, `.mini`, `#footer::before/::after`, `.broken` divider (ABSENT, build from `.track` gradient 124 pattern).
3. Global section: column-1 selector (ENGINE/FOLDERS/NETWORK) + column-2 panels, moving existing ids (`capAuto`…`btnCfgSave`) into them, removing Save.
4. Profile section: column 1 list (`cfRenderProfiles`), column 2 tabs (GENERAL/MEMORY/CACHE/COMPUTE/API from `group`), column 3 editor (`cfRenderOptions`), move ANE to COMPUTE per profile.
5. Model chooser modal (`#cfgModal` pattern), search filter, source caps, OK/CANCEL.
6. Footer rows: RESTART NEEDED row + CONFIG|version row + existing 2nd row; fix `.btn.r`.
7. DOM tests in `panel.test.mjs` after line 127 for each new id; live smoke round-trip for save→restart.

## (c) Existing CSS to build with
- **Custom properties (`:root`, panel.html 6–26):** `--bg #050508`, `--bg2 #0b0b12`, `--track #191d33`, `--orange #ff7700`, `--orange-dim #7a3b00`, `--teal #88ccff`, `--teal-dim #33618`, `--peach #ffcc99`, `--gray #ccaa88`, `--gray-dim #666688`, `--white #ffebde`, `--red #dd4444`, `--yellow #ffcc33`, `--green #33cc99`, `--lavender` (used 127 for thead; value in `:root`), `--display` (DIN Condensed …), `--accent` (per-section; `.settings-panel{--accent:#4455ff}` 64), `--lilac #cc88ff` (used by `.requests-panel` 63; **lilac exists** — spec's global lilac can use `var(--lavender)` or the `--lilac` value; the mock uses `#cc88ff` — verify `:root` has it), `#4455ff` (blue, hard-coded in many places — no var).
- **Section rail + heading:** `.section-heading, section > .label:first-child` 115–117; `.settings-panel .sec-h` 66–67 (flex, space-between).
- **Broken-line divider:** `.track::after, .bar::after, .seg::after` 124 (repeating gradient 34px/3px black breaks). Not a "section::after" in the app; build `section::after` by reusing that gradient, 4px tall, section color.
- **Caps / segmented:** `.capbtns` 68, `.cb` 69, `.cb.on` 70, `.cb:first-child/:last-child` 71–72 (rounded outer ends only, 14px).
- **Pills:** `.profile-cap` 93 (peach radius 14px), `.profile-cap.runnable` 94 (teal), `.profile-cap.unrunnable` 95 (peach), `.warn-cap` 96; gray pill `#pidPill .h`/`#envPill` 144 (`#888`, black text).
- **Fields:** `.settings-panel input[type=text|number]` 73–76 (`--track`, white text, no border, radius 0), `.settings-panel input:focus-visible` 77.
- **Buttons:** `.btn` 132 (28px min-height, 15px, radius 0), `.btn.gr` 133, `.btn.y` 134, `.btn:first-child` 135 (14px left), `.btn:last-of-type` 136 (14px right), hover/active 137–138. `.mini` 78–80 (22px min, 12px, `.mini.del` red tint).
- **Tabs:** none in the app (ABSENT). Use `.cb` segmented pattern vertical for tabs.
- **Swoop:** `#footer::before` 141 (42px left border + 12px bottom border, bottom-left radius 58px/38px), `#footer::after` 142 (12px bar, right radius 6px), `#header::before` 52.
- **Modal:** `#cfgModal` 110–114 (fixed overlay, `.card` 420px, blue top border 6px, `h3` display 18px, `p` Avenir 11px, `.btns` flex-end gap 8px).
- **Fonts:** `--display` for headings/caps; body `"Avenir Next","Helvetica Neue",sans-serif` at 11px (`.tried` 85, `.engpath` 86, `#cfgModal p` 113). Mono: none declared in grep (the mock's `monospace`; use `font-family: ui-monospace, monospace`? — **no existing mono var**; the spec's mono values need a choice — the app uses display-condensed for values; ABSENT mono stack).
- **Sizes in use:** 10, 11, 12, 13, 14, 15, 18, 25 px (spec's 3-size rule not followed by existing code; new text should use 25/16/11).

## (d) Not expressible / conflicts with current machinery
1. **Lilac global rail and green profiles rail (§1, §2):** no lilac/green rail exists; lilac `--lilac` may exist (requests-panel); rails must be built as new markup. Expressible.
2. **Broken-line `section::after`:** the app has the gradient on meters only (`.track::after` 124); building a section divider is new CSS but feasible.
3. **Mono font:** no mono stack in `:root`; spec's mono values need a new stack (not a new size). Flag.
4. **3 font sizes (25/16/11):** existing code uses 10/12/13/14/15/18. Spec demands 25/16/11; the engineer must map or the spec's rule conflicts with shipped CSS.
5. **Per-profile ANE (§3 COMPUTE) vs current global ANE (292–298):** schema currently stores ANE per profile (`profiles[].options.ane`) but UI writes profile 0 only (690). Needs UI move.
6. **Network settings (HOST, ALLOWED-HOST/ORIGIN, WEB UI) are NOT in the schema:** config change required, plus Swift launch mapping (`allowed_host`/`allowed_origin` are `.append` OptionDefs at 595–597 — they must come from `globals` now, which is a change to `buildArgv` and the registry). `web_ui` OptionDef not found — may not be supported by the engine: **verify** before committing.
7. **Eye toggle for API key:** pure JS (no backend needed; the raw key is never in the DOM per D6 (`cfgKey` readonly, masked from `api_key_masked`); the eye needs the raw key — **conflicts with D6** (raw key must never render). Reveal requires either a backend `config.reveal_key` command returning the raw key on demand, or the eye is out of scope. Flag this as a decision.
8. **"APPLIES ON NEXT RESTART" note vs RESTART NEEDED pill:** AGENTS.md says config changes requiring restart show a red pill, never a note. Spec §2 ENGINE includes the note — **conflict**: follow AGENTS.md (pill).
9. **Model size and HF search over downloaded models:** size needs file-size enumeration injected into `enumerateModels` (new FS closure).
10. **Template for ADD PROFILE (§5 "from a template"):** no template list exists; needs a defined template set (`defaultConfig` options could be the template). Decision needed.
11. **Version-gated tabs (§3 "hide, not disable"):** `profileOptionDefinitions` already filters by version; tabs need the `group` field (exists). Expressible.
12. **Eligibility and engine verdict:** the `unknown` verdict is not a gate (1353 comments); spec's "FALLBACK MAPPING" needs `mapping_fallback` (present in tick 1437).
13. **Restart target version (spec: 1.3.0 never 1.3.1):** the registry has no pin; `contractFor` maps an unknown newer version to 1.3.2 with fallback. Not expressible without a registry change — flag.
14. **Save buttons removal (§5):** current `btnCfgSave` (300) and `btnProfilesSave` (322) must be deleted, and all `config.save` invocations made on change (JS `cfDebouncedValidate` 612 exists). Expressible.

---

**Items needing a direct re-read before implementation (unverified in this pass):** `resolveKit` body (ui_logic.swift:243–285); `ServerProc.adopt` stamp of `lastSuccessfulPlanSignature`; `window.__cfgSave` consumer in panel.html; `.btn.r` definition; `loadFileURL` for panel.html in main.swift; `cfg.version_too_new` computation; whether `--allowed-host`/`--web-ui` options and `--allowed-origin` are in contract131/132 option lists.