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
    public var version: String?       // the engine kit version (release.json) actually running
    public var error: String?
}

// An "engine kit" is a directory holding the engine binary, a bundled python,
// and the server package. Both the release tarball's kit dir and the Homebrew
// keg's libexec/ are exactly that — same layout (`engine/splash`,
// `python/bin/python3`, `server/`), only the launch contract differs. The UI
// finds one by discovery, in order:
//   1. SPLASH_KIT_DIR — an explicit path-based install (always wins)
//   2. effective root/kit/splash-$SPLASH_VERSION-arm64-macos26 (install.sh layout)
//      — SPLASHUI_HOME, or the default install root when unset
//   3. a Homebrew keg when detected (`brew install incoai/tap/splash`) — the
//      fallback
// The model is a separate axis, found in order: SPLASH_MODEL_ROOT ->
// effective root/models -> ~/.lmstudio/models. A found dir
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
                               defaultRoot: String?,
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
    let effRoot = root ?? defaultRoot
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
    if let r = effRoot, r != "" { modelCandidates.append(r + "/models/" + dirModelId) }
    modelCandidates.append(home + "/.lmstudio/models/" + dirModelId)
    let modelRoot = modelCandidates.first { isDir($0) }

    var kit: String?
    func tryKit(_ d: String) {
        tried.append(d)
        if kit == nil, isKit(d) { kit = d }
    }

    // 1. Explicit path-based install (always wins).
    if let k = env["SPLASH_KIT_DIR"], k != "" { tryKit(k) }
    // 2. install.sh layout under SPLASHUI_HOME or the default install root.
    if kit == nil, let r = effRoot, r != "" {
        tryKit(r + "/kit/splash-\(version)-arm64-macos26")
    }
    // 3. Homebrew (1.3.1) — only when no local model is present: a 1.3.1
    //    engine cannot load the 1.3.0 package and would re-download the
    //    model, which is not what the user wants.
    if kit == nil, modelRoot == nil, let b = brewKeg(), b != "" {
        tryKit(b + "/libexec")
    }

    // Engine version gates the launch contract: >= 1.3.1 (the Homebrew keg)
    // loads the model by id; 1.3.0-style loads it positionally. The resolved
    // kit's release.json version is also surfaced in the panel (what's running).
    let kitVer = kit.flatMap { kitVersion($0) }
    let idModel = kitVer.map { versionGE($0, "1.3.1") } ?? false

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
        // 1.3.0-style: pass the on-disk model dir positionally (no download).
        // server.py also requires --model OWNER/REPO (validated id), and the
        // --tokenizer path must be the package's tokenizer/ subdir (the Splash
        // package keeps tokenizer.json + config there, not at the model root).
        engineArgs = ["-u", "-m", "server.server", m,
                      "--model", dirModelId,
                      "--tokenizer", m + "/tokenizer", "--binary", "./engine/splash",
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
                       modelId: modelId, version: kitVer,
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

public func requestRowId(current: Int, lineHasId: Int?) -> (id: Int, next: Int) {
    let id = lineHasId ?? current
    return (id, max(current, id == Int.max ? Int.max : id + 1))
}

public func inFlight(prefilling: Int, decoding: Int, frontendActive: Int) -> Bool {
    prefilling > 0 || decoding > 0 || frontendActive > 0
}

public func prefillProgress(prefilledTotal: Double, prefillBase: Double?) -> Double? {
    guard let base = prefillBase, base.isFinite, prefilledTotal.isFinite else { return nil }
    return max(0, prefilledTotal - base)
}

// Prefill completion percentage: done_fresh ÷ estFresh, clamped to 0...100 (or
// 0...cap). `done` is the request's fresh (uncached) prefill-token counter delta
// since it started; `estFresh` is an estimate of the same fresh-tail quantity it
// will total (numerator and denominator are commensurate). nil when estFresh is
// nil or <= 0 (no honest estimate); a stale/under-sized estimate that the counter
// runs past clamps to the ceiling — never > the ceiling, never NaN.
// `cap` holds the readout below 100 while the engine still reports an in-flight
// prefill (the scheduler is the only trustworthy prefill→decode signal; the
// extrapolated pct can otherwise flash 100% seconds before the first token).
public func prefillPct(done: Double, estFresh: Double?, cap: Double? = nil) -> Double? {
    guard let est = estFresh, est.isFinite, est > 0 else { return nil }
    let ceiling = cap.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 100
    return min(ceiling, max(0, 100 * done / est))
}

// Session fallback for a synthesized in-flight row whose prompt size the Request
// log has not logged yet: the mean fresh (uncached) tail over recent completions
// as (input, cached) pairs. nil when the window is empty or nothing fresh was
// ever observed.
public func meanFreshTail(fresh: [(Int, Int)]) -> Double? {
    let vals = fresh.map { p in max(0, p.0 - p.1) }
    guard !vals.isEmpty, vals.contains(where: { $0 > 0 }) else { return nil }
    return Double(vals.reduce(0) { $0 + $1 }) / Double(vals.count)
}

// Completion ETA from autoregression on the live prefill rate: the remaining
// fresh tail ÷ the measured prefill rate, recomputed every tick so it naturally
// shrinks as the rate updates. nil when the rate is nil or <= 0, or estFresh is
// nil/<= 0 (no estimate); negative remaining clamps to 0.
public func prefillEta(done: Double, estFresh: Double?, rate: Double?) -> Double? {
    guard let est = estFresh, est.isFinite, est > 0,
          let r = rate, r > 0, r.isFinite else { return nil }
    return max(0, est - done) / r
}

// Rate extrapolation for a chunk-stepped prefill counter. The engine commits
// splash_prefill_input_tokens_total in ~2048-token ANE-FFN steps (~8 s apart), so
// the raw counter sits flat for most of a chunk. Rather than projecting the
// fraction of the current chunk (which reads 0% until the first commit), we
// autoregress the live prefill rate over the time since the counter last moved,
// so the readout climbs from the start.
//   proj = workDone + (age − ageAtLastCommit) × rate
// clamped to [workDone, estFresh]: never below the counter (it is the truth) and
// never above estFresh (→ 100%, never >100). ageAtLastCommit is the row's age when
// the counter last moved (0 if it never moved). A nil rate returns the stepped
// counter (honest fallback — unchanged behavior). Monotone in age for fixed
// inputs; equals workDone at age == ageAtLastCommit.
public func prefillProjectedDone(workDone: Double, ageAtLastCommit: Double,
                                 age: Double, rate: Double?, estFresh: Double?) -> Double {
    guard workDone.isFinite, age.isFinite, ageAtLastCommit.isFinite,
          let r = rate, r > 0, r.isFinite else { return max(0, workDone) }
    let elapsed = max(0, age - ageAtLastCommit)
    var proj = max(0, workDone) + elapsed * r
    if let est = estFresh, est.isFinite, est > 0 { proj = min(proj, est) }
    return proj
}

// Three-rung rate for prefill extrapolation and ETA: the live per-prefill sample,
// then the 15 s latch, then the engine's session-wide prefill rate. The displayed
// tok/s readout is the live sample only (never this) — this only feeds the
// projected done-value and the ETA, so a cold request on a warm idle engine
// still climbs from the start.
public func prefillProjRate(live: Double?, latch: Double?, engine: Double?) -> Double? {
    func ok(_ v: Double?) -> Double? { v.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
    return ok(live) ?? ok(latch) ?? ok(engine)
}

// The prefill counter commits in ~2048-token steps, so a 1 s-delta rate sample that
// straddles a commit edge reads the whole chunk over the poll interval (~2000 tok/s
// against a ~128 tok/s sustained rate). The request-cumulative rate (tokens actually
// committed ÷ real elapsed time) self-averages over the request's life and is the one
// rate free of that edge spike — until the first commit lands, it under-reads (age
// includes pre-commit queue/wait time), so it is only trusted once it has seen at
// least one full chunk (minCommitted, ~2048 tokens).
public func prefillCumulativeRate(workDone: Double, age: Double, minCommitted: Double = 2048) -> Double? {
    guard workDone.isFinite, workDone >= minCommitted, age.isFinite, age > 0.5 else { return nil }
    let r = workDone / age
    return r.isFinite && r > 0 ? r : nil
}

// Extrapolation-rate guard against the chunk-edge spike. `raw` is the three-rung
// instantaneous rate; `cumulative` is the request-cumulative rate (nil until the
// first full chunk commits). A live spike over-runs the cumulative (raw > cumulative)
// → clamp to the cumulative; a legitimate low instantaneous sample (raw < cumulative,
// a mid-chunk flat window) is kept. Never raises the rate, never lowers it below a
// genuine measurement.
public func calibratePrefillRate(raw: Double?, cumulative: Double?) -> Double? {
    guard let r = raw, r.isFinite, r > 0 else { return nil }
    if let c = cumulative, c.isFinite, c > 0, r > c { return c }
    return r
}

// Diagnostic: the age (s) at which a time-series of (age, pct) samples first
// crosses `pct` (100, or a cap like 99), linearly interpolated between samples.
// nil when the series never reached that level (e.g. it was capped and the
// scheduler never flipped).
public func ageAtPctCross(samples: [(age: Double, pct: Double)], pct: Double) -> Double? {
    guard let first = samples.first, first.pct >= pct else {
        for i in samples.indices.dropFirst() {
            let a = samples[i - 1], b = samples[i]
            guard b.pct >= pct else { continue }
            let span = b.pct - a.pct
            let f = span > 0 ? (pct - a.pct) / span : 1
            return a.age + f * (b.age - a.age)
        }
        return nil
    }
    return first.age
}

// "12 s" under a minute, "1m 23 s" at/above (seconds ceil'd). nil when no ETA.
public func prefillEtaText(sec: Double?) -> String? {
    guard let s = sec, s.isFinite, s >= 0 else { return nil }
    let i = Int(ceil(s))
    return i >= 60 ? "\(i / 60)m \(i % 60) s" : "\(i) s"
}

public func prefillBaseline(prefilling: Bool, wasPrefilling: Bool, current: Double?, prefilledTotal: Double?) -> Double? {
    guard prefilling else { return current }
    let validTotal = prefilledTotal.flatMap { $0.isFinite ? $0 : nil }
    return !wasPrefilling || current == nil ? validTotal : current
}

public func telemetryInt(_ value: Double?) -> Int {
    guard let value = value, value.isFinite else { return 0 }
    return Int(exactly: value.rounded(.towardZero)) ?? 0
}

public func rssBytesFromPsOutput(_ text: String) -> Int64? {
    guard let kib = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)),
          kib >= 0, kib <= Int64.max / 1024 else { return nil }
    return kib * 1024
}
