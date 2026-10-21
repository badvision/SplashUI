# SplashUI Settings Panel — Design Log

Source of truth for every design delta. Newest last. Mock: /tmp/mock/settings_panel.py
(renders settings_panel.svg / settings_panel_2x.png). Reference app: Resources/panel.html.

## Decisions

- v1: 520-wide single mock; real :root palette, 42px accent bars, condensed type.
- v2: framed to match status page — top swoop (42 left + 28 top, outer radius 58x48),
  bottom swoop (42 left + 12 bottom, outer radius 58x38), title bar "SPLASH SETTINGS"
  with STATUS back-cap, peach model strip + 100px state pill (2-row header grid).
- v3: outer-corner swoop shape corrected (was rounding the inner elbow); 2-row header.
- v4: two scroll positions shown side by side (top / scrolled, footer pinned).
- v5: NO SCROLLBAR requirement. Consolidation + LCARS tabs 06 GLOBAL / 07 PROFILES.
  Network/Compute collapsed to single label+controls rows.
- v6: vertical rhythm tuned; dim SYS-xx status readout pinned above footer;
  removed redundant PROFILES heading.
- v7: locked per-row y positions; added dim LAUNCH preview line on Global.
- v8: tab row restored (was dropped by a bad edit); both tabs fit 520x800, approved layout baseline.
- v9: TABS REMOVED (not star-trekky). Finder-style column navigation:
  - GLOBAL: col1 = section list (ENGINE / FOLDERS / NETWORK / COMPUTE); col2 =
    details of the selected section.
  - NETWORK now carries: host, port, api-key, allowed-host, allowed-origin, Web UI
    toggle (moved out of profile scope).
  - PROFILES: col1 = profile list + "+" add; col2 = section list (GENERAL / MEMORY /
    CACHE / COMPUTE / API) in a swoopy blue frame NOTCHED into the selected profile
    row; col3 = section details.
  - GENERAL: editable model name, ACTIVATE / CLONE / DELETE, CHOOSE MODEL -> modal
    (search filter, HF identifier, source caps, model list, LOAD).
  - NO SAVE BUTTONS. Every change persists immediately; a running engine picks up
    changes only on restart (hint lines + SYS readout say so).
- v9.1: geometry fixes — profile row name 9pt + caps fit 120px col1 (model string
  dropped to 2nd line of row only where it fits); blue editor frame shortened to
  end ~588 (was clipping footer/status); modal overlay limited to content area
  (footer stays live under dim); "PROFILE EDITOR · DRAFT" label moved above frame
  top edge to avoid colliding with the QWEN3.8-27B readout.
- v9.2: GENERAL detail column filled: CREATED / LAST USED readouts (spec: profiles
  capture created + last-used) and a dim LAUNCH preview line (splash --model …
  --draft package --kv 16). Content now fills the editor frame.
- v9.3: COMPUTE removed from Global scope — ANE/compute settings live ONLY in a
  profile (COMPUTE section under a profile). Global col1 = ENGINE / FOLDERS / NETWORK.
- v9.4: Editor frame reworked to an OPEN-RIGHT bracket (top/left/bottom only):
  thick top bar carries the PROFILE SETTINGS label (+ profile name right), matching
  the window title bar at sub-section scale. Profile list = label-only rows styled
  identically to Global col1, selected row highlights and bridges into the frame
  via a connector. Section list (GENERAL/MEMORY/CACHE/COMPUTE/API) rides directly
  on the accent left-border column (selected section = cut-out chip); detail
  column shifted right to clear it.
- v10: GLOBAL and PROFILES now VERTICALLY STACKED on the single 520x800 screen
  (no tabs, no separate screens). Col1 width shrunk 176 -> 136px. GLOBAL block on
  top (ENGINE/FOLDERS/NETWORK + details), thin divider, PROFILES block below
  (label-only list + open-bracket editor with PROFILE SETTINGS top bar, sections
  on the accent left border, detail column). Modal unchanged, centered lower.
  Frames: 01 global=engine, 02 global=network, 03 chooser modal.
- v11: Added the full-page 42px LEFT RAIL (header swoop to footer swoop, channel
  06 at the bottom), matching the main app's section rail. Section headings now
  use the main app's sec-h style: "GLOBAL SETTINGS" (config.json right) over the
  global block, "PROFILES" (+ ADD PROFILE mini button) over the profile block.
  The block separator uses the main app's BROKEN-LINE pattern (accent 0-58% /
  gap / 60-82% / gap / 84-100%, 4px) instead of a plain track line. The profile
  editor top bar is VERTICALLY ALIGNED to the selected profile row (was dropped
  below it). Editor bottom bar 564..572; content ends 546.
- v12: Left rail SEGMENTED at the broken line: purple (#4455ff, channel 06) for the
  GLOBAL half, green (#33cc99) for the PROFILES half. PROFILES heading + profile
  list rows + editor frame (top bar / section column / bottom bar) all use the
  green; the selected row, editor frame and section chips use a darker green
  shade variant (#1fa87b). "+ ADD PROFILE" moved from the heading row to the
  BOTTOM of the profile list column (pill under LLAMA-8B).
- v13: Global rail segment switched from blue (#4455ff) to LILAC (#cc88ff, the
  palette's --lavender, the main app's default section accent) so the page reads
  blue masthead / lilac global / green profiles. Each rail segment now carries
  its channel number at the bottom: 06 on lilac, 07 on green. The GLOBAL
  heading, selected section rows, and the broken-line section break all follow
  the lilac; profile-side stays green.

## Functional notes (not design)

- ACTIVE PROFILE INDICATOR: the white capsule dot at the right edge of a
  profile list row marks which profile is ACTIVE — i.e. the one the running
  engine would use — independent of which profile row is selected/being
  edited. No such indicator exists on the GLOBAL section rows (ENGINE/
  FOLDERS/NETWORK); there the selected state is the row background alone.
- Hugging Face identifier entered in the model chooser acts as a search filter:
  if it matches an already-downloaded model, that model shows up in the list.
- DEFAULT VALUES (functional, applies to every field on the panel):
  - Text boxes: if a value is unset, show its DEFAULT in the box, rendered in
    GRAY (dim). Set/entered values render in the normal teal/white.
  - Toggles (2-option, e.g. ON/OFF): if unset, the DEFAULT option must be the
    selected one.
  - Multi-select (several options): the capseg PILL convention (see CONTROL
    CONVENTION below). If unset, the default option is selected.
- CONTROL CONVENTION (replaces the old `seg()` note): every small-choice
  control on the panel uses the `capseg` PILL treatment — separate segments
  with a 5px gap, only the outer tips rounded, flat inner edges. Selected
  segment = section color (lilac for Global, green for Profiles); unselected
  = gray. Used for ENGINE (AUTO/MANUAL), WEB UI (ON/OFF), profile ACTIVATE/
  CLONE/DELETE, and the path|BROWSE, model|CHANGE dual pills.
- TABBED TABS (unmocked): MEMORY, CACHE, COMPUTE, and API profile sections
  are not shown in the mockups and MUST follow the NETWORK tab's conventions
  as the default look — label at x=GD_X, input boxes via inb() at x=GD_X+108,
  full-width inputs where the value is a string, capseg pills for
  small-choice settings, eye glyph for masked fields, 28px row rhythm.
- TAB PANEL HEIGHT (implementation note, not mockable): the profile settings
  section must NOT collapse to fit the visible tab's content. It should occupy
  the space needed for the TALLEST tab so switching tabs never changes its
  height. The mock draws one static state, so this is carried as a note only.
- v14: Applied the spec in the mock: ENGINE (AUTO/MANUAL) and WEB UI (ON/OFF)
  converted from pill pairs to FOOTER-STYLE SEGMENTED CONTROLS (side-by-side,
  only outer corners rounded, black-on-section-color selected vs black-on-gray
  unselected). ALLOWED-ORIGIN in frame 02 renders its unset default (file://*)
  in GRAY to demo the default-value rule; frame 02 title flags "GRAY=default".
- v15: (a) Model-chooser modal confirm button renamed LOAD → OK: choosing a
  model does not load it — the profile is activated by ACTIVATE, so "LOAD" would
  mislead the user. (b) Profile section column now uses BLACK text for every
  section (was dim green / bright green). (c) The SELECTED section opens up to
  the right: its background row spans the full frame width (216→498), so the
  detail content no longer has a right-side green padding/border; content
  shifts down to y=P_ROW+58 to clear the opened row.
- v16 (corrects v15c): the selected section tab is a BLACK chip with WHITE
  text, confined to the section column — the green bar must NOT extend into the
  detail column (v15's full-width row looked wrong). Detail content starts at
  the selected tab's row (y=P_ROW+32); the unselected tabs keep black-on-green.
- v18: the selected-tab black chip is inset from the column's left edge so a
  GREEN strip remains to its left (chip at x=226, 10px green padding); text
  nudged to x=SEC_X+12. Right edge stays flush — no green bleed into details.

## Open questions

- (none yet — user iterating)
- v20: swoopy left ends — top bar, selected-tab chip, and bottom bar now use
  left-rounded corners (radius 12) so their left edges form a continuous curve
  (helper `lround(x, y, w, h, r, fill)` draws a rect with only left corners
  rounded). Right edges stay square/flush against the detail column.
- v21 (reverts v20): swoopy left-rounded ends removed — the rounded black chip
  against the green column read as a notch/notched-corner artifact. Back to
  clean square edges: top bar, selected-tab chip, and bottom bar are plain
  rectangles (v19 geometry); `lround` helper removed.
- v22 (final tab shape, per user's annotated image): the SELECTED TAB is the
  swoopy element, not the top/bottom bars (which stay FLUSH/square). Tab is a
  single path (226→282, h=26) with all four corners rounded (r≈13/14):
  left corners where the green column meets the tab; right corners bulge
  PAST the column edge (268) and open into the detail column — the black
  region swoops open to column 3. Reverts the v20/v21 bar treatment.
- v23 (supersedes v22; checked against the supplied reference image):
  - Column 1's selected profile joins the square/flush title without a narrow
    connector neck; the lower junction curves into column 2.
  - GENERAL has a semicircular black left end, white text, and green left padding.
  - The green shoulders immediately above and below GENERAL round at column 2's
    right edge, opening into column 3. This is not a black capsule bulging right.
  - Title and bottom bar retain square left edges; detail content is not shifted.
  - Rendered at 2x and visually compared using a focused junction crop.
- v24: Vertically centered column-2 labels in their 26px tab areas; baseline
  moved up 3.7px. Curves and horizontal positioning unchanged. Render checked.
- v25: Rounded PROFILE SETTINGS frame's outer bottom-left and inner black
  bottom-left corners. Rounded right endcaps on the page header and PROFILE
  SETTINGS title row; left title junction stays flush. Replaced the footer's
  stepped/overlapping bottom-left shapes with one continuous curved elbow.
  Rendered at 2x and inspected the full first frame; GENERAL opening unchanged.
- v26: PROFILE SETTINGS starts at DT_X, aligned above column 3's content.
  Removed the redundant profile-name label at the header's right edge.
  Re-rendered and visually checked the heading crop.
- v27: Rounded column 3's inside upper-left corner beneath the title, blending
  into GENERAL's upper shoulder without a seam. Kept MODEL NAME clear and all
  text positions unchanged. Re-rendered and visually checked the corner crop.
- v28: GENERAL reordered: PROFILE row (ACTIVATE/CLONE/DELETE) first, then MODEL
  pill (MODEL | name | CHANGE). All 3-up rows are true segmented controls: only
  the outer tips rounded, inner edges flat. MODEL pill resized 40/124/56 to fit
  the 220px column (name at 8pt). LAUNCH PREVIEW is now a labeled boxed panel
  (BG2, teal heading + divider). Frame extended to P_ROW+248 so the launch box
  no longer overlaps the bottom green edge; bottom edge right tip is rounded.
  Rendered at 2x; visually checked column, frame bottom, and footer clearance.
- v29: Model pill segments now separated by 4px gaps (each segment fully
  capsule-rounded; 46/112/54). Active profiles in col 1 show a bright white
  capsule dot at the row's right edge (lrow indicator). Rendered at 2x;
  visually checked the indicator and pill gaps.
- v29.1: Model pill corrected to match the ACTIVATE row treatment (user
  feedback: v29 over-rounded every segment). Now capseg left/right tips, flat
  inner edges, 5px gaps, sizes 42/112/56. Rendered at 2x; visually checked
  against the ACTIVATE row.
- v29.2: Model pill reduced to two segments (name | CHANGE, 159/56) — the
  MODEL section label already names the row, so the third "MODEL" segment was
  redundant. Rendered at 2x; visually checked.
- v30: WEB UI toggle reworked from the old contiguous seg() to the capseg pill
  treatment (ON | OFF, 84/85, 5px gap); ON selected state uses LILAC to match
  the GLOBAL section color. Rendered at 2x; visually checked the toggle.
- v31: ENGINE section converted to pill treatment. AUTO | MANUAL as two capseg
  segments (128/128), MANUAL (selected) in LILAC. Path is a dual pill:
  path | BROWSE (152/63, 5px gap), BROWSE white text at the right tip —
  replaces the separate Browse mini-button. Subsequent rows shifted down
  (LADDER 200, version 216, restart hint 238); all clear the 306 break.
  Rendered at 2x; visually checked.
- v31.1: Removed the old contiguous seg() widget — its only callers (ENGINE
  AUTO/MANUAL, WEB UI) are now capseg pills, so it was dead code. cap/mini
  retained (modal). Re-rendered; output unchanged.
- v32: Header status strip now reads "[active profile] - [model name]"
  (QWEN3.8-27B - INCOAI/QWEN3.8-27B-SPLASH) at 8.5pt bold. IDLE is now a
  green capsule (x 414..502, y 34..52) matching the peach strip height,
  rounded right end via A9 arc; previously a flat 24px-tall rect.
- v33: Profile frame bottom band thickened 8 -> 12px and its right end is
  now a rounded capsule (A6 arcs, tip at x=498) instead of a flat corner.
  Rendered at 2x; both visually checked.
- v34: ENGINE: AUTO | MANUAL slimmed (95/115, was 128/128). Engine path pill
  now full-width (path | BROWSE = 213/64, spans the detail column to x 498).
- v35: NETWORK: WEB UI ON | OFF slimmed (58/58, was 84/85). ALLOWED-HOST and
  ALLOWED-ORIGIN inputs made full-width (iw=174, span to x 498). API KEY
  input widened to 150 with a teal eye glyph (reveal/hide) at its right.
  Rendered at 2x; both sections and the eye visually checked.
- v36: The active-section indicator (white capsule dot) is REMOVED from the
  GLOBAL section rows (ENGINE/FOLDERS/NETWORK) — that dot read as "active" but
  the global row only marks the selected sub-section. The dot now means "which
  PROFILE is active, regardless of which profile is being edited" and is kept
  only on the profile list rows. `lrow()` gained a `dot=True` flag; global
  rows pass dot=False. Rendered at 2x; both lists visually checked.
- v37: All column-1 rows (global ENGINE/FOLDERS/NETWORK and profile list) now
  have rounded corners (r=8, arc-based path in `lrow`). Exception: the SELECTED
  profile row rounds only its LEFT corners (`lr=True`) so its right side stays
  square/flush where it joins the PROFILE SETTINGS top bar. Rendered at 2x;
  both column-1 lists visually checked.
- v38: "+ ADD PROFILE" converted from a TRACK capsule (centered text) to a
  plain off-row via lrow — same BG2 color, left-aligned text, same height and
  r=8 rounding as the other profile list rows. Rendered at 2x; checked.
- v39: The header swoop's INNER corner (where the top band meets the left
  column, at (42,28)) is rounded: the edge eases from the 28px band into the
  column with a Q-curve (L56 28 Q42 28 42 42, r=14) instead of a sharp 90-degree
  notch. Outer corners unchanged. Rendered at 2x; visually checked.
- v40: The blue footer band's RIGHT EDGE is rounded: the 12px-thick band
  (y 788..800) now ends in a PERFECT capsule cap - a single semicircle,
  r=6 centered on the band midline (A6,6 514,788 -> 520,794 -> 514,800).
  First pass (r=11) read as droopy because the arc radius exceeded the band
  half-thickness. Rendered at 2x; cap zoom-checked for a true semicircle.
- v41: Dropped the "config.json" annotation from the GLOBAL SETTINGS heading.
  The global detail column (ENGINE and NETWORK) now top-aligns with the
  GLOBAL SETTINGS label: sub() sub-labels moved to baseline y=94 (was 112),
  first control row at y=110, all rows shifted up 18px. Rendered at 2x;
  alignment visually checked in both global views.
- v41b: Visual re-verify: in the ENGINE view the ENGINE row is highlighted with
  the ENGINE detail (AUTO/MANUAL at y=110, path pill, LADDER, VALID); in the
  NETWORK view the NETWORK row is highlighted with the NETWORK detail (HOST at
  y=110). Both detail sub-labels sit on the GLOBAL SETTINGS baseline. The two
  views are consistent; no overlap with the column-1 rows.
- v42: Added a 5px gap above the PROFILE label in the third (detail) column -
  content start moved from P_ROW+32 to P_ROW+37 (13px clear of the top bar's
  bottom edge, was 8px). The open-right frame grew 5px taller to compensate:
  bottom band P_ROW+248 -> P_ROW+253, keeping the 20px padding under the LAUNCH
  PREVIEW box. Tab labels (GENERAL/MEMORY/...) are positioned independently, so
  they stay aligned. Rendered at 2x; top-bar gap and frame bottom both checked.
- v43: Section tab labels (GENERAL/MEMORY/CACHE/COMPUTE/API) are now centered
 in their container instead of left-anchored at 12px inset: unselected tabs center
 in the green column (216..268, mid 242); the selected tab centers in its black
 chip (226..278, mid 252). Fixes COMPUTE's 12px-left/0.5px-right imbalance
 (now ~6px each side) and GENERAL's 2px-left/14.5px-right chip imbalance (now
 ~8px each). No label grows toward the third column.
- v44: Selected GENERAL tab: left cap and label shifted 5px left (left arc
 226->221, text center 252->247) while the right side stays flush with the
 detail column (shoulders at 268, right edge 278) as before. First attempt
 shifted the whole chip left, leaving the right edge floating off the detail
 column - reverted; only the left cap and text move.
- v45: Left rail (06/07) now stops at FY-12, above the footer - the blue
 swoop's left edge rises to meet it instead of the rail running to the frame
 bottom. Status line: dropped "SYS-06" and "PERSISTED"; now two pills -
 "CONFIG | V1" (black on gray) and "RESTART NEEDED" (black on red), replacing
 the "applies on restart" text. Footer: START/RESTART/STOP are black-on-gray
 capsule pills (was green/yellow/red), PID ### is a black-on-gray pill
 (label+value, like the ON|OFF web-up pill), APP-MANAGED is black-on-gray.
- v46: Corrected v45 mistakes: (1) 07 rail end raised 14px more (FY-26) so it
 clearly stops above the footer; swoop left edge rises to meet it. (2) CONFIG
 | V1 is now a segmented control in the ON|OFF treatment (outer tips rounded,
 black text; V1 selected = accent blue, CONFIG unselected = gray), not one
 pill. (3) START/RESTART/STOP restored to their original per-action colors
 (green/yellow/red capsules) - v45 wrongly grayed them. (4) PID pill widened
 to 76px so 23181 no longer clips; "PID" label uses the same pill font (10px
 bold condensed) as the other pills, value stays monospace; APP-MANAGED
 shifted to 346.
- v47: Adopted pill-shape notation: ( ) = rounded caps, [ ] = square inner
 edges. Row 1: ( RESTART NEEDED ) full red capsule at left; ( CONFIG ] [ V1 )
 segmented control right-aligned to the content edge (498) - V1 selected in
 accent blue, CONFIG gray. Row 2: ( START ] [ RESTART ] [ STOP ) one segmented
 group of even 50px segments (green/yellow/red kept), 24px gap, ( PID ] [ ### )
 segmented gray group (value monospace), 24px gap, ( APP-MANAGED ) gray
 capsule. Removed the now-unused fbtn helper.
- v48: 4px gap between pill sections (was flush): row-1 CONFIG|V1 keeps its
 right edge at 498 (grows left, CONFIG at 394); row-2 groups keep their left
 edge at 66 and grow right, inter-group gaps recomputed to 24px (PID group
 248..334, APP-MANAGED at 358..468).
- v49: (1) APP-MANAGED right-flush with V1 (388..498). (2) PID|### group
 centered with even margins in the space between STOP and APP-MANAGED
 (263..349). (3) Row 1 moved down 10px (FY-38 -> FY-28). (4) Gray fills
 removed from footer unselected segments: CONFIG, PID|###, APP-MANAGED now
 use near-black BG2 fills with white text (no light gray). (5) Green broken-
 line section divider added at the bottom of the 07 rail segment (FY-30),
 mirroring the lilac divider that ends section 06.
- v50: Removed the gray TRACK line above row 1. Green 07 divider and the
 base of the 07 rail raised to FY-42 (the old track-line position, FY-44);
 the blue swoop's left arm top raised to FY-42 so it meets the green rail
 base exactly. 07 label moved up with the base (FY-54), keeping its 12px
 gap.

- v51 (user ruling, 2026-10-17): the app supports ANY engine version — the
  1.3.0 pin is retired as a verdict state. The ENGINE verdict cap is
  VALID (green) | FALLBACK MAPPING (peach, registry report as tip) |
  UNRUNNABLE (red). Built-against (1.3.0) vs running version is an
  informational detail carried in the verdict reason ("built against
  1.3.0; running 1.3.1") — information, never an alarm; the version pill
  shows the actual running version. The restart guard is unchanged: a
  restart re-executes the current plan (same binary/version as the
  running engine — session continuity).

- v52 (user overrides, 2026-10-17): removed the RESTART NEEDED pill in favor of
  flashing RESTART with tooltip “Settings saved. Changes take effect after the
  engine restarts.” Attention clears on restart or reverted changes. This supersedes
  the earlier black-on-red pill rule. Footer collapsed to one shared row in both
  views: START / RESTART / STOP, PID, ownership, CONFIG / version. Shared blue
  header now contains the title rather than placing it on black beneath the band.
  Settings width is 820px (status stays 520px); this keeps the profile/model controls
  and complete launch preview readable. Global and Profiles have fixed 230px and
  440px heights, with internal overflow; tab switches never resize either section.
  Chooser keeps explicit OK confirmation, source counts, MATCH tagging and no load.
  Removed the restart confirmation box's decorative peach left border: when the
  prompt starts below the scroll viewport it left a stray colored fragment beneath
  LAUNCH PREVIEW. Confirmation text/control remain scroll-accessible; RESTART flashes.

- v53 (user overrides, 2026-10-17): profile tabs are GENERAL / MEMORY / API.
  CACHE merges into MEMORY after a section break; COMPUTE is removed and its two
  unchanged per-profile settings move to GENERAL. GENERAL separates PROFILE
  identity/actions/history from the labeled MODEL sub-section (model chooser,
  package/drafter, draft-model, revision and other model-axis options).
  Reset is visible only for explicitly provided non-null settings, styled as a
  rounded black-on-gray pill. Reasoning-effort choices wrap. Settings scrollbars
  are hidden globally, while the reference layout itself fits without scrolling.
  Global grows to 270px; Profiles tightens to 390px. Settings widens to 1040px
  to fit the regrouped controls in compact two-column detail grids; status stays
  520px. Profile frame and selected-tab junctions use rounded elbows and corners.

- v54 (user clarification, 2026-10-17): supersedes v53's General model sub-section
  and nested grids. The final tabs are GENERAL / MODEL / MEMORY / API. MODEL
  owns model selection, drafter/package, every model-axis option and launch preview.
  GENERAL owns profile identity/actions/history and the two former Compute settings.
  All four detail panels are single-column; only profiles / tabs / settings form
  columns. MEMORY still includes CACHE after its section break. Compact rows keep
  the full option contract in the fixed boxes without scrolling.
  The single-column layout retains the previously accepted 820px settings width
  (the temporary 1040px nested-grid experiment in v53 is superseded). Status stays
  520px. Global and Profiles remain 270px / 390px, with no reference-size overflow.

- v55 (user clarification, 2026-10-17): replaces the lookalike settings header with
  the actual shared status masthead DOM; both views now use the same swoop, title
  slot, model/state row and right-aligned STATUS/menu control. The title changes by view.
  AUTO chooses the highest valid installed Homebrew Splash version numerically across
  both prefixes; the old SplashUI kit is no longer an automatic default. MANUAL resolves
  its exact path. Any current engine version is supported; VALID has no built-against note.
  Global navigation rounds all corners. Only existing common model folders are added
  automatically, missing paths are omitted, ADD checks existence first, and folder paths
  expand/wrap. Web UI caps align with the fields above. The selected profile opens
  directly into its green frame with a flush first-row top and rounded lower-right
  swoop; the failed blue connector is removed. Column-2 tabs sit below the editor elbow.
  GENERAL drops the redundant Profile/id row and regains LAUNCH PREVIEW and restart
  confirmation; MODEL drops its redundant heading. Tabs remain GENERAL / MODEL /
  MEMORY / API. The 820px settings width and 520px status width remain unchanged.
  Global/Profile minima are 270px / 390px; spare vertical room is distributed 2:3,
  eliminating dead space below 07 without any tab-dependent resizing. At 820×820,
  measured section heights are 273.59px / 395.41px and footer top is 755px across all tabs.

- v56 (user clarification, 2026-10-17): selected profile and its connector pieces
  stack above column-2 tabs and editor. Restored the black inside-corner swoops
  above/below the selected column-2 tab; only the failed blue junction blob stays
  removed. The green frame's top-right end is a 15px half-round cap and its 10px
  bottom edge ends in a 5px half-round cap, independent of the editor clipping.
  Model chooser is fixed at 460px wide by 75vh tall, with a flexible internally
  scrolling list and hidden scrollbars; empty, one-result and many-result states
  never resize or reposition the modal.

- v57 (user clarification, 2026-10-17): expose both inside-left 20px curves of
  column 3 against a green backing strip. Column-2 swoops use the same 20px
  radius; General starts 40px below the editor top, so its upper swoop's tip
  meets the editor's upper-left curve tip without a jagged vertical seam.
  The lower-left editor curve and the existing right-edge round caps remain visible.

- v58 (user clarification, 2026-10-17): column 2's upper-left outer corner is
  rounded by 20px when the second or a later profile is selected. The first
  selected row retains a square junction flowing directly into the title bar.
  Both the frame clipping and title bar follow selection without moving the layout.

- v59 (user clarification, 2026-10-17): a failed engine start must never close
  SplashUI. Process creation no longer counts as readiness. An exit before ready
  captures the engine log tail and exit status, opens a native error sheet over
  Settings, and offers Open Settings or Dismiss without terminating the app.
  A launch-failure record also prevents auto-quit after an earlier running session.
  Existing bounded retry behavior is unchanged; repeat identical errors do not
  repeatedly interrupt settings edits. Explicit Start/Restart can present a new failure.

- v60 (startup recovery, 2026-10-17): launcher-form engines refuse local model
  sources before process creation; AUTO selection is unchanged. Startup failures
  stay stopped until explicit Start/Restart (removed the 30-second launch retry).
  The error dialog now uses the panel's modal idiom, with Copy to Clipboard directly
  below the full error text, backed by NSPasteboard. Dismiss never starts an engine.

- v61 (user override, 2026-10-17): AUTO is capability-based. Local-library models
  choose the newest valid module-form kit across installed Homebrew kegs,
  ~/SplashUI/kit, the legacy ~/Documents/code/splash-standalone installation, and
  the configured engine path. Cached Hub models retain newest-Homebrew selection
  and force --offline plus HF_HUB_OFFLINE=1. Missing/incompatible cache files
  refuse startup with an explicit-download explanation; no model is downloaded
  silently. The Engine panel states the AUTO choice and reason. Tokenizers stored
  at the model root are used there instead of inventing a tokenizer/ subdirectory.

- v62 (cache precedence correction, 2026-10-17): resolve repo ids, including
  local/name ids originally selected in LM Studio, through models--owner--repo,
  refs/main and its snapshot before deciding engine capability. A complete snapshot
  (config, tokenizer and indexed safetensors shards) always keeps AUTO on the newest
  Homebrew launcher offline; it must not fall back to the old module engine merely
  because the profile's source is lmstudio. A real temporary-cache regression pins
  the OptiQ zero-revision layout and rejects a missing indexed shard.

- v63 (user ruling, 2026-10-17): keep OptiQ's nested vision tower in its original
  Hub snapshot. Remove the proposed flattened-cache workaround entirely; no cache
  rewrites, extra cache root or HF_HUB_CACHE override. AUTO uses the highest
  installed Homebrew keg (now 1.3.2) with --offline and HF_HUB_OFFLINE=1. This
  records launch planning only, not proof that the engine can finish loading it.

- v64 (user ruling, 2026-10-17): retain the vision tower through an isolated flat
  cache because 1.3.2 still rejects nested vision shard paths. Rewrite only the
  app-owned index filename to vision-optiq.safetensors; preserve every tensor key.
  All model data and metadata are symlinks to the original files. Prefer the
  original cache when it meets the launcher's filename restrictions; otherwise
  select the flat cache via child HF_HUB_CACHE, with HF_HUB_OFFLINE=1 and --offline.
  No modifications to the original Hub cache or Homebrew keg.

- v65 (offline draft resolution, 2026-10-17): the app-owned flat Hub cache also
  links the selected model's family DFlash2 repository from the original cache.
  Select its complete refs/main snapshot (drafts require config and weights, not
  target tokenizers). Repeated preparation retains the same repository symlink,
  so HF_HUB_CACHE does not hide the already-downloaded draft from the launcher.

- v66 (GGUF capability correction, 2026-10-17): a single cached root GGUF target
  (excluding mmproj projectors) is an offline-loadable snapshot when the installed
  launcher's upstream adapter defines _gguf_target. GGUF needs neither a cached
  config.json nor tokenizer JSON; the engine derives those from its header. Keep
  --offline and HF_HUB_OFFLINE=1, do not append an unnecessary variant, and refuse
  older engines with an accurate capability error rather than blaming the cache.

- v67 (user ruling, 2026-10-18): the launcher's `offline` option is honored. It
  is no longer forced on. When unset, offline is assumed only for a model specified
  from a local folder (profile source is not hfid/hfhub/hf/none); a Hugging Face
  id downloads through the engine unless offline is set. `HF_HUB_OFFLINE=1` follows
  the effective value. With offline on, a missing or incomplete snapshot is refused
  with an explicit-download error; with it off, the launch is not pre-refused.
  Supersedes the forced-offline clauses of v61 and v63.
