# SplashUI Settings Screen — Implementation Design Spec

Source of truth for the visual design: the approved `docs/design/settings_panel_2x.png`
and its geometry source `docs/design/settings_panel.py`. Current user overrides are
recorded in DESIGN_LOG v52–v55 and take precedence over the mock's two-row footer.

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

Settings uses an 820px-wide window; status remains 520px wide. Both share identical
header/footer structure and styling. Height remains status-driven and screen-clamped.
Global and Profiles have 270px / 390px minimum boxes and share spare height 2:3.
Their sizes depend on the window, not the selected tabs. At 820×820, their measured
heights are 273.59px / 395.41px with footer top 755px; all tabs fit without overflow.
Settings scrollbars are hidden throughout; smaller windows scroll internally.

- **Header**: one shared masthead DOM outside both views, retaining the status header's
  blue swoop, title slot, peach model bar and engine-state pill styling. The title is
  "SPLASH SETTINGS" in settings and "Splash interface control" in status. The same
  right-aligned control shows STATUS in settings and the menu icon in status. The peach
  bar carries active profile dash model; the state pill follows frozen status conventions.
- **Left rail** (full page height, 42px): lilac segment (channel 06, global)
  from the header line; green segment (channel 07, profiles) below. Channel
  numbers (23px-class bold, bg-color) right-aligned near the base of each
  segment, like the status screen's channels.
- **Section dividers**: the app's `section::after` broken-line pattern (three
  segments, 4px, section color) at the bottom of EACH section — lilac ending
  06, green ending 07. The 07 divider sits on the line where the blue footer
  swoop's left arm meets the rail (v50).
- **Footer** (blue swoop C-band: left rail column + bottom band, rounded
  inner/outer elbows, identical in status and settings): one control row, see §6.

## 2. Global section (06, lilac)

Section heading "GLOBAL SETTINGS" (16px-class bold, lilac). Finder-style
two-column layout:

- **Column 1** (narrow): three selectable rows — `ENGINE`, `FOLDERS`,
  `NETWORK`. Selected = lilac fill/black text, all four corners rounded;
  unselected = dark fill/white text. Selection drives column 2.
- **Column 2** (detail area):
  - **ENGINE** (sub-heading, teal):
    - `AUTO | MANUAL` segmented caps (selected = lilac). AUTO selects the highest
      valid installed Homebrew Splash version (numeric ordering, both standard prefixes).
      The legacy SplashUI-local kit is not an automatic default; MANUAL uses the exact user path.
    - Engine path pill (mono path, truncated) + `BROWSE` cap (folder picker).
      Validate the chosen folder is a real Splash install; show the discovery
      ladder line, the detected version (teal, from `release.json` — never user-set),
      `VALID` (green, no built-against annotation) / peach `FALLBACK MAPPING`
      (no authored mapping for the running version — registry report in its tooltip)
      / red `UNRUNNABLE — reason` (D3).
    - Saved plan changes flash the shared RESTART button; no save-state note.
  - **FOLDERS**: the model-folder list — rows of mono path + source tag
    (LM STUDIO / OLLAMA / HF HUB / SPLASH) + per-row remove; `+ ADD FOLDER`
    row. Common locations are added automatically only when their directories exist
    (LM Studio library, Ollama models, Hugging Face cache, Splash model directories).
    Missing paths are omitted. ADD validates directory existence before creating a row.
    Paths expand into available width and wrap, never truncating useful text.
    Folders feed the profile model chooser.
  - **NETWORK** (sub-heading, teal): flat fields (label + dark input, mono
    values, gray placeholder = unset default): HOST, PORT (steppers),
    API KEY (masked + explicit eye reveal; never passively rendered in plaintext, D6),
    ALLOWED-HOST, ALLOWED-ORIGIN. `WEB UI ON | OFF` caps align with the input fields above (selected = lilac).
    All network settings are global, never per-profile (D6).

## 3. Profiles section (07, green)

Section heading "PROFILES" (green). Three Finder-style columns:

- **Column 1**: profile rows (name, 26px-class) + `+ ADD PROFILE` at the
  bottom of the list (same alignment/color family). Selected row = dark green
  shade, black text, left corners rounded; the *active* profile carries a bright dot.
  The selected row opens into column 2; the first row's top edge is flush with the
  title bar and its lower-right corner swoops downward. No decorative blue blob.
- **Column 2**: `PROFILE SETTINGS` title bar spanning the editor width (green,
  bg-color text, rounded top) above the open-right frame; below it the four
  tab rows: `GENERAL`, `MODEL`, `MEMORY`, `API` (36px-class,
  selected = black bg/white text with green shoulder, unselected = green
  bg/black text). Selected profile drives column 3.
- **Column 3** (detail, open-bracket frame: top+left+bottom green border,
  rounded right cap, open on the right per the mock):
  - Every tab is a single-column panel. The only column split is the existing
    profiles / tabs / settings layout; no nested two-column option grids.
  - **GENERAL** contains profile name and ACTIVATE / CLONE / DELETE, created/used
    metadata, the two unchanged per-profile compute controls (ANE and idle sleep), and
    complete LAUNCH PREVIEW. There is no redundant Profile heading or generated-id row.
    Restart confirmation is reachable here through the shared flashing RESTART control.
  - **MODEL** is its own tab, not a sub-section in GENERAL. It contains the model pill
    and CHANGE, drafter/package facts, draft-model, revision and all other model-axis
    options. The redundant Model heading is removed.
  - **MEMORY** contains memory options followed by a broken section divider and
    CACHE options. CACHE and COMPUTE no longer have their own tabs. API retains
    API/request options; reasoning-effort choices flex-wrap instead of overflowing.
  - Option keys, registry groups, bridge messages and persistence are unchanged;
    this is UI grouping only. Version gating still hides unavailable controls.
  - Reset appears only for an explicitly provided non-null option, including false
    or a value equal to the default. Unset options have no visible reset button.
    Reset is a rounded black-on-gray pill. Unset values show gray placeholders;
    unset toggles select the effective default. ANE remains per-profile, default ON.
  - Profile frame, selected-tab shoulders, connector and lower corners use rounded
    elbows; the outer frame clips to a continuous rounded boundary, not sharp notches.

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
- **Never auto-restart** (D5): a pending plan change flashes the RESTART button
  with tooltip “Settings saved. Changes take effect after the engine restarts.”
  There is no RESTART NEEDED pill. Flashing stops on restart or a cleared pending
  state. The app still prompts for confirmation with the in-flight request count.
- Activation commits unsaved draft edits first (one atomic save, then
  active-id change + `last_used_at` stamp) (D14).
- Profile CRUD: add (from a template), clone (copies settings + metadata),
  delete (active profile: guard), all persisted to config.json.
- `restart_required` computed from the plan signature (kit + version + argv +
  key), never stored (D13).
- Unrunnable model/runtime combo: save allowed, peach `UNRUNNABLE — <reason>`
  cap with the actionable fix; start refused pre-flight (D4).

## 6. Footer (shared one-row layout, v52)

- Green 07 divider ends the profile section immediately above the blue swoop.
- One row in both views: `( START ] [ RESTART ] [ STOP )`, then `( PID ] [ number )`,
  then `( APP-MANAGED / EXTERNAL )`, then right-aligned `( CONFIG ] [ version )`.
- Action colors remain green/yellow/red. PID, ownership, CONFIG and version use
  black-on-gray pills. Segments have 3–4px gaps, square inner edges and rounded
  outer caps. PID is centered between its neighbors. The footer has no gray fill.
- Pending changes flash RESTART rather than reserving a separate warning row.
  Restart preserves session continuity by re-executing the current plan.

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
