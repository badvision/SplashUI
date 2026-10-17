# SplashUI Settings Screen — Implementation Design Spec

Source of truth for the visual design: the approved SVG mock v50 —
`/tmp/mock/settings_panel.py` (renders `/tmp/mock/settings_panel.svg`; iteration
history in `/tmp/mock/DESIGN_LOG.md`).

**Framing (critical):** the mock is a *visual-language reference, not a
pixel-perfect doctrine*. Implement it with the app's EXISTING CSS/markup system
(its custom properties, `section` rail/divider pattern, caps/pills/fields, its
font stack, its canonical palette). Where the mock's exact pixels collide with
the app's conventions or feasibility, adapt — keep the structure, hierarchy,
and color *meaning*; change the pixel values. Report every adaptation in the
completion report.

Binding project decisions live in `AGENTS.md` (read it): theme discipline
(canonical vivid-classic palette, ≤3–4 colors each with assigned meaning —
blue=structure/nav, lavender=primary content, ice/teal=values/metrics,
peach=warning, green=healthy/action, red=error; 14px cap buttons; 3 font sizes
25/16/11; flat styled fields; 0.45s independent transitions), D3/D4/D5/D6/D9/
D13/D14/D15/D16, ANE default ON, config.json atomic writes.

One approved deviation: the mock gives the profiles section a **green** rail
(channel 07) vs AGENTS.md's "new settings surfaces use channel 06, blue accent".
Keep the mock's green — the user approved it — but map it to an existing CSS
variable (the app's green) rather than inventing a new palette entry.

---

## 1. Screen structure

Full-screen settings view inside the existing 520×800 borderless panel, same
window as the status view (switched via the header STATUS pill / existing view
mechanism in panel.html).

- **Header** (blue swoop band): "SPLASH SETTINGS" title (25px-class, bg-color
  on blue, letterspaced); `STATUS` dark capsule at the right edge (click → back
  to status screen); a peach bar below carrying the active profile dash model
  name (`QWEN3.8-27B - INCOAI/QWEN3.8-27B-SPLASH`, mono, bg-color on peach);
  a green engine-state pill at the right end of the peach bar (IDLE / RUNNING
  etc. from the tick).
- **Left rail** (full page height, 42px): lilac segment (channel 06, global)
  from the header line; green segment (channel 07, profiles) below. Channel
  numbers (23px-class bold, bg-color) right-aligned near the base of each
  segment, like the status screen's channels.
- **Section dividers**: the app's `section::after` broken-line pattern (three
  segments, 4px, section color) at the bottom of EACH section — lilac ending
  06, green ending 07. The 07 divider sits on the line where the blue footer
  swoop's left arm meets the rail (v50).
- **Footer** (blue swoop C-band: left rail column + bottom band, rounded
  inner/outer elbows, exactly like the status screen's swoop): two control
  rows, see §6.

## 2. Global section (06, lilac)

Section heading "GLOBAL SETTINGS" (16px-class bold, lilac). Finder-style
two-column layout:

- **Column 1** (narrow): three selectable rows — `ENGINE`, `FOLDERS`,
  `NETWORK`. Selected = lilac fill/black text, only the outer-left corners
  rounded; unselected = dark fill/white text. Selection drives column 2.
- **Column 2** (detail area):
  - **ENGINE** (sub-heading, teal):
    - `AUTO | MANUAL` segmented caps (selected = lilac). AUTO = the app's
      existing discovery ladder; MANUAL = user path.
    - Engine path pill (mono path, truncated) + `BROWSE` cap (folder picker).
      Validate the chosen folder is a real Splash install; show the discovery
      ladder line, the detected version (teal, from `release.json` — never
      `VALID` (green — any engine version is supported; built-against vs
      running version is an informational tip) / peach `FALLBACK MAPPING`
      (no authored mapping for the running version — the registry report is
      the tip) / red `UNRUNNABLE — reason` (D3).
    - "APPLIES ON NEXT RESTART" mono note, shown only while the pending change
      differs from the running plan (D13/D5).
  - **FOLDERS**: the model-folder list — rows of mono path + source tag
    (LM STUDIO / OLLAMA / HF HUB / SPLASH) + per-row remove; `+ ADD FOLDER`
    row. Common locations auto-detected on first run (LM Studio library,
    Ollama blobs, Hugging Face cache, Splash's own download dir). Folders feed
    the profile model chooser.
  - **NETWORK** (sub-heading, teal): flat fields (label + dark input, mono
    values, gray placeholder = unset default): HOST, PORT (steppers),
    API KEY (masked + eye toggle; never rendered in plaintext, D6),
    ALLOWED-HOST, ALLOWED-ORIGIN. `WEB UI ON | OFF` caps (selected = lilac).
    All network settings are global, never per-profile (D6).

## 3. Profiles section (07, green)

Section heading "PROFILES" (green). Three Finder-style columns:

- **Column 1**: profile rows (name, 26px-class) + `+ ADD PROFILE` at the
  bottom of the list (same alignment/color family). Selected row = dark green
  shade, white text, left corners rounded; the *active* profile carries a
  small bright dot at the row's right edge.
- **Column 2**: `PROFILE SETTINGS` title bar spanning the editor width (green,
  bg-color text, rounded top) above the open-right frame; below it the five
  tab rows: `GENERAL`, `MEMORY`, `CACHE`, `COMPUTE`, `API` (36px-class,
  selected = black bg/white text with green shoulder, unselected = green
  bg/black text). Selected profile drives column 3.
- **Column 3** (detail, open-bracket frame: top+left+bottom green border,
  rounded right cap, open on the right per the mock):
  - **GENERAL**: `PROFILE` label; `ACTIVATE | CLONE | DELETE` segmented caps
    (activate = green); model pill (`MODEL | name | CHANGE`, name segment
    width-constrained) → opens the model chooser modal; package/draft line
    (mono teal: whether the runtime has a matching drafter, e.g.
    `--draft package --kv 16`); metadata line `CREATED <date> · USED <date>`
    (mono, dim); `LAUNCH PREVIEW` box (dark, rounded: teal heading, rule,
    the two-line mono launch command the profile would produce — includes
    `· RESTART` when it would change the plan).
  - **MEMORY / CACHE / COMPUTE / API**: the profile's remaining launch
    options as flat fields / caps / toggles, in the app's field idiom.
    **Version-gated**: the option set comes from the engine-version mapping
    (D3); settings that don't apply to the selected runtime are hidden, not
    disabled. ANE toggle defaults ON and never off in defaults/seeds/tests.
    KV cache size and the other options the discovery phase identified live
    here.

## 4. Model chooser modal

Dark overlay (70% black) + blue-framed panel (rounded):

- "CHOOSE MODEL" (teal, letterspaced) + `×` close cap.
- Search input (full width, mono, placeholder `search · hugging face id…` +
  ⌕). Typing a HF id acts as a *filter over already-downloaded models*; a
  download does not start from the modal.
- Source filter caps: `ALL · N` (selected = accent), `LM STUDIO · N`,
  `HF HUB · N` (counts live).
- Model rows: name (mono) + `source · size` (mono, right). The row matching
  the search = accent bg/bg-color text + `MATCH` tag.
- Rule + dim mono note: `HF ID MATCHES A DOWNLOADED MODEL → SHOWN AS A
  SEARCH RESULT`.
- `CANCEL` (dark) + `OK` (accent) bottom-right. OK = select the model for
  this profile (auto-save → may set `restart_required`); it never loads the
  engine. Closes the modal; no "Load" label anywhere.

## 5. Behavior (binding — from AGENTS.md)

- Everything auto-saves on change; **no save buttons anywhere** (D14/D15).
- **Never auto-restart** (D5): a pending plan change shows the `RESTART
  NEEDED` pill + the RESTART button becomes armed; the app prompts with the
  in-flight request count and the user confirms. Saving/activating never
  restarts the engine.
- Activation commits unsaved draft edits first (one atomic save, then
  active-id change + `last_used_at` stamp) (D14).
- Profile CRUD: add (from a template), clone (copies settings + metadata),
  delete (active profile: guard), all persisted to config.json.
- `restart_required` computed from the plan signature (kit + version + argv +
  key), never stored (D13).
- Unrunnable model/runtime combo: save allowed, peach `UNRUNNABLE — <reason>`
  cap with the actionable fix; start refused pre-flight (D4).

## 6. Footer (blue swoop, v50 layout)

- Green 07 divider on the swoop-arm line (above the footer, bottom of 07).
- **Row 1** (just below the divider): `( RESTART NEEDED )` full red capsule
  (bg-color text) at the left — visible only when `restart_required` is
  true; `( CONFIG ] [ <version> )` segmented control right-aligned to the
  content edge — CONFIG dark cap, version cap accent blue (value from the
  running kit's `release.json`, e.g. `1.3.0`; mock shows a `V1` stand-in).
- **Row 2**: `( START ] [ RESTART ] [ STOP )` — one segmented group, even
  segments, 3–4px gaps between sections, square inner edges / rounded outer
  caps, colors green/yellow/red, bg-color text. Then `PID | <pid>` dark
  segmented group (value mono) centered in the space around it (even
  margins). Then `APP-MANAGED` dark capsule, right-flush with the version
  cap above. START/RESTART/STOP drive the engine lifecycle; PID shows the
  engine process (dash when stopped); APP-MANAGED marks app-launched vs
  adopted.

## 7. Translation notes (mock → app idiom)

- **Fonts**: use the app's existing `--display`/mono stacks, not the mock's
  Avenir Next Condensed.
- **Font sizes**: the app has 3 sizes (25/16/11). Map: mock 21px title→25,
  mock 14px headings→16, mock 8–11px labels/values→11 (mono may sit at the
  app's smallest). Do not add new sizes.
- **Colors**: map every mock color to the nearest canonical/app variable
  (blue, lilac, green, peach, red, teal, the app's dark neutrals). The mock's
  gray-dim pills → the app's existing dark-cap treatment (bg-color or white
  text per contrast). No new palette entries.
- **Geometry**: mock coordinates are proportion references for the 520×800
  window; express layout with the app's existing flex/section machinery.
- The status screen is frozen except: keep its existing footer row treatment
  — the settings footer intentionally mirrors it (same pill shapes/gaps).

## 8. Verification (binding)

- Every new/changed UI surface lands with passing DOM assertions in
  `Tests/ui/panel.test.mjs` (jsdom against the real panel.html + fake
  bridge) in the same change; `./run_tests.sh` green is the gate
  (Swift pure-logic suite + DOM layer).
- Extend `Tests/ui/live_smoke.sh` round-trips where feasible (SPLASHUI_SMOKE
  gated, deterministic, machine state restored) — the settings save/restart
  transition is the priority round-trip.
- Swift JSON trap: NSNumber bridges to Bool for any number — discriminate
  CFBoolean via CFGetTypeID where the config schema gains booleans.

## 9. Out of scope for this iteration

- Tray/notification-bar surfaces (frozen rules apply; don't touch).
- Engine-version mapping table authoring beyond what the version-gating needs.
- Any work on the status screen's existing telemetry.
