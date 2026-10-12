// Pure launch decisions for SplashUI — no AppKit, unit-testable.
// Run the tests: ./run_tests.sh (compiles this file + Tests/ui_logic_test.swift).

import Foundation

public struct SplashPaths {
    public var kitDir: String?
    public var python: String?
    public var modelRoot: String?
    public var port: Int
    public var apiKey: String
    public var maxCacheDisk: String
    public var idleRelease: String
    public var base: String
    public var engineArgs: [String]
    public var error: String?
}

// Read once per launch/tick; injected closures keep this pure and testable.
public func resolveSplashPaths(env: [String: String],
                               isDir: (String) -> Bool,
                               isExecutable: (String) -> Bool) -> SplashPaths {
    let modelId = "incoai/Qwen3.8-27B-Splash"
    let root = env["SPLASHUI_HOME"]
    let version = env["SPLASH_VERSION"] ?? "1.3.0"

    var error: String?

    // A usable kit has both the engine binary and the bundled python.
    func isKit(_ d: String) -> Bool {
        isDir(d) && isExecutable(d + "/engine/splash") && isExecutable(d + "/python/bin/python")
    }

    // No assumed install location: an explicit SPLASH_KIT_DIR, or the install.sh
    // layout under an explicitly-set SPLASHUI_HOME. Nothing is guessed from $HOME —
    // a standalone Splash install (anywhere) is pointed at via SPLASH_KIT_DIR.
    var kitCandidates: [String] = []
    if let k = env["SPLASH_KIT_DIR"], k != "" { kitCandidates.append(k) }
    if let r = root { kitCandidates.append(r + "/kit/splash-\(version)-arm64-macos26") }
    let kitDir = kitCandidates.first { isKit($0) }

    // model: explicit SPLASH_MODEL_ROOT, or the install.sh layout under an
    // explicitly-set SPLASHUI_HOME. (No LM-Studio fallback: the user may well not
    // have LM Studio installed; point a separately-downloaded model via env.)
    var modelCandidates: [String] = []
    if let m = env["SPLASH_MODEL_ROOT"], m != "" { modelCandidates.append(m) }
    if let r = root { modelCandidates.append(r + "/models/" + modelId) }
    let modelRoot = modelCandidates.first { isDir($0) }

    if kitDir == nil {
        let tried = kitCandidates.isEmpty ? "" : " — tried: \(kitCandidates.joined(separator: ", "))"
        error = "engine kit not found\(tried) — set SPLASH_KIT_DIR=/path/to/splash-X.Y.Z-arm64-macos26 "
            + "to point at your existing Splash install, or run ./install.sh"
    }
    if modelRoot == nil {
        let tried = modelCandidates.isEmpty ? "" : " — tried: \(modelCandidates.joined(separator: ", "))"
        let m = "model not found\(tried) — set SPLASH_MODEL_ROOT=/path/to/model, or run ./install.sh"
        error = (error == nil) ? m : error! + " · " + m
    }
    let port: Int
    if let raw = env["SPLASH_PORT"], raw != "" {
        if let p = Int(raw), p > 0, p < 65536 {
            port = p
        } else {
            error = (error == nil) ? "SPLASH_PORT '\(raw)' is not a valid port — using 8123"
                : error! + " · SPLASH_PORT '\(raw)' is not a valid port — using 8123"
            port = 8123
        }
    } else { port = 8123 }

    let apiKey = env["SPLASH_KEY"] ?? "splash-standalone-1"
    let maxCacheDisk = env["SPLASH_MAX_CACHE_DISK"] ?? "100g"
    let idleRelease = env["SPLASH_IDLE_RELEASE"] ?? "240m"
    let base = "http://127.0.0.1:\(port)"

    var engineArgs: [String] = []
    if kitDir != nil, let modelRoot = modelRoot {
        engineArgs = ["-u", "-m", "server.server", modelRoot,
                      "--tokenizer", modelRoot + "/tokenizer",
                      "--model", modelId, "--binary", "./engine/splash",
                      "--host", "127.0.0.1", "--port", String(port), "--api-key", apiKey,
                      "--persistent-cache", "--max-cache-disk", maxCacheDisk,
                      "--idle-release", idleRelease]
        // GPU/Neural-Engine prefill split (1.3.0): on by default; SPLASH_ANE=off
        // adds --disable-ane for a GPU-only path.
        if (env["SPLASH_ANE"] ?? "on").lowercased() != "on" { engineArgs.append("--disable-ane") }
    }

    return SplashPaths(kitDir: kitDir,
                       python: kitDir.map { $0 + "/python/bin/python" },
                       modelRoot: modelRoot,
                       port: port,
                       apiKey: apiKey,
                       maxCacheDisk: maxCacheDisk,
                       idleRelease: idleRelease,
                       base: base,
                       engineArgs: engineArgs,
                       error: error)
}

// The UI never outlives the service — but only for a service that actually ran.
// A server that was observed up (crashed, or an adopted external one died) → quit
// 10 s after it's gone. A server that never came up (launch failed) must NOT
// quit: the menu bar stays with the actionable error on display.
public func autoQuitDecision(procGone: Bool, everUp: Bool, downFor: TimeInterval, userStopped: Bool) -> Bool {
    procGone && everUp && !userStopped && downFor > 10
}

// Bounded auto-retry of a failed launch: every 30 s while under 10 attempts.
// The user can fix the kit meanwhile — each attempt re-resolves paths fresh.
public func launchRetryDue(error: Date?, retries: Int, now: Date) -> Bool {
    error != nil && retries < 10 && now.timeIntervalSince(error!) >= 30
}
