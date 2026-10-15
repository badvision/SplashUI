// Regression tests for the pure SplashUI launch decisions (ui_logic.swift).
// Run from the repo root: ./run_tests.sh   (compiles ui_logic.swift + this file, no AppKit).

import Foundation

var failures = 0
func check(_ cond: Bool, _ label: String) {
    if cond { print("ok  - \(label)") }
    else { failures += 1; print("FAIL- \(label)") }
}


// Union for readability of the fixture sets below.
extension Set where Element: Hashable {
    static func | (l: Set, r: Set) -> Set { l.union(r) }
}
let now = Date(timeIntervalSince1970: 1_000_000)

// A tarball kit: dir + engine/splash + python/bin/python.
func kitPaths(_ d: String) -> (dirs: Set<String>, exe: Set<String>) {
    (["\(d)"], ["\(d)/engine/splash", "\(d)/python/bin/python"])
}

// A Homebrew keg: the libexec/ dir IS the engine kit (engine/splash + bundled
// python3 + server package); the prefix also carries the bin/splash shim.
func brewPaths(_ p: String) -> (dirs: Set<String>, exe: Set<String>) {
    (["\(p)", "\(p)/libexec", "\(p)/libexec/engine"],
     ["\(p)/bin/splash", "\(p)/libexec/engine/splash", "\(p)/libexec/python/bin/python3"])
}

// ---- resolveSplashPaths: engine ladder --------------------------------------

// env SPLASH_KIT_DIR (path-based install) wins — even over a brew keg.
do {
    let (kd, ke) = kitPaths("/env/kit")
    let (bd, be) = brewPaths("/opt/homebrew")
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/env/kit"],
        defaultRoot: "/home/SplashUI", home: "/home",
        isDir: { (kd | bd).contains($0) }, isExecutable: { (ke | be).contains($0) },
        brewKeg: { "/opt/homebrew" })
    check(r.workDir == "/env/kit", "ladder: SPLASH_KIT_DIR env wins over brew")
    check(r.executable == "/env/kit/python/bin/python", "ladder: env kit python derived")
}

// incomplete env kit (no python) is skipped; SPLASHUI_HOME rung wins.
do {
    let (hd, he) = kitPaths("/root/kit/splash-1.3.0-arm64-macos26")
    let dirs: Set<String> = hd.union(["/env/broken/kit", "/env/model"])
    let exe: Set<String> = he.union(["/env/broken/kit/engine/splash"])
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/env/broken/kit", "SPLASHUI_HOME": "/root",
              "SPLASH_MODEL_ROOT": "/env/model"],
        defaultRoot: "/home/SplashUI", home: "/home",
        isDir: { dirs.contains($0) }, isExecutable: { exe.contains($0) })
    check(r.workDir == "/root/kit/splash-1.3.0-arm64-macos26",
          "ladder: incomplete env kit skipped, SPLASHUI_HOME rung wins")
    check(r.executable == "/root/kit/splash-1.3.0-arm64-macos26/python/bin/python",
          "ladder: python derived from kit dir")
    check(r.error == nil, "ladder: no error when kit resolves")
}

// SPLASHUI_HOME + SPLASH_VERSION drive the derived path.
do {
    let (d, e) = kitPaths("/customroot/kit/splash-9.9.9-arm64-macos26")
    let r = resolveSplashPaths(
        env: ["SPLASHUI_HOME": "/customroot", "SPLASH_VERSION": "9.9.9"],
        defaultRoot: nil, home: "/home",
        isDir: { d.contains($0) }, isExecutable: { e.contains($0) })
    check(r.workDir == "/customroot/kit/splash-9.9.9-arm64-macos26",
          "ladder: SPLASHUI_HOME + SPLASH_VERSION honored")
}

// brew is the LAST rung — a path-based install (SPLASHUI_HOME) beats it.
do {
    let (bd, be) = brewPaths("/opt/homebrew")
    let (rd, re) = kitPaths("/root/kit/splash-1.3.0-arm64-macos26")
    let dirs: Set<String> = bd | rd
    let exe: Set<String> = be | re
    let r = resolveSplashPaths(
        env: ["SPLASHUI_HOME": "/root"],
        defaultRoot: nil, home: "/home",
        isDir: { dirs.contains($0) }, isExecutable: { exe.contains($0) },
        brewKeg: { "/opt/homebrew" })
    check(r.workDir == "/root/kit/splash-1.3.0-arm64-macos26",
          "ladder: SPLASHUI_HOME rung beats brew (brew is last)")
}

// brew is used when no path-based install exists (the only kit present).
do {
    let (bd, be) = brewPaths("/opt/homebrew")
    let r = resolveSplashPaths(
        env: [:],
        defaultRoot: nil, home: "/home",
        isDir: { bd.contains($0) }, isExecutable: { be.contains($0) },
        brewKeg: { "/opt/homebrew" },
        kitVersion: { $0.hasPrefix("/opt/homebrew/libexec") ? "1.3.1" : nil })
    check(r.workDir == "/opt/homebrew/libexec",
          "ladder: brew keg's libexec is the kit when only brew is present")
    check(r.executable == "/opt/homebrew/libexec/python/bin/python3",
          "ladder: brew kit uses the keg's bundled python3")
    check(r.error == nil, "ladder: brew (1.3.1) needs no model dir (loads by id)")
}

// brew (1.3.1) runs the launcher's id form, not the tarball module form —
// only when there is no local model (which a 1.3.1 engine can't load).
do {
    let (bd, be) = brewPaths("/opt/homebrew")
    let r = resolveSplashPaths(
        env: [:],
        defaultRoot: nil, home: "/home",
        isDir: { bd.contains($0) }, isExecutable: { be.contains($0) },
        brewKeg: { "/opt/homebrew" },
        kitVersion: { $0.hasPrefix("/opt/homebrew/libexec") ? "1.3.1" : nil })
    check(r.engineArgs.contains("install/launcher.py"),
          "brew args: runs the kit's install/launcher.py")
    check(r.engineArgs.contains("serve") && r.engineArgs.contains("--model"),
          "brew args: serve --model (id form)")
    check(r.engineArgs.contains("mlx-community/Qwen3.8-27B-4bit"),
          "brew args: the 1.3.1 MLX model id (family of the 1.3.0 package)")
    check(!r.engineArgs.contains("server.server") && !r.engineArgs.contains("--binary"),
          "brew args: not the module form (no server.server / --binary)")
    check(r.modelId == "mlx-community/Qwen3.8-27B-4bit",
          "brew: modelId is the MLX id it will download/serve (panel label)")
    check(r.version == "1.3.1", "brew: resolved keg version surfaced (1.3.1)")
    check(r.error == nil, "brew args: no local model -> no error (downloads by id)")
}

// a local model excludes the 1.3.1 brew keg: picking it would re-download the
// model, so with only brew present the app reports an actionable error.
do {
    let (bd, be) = brewPaths("/opt/homebrew")
    let model = "/home/.lmstudio/models/incoai/Qwen3.8-27B-Splash"
    let r = resolveSplashPaths(
        env: [:],
        defaultRoot: nil, home: "/home",
        isDir: { bd.contains($0) || $0 == model }, isExecutable: { be.contains($0) },
        brewKeg: { "/opt/homebrew" },
        kitVersion: { $0.hasPrefix("/opt/homebrew/libexec") ? "1.3.1" : nil })
    check(r.modelRoot == model, "local model: model dir resolved")
    check(r.executable == nil, "local model: no 1.3.0 kit -> brew (1.3.1) not used")
    let e = r.error ?? ""
    check(e.contains("local model found"), "local model: error names the local model")
    check(e.contains("1.3.0 engine kit"), "local model: error says a 1.3.0 kit is needed")
}

// local model + a 1.3.1 engine chosen explicitly (SPLASH_KIT_DIR) is rejected:
// it would ignore the model and re-download it.
do {
    let (bd, be) = brewPaths("/opt/homebrew")
    let model = "/env/model"
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/opt/homebrew/libexec", "SPLASH_MODEL_ROOT": model],
        defaultRoot: nil, home: "/home",
        isDir: { bd.contains($0) || $0 == model }, isExecutable: { be.contains($0) },
        brewKeg: { "/opt/homebrew" },
        kitVersion: { $0.hasPrefix("/opt/homebrew/libexec") ? "1.3.1" : nil })
    check(r.executable == "/opt/homebrew/libexec/python/bin/python3",
          "explicit 1.3.1 + local model: kit still resolves")
    let e = r.error ?? ""
    check(e.contains("cannot load the 1.3.0 model format"),
          "explicit 1.3.1 + local model: error says it can't load it")
}

// local model + a 1.3.0 kit (the common case) runs the module form on it.
do {
    let (kd, ke) = kitPaths("/kit130")
    let model = "/env/model"
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/kit130", "SPLASH_MODEL_ROOT": model],
        defaultRoot: nil, home: "/home",
        isDir: { kd.contains($0) || $0 == model }, isExecutable: { ke.contains($0) },
        kitVersion: { $0 == "/kit130" ? "1.3.0" : nil })
    check(r.error == nil, "local model + 1.3.0 kit: no error")
    check(r.engineArgs.contains("-m") && r.engineArgs.contains("server.server"),
          "local model + 1.3.0 kit: module form")
    check(r.engineArgs.contains(model),
          "local model + 1.3.0 kit: local model dir passed positionally")
    check(r.engineArgs.contains("--model") && r.engineArgs.contains("incoai/Qwen3.8-27B-Splash"),
          "local model + 1.3.0 kit: --model OWNER/REPO passed (server.py requires it)")
    check(r.engineArgs.contains(model + "/tokenizer"),
          "local model + 1.3.0 kit: --tokenizer points at the package's tokenizer/ subdir")
    check(r.modelId == "incoai/Qwen3.8-27B-Splash",
          "local model + 1.3.0 kit: modelId is the local package id (panel label)")
    check(r.version == "1.3.0", "local model + 1.3.0 kit: resolved kit version surfaced")
}

// Default install root: README install.sh layout is found with no env.
do {
    let (d, e) = kitPaths("/home/SplashUI/kit/splash-1.3.0-arm64-macos26")
    let model = "/home/SplashUI/models/incoai/Qwen3.8-27B-Splash"
    let r = resolveSplashPaths(
        env: [:],
        defaultRoot: "/home/SplashUI", home: "/home",
        isDir: { d.contains($0) || $0 == model }, isExecutable: { e.contains($0) })
    check(r.workDir == "/home/SplashUI/kit/splash-1.3.0-arm64-macos26",
          "ladder: default install root kit found with no env")
    check(r.modelRoot == model, "model: default install root models found with no env")
    check(r.error == nil, "default install root: kit and model resolve without error")
}

// Explicit SPLASHUI_HOME replaces the default root for both kit and model.
do {
    let (rd, re) = kitPaths("/root/kit/splash-1.3.0-arm64-macos26")
    let (dd, de) = kitPaths("/home/SplashUI/kit/splash-1.3.0-arm64-macos26")
    let model = "/root/models/incoai/Qwen3.8-27B-Splash"
    let dirs = rd | dd | [model, "/home/SplashUI/models/incoai/Qwen3.8-27B-Splash"]
    let r = resolveSplashPaths(
        env: ["SPLASHUI_HOME": "/root"],
        defaultRoot: "/home/SplashUI", home: "/home",
        isDir: { dirs.contains($0) }, isExecutable: { (re | de).contains($0) })
    check(r.workDir == "/root/kit/splash-1.3.0-arm64-macos26",
          "ladder: explicit SPLASHUI_HOME wins over default root")
    check(r.modelRoot == model, "model: explicit SPLASHUI_HOME wins over default root")
}

// nothing anywhere: no assumption is made — actionable error, no quit.
do {
    let r = resolveSplashPaths(
        env: [:],
        defaultRoot: nil, home: "/home",
        isDir: { _ in false }, isExecutable: { _ in false })
    check(r.executable == nil, "ladder: nothing found -> no executable")
    check(r.modelRoot == nil, "ladder: nothing found -> no model")
    let e = r.error ?? ""
    check(e.contains("engine kit not found"), "miss: error says kit not found")
    check(!e.contains("model not found"),
          "miss: no model error when the engine itself is absent (fix the kit first)")
}

// empty-string env values count as unset.
do {
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "", "SPLASH_MODEL_ROOT": ""],
        defaultRoot: nil, home: "/home",
        isDir: { _ in false }, isExecutable: { _ in false })
    check(r.executable == nil && r.modelRoot == nil, "empty env values treated as unset")
}

// ---- resolveSplashPaths: model ladder ---------------------------------------

// env SPLASH_MODEL_ROOT wins.
do {
    let (_, ke) = kitPaths("/k")
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/env/model"],
        defaultRoot: "/home/SplashUI", home: "/home",
        isDir: { $0 == "/k" || $0 == "/env/model" }, isExecutable: { ke.contains($0) })
    check(r.modelRoot == "/env/model", "model: SPLASH_MODEL_ROOT wins")
    check(r.error == nil, "model: no error when both resolve")
}

// SPLASHUI_HOME models rung.
do {
    let (kd, ke) = kitPaths("/k")
    let dirs: Set<String> = kd.union(["/customroot/models/incoai/Qwen3.8-27B-Splash"])
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASHUI_HOME": "/customroot"],
        defaultRoot: nil, home: "/home",
        isDir: { dirs.contains($0) }, isExecutable: { ke.contains($0) })
    check(r.modelRoot == "/customroot/models/incoai/Qwen3.8-27B-Splash",
          "model: SPLASHUI_HOME models rung")
}

// ~/.lmstudio is the LAST rung — an LM-Studio copy is picked up with no env.
do {
    let (kd, ke) = kitPaths("/k")
    let dirs: Set<String> = kd.union(["/home/.lmstudio/models/incoai/Qwen3.8-27B-Splash"])
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k"],
        defaultRoot: nil, home: "/home",
        isDir: { dirs.contains($0) }, isExecutable: { ke.contains($0) })
    check(r.modelRoot == "/home/.lmstudio/models/incoai/Qwen3.8-27B-Splash",
          "model: LM-Studio copy is the last rung")
}

// model miss: error names every tried location.
do {
    let (kd, ke) = kitPaths("/k")
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/env/model",
              "SPLASHUI_HOME": "/customroot"],
        defaultRoot: nil, home: "/home",
        isDir: { kd.contains($0) }, isExecutable: { ke.contains($0) })
    check(r.modelRoot == nil, "model miss: modelRoot nil")
    let e = r.error ?? ""
    check(e.contains("/env/model"), "model miss: error names SPLASH_MODEL_ROOT path")
    check(e.contains("/customroot/models/incoai/Qwen3.8-27B-Splash"),
          "model miss: error names SPLASHUI_HOME path")
    check(e.contains("/home/.lmstudio/models/incoai/Qwen3.8-27B-Splash"),
          "model miss: error names LM-Studio path")
    check(e.contains("SPLASH_MODEL_ROOT") && e.contains("./install.sh"),
          "model miss: error suggests env var / install.sh")
}

// model error is dirModel-only: a 1.3.1 (id) engine needs no model dir.
do {
    let (kd, ke) = kitPaths("/k")
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k"],
        defaultRoot: nil, home: "/home",
        isDir: { kd.contains($0) }, isExecutable: { ke.contains($0) },
        kitVersion: { $0 == "/k" ? "1.3.1" : nil })
    check(r.modelRoot == nil, "id model: modelRoot nil")
    let e = r.error ?? ""
    check(!e.contains("model not found"), "id model: no model error (loads by id)")
    check(r.engineArgs.contains("serve") && r.engineArgs.contains("--model"),
          "id model: id-form argv with no model dir")
}

// ---- knobs ------------------------------------------------------------------

do {
    let (_, ke) = kitPaths("/k")
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/m", "SPLASH_PORT": "8199",
              "SPLASH_KEY": "k2", "SPLASH_MAX_CACHE_DISK": "50g", "SPLASH_IDLE_RELEASE": "60m"],
        defaultRoot: nil, home: "/home",
        isDir: { $0 == "/k" || $0 == "/m" }, isExecutable: { ke.contains($0) })
    check(r.port == 8199, "port: SPLASH_PORT honored")
    check(r.apiKey == "k2", "key: SPLASH_KEY honored")
    check(r.maxCacheDisk == "50g", "cache: SPLASH_MAX_CACHE_DISK honored")
    check(r.idleRelease == "60m", "idle: SPLASH_IDLE_RELEASE honored")
    check(r.base == "http://127.0.0.1:8199", "base derived from resolved port")
    check(r.engineArgs.contains("8199"), "engineArgs: port in argv")
}

// invalid SPLASH_PORT: default 8123 kept, non-fatal note names the bad value.
do {
    let (_, ke) = kitPaths("/k")
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/m", "SPLASH_PORT": "nope"],
        defaultRoot: nil, home: "/home",
        isDir: { $0 == "/k" || $0 == "/m" }, isExecutable: { ke.contains($0) })
    check(r.port == 8123, "port: invalid SPLASH_PORT falls back to 8123")
    let e = r.error ?? ""
    check(e.contains("SPLASH_PORT") && e.contains("nope"), "port: invalid value named in error")
}

// defaults when nothing set.
do {
    let (_, ke) = kitPaths("/k")
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/m"],
        defaultRoot: nil, home: "/home",
        isDir: { $0 == "/k" || $0 == "/m" }, isExecutable: { ke.contains($0) })
    check(r.port == 8123 && r.apiKey == "splash-standalone-1" && r.maxCacheDisk == "100g"
          && r.idleRelease == "240m", "defaults: port/key/cache/idle")
    check(r.engineArgs.contains("-m") && r.engineArgs.contains("server.server"),
          "engineArgs: module form")
    check(!r.engineArgs.contains("--disable-ane"), "ane: on by default (no --disable-ane)")
}

// SPLASH_ANE=off adds --disable-ane (both flavors).
do {
    let (_, ke) = kitPaths("/k")
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/m", "SPLASH_ANE": "off"],
        defaultRoot: nil, home: "/home",
        isDir: { $0 == "/k" || $0 == "/m" }, isExecutable: { ke.contains($0) })
    check(r.engineArgs.last == "--disable-ane", "ane: SPLASH_ANE=off adds --disable-ane (module form)")

    let (bd, be) = brewPaths("/opt/homebrew")
    let rb = resolveSplashPaths(
        env: ["SPLASH_ANE": "off"],
        defaultRoot: nil, home: "/home",
        isDir: { bd.contains($0) }, isExecutable: { be.contains($0) },
        brewKeg: { "/opt/homebrew" },
        kitVersion: { $0.hasPrefix("/opt/homebrew/libexec") ? "1.3.1" : nil })
    check(rb.engineArgs.last == "--disable-ane", "ane: SPLASH_ANE=off adds --disable-ane (id form)")
    check(rb.engineArgs.contains("serve"), "ane: id form for the 1.3.1 brew kit")
    check(rb.executable == "/opt/homebrew/libexec/python/bin/python3",
          "ane: brew kit still resolves the keg python")
}

// ---- autoQuitDecision: truth table ------------------------------------------

// up then gone >10 s: quit (crash path, unchanged behavior).
check(autoQuitDecision(procGone: true, everUp: true, downFor: 11, userStopped: false) == true,
      "quit: up-then-gone 11s -> quit")
// up then gone 9 s: not yet.
check(autoQuitDecision(procGone: true, everUp: true, downFor: 9, userStopped: false) == false,
      "quit: up-then-gone 9s -> no quit")
// never up, long gone: NEVER quit (the bug fix).
check(autoQuitDecision(procGone: true, everUp: false, downFor: 60, userStopped: false) == false,
      "quit: never-up 60s -> no quit")
// not gone: never quit.
check(autoQuitDecision(procGone: false, everUp: true, downFor: 0, userStopped: false) == false,
      "quit: proc alive -> no quit")
// user stopped: never auto-quit.
check(autoQuitDecision(procGone: true, everUp: true, downFor: 11, userStopped: true) == false,
      "quit: userStopped -> no quit")

// ---- launchRetryDue ---------------------------------------------------------

// no error: not due.
check(launchRetryDue(error: nil, retries: 0, now: now) == false, "retry: no error -> not due")
// error 31 s old, within retry cap: due.
check(launchRetryDue(error: now.addingTimeInterval(-31), retries: 3, now: now) == true,
      "retry: 31s old, under cap -> due")
// error 29 s old: not yet (30 s interval).
check(launchRetryDue(error: now.addingTimeInterval(-29), retries: 3, now: now) == false,
      "retry: 29s old -> not due")
// at the 10-retry cap: never due again.
check(launchRetryDue(error: now.addingTimeInterval(-400), retries: 10, now: now) == false,
      "retry: cap (10) reached -> not due")
// just under the cap: still due.
check(launchRetryDue(error: now.addingTimeInterval(-400), retries: 9, now: now) == true,
      "retry: 9 retries, long ago -> due")

// ---- request display and RSS ------------------------------------------------
let explicitId = requestRowId(current: 3, lineHasId: 42)
check(explicitId.id == 42 && explicitId.next == 43, "request id: explicit id wins and advances sequence")
let olderId = requestRowId(current: 43, lineHasId: 9)
check(olderId.id == 9 && olderId.next == 43, "request id: older explicit id does not rewind")
var sequence = 10
var ids: [Int] = []
for _ in ["Done", "Cancelled", "Done"] {
    let row = requestRowId(current: sequence, lineHasId: nil)
    ids.append(row.id); sequence = row.next
}
check(ids == [10, 11, 12], "request id: mixed aligned batch is unique and monotonic")
let skewedRow = requestRowId(current: sequence, lineHasId: nil)
check(skewedRow.id == 13 && skewedRow.next == 14, "request id: extra line after snapshot remains unique")
check(requestRowId(current: 0, lineHasId: nil).id == 0, "request id: zero safe")
check(!inFlight(prefilling: 0, decoding: 0, frontendActive: 0), "in flight: idle")
check(inFlight(prefilling: 1, decoding: 0, frontendActive: 0), "in flight: prefill")
check(inFlight(prefilling: 0, decoding: 1, frontendActive: 0), "in flight: decode")
check(inFlight(prefilling: 0, decoding: 0, frontendActive: 1), "in flight: frontend")
check(prefillProgress(prefilledTotal: 150, prefillBase: 100) == 50, "prefill: cumulative delta")
check(prefillProgress(prefilledTotal: 80, prefillBase: 100) == 0, "prefill: reset clamps to zero")
check(prefillProgress(prefilledTotal: 150, prefillBase: nil) == nil, "prefill: missing baseline is unknown")
var baseline = prefillBaseline(prefilling: true, wasPrefilling: false, current: nil, prefilledTotal: nil)
check(baseline == nil, "prefill: status-before-metrics starts unknown")
baseline = prefillBaseline(prefilling: true, wasPrefilling: true, current: baseline, prefilledTotal: 100)
check(prefillProgress(prefilledTotal: 125, prefillBase: baseline) == 25, "prefill: late metrics baseline makes progress")
check(prefillBaseline(prefilling: true, wasPrefilling: true, current: baseline, prefilledTotal: 125) == 100, "prefill: established baseline remains stable")
check(prefillProgress(prefilledTotal: .nan, prefillBase: 100) == nil, "prefill: invalid total is unknown")

// ---- prefillPct / meanFreshTail / prefillEta / prefillEtaText -----------------
check(prefillPct(done: 50, estFresh: nil) == nil, "pct: nil estFresh -> no estimate")
check(prefillPct(done: 50, estFresh: 0) == nil, "pct: zero estFresh -> no estimate")
check(prefillPct(done: 50, estFresh: -5) == nil, "pct: negative estFresh -> no estimate")
check(prefillPct(done: 30, estFresh: 300) == 10, "pct: done/estFresh")
check(prefillPct(done: 300, estFresh: 300) == 100, "pct: done == estFresh -> 100")
check(prefillPct(done: 900, estFresh: 300) == 100, "pct: stale estimate clamps to 100")
check(prefillPct(done: -50, estFresh: 300) == 0, "pct: negative done clamps to 0")
check(prefillPct(done: .nan, estFresh: 300) == 0, "pct: NaN done is safe")
check(meanFreshTail(fresh: []) == nil, "meanFresh: empty window -> nil")
check(meanFreshTail(fresh: [(100, 100), (200, 200)]) == nil, "meanFresh: all-zero fresh -> nil")
check(meanFreshTail(fresh: [(100, 0), (200, 50)]) == 125, "meanFresh: mean of (input-cached)")
check(meanFreshTail(fresh: [(100, 0), (150, 160)]) == 50, "meanFresh: clamped negative pairs")
check(prefillEta(done: 300, estFresh: nil, rate: 300) == nil, "eta: nil estFresh -> no estimate")
check(prefillEta(done: 300, estFresh: 300, rate: nil) == nil, "eta: nil rate -> no estimate")
check(prefillEta(done: 300, estFresh: 300, rate: 0) == nil, "eta: zero rate -> no estimate")
check(prefillEta(done: 300, estFresh: 300, rate: -5) == nil, "eta: negative rate -> no estimate")
check(prefillEta(done: 900, estFresh: 300, rate: 300) == 0, "eta: done past estimate -> 0 s")
check(prefillEta(done: 0, estFresh: 300, rate: 300) == 1, "eta: estFresh - done / rate")
check(abs(prefillEta(done: 30, estFresh: 330, rate: 30)! - 10) < 0.001, "eta: 300/30 = 10 s")
check(prefillEtaText(sec: nil) == nil, "eta text: nil -> nil")
check(prefillEtaText(sec: 11) == "11 s", "eta text: under a minute")
check(prefillEtaText(sec: 0) == "0 s", "eta text: 0 s")
check(prefillEtaText(sec: 60) == "1m 0 s", "eta text: 60 s boundary")
check(prefillEtaText(sec: 73) == "1m 13 s", "eta text: 73 s -> 1m 13 s")
check(prefillEtaText(sec: 59.4) == "1m 0 s", "eta text: ceil 59.4 -> 60 s -> minute form")
check(prefillEtaText(sec: 65) == "1m 5 s", "eta text: 65 s -> 1m 5 s")
check(prefillEtaText(sec: -1) == nil, "eta text: negative -> nil")
// ---- prefillProjRate (three-rung precedence) ------------------------------
check(prefillProjRate(live: 320, latch: 250, engine: 208) == 320, "projRate: live wins")
check(prefillProjRate(live: nil, latch: 250, engine: 208) == 250, "projRate: latch when live nil")
check(prefillProjRate(live: 0, latch: 250, engine: 208) == 250, "projRate: zero live falls to latch")
check(prefillProjRate(live: nil, latch: 0, engine: 208) == 208, "projRate: zero latch falls to engine")
check(prefillProjRate(live: nil, latch: nil, engine: 208) == 208, "projRate: engine as final rung")
check(prefillProjRate(live: nil, latch: nil, engine: nil) == nil, "projRate: all nil -> nil")
check(prefillProjRate(live: nil, latch: nil, engine: 0) == nil, "projRate: zero engine -> nil")
check(prefillProjRate(live: .nan, latch: nil, engine: 208) == 208, "projRate: NaN live ignored")
check(prefillProjRate(live: .infinity, latch: nil, engine: 208) == 208, "projRate: nonfinite live ignored")

// ---- prefillPct cap (the pill no longer flashes 100% mid-prefill) -------------
check(prefillPct(done: 500, estFresh: 4900, cap: 99) == 100 * 500 / 4900, "pct cap: under the cap, unchanged")
check(prefillPct(done: 4900, estFresh: 4900, cap: 99) == 99, "pct cap: at 100 but capped -> 99")
check(prefillPct(done: 4900, estFresh: 4900, cap: nil) == 100, "pct cap: nil cap still reaches 100")
check(prefillPct(done: 6000, estFresh: 4900, cap: 99) == 99, "pct cap: overshoot clamped to cap, not 100")
check(prefillPct(done: 500, estFresh: 4900, cap: 150) == 100 * 500 / 4900, "pct cap: cap above 100 is a no-op")
check(prefillPct(done: 4900, estFresh: 4900, cap: -1) == 100, "pct cap: invalid cap falls back to 100")

// ---- prefillCumulativeRate (chunk-edge spike guard) ----------------------------
check(prefillCumulativeRate(workDone: 0, age: 2) == nil, "cumrate: below first chunk -> nil")
check(prefillCumulativeRate(workDone: 2047, age: 2) == nil, "cumrate: just under minCommitted -> nil")
check(prefillCumulativeRate(workDone: 2048, age: 16) == 128, "cumrate: 2048 over 16s -> 128")
check(prefillCumulativeRate(workDone: 4096, age: 32) == 128, "cumrate: 4096 over 32s -> 128")
check(prefillCumulativeRate(workDone: 2048, age: 0.4) == nil, "cumrate: age below floor -> nil")
check(prefillCumulativeRate(workDone: 2048, age: .nan) == nil, "cumrate: NaN age -> nil")
check(prefillCumulativeRate(workDone: .infinity, age: 16) == nil, "cumrate: nonfinite workDone -> nil")

// ---- calibratePrefillRate (spike clamp) ----------------------------------------
check(calibratePrefillRate(raw: 2048, cumulative: 128) == 128, "cal: spike over cumulative clamped down")
check(calibratePrefillRate(raw: 128, cumulative: 128) == 128, "cal: raw == cumulative kept")
check(calibratePrefillRate(raw: 100, cumulative: 128) == 100, "cal: legit low sample (mid-chunk) kept")
check(calibratePrefillRate(raw: 2048, cumulative: nil) == 2048, "cal: no cumulative (pre-first-commit) keeps raw")
check(calibratePrefillRate(raw: nil, cumulative: 128) == nil, "cal: nil raw -> nil")
check(calibratePrefillRate(raw: 0, cumulative: 128) == nil, "cal: zero raw -> nil")
// Never RAISES the rate: raw below cumulative is never bumped up.
check(calibratePrefillRate(raw: 50, cumulative: 128) == 50, "cal: never raises raw to cumulative")

// ---- ageAtPctCross (diagnostic: when does a formula claim 100%?) ---------------
func xcross(_ s: [(Double, Double)], _ p: Double) -> Double? {
    ageAtPctCross(samples: s.map { (age: $0.0, pct: $0.1) }, pct: p)
}
check(xcross([], 100) == nil, "xcross: empty -> nil")
check(xcross([(1, 10), (2, 20)], 100) == nil, "xcross: never reached -> nil")
check(xcross([(1, 100)], 100) == 1, "xcross: single sample already at 100 -> its age")
check(xcross([(1, 90), (2, 100)], 100) == 2, "xcross: first hit at second sample -> its age")
check(xcross([(1, 90), (2, 100)], 95) == 1.5, "xcross: linear interpolation between samples")
check(xcross([(1, 0), (2, 0), (3, 100)], 100) == 3, "xcross: hit after flat stretch -> its age")
check(xcross([(1, 50)], 99) == nil, "xcross: single sample below target -> nil")
// ---- prefillProjectedDone (rate extrapolation) ------------------------------
// First-chunk, before any commit: workDone 0, age 2 s, rate 250, estFresh 4900
// -> proj 500 -> pct ~= 10.2% (the readout climbs from the start).
check(prefillProjectedDone(workDone: 0, ageAtLastCommit: 0, age: 2, rate: 250, estFresh: 4900) == 500, "proj: first chunk t=2s -> 500")
if let p = prefillPct(done: 500, estFresh: 4900) { check(abs(p - 10.204) < 0.01, "proj: first chunk pct ~= 10.2%") }
check(prefillProjectedDone(workDone: 0, ageAtLastCommit: 0, age: 6, rate: 250, estFresh: 4900) == 1500, "proj: age 6s before any commit -> 1500")
// After a commit at age 7 (workDone 2048), at age 10 s: 2048 + 3*250, clamped by estFresh.
check(prefillProjectedDone(workDone: 2048, ageAtLastCommit: 7, age: 10, rate: 250, estFresh: 4900) == 2798, "proj: after commit, extrapolated -> min(2048+750, estFresh)")
check(prefillProjectedDone(workDone: 2048, ageAtLastCommit: 7, age: 10, rate: 250, estFresh: 2500) == 2500, "proj: extrapolation clamped to estFresh")
// Equals workDone exactly at age == ageAtLastCommit (no extrapolation yet).
check(prefillProjectedDone(workDone: 2048, ageAtLastCommit: 7, age: 7, rate: 250, estFresh: 4900) == 2048, "proj: at age==ageAtLastCommit -> workDone")
// Never exceeds estFresh even over a long elapsed time.
check(prefillProjectedDone(workDone: 0, ageAtLastCommit: 0, age: 100, rate: 250, estFresh: 4900) == 4900, "proj: clamped, never exceeds estFresh")
// Never below workDone (the counter is the truth), even if age < ageAtLastCommit.
check(prefillProjectedDone(workDone: 2048, ageAtLastCommit: 10, age: 5, rate: 250, estFresh: 4900) == 2048, "proj: age < ageAtLastCommit -> not below workDone")
// Nil rate -> stepped counter (honest fallback, unchanged behavior).
check(prefillProjectedDone(workDone: 2048, ageAtLastCommit: 7, age: 10, rate: nil, estFresh: 4900) == 2048, "proj: nil rate -> workDone")
check(prefillProjectedDone(workDone: 2048, ageAtLastCommit: 7, age: 10, rate: 0, estFresh: 4900) == 2048, "proj: zero rate -> workDone")
// NaN safety: a nonfinite input yields a finite (safe) result, not NaN.
check(prefillProjectedDone(workDone: .nan, ageAtLastCommit: 0, age: 10, rate: 250, estFresh: 4900).isFinite, "proj: NaN workDone -> finite")
check(prefillProjectedDone(workDone: 2048, ageAtLastCommit: .nan, age: 10, rate: 250, estFresh: 4900).isFinite, "proj: NaN ageAtLastCommit -> finite")
do { // monotone non-decreasing over a sweep of age
    var last = -Double.greatestFiniteMagnitude
    var mono = true
    for t in stride(from: 0.0, through: 30.0, by: 0.5) {
        let v = prefillProjectedDone(workDone: 2048, ageAtLastCommit: 7, age: t, rate: 250, estFresh: 4900)
        if v < last { mono = false; break }
        last = v
    }
    check(mono, "proj: monotone in age")
}
// done == estFresh -> pct 100 / eta 0
if let p = prefillPct(done: 4900, estFresh: 4900) { check(p == 100, "eta: done==estFresh -> pct 100") }
check(prefillEta(done: 4900, estFresh: 4900, rate: 250) == 0, "eta: done==estFresh -> eta 0")
check(telemetryInt(12) == 12 && telemetryInt(12.5) == 12, "telemetry: representable integers")
check(telemetryInt(nil) == 0 && telemetryInt(.nan) == 0 && telemetryInt(.infinity) == 0, "telemetry: missing and nonfinite are safe")
check(telemetryInt(Double(Int.max)) == 0 && telemetryInt(-Double.greatestFiniteMagnitude) == 0, "telemetry: out-of-range values are safe")
check(rssBytesFromPsOutput(" 437072\n") == 447561728, "RSS: KiB converted to bytes")
check(rssBytesFromPsOutput("0") == 0, "RSS: zero")
check(rssBytesFromPsOutput("") == nil, "RSS: empty")
check(rssBytesFromPsOutput("NaN") == nil, "RSS: malformed")
check(rssBytesFromPsOutput("-1") == nil, "RSS: negative")
check(rssBytesFromPsOutput(String(Int64.max)) == nil, "RSS: overflow")

// ---- config.json store (S1a): parse / migrate / serialize / defaults / store ----

// 1. JSONValue canonical form: deterministic key order, escapes, number rendering.
do {
    let a = JSONValue.object(["b": .number(2), "a": .string("x\ny")])
    let b = JSONValue.object(["a": .string("x\ny"), "b": .number(2)])
    check(canonicalJSONString(a) == canonicalJSONString(b), "cfg: canonical key order is deterministic")
    check(canonicalJSONString(a) == "{\"a\":\"x\\ny\",\"b\":2}", "cfg: canonical renders sorted keys + escapes + integer numbers")
    check(canonicalJSONString(.number(240.5)) == "240.5", "cfg: fractional numbers keep the fraction")
    check(canonicalJSONString(.array([.null, .bool(true), .string("s")])) == "[null,true,\"s\"]", "cfg: mixed-type arrays")
    check(canonicalJSONString(.object(["a": .object(["c": .null])])) == "{\"a\":{\"c\":null}}", "cfg: nested objects")
}

// 2. defaultConfig regression anchor (D9): the 9 documented vars, encoded as data.
do {
    let d = defaultConfig(home: "/home", now: now)
    check(d.globals.port == 8123, "default: port 8123")
    check(d.globals.apiKey == "splash-standalone-1", "default: key splash-standalone-1")
    let ids = d.globals.modelFolders.map { $0.id }
    check(ids == ["lmstudio", "ollama", "hfhub", "splash", "installroot"], "default: the 5 documented auto roots, in order")
    let paths = d.globals.modelFolders.map { $0.path }
    check(paths == ["/home/.lmstudio/models", "/home/.ollama/models",
                    "/home/.cache/huggingface/hub",
                    "/home/Library/Application Support/Splash/models",
                    "/home/SplashUI/models"], "default: the 5 documented root paths")
    check(d.globals.modelFolders.allSatisfy { $0.source == "auto" }, "default: roots tagged source auto")
    check(d.globals.engine.mode == "auto" && d.globals.engine.brew && d.globals.engine.manualPath == nil,
          "default: engine auto (full discovery ladder) + brew rung on")
    check(d.profiles.count == 1 && d.profiles[0].name == "Default", "default: one profile named Default")
    check(d.activeProfile == d.profiles[0].id && d.profiles[0].id.hasPrefix("p-"),
          "default: active = the Default profile, app-generated id")
    let o = d.profiles[0].options
    check(o["max_cache_disk"]?.string == "100g", "default: max_cache_disk 100g")
    check(o["idle_release"]?.string == "240m", "default: idle_release 240m")
    check(o["ane"]?.bool == true, "default: ANE on (binding decision)")
    check(o["persistent_cache"]?.bool == true, "default: persistent cache on (today's hardcoded --persistent-cache)")
    check(d.profiles[0].model.source == "lmstudio" && d.profiles[0].model.id == "incoai/Qwen3.8-27B-Splash"
          && d.profiles[0].model.dir == nil, "default: the documented model (lmstudio package; dir resolves at scan)")
    check(d.profiles[0].meta.createdAt != nil, "default: created_at stamped")
}

// 3. Round-trip: parseConfig(configData(doc)) == doc; schema_version stamped.
do {
    let d = defaultConfig(home: "/home", now: now)
    let data = configData(d)
    let (d2, err, dropped) = parseConfig(data)
    check(err == nil, "cfg: round-trip parses cleanly")
    check(dropped.isEmpty, "cfg: round-trip drops nothing")
    check(d2 == d, "cfg: round-trip is identity")
    check(String(data: data, encoding: .utf8)?.contains("\"schema_version\": 1") == true,
          "cfg: current schema_version stamped on write")
}

// 4. Unknown top-level keys are preserved verbatim (forward-compat).
do {
    var d = defaultConfig(home: "/home", now: now)
    d.reserved["experimental"] = .object(["feature_flags": .object(["beta_ui": .bool(true)])])
    d.reserved["note"] = .string("hand-edited")
    let (d2, err, _) = parseConfig(configData(d))
    check(err == nil, "cfg: doc with unknown top-level keys parses")
    check(d2 == d, "cfg: unknown top-level keys preserved through round-trip")
    let out = String(data: configData(d2!), encoding: .utf8)!
    check(out.contains("\"experimental\"") && out.contains("\"feature_flags\"") && out.contains("\"beta_ui\""),
          "cfg: unknown top-level keys re-serialized verbatim")
}

// 5. Unknown keys inside globals/profile entries are dropped (reported, not written back).
do {
    let txt = """
    {"schema_version":1,
     "globals":{"engine":{"mode":"auto","manual_path":null,"brew":true,"custom_engine":7},
                "model_folders":[],"port":8123,"api_key":"k","mystery":"x"},
     "profiles":[{"id":"p1","name":"A","extra":"drop","model":{"source":"none","id":null,"dir":null},"options":{},"meta":{}}],
     "active_profile":"p1"}
    """
    let (d, err, dropped) = parseConfig(Data(txt.utf8))
    check(err == nil, "cfg: file with unknown nested keys still parses")
    check(dropped.contains("globals.mystery") && dropped.contains("globals.engine.custom_engine")
          && dropped.contains("profiles[0].extra"), "cfg: unknown nested keys reported for the console log")
    let out = String(data: configData(d!), encoding: .utf8)!
    check(!out.contains("mystery") && !out.contains("custom_engine") && !out.contains("\"extra\""),
          "cfg: unknown nested keys not written back")
}

// 6. Corrupt: unparseable / strict-type-violating files are flagged, never repaired in place.
do {
    let (d, err, _) = parseConfig(Data("this is not json".utf8))
    check(d == nil, "cfg: corrupt (not JSON) -> no doc")
    if case .invalidFormat = err { check(true, "cfg: corrupt -> invalidFormat") }
    else { check(false, "cfg: corrupt -> invalidFormat") }
}
do {
    func bad(_ field: String) -> Data {
        Data("{\"schema_version\":1,\"globals\":{\(field)},\"profiles\":[],\"active_profile\":null}".utf8)
    }
    let cases: [(String, Data, String)] = [
        ("string port", bad("\"port\":\"8123\""), "port"),
        ("empty api_key", bad("\"port\":8123,\"api_key\":\"\""), "api_key"),
        ("port 0", bad("\"port\":0"), "port"),
        ("port 65536", bad("\"port\":65536"), "port"),
        ("unknown engine mode", bad("\"engine\":{\"mode\":\"sometimes\"}"), "mode"),
        ("bool where int expected", bad("\"port\":true"), "port"),
    ]
    for (label, data, needle) in cases {
        let (_, err, _) = parseConfig(data)
        if case .invalidFormat(let msg) = err {
            check(msg.contains(needle), "cfg: corrupt(\(label)) -> invalidFormat names the field")
        } else {
            check(false, "cfg: corrupt(\(label)) -> invalidFormat names the field")
        }
    }
    // Missing known fields -> defaults (lenient), not corrupt.
    let t = Data("{\"schema_version\":1,\"globals\":{},\"profiles\":[],\"active_profile\":null}".utf8)
    let (td, te, _) = parseConfig(t)
    check(te == nil && td?.globals.port == 8123 && td?.globals.apiKey == "splash-standalone-1",
          "cfg: missing known fields fall back to defaults (not corrupt)")
}

// 7. version > app -> read-only load, never written.
do {
    let txt = """
    {"schema_version":2,
     "globals":{"port":9999,"api_key":"k2","model_folders":[],"engine":{"mode":"manual","manual_path":"/x","brew":false}},
     "profiles":[{"id":"p9","name":"Fwd","model":{"source":"hfid","id":"x/y","dir":null},"options":{"state_format":"bf16"},"meta":{"created_at":"t"}}],
     "active_profile":"p9"}
    """
    let (d, err, _) = parseConfig(Data(txt.utf8))
    check(d != nil, "cfg: newer version still loads (read-only display)")
    if case .versionTooNew(let f, let a)? = err { check(f == 2 && a == 1, "cfg: versionTooNew carries file/app versions") }
    else { check(false, "cfg: versionTooNew carries file/app versions") }
    var wrote = false
    let store = ConfigStore(home: "/home", path: "/h/SplashUI/config.json",
                            read: { _ in Data(txt.utf8) },
                            write: { _, _ in wrote = true; return true },
                            ensureDir: { _, _ in true })
    let r = store.saveCurrent()
    check(store.versionTooNew, "store: newer file version -> read-only")
    check(!r.ok && wrote == false, "store: read-only store refuses to write (file untouched)")
    check(r.errors.first?.contains("2") == true, "store: refusal names the file's version")
    check(store.doc.globals.port == 9999, "store: read-only store shows the forward doc's values")
}

// 8. Migration: v1 identity; pre-v1 clamps; the ordered migrator is a no-op at v1.
do {
    let d = defaultConfig(home: "/home", now: now)
    check(migrate(d, from: 1, to: 1) == d, "migrate: v1->v1 identity")
    check(migrate(d, from: 0, to: 1) == d, "migrate: pre-v1 clamps to v1 (identity)")
    let txt = """
    {"schema_version":0,
     "globals":{"port":8123,"api_key":"k0","model_folders":[],"engine":{"mode":"auto","brew":true}},
     "profiles":[],"active_profile":null}
    """
    let (d2, err, _) = parseConfig(Data(txt.utf8))
    check(err == nil && d2?.globals.port == 8123, "cfg: pre-v1 file loads (clamped, identity migration)")
}

// 9. Store: corrupt file -> last-good in memory + load_error, file untouched.
do {
    let good = defaultConfig(home: "/home", now: now)
    let goodData = configData(good)
    let corrupt = Data("}{ not json".utf8)
    var fileData: Data? = goodData
    var writes = 0
    let path = "/h/Library/Application Support/SplashUI/config.json"
    let store = ConfigStore(home: "/home", path: path,
                            read: { _ in fileData },
                            write: { d, _ in writes += 1; fileData = d; return true },
                            ensureDir: { _, _ in true })
    check(store.doc == good && store.loadError == nil, "store: clean load keeps the file's doc")
    fileData = corrupt
    store.load()
    check(store.doc == good, "store: corrupt file -> last-good stays in memory")
    check(store.loadError != nil, "store: corrupt file -> load_error surfaced")
    check(fileData == corrupt && writes == 0, "store: corrupt file left untouched (never repaired)")
    // A fresh store (no last-good) on a corrupt file -> the documented defaults.
    fileData = corrupt
    let s2 = ConfigStore(home: "/home", path: path,
                         read: { _ in fileData },
                         write: { _, _ in true },
                         ensureDir: { _, _ in true })
    check(s2.loadError != nil, "store: corrupt, no last-good -> load_error")
    check(s2.doc.globals.port == 8123 && s2.doc.globals.apiKey == "splash-standalone-1",
          "store: corrupt, no last-good -> documented defaults")
    check(s2.doc.profiles.count == 1 && s2.doc.profiles[0].name == "Default",
          "store: corrupt, no last-good -> Default profile from defaults")
}

// 10. Store: absent file -> first-run seed (S1b, D10/R10): written exactly once,
// first_run true; the next load with the file present does not re-seed.
do {
    var writes = 0
    var fileData: Data? = nil
    let store = ConfigStore(home: "/home", path: "/h/x/config.json",
                            read: { _ in fileData },
                            write: { d, _ in writes += 1; fileData = d; return true },
                            ensureDir: { _, _ in true },
                            brewKeg: { nil }, kitVersion: { _ in nil }, isDir: { _ in false })
    check(store.firstRun, "store: absent file -> first_run true (the seed ran)")
    check(writes == 1, "store: absent file -> the seed is written exactly once (R10, single owner)")
    check(fileData == configData(store.doc), "store: the seeded bytes == the canonical serialization of the in-memory doc")
    check(store.loadError == nil && !store.versionTooNew, "store: seed -> healthy load state")
    store.load()
    check(writes == 1, "store: the next load finds the seeded file -> no re-seed")
    check(!store.firstRun, "store: the next launch -> first_run false (one-shot per launch)")
}

// 11. Store save: validate + atomic write + in-memory update + result stamping.
do {
    let good = defaultConfig(home: "/home", now: now)
    var fileData: Data? = configData(good)
    var writes = 0
    let store = ConfigStore(home: "/home", path: "/h/x/config.json",
                            read: { _ in fileData },
                            write: { d, _ in writes += 1; fileData = d; return true },
                            ensureDir: { _, _ in true })
    var cand = good
    cand.globals.port = 9000
    let r = store.save(candidate: cand)
    check(r.ok, "store: valid save succeeds")
    check(writes == 1, "store: one atomic write per save")
    check(fileData == configData(cand), "store: written bytes == canonical serialization")
    check(store.doc == cand, "store: save updates the in-memory doc")
    check(store.saveResult?.ok == true, "store: save stamps the result for the tick")
    // A save that fails validation: no write, doc unchanged, error stamp.
    var badCand = cand
    badCand.globals.port = 0
    let rb = store.save(candidate: badCand)
    check(!rb.ok && writes == 1, "store: invalid save refuses without writing")
    check(store.doc == cand, "store: in-memory doc unchanged after a refused save")
    check(store.saveResult?.ok == false, "store: refused save stamps the error")
    // A write failure (disk full / perms): doc unchanged, error stamp.
    let storeFail = ConfigStore(home: "/home", path: "/h/x/config.json",
                                read: { _ in fileData },
                                write: { _, _ in false },
                                ensureDir: { _, _ in true })
    let before = storeFail.doc
    let rf = storeFail.save(candidate: cand)
    check(!rf.ok && storeFail.doc == before, "store: failed write leaves the doc untouched")
}

// 12. saveCandidate (the bridge entry): parse + validate + write.
do {
    let txt = """
    {"schema_version":1,
     "globals":{"port":8200,"api_key":"k","model_folders":[],"engine":{"mode":"auto","brew":true}},
     "profiles":[{"id":"p1","name":"A","model":{"source":"none","id":null,"dir":null},"options":{"kv_format":"int8"},"meta":{"created_at":"t"}}],
     "active_profile":"p1"}
    """
    var writes = 0
    var fileData: Data? = Data(txt.utf8)   // present at load: no first-run seed in this test
    let store = ConfigStore(home: "/home", path: "/h/x/config.json",
                            read: { _ in fileData },
                            write: { d, _ in writes += 1; fileData = d; return true },
                            ensureDir: { _, _ in true },
                            brewKeg: { nil }, kitVersion: { _ in nil }, isDir: { _ in false })
    let r = store.saveCandidate(Data(txt.utf8))
    check(r.ok && writes == 1, "store: saveCandidate parses + writes a valid doc")
    check(store.doc.globals.port == 8200, "store: candidate values land in memory")
    check(String(data: configData(store.doc), encoding: .utf8)!.contains("\"schema_version\": 1"),
          "store: current schema_version stamped on the saved doc")
    let bad = Data("{\"schema_version\":1,\"globals\":{\"port\":\"nope\"},\"profiles\":[],\"active_profile\":null}".utf8)
    let r2 = store.saveCandidate(bad)
    check(!r2.ok && writes == 1, "store: saveCandidate with a type error refuses without writing")
    check(store.doc.globals.port == 8200, "store: in-memory doc unchanged after a refused candidate")
    let fwd = Data("{\"schema_version\":9,\"globals\":{\"port\":8200},\"profiles\":[],\"active_profile\":null}".utf8)
    let r3 = store.saveCandidate(fwd)
    check(!r3.ok && writes == 1, "store: forward-version candidate refused (never destroys forward data)")
}

// 13. Save validation rules (pure).
do {
    let d = defaultConfig(home: "/home", now: now)
    check(validateConfig(d).ok, "validate: default config is valid")
    var dup = d
    var clone = dup.profiles[0]
    clone.id = "p-2-xyz"
    dup.profiles.append(clone)
    let rv = validateConfig(dup)
    check(!rv.ok && rv.errors.contains(where: { $0.contains("Default") }), "validate: duplicate profile name rejected")
    var badPort = d
    badPort.globals.port = 0
    check(!validateConfig(badPort).ok, "validate: port 0 rejected")
    var dang = d
    dang.activeProfile = "p-nope"
    let rd = validateConfig(dang)
    check(rd.ok && rd.warnings.contains(where: { $0.contains("active_profile") }),
          "validate: dangling active_profile warns (never blocks)")
    let (norm, invalid) = normalizeConfig(dang)
    check(norm.activeProfile == nil && invalid, "normalize: dangling active -> null + active_invalid")
    var man = d
    man.globals.engine.mode = "manual"
    man.globals.engine.manualPath = nil
    let rm = validateConfig(man)
    check(rm.ok && rm.warnings.contains(where: { $0.contains("manual") }),
          "validate: manual mode without a path warns (never blocks)")
}

// 14. Masking: len + first/last 4; the raw key never appears.
do {
    check(maskSecret("splash-standalone-1") == "19 ch · spla…ne-1", "mask: len + first/last 4")
    check(!maskSecret("splash-standalone-1").contains("splash-standalone-1"), "mask: raw key never appears")
    check(maskSecret("abc") == "3 ch · •••", "mask: short keys fully masked")
    check(maskSecret("") == "0 ch · •••", "mask: empty key masked, not echoed")
}

// 15. configTickPayload + the change gate.
do {
    let d = defaultConfig(home: "/home", now: now)
    func payload(_ doc: ConfigDoc, inFlight: Int = 0, result: ConfigSaveResult? = nil) -> [String: Any] {
        configTickPayload(doc: doc, loadError: nil, versionTooNew: false, activeInvalid: false,
                          firstRun: false, inFlight: inFlight, result: result)
    }
    let p1 = payload(d)
    let keys = ["load_error", "version_too_new", "engine", "folders", "port", "api_key_masked",
                "profiles", "active_profile", "active_invalid", "mapping_fallback", "mapping_used",
                "registry_report", "first_run", "restart_required", "restart_reason", "in_flight",
                "result", "picked"]
    for k in keys { check(p1[k] != nil, "cfg payload: carries \(k)") }
    check(p1["port"] as? Int == 8123, "cfg payload: port")
    check(p1["api_key_masked"] as? String == "19 ch · spla…ne-1", "cfg payload: api_key masked")
    let canon1 = canonicalJSONString(JSONValue(any: p1))
    check(!canon1.contains("splash-standalone-1"), "cfg payload: raw key never in the tick")
    let p2 = payload(d)
    check(canonicalJSONString(JSONValue(any: p2)) == canon1, "change-gate: unchanged config -> stable canonical form")
    var d2 = d
    d2.globals.port = 8124
    check(canonicalJSONString(JSONValue(any: payload(d2))) != canon1, "change-gate: changed config -> new canonical form")
    let pr = payload(d, inFlight: 1, result: ConfigSaveResult(ok: true, errors: [], warnings: ["w1"]))
    check(pr["in_flight"] as? Int == 1, "cfg payload: in_flight count")
    check((pr["result"] as? [String: Any])?["ok"] as? Bool == true
          && ((pr["result"] as? [String: Any])?["warnings"] as? [String])?.contains("w1") == true,
          "cfg payload: result stamp {ok, errors, warnings}")
    let pe = configTickPayload(doc: d, loadError: "boom", versionTooNew: true, activeInvalid: false,
                               firstRun: false, inFlight: 0, result: nil)
    check(pe["load_error"] as? String == "boom" && pe["version_too_new"] as? Bool == true,
          "cfg payload: load_error + version_too_new surface")
    // Reserved top-level keys ride along so the JS draft can carry them through a save.
    var d3 = d
    d3.reserved["experimental"] = .object(["beta_ui": .bool(true)])
    check(canonicalJSONString(JSONValue(any: payload(d3))).contains("experimental"),
          "cfg payload: reserved top-level keys ride along")
    // The one-shot result round-trip: stamped once, then nulled (the gate flips, then settles).
    let withRes = canonicalJSONString(JSONValue(any: payload(d, result: ConfigSaveResult(ok: true, errors: [], warnings: []))))
    let withoutRes = canonicalJSONString(JSONValue(any: payload(d, result: nil)))
    check(withRes != canon1 && withoutRes == canon1, "change-gate: result stamp flips the gate exactly once")
}

// 16. Real filesystem (the store's default closures): 0700 dir, 0600 file, atomic rename.
do {
    let home = "/tmp/splashui-s1a-\(ProcessInfo.processInfo.processIdentifier)"
    try? FileManager.default.removeItem(atPath: home)
    let store = ConfigStore(home: home, brewKeg: { nil }, kitVersion: { _ in nil }, isDir: { _ in false })   // real FS closures; fake detection (hermetic seed)
    var cand = defaultConfig(home: home, now: now)
    cand.globals.port = 8124
    let r = store.save(candidate: cand)
    let path = home + "/Library/Application Support/SplashUI/config.json"
    let mode = ((try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int) ?? -1
    check(r.ok, "store(fs): save succeeds on the real filesystem")
    check(mode == 0o600, "store(fs): file mode 0600 (the API key)")
    let dirMode = ((try? FileManager.default.attributesOfItem(atPath: home + "/Library/Application Support/SplashUI"))?[.posixPermissions] as? Int) ?? -1
    check(dirMode == 0o700, "store(fs): parent dir mode 0700")
    check(!FileManager.default.fileExists(atPath: path + ".tmp"), "store(fs): no stray tmp file after the atomic rename")
    if let fileData = FileManager.default.contents(atPath: path) {
        let re = parseConfig(fileData)
        check(re.doc?.globals.port == 8124, "store(fs): the saved file re-parses with the change")
    } else {
        check(false, "store(fs): the saved file re-parses with the change")
    }
    let s2 = ConfigStore(home: home, brewKeg: { nil }, kitVersion: { _ in nil }, isDir: { _ in false })
    check(s2.doc == cand && s2.loadError == nil, "store(fs): a fresh store reloads the saved file cleanly")
    try? FileManager.default.removeItem(atPath: home)
}

// ---- first-run seed + startup activation (S1b: D10/D11/D12) ----------------

// 17. firstRunConfig: a Homebrew keg (1.3.1+) -> engine auto + one "Default"
// profile preconfigured with that runtime's default model (MLX hfid).
do {
    let d = firstRunConfig(home: "/home",
                           brewKeg: { "/opt/homebrew/Cellar/splash/1.3.1" },
                           kitVersion: { $0 == "/opt/homebrew/Cellar/splash/1.3.1/libexec" ? "1.3.1" : nil },
                           isDir: { $0 == "/opt/homebrew/Cellar/splash/1.3.1/libexec" },
                           now: now)
    check(d.globals.engine.mode == "auto" && d.globals.engine.manualPath == nil && d.globals.engine.brew,
          "firstRun: keg detected -> engine auto (D2 ladder), brew rung on")
    check(d.globals.port == 8123 && d.globals.apiKey == "splash-standalone-1", "firstRun: documented defaults")
    let ids = d.globals.modelFolders.map { $0.id }
    check(ids == ["lmstudio", "ollama", "hfhub", "splash", "installroot"], "firstRun: the 5 auto model roots")
    check(d.globals.modelFolders.allSatisfy { $0.source == "auto" }, "firstRun: roots tagged source auto")
    check(d.profiles.count == 1 && d.profiles[0].name == "Default", "firstRun: one profile named Default (D11)")
    check(d.profiles[0].model.source == "hfid" && d.profiles[0].model.id == "mlx-community/Qwen3.8-27B-4bit"
          && d.profiles[0].model.dir == nil, "firstRun: 1.3.1+ keg -> the runtime's default MLX model by id")
    check(d.profiles[0].options["ane"]?.bool == true, "firstRun: ANE on (binding decision)")
    check(d.profiles[0].options["max_cache_disk"]?.string == "100g"
          && d.profiles[0].options["idle_release"]?.string == "240m"
          && d.profiles[0].options["persistent_cache"]?.bool == true, "firstRun: the documented per-profile defaults")
    check(d.activeProfile == d.profiles[0].id && d.profiles[0].id.hasPrefix("p-"), "firstRun: active = the Default profile")
    check(d.profiles[0].meta.createdAt != nil && d.profiles[0].meta.lastUsedAt == nil,
          "firstRun: created_at stamped, not yet used")
    check(d.reserved.isEmpty, "firstRun: no reserved keys")
}

// 18. firstRunConfig: a 1.3.0-style keg -> the 1.3.0 package (the module flavor
// default); an unreadable version defaults to the module flavor too.
do {
    func make(_ version: String?) -> ConfigDoc {
        firstRunConfig(home: "/home",
                       brewKeg: { "/brew/Cellar/splash/1.3.0" },
                       kitVersion: { _ in version },
                       isDir: { $0 == "/brew/Cellar/splash/1.3.0/libexec" },
                       now: now)
    }
    let d = make("1.3.0")
    check(d.globals.engine.mode == "auto", "firstRun: 1.3.0 keg -> engine auto")
    check(d.profiles[0].model.source == "lmstudio" && d.profiles[0].model.id == "incoai/Qwen3.8-27B-Splash"
          && d.profiles[0].model.dir == nil, "firstRun: 1.3.0 keg -> the local package (the 1.3.0 flavor's default)")
    let dn = make(nil)   // resolveSplashPaths does the same: unknown version -> module flavor
    check(dn.globals.engine.mode == "auto" && dn.profiles[0].model.source == "lmstudio"
          && dn.profiles[0].model.id == "incoai/Qwen3.8-27B-Splash",
          "firstRun: keg with an unreadable version -> the 1.3.0 flavor")
}

// 19. firstRunConfig: no runtime detected -> engine manual + empty path + model
// unset (unrunnable until the user configures an engine, D10).
do {
    let d = firstRunConfig(home: "/home", brewKeg: { nil }, kitVersion: { _ in nil },
                           isDir: { _ in false }, now: now)
    check(d.globals.engine.mode == "manual" && d.globals.engine.manualPath == nil,
          "firstRun: no runtime -> manual + empty path (D10)")
    check(d.profiles[0].model.source == "none" && d.profiles[0].model.id == nil && d.profiles[0].model.dir == nil,
          "firstRun: no runtime -> model unset (unrunnable until configured)")
    check(d.activeProfile == d.profiles[0].id && d.profiles[0].name == "Default", "firstRun: active = the unrunnable Default")
    check(d.profiles[0].meta.createdAt != nil, "firstRun: created_at stamped")
    let stale = firstRunConfig(home: "/home", brewKeg: { "/stale/keg" }, kitVersion: { _ in "1.3.1" },
                               isDir: { _ in false }, now: now)
    check(stale.globals.engine.mode == "manual" && stale.globals.engine.manualPath == nil
          && stale.profiles[0].model.source == "none",
          "firstRun: a keg that is not a real directory is treated as absent")
}

// 20. startupActivation (D12): most-recent last_used_at -> tie -> persisted id -> first.
do {
    func p(_ id: String, _ used: String?) -> Profile {
        Profile(id: id, name: id, model: ProfileModel(source: "none"), meta: ProfileMeta(lastUsedAt: used))
    }
    let a = p("p-a", "2026-01-01T00:00:00Z")
    let b = p("p-b", "2026-01-02T00:00:00Z")
    let c = p("p-c", "2026-01-03T00:00:00Z")
    check(startupActivation([a, b, c], persistedActive: "p-a") == "p-c", "activate: the most recent last_used_at wins")
    check(startupActivation([a, p("p-b2", "2026-01-03T00:00:00Z"), c], persistedActive: "p-a") == "p-a",
          "activate: tie on the most recent -> the persisted id")
    check(startupActivation([p("p-b2", "2026-01-03T00:00:00Z"), c], persistedActive: nil) == "p-b2",
          "activate: tie + no persisted id -> first in array order")
    check(startupActivation([a, p("p-b", nil), c], persistedActive: "p-a") == "p-c",
          "activate: a nil last_used_at never beats a dated one")
    let nils = [p("p-x", nil), p("p-y", nil)]
    check(startupActivation(nils, persistedActive: "p-y") == "p-y", "activate: all-nil -> the persisted id")
    check(startupActivation(nils, persistedActive: nil) == "p-x", "activate: all-nil + no persisted -> first profile")
    check(startupActivation(nils, persistedActive: "p-nope") == "p-x", "activate: a dangling persisted id -> first profile")
    check(startupActivation([a], persistedActive: nil) == "p-a"
          && startupActivation([a], persistedActive: "p-other") == "p-a",
          "activate: a single profile is always the pick")
    check(startupActivation([], persistedActive: "p-a") == nil, "activate: no profiles -> nil")
    check(startupActivation([p("p-bad", "not-a-timestamp"), c], persistedActive: "p-a") == "p-c",
          "activate: an unparseable timestamp is treated as unused")
    // created_at never participates in the recency rule.
    let createdOnly = Profile(id: "p-cr", name: "cr", model: ProfileModel(source: "none"),
                              meta: ProfileMeta(createdAt: "2026-12-31T00:00:00Z"))
    check(startupActivation([createdOnly, a], persistedActive: "p-a") == "p-a",
          "activate: created_at (without last_used_at) does not win recency")
}

// 21. Store: file absent + keg detected -> the seed is written once (R10) with
// the detected runtime; startup activation on a fresh seed writes nothing extra.
do {
    var writes = 0
    var fileData: Data? = nil
    let store = ConfigStore(home: "/home", path: "/h/x/config.json",
                            read: { _ in fileData },
                            write: { d, _ in writes += 1; fileData = d; return true },
                            ensureDir: { _, _ in true },
                            brewKeg: { "/brew/keg" },
                            kitVersion: { _ in "1.3.1" },
                            isDir: { $0 == "/brew/keg/libexec" })
    check(store.firstRun && writes == 1, "store: keg seed -> first_run true + exactly one write")
    check(store.doc.globals.engine.mode == "auto" && store.doc.profiles[0].model.id == "mlx-community/Qwen3.8-27B-4bit",
          "store: the seed carries the detected runtime (auto + MLX hfid)")
    store.activateStartup(now: now)
    check(writes == 1, "store: activation on a fresh seed writes nothing extra (the seed IS the persistence)")
    check(store.doc.profiles[0].meta.lastUsedAt != nil, "store: the startup pick stamps last_used_at (D13)")
    check(store.doc.activeProfile == store.doc.profiles[0].id, "store: the fresh seed stays on its own Default")
    // A real FS round-trip of the same scenario (0600 file, re-armed only on deletion).
    let home = "/tmp/splashui-s1b-\(ProcessInfo.processInfo.processIdentifier)"
    try? FileManager.default.removeItem(atPath: home)
    let fs = ConfigStore(home: home, brewKeg: { "/brew/keg" }, kitVersion: { _ in "1.3.1" }, isDir: { $0 == "/brew/keg/libexec" })
    let path = home + "/Library/Application Support/SplashUI/config.json"
    let mode = ((try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int) ?? -1
    check(FileManager.default.fileExists(atPath: path) && mode == 0o600, "store(fs): the first-run seed lands 0600")
    check(fs.firstRun, "store(fs): first_run true on the seeded launch")
    let s2 = ConfigStore(home: home, brewKeg: { "/brew/keg" }, kitVersion: { _ in "1.3.1" }, isDir: { $0 == "/brew/keg/libexec" })
    check(!s2.firstRun, "store(fs): the seeded file present -> the next launch is not first-run")
    try? FileManager.default.removeItem(atPath: home)
}

// 22. Store: startup activation picks by recency and persists the changed choice
// (one explicit save before the first launch, D12/D13); an unchanged pick stamps
// in memory only (D15: no background writes).
do {
    let tNow = Date(timeIntervalSince1970: 2_000_000_000)   // after every fixture timestamp below
    func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
    var writes = 0
    var fileData: Data? = nil
    let store = ConfigStore(home: "/home", path: "/h/x/config.json",
                            read: { _ in fileData },
                            write: { d, _ in writes += 1; fileData = d; return true },
                            ensureDir: { _, _ in true },
                            brewKeg: { nil }, kitVersion: { _ in nil }, isDir: { _ in false })
    check(writes == 1, "store: the no-runtime seed wrote once")
    // The user's history so far: two profiles, "Work" last used after "Default".
    var d = store.doc
    var work = d.profiles[0]
    work.id = "p-second-aaa1"; work.name = "Work"
    work.meta.lastUsedAt = "2026-01-05T00:00:00Z"
    d.profiles.append(work)
    d.profiles[0].meta.lastUsedAt = "2026-01-01T00:00:00Z"
    d.activeProfile = "p-second-aaa1"   // as persisted by a previous config.save
    check(store.save(candidate: d).ok, "store: the history save succeeds")
    store.activateStartup(now: tNow)
    check(store.doc.activeProfile == "p-second-aaa1", "store: the recency pick stays the active profile")
    check(store.doc.profiles[1].meta.lastUsedAt == iso(tNow), "store: the pick stamps last_used_at (D13)")
    check(writes == 2, "store: pick == persisted active -> the stamp flushes with no extra write (D15)")
    // Now the persisted active is the OLDER profile: the pick flips it.
    var d2 = store.doc
    d2.activeProfile = d.profiles[0].id   // "Default" (older) is what the file persists
    check(store.save(candidate: d2).ok, "store: the flip-back save succeeds")
    let before = writes
    store.activateStartup(now: tNow)
    check(store.doc.activeProfile == "p-second-aaa1", "store: the D12 recency pick wins over the persisted id")
    check(writes == before + 1, "store: the changed choice is persisted with one explicit save")
    let (re, err, _) = parseConfig(fileData!)
    check(err == nil && re?.activeProfile == "p-second-aaa1", "store: the file on disk carries the D12 pick")
    check(re?.profiles[1].meta.lastUsedAt == iso(tNow), "store: the file carries the stamped last_used_at")
}

// 23. Store: activation never writes a corrupt file (S1a contract) or a
// version-too-new file (forward data is sacred); the pick still applies in memory.
do {
    let tNow = Date(timeIntervalSince1970: 2_000_000_000)
    var d = defaultConfig(home: "/home", now: now)
    var work = d.profiles[0]
    work.id = "p-second-aaa1"; work.name = "Work"; work.meta.lastUsedAt = "2026-01-05T00:00:00Z"
    d.profiles.append(work)
    d.profiles[0].meta.lastUsedAt = "2026-01-01T00:00:00Z"
    d.activeProfile = d.profiles[0].id   // the file persists the OLDER profile active
    var writes = 0
    var fileData: Data? = configData(d)
    let store = ConfigStore(home: "/home", path: "/h/x/config.json",
                            read: { _ in fileData },
                            write: { dd, _ in writes += 1; fileData = dd; return true },
                            ensureDir: { _, _ in true },
                            brewKeg: { nil }, kitVersion: { _ in nil }, isDir: { _ in false })
    check(!store.firstRun && writes == 0, "store: a present file never re-seeds")
    fileData = Data("}{ corrupt".utf8)
    store.load()
    store.activateStartup(now: tNow)
    check(writes == 0, "store: activation on a corrupt file never writes (the file is untouched)")
    check(store.doc.activeProfile == "p-second-aaa1", "store: the pick still applies in memory over a corrupt file")
    check(store.loadError != nil, "store: the corrupt load_error stays surfaced")
    let fwdTxt = "{\"schema_version\":9,\"globals\":{\"port\":8123,\"api_key\":\"k\",\"model_folders\":[],\"engine\":{\"mode\":\"auto\",\"brew\":true}},"
        + "\"profiles\":[{\"id\":\"p-x\",\"name\":\"X\",\"model\":{\"source\":\"none\"},\"options\":{},\"meta\":{\"last_used_at\":\"2026-01-01T00:00:00Z\"}},"
        + "{\"id\":\"p-y\",\"name\":\"Y\",\"model\":{\"source\":\"none\"},\"options\":{},\"meta\":{\"last_used_at\":\"2026-01-05T00:00:00Z\"}}],"
        + "\"active_profile\":\"p-x\"}"
    let fwd = Data(fwdTxt.utf8)
    fileData = fwd
    store.load()
    store.activateStartup(now: tNow)
    check(writes == 0, "store: activation on a version-too-new file never writes")
    check(store.doc.activeProfile == "p-y" && fileData == fwd, "store: the pick applies in memory; the forward file is byte-identical")
}

// 24. S1a-QA carry-over: UNKNOWN PROFILE OPTION KEYS (bool/number/string/null/
// object values) survive the load -> save round-trip (a value stored under a
// newer mapping must survive a downgrade; S7 shows them stale, never drops them).
do {
    let txt = """
    {"schema_version":1,
     "globals":{"port":8123,"api_key":"k","model_folders":[],"engine":{"mode":"auto","brew":true}},
     "profiles":[{"id":"p1","name":"A",
       "model":{"source":"hfid","id":"x/y","dir":null},
       "options":{"kv_format":"int8","future_flag":"2026","future_count":3.5,"future_bool":true,"future_null":null,"future_obj":{"a":1}},
       "meta":{}}],
     "active_profile":"p1"}
    """
    let (d, err, dropped) = parseConfig(Data(txt.utf8))
    check(err == nil, "options: unknown option keys parse")
    check(dropped.isEmpty, "options: unknown option keys are kept, not reported as dropped")
    let (d2, err2, _) = parseConfig(configData(d!))
    check(err2 == nil, "options: the round-trip re-parses")
    let o = d2!.profiles[0].options
    check(o["kv_format"] == .string("int8"), "options: the known key survives load->save")
    check(o["future_flag"] == .string("2026"), "options: unknown STRING value survives load->save")
    check(o["future_count"] == .number(3.5), "options: unknown NUMBER value survives load->save")
    check(o["future_bool"] == .bool(true), "options: unknown BOOL value survives load->save")
    check(o["future_null"] == .null, "options: unknown NULL value survives load->save")
    check(o["future_obj"] == .object(["a": .number(1)]), "options: unknown OBJECT value survives load->save")
    check(o.count == 6, "options: nothing was dropped from the flat options map")
}

// 25. cfg.first_run in the tick payload (one-shot per launch; S5 consumes it).
do {
    let d = defaultConfig(home: "/home", now: now)
    let pTrue = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                                  firstRun: true, inFlight: 0, result: nil)
    let pFalse = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                                   firstRun: false, inFlight: 0, result: nil)
    check(pTrue["first_run"] as? Bool == true, "cfg payload: first_run true rides the tick")
    check(pFalse["first_run"] as? Bool == false, "cfg payload: first_run false on a normal launch")
    check(canonicalJSONString(JSONValue(any: pTrue)) != canonicalJSONString(JSONValue(any: pFalse)),
          "change-gate: first_run flips the gate (the one-shot is visible exactly once)")
}

// ---- S2a: versioned contract registry + argv builder (C2/D3/D9(b)) ---------

// The golden 1.3.0 model dir (the install.sh layout: the default root's models/).
let goldenModelDir = "/home/SplashUI/models/incoai/Qwen3.8-27B-Splash"

// The EXACT argv today's resolveSplashPaths emits for the 1.3.0 kit under the
// 9 vars' documented defaults (test 26 pins it pristine; test 32's D9(b) anchor
// diffs the new builder's output against it).
let golden130Args: [String] = [
    "-u", "-m", "server.server", goldenModelDir,
    "--model", "incoai/Qwen3.8-27B-Splash",
    "--tokenizer", goldenModelDir + "/tokenizer",
    "--binary", "./engine/splash",
    "--host", "127.0.0.1", "--port", "8123",
    "--api-key", "splash-standalone-1", "--persistent-cache",
    "--max-cache-disk", "100g", "--idle-release", "240m",
]

// 26. GOLDEN BASELINE (D9(b)): drive the CURRENT resolveSplashPaths with every
// one of the 9 documented vars UNSET (their documented defaults: port 8123, key
// splash-standalone-1, 100g, 240m, ANE on, version 1.3.0, the install.sh layout)
// and verify it produces exactly the golden argv. Captured BEFORE any new code
// exists, so the baseline is pristine — if this ever fails, the baseline moved.
do {
    let (kd, ke) = kitPaths("/home/SplashUI/kit/splash-1.3.0-arm64-macos26")
    let g = resolveSplashPaths(
        env: [:],
        defaultRoot: "/home/SplashUI", home: "/home",
        isDir: { kd.contains($0) || $0 == goldenModelDir },
        isExecutable: { ke.contains($0) },
        kitVersion: { $0.hasPrefix("/home/SplashUI/kit") ? "1.3.0" : nil })
    check(g.error == nil, "golden: kit + model resolve under the documented defaults")
    check(g.workDir == "/home/SplashUI/kit/splash-1.3.0-arm64-macos26", "golden: workDir is the kit dir")
    check(g.engineArgs == golden130Args, "golden: the EXACT current 1.3.0 module argv (pristine baseline)")
}

// 27. contractFor: exact hits for the three authored versions (D16: keyed to the
// kit's release.json version; D3: fallback only for unseen versions).
do {
    let a = contractFor("1.3.0", registry: launchRegistry)
    check(a.fallback == false && a.contract.version == "1.3.0" && a.contract.flavor == .module,
          "contractFor: 1.3.0 -> the module contract, fallback false")
    let b = contractFor("1.3.1", registry: launchRegistry)
    check(b.fallback == false && b.contract.version == "1.3.1" && b.contract.flavor == .launcher,
          "contractFor: 1.3.1 -> the launcher contract, fallback false")
    let c = contractFor("1.3.2", registry: launchRegistry)
    check(c.fallback == false && c.contract.version == "1.3.2" && c.contract.flavor == .launcher,
          "contractFor: 1.3.2 -> the launcher contract, fallback false")
}

// 28. contractFor: unseen versions -> the LATEST authored (1.3.2) + fallback =
// true (D3: launch proceeds; S7 shows the "FALLBACK MAPPING" cap).
do {
    let newer = contractFor("1.3.3", registry: launchRegistry)
    check(newer.fallback == true && newer.contract.version == "1.3.2",
          "contractFor: unseen 1.3.3 -> the latest authored (1.3.2) + fallback")
    let older = contractFor("1.2.9", registry: launchRegistry)
    check(older.fallback == true && older.contract.version == "1.3.2",
          "contractFor: older 1.2.x -> the latest authored (1.3.2) + fallback")
    let unreadable = contractFor(nil, registry: launchRegistry)
    check(unreadable.fallback == true && unreadable.contract.version == "1.3.2",
          "contractFor: unreadable release.json (nil) -> the latest authored + fallback")
}

// 29. The 1.3.0 contract content (ground truth: the real kit's server.py parser +
// serve_options.py): 26 flags = the 23 shared (incl. --port) + the structural
// model trio; no family registry (packages bake the draft; assembly needs draft/).
do {
    let c = contract130
    check(c.version == "1.3.0" && c.flavor == .module, "contract 1.3.0: the module flavor")
    check(c.options.count == 26, "contract 1.3.0: the 26 verified flags")
    check(Set(c.options.map { $0.flag }) == [
        "--host", "--allowed-host", "--allowed-origin", "--api-key", "--no-webui",
        "--port", "--max-memory", "--max-context", "--kv-format", "--idle-release",
        "--max-cache-disk", "--persistent-cache", "--cache-dir", "--served-model-name",
        "--announce-served-name", "--default-reasoning-effort", "--max-request-size",
        "--max-image-pixels", "--request-timeout", "--queue-size", "--decode-share",
        "--disable-ane", "--allow-idle-sleep",
        "--model", "--tokenizer", "--binary",
    ], "contract 1.3.0: the exact flag set (23 shared + model/tokenizer/binary)")
    check(c.familyRegistry.isEmpty, "contract 1.3.0: no family registry (1.3.0 has no DFlash2 registry)")
    check(c.option("max_cache_disk")?.defValue == "0", "contract 1.3.0: --max-cache-disk engine default 0 (disabled)")
    check(c.option("idle_release")?.defValue == "10m", "contract 1.3.0: --idle-release engine default 10m")
    check(c.option("kv_format")?.defValue == "int8" && c.option("kv_format")?.choices == ["int8", "bf16"],
          "contract 1.3.0: --kv-format default int8, choices int8/bf16")
    check(c.option("api_key")?.secret == true && c.option("api_key")?.envVar == "SPLASH_API_KEY",
          "contract 1.3.0: --api-key is secret, env SPLASH_API_KEY (open item 5: the 1.3.0 server reads it from env)")
    check(c.option("host")?.alwaysEmit == true && c.option("host")?.defValue == "127.0.0.1",
          "contract 1.3.0: --host always emitted (the app is local-only; today's code hard-codes it)")
    check(c.option("port")?.alwaysEmit == true && c.option("port")?.defValue == "8000",
          "contract 1.3.0: --port always emitted (engine default 8000)")
    check(c.option("ane")?.flag == "--disable-ane" && c.option("ane")?.defValue == "true",
          "contract 1.3.0: ANE default-on = the inverted --disable-ane flag")
    check(c.option("persistent_cache")?.requires == ["max_cache_disk"],
          "contract 1.3.0: --persistent-cache requires --max-cache-disk (the engine's check_serve_arguments)")
}

// 30. The 1.3.1 contract: the shared 23 flags byte-identical to 1.3.0's (verified:
// the installed keg's serve_options.py is byte-identical to the 1.3.0 kit's), +
// the launcher model-axis flags, + the 2 verified DFlash2 family entries.
do {
    let c = contract131
    check(c.flavor == .launcher, "contract 1.3.1: the launcher flavor")
    let shared = contract130.options.filter { !$0.builtFromModel }
    let sharedKeys = Set(shared.map { $0.key })
    check(c.options.filter { sharedKeys.contains($0.key) } == shared,
          "contract 1.3.1: the shared 23 flags are byte-identical to 1.3.0's (keg == tag)")
    check(c.options.count == 28, "contract 1.3.1: 23 shared + model/revision/draft-model/language-only/offline")
    let axis = Set(["revision", "draft_model", "language_only", "offline"])
    check(Set(c.options.map { $0.key }).subtracting(["model"]).subtracting(
            Set(contract130.options.map { $0.key }).subtracting(["model", "tokenizer", "binary"])) == axis,
          "contract 1.3.1: the launcher-only model-axis flags (revision/draft_model/language_only/offline)")
    check(c.option("draft_model")?.group == "model" && c.option("revision")?.group == "model"
          && c.option("language_only")?.kind == .bool && c.option("offline")?.kind == .bool,
          "contract 1.3.1: the model-axis flags sit in the model group (language-only/offline are store_true)")
    check(c.familyRegistry == [
        "Qwen3.8-27B": "incoai/Qwen3.8-27B-DFlash2",
        "Qwen3.6-35B-A3B": "incoai/Qwen3.6-35B-A3B-DFlash2",
    ], "contract 1.3.1: the 2 verified DFlash2 family entries (the keg's install/families.py)")
}

// 31. The 1.3.2 contract (ground truth: the real 1.3.2 tag's serve_options.py):
// 1.3.1 + the 4 new flags; --max-cache-disk default 0 -> auto; --persistent-cache
// stays a plain store_true on the Python CLI (the "on|off" is the engine's shape).
do {
    let c = contract132
    check(c.flavor == .launcher, "contract 1.3.2: the launcher flavor")
    let newKeys = Set(["state_format", "max_cache_disk_writes", "thinking_token_budget", "thinking_end_text"])
    check(Set(c.options.map { $0.key }) == Set(contract131.options.map { $0.key }) | newKeys,
          "contract 1.3.2: 1.3.1's keys + exactly the 4 new flags")
    check(c.option("max_cache_disk")?.defValue == "auto",
          "contract 1.3.2: --max-cache-disk default auto (the 1.3.2 semantics change: <=32G free)")
    check(c.option("state_format")?.defValue == "fp32" && c.option("state_format")?.choices == ["fp32", "bf16"],
          "contract 1.3.2: --state-format {fp32,bf16}, engine default fp32")
    check(c.option("max_cache_disk_writes")?.defValue == "0",
          "contract 1.3.2: --max-cache-disk-writes default 0 (no limit)")
    check(c.option("thinking_token_budget")?.defValue == nil && c.option("thinking_end_text")?.defValue == nil,
          "contract 1.3.2: the thinking flags have no engine default (emit only when set)")
    check(c.option("persistent_cache")?.kind == .bool && c.option("persistent_cache")?.requires.isEmpty == true,
          "contract 1.3.2: --persistent-cache is still store_true and no longer requires --max-cache-disk (auto is non-zero)")
    check(c.option("max_cache_disk_writes")?.requires == ["max_cache_disk"],
          "contract 1.3.2: --max-cache-disk-writes requires the SSD cache (the 1.3.2 engine check)")
    check(c.familyRegistry == contract131.familyRegistry,
          "contract 1.3.2: the DFlash2 registry is the tag's families.py (unchanged from 1.3.1)")
}

// 32. THE D9(b) HEADLINE ANCHOR (amended per open item 5): with the seeded
// default config, the 1.3.0 module argv is byte-identical to the golden baseline
// EXCEPT the api key moves from argv to the child env as SPLASH_API_KEY.
do {
    let cfg = defaultConfig(home: "/home", now: now)
    let (contract, fallback) = contractFor("1.3.0", registry: launchRegistry)
    check(fallback == false, "anchor: the seeded-default engine (1.3.0) is an exact contract hit")
    let res = buildArgv(contract,
                        profileValues: cfg.profiles[0].options,
                        model: ProfileModel(source: "lmstudio", id: "incoai/Qwen3.8-27B-Splash", dir: goldenModelDir),
                        globals: cfg.globals)
    var expected = golden130Args
    if let i = expected.firstIndex(of: "--api-key") {
        expected.removeSubrange(i..<(i + 2))   // the amended anchor: the key moves to env
    }
    check(res.args == expected,
          "D9(b): the seeded-default 1.3.0 module argv is byte-identical EXCEPT --api-key moved to env")
    check(res.env == ["SPLASH_API_KEY": "splash-standalone-1"], "D9(b): the key rides the child env as SPLASH_API_KEY")
    check(!res.args.contains("splash-standalone-1"), "D9(b): the key never appears on argv")
    check(res.issues.isEmpty, "D9(b): no issues on the seeded defaults (100g + persistent-cache satisfy requires)")
}

// 33. The .launcher (1.3.1) form: `launcher.py serve --model <ID>` + shared flags,
// the key in env, NEVER on argv (open item 5: uniform across both flavors).
do {
    let res = buildArgv(contract131,
                        profileValues: ["persistent_cache": .bool(true), "max_cache_disk": .string("100g"),
                                        "idle_release": .string("240m"), "ane": .bool(true)],
                        model: ProfileModel(source: "hfid", id: "mlx-community/Qwen3.8-27B-4bit"),
                        globals: GlobalCfg(port: 8123, apiKey: "splash-standalone-1"))
    check(res.args == [
        "-u", "install/launcher.py", "serve", "--model", "mlx-community/Qwen3.8-27B-4bit",
        "--host", "127.0.0.1", "--port", "8123",
        "--persistent-cache", "--max-cache-disk", "100g", "--idle-release", "240m",
    ], "launcher: the exact argv (model id + shared flags; the key is NOT on it)")
    check(!res.args.contains("--api-key") && !res.args.contains("splash-standalone-1"),
          "launcher: the api key is never on argv")
    check(res.env == ["SPLASH_API_KEY": "splash-standalone-1"], "launcher: the api key goes into env as SPLASH_API_KEY")
    check(res.issues.isEmpty, "launcher: no issues")
}

// 34. ANE: `true` -> NOTHING on argv (the split is default-on, today's behavior);
// `false` -> --disable-ane; absent -> nothing.
do {
    let model = ProfileModel(source: "lmstudio", id: "incoai/Qwen3.8-27B-Splash", dir: goldenModelDir)
    let globals = GlobalCfg(port: 8123, apiKey: "splash-standalone-1")
    let on = buildArgv(contract130, profileValues: ["ane": .bool(true)], model: model, globals: globals)
    check(!on.args.contains("--disable-ane"), "ane: true -> nothing on argv (default-on split)")
    let off = buildArgv(contract130, profileValues: ["ane": .bool(false)], model: model, globals: globals)
    check(off.args.last == "--disable-ane", "ane: false -> --disable-ane (last, as today)")
    let absent = buildArgv(contract130, profileValues: [:], model: model, globals: globals)
    check(!absent.args.contains("--disable-ane"), "ane: unset -> nothing (the engine default is on)")
    let bOff = buildArgv(contract131, profileValues: ["ane": .bool(false)],
                         model: ProfileModel(source: "hfid", id: "m/r"), globals: globals)
    check(bOff.args.last == "--disable-ane", "ane: false -> --disable-ane (launcher form)")
}

// 35. defValue omission: a value equal to the engine default is OMITTED (the
// engine reads it itself); a non-default value emits.
do {
    let model = ProfileModel(source: "hfid", id: "m/r")
    let globals = GlobalCfg(port: 8123, apiKey: "k")
    let def = buildArgv(contract131, profileValues: ["kv_format": .string("int8"), "max_memory": .string("auto"),
                                                     "decode_share": .string("0.5")], model: model, globals: globals)
    check(!def.args.contains("int8") && !def.args.contains("auto") && !def.args.contains("0.5"),
          "omission: values equal to the engine defaults are omitted (kv-format int8, max-memory auto, decode-share 0.5)")
    let non = buildArgv(contract131, profileValues: ["kv_format": .string("bf16"), "max_memory": .string("28G"),
                                                     "decode_share": .string("0.7")], model: model, globals: globals)
    check(non.args == ["-u", "install/launcher.py", "serve", "--model", "m/r",
                        "--host", "127.0.0.1", "--port", "8123",
                        "--max-memory", "28G", "--kv-format", "bf16", "--decode-share", "0.7"],
          "omission: non-default values emit in registry order")
}

// 36. 1.3.2 flags emit ONLY when set (the design driver for the versioned registry).
do {
    let model = ProfileModel(source: "hfid", id: "m/r")
    let globals = GlobalCfg(port: 8123, apiKey: "k")
    let none = buildArgv(contract132, profileValues: [:], model: model, globals: globals)
    for absent in ["--state-format", "--max-cache-disk-writes", "--thinking-token-budget", "--thinking-end-text"] {
        check(!none.args.contains(absent), "1.3.2: \(absent) is absent when unset")
    }
    check(!none.args.contains("auto") && !none.args.contains("--max-cache-disk"),
          "1.3.2: --max-cache-disk is absent when unset (the engine default auto)")
    let endText = """
Now the answer


"""
    let set = buildArgv(contract132, profileValues: ["state_format": .string("bf16"),
                                                     "thinking_token_budget": .number(4096),
                                                     "thinking_end_text": .string(endText),
                                                     "max_cache_disk_writes": .string("200G")],
                        model: model, globals: globals)
    check(set.args.contains("--state-format") && set.args.contains("bf16"), "1.3.2: --state-format emits when set (bf16)")
    check(set.args.contains("--thinking-token-budget") && set.args.contains("4096"), "1.3.2: --thinking-token-budget emits when set")
    check(set.args.contains("--thinking-end-text"), "1.3.2: --thinking-end-text emits when set (multi-line text is a single argv element)")
    check(set.args.contains("--max-cache-disk-writes") && set.args.contains("200G"), "1.3.2: --max-cache-disk-writes emits when set")
    let atDefault = buildArgv(contract132, profileValues: ["state_format": .string("fp32")], model: model, globals: globals)
    check(!atDefault.args.contains("--state-format"), "1.3.2: a value equal to the engine default (fp32) is still omitted")
    let explicitAuto = buildArgv(contract132, profileValues: ["max_cache_disk": .string("auto")], model: model, globals: globals)
    check(!explicitAuto.args.contains("--max-cache-disk"), "1.3.2: explicit 'auto' == the engine default -> omitted")
}

// 37. requires violations (D4: warn, never block — the offending flag is DROPPED,
// the launch proceeds): mirrors the engine's own cross-checks, translated to
// warning + drop instead of the engine's hard error.
do {
    let model = ProfileModel(source: "lmstudio", id: "incoai/Qwen3.8-27B-Splash", dir: goldenModelDir)
    let globals = GlobalCfg(port: 8123, apiKey: "k")
    // 1.3.0: persistent-cache needs max-cache-disk (engine default 0 = disabled).
    let v1 = buildArgv(contract130, profileValues: ["persistent_cache": .bool(true)], model: model, globals: globals)
    check(!v1.args.contains("--persistent-cache") && !v1.args.contains("--max-cache-disk"),
          "requires 1.3.0: --persistent-cache dropped when --max-cache-disk is unset (engine default 0)")
    check(v1.issues.count == 1 && v1.issues[0].severity == .warning && v1.issues[0].message.contains("--persistent-cache"),
          "requires 1.3.0: an ArgvIssue.warning names the dropped flag")
    check(!v1.args.isEmpty, "requires 1.3.0: the launch still proceeds (warn, never block)")
    let v2 = buildArgv(contract130, profileValues: ["persistent_cache": .bool(true), "max_cache_disk": .string("0")],
                       model: model, globals: globals)
    check(!v2.args.contains("--persistent-cache") && v2.issues.count == 1,
          "requires 1.3.0: explicit '0' is the disabled state -> --persistent-cache dropped + warn")
    let ok = buildArgv(contract130, profileValues: ["persistent_cache": .bool(true), "max_cache_disk": .string("100g")],
                       model: model, globals: globals)
    check(ok.args.contains("--persistent-cache") && ok.issues.isEmpty,
          "requires 1.3.0: a non-zero --max-cache-disk satisfies requires -> no issue")
    // 1.3.2: auto (non-zero) satisfies; explicit 0 does not.
    let w1 = buildArgv(contract132, profileValues: ["max_cache_disk_writes": .string("200G")],
                       model: ProfileModel(source: "hfid", id: "m/r"), globals: globals)
    check(w1.args.contains("--max-cache-disk-writes") && w1.issues.isEmpty,
          "requires 1.3.2: --max-cache-disk-writes is fine on top of the auto cache")
    let w2 = buildArgv(contract132, profileValues: ["max_cache_disk_writes": .string("200G"), "max_cache_disk": .string("0")],
                       model: ProfileModel(source: "hfid", id: "m/r"), globals: globals)
    check(!w2.args.contains("--max-cache-disk-writes") && w2.args.contains("--max-cache-disk") && w2.args.contains("0"),
          "requires 1.3.2: a '0' cache disables --max-cache-disk-writes (dropped + warn), the '0' itself emits")
    check(w2.issues.count == 1 && w2.issues[0].message.contains("--max-cache-disk-writes"),
          "requires 1.3.2: the warning names --max-cache-disk-writes")
    // announce-served-name needs a served-model-name (the other engine cross-check).
    let a1 = buildArgv(contract130, profileValues: ["announce_served_name": .bool(true)], model: model, globals: globals)
    check(!a1.args.contains("--announce-served-name") && a1.issues.count == 1,
          "requires 1.3.0: --announce-served-name dropped without --served-model-name")
    let a2 = buildArgv(contract130, profileValues: ["announce_served_name": .bool(true), "served_model_name": .array([.string("m1")])],
                       model: model, globals: globals)
    check(a2.args.contains("--announce-served-name") && a2.issues.isEmpty,
          "requires 1.3.0: a served-model-name present -> announce kept, no issue")
}

// 38. host/port are structural: ALWAYS emitted, even when equal to the engine
// defaults (today's code emits `--host 127.0.0.1 --port <port>` unconditionally).
do {
    let model = ProfileModel(source: "hfid", id: "m/r")
    let res = buildArgv(contract131, profileValues: [:], model: model, globals: GlobalCfg(port: 8000, apiKey: "k"))
    check(res.args.contains("--host") && res.args.contains("127.0.0.1"), "host: always emitted (the app is local-only)")
    check(res.args.contains("--port") && res.args.contains("8000"),
          "port: emitted even when equal to the engine default (alwaysEmit overrides the omission rule)")
    let wide = buildArgv(contract131, profileValues: ["host": .string("0.0.0.0")], model: model,
                         globals: GlobalCfg(port: 8123, apiKey: "k"))
    check(wide.args.contains("0.0.0.0"), "host: a user-set non-loopback host emits")
}

// 39. The module structural prefix: exactly today's resolveSplashPaths shape
// (the positional dir, --model id, --tokenizer <DIR>/tokenizer, --binary
// ./engine/splash — in that order, before the shared flags).
do {
    let dir = "/opt/models/incoai/Qwen3.8-27B-Splash"
    let res = buildArgv(contract130, profileValues: [:],
                        model: ProfileModel(source: "lmstudio", id: "incoai/Qwen3.8-27B-Splash", dir: dir),
                        globals: GlobalCfg(port: 8123, apiKey: "k"))
    check(res.args.prefix(10) == ["-u", "-m", "server.server", dir,
                                  "--model", "incoai/Qwen3.8-27B-Splash",
                                  "--tokenizer", dir + "/tokenizer", "--binary", "./engine/splash"],
          "module: the structural prefix is byte-identical to today's shape")
}

// 40. A module-flavor launch without an on-disk model dir cannot be built (the
// dir is the positional argument): an error issue, no argv (D4's pre-flight
// gate — the plan layer names the fix).
do {
    let res = buildArgv(contract130, profileValues: [:],
                        model: ProfileModel(source: "hfid", id: "m/r"),
                        globals: GlobalCfg(port: 8123, apiKey: "k"))
    check(res.args.isEmpty, "module: no dir -> no argv")
    check(res.issues.count == 1 && res.issues[0].severity == .error, "module: no dir -> an error issue (launch is refused pre-flight)")
    let resId = buildArgv(contract130, profileValues: [:],
                          model: ProfileModel(source: "lmstudio", id: nil, dir: "/opt/models/x"),
                          globals: GlobalCfg(port: 8123, apiKey: "k"))
    check(resId.args.isEmpty && resId.issues.first?.severity == .error, "module: a dir without an id cannot name --model -> error")
    // The launcher needs only the id: a dir-less hfid is fine.
    let l = buildArgv(contract131, profileValues: [:], model: ProfileModel(source: "hfid", id: "m/r"),
                      globals: GlobalCfg(port: 8123, apiKey: "k"))
    check(!l.args.isEmpty && l.issues.allSatisfy { $0.severity == .warning }, "launcher: an id-only model builds (dir ignored)")
}

// 41. Fallback in the builder: a 1.3.9 kit (no authored contract) runs the latest
// authored mapping (1.3.2) with fallback = true — the launch proceeds (D3); S7
// surfaces the cap.
do {
    let (contract, fallback) = contractFor("1.3.9", registry: launchRegistry)
    check(fallback == true && contract.version == "1.3.2", "fallback: a 1.3.9 kit maps to the 1.3.2 contract")
    let res = buildArgv(contract, profileValues: ["state_format": .string("bf16")],
                        model: ProfileModel(source: "hfid", id: "m/r"),
                        globals: GlobalCfg(port: 8123, apiKey: "k"))
    check(res.args == ["-u", "install/launcher.py", "serve", "--model", "m/r",
                       "--host", "127.0.0.1", "--port", "8123", "--state-format", "bf16"],
          "fallback: the 1.3.2 mapping drives the argv (launch proceeds)")
    check(res.env == ["SPLASH_API_KEY": "k"], "fallback: env built from the globals as usual")
}

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
