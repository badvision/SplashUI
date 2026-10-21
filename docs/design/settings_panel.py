#!/usr/bin/env python3
"""SplashUI Settings screen mock v11 — one 520x800 screen, stacked GLOBAL/PROFILES.
Full-page 42px left rail (channel 06), GLOBAL SETTINGS + PROFILES sec-h headings,
broken-line section break (main-app segment pattern), open-bracket profile editor
with the top bar VERTICALLY ALIGNED to the selected profile row.
No SAVE buttons: everything persists immediately; engine applies on restart.
"""

H = 800; W = 520; GAP = 64
BG = "#050508"; BG2 = "#0b0b12"; TRACK = "#191d33"
TEAL = "#88ccff"; PEACH = "#ffcc99"
GRAY = "#ccaa88"; GRAY_DIM = "#666688"; WHITE = "#ffebde"
GREEN = "#33cc99"; RED = "#dd4444"; YELLOW = "#ffcc33"
ACCENT = "#4455ff"
PROF = "#33cc99"               # profiles section color (green)
PROF_DIM = "#1fa87b"          # shade variant for profile col1 + editor frame
LILAC = "#cc88ff"             # global section color (lilac, ch 06)
COND = "'Avenir Next Condensed','Arial Narrow',sans-serif"
MONO = "monospace"

FY = H - 64  # 736
CX = 66      # content left (42 rail + 24)
C1W = 136                       # slim col1: 66..202
GD_X, GD_W = 216, 282           # global detail column 216..498

els = []
def R(x, y, w, h, fill, rx=0, op=None):
    o = f' opacity="{op}"' if op is not None else ""
    els.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" rx="{rx}"{o}/>')
def P(d, fill):
    els.append(f'<path d="{d}" fill="{fill}"/>')
def T(x, y, s, size=11, fill=WHITE, anchor="start", ls=0, w=None, fam=COND):
    e = f' letter-spacing="{ls}"' if ls else ""
    wt = f' font-weight="{w}"' if w else ""
    els.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-family="{fam}" text-anchor="{anchor}"{e}{wt}>{s}</text>')
def sub(x, yy, s): T(x, yy, s, 12, TEAL, ls=2, w=700)
def cap(x, yy, w, label, on=False, col=None, tcol=None, size=10):
    R(x, yy, w, 20, col or (ACCENT if on else BG2), rx=10)
    T(x + w/2, yy + 14, label, size, tcol or (BG if on else GRAY), anchor="middle", ls=0.5, w=700)
def mini(x, yy, w, label, red=False):
    R(x, yy, w, 20, "#3a2020" if red else TRACK, rx=10)
    T(x + w/2, yy + 14, label, 10, RED if red else WHITE, anchor="middle", w=700)
def inb(x, yy, w, h=22):
    R(x, yy, w, h, BG2); R(x, yy, w, 2, TRACK)
def lrow(yy, label, on, col=ACCENT, dot=True, rx=8, lr=False):
    x, y, w, h = 66, yy, C1W, 26
    r = min(rx, h / 2)
    rc = 0 if lr else r  # lr = left corners rounded only; right stays square
    P(f"M{x+r},{y} H{x+w-rc} A{rc},{rc} 0 0 1 {x+w},{y+rc} "
      f"V{y+h-rc} A{rc},{rc} 0 0 1 {x+w-rc},{y+h} "
      f"H{x+r} A{r},{r} 0 0 1 {x},{y+h-r} "
      f"V{y+r} A{r},{r} 0 0 1 {x+r},{y} Z", col if on else BG2)
    if on and dot:
        # Active indicator: bright capsule dot at the row's right edge.
        R(66 + C1W - 14, yy + 8, 8, 10, WHITE, rx=4)
    T(76, yy + 17, label, 10, BG if on else WHITE, w=700, ls=0.5)

def header():
    P("M58 0 L64 0 L64 28 L56 28 Q42 28 42 42 L42 62 L0 62 L0 48 Q0 0 58 0 Z", ACCENT)
    P(f"M64,0 H{W-14} A14,14 0 0 1 {W-14},28 H64 Z", ACCENT)
    T(82, 22, "SPLASH SETTINGS", 21, BG, ls=2.6, w=700)
    R(432, 4, 76, 20, BG, rx=10)
    T(470, 17, "STATUS", 10, WHITE, anchor="middle", ls=1, w=700)
    R(64, 34, 350, 18, PEACH)
    T(72, 47, "QWEN3.8-27B - INCOAI/QWEN3.8-27B-SPLASH", 8.5, BG, w=700)
    P("M414,34 H502 A9,9 0 0 1 502,52 H414 Z", GREEN)
    T(458, 47, "IDLE", 11, BG, anchor="middle", w=700)
    R(0, 62, 42, 4, ACCENT)
    R(42, 66, W - 42, 2, TRACK)

def rail():
    R(0, 66, 42, 306 - 66, LILAC)            # global segment (lilac, ch 06)
    R(0, 306, 42, FY - 42 - 306, PROF)        # profiles segment (green, ch 07)
    T(36, 306 - 12, "06", 23, BG, anchor="end", w=700)
    T(36, FY - 54, "07", 23, BG, anchor="end", w=700)
    # Green section divider where the 07 segment ends (replaces the old
    # track line), like the lilac one at the end of 06.
    R(52, FY - 42, 259, 4, PROF)
    R(320, FY - 42, 98, 4, PROF)
    R(427, FY - 42, 71, 4, PROF, rx=2)

def broken_line(y):
    # main-app section break: accent 0-58% / gap / accent 60-82% / gap / accent 84-100%
    R(52, y, 259, 4, LILAC)
    R(320, y, 98, 4, LILAC)
    R(427, y, 71, 4, LILAC, rx=2)

def sec_h(y, label, right=None, col=ACCENT):
    T(66, y, label, 14, col, ls=1.7, w=700)
    if right:
        T(498, y, right, 11, GRAY, anchor="end")

def pill(x, yy, w, text, fill, tx, size=10):
    R(x, yy, w, 20, fill, rx=10)
    T(x + w/2, yy + 14, text, size, tx, anchor="middle", w=700, ls=0.5)

def status_line():
    # (no track line — the green 07 divider replaces it)
    # Row 1: ( RESTART NEEDED ) capsule on the left;
    # ( CONFIG ] [ V1 ) segmented, right-aligned to the content edge.
    pill(66, FY - 28, 104, "RESTART NEEDED", RED, BG)
    capseg(394, FY - 28, 60, 20, BG2, "l")
    capseg(458, FY - 28, 40, 20, ACCENT, "r")
    T(424, FY - 14, "CONFIG", 10, WHITE, anchor="middle", w=700, ls=0.5)
    T(478, FY - 14, "V1", 10, BG, anchor="middle", w=700, ls=0.5)

def bottom_swoop():
    # Continuous outer/inner curves, with no overlapping rectangles or stepped notch.
    P(f"M0,{FY-42} H42 V{H-34} Q42,{H-12} 64,{H-12} "
      f"H{W-6} A6,6 0 0 1 {W},{H-6} A6,6 0 0 1 {W-6},{H} H58 Q0,{H} 0,{FY-42} Z", ACCENT)
    yy = FY + 10
    # Row 2: 4px gaps between pill sections, 24px gaps between groups.
    capseg(66, yy, 50, 20, GREEN, "l")
    R(120, yy, 50, 20, YELLOW)
    capseg(174, yy, 50, 20, RED, "r")
    T(91, yy + 14, "START", 10, BG, anchor="middle", w=700, ls=0.5)
    T(145, yy + 14, "RESTART", 10, BG, anchor="middle", w=700, ls=0.5)
    T(199, yy + 14, "STOP", 10, BG, anchor="middle", w=700, ls=0.5)
    # ( PID ] [ ### ) centered in the space between the groups (even margins).
    capseg(263, yy, 34, 20, BG2, "l")
    capseg(301, yy, 48, 20, BG2, "r")
    T(280, yy + 14, "PID", 10, WHITE, anchor="middle", w=700, ls=0.5)
    T(325, yy + 14, "23181", 9.5, WHITE, anchor="middle", fam=MONO, w=700)
    # ( APP-MANAGED ) right-flush with the V1 segment above.
    pill(388, yy, 110, "APP-MANAGED", BG2, WHITE)

# ---------------- GLOBAL (y ~94..300) ----------------
def global_block(sel):
    sec_h(94, "GLOBAL SETTINGS", col=LILAC)
    lrow(108, "ENGINE", sel == "engine", col=LILAC, dot=False)
    lrow(140, "FOLDERS", sel == "folders", col=LILAC, dot=False)
    lrow(172, "NETWORK", sel == "network", col=LILAC, dot=False)
    if sel == "engine":
        g_engine()
    else:
        g_network()
    broken_line(306)

def g_engine():
    sub(GD_X, 94, "ENGINE")
    aw, am = 95, 115
    capseg(GD_X, 110, aw, 20, GRAY_DIM, "l")
    capseg(GD_X + aw + 5, 110, am, 20, LILAC, "r")
    T(GD_X + aw/2, 124, "AUTO", 10, BG, anchor="middle", w=700, ls=0.5)
    T(GD_X + aw + 5 + am/2, 124, "MANUAL", 10, BG, anchor="middle", w=700, ls=0.5)
    pw, bw = 213, 64
    capseg(GD_X, 140, pw, 20, GRAY_DIM, "l")
    capseg(GD_X + pw + 5, 140, bw, 20, GRAY_DIM, "r")
    T(GD_X + 10, 154, "/Users/brobert/…/splash-standalone", 9, BG, fam=MONO)
    T(GD_X + pw + 5 + bw/2, 154, "BROWSE", 9, WHITE, anchor="middle", w=700, ls=0.5)
    T(GD_X, 182, "LADDER  …/kit/splash-1.3.0-arm64-macos26", 9, GRAY_DIM, fam=MONO)
    T(GD_X, 198, "1.3.0", 10, TEAL, w=700)
    T(GD_X + 44, 198, "ARM64 · MACOS 26.6", 9, GRAY_DIM, fam=MONO)
    T(GD_X + GD_W, 198, "VALID", 10, GREEN, anchor="end", w=700)
    T(GD_X, 220, "APPLIES ON NEXT RESTART", 9, GRAY_DIM, fam=MONO)

def gfield(y, label, text, iw=118, masked=False, default=False, eye=False):
    T(GD_X, y + 15, label, 10, GRAY)
    inb(GD_X + 108, y, iw)
    if eye:
        ex, cx = GD_X + 108 + iw + 8, GD_X + 108 + iw + 15
        P(f"M{ex},{y+11} Q{cx},{y+5} {ex+14},{y+11} Q{cx},{y+17} {ex},{y+11} Z", TEAL)
        R(cx - 2.5, y + 8.5, 5, 5, BG2, rx=2.5)
    if default:
        T(GD_X + 114, y + 15, text, 9.5, GRAY_DIM, fam=MONO)
    else:
        T(GD_X + 114, y + 15, text, 9.5, TEAL if masked else WHITE, fam=MONO)

def g_network():
    sub(GD_X, 94, "NETWORK")
    gfield(110, "HOST", "127.0.0.1", iw=124)
    gfield(138, "PORT", "8123", iw=70)
    T(GD_X + 200, 149, "▴", 8, TEAL)
    T(GD_X + 200, 157, "▾", 8, TEAL)
    gfield(166, "API KEY", "••••••••", iw=150, masked=True, eye=True)
    gfield(194, "ALLOWED-HOST", "127.0.0.1,localhost", iw=174)
    gfield(222, "ALLOWED-ORIGIN", "file://*", iw=174, default=True)
    T(GD_X, 265, "WEB UI", 10, GRAY)
    x_on, w_on, w_off = GD_X + 108, 58, 58
    capseg(x_on, 254, w_on, 20, LILAC, "l")
    capseg(x_on + w_on + 5, 254, w_off, 20, GRAY_DIM, "r")
    T(x_on + w_on/2, 268, "ON", 10, BG, anchor="middle", w=700, ls=0.5)
    T(x_on + w_on + 5 + w_off/2, 268, "OFF", 10, BG, anchor="middle", w=700, ls=0.5)

# ---------------- PROFILES (y ~320..572) ----------------
SEC_X, SEC_W = 216, 52           # section column = accent left border
DT_X, DT_1 = 278, 498            # detail column
P_ROW = 350                      # selected profile row y — editor top bar aligns here

def profiles_block():
    sec_h(336, "PROFILES", col=PROF)
    lrow(P_ROW, "QWEN3.8-27B", True, col=PROF_DIM, lr=True)
    lrow(P_ROW + 32, "LLAMA-8B", False, col=PROF_DIM)
    lrow(P_ROW + 64, "+ ADD PROFILE", False, col=PROF_DIM)
    R(202, P_ROW, 14, 26, PROF_DIM)          # flush selected profile -> title junction
    P(f"M216,{P_ROW} H486 A12,12 0 0 1 486,{P_ROW+24} H216 Z", PROF_DIM)
    T(DT_X, P_ROW + 17, "PROFILE SETTINGS", 14, BG, ls=1.7, w=700)
    # One open-right frame: rounded outer elbow and inner content corner.
    P(f"M216,{P_ROW+24} H268 V{P_ROW+231} "
      f"Q268,{P_ROW+241} 282,{P_ROW+241} H492 "
      f"A6,6 0 0 1 498,{P_ROW+247} A6,6 0 0 1 492,{P_ROW+253} "
      f"H234 Q216,{P_ROW+253} 216,{P_ROW+235} Z", PROF_DIM)
    # Sweep the selected profile's lower junction into the section column.
    P(f"M202,{P_ROW+26} H216 V{P_ROW+40} "
      f"Q216,{P_ROW+26} 202,{P_ROW+26} Z", PROF_DIM)
    R(268, P_ROW + 24, 8, 8, PROF_DIM)       # upper inner corner, shaped by tab cutout
    for i, name in enumerate(("GENERAL", "MEMORY", "CACHE", "COMPUTE", "API")):
        yy = P_ROW + 32 + i * 36
        on = (i == 0)
        if on:
            # Round the green shoulders into the open detail area, not a capsule end.
            P(f"M276,{yy-8} Q268,{yy-8} 268,{yy-4} Q268,{yy} 260,{yy} H234 "
              f"A13,13 0 0 0 221,{yy+13} A13,13 0 0 0 234,{yy+26} "
              f"H260 Q268,{yy+26} 268,{yy+34} H278 V{yy-8} Z", BG)
        # Selected tab: left cap + text shifted 5px left of the centered
        # position; right edge stays flush with the detail column.
        T(247 if on else SEC_X + SEC_W / 2, yy + 13 + 3.3, name, 9,
          WHITE if on else BG, w=700, ls=0.5, anchor="middle")
    p_general()

def capseg(x, y, w, h, fill, side):
    R(x, y, w, h, fill, rx=h/2)
    # Square the inner edge so only the outer tip is rounded.
    R(x + (w - h if side == "l" else 0), y, h, h, fill)

def p_general():
    x0, x1 = DT_X, DT_1
    y = P_ROW + 37
    T(x0, y, "PROFILE", 8, GRAY_DIM)
    bw = (x1 - x0 - 10) // 3
    capseg(x0, y + 6, bw, 20, GREEN, "l")
    R(x0 + bw + 5, y + 6, bw, 20, GRAY_DIM)
    capseg(x0 + 2 * (bw + 5), y + 6, bw, 20, GRAY_DIM, "r")
    T(x0 + bw/2, y + 20, "ACTIVATE", 9, BG, anchor="middle", w=700, ls=0.5)
    T(x0 + bw + 5 + bw/2, y + 20, "CLONE", 9, BG, anchor="middle", w=700, ls=0.5)
    T(x0 + 2 * (bw + 5) + bw/2, y + 20, "DELETE", 9, BG, anchor="middle", w=700, ls=0.5)
    T(x0, y + 44, "MODEL", 8, GRAY_DIM)
    nw, g, bw2 = 159, 5, 56
    capseg(x0, y + 50, nw, 20, GRAY_DIM, "l")
    capseg(x0 + nw + g, y + 50, bw2, 20, GRAY_DIM, "r")
    T(x0 + 10, y + 64, "Qwen3.8-27B-Splash", 8, BG, fam=MONO)
    T(x0 + nw + g + bw2/2, y + 64, "CHANGE", 9, WHITE, anchor="middle", w=700, ls=0.5)
    T(x0, y + 92, "DRAFTER", 8, GRAY_DIM)
    T(x0, y + 104, "PACKAGE — BAKED IN DRAFT/", 9, TEAL, w=700, fam=MONO)
    T(x0, y + 120, "CREATED 2026-10-15 · USED 2026-10-16", 8.5, GRAY_DIM, fam=MONO)
    R(x0, y + 132, x1 - x0, 64, BG2, rx=6)
    T(x0 + 10, y + 146, "LAUNCH PREVIEW", 8, TEAL, w=700, ls=1)
    R(x0 + 10, y + 152, x1 - x0 - 20, 1, TRACK)
    T(x0 + 10, y + 166, "splash --model Qwen3.8-27B", 8.5, WHITE, fam=MONO)
    T(x0 + 10, y + 180, "  --draft package --kv 16 · RESTART", 8.5, TEAL, fam=MONO)

# ---------------- modal ----------------
def chooser_modal():
    R(42, 68, W - 42, 622, "#000000", op=0.7)
    R(76, 208, 368, 320, ACCENT, rx=8)
    R(80, 212, 360, 312, BG)
    T(96, 240, "CHOOSE MODEL", 14, TEAL, ls=3, w=700)
    R(410, 222, 22, 22, BG2, rx=11)
    T(421, 237, "×", 11, GRAY, anchor="middle", w=700)
    inb(96, 254, 336, 22)
    T(102, 269, "search · hugging face id…", 10, GRAY_DIM)
    T(426, 269, "⌕", 12, TEAL, anchor="end")
    for i, (c, lbl) in enumerate(((True, "ALL · 20"), (False, "LM STUDIO · 7"), (False, "HF HUB · 13"))):
        cap(96 + i * 92, 288, 86, lbl, on=c, size=8)
    rows = (
        ("Qwen3.8-27B-Splash", "LM STUDIO", "8.4 GB", True),
        ("Llama-8B-Splash", "HF HUB", "4.9 GB", False),
        ("Llama-8B-Instruct", "HF HUB", "4.9 GB", False),
        ("Qwen3.8-8B-Splash", "LM STUDIO", "5.1 GB", False),
    )
    for i, (n, src, size, match) in enumerate(rows):
        yy = 322 + i * 27
        R(96, yy, 336, 24, ACCENT if match else BG2)
        T(104, yy + 16, n, 10, BG if match else WHITE, fam=MONO)
        if match:
            T(254, yy + 16, "MATCH", 7, BG, w=700)
        T(424, yy + 16, src + " · " + size, 8, BG if match else TEAL, anchor="end", fam=MONO)
    R(96, 436, 336, 2, TRACK)
    T(96, 456, "HF ID MATCHES A DOWNLOADED MODEL →", 8, GRAY_DIM, fam=MONO)
    T(96, 469, "SHOWN AS A SEARCH RESULT", 8, GRAY_DIM, fam=MONO)
    mini(300, 494, 54, "CANCEL")
    cap(360, 494, 66, "OK", on=True)

# ---------------- frames ----------------
FXS = [0, W + GAP, 2 * (W + GAP)]
TITLES = ("01 · ONE SCREEN — GLOBAL=ENGINE", "02 · ONE SCREEN — GLOBAL=NETWORK · GRAY=default",
          "03 · MODEL CHOOSER MODAL")
for i, fx in enumerate(FXS):
    T(fx + 10, 12, TITLES[i], 10, GRAY_DIM, ls=2)
    els.append(f'<g transform="translate({fx},20)">')
    header()
    rail()
    global_block("engine" if i == 0 else "network")
    profiles_block()
    if i == 2:
        chooser_modal()
    status_line()
    bottom_swoop()
    els.append('</g>')

TW = W * 3 + GAP * 2
svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {TW} {H+24}" width="{TW}" height="{H+24}">'
       f'<rect width="{TW}" height="{H+24}" fill="#000"/>' +
       "".join(f'<rect x="{fx}" y="20" width="{W}" height="{H-24}" fill="{BG}"/>' for fx in FXS) +
       "\n".join(els) + "</svg>")
open("/tmp/mock/settings_panel.svg", "w").write(svg)
print(f"wrote /tmp/mock/settings_panel.svg  {TW}x{H+24}")
