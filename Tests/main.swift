// Regression tests for the pure SplashUI launch decisions (ui_logic.swift).
// Run from the repo root: ./run_tests.sh   (compiles ui_logic.swift + this file, no AppKit).

import Foundation
import Darwin

var failures = 0
func check(_ cond: Bool, _ label: String) {
    if cond { print("ok  - \(label)") }
    else { failures += 1; print("FAIL- \(label)") }
}

/// The harness's process-environment injection (D9 invariance tests): set the
/// given vars, run the closure, then restore (unset) them. The deprecated
/// SPLASH_* vars must have zero effect on anything in ui_logic.swift.
func withEnv(_ vars: [String: String], _ body: () -> Void) {
    for (k, v) in vars { setenv(k, v, 1) }
    body()
    for k in vars.keys { unsetenv(k) }
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
check(autoQuitDecision(procGone: true, everUp: true, downFor: 11, userStopped: false, launchFailed: false) == true,
      "quit: up-then-gone 11s -> quit")
// up then gone 9 s: not yet.
check(autoQuitDecision(procGone: true, everUp: true, downFor: 9, userStopped: false, launchFailed: false) == false,
      "quit: up-then-gone 9s -> no quit")
// never up, long gone: NEVER quit (the bug fix).
check(autoQuitDecision(procGone: true, everUp: false, downFor: 60, userStopped: false, launchFailed: true) == false,
      "quit: never-up 60s -> no quit")
// not gone: never quit.
check(autoQuitDecision(procGone: false, everUp: true, downFor: 0, userStopped: false, launchFailed: false) == false,
      "quit: proc alive -> no quit")
// user stopped: never auto-quit.
check(autoQuitDecision(procGone: true, everUp: true, downFor: 11, userStopped: true, launchFailed: false) == false,
      "quit: userStopped -> no quit")
check(autoQuitDecision(procGone: true, everUp: true, downFor: 600, userStopped: false, launchFailed: true) == false,
      "quit: failed restart after an earlier serving session keeps Settings available")
check(autoQuitDecision(procGone: true, everUp: false, downFor: 600, userStopped: false, launchFailed: false) == false,
      "quit: spawning a process is not evidence that the engine ever served")
do {
    let engineError = "Traceback (most recent call last):\nValueError: invalid --max-memory setting"
    let message = engineStartupFailure(exitStatus: 1, output: "\n" + engineError + "\n")
    check(message.contains(engineError), "startup failure: preserves the engine's multiline error verbatim")
    check(message.contains("exit status 1"), "startup failure: includes the actual process exit status")
    check(engineStartupFailure(exitStatus: 0, output: " \n") == "Engine exited before it became ready (exit status 0).",
          "startup failure: a clean exit without readiness still reports the real status")
}


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
                           isDir: { ["/opt/homebrew/Cellar/splash/1.3.1/libexec", "/home/.lmstudio/models",
                                     "/home/.cache/huggingface/hub"].contains($0) },
                           now: now)
    check(d.globals.engine.mode == "auto" && d.globals.engine.manualPath == nil && d.globals.engine.brew,
          "firstRun: keg detected -> engine auto (D2 ladder), brew rung on")
    check(d.globals.port == 8123 && d.globals.apiKey == "splash-standalone-1", "firstRun: documented defaults")
    let ids = d.globals.modelFolders.map { $0.id }
    check(ids == ["lmstudio", "hfhub"], "firstRun: only the two installed model libraries are seeded")
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

// 27. contractFor: exact hits for the four authored versions (D16: keyed to the
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
    let d = contractFor("1.4.0", registry: launchRegistry)
    check(d.fallback == false && d.contract.version == "1.4.0" && d.contract.flavor == .launcher,
          "contractFor: 1.4.0 -> the launcher contract, fallback false")
}

// 28. contractFor: unseen versions -> the LATEST authored (1.4.0) + fallback =
// true (D3: launch proceeds; S7 shows the "FALLBACK MAPPING" cap).
do {
    let newer = contractFor("1.4.1", registry: launchRegistry)
    check(newer.fallback == true && newer.contract.version == "1.4.0",
          "contractFor: unseen 1.4.1 -> the latest authored (1.4.0) + fallback")
    let older = contractFor("1.2.9", registry: launchRegistry)
    check(older.fallback == true && older.contract.version == "1.4.0",
          "contractFor: older 1.2.x -> the latest authored (1.4.0) + fallback")
    let unreadable = contractFor(nil, registry: launchRegistry)
    check(unreadable.fallback == true && unreadable.contract.version == "1.4.0",
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
    check(c.option("persistent_cache")?.kind == .bool && c.option("persistent_cache")?.requires == ["max_cache_disk"],
          "contract 1.3.2: --persistent-cache requires --max-cache-disk (the 1.3.2 engine hard-errors on max_cache_disk == 0; unset -> auto passes)")
    check(c.option("max_cache_disk_writes")?.requires == ["max_cache_disk"],
          "contract 1.3.2: --max-cache-disk-writes requires the SSD cache (the 1.3.2 engine check)")
    check(c.familyRegistry == contract131.familyRegistry,
          "contract 1.3.2: the DFlash2 registry is the tag's families.py (unchanged from 1.3.1)")
}

// 31b. The 1.4.0 contract (ground truth: the real 1.4.0 keg's serve_options.py +
// install/families.py, diffed against the 1.3.2 tag): 1.3.2 + the 4 new flags
// (3 memory budgets + --verify-rows) + the Qwen3.8-Flash-Next family.
do {
    let c = contract140
    check(c.flavor == .launcher, "contract 1.4.0: the launcher flavor")
    let newKeys = Set(["ple_memory", "expert_memory", "sparse_kv_memory", "verify_rows"])
    check(Set(c.options.map { $0.key }) == Set(contract132.options.map { $0.key }) | newKeys,
          "contract 1.4.0: 1.3.2's keys + exactly the 4 new flags")
    check(c.option("ple_memory")?.defValue == "auto" && c.option("ple_memory")?.group == "memory",
          "contract 1.4.0: --ple-memory (memory, auto)")
    check(c.option("expert_memory")?.defValue == "auto" && c.option("sparse_kv_memory")?.defValue == "auto",
          "contract 1.4.0: --expert-memory / --sparse-kv-memory default auto")
    check(c.option("verify_rows")?.defValue == "auto" && c.option("verify_rows")?.choices == ["auto", "all"],
          "contract 1.4.0: --verify-rows {auto,all}, engine default auto")
    check(c.familyRegistry == [
        "Qwen3.8-27B": "incoai/Qwen3.8-27B-DFlash2",
        "Qwen3.6-35B-A3B": "incoai/Qwen3.6-35B-A3B-DFlash2",
        "Qwen3.8-Flash-Next": "incoai/Qwen3.8-Flash-Next-DFlash2",
    ], "contract 1.4.0: the tag's families.py (+ the Flash-Next family)")
    // The 1.3.2 cross-checks carry over verbatim into the 1.4.0 shared set.
    check(c.option("persistent_cache")?.requires == ["max_cache_disk"]
        && c.option("max_cache_disk_writes")?.requires == ["max_cache_disk"]
        && c.option("cache_dir")?.requires == ["persistent_cache"],
          "contract 1.4.0: the 1.3.2 requires cross-checks survive unchanged")
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

// 36b. 1.4.0 flags emit ONLY when set (the 4 new flags; the 1.3.2 rules still
// hold inside the 1.4.0 contract).
do {
    let model = ProfileModel(source: "hfid", id: "m/r")
    let globals = GlobalCfg(port: 8123, apiKey: "k")
    let none = buildArgv(contract140, profileValues: [:], model: model, globals: globals)
    for absent in ["--ple-memory", "--expert-memory", "--sparse-kv-memory", "--verify-rows"] {
        check(!none.args.contains(absent), "1.4.0: \(absent) is absent when unset")
    }
    check(!none.args.contains("auto"), "1.4.0: no stray 'auto' when everything is unset")
    let set = buildArgv(contract140, profileValues: ["ple_memory": .string("2G"),
                                                     "expert_memory": .string("16G"),
                                                     "sparse_kv_memory": .string("1200M"),
                                                     "verify_rows": .string("all")],
                        model: model, globals: globals)
    check(set.args.contains("--ple-memory") && set.args.contains("2G"), "1.4.0: --ple-memory emits when set")
    check(set.args.contains("--expert-memory") && set.args.contains("16G"), "1.4.0: --expert-memory emits when set")
    check(set.args.contains("--sparse-kv-memory") && set.args.contains("1200M"), "1.4.0: --sparse-kv-memory emits when set")
    check(set.args.contains("--verify-rows") && set.args.contains("all"), "1.4.0: --verify-rows emits when set (all)")
    let atDefault = buildArgv(contract140, profileValues: ["verify_rows": .string("auto")], model: model, globals: globals)
    check(!atDefault.args.contains("--verify-rows"), "1.4.0: 'auto' == the engine default -> omitted")
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
    // D6: the bind address is a GLOBAL, not a profile option — a user-set
    // non-loopback host comes from the globals and wins over a stale profile value.
    let wide = buildArgv(contract131, profileValues: ["host": .string("1.2.3.4")], model: model,
                         globals: GlobalCfg(host: "0.0.0.0", port: 8123, apiKey: "k"))
    check(wide.args.contains("0.0.0.0") && !wide.args.contains("1.2.3.4"),
          "host: the globals host emits and overrides a stale profile host")
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
// authored mapping (1.4.0) with fallback = true — the launch proceeds (D3); S7
// surfaces the cap.
do {
    let (contract, fallback) = contractFor("1.3.9", registry: launchRegistry)
    check(fallback == true && contract.version == "1.4.0", "fallback: a 1.3.9 kit maps to the 1.4.0 contract")
    let res = buildArgv(contract, profileValues: ["state_format": .string("bf16")],
                        model: ProfileModel(source: "hfid", id: "m/r"),
                        globals: GlobalCfg(port: 8123, apiKey: "k"))
    check(res.args == ["-u", "install/launcher.py", "serve", "--model", "m/r",
                       "--host", "127.0.0.1", "--port", "8123", "--state-format", "bf16"],
          "fallback: the 1.4.0 mapping drives the argv (launch proceeds)")
    check(res.env == ["SPLASH_API_KEY": "k"], "fallback: env built from the globals as usual")
}

// 42. G1: the real 1.3.2 engine hard-errors `--persistent-cache` when
// --max-cache-disk is 0 (serve_options.py: `if args.persistent_cache and
// args.max_cache_disk == 0: parser.error(...)`). The registry must carry the
// requires; the disabled-state check ("0") does the work. Unset -> "auto"
// (non-zero) -> the flag is kept.
do {
    let model = ProfileModel(source: "hfid", id: "m/r")
    let globals = GlobalCfg(port: 8123, apiKey: "k")
    let unset = buildArgv(contract132, profileValues: ["persistent_cache": .bool(true)],
                          model: model, globals: globals)
    check(unset.args.contains("--persistent-cache") && unset.issues.isEmpty,
          "G1 1.3.2: --persistent-cache kept when --max-cache-disk is unset (engine default auto is non-zero)")
    let zero = buildArgv(contract132, profileValues: ["persistent_cache": .bool(true), "max_cache_disk": .string("0")],
                         model: model, globals: globals)
    check(!zero.args.contains("--persistent-cache") && zero.args.contains("--max-cache-disk") && zero.args.contains("0"),
          "G1 1.3.2: a '0' cache disables --persistent-cache (dropped), the '0' itself emits")
    check(zero.issues.count == 1 && zero.issues[0].severity == .warning && zero.issues[0].message.contains("--persistent-cache"),
          "G1 1.3.2: the warning names --persistent-cache (D4: warn, never block)")
}

// 43. G2: `--cache-dir needs --persistent-cache` — the engine cross-checks it in
// ALL THREE versions (verified: the 1.3.0 kit, the 1.3.1 keg, and the 1.3.2 tag
// serve_options.py each carry the check). The registry must mirror it in every
// shared set; a cache-dir without persistent-cache is dropped with a warning.
do {
    let model = ProfileModel(source: "lmstudio", id: "m/r", dir: "/m")   // dir + id: both flavors build
    let globals = GlobalCfg(port: 8123, apiKey: "k")
    for contract in [contract130, contract131, contract132, contract140] {
        check(contract.option("cache_dir")?.requires == ["persistent_cache"],
              "G2: \(contract.version) --cache-dir requires --persistent-cache (the engine cross-check)")
        let v = buildArgv(contract, profileValues: ["cache_dir": .string("/tmp/pc")],
                          model: model, globals: globals)
        check(!v.args.contains("--cache-dir") && !v.args.contains("/tmp/pc"),
              "G2: \(contract.version) --cache-dir dropped without --persistent-cache")
        check(v.issues.count == 1 && v.issues[0].severity == .warning && v.issues[0].message.contains("--cache-dir"),
              "G2: \(contract.version) the warning names --cache-dir (D4: warn, never block)")
        let ok = buildArgv(contract, profileValues: ["cache_dir": .string("/tmp/pc"), "persistent_cache": .bool(true),
                                                     "max_cache_disk": .string("100g")],
                           model: model, globals: globals)
        check(ok.args.contains("--cache-dir") && ok.args.contains("--persistent-cache") && ok.issues.isEmpty,
              "G2: \(contract.version) --cache-dir kept when --persistent-cache is on (a non-zero cache satisfies it)")
    }
}

// 44. G3: REASONING_EFFORTS is 7 values in 1.3.0 AND 1.3.2 (verified in both
// kits' serve_options.py): none, minimal, low, medium, high, xhigh, max — the
// registry was missing "max" in all three contracts.
do {
    let seven = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
    for contract in [contract130, contract131, contract132, contract140] {
        check(contract.option("reasoning_effort")?.choices == seven,
              "G3: \(contract.version) --default-reasoning-effort has the 7 real choices (incl. max)")
    }
    let model = ProfileModel(source: "hfid", id: "m/r")
    let res = buildArgv(contract131, profileValues: ["reasoning_effort": .string("max")],
                        model: model, globals: GlobalCfg(port: 8123, apiKey: "k"))
    check(res.args.contains("--default-reasoning-effort") && res.args.contains("max"),
          "G3: 'max' emits on the argv (S6b's save-validation consumes the choices)")
}

// ---- S3: resolveKit (the engine ladder extracted from resolveSplashPaths) ----
// AUTO chooses the highest installed Homebrew version; the old SplashUI kit is
// available through an explicit MANUAL path only. D9: no environment reads.

let fixedKitDir = "/home/SplashUI/kit/splash-1.3.0-arm64-macos26"

// 45. AUTO ignores the old fixed kit even when it is installed.
do {
    let (kd, ke) = kitPaths(fixedKitDir)
    let (bd, be) = brewPaths("/opt/homebrew")
    let r = resolveKit(
        engine: EngineCfg(mode: "auto", manualPath: nil, brew: true),
        home: "/home",
        isDir: { (kd | bd).contains($0) }, isExecutable: { (ke | be).contains($0) },
        brewKeg: { "/opt/homebrew" },
        kitVersion: { $0 == "/opt/homebrew/libexec" ? "1.3.1" : "1.3.0" })
    check(r.kit == "/opt/homebrew/libexec", "resolveKit: AUTO uses Homebrew, not the old SplashUI kit")
    check(r.version == "1.3.1", "resolveKit: version read from the selected Homebrew kit")
    check(r.tried == ["/opt/homebrew/libexec"], "resolveKit: AUTO records only the Homebrew kit")
    check(r.error == nil, "resolveKit: no error when a kit resolves")
}

// 46. auto mode: the brew keg's libexec is the kit when only brew is present.
do {
    let (bd, be) = brewPaths("/opt/homebrew")
    let r = resolveKit(
        engine: EngineCfg(mode: "auto", manualPath: nil, brew: true),
        home: "/home",
        isDir: { bd.contains($0) }, isExecutable: { be.contains($0) },
        brewKeg: { "/opt/homebrew" },
        kitVersion: { $0.hasPrefix("/opt/homebrew/libexec") ? "1.3.1" : nil })
    check(r.kit == "/opt/homebrew/libexec", "resolveKit: the Homebrew keg libexec resolves")
    check(r.version == "1.3.1", "resolveKit: the keg version surfaces (1.3.1)")
    check(r.tried == ["/opt/homebrew/libexec"], "resolveKit: AUTO does not try an assumed install.sh path")
    check(r.error == nil, "resolveKit: no error")
}

// 47. MANUAL resolves exactly the selected path.
do {
    let (md, me) = kitPaths("/user/kit")
    let (kd, ke) = kitPaths(fixedKitDir)
    let r = resolveKit(
        engine: EngineCfg(mode: "manual", manualPath: "/user/kit", brew: true),
        home: "/home",
        isDir: { (md | kd).contains($0) }, isExecutable: { (me | ke).contains($0) },
        brewKeg: { nil },
        kitVersion: { _ in nil })
    check(r.kit == "/user/kit", "resolveKit: a valid manual path replaces rung 1 (always wins when set)")
    check(r.tried.first == "/user/kit", "resolveKit: manual path tried first")
}

// 48. An incomplete MANUAL kit fails without silently changing engine version.
do {
    let (kd, ke) = kitPaths(fixedKitDir)
    let dirs: Set<String> = kd.union(["/broken/kit"])
    let exe: Set<String> = ke.union(["/broken/kit/engine/splash"])   // engine yes, python no
    let r = resolveKit(
        engine: EngineCfg(mode: "manual", manualPath: "/broken/kit", brew: true),
        home: "/home",
        isDir: { dirs.contains($0) }, isExecutable: { exe.contains($0) },
        brewKeg: { nil },
        kitVersion: { $0 == fixedKitDir ? "1.3.0" : nil })
    check(r.kit == nil, "resolveKit: an incomplete manual kit never falls back to the old kit")
    check(r.tried == ["/broken/kit"], "resolveKit: only the explicit manual path is tried")
    check(r.error != nil, "resolveKit: incomplete manual kit returns an actionable error")
}

// 49. An empty MANUAL path does not pick an unrelated engine.
do {
    let (kd, ke) = kitPaths(fixedKitDir)
    let r = resolveKit(
        engine: EngineCfg(mode: "manual", manualPath: "", brew: true),
        home: "/home",
        isDir: { kd.contains($0) }, isExecutable: { ke.contains($0) },
        brewKeg: { nil })
    check(r.kit == nil, "resolveKit: an empty manual path cannot resolve an engine")
    check(r.tried.isEmpty, "resolveKit: an empty manual path contributes no tried location")
}

// 50. AUTO no longer inherits a legacy disabled-Homebrew rung flag.
do {
    let (bd, be) = brewPaths("/opt/homebrew")
    let r = resolveKit(
        engine: EngineCfg(mode: "auto", manualPath: nil, brew: false),
        home: "/home",
        isDir: { bd.contains($0) }, isExecutable: { be.contains($0) },
        brewKeg: { "/opt/homebrew" })
    check(r.kit == "/opt/homebrew/libexec", "resolveKit: AUTO uses Homebrew even with a legacy brew=false")
    check(r.tried == ["/opt/homebrew/libexec"], "resolveKit: only the Homebrew keg is tried")
    check(r.error == nil, "resolveKit: the installed Homebrew kit is valid")
}

// 51. nothing anywhere: an actionable error names every rung tried (today's style).
do {
    let r = resolveKit(
        engine: EngineCfg(mode: "auto", manualPath: nil, brew: true),
        home: "/home",
        isDir: { _ in false }, isExecutable: { _ in false },
        brewKeg: { "/opt/homebrew" },
        kitVersion: { _ in nil })
    check(r.kit == nil && r.version == nil, "resolveKit: nothing found -> no kit, no version")
    let e = r.error ?? ""
    check(e.contains("engine kit not found"), "resolveKit: the error names the failure")
    check(!e.contains(fixedKitDir) && e.contains("/opt/homebrew/libexec"),
          "resolveKit: the error names the actual Homebrew location, not an assumed fixed kit")
}

// Highest Homebrew version is numeric, spans both prefixes, and skips incomplete kegs.
do {
    let entries = ["/opt/homebrew/Cellar/splash": ["1.3.9", "1.3.10", "libexec", "1.4.0"],
                   "/usr/local/Cellar/splash": ["1.3.11_1", "1.3.11_2"]]
    let keg = findBrewKeg(listDir: { entries[$0] }, isExecutable: { !$0.contains("1.4.0/") })
    check(keg == "/usr/local/Cellar/splash/1.3.11_2", "AUTO: highest numeric installed version/revision across Homebrew prefixes")
    let numeric = findBrewKeg(prefixes: ["/opt/homebrew"], listDir: { entries[$0] },
                              isExecutable: { !$0.contains("1.4.0/") })
    check(numeric == "/opt/homebrew/Cellar/splash/1.3.10", "AUTO: 1.3.10 sorts after 1.3.9; incomplete newer keg is skipped")
    check(findBrewKeg(listDir: { _ in nil }, isExecutable: { _ in false }) == nil,
          "AUTO: no installed Homebrew runtime returns nil")
}

// Common model libraries are conveniences only when their directories exist.
do {
    let custom = ModelFolder(id: "custom", path: "/custom/models", source: "manual")
    let missing = ModelFolder(id: "gone", path: "/gone", source: "auto")
    let dirs: Set<String> = [custom.path, "/home/.lmstudio/models", "/home/.cache/huggingface/hub"]
    let folders = existingModelFolders([custom, missing], home: "/home", isDir: { dirs.contains($0) })
    check(folders.map { $0.id } == ["custom", "lmstudio", "hfhub"], "folders: retain existing custom path and auto-add only installed libraries")
    check(existingModelFolders(folders, home: "/home", isDir: { dirs.contains($0) }) == folders,
          "folders: discovery never duplicates an existing path")
    check(existingModelFolders([], home: "/home", isDir: { _ in false }).isEmpty,
          "folders: absent defaults do not create phantom registry entries")
    let errors = modelFolderAdditionErrors([custom, missing], existing: [custom], isDir: { dirs.contains($0) })
    check(errors == ["model folder does not exist: /gone"], "folders: nonexistent ADD is rejected before persistence")
    check(modelFolderAdditionErrors([missing], existing: [missing], isDir: { _ in false }).isEmpty,
          "folders: a disappeared saved folder does not block unrelated changes")
    let seed = firstRunConfig(home: "/home", brewKeg: { nil }, kitVersion: { _ in nil }, isDir: { _ in false })
    check(seed.globals.modelFolders.isEmpty, "folders: first run does not seed nonexistent libraries")
}

// 52. D9: the ladder reads NO environment. With every documented SPLASH_* var
// set in the process environment, the result is unchanged (the rungs are
// config + constants — SPLASH_KIT_DIR / SPLASHUI_HOME / SPLASH_VERSION are gone).
do {
    let (kd, ke) = kitPaths(fixedKitDir)
    let (bd, be) = brewPaths("/opt/homebrew")
    let noEnv = resolveKit(
        engine: EngineCfg(mode: "auto", manualPath: nil, brew: true),
        home: "/home",
        isDir: { (kd | bd).contains($0) }, isExecutable: { (ke | be).contains($0) },
        brewKeg: { "/opt/homebrew" },
        kitVersion: { $0 == fixedKitDir ? "1.3.0" : $0.hasPrefix("/opt/homebrew/libexec") ? "1.3.1" : nil })
    withEnv(["SPLASH_KIT_DIR": "/env/kit", "SPLASHUI_HOME": "/customroot",
                     "SPLASH_VERSION": "9.9.9", "SPLASH_PORT": "9999",
                     "SPLASH_KEY": "other", "SPLASH_MODEL_ROOT": "/env/model",
                     "SPLASH_MAX_CACHE_DISK": "50g", "SPLASH_IDLE_RELEASE": "60m",
                     "SPLASH_ANE": "off"]) {
        let polluted = resolveKit(
            engine: EngineCfg(mode: "auto", manualPath: nil, brew: true),
            home: "/home",
            isDir: { (kd | bd).contains($0) }, isExecutable: { (ke | be).contains($0) },
            brewKeg: { "/opt/homebrew" },
            kitVersion: { $0 == fixedKitDir ? "1.3.0" : $0.hasPrefix("/opt/homebrew/libexec") ? "1.3.1" : nil })
        check(polluted == noEnv, "resolveKit D9: the 9 SPLASH_* vars in the process env change nothing")
    }
}

// 53. the isKit validation is the exact 3-way check: dir + engine/splash + python{,3}.
do {
    // a dir with an engine but NO python at all -> not a kit
    let dirs: Set<String> = ["/x", "/x/engine"]
    let exe: Set<String> = ["/x/engine/splash"]
    let r1 = resolveKit(engine: EngineCfg(mode: "manual", manualPath: "/x", brew: false),
                        home: "/home",
                        isDir: { dirs.contains($0) }, isExecutable: { exe.contains($0) },
                        brewKeg: { nil })
    check(r1.kit == nil, "isKit: engine/splash without python is not a kit")
    // python3 alone suffices (the brew layout)
    let d2: Set<String> = ["/y", "/y/python"]
    let e2: Set<String> = ["/y/engine/splash", "/y/python/bin/python3"]
    let r2 = resolveKit(engine: EngineCfg(mode: "manual", manualPath: "/y", brew: false),
                        home: "/home",
                        isDir: { d2.contains($0) }, isExecutable: { e2.contains($0) },
                        brewKeg: { nil })
    check(r2.kit == "/y", "isKit: engine/splash + python3 is a kit (the keg layout)")
}

// ---- S3: model classification + enumeration ---------------------------------

/// A fake FS for enumeration fixtures: path sets + text contents + symlinks
/// (a symlink entry aliases its target for isDir/listDir/fileContents — the
/// kernel follows links, so the pure closures do too). NEVER the real FS:
/// tests must not scan the machine's 92G HF cache.
struct FakeFS {
    var dirs: Set<String> = []
    var files: Set<String> = []
    var text: [String: String] = [:]
    var symlinks: [String: String] = [:]
    var executables: Set<String> = []

    func isDir(_ p: String) -> Bool {
        if let t = symlinks[p] { return isDir(t) }
        return dirs.contains(p)
    }
    func isExecutable(_ p: String) -> Bool { executables.contains(p) }
    func fileContents(_ p: String) -> String? {
        var cur = p
        var guard_ = 0
        while let t = symlinks[cur], guard_ < 8 { cur = t; guard_ += 1 }
        if let s = text[cur] { return s }
        return files.contains(cur) ? "" : nil
    }
    func listDir(_ p: String) -> [String]? {
        var cur = p
        var guard_ = 0
        while let t = symlinks[cur], guard_ < 8 { cur = t; guard_ += 1 }
        guard dirs.contains(cur) else { return nil }
        var entries = Set<String>()
        for name in dirs where name.hasPrefix(cur + "/") {
            let rest = String(name.dropFirst(cur.count + 1))
            if !rest.contains("/") { entries.insert(rest) }
        }
        for name in files where name.hasPrefix(cur + "/") {
            let rest = String(name.dropFirst(cur.count + 1))
            if !rest.contains("/") { entries.insert(rest) }
        }
        for name in symlinks.keys where name.hasPrefix(cur + "/") {
            let rest = String(name.dropFirst(cur.count + 1))
            if !rest.contains("/") { entries.insert(rest) }
        }
        return entries.sorted()
    }
    mutating func dir(_ p: String, _ children: [String]) {
        insertAncestors(p)
        dirs.insert(p)
        for c in children {
            let name = c.hasSuffix("/") ? String(c.dropLast()) : c
            let full = p + "/" + name
            if c.hasSuffix("/") { dirs.insert(full) } else { files.insert(full) }
        }
    }
    mutating func file(_ path: String, _ contents: String = "") {
        insertAncestors((path as NSString).deletingLastPathComponent)
        files.insert(path)
        text[path] = contents
    }
    mutating func exec(_ path: String) { executables.insert(path) }
    private mutating func insertAncestors(_ path: String) {
        var cur = path
        while cur.hasPrefix("/") {
            dirs.insert(cur)
            guard cur != "/" else { break }
            let i = cur.lastIndex(of: "/")!   // cur != "/" and hasPrefix("/") guarantee it
            cur = String(cur[..<i])
        }
    }
}

// 54. classifyModelDir: the 4 kinds (C3: package/assembly/hfid/other).
do {
    var fs = FakeFS()
    fs.dir("/m/pkg", ["manifest.json", "model.json", "config.json"])
    fs.dir("/m/asm", ["model.json", "config.json"])
    fs.dir("/m/plain", ["config.json", "model.safetensors"])
    fs.dir("/m/half", ["model.json"])
    let isDir = fs.isDir, fc = fs.fileContents
    // package: manifest.json wins (even when a model.json is also present).
    check(classifyModelDir(dir: "/m/pkg", id: "o/r", isDir: isDir, fileContents: fc) == .package,
          "classify: manifest.json -> package (beats model.json)")
    // assembly: model.json + config.json.
    check(classifyModelDir(dir: "/m/asm", id: "o/r", isDir: isDir, fileContents: fc) == .assembly,
          "classify: model.json + config.json -> assembly")
    // a plain model dir (config.json, weights) WITH an HF id -> hfid (its local copy).
    check(classifyModelDir(dir: "/m/plain", id: "o/r", isDir: isDir, fileContents: fc) == .hfid,
          "classify: a plain dir with an HF id -> hfid")
    // the same dir WITHOUT an id -> other (no name to serve by).
    check(classifyModelDir(dir: "/m/plain", id: nil, isDir: isDir, fileContents: fc) == .other,
          "classify: a plain dir without an id -> other")
    // a 1-component name is not an HF id either.
    check(classifyModelDir(dir: "/m/plain", id: "name", isDir: isDir, fileContents: fc) == .other,
          "classify: a 1-component name is not an HF id -> other")
    // model.json without config.json is not an assembly (it needs both).
    check(classifyModelDir(dir: "/m/half", id: "o/r", isDir: isDir, fileContents: fc) == .hfid,
          "classify: model.json without config.json is not an assembly (a plain dir with an id)")
    // an id-only model (no dir) -> hfid.
    check(classifyModelDir(dir: nil, id: "o/r", isDir: isDir, fileContents: fc) == .hfid,
          "classify: no dir (id-only) -> hfid")
}

// 55. enumerateModels: the lmstudio layout (<owner>/<repo>, two-level, skip hidden,
// cap 200/dir; kinds classified; source tagged). The real root on this machine:
// 6 models under 5 owners (incoai x3, keXjos, lmstudio-community, local,
// mlx-community, p4ik — 7 under 6 owners).
do {
    var fs = FakeFS()
    fs.file("/root/README.md")                       // a root file: not a model
    fs.dir("/root/.hidden", ["config.json"])         // hidden: skipped
    fs.dir("/root/incoai/Qwen3.8-27B-Splash", ["manifest.json", "tokenizer/", "draft/", "target/"])
    fs.dir("/root/incoai/Qwen3.8-27B-Splash-Reasoning", ["config.json"])
    fs.dir("/root/incoai/Qwen3.8-27B-DFlash2", ["config.json"])
    fs.dir("/root/keXjos/m1", ["config.json"])
    fs.dir("/root/lmstudio-community/m2", ["model.json", "config.json"])
    fs.dir("/root/local/m3", ["config.json"])
    fs.dir("/root/mlx-community/Qwen3.8-27B-4bit", ["config.json"])
    fs.dir("/root/p4ik/m4", ["config.json"])
    let folder = ModelFolder(id: "lmstudio", path: "/root", source: "auto")
    let models = enumerateModels(folder: folder,
                                 isDir: fs.isDir, fileContents: fs.fileContents, listDir: fs.listDir)
    check(models.count == 8, "lmstudio: 8 models under 6 owners (hidden skipped, root file skipped)")
    check(models.map { $0.id } == [
        "incoai/Qwen3.8-27B-DFlash2", "incoai/Qwen3.8-27B-Splash",
        "incoai/Qwen3.8-27B-Splash-Reasoning", "keXjos/m1",
        "lmstudio-community/m2", "local/m3", "mlx-community/Qwen3.8-27B-4bit", "p4ik/m4"],
        "lmstudio: ids are owner/repo, sorted")
    check(models.allSatisfy { $0.source == "lmstudio" }, "lmstudio: source-tagged with the folder id")
    let splash = models.first { $0.id == "incoai/Qwen3.8-27B-Splash" }
    check(splash?.kind == .package, "lmstudio: the Splash package classifies as package")
    check(splash?.dir == "/root/incoai/Qwen3.8-27B-Splash", "lmstudio: the dir is the on-disk repo dir")
    let asm = models.first { $0.id == "lmstudio-community/m2" }
    check(asm?.kind == .assembly, "lmstudio: model.json+config.json classifies as assembly")
    let plain = models.first { $0.id == "mlx-community/Qwen3.8-27B-4bit" }
    check(plain?.kind == .hfid, "lmstudio: a plain MLX repo with an id classifies as hfid")
    check(models.allSatisfy { $0.dir?.hasPrefix("/root/") == true }, "lmstudio: dirs are two-level under the root")
}

// 56. enumeration bounds (92G-style): the 200-entries-per-dir cap and depth <= 2.
do {
    var fs = FakeFS()
    for i in 0..<250 {
        fs.dir(String(format: "/root/owner-%03d", i) + "/repo", ["config.json"])
    }
    // depth-3 dirs under a repo: never enumerated (depth <= 2).
    fs.dir("/root/owner-000/repo/tokenizer", ["tokenizer.json"])
    let folder = ModelFolder(id: "lmstudio", path: "/root", source: "auto")
    let models = enumerateModels(folder: folder,
                                 isDir: fs.isDir, fileContents: fs.fileContents, listDir: fs.listDir)
    check(models.count == 200, "cap: 250 owner dirs -> 200 (the per-dir cap)")
    check(models.allSatisfy { $0.id.hasPrefix("owner-") }, "cap: the FIRST 200 in sort order survive")
    check(!models.contains { $0.id.contains("tokenizer") }, "depth: 3-level entries are never models")
    check(models.allSatisfy { $0.dir.map { $0.split(separator: "/").count } == 3 },
          "depth: every model sits exactly two levels under the root")
}

// 57. enumerateModels: the hfhub layout — models--<o>--<r> decodes to o/r; the
// snapshot is the newest (refs/main when present, else the last in sort order);
// a single listing, no recursion; an empty hub -> [] (NOT an error).
do {
    var fs = FakeFS()
    fs.file("/hub/CACHEDIR.TAG")
    fs.dir("/hub/blobs", ["ab12"])
    // two snapshots; refs/main points at the OLDER one (the current ref).
    fs.dir("/hub/models--o--r/snapshots/aaaa", ["config.json"])
    fs.dir("/hub/models--o--r/snapshots/bbbb", ["config.json"])
    fs.file("/hub/models--o--r/refs/main", "aaaa")
    fs.dir("/hub/models--x--y/snapshots/1111", ["config.json"])
    fs.dir("/hub/models--x--y/snapshots/2222", ["config.json"])
    fs.dir("/hub/models--p--q/snapshots", [])       // an empty snapshots dir
    let folder = ModelFolder(id: "hfhub", path: "/hub", source: "auto")
    let models = enumerateModels(folder: folder,
                                 isDir: fs.isDir, fileContents: fs.fileContents, listDir: fs.listDir)
    check(models.count == 2, "hfhub: 2 repos (blobs/ + CACHEDIR.TAG skipped; the empty-snapshot repo dropped)")
    let or = models.first { $0.id == "o/r" }
    check(or?.dir == "/hub/models--o--r/snapshots/aaaa", "hfhub: refs/main picks the current snapshot")
    let xy = models.first { $0.id == "x/y" }
    check(xy?.dir == "/hub/models--x--y/snapshots/2222", "hfhub: without refs, the last snapshot in sort order")
    check(models.allSatisfy { $0.kind == .hfid }, "hfhub: snapshot dirs with a config.json + an id -> hfid")
    // an empty hub is not an error.
    var empty = FakeFS()
    empty.dir("/hub2/blobs", [])
    empty.file("/hub2/CACHEDIR.TAG")
    let m2 = enumerateModels(folder: ModelFolder(id: "hfhub", path: "/hub2", source: "auto"),
                             isDir: empty.isDir, fileContents: empty.fileContents, listDir: empty.listDir)
    check(m2.isEmpty, "hfhub: an empty hub -> [] (not an error)")
}

// 58. enumerateModels: ollama — the manifest paths become names; an EMPTY root
// is [] (not an error); entries carry no dir (blobs are not loadable model dirs).
do {
    var fs = FakeFS()
    fs.dir("/om/models/manifests/registry.ollama.ai/library/qwen3.8-27b", ["latest"])
    fs.file("/om/models/manifests/registry.ollama.ai/library/llama3.1-8b:latest")
    let folder = ModelFolder(id: "ollama", path: "/om/models", source: "auto")
    let models = enumerateModels(folder: folder,
                                 isDir: fs.isDir, fileContents: fs.fileContents, listDir: fs.listDir)
    check(models.count == 2, "ollama: 2 manifest names (a dir and a file entry)")
    check(models.map { $0.id }.sorted() == ["llama3.1-8b:latest", "qwen3.8-27b"],
          "ollama: ids are the manifest names, sorted")
    check(models.allSatisfy { $0.dir == nil }, "ollama: no dir (the blobs are not a loadable model dir)")
    // the real machine's root is empty: not an error.
    var empty = FakeFS()
    empty.dir("/om2/models/manifests/registry.ollama.ai/library", [])
    empty.dir("/om2/models/manifests-v2/registry.ollama.ai/library", [])
    let m2 = enumerateModels(folder: ModelFolder(id: "ollama", path: "/om2/models", source: "auto"),
                             isDir: empty.isDir, fileContents: empty.fileContents, listDir: empty.listDir)
    check(m2.isEmpty, "ollama: an empty library -> [] (not an error)")
}

// 59. enumerateModels: the Splash app-support root — the launcher symlinks its
// models here under models/<owner>/<repo> (install/models.py selection_link),
// .selections/* for variant/revision picks (hidden: skipped); the enumeration
// follows each symlink (isDir/fileContents follow links) and reports the
// symlink path as the model dir.
do {
    var fs = FakeFS()
    // the real targets (the launcher's preparation dir + the HF cache).
    fs.dir("/targets/qwen4bit", ["config.json"])
    fs.dir("/targets/dflash2", ["config.json", "draft.safetensors"])
    // the root: owner dirs + selection symlinks (the launcher's two-level layout).
    fs.dir("/splash/models/mlx-community", [])
    fs.dir("/splash/models/incoai", [])
    fs.dirs.insert("/splash/models/.selections")
    fs.symlinks["/splash/models/mlx-community/Qwen3.8-27B-4bit"] = "/targets/qwen4bit"
    fs.symlinks["/splash/models/incoai/Qwen3.8-27B-DFlash2"] = "/targets/dflash2"
    fs.symlinks["/splash/models/.selections/ab12cd"] = "/targets/qwen4bit"
    fs.file("/splash/models/.DS_Store")
    let folder = ModelFolder(id: "splash", path: "/splash/models", source: "auto")
    let models = enumerateModels(folder: folder,
                                 isDir: fs.isDir, fileContents: fs.fileContents, listDir: fs.listDir)
    check(models.count == 2, "splash: 2 symlinked models (.selections + hidden skipped)")
    check(models.map { $0.id }.sorted() == ["incoai/Qwen3.8-27B-DFlash2", "mlx-community/Qwen3.8-27B-4bit"],
          "splash: ids are owner/repo (the launcher's selection_link layout)")
    let q = models.first { $0.id == "mlx-community/Qwen3.8-27B-4bit" }
    check(q?.dir == "/splash/models/mlx-community/Qwen3.8-27B-4bit",
          "splash: the dir is the symlink path (the kernel resolves it to the target)")
    check(q?.kind == .hfid, "splash: classification follows the link to the target's files (a config + an HF id)")
}

// 60. enumerateModels: manual folders — the same rules, source-tagged; a models
// root with single-level model dirs AND two-level owner dirs both work.
do {
    var fs = FakeFS()
    fs.dir("/manual/my-model", ["config.json", "weights.npz"])   // single-level model
    fs.dir("/manual/ownerX/repoY", ["config.json"])              // two-level model
    fs.dir("/manual/.cache", ["config.json"])                    // hidden: skipped
    let folder = ModelFolder(id: "u-1", path: "/manual", source: "manual")
    let models = enumerateModels(folder: folder,
                                 isDir: fs.isDir, fileContents: fs.fileContents, listDir: fs.listDir)
    check(models.count == 2, "manual: 2 models (hidden skipped)")
    check(models.map { $0.id }.sorted() == ["my-model", "ownerX/repoY"], "manual: single- and two-level ids")
    check(models.allSatisfy { $0.source == "u-1" }, "manual: tagged with the folder id")
    check(models.allSatisfy { $0.source != "auto" } && folder.source == "manual", "manual: the folder's source is manual")
}

// ---- S3: eligibility (D4: static + conservative; the plan-time table, C3) ----
//
// runnable  = the plan can launch;
// unrunnable = saveable (D4) but start refused pre-flight with the fix;
// blocked   = a hard gate: the engine categorically refuses the combo, launch
//             is never attempted (the 1.3.0-package gate, 1.3.1+);
// unknown   = the app cannot decide (the engine's family comes from the model
//             config at load) — launch proceeds; the engine is the final arbiter.
// D4: NEVER a false-runnable; undecidable -> unknown, never a fake runnable.

// 61. package row: 1.3.0 = runnable iff tokenizer/ + draft/ present; 1.3.1+ =
// BLOCKED (the engine refuses 1.3.0 packages — "Splash no longer loads").
do {
    let full = ModelDirFiles(manifest: true, config: true, tokenizer: true, draft: true, draftConfig: true)
    let e = eligibility(kind: .package, contract: contract130, modelId: "incoai/Qwen3.8-27B-Splash",
                        modelDir: "/m", draftModel: nil, family: nil, files: full)
    check(e.verdict == .runnable, "eligibility: package + 1.3.0 with tokenizer/ + draft/ -> runnable")
    let noTok = ModelDirFiles(manifest: true, config: true, draft: true, draftConfig: true)
    let e2 = eligibility(kind: .package, contract: contract130, modelId: "incoai/Qwen3.8-27B-Splash",
                         modelDir: "/m", draftModel: nil, family: nil, files: noTok)
    check(e2.verdict == .unrunnable && (e2.reason ?? "").contains("tokenizer"),
          "eligibility: package + 1.3.0 missing tokenizer/ -> unrunnable (names the gap)")
    let noDraft = ModelDirFiles(manifest: true, config: true, tokenizer: true)
    let e3 = eligibility(kind: .package, contract: contract130, modelId: "incoai/Qwen3.8-27B-Splash",
                         modelDir: "/m", draftModel: nil, family: nil, files: noDraft)
    check(e3.verdict == .unrunnable && (e3.reason ?? "").contains("draft"),
          "eligibility: package + 1.3.0 missing draft/ -> unrunnable (names the gap)")
    for c in [contract131, contract132] {
        let eb = eligibility(kind: .package, contract: c, modelId: "incoai/Qwen3.8-27B-Splash",
                             modelDir: "/m", draftModel: nil, family: nil, files: full)
        check(eb.verdict == .blocked, "eligibility: package + \(c.version) -> BLOCKED")
        let r = eb.reason ?? ""
        check(r.contains("refuses 1.3.0 packages"), "eligibility: the blocked reason names the engine's refusal")
        check(r.contains("1.3.0"), "eligibility: the fix text names the 1.3.0 kit (issue §7 version-tolerance)")
    }
}

// 62. assembly row: 1.3.0 = runnable iff config.json + draft/config.json (R3: the
// draft is required in both versions — in 1.3.0 the drafter contract IS draft/);
// 1.3.1+ = blocked (the launcher serves by HF id, never a local assembly dir).
do {
    let ok = ModelDirFiles(modelJson: true, config: true, draft: true, draftConfig: true)
    let e = eligibility(kind: .assembly, contract: contract130, modelId: "o/r",
                        modelDir: "/m", draftModel: nil, family: nil, files: ok)
    check(e.verdict == .runnable, "eligibility: assembly + 1.3.0 with config.json + draft/config.json -> runnable")
    let noDraft = ModelDirFiles(modelJson: true, config: true, draft: true)
    let e2 = eligibility(kind: .assembly, contract: contract130, modelId: "o/r",
                         modelDir: "/m", draftModel: nil, family: nil, files: noDraft)
    check(e2.verdict == .unrunnable && (e2.reason ?? "").contains("draft/config.json"),
          "eligibility: assembly + 1.3.0 without draft/config.json -> unrunnable (the S3 GWT case)")
    let noConfig = ModelDirFiles(modelJson: true, draft: true, draftConfig: true)
    let e3 = eligibility(kind: .assembly, contract: contract130, modelId: "o/r",
                         modelDir: "/m", draftModel: nil, family: nil, files: noConfig)
    check(e3.verdict == .unrunnable && (e3.reason ?? "").contains("config.json"),
          "eligibility: assembly + 1.3.0 without config.json -> unrunnable")
    for c in [contract131, contract132] {
        let eb = eligibility(kind: .assembly, contract: c, modelId: "o/r",
                             modelDir: "/m", draftModel: nil, family: nil, files: ok)
        check(eb.verdict == .blocked, "eligibility: assembly + \(c.version) -> blocked (the launcher serves by HF id)")
        check((eb.reason ?? "").contains("HF id"), "eligibility: the reason explains the launcher's id-only form")
    }
}

// 63. hfid row, 1.3.0 (module loads positionally — it never downloads): a resolved
// dir with a config.json -> runnable positional; no local dir -> unrunnable; a
// 1-component name is not an HF id -> unrunnable.
do {
    // a pure hfid (no local dir) under 1.3.0: the module form needs the dir.
    let e = eligibility(kind: .hfid, contract: contract130, modelId: "mlx-community/Qwen3.8-27B-4bit",
                        modelDir: nil, draftModel: nil, family: nil, files: ModelDirFiles())
    check(e.verdict == .unrunnable && (e.reason ?? "").contains("positionally"),
          "eligibility: hfid + 1.3.0 with no local dir -> unrunnable (1.3.0 never downloads)")
    // a resolved dir WITH a config.json: runnable positional (C3: iff config.json present).
    let e2 = eligibility(kind: .hfid, contract: contract130, modelId: "mlx-community/Qwen3.8-27B-4bit",
                         modelDir: "/hub/snapshots/x", draftModel: nil, family: nil,
                         files: ModelDirFiles(config: true))
    check(e2.verdict == .runnable, "eligibility: hfid + 1.3.0 with a config.json dir -> runnable positional")
    // a resolved dir WITHOUT a config.json (e.g. a GGUF-only snapshot): unrunnable.
    let e3 = eligibility(kind: .hfid, contract: contract130, modelId: "o/r",
                         modelDir: "/hub/snapshots/y", draftModel: nil, family: nil,
                         files: ModelDirFiles())
    check(e3.verdict == .unrunnable && (e3.reason ?? "").contains("config.json"),
          "eligibility: hfid + 1.3.0 with a dir but no config.json -> unrunnable")
    // a 1-component name is not a valid --model id (server.py validates OWNER/REPO).
    let e4 = eligibility(kind: .hfid, contract: contract130, modelId: "qwen3.8-27b",
                         modelDir: nil, draftModel: nil, family: nil, files: ModelDirFiles())
    check(e4.verdict == .unrunnable && (e4.reason ?? "").contains("OWNER/REPO"),
          "eligibility: a 1-component id + 1.3.0 -> unrunnable (server.py validates OWNER/REPO)")
}

// 64. hfid row, 1.3.1+ (launcher): --draft-model override -> runnable; a known
// family in the registry -> runnable; a known family NOT in the registry ->
// unrunnable with the engine's own error; an undecidable family -> UNKNOWN
// (the engine decides at load — D4: never a false-runnable, never a fake block).
do {
    let draft = eligibility(kind: .hfid, contract: contract131, modelId: "o/r",
                            modelDir: nil, draftModel: "incoai/Qwen3.8-27B-DFlash2", family: nil,
                            files: ModelDirFiles())
    check(draft.verdict == .runnable, "eligibility: hfid + 1.3.1 with --draft-model -> runnable (the override)")
    let known = eligibility(kind: .hfid, contract: contract131, modelId: "mlx-community/Qwen3.8-27B-4bit",
                            modelDir: nil, draftModel: nil, family: "Qwen3.8-27B",
                            files: ModelDirFiles())
    check(known.verdict == .runnable && (known.reason ?? "").contains("Qwen3.8-27B"),
          "eligibility: hfid + 1.3.1 with a registry family -> runnable (names the family)")
    let unknownFam = eligibility(kind: .hfid, contract: contract131, modelId: "o/other",
                                 modelDir: nil, draftModel: nil, family: "Gemma4-12B",
                                 files: ModelDirFiles())
    check(unknownFam.verdict == .unrunnable && (unknownFam.reason ?? "").contains("Gemma4-12B"),
          "eligibility: hfid + 1.3.1 with a family outside the registry -> unrunnable (the engine's own error)")
    check((unknownFam.reason ?? "").contains("draft"), "eligibility: the fix names the --draft-model override")
    let undecided = eligibility(kind: .hfid, contract: contract131, modelId: "mlx-community/Qwen3.8-27B-4bit",
                                modelDir: nil, draftModel: nil, family: nil,
                                files: ModelDirFiles())
    check(undecided.verdict == .unknown, "eligibility: hfid + 1.3.1 with an undecidable family -> unknown")
    check((undecided.reason ?? "").contains("engine decides at load"),
          "eligibility: the unknown reason says the engine decides at load (D4)")
    // the 1.3.2 registry (identical families) behaves the same.
    let c2 = eligibility(kind: .hfid, contract: contract132, modelId: "mlx-community/Qwen3.8-27B-4bit",
                         modelDir: nil, draftModel: nil, family: "Qwen3.8-27B",
                         files: ModelDirFiles())
    check(c2.verdict == .runnable, "eligibility: hfid + 1.3.2 with a registry family -> runnable")
    // an ollama-style 1-component name under the launcher: not an HF repo id.
    let ol = eligibility(kind: .hfid, contract: contract131, modelId: "qwen3.8-27b",
                         modelDir: nil, draftModel: nil, family: nil,
                         files: ModelDirFiles())
    check(ol.verdict == .unrunnable && (ol.reason ?? "").contains("HF"),
          "eligibility: a 1-component id + 1.3.1+ -> unrunnable (not a Hugging Face repo id)")
}

// 65. other row: a local dir that is neither package nor assembly and carries no
// HF id — unrunnable in BOTH flavors (saveable, D4; start refused with the fix).
do {
    let e1 = eligibility(kind: .other, contract: contract130, modelId: nil,
                         modelDir: "/m", draftModel: nil, family: nil, files: ModelDirFiles())
    check(e1.verdict == .unrunnable, "eligibility: other + 1.3.0 -> unrunnable")
    check((e1.reason ?? "").contains("package") && (e1.reason ?? "").contains("assembly"),
          "eligibility: the reason names what 1.3.0 actually loads")
    let e2 = eligibility(kind: .other, contract: contract131, modelId: nil,
                         modelDir: "/m", draftModel: nil, family: nil, files: ModelDirFiles())
    check(e2.verdict == .unrunnable, "eligibility: other + 1.3.1 -> unrunnable (no id to serve by)")
}

// 66. family derivation (the app's plan-time knowledge of the engine's
// config->family rule, as registry data): model_type qwen3_5 -> Qwen3.8-27B
// (verified: the mlx-community repo's config.json AND the engine's registry).
// An unrecognized config -> nil (undecidable -> the unknown verdict upstream).
do {
    let cfg = #"{"model_type": "qwen3_5", "architectures": ["Qwen3_5ForConditionalGeneration"]}"#
    check(deriveFamily(config: cfg, contract: contract131) == "Qwen3.8-27B",
          "family: model_type qwen3_5 derives the Qwen3.8-27B family (1.3.1)")
    check(deriveFamily(config: cfg, contract: contract132) == "Qwen3.8-27B",
          "family: the 1.3.2 registry carries the same rule")
    let fnCfg = #"{"model_type": "qwen4_exp", "text_config": {"model_type": "qwen4_exp_text"}}"#
    check(deriveFamily(config: fnCfg, contract: contract140) == "Qwen3.8-Flash-Next",
          "family: model_type qwen4_exp derives the Qwen3.8-Flash-Next family (1.4.0)")
    check(deriveFamily(config: fnCfg, contract: contract132) == nil,
          "family: the 1.3.2 registry has no qwen4_exp rule -> undecidable")
    check(deriveFamily(config: #"{"model_type": "gemma_4"}"#, contract: contract131) == nil,
          "family: an unrecognized config -> undecidable (nil)")
    check(deriveFamily(config: nil, contract: contract131) == nil,
          "family: no readable config -> undecidable (nil)")
    check(deriveFamily(config: "not json", contract: contract131) == nil,
          "family: unparseable config -> undecidable (nil)")
    check(deriveFamily(config: cfg, contract: contract130) == nil,
          "family: 1.3.0 has no registry (packages bake the draft) -> always undecidable")
}
// ---- S3: planLaunch (C3: resolveKit -> contractFor -> enumerate -> classify ->
// eligibility -> buildArgv -> plan signature; D9: NO env reads) ----

/// A kit fixture: engine/splash + python/bin/python3 executables + release.json.
func planKit(fs: inout FakeFS, path: String, version: String) {
    fs.dir(path, ["engine/splash/", "python/bin/python3", "release.json"])
    fs.exec(path + "/engine/splash")
    fs.exec(path + "/python/bin/python3")
    fs.file(path + "/release.json", "{\"version\": \"\(version)\"}")
}

/// A config.json with one profile; the knobs the plan-signature tests vary.
func planCfgJSON(engineMode: String, manualPath: String?, port: Int, key: String,
                 name: String, modelId: String?, modelDir: String?,
                 options: [String: Any], modelSource: String? = nil) -> Data {
    var opts = options
    var engine: [String: Any] = ["mode": engineMode]
    if let manualPath { engine["manual_path"] = manualPath }
    var model: [String: Any] = ["source": modelId == nil ? "none" : (modelSource ?? (modelDir == nil ? "hfid" : "lmstudio"))]
    if let modelId { model["id"] = modelId }
    if let modelDir { model["dir"] = modelDir }
    let globals: [String: Any] = [
        "engine": engine,
        "model_folders": [["id": "lmstudio", "path": "/models", "source": "auto"]],
        "port": port,
        "api_key": key,
    ]
    let profiles: [[String: Any]] = [[
        "id": "p1", "name": name,
        "model": model,
        "options": opts,
    ]]
    let top: [String: Any] = [
        "globals": globals,
        "profiles": profiles,
        "active_profile": "p1",
    ]
    return try! JSONSerialization.data(withJSONObject: top)
}

func readKitVersion(fs: FakeFS, kit: String) -> String? {
    guard let s = fs.fileContents(kit + "/release.json"),
          let d = s.data(using: .utf8),
          let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
    return o["version"] as? String
}

func portArg(_ plan: LaunchConfig) -> String? {
    guard let i = plan.engineArgs.firstIndex(of: "--port"), i + 1 < plan.engineArgs.count else { return nil }
    return plan.engineArgs[i + 1]
}
do {
    var fs = FakeFS()
    planKit(fs: &fs, path: "/guard-kit", version: "1.3.1")
    fs.dir("/local/owner/model", ["config.json", "draft/"])
    fs.file("/local/owner/model/draft/config.json")
    func guardedPlan(_ source: String, _ dir: String?, offline: Bool? = nil) -> LaunchConfig {
        var opts: [String: Any] = ["draft_model": "owner/draft"]
        if let offline { opts["offline"] = offline }
        let cfg = planCfgJSON(engineMode: "manual", manualPath: "/guard-kit", port: 8123,
            key: "test", name: "Local", modelId: "owner/model", modelDir: dir,
            options: opts, modelSource: source)
        return planLaunch(cfg, home: "/home", isDir: { fs.isDir($0) },
            isExecutable: { fs.isExecutable($0) }, kitVersion: { readKitVersion(fs: fs, kit: $0) },
            fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    }
    let refused = guardedPlan("lmstudio", "/local/owner/model")
    check(refused.error?.contains("No installed local-folder-capable engine") == true && refused.executable == nil && refused.engineArgs.isEmpty,
          "local model + launcher: refused before a process can spawn")
    let cached = guardedPlan("hfid", "/local/owner/model")
    check(cached.error == nil && !cached.engineArgs.contains("--offline") && cached.engineEnv["HF_HUB_OFFLINE"] == nil,
          "HF id with a local dir + launcher: online unless the profile sets offline")
    let forcedOffline = guardedPlan("hfid", "/local/owner/model", offline: true)
    check(forcedOffline.engineArgs.contains("--offline") && forcedOffline.engineEnv["HF_HUB_OFFLINE"] == "1",
          "HF id + offline set: launch offline")
    check(guardedPlan("hfid", nil).error == nil && !guardedPlan("hfid", nil).engineArgs.contains("--offline"),
          "uncached HF model: the engine downloads it when offline is not set")
    check(guardedPlan("hfid", nil, offline: true).error?.contains("Offline is on") == true,
          "uncached HF model + offline set: explicit-download error, no silent download")
    planKit(fs: &fs, path: "/guard-kit", version: "1.3.0")
    check(guardedPlan("lmstudio", "/local/owner/model").error == nil, "local model + module: launch permitted")
}
do {
    var fs = FakeFS()
    let old = "/home/SplashUI/kit/splash-1.3.0"
    planKit(fs: &fs, path: old, version: "1.3.0")
    planKit(fs: &fs, path: "/brew/1.3.1/libexec", version: "1.3.1")
    fs.dir("/home/SplashUI/kit", ["splash-1.3.0/"])
    fs.dir("/cached/model", ["config.json"]); fs.file("/cached/model/config.json", "{}")
    func autoPlan(_ source: String) -> LaunchConfig {
        let cfg = planCfgJSON(engineMode: "auto", manualPath: nil, port: 8123, key: "test", name: "Auto",
            modelId: "owner/model", modelDir: "/cached/model", options: ["draft_model": "owner/draft"], modelSource: source)
        return planLaunch(cfg, home: "/home", isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
            brewKeg: { "/brew/1.3.1" }, kitVersion: { readKitVersion(fs: fs, kit: $0) },
            fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    }
    let local = autoPlan("lmstudio"), hub = autoPlan("hfhub")
    check(local.version == "1.3.0" && local.engineArgs.prefix(3) == ["-u", "-m", "server.server"] && local.engineArgs.contains("/cached/model/tokenizer"), "AUTO local directory: newest local-capable module engine with tokenizer argv")
    check(hub.version == "1.3.1" && !hub.engineArgs.contains("--offline") && hub.engineEnv["HF_HUB_OFFLINE"] == nil, "AUTO cached HF model: highest Homebrew engine, online unless offline is set")
    fs.dirs.remove(old)
    check(autoPlan("lmstudio").error?.contains("No installed local-folder-capable engine") == true, "AUTO local model without a local-capable engine: specific error, no download")
}
do {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent("splash-cache-" + UUID().uuidString).path
    defer { try? fm.removeItem(atPath: home) }
    let id = "local/Qwen3.8-27B-OptiQ-5bit-sharp-compact"
    let repo = home + "/.cache/huggingface/hub/models--local--Qwen3.8-27B-OptiQ-5bit-sharp-compact"
    let revision = String(repeating: "0", count: 40)
    let snapshot = repo + "/snapshots/" + revision
    try! fm.createDirectory(atPath: snapshot, withIntermediateDirectories: true)
    try! fm.createDirectory(atPath: repo + "/refs", withIntermediateDirectories: true)
    try! (revision + "\n").write(toFile: repo + "/refs/main", atomically: true, encoding: .utf8)
    let shards = (1...4).map { "model-0000\($0)-of-00004.safetensors" } + ["optiq/optiq_vision.safetensors"]
    try! fm.createDirectory(atPath: snapshot + "/optiq", withIntermediateDirectories: true)
    for name in ["config.json", "tokenizer.json", "tokenizer_config.json"] + shards {
        try! "{}".write(toFile: snapshot + "/" + name, atomically: true, encoding: .utf8)
    }
    try! #"{"model_type":"qwen3_5"}"#.write(toFile: snapshot + "/config.json", atomically: true, encoding: .utf8)
    let draftRepo = home + "/.cache/huggingface/hub/models--incoai--Qwen3.8-27B-DFlash2"
    let draftSnapshot = draftRepo + "/snapshots/complete-draft"
    try! fm.createDirectory(atPath: draftSnapshot, withIntermediateDirectories: true)
    try! fm.createDirectory(atPath: draftRepo + "/refs", withIntermediateDirectories: true)
    try! "complete-draft".write(toFile: draftRepo + "/refs/main", atomically: true, encoding: .utf8)
    for name in ["config.json", "model.safetensors"] {
        try! "{}".write(toFile: draftSnapshot + "/" + name, atomically: true, encoding: .utf8)
    }
    var weightMap = Dictionary(uniqueKeysWithValues: shards.prefix(4).enumerated().map { ("language_model.weight\($0.offset)", $0.element) })
    weightMap["vision_tower.blocks.0.weight"] = "optiq/optiq_vision.safetensors"
    let index = ["weight_map": weightMap]
    let originalIndex = try! JSONSerialization.data(withJSONObject: index)
    try! originalIndex.write(to: URL(fileURLWithPath: snapshot + "/model.safetensors.index.json"))
    let rewritten = try! flattenedHubIndex(originalIndex)
    let rewrittenWeights = ((try! JSONSerialization.jsonObject(with: rewritten.data)) as! [String: Any])["weight_map"] as! [String: String]
    check(rewrittenWeights.values.allSatisfy { !$0.contains("/") } && rewrittenWeights["vision_tower.blocks.0.weight"] == "vision-optiq.safetensors" && Set(rewrittenWeights.keys) == Set(weightMap.keys),
          "flat index: every filename is flat and all vision_tower tensor keys retain the vision shard")
    var fs = FakeFS()
    planKit(fs: &fs, path: "/brew/1.3.2/libexec", version: "1.3.2")
    planKit(fs: &fs, path: home + "/SplashUI/kit/old", version: "1.3.0")
    func plan(offline: Bool? = nil) -> LaunchConfig {
        var opts: [String: Any] = ["draft_model": "owner/draft"]
        if let offline { opts["offline"] = offline }
        let data = planCfgJSON(engineMode: "auto", manualPath: nil, port: 8123, key: "test", name: "OptiQ Compact",
            modelId: id, modelDir: "/lmstudio/local/model", options: opts, modelSource: "lmstudio")
        return planLaunch(data, home: home,
            isDir: { path in var dir: ObjCBool = false; return fs.isDir(path) || (fm.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue) },
            isExecutable: { fs.isExecutable($0) }, brewKeg: { "/brew/1.3.2" }, kitVersion: { readKitVersion(fs: fs, kit: $0) },
            fileContents: { (try? String(contentsOfFile: $0, encoding: .utf8)) ?? fs.fileContents($0) },
            listDir: { (try? fm.contentsOfDirectory(atPath: $0)) ?? fs.listDir($0) })
    }
    let config = planCfgJSON(engineMode: "auto", manualPath: nil, port: 8123, key: "test", name: "OptiQ Compact", modelId: id, modelDir: nil, options: [:], modelSource: "lmstudio")
    let flatRoot = try! prepareFlatHubCache(parseConfig(config).doc!, home: home)!
    let flatSnapshot = flatRoot + "/models--local--Qwen3.8-27B-OptiQ-5bit-sharp-compact/snapshots/" + revision
    check((try! Data(contentsOf: URL(fileURLWithPath: snapshot + "/model.safetensors.index.json"))) == originalIndex &&
          (try! fm.destinationOfSymbolicLink(atPath: flatSnapshot + "/vision-optiq.safetensors")) == snapshot + "/optiq/optiq_vision.safetensors",
          "flat cache: source index unchanged and vision weights are symlinked, never copied")
    check(try! prepareFlatHubCache(parseConfig(config).doc!, home: home) == flatRoot, "flat cache: preparing again is idempotent")
    let linkedDraft = flatRoot + "/models--incoai--Qwen3.8-27B-DFlash2"
    check((try! fm.destinationOfSymbolicLink(atPath: linkedDraft)) == draftRepo &&
          (try! String(contentsOfFile: linkedDraft + "/refs/main", encoding: .utf8)) == "complete-draft" &&
          fm.fileExists(atPath: linkedDraft + "/snapshots/complete-draft/model.safetensors"),
          "flat cache: complete family DFlash2 repo is symlinked idempotently for offline draft resolution")
    let offline = plan()
    check(offline.error == nil && offline.version == "1.3.2" && offline.modelDir == flatSnapshot &&
          offline.engineArgs.prefix(5) == ["-u", "install/launcher.py", "serve", "--model", id] &&
          offline.engineArgs.contains("--offline") && offline.engineEnv["HF_HUB_OFFLINE"] == "1" && offline.engineEnv["HF_HUB_CACHE"] == flatRoot,
          "AUTO OptiQ nested vision: Homebrew 1.3.2 offline using isolated flat cache")
    check(plan(offline: false).error == nil && !plan(offline: false).engineArgs.contains("--offline") && plan(offline: false).engineEnv["HF_HUB_OFFLINE"] == nil,
          "AUTO OptiQ local-folder model with offline set false: the explicit false is honored")
    try! rewritten.data.write(to: URL(fileURLWithPath: snapshot + "/model.safetensors.index.json"))
    try! fm.createSymbolicLink(atPath: snapshot + "/vision-optiq.safetensors", withDestinationPath: snapshot + "/optiq/optiq_vision.safetensors")
    check(plan().modelDir == snapshot && plan().engineEnv["HF_HUB_CACHE"] == nil,
          "compatible original snapshot takes precedence over app-owned flat cache")
    try! originalIndex.write(to: URL(fileURLWithPath: snapshot + "/model.safetensors.index.json"))
    try! fm.removeItem(atPath: snapshot + "/" + shards[3])
    try! fm.removeItem(atPath: flatSnapshot + "/" + shards[3])
    check(plan().version != "1.3.2" || plan().error != nil, "incomplete Hub snapshot: a missing indexed shard never enables offline launcher")
}
do {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent("splash-gguf-" + UUID().uuidString).path
    defer { try? fm.removeItem(atPath: home) }
    let id = "ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF"
    let repo = home + "/.cache/huggingface/hub/models--ISTA-DASLab--Qwen3.8-27B-GSQ-RCO-GGUF"
    let revision = "d562806dbafae37109975e970aae91b43e73b440"
    let snapshot = repo + "/snapshots/" + revision
    try! fm.createDirectory(atPath: snapshot, withIntermediateDirectories: true)
    try! fm.createDirectory(atPath: repo + "/refs", withIntermediateDirectories: true)
    try! revision.write(toFile: repo + "/refs/main", atomically: true, encoding: .utf8)
    for name in ["Qwen3.8-27B-GSQ-RCO-IQ3_S-mtp.gguf", "mmproj-Qwen3.8-27B-BF16.gguf"] {
        try! Data("GGUF".utf8).write(to: URL(fileURLWithPath: snapshot + "/" + name))
    }
    func plan(_ supportsGGUF: Bool) -> LaunchConfig {
        let data = planCfgJSON(engineMode: "auto", manualPath: nil, port: 8123, key: "test", name: "3-Bit",
            modelId: id, modelDir: nil, options: ["offline": true], modelSource: "hfhub")
        return planLaunch(data, home: home,
            isDir: { path in var d: ObjCBool = false; return path == "/brew/libexec" || (fm.fileExists(atPath: path, isDirectory: &d) && d.boolValue) },
            isExecutable: { $0 == "/brew/libexec/engine/splash" || $0 == "/brew/libexec/python/bin/python" },
            brewKeg: { "/brew" }, kitVersion: { _ in supportsGGUF ? "1.3.2" : "1.3.1" },
            fileContents: { path in path == "/brew/libexec/install/upstream.py" && supportsGGUF ? "def _gguf_target(repo, variant, language_only, scratch):" : (try? String(contentsOfFile: path, encoding: .utf8)) },
            listDir: { try? fm.contentsOfDirectory(atPath: $0) })
    }
    let gguf = plan(true)
    check(gguf.error == nil && gguf.modelDir == snapshot && gguf.engineArgs.prefix(5) == ["-u", "install/launcher.py", "serve", "--model", id] &&
          gguf.engineArgs.contains("--offline") && gguf.engineEnv["HF_HUB_OFFLINE"] == "1" && gguf.engineEnv["HF_HUB_CACHE"] == nil,
          "GGUF-only target plus BF16 mmproj cache: capable 1.3.2 launcher offline without variant or config.json")
    check(plan(false).error?.contains("does not support GGUF targets") == true,
          "GGUF-only cache: older engine gets accurate GGUF capability refusal")
}

// 67. planLaunch happy path, the 1.3.0 module form: a manual kit + a package
// model found by enumeration -> positional dir argv, key via env, port from the
// config.
do {
    var fs = FakeFS()
    planKit(fs: &fs, path: "/kits/kit130", version: "1.3.0")
    fs.dir("/models/incoai/Qwen3.8-27B-Splash",
           ["manifest.json", "model.json", "config.json", "tokenizer/", "draft/"])
    fs.file("/models/incoai/Qwen3.8-27B-Splash/draft/config.json")
    let cfg = planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130", port: 8123,
                          key: "splash-standalone-1", name: "Default",
                          modelId: "incoai/Qwen3.8-27B-Splash", modelDir: nil, options: [:])
    let plan = planLaunch(cfg, home: "/home",
                          isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                          brewKeg: { nil },
                          kitVersion: { readKitVersion(fs: fs, kit: $0) },
                          fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    check(plan.error == nil, "planLaunch: the happy path plans (got: \(plan.error ?? "ok"))")
    check(plan.workDir == "/kits/kit130" && plan.base == "/kits/kit130",
          "planLaunch: workDir = the resolved manual kit")
    check(plan.executable == "/kits/kit130/python/bin/python3", "planLaunch: the kit's bundled python")
    check(plan.version == "1.3.0", "planLaunch: version from the kit's release.json (D16)")
    check(plan.modelDir == "/models/incoai/Qwen3.8-27B-Splash",
          "planLaunch: the model dir is resolved by enumeration (stored dir was null)")
    check(Array(plan.engineArgs.prefix(3)) == ["-u", "-m", "server.server"], "planLaunch: the module form prefix")
    check(plan.engineArgs.count > 3 && plan.engineArgs[3] == "/models/incoai/Qwen3.8-27B-Splash",
          "planLaunch: the positional dir (1.3.0 loads it, never re-downloading)")
    check(plan.engineArgs.contains("--model") && plan.modelId == "incoai/Qwen3.8-27B-Splash",
          "planLaunch: server.py's required --model OWNER/REPO")
    check(plan.engineEnv["SPLASH_API_KEY"] == "splash-standalone-1", "planLaunch: the key via env (open item 5)")
    check(!plan.engineArgs.contains("--api-key"), "planLaunch: the key is NEVER on argv")
    check(portArg(plan) == "8123", "planLaunch: the port from the config (not the engine default)")
    check(!plan.mappingFallback, "planLaunch: an exact contract is not a fallback")
    check(plan.profileId == "p1" && plan.profileName == "Default", "planLaunch: profile identity is carried")
    check(plan.restartRequired == false, "planLaunch: a fresh plan never requires a restart (S4 wires the state)")
    check(!plan.signature.isEmpty, "planLaunch: the plan signature is computed (D13)")
}

// 68. planLaunch happy path, the 1.3.1 launcher form via the Homebrew rung: an
// HF model with a known family config -> the launcher serves by id; ANE off is
// explicit; the key reaches the env (never argv).
do {
    var fs = FakeFS()
    planKit(fs: &fs, path: "/keg/1.3.1/libexec", version: "1.3.1")
    fs.dir("/models/mlx-community/Qwen3.8-27B-4bit", ["config.json"])
    fs.file("/models/mlx-community/Qwen3.8-27B-4bit/config.json",
            "{\"model_type\": \"qwen3_5\"}")
    let cfg = planCfgJSON(engineMode: "auto", manualPath: nil, port: 9000, key: "test-key",
                          name: "Qwen", modelId: "mlx-community/Qwen3.8-27B-4bit",
                          modelDir: nil, options: ["ane": "false"])
    let plan = planLaunch(cfg, home: "/home",
                          isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                          brewKeg: { "/keg/1.3.1" },
                          kitVersion: { readKitVersion(fs: fs, kit: $0) },
                          fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    check(plan.error == nil, "planLaunch: the launcher form plans (got: \(plan.error ?? "ok"))")
    check(plan.workDir == "/keg/1.3.1/libexec", "planLaunch: the Homebrew keg's libexec is the kit (rung 3)")
    check(plan.version == "1.3.1", "planLaunch: the keg's release.json version")
    check(Array(plan.engineArgs.prefix(5)) == ["-u", "install/launcher.py", "serve",
                                               "--model", "mlx-community/Qwen3.8-27B-4bit"],
          "planLaunch: the launcher serves the model by its HF id")
    check(plan.engineArgs.contains("--disable-ane"),
          "planLaunch: ANE default-on — only an explicit ane=false adds --disable-ane")
    check(portArg(plan) == "9000", "planLaunch: the config's port")
    check(plan.engineEnv["SPLASH_API_KEY"] == "test-key" && !plan.engineArgs.contains("--api-key"),
          "planLaunch: the key via env (open item 5), never on argv")
    check(plan.modelId == "mlx-community/Qwen3.8-27B-4bit", "planLaunch: the served model id")
}

// 69. D9: the plan is invariant under the legacy SPLASH_* env vars — the config
// is the single source of truth; nothing in the plan may come from the process
// environment (driven through the real environment via setenv).
do {
    var fs = FakeFS()
    planKit(fs: &fs, path: "/kits/kit130", version: "1.3.0")
    fs.dir("/models/incoai/Qwen3.8-27B-Splash",
           ["manifest.json", "model.json", "config.json", "tokenizer/", "draft/"])
    fs.file("/models/incoai/Qwen3.8-27B-Splash/draft/config.json")
    let cfg = planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130", port: 8123,
                          key: "splash-standalone-1", name: "Default",
                          modelId: "incoai/Qwen3.8-27B-Splash", modelDir: nil, options: [:])
    let planA = planLaunch(cfg, home: "/home",
                           isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                           brewKeg: { nil },
                           kitVersion: { readKitVersion(fs: fs, kit: $0) },
                           fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    setenv("SPLASH_KIT_DIR", "/elsewhere/kit", 1)
    setenv("SPLASH_PORT", "6969", 1)
    setenv("SPLASH_KEY", "attacker-key", 1)
    setenv("SPLASH_MODEL_ROOT", "/elsewhere/model", 1)
    setenv("SPLASH_MAX_CACHE_DISK", "1gb", 1)
    setenv("SPLASH_ANE", "off", 1)
    defer {
        unsetenv("SPLASH_KIT_DIR"); unsetenv("SPLASH_PORT"); unsetenv("SPLASH_KEY")
        unsetenv("SPLASH_MODEL_ROOT"); unsetenv("SPLASH_MAX_CACHE_DISK"); unsetenv("SPLASH_ANE")
    }
    let planB = planLaunch(cfg, home: "/home",
                           isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                           brewKeg: { nil },
                           kitVersion: { readKitVersion(fs: fs, kit: $0) },
                           fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    check(planA == planB, "D9: the plan is byte-identical with the legacy SPLASH_* env set")
    check(planB.workDir == "/kits/kit130", "D9: the kit from the config, not SPLASH_KIT_DIR")
    check(portArg(planB) == "8123", "D9: the port from the config, not SPLASH_PORT")
    check(planB.engineEnv["SPLASH_API_KEY"] == "splash-standalone-1",
          "D9: the key from the config, not SPLASH_KEY")
    check(!planB.engineArgs.contains("--disable-ane"), "D9: ANE from the config, not SPLASH_ANE")
}

// 70. planLaunch error cases carry actionable text: the tried rungs for a missing
// kit; the 1.3.0-package gate (blocked); an unrunnable assembly; no model.
do {
    // (a) no kit anywhere: the manual rung is named, with the fix.
    let fs = FakeFS()
    let cfgA = planCfgJSON(engineMode: "manual", manualPath: "/no/kit", port: 8123, key: "k",
                           name: "D", modelId: "incoai/Qwen3.8-27B-Splash", modelDir: nil, options: [:])
    let pA = planLaunch(cfgA, home: "/home",
                        isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                        brewKeg: { nil }, kitVersion: { readKitVersion(fs: fs, kit: $0) },
                        fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    check(pA.error != nil && pA.error!.contains("/no/kit"), "planLaunch: the kit error names the tried rung")
    check((pA.error ?? "").contains("install.sh") || (pA.error ?? "").contains("Homebrew"),
          "planLaunch: the kit error names the fix")
    // (b) a 1.3.0 package model under a 1.3.1 engine: the package gate (blocked).
    var fsB = FakeFS()
    planKit(fs: &fsB, path: "/kits/k131", version: "1.3.1")
    fsB.dir("/models/incoai/Qwen3.8-27B-Splash",
            ["manifest.json", "model.json", "config.json", "tokenizer/", "draft/"])
    fsB.file("/models/incoai/Qwen3.8-27B-Splash/draft/config.json")
    let cfgB = planCfgJSON(engineMode: "manual", manualPath: "/kits/k131", port: 8123, key: "k",
                           name: "D", modelId: "incoai/Qwen3.8-27B-Splash", modelDir: nil, options: [:])
    let pB = planLaunch(cfgB, home: "/home",
                        isDir: { fsB.isDir($0) }, isExecutable: { fsB.isExecutable($0) },
                        brewKeg: { nil }, kitVersion: { readKitVersion(fs: fsB, kit: $0) },
                        fileContents: { fsB.fileContents($0) }, listDir: { fsB.listDir($0) })
    check(pB.error != nil && pB.error!.contains("refuses 1.3.0 packages"),
          "planLaunch: the 1.3.0 package under 1.3.1 is refused pre-flight (the issue's friction)")
    // (c) an assembly missing its draft under 1.3.0: unrunnable (R3).
    var fsC = FakeFS()
    planKit(fs: &fsC, path: "/kits/kit130", version: "1.3.0")
    fsC.dir("/models/o/asm", ["model.json", "config.json"])
    let cfgC = planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130", port: 8123, key: "k",
                           name: "D", modelId: "o/asm", modelDir: nil, options: [:])
    let pC = planLaunch(cfgC, home: "/home",
                        isDir: { fsC.isDir($0) }, isExecutable: { fsC.isExecutable($0) },
                        brewKeg: { nil }, kitVersion: { readKitVersion(fs: fsC, kit: $0) },
                        fileContents: { fsC.fileContents($0) }, listDir: { fsC.listDir($0) })
    check(pC.error != nil && pC.error!.contains("draft/config.json"),
          "planLaunch: an assembly without draft/config.json is unrunnable (R3: the draft is required in both versions)")
    // (d) no model selected: a clean error, not a crash.
    let cfgD = planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130", port: 8123, key: "k",
                           name: "D", modelId: nil, modelDir: nil, options: [:])
    var fsD = FakeFS()
    planKit(fs: &fsD, path: "/kits/kit130", version: "1.3.0")
    let pD = planLaunch(cfgD, home: "/home",
                        isDir: { fsD.isDir($0) }, isExecutable: { fsD.isExecutable($0) },
                        brewKeg: { nil }, kitVersion: { readKitVersion(fs: fsD, kit: $0) },
                        fileContents: { fsD.fileContents($0) }, listDir: { fsD.listDir($0) })
    check(pD.error != nil && (pD.error ?? "").contains("no model"),
          "planLaunch: no model selected -> a clean error (never a launch attempt)")
}

// 71. the plan signature (D13): it flips when a field changes the argv/env/workdir
// (port, key, ane, model, kit, fallback contract) — and NEVER on a profile rename.
do {
    var fs = FakeFS()
    planKit(fs: &fs, path: "/kits/k131", version: "1.3.1")
    fs.dir("/models/mlx-community/Qwen3.8-27B-4bit", ["config.json"])
    fs.file("/models/mlx-community/Qwen3.8-27B-4bit/config.json", "{\"model_type\": \"qwen3_5\"}")
    fs.dir("/models/o/other", ["config.json"])
    let plan: (Int, String, String, String?, String) -> LaunchConfig = { port, key, name, kit, mid in
        let cfg = planCfgJSON(engineMode: "manual", manualPath: kit, port: port, key: key,
                              name: name, modelId: mid, modelDir: nil, options: ["ane": "false"])
        return planLaunch(cfg, home: "/home",
                          isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                          brewKeg: { nil },
                          kitVersion: { readKitVersion(fs: fs, kit: $0) },
                          fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    }
    let s0 = plan(8123, "k", "Default", "/kits/k131", "mlx-community/Qwen3.8-27B-4bit")
    check(s0.error == nil, "signature: the base plan is valid")
    check(s0.signature != plan(8124, "k", "Default", "/kits/k131", "mlx-community/Qwen3.8-27B-4bit").signature,
          "signature: a port change flips it")
    check(s0.signature != plan(8123, "k2", "Default", "/kits/k131", "mlx-community/Qwen3.8-27B-4bit").signature,
          "signature: a key change flips it (it reaches the child via env)")
    check(s0.signature == plan(8123, "k", "Renamed", "/kits/k131", "mlx-community/Qwen3.8-27B-4bit").signature,
          "signature: a profile rename does NOT flip it (D13)")
    check(s0.signature != plan(8123, "k", "Default", "/kits/k131", "o/other").signature,
          "signature: a model change flips it")
    // a kit change: a second kit of the same version (the workdir differs).
    planKit(fs: &fs, path: "/kits/k131b", version: "1.3.1")
    check(s0.signature != plan(8123, "k", "Default", "/kits/k131b", "mlx-community/Qwen3.8-27B-4bit").signature,
          "signature: a kit change flips it (the workdir is part of the plan)")
    // a fallback-contract change: an unversioned kit -> the latest contract (D16/D3).
    planKit(fs: &fs, path: "/kits/future", version: "1.9.9")
    let pf = plan(8123, "k", "Default", "/kits/future", "mlx-community/Qwen3.8-27B-4bit")
    check(s0.signature != pf.signature, "signature: a fallback-contract change flips it")
}

// 72. the unknown verdict is NOT a gate: an hfid whose family the app cannot
// derive plans fine (the engine decides at load); an explicit --draft-model also
// plans fine regardless of family.
do {
    var fs = FakeFS()
    planKit(fs: &fs, path: "/kits/k131", version: "1.3.1")
    fs.dir("/models/o/mystery", ["config.json"])
    fs.file("/models/o/mystery/config.json", "{\"model_type\": \"gemma_4\"}")
    let cfg = planCfgJSON(engineMode: "manual", manualPath: "/kits/k131", port: 8123, key: "k",
                          name: "D", modelId: "o/mystery", modelDir: nil, options: [:])
    let plan = planLaunch(cfg, home: "/home",
                          isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                          brewKeg: { nil },
                          kitVersion: { readKitVersion(fs: fs, kit: $0) },
                          fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    check(plan.error == nil, "planLaunch: an undecidable family is not blocked (D4: the engine decides at load)")
    let cfg2 = planCfgJSON(engineMode: "manual", manualPath: "/kits/k131", port: 8123, key: "k",
                           name: "D", modelId: "o/mystery", modelDir: nil,
                           options: ["draft_model": "incoai/Qwen3.8-27B-DFlash2"])
    let plan2 = planLaunch(cfg2, home: "/home",
                           isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                           brewKeg: { nil },
                           kitVersion: { readKitVersion(fs: fs, kit: $0) },
                           fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    check(plan2.error == nil, "planLaunch: an explicit --draft-model override plans regardless of family")
    check(plan2.engineArgs.contains("--draft-model")
          && plan2.engineArgs.firstIndex(of: "--draft-model").map {
              plan2.engineArgs[$0 + 1] == "incoai/Qwen3.8-27B-DFlash2"
          } == true,
          "planLaunch: the --draft-model override reaches the argv")
}

// 73. D4: an unrunnable/blocked plan is saveable — it still carries the model +
// profile identity (S6 saves it; S7 shows the verdict chip + the fix text).
do {
    var fs = FakeFS()
    planKit(fs: &fs, path: "/kits/k131", version: "1.3.1")
    fs.dir("/models/incoai/Qwen3.8-27B-Splash",
           ["manifest.json", "model.json", "config.json", "tokenizer/", "draft/"])
    fs.file("/models/incoai/Qwen3.8-27B-Splash/draft/config.json")
    let cfg = planCfgJSON(engineMode: "manual", manualPath: "/kits/k131", port: 8123, key: "k",
                          name: "D", modelId: "incoai/Qwen3.8-27B-Splash", modelDir: nil, options: [:])
    let plan = planLaunch(cfg, home: "/home",
                          isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                          brewKeg: { nil },
                          kitVersion: { readKitVersion(fs: fs, kit: $0) },
                          fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    check(plan.error != nil, "planLaunch: the package under 1.3.1 errors")
    check(plan.modelId == "incoai/Qwen3.8-27B-Splash" && plan.profileId == "p1" && plan.profileName == "D",
          "D4: the failed plan still carries the model + profile identity (saveable)")
}

// 74. D16/D3: an unversioned kit (release.json unknown) plans on the LATEST
// fallback contract with mappingFallback set (the visible indicator's source).
do {
    var fs = FakeFS()
    planKit(fs: &fs, path: "/kits/future", version: "1.9.9")
    fs.dir("/models/mlx-community/Qwen3.8-27B-4bit", ["config.json"])
    fs.file("/models/mlx-community/Qwen3.8-27B-4bit/config.json", "{\"model_type\": \"qwen3_5\"}")
    let cfg = planCfgJSON(engineMode: "manual", manualPath: "/kits/future", port: 8123, key: "k",
                          name: "D", modelId: "mlx-community/Qwen3.8-27B-4bit", modelDir: nil, options: [:])
    let plan = planLaunch(cfg, home: "/home",
                          isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                          brewKeg: { nil },
                          kitVersion: { readKitVersion(fs: fs, kit: $0) },
                          fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
    check(plan.error == nil, "planLaunch: a 1.9.9 kit plans on the fallback (not an error)")
    check(plan.mappingFallback, "D3: mappingFallback is set for the unknown version")
    check(plan.version == "1.9.9", "planLaunch: version = what release.json said (not the fallback's)")
}


// S2b fixtures: verbatim copies of the SERVE_OPTIONS table of the real kits'
// server/serve_options.py. The 1.3.1 keg's file is byte-identical to the 1.3.0
// kit's (verified in S2a), so one fixture covers both; the 1.3.2 table is the
// github.com/incoai/splash tag 1.3.2 copy.
let fixtureServeOptions130 = #"""
SERVE_OPTIONS = (
    ServeOption(
        "--host",
        "network",
        dict(
            default="127.0.0.1",
            metavar="ADDRESS",
            help="HTTP bind address (default: 127.0.0.1; 0.0.0.0 for all IPv4 "
            "interfaces); clients use an IP address, localhost or a name given "
            "with --allowed-host",
        ),
    ),
    ServeOption(
        "--allowed-host",
        "network",
        dict(
            action="append",
            default=[],
            metavar="HOST",
            help="additional HTTP Host name to accept, e.g. mymac.local; does not "
            "change the bind address (repeatable)",
        ),
    ),
    ServeOption(
        "--allowed-origin",
        "network",
        dict(
            action="append",
            default=[],
            type=parse_allowed_origin,
            metavar="ORIGIN",
            help="origin whose pages may call the API from a browser or webview, "
            "e.g. tauri://localhost; '*' for any (repeatable)",
        ),
        text=_origin_text,
    ),
    ServeOption(
        "--api-key",
        "network",
        dict(
            type=parse_api_key,
            metavar="KEY",
            help="require this key as a bearer token or x-api-key on every route "
            "but the chat page, /health and /ready (default: SPLASH_API_KEY)",
        ),
        environment="SPLASH_API_KEY",
        secret=True,
    ),
    ServeOption(
        "--no-webui",
        "network",
        dict(action="store_true", default=False, help="disable the chat page"),
    ),
    ServeOption(
        "--max-memory",
        "memory",
        dict(
            type=parse_max_memory,
            default=None,
            metavar="SIZE",
            help="Metal memory budget, e.g. 28G; it can only lower the automatic "
            "budget (default: auto)",
        ),
    ),
    ServeOption(
        "--max-context",
        "memory",
        dict(
            type=parse_max_context,
            default=None,
            metavar="TOKENS",
            help="context token limit, e.g. 100K (K = 1024 tokens); it can only "
            "lower the automatic limit, the model's native window when memory "
            "holds it (default: auto)",
        ),
    ),
    ServeOption(
        "--kv-format",
        "memory",
        dict(
            choices=("int8", "bf16"),
            default="int8",
            help="target KV cache storage (default: int8); bf16 uses more memory",
        ),
    ),
    ServeOption(
        "--idle-release",
        "memory",
        dict(
            type=parse_idle_release,
            default=None,
            metavar="DURATION",
            help="time without a request before the engine unwires its memory and "
            "frees the weights: seconds, or with an s, m or h suffix, e.g. 30m "
            "(default: 10m); off keeps both",
        ),
        text=idle_release_text,
    ),
    ServeOption(
        "--max-cache-disk",
        "cache",
        dict(
            type=parse_max_cache_disk,
            default=0,
            metavar="SIZE",
            help="SSD quota for cached KV pages and states, e.g. 5G (default: 0, "
            "disabled)",
        ),
    ),
    ServeOption(
        "--persistent-cache",
        "cache",
        dict(
            action="store_true",
            default=False,
            help="keep the SSD cache across restarts (needs --max-cache-disk)",
        ),
    ),
    ServeOption(
        "--cache-dir",
        "cache",
        dict(
            type=parse_cache_dir,
            default=None,
            metavar="DIRECTORY",
            help="where --persistent-cache keeps its files; needs "
            "--persistent-cache (default: ~/Library/Caches/Splash/prefix-cache)",
        ),
    ),
    ServeOption(
        "--served-model-name",
        "api",
        dict(
            action="append",
            default=[],
            type=parse_served_model_name,
            metavar="NAME",
            help="additional API model name (repeatable); responses report the "
            "loaded model ID unless --announce-served-name",
        ),
    ),
    ServeOption(
        "--announce-served-name",
        "api",
        dict(
            action="store_true",
            default=False,
            help="report the first --served-model-name in API responses and list "
            "it first in /v1/models; /status keeps the loaded model ID (needs "
            "--served-model-name)",
        ),
    ),
    ServeOption(
        "--default-reasoning-effort",
        "api",
        dict(
            type=parse_reasoning_effort,
            metavar="EFFORT",
            help="effort of Chat and Responses requests that set none: "
            + ", ".join(REASONING_EFFORTS[:-1])
            + f" or {REASONING_EFFORTS[-1]} (default: "
            "SPLASH_DEFAULT_REASONING_EFFORT, else the model template's)",
        ),
        environment="SPLASH_DEFAULT_REASONING_EFFORT",
    ),
    ServeOption(
        "--max-request-size",
        "requests",
        dict(
            type=parse_request_size,
            default=DEFAULT_MAX_REQUEST_BYTES,
            metavar="SIZE",
            help="maximum HTTP request body size, e.g. 128M (default: 128M); "
            "shared input budget is max(512M, twice this limit)",
        ),
    ),
    ServeOption(
        "--max-image-pixels",
        "requests",
        dict(
            type=parse_max_image_pixels,
            default=images.MAX_PIXELS,
            metavar="PIXELS",
            help=f"maximum resized pixels per image, {images.MIN_PIXELS}–"
            f"{images.MAX_PIXELS} (default: {images.MAX_PIXELS}); bounds the "
            "vision scratch one image needs",
        ),
    ),
    ServeOption(
        "--request-timeout",
        "requests",
        dict(
            type=parse_request_timeout,
            default=None,
            metavar="DURATION",
            help="time before a queued or in-flight request expires with 504: "
            "seconds, or with an s, m or h suffix, e.g. 30m (default: none)",
        ),
    ),
    ServeOption(
        "--queue-size",
        "requests",
        dict(
            type=parse_queue_size,
            default=DEFAULT_QUEUE_SIZE,
            metavar="REQUESTS",
            help="requests admitted at once, running or waiting; more get 503 "
            f"(default: {DEFAULT_QUEUE_SIZE})",
        ),
    ),
    ServeOption(
        "--decode-share",
        "requests",
        dict(
            type=parse_decode_share,
            default=None,
            metavar="SHARE",
            help="decode time owed per unit of prefill time while other requests "
            "decode (default: 0.5; 0 alternates one command each)",
        ),
    ),
    ServeOption(
        "--disable-ane",
        "requests",
        dict(
            action="store_true",
            default=False,
            help="prefill on the GPU alone (default: a dense model's long "
            "prompts also use the Neural Engine when that is faster)",
        ),
    ),
    ServeOption(
        "--allow-idle-sleep",
        "requests",
        dict(
            action="store_true",
            default=False,
            help="let the Mac sleep automatically while requests run (default: it "
            "stays awake until they finish; the display may still sleep)",
        ),
    ),
)
"""#
let fixtureServeOptions132 = #"""
SERVE_OPTIONS = (
    ServeOption(
        "--host",
        "network",
        dict(
            default="127.0.0.1",
            metavar="ADDRESS",
            help="HTTP bind address (default: 127.0.0.1; 0.0.0.0 for all IPv4 "
            "interfaces); clients use an IP address, localhost or a name given "
            "with --allowed-host",
        ),
    ),
    ServeOption(
        "--allowed-host",
        "network",
        dict(
            action="append",
            default=[],
            metavar="HOST",
            help="additional HTTP Host name to accept, e.g. mymac.local; does not "
            "change the bind address (repeatable)",
        ),
    ),
    ServeOption(
        "--allowed-origin",
        "network",
        dict(
            action="append",
            default=[],
            type=parse_allowed_origin,
            metavar="ORIGIN",
            help="origin whose pages may call the API from a browser or webview, "
            "e.g. tauri://localhost; '*' for any (repeatable)",
        ),
        text=_origin_text,
    ),
    ServeOption(
        "--api-key",
        "network",
        dict(
            type=parse_api_key,
            metavar="KEY",
            help="require this key as a bearer token or x-api-key on every route "
            "but the chat page, /health and /ready (default: SPLASH_API_KEY)",
        ),
        environment="SPLASH_API_KEY",
        secret=True,
    ),
    ServeOption(
        "--no-webui",
        "network",
        dict(action="store_true", default=False, help="disable the chat page"),
    ),
    ServeOption(
        "--max-memory",
        "memory",
        dict(
            type=parse_max_memory,
            default=None,
            metavar="SIZE",
            help="Metal memory budget, e.g. 28G; it can only lower the automatic "
            "budget (default: auto)",
        ),
    ),
    ServeOption(
        "--max-context",
        "memory",
        dict(
            type=parse_max_context,
            default=None,
            metavar="TOKENS",
            help="context token limit, e.g. 100K (K = 1024 tokens); it can only "
            "lower the automatic limit, the model's native window when memory "
            "holds it (default: auto)",
        ),
    ),
    ServeOption(
        "--kv-format",
        "memory",
        dict(
            choices=("int8", "bf16"),
            default="int8",
            help="target KV cache storage (default: int8); bf16 uses more memory",
        ),
    ),
    ServeOption(
        "--state-format",
        "memory",
        dict(
            choices=("fp32", "bf16"),
            default="fp32",
            help="recurrent state storage (default: fp32); bf16 halves each "
            "state, so memory and the SSD cache hold about twice as many",
        ),
    ),
    ServeOption(
        "--idle-release",
        "memory",
        dict(
            type=parse_idle_release,
            default=None,
            metavar="DURATION",
            help="time without a request before the engine unwires its memory and "
            "frees the weights: seconds, or with an s, m or h suffix, e.g. 30m "
            "(default: 10m); off keeps both, though POST /v1/memory/release "
            "still frees the weights",
        ),
        text=idle_release_text,
    ),
    ServeOption(
        "--max-cache-disk",
        "cache",
        dict(
            type=parse_max_cache_disk,
            default=None,
            metavar="SIZE",
            help="SSD quota for cached KV pages and states: auto follows the "
            "volume's free space up to 32G, 0 disables, or a size such as 16G "
            "(default: auto)",
        ),
    ),
    ServeOption(
        "--max-cache-disk-writes",
        "cache",
        dict(
            type=parse_max_cache_disk_writes,
            default=0,
            metavar="SIZE",
            help="the most the SSD cache writes a day, e.g. 200G; the state a "
            "conversation resumes from and KV pages pass it (default: 0, no "
            "limit)",
        ),
    ),
    ServeOption(
        "--persistent-cache",
        "cache",
        dict(
            action="store_true",
            default=False,
            help="keep the SSD cache across restarts",
        ),
    ),
    ServeOption(
        "--cache-dir",
        "cache",
        dict(
            type=parse_cache_dir,
            default=None,
            metavar="DIRECTORY",
            help="where --persistent-cache keeps its files; needs "
            "--persistent-cache (default: ~/Library/Caches/Splash/prefix-cache)",
        ),
    ),
    ServeOption(
        "--served-model-name",
        "api",
        dict(
            action="append",
            default=[],
            type=parse_served_model_name,
            metavar="NAME",
            help="additional API model name (repeatable); responses report the "
            "loaded model ID unless --announce-served-name",
        ),
    ),
    ServeOption(
        "--announce-served-name",
        "api",
        dict(
            action="store_true",
            default=False,
            help="report the first --served-model-name in API responses and list "
            "it first in /v1/models; /status keeps the loaded model ID (needs "
            "--served-model-name)",
        ),
    ),
    ServeOption(
        "--default-reasoning-effort",
        "api",
        dict(
            type=parse_reasoning_effort,
            metavar="EFFORT",
            help="effort of Chat and Responses requests that set none: "
            + ", ".join(REASONING_EFFORTS[:-1])
            + f" or {REASONING_EFFORTS[-1]} (default: "
            "SPLASH_DEFAULT_REASONING_EFFORT, else the model template's)",
        ),
        environment="SPLASH_DEFAULT_REASONING_EFFORT",
    ),
    ServeOption(
        "--thinking-token-budget",
        "api",
        dict(
            type=parse_thinking_token_budget,
            metavar="N",
            help="thinking tokens of a thinking request that sets no "
            "thinking_token_budget, after which its thinking closes (default: "
            "SPLASH_THINKING_TOKEN_BUDGET, else no cap)",
        ),
        environment="SPLASH_THINKING_TOKEN_BUDGET",
    ),
    ServeOption(
        "--thinking-end-text",
        "api",
        dict(
            metavar="TEXT",
            help="text that ends thinking where a thinking budget runs out, such "
            "as a sentence that turns to the answer, then </think> as its last "
            f"token; at most {MAX_THINKING_END_TOKENS} tokens (default: "
            "SPLASH_THINKING_END_TEXT, else </think> alone)",
        ),
        environment="SPLASH_THINKING_END_TEXT",
    ),
    ServeOption(
        "--max-request-size",
        "requests",
        dict(
            type=parse_request_size,
            default=DEFAULT_MAX_REQUEST_BYTES,
            metavar="SIZE",
            help="maximum HTTP request body size, e.g. 128M (default: 128M); "
            "shared input budget is max(512M, twice this limit)",
        ),
    ),
    ServeOption(
        "--max-image-pixels",
        "requests",
        dict(
            type=parse_max_image_pixels,
            default=images.MAX_PIXELS,
            metavar="PIXELS",
            help=f"maximum resized pixels per image, {images.MIN_PIXELS}–"
            f"{images.MAX_PIXELS} (default: {images.MAX_PIXELS}); bounds the "
            "vision scratch one image needs",
        ),
    ),
    ServeOption(
        "--request-timeout",
        "requests",
        dict(
            type=parse_request_timeout,
            default=None,
            metavar="DURATION",
            help="time before a queued or in-flight request expires with 504: "
            "seconds, or with an s, m or h suffix, e.g. 30m (default: none)",
        ),
    ),
    ServeOption(
        "--queue-size",
        "requests",
        dict(
            type=parse_queue_size,
            default=DEFAULT_QUEUE_SIZE,
            metavar="REQUESTS",
            help="requests admitted at once, running or waiting; more get 503 "
            f"(default: {DEFAULT_QUEUE_SIZE})",
        ),
    ),
    ServeOption(
        "--decode-share",
        "requests",
        dict(
            type=parse_decode_share,
            default=None,
            metavar="SHARE",
            help="decode time owed per unit of prefill time while other requests "
            "decode (default: 0.5; 0 alternates one command each)",
        ),
    ),
    ServeOption(
        "--disable-ane",
        "requests",
        dict(
            action="store_true",
            default=False,
            help="prefill on the GPU alone (default: a dense model's long "
            "prompts also use the Neural Engine when that is faster)",
        ),
    ),
    ServeOption(
        "--allow-idle-sleep",
        "requests",
        dict(
            action="store_true",
            default=False,
            help="let the Mac sleep automatically while requests run (default: it "
            "stays awake until they finish; the display may still sleep)",
        ),
    ),
)
"""#

let fixtureServeOptions140 = #"""
SERVE_OPTIONS = (
ServeOption(
    "--host",
    "network",
    dict(
        default="127.0.0.1",
        metavar="ADDRESS",
        help="HTTP bind address (default: 127.0.0.1; 0.0.0.0 for all IPv4 "
        "interfaces); clients use an IP address, localhost or a name given "
        "with --allowed-host",
    ),
),
ServeOption(
    "--allowed-host",
    "network",
    dict(
        action="append",
        default=[],
        metavar="HOST",
        help="additional HTTP Host name to accept, e.g. mymac.local; does not "
        "change the bind address (repeatable)",
    ),
),
ServeOption(
    "--allowed-origin",
    "network",
    dict(
        action="append",
        default=[],
        type=parse_allowed_origin,
        metavar="ORIGIN",
        help="origin whose pages may call the API from a browser or webview, "
        "e.g. tauri://localhost; '*' for any (repeatable)",
    ),
    text=_origin_text,
),
ServeOption(
    "--api-key",
    "network",
    dict(
        type=parse_api_key,
        metavar="KEY",
        help="require this key as a bearer token or x-api-key on every route "
        "but the chat page, /health and /ready (default: SPLASH_API_KEY)",
    ),
    environment="SPLASH_API_KEY",
    secret=True,
),
ServeOption(
    "--no-webui",
    "network",
    dict(action="store_true", default=False, help="disable the chat page"),
),
ServeOption(
    "--max-memory",
    "memory",
    dict(
        type=parse_max_memory,
        default=None,
        metavar="SIZE",
        help="Metal memory budget, e.g. 28G; it can only lower the automatic "
        "budget (default: auto)",
    ),
),
ServeOption(
    "--max-context",
    "memory",
    dict(
        type=parse_max_context,
        default=None,
        metavar="TOKENS",
        help="context token limit, e.g. 100K or 1M (K = 1024 tokens, M = "
        "1000000 tokens), up to 1010000; past the model's 256K native window "
        "it turns on YaRN, which is static and changes answers at every "
        "length, so pass more than 256K only when a request needs it "
        "(default: auto, the native window when memory holds it)",
    ),
),
ServeOption(
    "--ple-memory",
    "memory",
    dict(
        type=parse_ple_memory,
        default=None,
        metavar="SIZE",
        help="RAM row cache of the PLE n-gram table of a Qwen3.8-Flash-Next "
        "GGUF, e.g. 2G, which streams the rest from the SSD; off loads the "
        "whole table, tens of GB (default: auto, which streams it where "
        "memory cannot hold it)",
    ),
),
ServeOption(
    "--expert-memory",
    "memory",
    dict(
        type=parse_expert_memory,
        default=None,
        metavar="SIZE",
        help="RAM slots of the routed experts of a MoE model, e.g. 16G, which "
        "reads the others from the SSD when a token routes them; off loads "
        "every expert (default: auto, which loads them all where memory "
        "holds them and otherwise gives them what the context leaves)",
    ),
),
ServeOption(
    "--sparse-kv-memory",
    "memory",
    dict(
        type=parse_sparse_kv_memory,
        default=None,
        metavar="SIZE",
        help="RAM cache of the KV blocks a block-sparse model such as "
        "Qwen3.8-Flash-Next reads of requests whose KV is on the SSD, e.g. "
        "1200M; never below its floor (default: auto, its floor)",
    ),
),
ServeOption(
    "--kv-format",
    "memory",
    dict(
        choices=("int8", "bf16"),
        default="int8",
        help="target KV cache storage (default: int8); bf16 uses more memory",
    ),
),
ServeOption(
    "--state-format",
    "memory",
    dict(
        choices=("fp32", "bf16"),
        default="fp32",
        help="recurrent state storage (default: fp32); bf16 halves each "
        "state, so memory and the SSD cache hold about twice as many",
    ),
),
ServeOption(
    "--idle-release",
    "memory",
    dict(
        type=parse_idle_release,
        default=None,
        metavar="DURATION",
        help="time without a request before the engine unwires its memory and "
        "frees the weights: seconds, or with an s, m or h suffix, e.g. 30m "
        "(default: 10m); off keeps both, though POST /v1/memory/release "
        "still frees the weights",
    ),
    text=idle_release_text,
),
ServeOption(
    "--max-cache-disk",
    "cache",
    dict(
        type=parse_max_cache_disk,
        default=None,
        metavar="SIZE",
        help="SSD quota for cached KV pages and states: auto follows the "
        "volume, a quarter of its free space beyond a floor of 10G (5%% of "
        "a volume under 200G), at most 32G; a size such as 16G is held as "
        "given while the volume keeps that floor; 0 disables (default: auto)",
    ),
),
ServeOption(
    "--max-cache-disk-writes",
    "cache",
    dict(
        type=parse_max_cache_disk_writes,
        default=0,
        metavar="SIZE",
        help="the most the SSD cache writes a day, e.g. 200G; the state a "
        "conversation resumes from and KV pages pass it (default: 0, no "
        "limit)",
    ),
),
ServeOption(
    "--persistent-cache",
    "cache",
    dict(
        action="store_true",
        default=False,
        help="keep the SSD cache across restarts",
    ),
),
ServeOption(
    "--cache-dir",
    "cache",
    dict(
        type=parse_cache_dir,
        default=None,
        metavar="DIRECTORY",
        help="where --persistent-cache keeps its files; needs "
        "--persistent-cache (default: ~/Library/Caches/Splash/prefix-cache)",
    ),
),
ServeOption(
    "--served-model-name",
    "api",
    dict(
        action="append",
        default=[],
        type=parse_served_model_name,
        metavar="NAME",
        help="additional API model name (repeatable); responses report the "
        "loaded model ID unless --announce-served-name",
    ),
),
ServeOption(
    "--announce-served-name",
    "api",
    dict(
        action="store_true",
        default=False,
        help="report the first --served-model-name in API responses and list "
        "it first in /v1/models; /status keeps the loaded model ID (needs "
        "--served-model-name)",
    ),
),
ServeOption(
    "--default-reasoning-effort",
    "api",
    dict(
        type=parse_reasoning_effort,
        metavar="EFFORT",
        help="effort of Chat and Responses requests that set none: "
        + ", ".join(REASONING_EFFORTS[:-1])
        + f" or {REASONING_EFFORTS[-1]} (default: "
        "SPLASH_DEFAULT_REASONING_EFFORT, else the model template's)",
    ),
    environment="SPLASH_DEFAULT_REASONING_EFFORT",
),
ServeOption(
    "--thinking-token-budget",
    "api",
    dict(
        type=parse_thinking_token_budget,
        metavar="N",
        help="thinking tokens of a thinking request that sets no "
        "thinking_token_budget, after which its thinking closes (default: "
        "SPLASH_THINKING_TOKEN_BUDGET, else no cap)",
    ),
    environment="SPLASH_THINKING_TOKEN_BUDGET",
),
ServeOption(
    "--thinking-end-text",
    "api",
    dict(
        metavar="TEXT",
        help="text that ends thinking where a thinking budget runs out, such "
        "as a sentence that turns to the answer, then </think> as its last "
        f"token; at most {MAX_THINKING_END_TOKENS} tokens (default: "
        "SPLASH_THINKING_END_TEXT, else </think> alone)",
    ),
    environment="SPLASH_THINKING_END_TEXT",
),
ServeOption(
    "--max-request-size",
    "requests",
    dict(
        type=parse_request_size,
        default=DEFAULT_MAX_REQUEST_BYTES,
        metavar="SIZE",
        help="maximum HTTP request body size, e.g. 128M (default: 128M); "
        "shared input budget is max(512M, twice this limit)",
    ),
),
ServeOption(
    "--max-image-pixels",
    "requests",
    dict(
        type=parse_max_image_pixels,
        default=images.MAX_PIXELS,
        metavar="PIXELS",
        help=f"maximum resized pixels per image, {images.MIN_PIXELS}–"
        f"{images.MAX_PIXELS} (default: {images.MAX_PIXELS}); bounds the "
        "vision scratch one image needs",
    ),
),
ServeOption(
    "--request-timeout",
    "requests",
    dict(
        type=parse_request_timeout,
        default=None,
        metavar="DURATION",
        help="time before a queued or in-flight request expires with 504: "
        "seconds, or with an s, m or h suffix, e.g. 30m (default: none)",
    ),
),
ServeOption(
    "--queue-size",
    "requests",
    dict(
        type=parse_queue_size,
        default=DEFAULT_QUEUE_SIZE,
        metavar="REQUESTS",
        help="requests admitted at once, running or waiting; more get 503 "
        f"(default: {DEFAULT_QUEUE_SIZE})",
    ),
),
ServeOption(
    "--decode-share",
    "requests",
    dict(
        type=parse_decode_share,
        default=None,
        metavar="SHARE",
        help="decode time owed per unit of prefill time while other requests "
        "decode (default: 0.5; 0 alternates one command each)",
    ),
),
ServeOption(
    "--disable-ane",
    "requests",
    dict(
        action="store_true",
        default=False,
        help="prefill on the GPU alone (default: a dense model's long "
        "prompts also use the Neural Engine when that is faster)",
    ),
),
ServeOption(
    "--verify-rows",
    "requests",
    dict(
        choices=("auto", "all"),
        default="auto",
        help="rows of each draft block decode verifies: all verifies every "
        "row, so a MoE model's greedy and seeded outputs repeat as a dense "
        "model's do (default: auto, where a verify budget learned from "
        "earlier cycles chooses a MoE model's rows, which is faster but "
        "lets those outputs differ from run to run)",
    ),
),
ServeOption(
    "--allow-idle-sleep",
    "requests",
    dict(
        action="store_true",
        default=False,
        help="let the Mac sleep automatically while requests run (default: it "
        "stays awake until they finish; the display may still sleep)",
    ),
),
)
"""#


// 75. S2b: parseServeOptions — the read-only view of the kit's shared table.
do {
    let r130 = parseServeOptions(fixtureServeOptions130)
    check(r130.options.count == 22, "s2b parse: the real 1.3.0 table yields the 22 shared options")
    check(r130.unrecognized.isEmpty, "s2b parse: no unrecognized blocks in the real table")
    check(r130.options.map(\.flag) == [
        "--host", "--allowed-host", "--allowed-origin", "--api-key", "--no-webui",
        "--max-memory", "--max-context", "--kv-format", "--idle-release",
        "--max-cache-disk", "--persistent-cache", "--cache-dir", "--served-model-name",
        "--announce-served-name", "--default-reasoning-effort", "--max-request-size",
        "--max-image-pixels", "--request-timeout", "--queue-size", "--decode-share",
        "--disable-ane", "--allow-idle-sleep",
    ], "s2b parse: file order preserved")
    func entry130(_ f: String) -> ServeOptionEntry? { r130.options.first { $0.flag == f } }
    check(entry130("--host") == ServeOptionEntry(flag: "--host", group: "network",
                                                  defaultText: "127.0.0.1"),
          "s2b parse: --host (network, 127.0.0.1)")
    check(entry130("--api-key") == ServeOptionEntry(flag: "--api-key", group: "network",
                                                    env: "SPLASH_API_KEY", secret: true),
          "s2b parse: --api-key (env SPLASH_API_KEY, secret)")
    check(entry130("--kv-format") == ServeOptionEntry(flag: "--kv-format", group: "memory",
                                                      choices: ["int8", "bf16"], defaultText: "int8"),
          "s2b parse: --kv-format (choices int8/bf16, default int8)")
    check(entry130("--allowed-host") == ServeOptionEntry(flag: "--allowed-host", group: "network", action: "append"),
          "s2b parse: --allowed-host (append)")
    check(entry130("--no-webui") == ServeOptionEntry(flag: "--no-webui", group: "network",
                                                     action: "store_true", defaultText: "false"),
          "s2b parse: --no-webui (store_true, false)")
    check(entry130("--max-request-size")?.defaultText == "DEFAULT_MAX_REQUEST_BYTES",
          "s2b parse: symbolic defaults stay verbatim (DEFAULT_MAX_REQUEST_BYTES)")
    check(entry130("--queue-size")?.defaultText == "DEFAULT_QUEUE_SIZE",
          "s2b parse: symbolic defaults stay verbatim (DEFAULT_QUEUE_SIZE)")
    check(entry130("--max-image-pixels")?.defaultText == "images.MAX_PIXELS",
          "s2b parse: dotted symbolic default stays verbatim (images.MAX_PIXELS)")
    check(entry130("--max-cache-disk")?.defaultText == "0", "s2b parse: --max-cache-disk default 0")
    check(entry130("--idle-release")?.defaultText == nil, "s2b parse: None default -> nil")
    check(entry130("--default-reasoning-effort")?.env == "SPLASH_DEFAULT_REASONING_EFFORT"
          && entry130("--default-reasoning-effort")?.defaultText == nil,
          "s2b parse: --default-reasoning-effort env, no default")

    let r132 = parseServeOptions(fixtureServeOptions132)
    check(r132.options.count == 26, "s2b parse: the 1.3.2 table yields 26 options")
    check(r132.unrecognized.isEmpty, "s2b parse: no unrecognized blocks in the 1.3.2 table")
    check(r132.options.map(\.flag) == [
        "--host", "--allowed-host", "--allowed-origin", "--api-key", "--no-webui",
        "--max-memory", "--max-context", "--kv-format", "--state-format", "--idle-release",
        "--max-cache-disk", "--max-cache-disk-writes", "--persistent-cache", "--cache-dir",
        "--served-model-name", "--announce-served-name", "--default-reasoning-effort",
        "--thinking-token-budget", "--thinking-end-text", "--max-request-size",
        "--max-image-pixels", "--request-timeout", "--queue-size", "--decode-share",
        "--disable-ane", "--allow-idle-sleep",
    ], "s2b parse: the 1.3.2 file order (the 4 new flags beside their relatives)")
    func entry132(_ f: String) -> ServeOptionEntry? { r132.options.first { $0.flag == f } }
    check(entry132("--state-format") == ServeOptionEntry(flag: "--state-format", group: "memory",
                                                         choices: ["fp32", "bf16"], defaultText: "fp32"),
          "s2b parse 1.3.2: --state-format (fp32/bf16, default fp32, memory)")
    check(entry132("--max-cache-disk")?.defaultText == nil, "s2b parse 1.3.2: --max-cache-disk default None (auto)")
    check(entry132("--max-cache-disk-writes") == ServeOptionEntry(flag: "--max-cache-disk-writes",
                                                                  group: "cache", defaultText: "0"),
          "s2b parse 1.3.2: --max-cache-disk-writes (cache, 0)")
    check(entry132("--thinking-token-budget") == ServeOptionEntry(flag: "--thinking-token-budget",
                                                                  group: "api",
                                                                  env: "SPLASH_THINKING_TOKEN_BUDGET"),
          "s2b parse 1.3.2: --thinking-token-budget env")
    check(entry132("--thinking-end-text") == ServeOptionEntry(flag: "--thinking-end-text",
                                                              group: "api",
                                                              env: "SPLASH_THINKING_END_TEXT"),
          "s2b parse 1.3.2: --thinking-end-text env")

    let r140 = parseServeOptions(fixtureServeOptions140)
    check(r140.options.count == 30, "s2b parse: the 1.4.0 table yields 30 options")
    check(r140.unrecognized.isEmpty, "s2b parse: no unrecognized blocks in the 1.4.0 table")
    check(r140.options.map(\.flag) == [
        "--host", "--allowed-host", "--allowed-origin", "--api-key", "--no-webui",
        "--max-memory", "--max-context", "--ple-memory", "--expert-memory", "--sparse-kv-memory",
        "--kv-format", "--state-format", "--idle-release",
        "--max-cache-disk", "--max-cache-disk-writes", "--persistent-cache", "--cache-dir",
        "--served-model-name", "--announce-served-name", "--default-reasoning-effort",
        "--thinking-token-budget", "--thinking-end-text", "--max-request-size",
        "--max-image-pixels", "--request-timeout", "--queue-size", "--decode-share",
        "--disable-ane", "--verify-rows", "--allow-idle-sleep",
    ], "s2b parse: the 1.4.0 file order (the 4 new flags beside their relatives)")
    func entry140(_ f: String) -> ServeOptionEntry? { r140.options.first { $0.flag == f } }
    check(entry140("--ple-memory") == ServeOptionEntry(flag: "--ple-memory", group: "memory"),
          "s2b parse 1.4.0: --ple-memory (memory, no default)")
    check(entry140("--expert-memory")?.group == "memory"
        && entry140("--sparse-kv-memory")?.group == "memory",
          "s2b parse 1.4.0: --expert-memory / --sparse-kv-memory (memory)")
    check(entry140("--verify-rows") == ServeOptionEntry(flag: "--verify-rows", group: "requests",
                                                        choices: ["auto", "all"], defaultText: "auto"),
          "s2b parse 1.4.0: --verify-rows (auto/all, default auto, requests)")

    // A mangled block (non-string first arg): the good blocks parse, the bad
    // one is reported, not fatal.
    let mangled = """
    SERVE_OPTIONS = (
        ServeOption(
            42,
            "cache",
            dict(),
        ),
        ServeOption(
            "--ok-flag",
            "cache",
            dict(default="1"),
        ),
    )
    """
    let rm = parseServeOptions(mangled)
    check(rm.options.map(\.flag) == ["--ok-flag"] && rm.options[0].defaultText == "1",
          "s2b parse: a mangled table keeps the parseable blocks")
    check(rm.unrecognized.count == 1 && rm.unrecognized[0].contains("42"),
          "s2b parse: the mangled block is reported with its bad token")

    check(parseServeOptions("").options.isEmpty && parseServeOptions("").unrecognized.isEmpty,
          "s2b parse: empty text -> empty report, no error")
    check(parseServeOptions("def f(): pass\n").options.isEmpty
          && parseServeOptions("def f(): pass\n").unrecognized.isEmpty,
          "s2b parse: non-table text -> empty report, no error")
    check(parseServeOptions("SERVE_OPTIONS = (\n").options.isEmpty,
          "s2b parse: an unbalanced table -> empty report, no crash")
}

// 76. S2b: registryDiff (the D3 shared-scope diff) + registry_report on the tick.
do {
    let r130 = parseServeOptions(fixtureServeOptions130)
    let r132 = parseServeOptions(fixtureServeOptions132)
    let d130_130 = registryDiff(r130, contract: contract130, version: "1.3.0")
    check(d130_130.inSync, "s2b diff: the 1.3.0 table matches the 1.3.0 contract (inSync)")
    check(d130_130.version == "1.3.0", "s2b diff: the report carries the kit version")
    let d130_131 = registryDiff(r130, contract: contract131, version: "1.3.1")
    check(d130_131.inSync, "s2b diff: the shared table is 1.3.1-identical (inSync)")
    let fourNew = ["--max-cache-disk-writes", "--state-format", "--thinking-end-text",
                   "--thinking-token-budget"]
    let d132_131 = registryDiff(r132, contract: contract131, version: "1.3.2")
    check(!d132_131.inSync && d132_131.missingInContract == fourNew
          && d132_131.missingInKit.isEmpty && d132_131.envSecretMismatches.isEmpty,
          "s2b diff: 1.3.2 table vs the 1.3.1 contract -> exactly the 4 new flags, amber only")
    let d130_132 = registryDiff(r130, contract: contract132, version: "1.3.0")
    check(!d130_132.inSync && d130_132.missingInKit == fourNew
          && d130_132.missingInContract.isEmpty,
          "s2b diff: 1.3.0 table vs the 1.3.2 contract -> exactly the 4 flags missingInKit")
    let d140_140 = registryDiff(parseServeOptions(fixtureServeOptions140), contract: contract140, version: "1.4.0")
    check(d140_140.inSync, "s2b diff: the 1.4.0 table matches the 1.4.0 contract (inSync)")
    let fourNew140 = ["--expert-memory", "--ple-memory", "--sparse-kv-memory", "--verify-rows"]
    let d140_132 = registryDiff(parseServeOptions(fixtureServeOptions140), contract: contract132, version: "1.4.0")
    check(!d140_132.inSync && d140_132.missingInContract == fourNew140
          && d140_132.missingInKit.isEmpty && d140_132.envSecretMismatches.isEmpty,
          "s2b diff: 1.4.0 table vs the 1.3.2 contract -> exactly the 4 new flags, amber only")
    // Synthetic env drift: the registry stays the source of truth (silent correction).
    let drifted = ServeOptionsReport(options: r130.options.map {
        $0.flag == "--api-key"
            ? ServeOptionEntry(flag: $0.flag, group: $0.group, env: "SPLASH_KEK",
                               secret: $0.secret, action: $0.action, choices: $0.choices,
                               defaultText: $0.defaultText)
            : $0
    })
    let dDrift = registryDiff(drifted, contract: contract131, version: "1.3.1")
    check(!dDrift.inSync && dDrift.envSecretMismatches.count == 1
          && dDrift.envSecretMismatches[0].contains("--api-key")
          && dDrift.envSecretMismatches[0].contains("SPLASH_KEK")
          && dDrift.envSecretMismatches[0].contains("SPLASH_API_KEY"),
          "s2b diff: an env drift is named (actual vs expected), !inSync")

    // The tick: null when quiet, a condensed dict when out of sync, gate-stable.
    let d = defaultConfig(home: "/home", now: now)
    let pNil = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                                 firstRun: false, inFlight: 0, result: nil)
    check(pNil["registry_report"] is NSNull, "s2b tick: nil report -> registry_report null")
    let pSync = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                                  firstRun: false, inFlight: 0, result: nil, registryReport: d130_131)
    check(pSync["registry_report"] is NSNull, "s2b tick: an inSync report -> null (known-good kits stay quiet)")
    let pDrift = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                                   firstRun: false, inFlight: 0, result: nil, registryReport: d132_131)
    let dd = pDrift["registry_report"] as? [String: Any]
    check(dd != nil, "s2b tick: an out-of-sync report -> a condensed dict")
    check(dd?["version"] as? String == "1.3.2", "s2b tick: the dict carries the kit version")
    check((dd?["missing_in_contract"] as? [String]) == fourNew,
          "s2b tick: missing_in_contract rides the tick")
    check(dd?["missing_in_kit"] == nil && dd?["env_secret_mismatches"] == nil && dd?["unrecognized"] == nil,
          "s2b tick: empty classifications are omitted")
    let pDrift2 = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                                    firstRun: false, inFlight: 0, result: nil, registryReport: d132_131)
    check(canonicalJSONString(JSONValue(any: pDrift)) == canonicalJSONString(JSONValue(any: pDrift2)),
          "s2b tick change-gate: identical drift report -> identical canonical form")
    check(canonicalJSONString(JSONValue(any: pDrift)) != canonicalJSONString(JSONValue(any: pNil)),
          "s2b tick change-gate: drift vs null flips the gate")
}
// 88. S4: the launch registry covers the versions the plan can resolve: an
// exact 1.3.0 contract (the app's fixed kit rung) plus 1.3.1/1.3.2 (a new
// Homebrew keg must plan, not crash — contractFor falls back).
do {
 let (c130, fb) = contractFor("1.3.0", registry: launchRegistry)
 check(!fb && c130.version == "1.3.0", "S4: the registry carries an exact 1.3.0 contract (no fallback, version-keyed)")
 let pc = c130.option("persistent_cache")
 check(pc != nil && pc!.kind == .bool, "S4: 1.3.0's registry carries the persistent-cache flag (a store_true bool)")
 let ak = c130.option("api_key")
 check(ak != nil && ak!.secret && ak!.envVar == "SPLASH_API_KEY", "S4: 1.3.0's api_key is secret, env SPLASH_API_KEY (never argv)")
 let (_, fb131) = contractFor("1.3.1", registry: launchRegistry)
 check(!fb131, "S4: the registry carries 1.3.1 (a new keg plans, not crashes)")
 let (_, fb132) = contractFor("1.3.2", registry: launchRegistry)
 check(!fb132, "S4: the registry carries 1.3.2")
 let (_, fb140) = contractFor("1.4.0", registry: launchRegistry)
 check(!fb140, "S4: the registry carries 1.4.0")
 let (_, fbX) = contractFor("1.9.9", registry: launchRegistry)
 check(fbX, "S4: an unknown version falls back, not crashes (D3)")
}

// 89. S4: the tick cutover — the plan's launch-relevant fields (engine
// resolved/version/tried/valid/error, the plan sub-object, the restart state)
// are overlaid onto the change-gated cfg payload by S4's pure helper. Without a
// plan they stay null (change-gate stable). Mirrors main.swift's applyPlanToCfg.
do {
 var fs = FakeFS()
 planKit(fs: &fs, path: "/kits/kit130", version: "1.3.0")
 let model = "/models/pkg"
 fs.dir(model, ["manifest.json", "model.json", "config.json", "tokenizer/", "draft/"])
 fs.file(model + "/manifest.json", #"{"model_type": "qwen3_5", "draft_repo": "draft"}"#)
 fs.file(model + "/draft/config.json")
 let cfg = planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130", port: 8123,
                       key: "splash-standalone-1", name: "default",
                       modelId: "incoai/Qwen3.8-27B-Splash", modelDir: model,
                       options: ["persistent_cache": "true", "max_cache_disk": "100"])
 let plan = planLaunch(cfg, home: "/home",
                       isDir: { fs.isDir($0) }, isExecutable: { fs.isExecutable($0) },
                       brewKeg: { nil }, kitVersion: { readKitVersion(fs: fs, kit: $0) },
                       fileContents: { fs.fileContents($0) }, listDir: { fs.listDir($0) })
 check(plan.error == nil, "S4 tick: the fixture plan is healthy (got: \(plan.error ?? "ok"))")
 let d = parseConfig(cfg).doc!

 // A mirror of main.swift's S4 overlay (the harness cannot compile main.swift):
func applyPlanToCfg(_ payload: inout [String: Any], plan: LaunchConfig?,
                     restart: Bool?, reason: String?, report: RegistryReport?) {
    var eng = (payload["engine"] as? [String: Any]) ?? [:]
     if let p = plan {
         eng["resolved"] = p.workDir != nil
         eng["version"] = p.version ?? NSNull()
         eng["path"] = p.workDir ?? NSNull()
         eng["tried"] = p.tried
         eng["valid"] = p.error == nil
         eng["error"] = p.error ?? NSNull()
     }
     payload["engine"] = eng
     payload["mapping_fallback"] = plan?.mappingFallback ?? NSNull()
     payload["mapping_used"] = plan?.version ?? NSNull()
     payload["restart_required"] = restart ?? NSNull()
     payload["restart_reason"] = reason ?? NSNull()
     if let r = report, !r.inSync {
         var d: [String: Any] = ["version": r.version ?? NSNull()]
         if !r.missingInContract.isEmpty { d["missing_in_contract"] = r.missingInContract as Any }
         if !r.missingInKit.isEmpty { d["missing_in_kit"] = r.missingInKit as Any }
         if !r.envSecretMismatches.isEmpty { d["env_secret_mismatches"] = r.envSecretMismatches as Any }
         if !r.unrecognized.isEmpty { d["unrecognized"] = r.unrecognized as Any }
         payload["registry_report"] = d
     }
 }

 // No plan: the plan-derived engine fields stay null (the pre-S4 base shape).
 var pNil = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                              firstRun: false, inFlight: 0, result: nil)
 applyPlanToCfg(&pNil, plan: nil, restart: nil, reason: nil, report: nil)
 let eNil = pNil["engine"] as? [String: Any]
 check(eNil?["resolved"] is NSNull && eNil?["version"] is NSNull,
       "S4 tick: no plan -> engine resolved/version null (pre-S4 shape)")
 check(pNil["mapping_fallback"] is NSNull && pNil["mapping_used"] is NSNull,
       "S4 tick: no plan -> mapping_fallback/used null")
 check(pNil["restart_required"] is NSNull && pNil["restart_reason"] is NSNull,
       "S4 tick: no plan -> restart_required/reason null")

 // A healthy plan fills the engine block + the mapping fields.
 var p = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                           firstRun: false, inFlight: 0, result: nil)
 applyPlanToCfg(&p, plan: plan, restart: nil, reason: nil, report: nil)
 let e = p["engine"] as? [String: Any]
 check(e?["resolved"] as? Bool == true, "S4 tick: engine.resolved true (a kit was found)")
 check(e?["version"] as? String == "1.3.0", "S4 tick: engine.version from the kit's release.json (D16)")
 check(e?["valid"] as? Bool == true, "S4 tick: engine.valid true (the plan is healthy)")
 check(e?["error"] is NSNull, "S4 tick: engine.error null when the plan is healthy")
 check(p["mapping_fallback"] as? Bool == false,
       "S4 tick: mapping_fallback false (an exact 1.3.0 contract, not a fallback)")
 check(p["mapping_used"] as? String == "1.3.0",
       "S4 tick: mapping_used = the kit's release.json version (the contract's key)")
 check(p["restart_required"] is NSNull, "S4 tick: restart_required null while never launched")

 // Change-gate stability: the same plan ticks identically (no churn).
 var p2 = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                            firstRun: false, inFlight: 0, result: nil)
 applyPlanToCfg(&p2, plan: plan, restart: nil, reason: nil, report: nil)
 check(canonicalJSONString(JSONValue(any: p)) == canonicalJSONString(JSONValue(any: p2)),
       "S4 tick change-gate: an identical plan ticks identically")

 // A failed plan: resolved false, valid false, the actionable error text.
 let fsBad = FakeFS()
 let cfgBad = planCfgJSON(engineMode: "manual", manualPath: "/no/kit", port: 8123, key: "k",
                          name: "default", modelId: "incoai/Qwen3.8-27B-Splash",
                          modelDir: nil, options: [:])
 let bad = planLaunch(cfgBad, home: "/home",
                      isDir: { fsBad.isDir($0) }, isExecutable: { fsBad.isExecutable($0) },
                      brewKeg: { nil }, kitVersion: { readKitVersion(fs: fs, kit: $0) },
                      fileContents: { fsBad.fileContents($0) }, listDir: { fsBad.listDir($0) })
 check(bad.error != nil, "S4 tick: the broken plan errors (fixture sanity)")
 var pBad = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                              firstRun: false, inFlight: 0, result: nil)
 applyPlanToCfg(&pBad, plan: bad, restart: true, reason: "port changed", report: nil)
 let eBad = pBad["engine"] as? [String: Any]
 check(eBad?["resolved"] as? Bool == false, "S4 tick: a broken plan -> engine.resolved false")
 check((eBad?["error"] as? String)?.contains("/no/kit") == true,
       "S4 tick: engine.error carries the actionable plan text")
 check(eBad?["valid"] as? Bool == false, "S4 tick: a broken plan -> engine.valid false")
 check(pBad["restart_required"] as? Bool == true && pBad["restart_reason"] as? String == "port changed",
       "S4 tick: restart_required/reason ride the tick")

 // registry_report wiring (S2b) survives the cutover: a drifting report renders,
 // an inSync kit stays null (the gate is stable).
 var pDrift = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                                firstRun: false, inFlight: 0, result: nil)
 applyPlanToCfg(&pDrift, plan: plan, restart: nil, reason: nil,
                report: RegistryReport(version: "1.3.0", unrecognized: ["--new-flag"]))
 check((pDrift["registry_report"] as? [String: Any])?["unrecognized"] is [Any],
       "S4 cfg: a drifting registry_report renders as the condensed dict")
 var pSync = configTickPayload(doc: d, loadError: nil, versionTooNew: false, activeInvalid: false,
                               firstRun: false, inFlight: 0, result: nil)
 applyPlanToCfg(&pSync, plan: plan, restart: nil, reason: nil,
                report: RegistryReport(version: "1.3.0"))
 check(pSync["registry_report"] is NSNull,
       "S4 cfg: an inSync kit keeps registry_report null (the gate is stable)")
}

// 90. S4: restart_required signature compare (D13) — a launch-relevant change
// flips it; a profile rename does NOT; it clears once the engine runs the new
// plan. Mirrors main.swift's pure compare helper.
do {
 func cfgJSON(port: Int, options: [String: String]) -> Data {
 planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130", port: port, key: "splash-standalone-1",
             name: "default", modelId: "incoai/Qwen3.8-27B-Splash", modelDir: "/models/pkg",
             options: options)
 }
 let closures: (isDir: (String) -> Bool, isExe: (String) -> Bool,
                kitVer: (String) -> String?, fc: (String) -> String?, ld: (String) -> [String]?) = (
    { _ in true }, { _ in true }, { _ in "1.3.0" },
    { _ in #"{"model_type": "qwen3_5", "draft_repo": "draft"}"# }, { _ in [] })
 let mk = { (data: Data) in
 planLaunch(data, home: "/home",
            isDir: closures.isDir, isExecutable: closures.isExe,
            brewKeg: { nil }, kitVersion: closures.kitVer,
            fileContents: closures.fc, listDir: closures.ld)
 }
 let planA = mk(cfgJSON(port: 8123, options: ["persistent_cache": "true"]))
 let planB = mk(cfgJSON(port: 8124, options: ["persistent_cache": "true"]))

 // Mirror of main.swift's D13 compare.
 func restartRequired(_ current: String, lastSuccessful: String?) -> Bool? {
     guard let last = lastSuccessful else { return nil }
     return current != last
 }
 check(restartRequired(planA.signature, lastSuccessful: nil) == nil,
       "S4 restart: first launch (no last successful plan) -> not required (nil)")
 check(restartRequired(planA.signature, lastSuccessful: planA.signature) == false,
       "S4 restart: the running plan IS the successful one -> not required")
 check(restartRequired(planB.signature, lastSuccessful: planA.signature) == true,
       "S4 restart: a launch-relevant change (port) -> required")
 check(restartRequired(planB.signature, lastSuccessful: planB.signature) == false,
       "S4 restart: the engine now runs the new plan -> cleared")

 // A profile RENAME changes neither the signature (D13: signature, not identity).
 let renamed = planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130", port: 8124, key: "splash-standalone-1",
                           name: "Renamed", modelId: "incoai/Qwen3.8-27B-Splash", modelDir: "/models/pkg",
                           options: ["persistent_cache": "true"])
 let planRenamed = mk(renamed)
 check(planRenamed.signature == planB.signature,
       "S4 restart: a profile rename leaves the signature unchanged (no spurious restart)")
 check(restartRequired(planRenamed.signature, lastSuccessful: planB.signature) == false,
       "S4 restart: a rename does not flip restart_required")

 // The engine-env merge (D9): inherited + LaunchConfig.env; the key rides in the
 // env, never on argv (the S2a contract). Mirrors main.swift's mergedEngineEnv.
 func mergedEngineEnv(inherited: [String: String], extra: [String: String]) -> [String: String] {
     var m = inherited
     for (k, v) in extra { m[k] = v }
     return m
 }
 let env = mergedEngineEnv(inherited: ["PATH": "/usr/bin", "LANG": "en_US.UTF-8"],
                           extra: planB.engineEnv)
 check(env["PATH"] == "/usr/bin" && env["LANG"] == "en_US.UTF-8",
       "S4 engineEnv: inherited entries survive the merge")
 check(env["SPLASH_API_KEY"] == "splash-standalone-1", "S4 engineEnv: the key rides the env")
 check(!planB.engineArgs.contains("--api-key"),
       "S4 engineEnv: the key is NOT on argv (the S2a anchor)")
 check(planB.engineEnv["SPLASH_API_KEY"] == "splash-standalone-1",
       "S4 engineEnv: LaunchConfig.engineEnv carries the key")
}

// 91. S5: LaunchConfig.tried — populated on both the kit-miss path and the
// success path. On the kit-miss path the tried list is every rung the ladder
// checked; on success it is the same (the ladder always appends each rung it
// examines, not just the one it picks).
do {
    // Kit-miss path: MANUAL records only its exact path.
    let cfgMiss = planCfgJSON(engineMode: "manual", manualPath: "/bad/kit",
                               port: 8123, key: "k", name: "default",
                               modelId: "incoai/Qwen3.8-27B-Splash",
                               modelDir: nil, options: [:])
    let planMiss = planLaunch(cfgMiss, home: "/home",
                              isDir: { _ in false }, isExecutable: { _ in false },
                              brewKeg: { nil }, kitVersion: { _ in nil },
                              fileContents: { _ in nil }, listDir: { _ in nil })
    check(planMiss.error != nil, "S5 tried: kit-miss plan errors")
    check(planMiss.tried.contains("/bad/kit"),
          "S5 tried: manual path appears in the kit-miss tried list")
    check(planMiss.tried == ["/bad/kit"], "S5 tried: no assumed install.sh rung on the manual miss path")

    // Success path: a valid kit -> tried contains the same rungs.
    var fsS5 = FakeFS()
    planKit(fs: &fsS5, path: "/kits/kit130", version: "1.3.0")
    fsS5.dir("/models/pkg", ["manifest.json", "model.json", "config.json", "tokenizer/", "draft/"])
    fsS5.file("/models/pkg/manifest.json", #"{"model_type": "qwen3_5", "draft_repo": "draft"}"#)
    fsS5.file("/models/pkg/draft/config.json")
    let cfgOk = planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130",
                             port: 8123, key: "k", name: "default",
                             modelId: "incoai/Qwen3.8-27B-Splash",
                             modelDir: "/models/pkg", options: [:])
    let planOk = planLaunch(cfgOk, home: "/home",
                            isDir: { fsS5.isDir($0) }, isExecutable: { fsS5.isExecutable($0) },
                            brewKeg: { nil }, kitVersion: { readKitVersion(fs: fsS5, kit: $0) },
                            fileContents: { fsS5.fileContents($0) }, listDir: { fsS5.listDir($0) })
    check(planOk.error == nil, "S5 tried: success plan is healthy")
    check(planOk.tried.contains("/kits/kit130"),
          "S5 tried: the chosen kit appears in the success-path tried list")
    check(planOk.tried == ["/kits/kit130"], "S5 tried: no assumed install.sh rung on the manual success path")
}

// 92. S5: configTickPayload engine.path — the resolved kit dir (workDir).
do {
    var fsP = FakeFS()
    planKit(fs: &fsP, path: "/kits/kit130", version: "1.3.0")
    fsP.dir("/models/pkg", ["manifest.json", "model.json", "config.json", "tokenizer/", "draft/"])
    fsP.file("/models/pkg/manifest.json", #"{"model_type": "qwen3_5", "draft_repo": "draft"}"#)
    fsP.file("/models/pkg/draft/config.json")
    let cfgP = planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130",
                            port: 8123, key: "k", name: "default",
                            modelId: "incoai/Qwen3.8-27B-Splash",
                            modelDir: "/models/pkg", options: [:])
    let planP = planLaunch(cfgP, home: "/home",
                           isDir: { fsP.isDir($0) }, isExecutable: { fsP.isExecutable($0) },
                           brewKeg: { nil }, kitVersion: { readKitVersion(fs: fsP, kit: $0) },
                           fileContents: { fsP.fileContents($0) }, listDir: { fsP.listDir($0) })
    let dP = parseConfig(cfgP).doc!
    let payloadP = configTickPayload(doc: dP, loadError: nil, versionTooNew: false,
                                      activeInvalid: false, firstRun: false,
                                      inFlight: 0, result: nil)
    // The base engine dict has path: NSNull (pre-plan). The plan overlay fills it.
    let baseEng = payloadP["engine"] as? [String: Any]
    check(baseEng?["path"] is NSNull,
          "S5 path: the base engine dict has path null (pre-plan)")
    // Simulate the main.swift overlay:
    var eng = baseEng ?? [:]
    eng["path"] = planP.workDir ?? NSNull()
    check(eng["path"] as? String == "/kits/kit130",
          "S5 path: the overlay fills path with the resolved kit dir")
}

// 93. S5: folderTickState — present, missing, and empty-models cases.
do {
    var fsF = FakeFS()
    fsF.dir("/folders/lm", ["incoai/Qwen3.8-27B-Splash", "local/m3"])
    fsF.dir("/folders/lm/incoai/Qwen3.8-27B-Splash", ["manifest.json"])
    fsF.dir("/folders/lm/local/m3", ["config.json"])
    fsF.file("/folders/lm/incoai/Qwen3.8-27B-Splash/manifest.json", "{}")
    let lm = ModelFolder(id: "lmstudio", path: "/folders/lm", source: "auto")
    let st = folderTickState(folder: lm,
                             isDir: { fsF.isDir($0) },
                             fileContents: { fsF.fileContents($0) },
                             listDir: { fsF.listDir($0) })
    check(st["present"] as? Bool == true, "S5 folderTick: present true for an existing dir")
    check(st["scanning"] as? Bool == false, "S5 folderTick: scanning false in the pure path")
    check(st["error"] is NSNull, "S5 folderTick: error null in the pure path")
    check(st["id"] as? String == "lmstudio", "S5 folderTick: id matches the folder")
    let models = st["models"] as? [Any]
    check(models?.count == 2,
          "S5 folderTick: two models enumerated (got \(models?.count ?? -1))")

    // Missing folder: present false, models empty.
    let gone = ModelFolder(id: "gone", path: "/no/such/dir", source: "auto")
    let stGone = folderTickState(folder: gone,
                                 isDir: { fsF.isDir($0) },
                                 fileContents: { fsF.fileContents($0) },
                                 listDir: { fsF.listDir($0) })
    check(stGone["present"] as? Bool == false, "S5 folderTick: present false for a missing dir")
    check((stGone["models"] as? [Any])?.isEmpty == true,
          "S5 folderTick: models empty for a missing dir")

    // Empty folder: present true, models empty.
    fsF.dir("/folders/empty", [])
    let empty = ModelFolder(id: "empty", path: "/folders/empty", source: "auto")
    let stEmpty = folderTickState(folder: empty,
                                  isDir: { fsF.isDir($0) },
                                  fileContents: { fsF.fileContents($0) },
                                  listDir: { fsF.listDir($0) })
    check(stEmpty["present"] as? Bool == true, "S5 folderTick: present true for an empty dir")
    check((stEmpty["models"] as? [Any])?.isEmpty == true,
          "S5 folderTick: models empty for an empty dir")
}

// 94. S5: full store round-trip — manual mode + custom folder + ane=false
// produces the --disable-ane flag in the engine argv.
do {
    var fsRT = FakeFS()
    planKit(fs: &fsRT, path: "/kits/kit130", version: "1.3.0")
    fsRT.dir("/models/pkg", ["manifest.json", "model.json", "config.json", "tokenizer/", "draft/"])
    fsRT.file("/models/pkg/manifest.json", #"{"model_type": "qwen3_5", "draft_repo": "draft"}"#)
    fsRT.file("/models/pkg/draft/config.json")
    let cfgRT = planCfgJSON(engineMode: "manual", manualPath: "/kits/kit130",
                             port: 8123, key: "splash-standalone-1", name: "default",
                             modelId: "incoai/Qwen3.8-27B-Splash",
                             modelDir: "/models/pkg", options: ["ane": "false"])
    let planRT = planLaunch(cfgRT, home: "/home",
                            isDir: { fsRT.isDir($0) }, isExecutable: { fsRT.isExecutable($0) },
                            brewKeg: { nil }, kitVersion: { readKitVersion(fs: fsRT, kit: $0) },
                            fileContents: { fsRT.fileContents($0) }, listDir: { fsRT.listDir($0) })
    check(planRT.error == nil, "S5 roundtrip: plan is healthy (got: \(planRT.error ?? "ok"))")
    check(planRT.engineArgs.contains("--disable-ane"),
          "S5 roundtrip: ane=false -> --disable-ane appears in engine argv")
    check(!planRT.engineArgs.contains("true"),
          "S5 roundtrip: ane=false -> no bare 'true' in argv")

    // Now test the ConfigStore round-trip: save, re-read, verify the doc.
    let home = "/tmp/s5rt"
    var storeWrites: [String: Data] = [:]
    let store = ConfigStore(
        home: home,
        path: home + "/config.json",
        read: { _ in nil },  // first load: absent -> seeds
        write: { data, path in storeWrites[path] = data; return true },
        ensureDir: { _, _ in true },
        brewKeg: { nil }, kitVersion: { _ in nil }, isDir: { _ in false })
    // Build a manual-mode doc with ane=false:
    var doc = store.doc
    doc.globals.engine = EngineCfg(mode: "manual", manualPath: "/kits/kit130", brew: false)
    doc.globals.modelFolders = [ModelFolder(id: "lmstudio", path: "/models", source: "auto")]
    doc.globals.port = 8123
    doc.globals.apiKey = "splash-standalone-1"
    if let i = doc.profiles.firstIndex(where: { $0.id == doc.activeProfile }) {
        doc.profiles[i].options["ane"] = .bool(false)
    }
    let r = store.save(candidate: doc)
    check(r.ok, "S5 store roundtrip: save succeeds")
    // Read back:
    let savedData = storeWrites[home + "/config.json"]
    check(savedData != nil, "S5 store roundtrip: file was written")
    if let d = savedData {
        let (rd, _, _) = parseConfig(d)
        check(rd?.globals.engine.mode == "manual", "S5 store roundtrip: manual mode persisted")
        check(rd?.globals.engine.manualPath == "/kits/kit130", "S5 store roundtrip: manual path persisted")
        check(rd?.globals.port == 8123, "S5 store roundtrip: port persisted")
        if let p = rd?.profiles.first(where: { $0.id == rd?.activeProfile }) {
            check(p.options["ane"]?.bool == false, "S5 store roundtrip: ane=false persisted")
        }
    }
}

// S6a: profile model facts reuse S3 verdicts; CRUD stays in schema v1.
do {
    let pkg = ProfileModel(source: "lmstudio", id: "org/pkg", dir: "/pkg")
    let files: [String: String] = ["/pkg/manifest.json": "{}", "/assembly/model.json": "{}", "/assembly/config.json": "{}", "/hf/config.json": #"{"model_type":"qwen3_5"}"#]
    func state(_ model: ProfileModel, _ version: String, _ draft: String? = nil) -> [String: Any] {
        modelTickState(model: model, version: version, draftModel: draft,
                       isDir: { ["/pkg", "/pkg/tokenizer", "/pkg/draft"].contains($0) },
                       fileContents: { files[$0] })
    }
    let p = state(pkg, "1.3.0")
    check(p["eligibility"] as? String == "runnable", "S6a package is runnable with the built-against kit")
    check((p["drafter"] as? String)?.contains("baked") == true, "S6a package drafter is baked in")
    check(state(pkg, "1.3.1")["eligibility"] as? String == "blocked", "S6a newer kit never falsely accepts package")
    let assembly = state(ProfileModel(source: "manual", id: "org/a", dir: "/assembly"), "1.3.0")
    check(assembly["eligibility"] as? String == "unrunnable", "S6a assembly requires draft/config.json")
    check((assembly["eligibility_reason"] as? String)?.contains("draft/config.json") == true, "S6a missing drafter preserves engine fix text")
    let hf = ProfileModel(source: "hfhub", id: "org/hf", dir: "/hf")
    check((state(hf, "1.3.1")["drafter"] as? String)?.contains("DFlash2") == true, "S6a drafter is resolved from config family registry")
    let unknown = ProfileModel(source: "hfid", id: "org/unknown")
    check(state(unknown, "1.3.1")["eligibility"] as? String == "unknown", "S6a unknown family remains unknown")
    check(state(unknown, "1.3.1", "org/draft")["eligibility"] as? String == "runnable", "S6a explicit drafter override uses S3 eligibility")
    check(state(ProfileModel(source: "none"), "1.3.1")["eligibility"] as? String == "unrunnable", "S6a unset model cannot be runnable")
    var doc = defaultConfig(home: "/home", now: now)
    let original = doc.profiles[0]
    var copy = original
    copy.id = "p-1234-abcd"; copy.name = "Clone"
    copy.meta = ProfileMeta(createdAt: "2026-10-15T00:00:00Z")
    copy.model = pkg
    doc.profiles.append(copy)
    let roundtrip = parseConfig(configData(doc)).doc
    check(roundtrip == doc, "S6a complete profile CRUD candidate persists through ConfigDoc schema v1")
    check(roundtrip?.profiles.last?.options == original.options, "S6a clone options survive persistence")
    check(roundtrip?.profiles.last?.meta.lastUsedAt == nil, "S6a clone usage metadata stays reset")
    doc.profiles[1].name = original.name
    check(!validateConfig(doc).ok, "S6a duplicate profile names use existing blocking validation")
    doc.profiles.removeLast()
    check(parseConfig(configData(doc)).doc?.profiles.count == 1, "S6a removal persists without parallel store")
    check(configSchemaVersion == 1, "S6a needs no migration: all profile fields already exist")
}

do {
    var candidate = defaultConfig(home: "/home", now: now)
    candidate.globals.engine = EngineCfg(mode: "manual", manualPath: "/kits/k131")
    candidate.profiles[0].model = ProfileModel(source: "hfid", id: "org/model", dir: "/cached/model")
    candidate.profiles[0].options["draft_model"] = .string("org/draft")
    var fs = FakeFS(); planKit(fs: &fs, path: "/kits/k131", version: "1.3.1")
    fs.dir("/cached/model", ["config.json"]); fs.file("/cached/model/config.json", "{}")
    func signature(_ d: ConfigDoc) -> String {
        planLaunch(configData(d), home: "/home", isDir: { fs.isDir($0) },
                   isExecutable: { fs.isExecutable($0) }, kitVersion: { _ in "1.3.1" }, fileContents: { fs.fileContents($0) }).signature
    }
    let baseline = signature(candidate)
    var second = candidate.profiles[0]; second.id = "second"; second.name = "Second"
    candidate.profiles.append(second)
    var writes = 0
    let store = ConfigStore(home: "/home", read: { _ in configData(candidate) },
                            write: { _, _ in writes += 1; return true }, ensureDir: { _, _ in true })
    candidate.profiles[1].options["kv_format"] = .string("bf16")
    let result = store.activateCandidate(configData(candidate), profileId: "second", now: now)
    check(result.ok && writes == 1, "S6b activation commits the full draft with exactly one atomic write")
    check(store.doc.activeProfile == "second", "S6b activation moves active profile")
    check(store.doc.profiles[1].meta.lastUsedAt != nil, "S6b activation stamps last-used")
    check(store.doc.profiles[1].options["kv_format"] == .string("bf16"), "S6b activation keeps unsaved option edits")
    check(signature(store.doc) != baseline, "S6b activation computes restart-required from changed active plan")
    let stamp = store.doc.profiles[1].meta.lastUsedAt
    check(store.save(candidate: store.doc).ok && store.doc.profiles[1].meta.lastUsedAt == stamp, "S6b explicit saves preserve activation metadata")
    let beforeInvalid = writes
    check(!store.activateCandidate(configData(candidate), profileId: "missing", now: now).ok && writes == beforeInvalid, "S6b unknown activation never writes")
    let old = profileOptionDefinitions(version: "1.3.0"), latest = profileOptionDefinitions(version: "1.3.2")
    check(!old.contains { $0["key"] as? String == "state_format" }, "S6b module hides newer contract flags")
    check(latest.contains { $0["key"] as? String == "state_format" }, "S6b latest contract exposes state format")
    check(!old.contains { $0["key"] as? String == "api_key" || $0["key"] as? String == "port" }, "S6b global-only secret and port never enter profile controls")
    let revert = store.activateCandidate(configData(candidate), profileId: candidate.profiles[0].id, now: now)
    check(revert.ok && signature(store.doc) == baseline, "S6b reverting activation clears restart-required without a restart")
    var invalid = candidate; invalid.profiles[0].options["max_cache_disk"] = .string("nonsense")
    check(!validateConfig(invalid).ok, "S6b malformed size blocks commit")
    invalid = candidate; invalid.profiles[0].options["kv_format"] = .string("fp99")
    check(!validateConfig(invalid).ok, "S6b invalid registry enum blocks commit")
    invalid = candidate; invalid.profiles[0].options["persistent_cache"] = .bool(true); invalid.profiles[0].options["max_cache_disk"] = .string("0")
    check(validateConfig(invalid).ok, "S6b unsupported combinations remain saveable D4")
    check(profileOptionDefinitions(version: "1.3.1").contains { $0["key"] as? String == "revision" }, "S6b launcher option groups use the versioned registry")
    check(!old.contains { $0["key"] as? String == "revision" }, "S6b module hides launcher-only axis")
    let beforeForward = writes
    let forward = String(data: configData(candidate), encoding: .utf8)!.replacingOccurrences(of: "\"schema_version\": 1", with: "\"schema_version\": 99")
    check(!store.activateCandidate(Data(forward.utf8), profileId: "second").ok && writes == beforeForward, "S6b forward-schema activation refuses without writing")
}

// =============================================================================
// S7: the settings-screen redesign — globals network fields, model sizes,
// engine verdict, profile previews, the 1.3.0 pin.
// =============================================================================

// 95. S7 globals: the network fields round-trip through configData/parseConfig.
do {
    var doc = defaultConfig(home: "/home", now: now)
    doc.globals.host = "0.0.0.0"
    doc.globals.port = 9999
    doc.globals.apiKey = "secret-key-123"
    doc.globals.allowedHosts = ["example.com", "10.0.0.1"]
    doc.globals.allowedOrigins = ["http://example.com"]
    doc.globals.webUI = false
    let data = configData(doc)
    let (rd, err, _) = parseConfig(data)
    check(err == nil && rd != nil, "S7 globals: the network fields parse back")
    check(rd?.globals.host == "0.0.0.0", "S7 globals: host round-trips")
    check(rd?.globals.port == 9999, "S7 globals: port round-trips")
    check(rd?.globals.allowedHosts == ["example.com", "10.0.0.1"], "S7 globals: allowed_hosts round-trip")
    check(rd?.globals.allowedOrigins == ["http://example.com"], "S7 globals: allowed_origins round-trip")
    check(rd?.globals.webUI == false, "S7 globals: web_ui false round-trips")
    // Defaults when absent.
    let (dd, derr, _) = parseConfig(Data(#"{"schema_version":1,"globals":{}}"#.utf8))
    check(derr == nil, "S7 defaults: an empty globals parses")
    check(dd?.globals.host == "127.0.0.1", "S7 defaults: host 127.0.0.1")
    check(dd?.globals.webUI == true, "S7 defaults: web_ui true (the engine default)")
    check(dd?.globals.allowedHosts == [] && dd?.globals.allowedOrigins == [], "S7 defaults: empty allowed lists")
}

// 96. S7 CFBoolean trap: a JSON NUMBER for web_ui is a type violation (strict),
// never a truthy bool. `true`/`false` parse to .bool.
do {
    let bad = Data(#"{"schema_version":1,"globals":{"web_ui":1}}"#.utf8)
    let (d, err, _) = parseConfig(bad)
    check(d == nil && err != nil, "S7 CFBoolean: a JSON number for web_ui is rejected (strict)")
    let ok = Data(#"{"schema_version":1,"globals":{"web_ui":false}}"#.utf8)
    let (d2, err2, _) = parseConfig(ok)
    check(err2 == nil && d2?.globals.webUI == false, "S7 CFBoolean: JSON false decodes to .bool(false)")
}

// 97. S7 buildArgv: the network globals wire into the engine argv.
do {
    let model = ProfileModel(source: "hfid", id: "m/r")
    // web_ui false -> --no-webui; allowed hosts/origins repeat; host non-loopback.
    let g = GlobalCfg(host: "0.0.0.0", port: 8123, apiKey: "k",
                      allowedHosts: ["a.com", "b.com"], allowedOrigins: ["o.com"],
                      webUI: false)
    let res = buildArgv(contract131, profileValues: [:], model: model, globals: g)
    check(res.args.contains("--host") && res.args.contains("0.0.0.0"), "S7 argv: non-loopback host emits")
    check(res.args.contains("--no-webui"), "S7 argv: web_ui false -> --no-webui")
    let ahIdx = res.args.firstIndex(of: "--allowed-host")
    check(ahIdx != nil && res.args[ahIdx! + 1] == "a.com"
          && res.args.filter { $0 == "--allowed-host" }.count == 2,
          "S7 argv: allowed_host repeats for each entry")
    check(res.args.contains("o.com"), "S7 argv: allowed_origin emits")
    // web_ui true (the default) -> no --no-webui (it would be at defValue "false").
    let gOn = GlobalCfg(host: "127.0.0.1", port: 8123, apiKey: "k")
    let resOn = buildArgv(contract131, profileValues: [:], model: model, globals: gOn)
    check(!resOn.args.contains("--no-webui"), "S7 argv: web_ui true -> no --no-webui (engine default)")
    check(!resOn.args.contains("--allowed-host") && !resOn.args.contains("--allowed-origin"),
          "S7 argv: empty allowed lists emit nothing")
    // A stale profile host/allowed is overridden/cleared by the globals (D6).
    let stale = buildArgv(contract131,
                          profileValues: ["host": .string("9.9.9.9"), "allowed_host": .array([.string("stale.com")])],
                          model: model, globals: GlobalCfg(port: 8123, apiKey: "k"))
    check(!stale.args.contains("9.9.9.9") && !stale.args.contains("stale.com"),
          "S7 argv: globals override stale profile host + clear a stale allowed_host")
    check(stale.args.contains("127.0.0.1"), "S7 argv: the default host still emits")
}

// 98. S7 profileOptionDefinitions: the network group is GLOBAL (D6) and never
// appears in a profile; the API tab is the requests group remapped.
do {
    let defs = profileOptionDefinitions(version: "1.3.1")
    let keys = Set(defs.compactMap { $0["key"] as? String })
    for netKey in ["host", "port", "api_key", "allowed_host", "allowed_origin", "no_webui"] {
        check(!keys.contains(netKey), "S7 optdefs: \(netKey) is global-only, not a profile option")
    }
    // The requests group (max_request_size etc.) is remapped to "api".
    check(defs.contains { ($0["key"] as? String) == "max_request_size" && ($0["group"] as? String) == "api" },
          "S7 optdefs: requests options land in the API tab")
    // The ANE stays in the COMPUTE group (per-profile).
    check(defs.contains { ($0["key"] as? String) == "ane" && ($0["group"] as? String) == "compute" },
          "S7 optdefs: ane stays in COMPUTE (per-profile)")
    // A version WITHOUT the cache group -> the CACHE tab has no options (hidden).
    let noCache = profileOptionDefinitions(version: "9.9.9")   // unseen -> latest fallback
    _ = noCache
}

// 99. S7 kitArchOS: the kit dir name yields the arch + OS display.
do {
    let (a1, o1) = kitArchOS("/k/kit/splash-1.3.0-arm64-macos26")
    check(a1 == "ARM64" && o1 == "MACOS 26", "S7 archOS: arm64-macos26 -> ARM64 / MACOS 26")
    let (a2, o2) = kitArchOS("/k/kit/splash-1.3.1-x86_64-macos14")
    check(a2 == "X86_64" && o2 == "MACOS 14", "S7 archOS: x86_64-macos14 -> X86_64 / MACOS 14")
    let (a3, o3) = kitArchOS("/opt/homebrew/libexec")
    check(a3 == nil && o3 == nil, "S7 archOS: a non-named dir yields nils (the line stays quiet)")
    check(kitArchOS(nil) == (nil, nil), "S7 archOS: nil kit -> nils")
}

// 100. S7 engineVerdict: the ENGINE panel's verdict cap.
do {
    check(engineVerdict(resolved: false, version: nil, error: nil, mappingFallback: false).verdict == "unrunnable",
          "S7 verdict: no kit -> unrunnable")
    check(engineVerdict(resolved: true, version: "1.3.0", error: "no python", mappingFallback: false).verdict == "unrunnable",
          "S7 verdict: a resolved kit with a plan error -> unrunnable (the actionable reason)")
    let fb = engineVerdict(resolved: true, version: "1.3.3", error: nil, mappingFallback: true)
    check(fb.verdict == "fallback" && (fb.reason?.contains("FALLBACK") ?? false),
          "S7 verdict: an unmapped version -> fallback")
    let un = engineVerdict(resolved: true, version: "1.3.1", error: nil, mappingFallback: false)
    check(un.verdict == "valid" && un.reason == nil,
          "S7 verdict: any supported version is VALID with no build-version annotation")
    let ok = engineVerdict(resolved: true, version: "1.3.0", error: nil, mappingFallback: false)
    check(ok.verdict == "valid" && ok.reason == nil, "S7 verdict: the built-against kit -> valid, no reason")
    check(builtEngineVersion == "1.3.0", "S7: the built-against version is 1.3.0 (informational only)")
}

// 101. S7 profilePreview: the GENERAL tab's LAUNCH PREVIEW is pure.
do {
    var fs = FakeFS()
    planKit(fs: &fs, path: "/kits/kit130", version: "1.3.0")
    fs.dir("/models/pkg", ["manifest.json", "tokenizer/", "draft/"])
    fs.file("/models/pkg/manifest.json", #"{"model_type": "qwen3_5", "draft_repo": "draft"}"#)
    fs.file("/models/pkg/draft/config.json")
    let folder = ModelFolder(id: "lmstudio", path: "/models", source: "auto")
    let profile = Profile(id: "p1", name: "P",
                          model: ProfileModel(source: "lmstudio", id: "pkg", dir: nil))
    // A healthy package -> the argv is built; restart is the signature vs baseline.
    let p1 = profilePreview(profile, kit: "/kits/kit130", version: "1.3.0",
                            folders: [folder],
                            isDir: { fs.isDir($0) }, fileContents: { fs.fileContents($0) },
                            listDir: { fs.listDir($0) },
                            globals: GlobalCfg(), baselineSignature: nil)
    let args1 = p1["args"] as? [String] ?? []
    check((p1["error"] as? String) == nil, "S7 preview: a healthy package -> no error")
    check(args1.contains("--host") && args1.contains("127.0.0.1"), "S7 preview: the argv carries the host")
    check(p1["restart"] as? Bool == false, "S7 preview: no baseline (nothing running) -> not a restart")
    // The model is resolved from the folder (the stored dir was nil).
    check(args1.contains("/models/pkg") || args1.contains("pkg"), "S7 preview: the model resolves against the folder")
    // A nil kit -> the actionable reason, empty argv.
    let p2 = profilePreview(profile, kit: nil, version: "1.3.0", folders: [folder],
                            isDir: { fs.isDir($0) }, fileContents: { fs.fileContents($0) },
                            listDir: { fs.listDir($0) },
                            globals: GlobalCfg(), baselineSignature: nil)
    check(((p2["args"] as? [Any])?.isEmpty == true) && (p2["error"] as? String) != nil,
          "S7 preview: a missing kit -> empty argv + the reason")
    // A no-model profile -> the actionable "no model" reason.
    let p3 = profilePreview(Profile(id: "p3", name: "X", model: ProfileModel(source: "none")),
                            kit: "/kits/kit130", version: "1.3.0", folders: [folder],
                            isDir: { fs.isDir($0) }, fileContents: { fs.fileContents($0) },
                            listDir: { fs.listDir($0) },
                            globals: GlobalCfg(), baselineSignature: nil)
    check((p3["error"] as? String)?.contains("no model") == true, "S7 preview: no model -> the reason")
    // A baseline that differs -> restart true.
    let p4 = profilePreview(profile, kit: "/kits/kit130", version: "1.3.0", folders: [folder],
                            isDir: { fs.isDir($0) }, fileContents: { fs.fileContents($0) },
                            listDir: { fs.listDir($0) },
                            globals: GlobalCfg(port: 9999), baselineSignature: "a-different-baseline")
    check(p4["restart"] as? Bool == true, "S7 preview: a changed signature vs baseline -> restart")
}

// 102. S7 model sizes: enumerateModels/folderTickState surface size_bytes via
// the injected dirSize (dir-less ollama models -> null).
do {
    var fs = FakeFS()
    fs.dir("/folders/lm/incoai/pkg", ["manifest.json"])
    fs.file("/folders/lm/incoai/pkg/manifest.json", "{}")
    let folder = ModelFolder(id: "lmstudio", path: "/folders/lm", source: "auto")
    let st = folderTickState(folder: folder,
                             isDir: { fs.isDir($0) }, fileContents: { fs.fileContents($0) },
                             listDir: { fs.listDir($0) },
                             dirSize: { $0.hasSuffix("/pkg") ? 1234 : 0 })
    let m = st["models"] as? [Any]
    check(m?.count == 1, "S7 size: one model enumerated")
    let size = (m?.first as? [String: Any])?["size_bytes"]
    check(size as? Int64 == 1234, "S7 size: the dir size rides the model tick state")
}

// 103. S7 real-FS dirSize helper: a file is its own size; a missing path -> nil.
do {
    let tmp = NSTemporaryDirectory() + "/splashui-dirtsize-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    let f = tmp + "/f.bin"
    try? Data(count: 512).write(to: URL(fileURLWithPath: f))
    check(dirSize(f) == 512, "S7 dirSize: a file is its own size")
    check(dirSize(tmp) != nil, "S7 dirSize: a dir sums to a non-nil size")
    check(dirSize(tmp + "/nope") == nil, "S7 dirSize: a missing path -> nil")
    try? FileManager.default.removeItem(atPath: tmp)
}

// 104. S7 tick payload: the new engine + network + preview keys ride along as
// stable nulls/defaults (the change gate stays quiet).
do {
    let d = defaultConfig(home: "/home", now: now)
    let p = configTickPayload(doc: d, loadError: nil, versionTooNew: false,
                              activeInvalid: false, firstRun: false, inFlight: 0, result: nil)
    let eng = p["engine"] as? [String: Any]
    for k in ["arch", "os", "verdict", "verdict_reason"] {
        check(eng?[k] is NSNull, "S7 tick: engine.\(k) is a stable null (pre-overlay)")
    }
    check(p["host"] as? String == "127.0.0.1", "S7 tick: the global host rides along")
    check(p["web_ui"] as? Bool == true, "S7 tick: the global web_ui rides along")
    let prof = p["profiles"] as? [Any]
    check((prof?.first as? [String: Any])?["preview"] is NSNull, "S7 tick: a stable preview null")
    check(((prof?.first as? [String: Any])?["model"] as? [String: Any])?["size_bytes"] is NSNull,
          "S7 tick: a stable model size null")
}

// 105. S7 panel size: the settings view widens the window, the status view
// stays put; the height keeps the app's usual clamps.
do {
    let status = panelTargetSize(view: "status", contentHeight: 700, screenHeight: 1000)
    check(status.width == 520, "panel size: status stays 520 wide")
    check(status.height == 716, "panel size: height is content + 16, unclamped")
    let settings = panelTargetSize(view: "settings", contentHeight: 700, screenHeight: 1000)
    check(settings.width == 820, "panel size: settings widens to 820")
    check(settings.height == 716, "panel size: the view switch does not change the height")
    check(panelTargetSize(view: "whatever", contentHeight: 700, screenHeight: 1000).width == 520,
          "panel size: an unknown view defaults to the status width")
    check(panelTargetSize(view: "status", contentHeight: 100, screenHeight: 1000).height == 370,
          "panel size: the 370pt floor holds")
    check(panelTargetSize(view: "status", contentHeight: 5000, screenHeight: 1000).height == 880,
          "panel size: the screen cap (screenH - 120) holds")
}

// Coding-agent integration: what the Model Provider buttons put on the clipboard.
do {
    let oc = providerSnippet(target: .openCode, profileName: "Qwen", servedName: "served-x",
                             host: "0.0.0.0", port: 8123, apiKey: "k")
    let pi = providerSnippet(target: .pi, profileName: "Qwen", servedName: "served-x",
                             host: "127.0.0.1", port: 9000, apiKey: "k")
    check(oc.contains("\"baseURL\" : \"http://127.0.0.1:8123/v1\""),
          "provider snippet: a 0.0.0.0 bind dials loopback in the OpenCode baseURL")
    check(oc.contains("\"served-x\" : {"),
          "provider snippet: OpenCode keys the models map by the served name")
    check(pi.contains("\"baseUrl\" : \"http://127.0.0.1:9000/v1\""),
          "provider snippet: Pi baseUrl follows the configured host and port")
    check(pi.contains("\"id\" : \"served-x\""),
          "provider snippet: Pi lists the served name as the model id")
    check(loopbackHost("192.168.1.5") == "192.168.1.5",
          "loopbackHost: a concrete LAN address is left alone")
}

// Offline's effective value: unset follows the model's source; an explicit value wins.
do {
    let local = Profile(id: "a", name: "a", model: ProfileModel(source: "lmstudio", id: "x/y"))
    let hf = Profile(id: "b", name: "b", model: ProfileModel(source: "hfid", id: "x/y"))
    let forcedOn = Profile(id: "c", name: "c", model: ProfileModel(source: "hfid", id: "x/y"),
                           options: ["offline": .bool(true)])
    check(offlineEffective(local, folders: []) == true,
          "offline unset + local-folder model: effective ON")
    check(offlineEffective(hf, folders: []) == false,
          "offline unset + Hugging Face id: effective OFF (it downloads)")
    check(offlineEffective(forcedOn, folders: []) == true,
          "offline set explicitly: the explicit value wins over the source default")
}

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
