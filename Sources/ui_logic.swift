// Pure launch decisions for SplashUI — no AppKit, unit-testable.
// Run the tests: ./run_tests.sh (compiles this file + Tests/main.swift).

import Foundation

public struct SplashPaths {
    public var workDir: String?      // the kit dir (cwd): holds engine/ + python/ + server/
    public var executable: String?   // the bundled python binary that runs the server module
    public var modelRoot: String?    // the on-disk model dir (1.3.0 flavor loads it positionally, never re-downloading)
    public var port: Int
    public var apiKey: String
    public var maxCacheDisk: String
    public var idleRelease: String
    public var base: String
    public var engineArgs: [String]
    public var modelId: String?       // the model id actually served (flavor-aware)
    public var error: String?
}

// An "engine kit" is a directory holding the engine binary, a bundled python,
// and the server package. Both the release tarball's kit dir and the Homebrew
// keg's libexec/ are exactly that — same layout (`engine/splash`,
// `python/bin/python3`, `server/`), only the launch contract differs. The UI
// finds one by discovery, in order:
//   1. SPLASH_KIT_DIR — an explicit path-based install (always wins)
//   2. SPLASHUI_HOME/kit/splash-$SPLASH_VERSION-arm64-macos26 (install.sh layout)
//   3. the directory the app was launched from (install.sh's default layout)
//   4. a Homebrew keg when detected (`brew install incoai/tap/splash`) — the
//      fallback
// The model is a separate axis, found in order: SPLASH_MODEL_ROOT ->
// SPLASHUI_HOME/models -> launchdir/models -> ~/.lmstudio/models. A found dir
// tells a 1.3.0-style engine where to load from (reusing an installed model,
// never re-downloading). The model is always identified by its Hugging Face id
// regardless; the dir is only used by the 1.3.0 flavor. The launch contract is
// keyed to a kit's on-disk `release.json` version: 1.3.0-style loads the model
// DIR positionally (no download); 1.3.1+ (the Homebrew keg) loads by id via
// `install/launcher.py serve` (one-time download; a 1.3.0 model dir is not
// usable by it). When nothing resolves, the menu bar stays up and names every
// location tried instead of quitting. `home`, `brewKeg`, and `kitVersion` are
// injected for tests.
public func resolveSplashPaths(env: [String: String],
                               appRoot: String,
                               home: String,
                               isDir: (String) -> Bool,
                               isExecutable: (String) -> Bool,
                               brewKeg: () -> String? = { nil },
                               kitVersion: (String) -> String? = { _ in nil }) -> SplashPaths {
    // The on-disk model (the 1.3.0 Splash package): loaded positionally by a
    // 1.3.0-style engine. A 1.3.1+ engine (the Homebrew keg) cannot read that
    // format at all — neither the launcher ("Splash no longer loads") nor the
    // engine binary — so it downloads and loads its own MLX model by id
    // instead; the local package is unusable by it.
    let dirModelId = "incoai/Qwen3.8-27B-Splash"
    let idModelId = "mlx-community/Qwen3.8-27B-4bit"
    let root = env["SPLASHUI_HOME"]
    let version = env["SPLASH_VERSION"] ?? "1.3.0"

    var errorParts: [String] = []
    func kitError(_ t: String) {
        errorParts.insert("engine kit not found\(t) — set SPLASH_KIT_DIR=/path/to/splash-X.Y.Z-arm64-macos26, "
            + "run `./install.sh`, or install via Homebrew (brew install incoai/tap/splash), at: \(t)", at: 0)
    }

    func isKit(_ d: String) -> Bool {
        isDir(d) && isExecutable(d + "/engine/splash") &&
        (isExecutable(d + "/python/bin/python") || isExecutable(d + "/python/bin/python3"))
    }
    func pythonOf(_ d: String) -> String? {
        if isExecutable(d + "/python/bin/python") { return d + "/python/bin/python" }
        if isExecutable(d + "/python/bin/python3") { return d + "/python/bin/python3" }
        return nil
    }

    var tried: [String] = []

    // Model discovery first: the engine selection depends on whether a local
    // model is present, because only a 1.3.0-style engine can load it.
    var modelCandidates: [String] = []
    if let m = env["SPLASH_MODEL_ROOT"], m != "" { modelCandidates.append(m) }
    if let r = root, r != "" { modelCandidates.append(r + "/models/" + dirModelId) }
    if !appRoot.isEmpty { modelCandidates.append(appRoot + "/models/" + dirModelId) }
    modelCandidates.append(home + "/.lmstudio/models/" + dirModelId)
    let modelRoot = modelCandidates.first { isDir($0) }

    var kit: String?
    func tryKit(_ d: String) {
        tried.append(d)
        if kit == nil, isKit(d) { kit = d }
    }

    // 1. Explicit path-based install (always wins).
    if let k = env["SPLASH_KIT_DIR"], k != "" { tryKit(k) }
    // 2. install.sh layout under an explicitly-set home.
    if kit == nil, let r = root, r != "" {
        tryKit(r + "/kit/splash-\(version)-arm64-macos26")
    }
    // 3. The checkout the app was launched from (install.sh's default layout).
    if kit == nil, !appRoot.isEmpty {
        tryKit(appRoot + "/kit/splash-\(version)-arm64-macos26")
    }
    // 4. Homebrew (1.3.1) — only when no local model is present: a 1.3.1
    //    engine cannot load the 1.3.0 package and would re-download the
    //    model, which is not what the user wants.
    if kit == nil, modelRoot == nil, let b = brewKeg(), b != "" {
        tryKit(b + "/libexec")
    }

    // Engine version gates the launch contract: >= 1.3.1 (the Homebrew keg)
    // loads the model by id; 1.3.0-style loads it positionally.
    let idModel = kit.flatMap { kitVersion($0) }
        .map { versionGE($0, "1.3.1") } ?? false

    if kit == nil {
        if modelRoot != nil {
            let kt = tried.isEmpty ? "" : " — tried: " + tried.joined(separator: ", ")
            errorParts.append("local model found (at: \(modelRoot!)) but no 1.3.0 engine kit\(kt) — "
                + "the 1.3.1 Homebrew engine cannot load it (it would re-download the model instead); "
                + "set SPLASH_KIT_DIR=/path/to/splash-1.3.0-arm64-macos26")
        } else {
            kitError(tried.joined(separator: ", "))
        }
    }

    let executable = kit.flatMap { pythonOf($0) }
    if kit != nil, executable != nil, !idModel, modelRoot == nil {
        let mt = modelCandidates.isEmpty ? "" : " — tried: " + modelCandidates.joined(separator: ", ")
        errorParts.append("model not found" + mt + " — set SPLASH_MODEL_ROOT=/path/to/model, or run `./install.sh`")
    }
    if idModel, let k = kit, modelRoot != nil {
        errorParts.append("local model found (at: \(modelRoot!)) but the engine at \(k) is \(kitVersion(k) ?? "unknown") — "
            + "it cannot load the 1.3.0 model format (it would re-download the model); "
            + "point SPLASH_KIT_DIR at a 1.3.0 kit")
    }

    let port: Int = {
        if let raw = env["SPLASH_PORT"], raw != "" {
            if let p = Int(raw), p > 0, p < 65536 { return p }
            errorParts.append("SPLASH_PORT (\"\(raw)\") is not a valid port; using 8123")
            return 8123
        }
        return 8123
    }()
    let apiKey = env["SPLASH_KEY"] ?? "splash-standalone-1"
    let maxCacheDisk = env["SPLASH_MAX_CACHE_DISK"] ?? "100g"
    let idleRelease = env["SPLASH_IDLE_RELEASE"] ?? "240m"
    let base = "http://127.0.0.1:\(port)"

    var engineArgs: [String] = []
    if executable == nil {
        engineArgs = []
    } else if idModel {
        // 1.3.1+ (Homebrew keg): load the model by id; the key assembles its
        // own copy (one-time download). launcher.py is script-relative, so
        // cwd=kit is enough to find it.
        engineArgs = ["-u", "install/launcher.py", "serve", "--model", idModelId,
                      "--host", "127.0.0.1", "--port", String(port),
                      "--api-key", apiKey, "--persistent-cache",
                      "--max-cache-disk", maxCacheDisk, "--idle-release", idleRelease]
    } else if let m = modelRoot {
        // 1.3.0-style: pass the on-disk model dir positionally (no download)
        engineArgs = ["-u", "-m", "server.server", m,
                      "--tokenizer", m, "--binary", "./engine/splash",
                      "--host", "127.0.0.1", "--port", String(port),
                      "--api-key", apiKey, "--persistent-cache",
                      "--max-cache-disk", maxCacheDisk, "--idle-release", idleRelease]
    }

    // GPU/Neural-Engine prefill split: on by default; SPLASH_ANE=off adds
    // --disable-ane.
    if (env["SPLASH_ANE"] ?? "on").lowercased() != "on" {
        engineArgs.append("--disable-ane")
    }
    // The model id actually served — flavor-aware, so the panel shows the real
    // model (the user's local package under the 1.3.0 engine, the MLX id under
    // 1.3.1) rather than a fixed string.
    let modelId: String?
    if executable == nil {
        modelId = nil
    } else if idModel {
        modelId = idModelId
    } else if modelRoot != nil {
        modelId = dirModelId
    } else {
        modelId = nil
    }

    return SplashPaths(workDir: kit, executable: executable, modelRoot: modelRoot,
                       port: port, apiKey: apiKey, maxCacheDisk: maxCacheDisk,
                       idleRelease: idleRelease, base: base, engineArgs: engineArgs,
                       modelId: modelId,
                       error: errorParts.isEmpty ? nil : errorParts.joined(separator: " | "))
}

// Returns true when version `a` >= version `b` (e.g. "1.3.1" >= "1.3.1").
func versionGE(_ a: String, _ b: String) -> Bool {
    let ac = a.split(separator: ".").compactMap { Int($0) }
    let bc = b.split(separator: ".").compactMap { Int($0) }
    let n = max(ac.count, bc.count)
    for i in 0..<n {
        let x = i < ac.count ? ac[i] : 0
        let y = i < bc.count ? bc[i] : 0
        if x != y { return x > y }
    }
    return true
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
