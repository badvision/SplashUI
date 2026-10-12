// Pure launch decisions for SplashUI — no AppKit, unit-testable.
// Run the tests: ./run_tests.sh (compiles this file + Tests/main.swift).

import Foundation

// How the engine is executed. Two install layouts exist:
//   tarball — a release tarball (or ./install.sh): run the bundled python with
//             `-m server.server`, cwd = the kit, model passed as a directory.
//   brew    — `brew install incoai/tap/splash`: run the `splash` shim with
//             `serve --model <id>`; the launcher downloads/verifies the model
//             itself, so no model dir is required up front.
public enum EnginePlan {
    case tarball
    case brew
}

public struct SplashPaths {
    public var plan: EnginePlan
    public var executable: String?   // bundled python (tarball) or splash shim (brew)
    public var workDir: String?      // the kit dir (tarball); nil for brew
    public var modelRoot: String?    // model dir (tarball) or the model name (brew)
    public var port: Int
    public var apiKey: String
    public var maxCacheDisk: String
    public var idleRelease: String
    public var base: String
    public var engineArgs: [String]
    public var error: String?
}

// Resolution order for the engine: an explicit SPLASH_KIT_DIR (an optional
// path-based install) always wins, then a Homebrew keg when detected
// (`brew install incoai/tap/splash`) — the preferred default, then the
// install.sh layout under an explicitly-set SPLASHUI_HOME, then the directory
// the app was launched from (install.sh's default install root). `home` and
// `brewKeg` are injected for tests.
public func resolveSplashPaths(env: [String: String],
                               appRoot: String,
                               home: String,
                               isDir: (String) -> Bool,
                               isExecutable: (String) -> Bool,
                               brewKeg: () -> String? = { nil }) -> SplashPaths {
    let modelId = "incoai/Qwen3.8-27B-Splash"
    let root = env["SPLASHUI_HOME"]
    let version = env["SPLASH_VERSION"] ?? "1.3.0"

    var error: String?

    // A usable tarball kit has both the engine binary and the bundled python.
    func isKit(_ d: String) -> Bool {
        isDir(d) && isExecutable(d + "/engine/splash") && isExecutable(d + "/python/bin/python")
    }

    // A usable Homebrew keg exposes the `splash` shim + engine + python3
    // launcher under its prefix. No `engine/splash` at the prefix root and no
    // `python/bin/python` (it is `python3`), so this is distinct from the
    // tarball layout.
    func isBrew(_ prefix: String) -> Bool {
        isExecutable(prefix + "/bin/splash")
            && isDir(prefix + "/libexec/engine")
            && isExecutable(prefix + "/libexec/python/bin/python3")
    }

    enum Hit { case tarball(String), brew(String) }
    var hit: Hit?
    var tried: [String] = []

    // 1. Explicit path-based install.
    if let k = env["SPLASH_KIT_DIR"], k != "" {
        tried.append(k)
        if isKit(k) { hit = .tarball(k) }
    }
    // 2. Homebrew (the preferred default when present).
    if hit == nil, let b = brewKeg() {
        tried.append(b)
        if isBrew(b) { hit = .brew(b) }
    }
    // 3. install.sh layout under an explicitly-set home.
    if hit == nil, let r = root, r != "" {
        let d = r + "/kit/splash-\(version)-arm64-macos26"
        tried.append(d)
        if isKit(d) { hit = .tarball(d) }
    }
    // 4. The checkout the app was launched from.
    if hit == nil, !appRoot.isEmpty {
        let d = appRoot + "/kit/splash-\(version)-arm64-macos26"
        tried.append(d)
        if isKit(d) { hit = .tarball(d) }
    }

    let plan: EnginePlan
    var executable: String?
    var workDir: String?
    switch hit {
    case .tarball(let d): plan = .tarball; executable = d + "/python/bin/python"; workDir = d
    case .brew(let p):    plan = .brew;    executable = p + "/bin/splash"
    case .none:           plan = .tarball
    }

    // A model dir is only needed by the tarball plan. The brew launcher
    // downloads and verifies the model by name, so it requires none up front.
    var modelRoot: String?
    if plan == .tarball, workDir != nil {
        var modelCandidates: [String] = []
        if let m = env["SPLASH_MODEL_ROOT"], m != "" { modelCandidates.append(m) }
        if let r = root, r != "" { modelCandidates.append(r + "/models/" + modelId) }
        if !appRoot.isEmpty { modelCandidates.append(appRoot + "/models/" + modelId) }
        modelCandidates.append(home + "/.lmstudio/models/" + modelId)
        modelRoot = modelCandidates.first { isDir($0) }
        if modelRoot == nil {
            let tried = modelCandidates.isEmpty ? "" : " — tried: \(modelCandidates.joined(separator: ", "))"
            let m = "model not found\(tried) — set SPLASH_MODEL_ROOT=/path/to/model, or run ./install.sh"
            error = (error == nil) ? m : error! + " · " + m
        }
    } else if plan == .brew {
        modelRoot = modelId
    }

    if hit == nil {
        let tried = tried.isEmpty ? "" : " — tried: \(tried.joined(separator: ", "))"
        let e = "engine kit not found\(tried) — set SPLASH_KIT_DIR=/path/to/splash-X.Y.Z-arm64-macos26, "
            + "run ./install.sh, or install via Homebrew (brew install incoai/tap/splash)"
        error = (error == nil) ? e : error! + " · " + e
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
    if executable != nil, modelRoot != nil {
        switch plan {
        case .tarball:
            engineArgs = ["-u", "-m", "server.server", modelRoot!,
                          "--tokenizer", modelRoot! + "/tokenizer",
                          "--model", modelId, "--binary", "./engine/splash",
                          "--host", "127.0.0.1", "--port", String(port), "--api-key", apiKey,
                          "--persistent-cache", "--max-cache-disk", maxCacheDisk,
                          "--idle-release", idleRelease]
        case .brew:
            engineArgs = ["serve", "--model", modelRoot!,
                          "--host", "127.0.0.1", "--port", String(port), "--api-key", apiKey,
                          "--persistent-cache", "--max-cache-disk", maxCacheDisk,
                          "--idle-release", idleRelease]
        }
        // GPU/Neural-Engine prefill split (1.3.0): on by default; SPLASH_ANE=off
        // adds --disable-ane for a GPU-only path.
        if (env["SPLASH_ANE"] ?? "on").lowercased() != "on" { engineArgs.append("--disable-ane") }
    }

    return SplashPaths(plan: plan,
                       executable: executable,
                       workDir: workDir,
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
