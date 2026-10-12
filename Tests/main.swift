// Regression tests for the pure SplashUI launch decisions (ui_logic.swift).
// Run from the repo root: ./run_tests.sh   (compiles ui_logic.swift + this file, no AppKit).

import Foundation

var failures = 0
func check(_ cond: Bool, _ label: String) {
    if cond { print("ok  - \(label)") }
    else { failures += 1; print("FAIL- \(label)") }
}

let now = Date(timeIntervalSince1970: 1_000_000)

// ---- resolveSplashPaths: kit ladder -----------------------------------------

// env SPLASH_KIT_DIR wins
do {
    let dirs: Set<String> = ["/env/kit", "/root/kit/splash-1.3.0-arm64-macos26"]
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/env/kit"],
        isDir: { dirs.contains($0) }, isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.kitDir == "/env/kit", "kit: SPLASH_KIT_DIR env wins")
}

// incomplete env kit (no python) is skipped; SPLASHUI_HOME rung wins
do {
    let dirs: Set<String> = ["/root/kit/splash-1.3.0-arm64-macos26", "/env/broken/kit",
                              "/env/model"]
    // The broken env kit has the engine binary but no bundled python; the SPLASHUI_HOME
    // kit is complete.
    let exe: Set<String> = [
        "/env/broken/kit/engine/splash",
        "/root/kit/splash-1.3.0-arm64-macos26/engine/splash",
        "/root/kit/splash-1.3.0-arm64-macos26/python/bin/python",
    ]
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/env/broken/kit", "SPLASHUI_HOME": "/root",
              "SPLASH_MODEL_ROOT": "/env/model"],
        isDir: { dirs.contains($0) },
        isExecutable: { exe.contains($0) })
    check(r.kitDir == "/root/kit/splash-1.3.0-arm64-macos26", "kit: incomplete env kit skipped, SPLASHUI_HOME rung wins")
    check(r.python == "/root/kit/splash-1.3.0-arm64-macos26/python/bin/python", "kit: python derived from kit dir")
    check(r.error == nil, "kit: no error when kit resolves")
}

// SPLASHUI_HOME + SPLASH_VERSION drive the derived path
do {
    let dirs: Set<String> = ["/customroot/kit/splash-9.9.9-arm64-macos26"]
    let r = resolveSplashPaths(
        env: ["SPLASHUI_HOME": "/customroot", "SPLASH_VERSION": "9.9.9"],
        isDir: { dirs.contains($0) },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.kitDir == "/customroot/kit/splash-9.9.9-arm64-macos26", "kit: SPLASHUI_HOME + SPLASH_VERSION honored")
}

// no env at all: NOTHING is assumed — no home-root guess, no LM-Studio guess,
// even if such directories exist on disk (the 0.3 hard-code is gone).
do {
    let r = resolveSplashPaths(
        env: [:],
        isDir: { _ in true }, isExecutable: { _ in true })
    check(r.kitDir == nil, "kit: no env -> no kit assumed")
    check(r.modelRoot == nil, "model: no env -> no model assumed")
    let e = r.error ?? ""
    check(e.contains("SPLASH_KIT_DIR") && e.contains("SPLASH_MODEL_ROOT"),
          "no env: error names both env knobs")
    check(!e.contains("/home/") && !e.contains("/Users/"), "no env: error names no assumed path")
}

// a kit installed under ~/SplashUI (the old default) is NOT found without env —
// it is just another standalone Splash install, to be pointed at explicitly.
do {
    let dirs: Set<String> = ["/home/SplashUI/kit/splash-1.3.0-arm64-macos26"]
    let r = resolveSplashPaths(
        env: [:],
        isDir: { dirs.contains($0) },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.kitDir == nil, "kit: existing ~/SplashUI install ignored without env")
    check(r.error?.contains("SPLASH_KIT_DIR") == true, "kit: error suggests SPLASH_KIT_DIR")
}

// empty-string env values count as unset
do {
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "", "SPLASH_MODEL_ROOT": ""],
        isDir: { _ in true }, isExecutable: { _ in true })
    check(r.kitDir == nil && r.modelRoot == nil, "empty env values treated as unset")
}

// ---- resolveSplashPaths: model ladder ---------------------------------------

// env SPLASH_MODEL_ROOT wins
do {
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/env/model"],
        isDir: { $0 == "/k" || $0 == "/env/model" },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.modelRoot == "/env/model", "model: SPLASH_MODEL_ROOT wins")
    check(r.error == nil, "model: no error when both resolve")
}

// SPLASHUI_HOME models rung
do {
    let dirs: Set<String> = ["/k", "/customroot/models/incoai/Qwen3.8-27B-Splash"]
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASHUI_HOME": "/customroot"],
        isDir: { dirs.contains($0) },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.modelRoot == "/customroot/models/incoai/Qwen3.8-27B-Splash", "model: SPLASHUI_HOME models rung")
}

// no LM-Studio rung: a model that exists ONLY in ~/.lmstudio is not picked up.
do {
    let dirs: Set<String> = ["/k", "/home/.lmstudio/models/incoai/Qwen3.8-27B-Splash"]
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k"],
        isDir: { dirs.contains($0) },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.modelRoot == nil, "model: LM-Studio location not assumed")
    check(r.error?.contains("SPLASH_MODEL_ROOT") == true, "model: miss suggests SPLASH_MODEL_ROOT")
}

// model miss with env set: error names the tried location
do {
    let dirs: Set<String> = ["/k"]
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/env/model",
              "SPLASHUI_HOME": "/customroot"],
        isDir: { dirs.contains($0) },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.modelRoot == nil, "model miss: modelRoot nil")
    let e = r.error ?? ""
    check(e.contains("/env/model"), "model miss: error names SPLASH_MODEL_ROOT path")
    check(e.contains("/customroot/models/incoai/Qwen3.8-27B-Splash"),
          "model miss: error names SPLASHUI_HOME path")
    check(e.contains("SPLASH_MODEL_ROOT") && e.contains("./install.sh"),
          "model miss: error suggests env var / install.sh")
}

// ---- knobs ------------------------------------------------------------------

do {
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/m", "SPLASH_PORT": "8199",
              "SPLASH_KEY": "k2", "SPLASH_MAX_CACHE_DISK": "50g", "SPLASH_IDLE_RELEASE": "60m"],
        isDir: { $0 == "/k" || $0 == "/m" },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.port == 8199, "port: SPLASH_PORT honored")
    check(r.apiKey == "k2", "key: SPLASH_KEY honored")
    check(r.maxCacheDisk == "50g", "cache: SPLASH_MAX_CACHE_DISK honored")
    check(r.idleRelease == "60m", "idle: SPLASH_IDLE_RELEASE honored")
    check(r.base == "http://127.0.0.1:8199", "base derived from resolved port")
    check(r.engineArgs.contains("8199"), "engineArgs: port in argv")
}

// invalid SPLASH_PORT: default 8123 kept, non-fatal note names the bad value
do {
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/m", "SPLASH_PORT": "nope"],
        isDir: { $0 == "/k" || $0 == "/m" },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.port == 8123, "port: invalid SPLASH_PORT falls back to 8123")
    let e = r.error ?? ""
    check(e.contains("SPLASH_PORT") && e.contains("nope"), "port: invalid value named in error")
}

// defaults when nothing set
do {
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/m"],
        isDir: { $0 == "/k" || $0 == "/m" },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.port == 8123 && r.apiKey == "splash-standalone-1" && r.maxCacheDisk == "100g"
          && r.idleRelease == "240m", "defaults: port/key/cache/idle")
    check(r.engineArgs.contains("-m") && r.engineArgs.contains("server.server"), "engineArgs: module form")
    check(!r.engineArgs.contains("--disable-ane"), "ane: on by default (no --disable-ane)")
}

// SPLASH_ANE=off adds --disable-ane
do {
    let r = resolveSplashPaths(
        env: ["SPLASH_KIT_DIR": "/k", "SPLASH_MODEL_ROOT": "/m", "SPLASH_ANE": "off"],
        isDir: { $0 == "/k" || $0 == "/m" },
        isExecutable: { $0.hasSuffix("python") || $0.hasSuffix("splash") })
    check(r.engineArgs.last == "--disable-ane", "ane: SPLASH_ANE=off adds --disable-ane")
}

// ---- autoQuitDecision: truth table ------------------------------------------

// up then gone >10 s: quit (crash path, unchanged behavior)
check(autoQuitDecision(procGone: true, everUp: true, downFor: 11, userStopped: false) == true,
      "quit: up-then-gone 11s -> quit")
// up then gone 9 s: not yet
check(autoQuitDecision(procGone: true, everUp: true, downFor: 9, userStopped: false) == false,
      "quit: up-then-gone 9s -> no quit")
// never up, long gone: NEVER quit (the bug fix)
check(autoQuitDecision(procGone: true, everUp: false, downFor: 60, userStopped: false) == false,
      "quit: never-up 60s -> no quit")
// not gone: never quit
check(autoQuitDecision(procGone: false, everUp: true, downFor: 0, userStopped: false) == false,
      "quit: proc alive -> no quit")
// user stopped: never auto-quit
check(autoQuitDecision(procGone: true, everUp: true, downFor: 11, userStopped: true) == false,
      "quit: userStopped -> no quit")

// ---- launchRetryDue ---------------------------------------------------------

// no error: not due
check(launchRetryDue(error: nil, retries: 0, now: now) == false, "retry: no error -> not due")
// error 31 s old, within retry cap: due
check(launchRetryDue(error: now.addingTimeInterval(-31), retries: 3, now: now) == true, "retry: 31s old, under cap -> due")
// error 29 s old: not yet (30 s interval)
check(launchRetryDue(error: now.addingTimeInterval(-29), retries: 3, now: now) == false, "retry: 29s old -> not due")
// at the 10-retry cap: never due again
check(launchRetryDue(error: now.addingTimeInterval(-400), retries: 10, now: now) == false, "retry: cap (10) reached -> not due")
// just under the cap: still due
check(launchRetryDue(error: now.addingTimeInterval(-400), retries: 9, now: now) == true, "retry: 9 retries, long ago -> due")

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
