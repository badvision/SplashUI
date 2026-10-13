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
        appRoot: "/app", home: "/home",
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
        appRoot: "/app", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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

// appRoot rung: a kit in the checkout the app was launched from (install.sh's
// default layout) is found with no env.
do {
    let (d, e) = kitPaths("/app/kit/splash-1.3.0-arm64-macos26")
    let (md, _) = kitPaths("/app/models/incoai/Qwen3.8-27B-Splash")
    let r = resolveSplashPaths(
        env: [:],
        appRoot: "/app", home: "/home",
        isDir: { (d | md).contains($0) }, isExecutable: { e.contains($0) })
    check(r.workDir == "/app/kit/splash-1.3.0-arm64-macos26",
          "ladder: appRoot kit rung found")
    check(r.modelRoot == "/app/models/incoai/Qwen3.8-27B-Splash",
          "model: appRoot models rung")
}

// nothing anywhere: no assumption is made — actionable error, no quit.
do {
    let r = resolveSplashPaths(
        env: [:],
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
        isDir: { _ in false }, isExecutable: { _ in false })
    check(r.executable == nil && r.modelRoot == nil, "empty env values treated as unset")
}

// ---- resolveSplashPaths: model ladder ---------------------------------------

// env SPLASH_MODEL_ROOT wins.
do {
    let (_, ke) = kitPaths("/k")
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/env/model"],
        appRoot: "/app", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
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
        appRoot: "", home: "/home",
        isDir: { $0 == "/k" || $0 == "/m" }, isExecutable: { ke.contains($0) })
    check(r.engineArgs.last == "--disable-ane", "ane: SPLASH_ANE=off adds --disable-ane (module form)")

    let (bd, be) = brewPaths("/opt/homebrew")
    let rb = resolveSplashPaths(
        env: ["SPLASH_ANE": "off"],
        appRoot: "", home: "/home",
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
check(telemetryInt(12) == 12 && telemetryInt(12.5) == 12, "telemetry: representable integers")
check(telemetryInt(nil) == 0 && telemetryInt(.nan) == 0 && telemetryInt(.infinity) == 0, "telemetry: missing and nonfinite are safe")
check(telemetryInt(Double(Int.max)) == 0 && telemetryInt(-Double.greatestFiniteMagnitude) == 0, "telemetry: out-of-range values are safe")
check(rssBytesFromPsOutput(" 437072\n") == 447561728, "RSS: KiB converted to bytes")
check(rssBytesFromPsOutput("0") == 0, "RSS: zero")
check(rssBytesFromPsOutput("") == nil, "RSS: empty")
check(rssBytesFromPsOutput("NaN") == nil, "RSS: malformed")
check(rssBytesFromPsOutput("-1") == nil, "RSS: negative")
check(rssBytesFromPsOutput(String(Int64.max)) == nil, "RSS: overflow")

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
