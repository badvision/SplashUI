// Pure launch decisions for SplashUI — no AppKit, unit-testable.
// Run the tests: ./run_tests.sh (compiles this file + Tests/main.swift).

import Foundation
import Darwin

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
// MARK: - config.json (S1a): JSON value language, serialization, schema, store

/// A generic JSON value — the file's value language. `options` is a flat map of
/// these (grouping is display-only, T10); unknown top-level keys are preserved as
/// these verbatim (forward-compat). Deliberately not Codable: both file formats
/// (pretty, canonical) come from the deterministic serializer below, which avoids
/// JSONEncoder's `240.0`-style double rendering.
public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Bridge Foundation/JSON values (NSDictionary/NSArray/NSNumber/NSNull, …) in.
    /// NSNumber is checked BEFORE Bool: in Swift an NSNumber from JSONSerialization
    /// bridges to Bool for ANY number, so JSON `1` would otherwise become `true`.
    /// JSON true/false and a Swift Bool both arrive as CFBoolean — the precise
    /// discriminator (a plain JSON number is __NSCFNumber, not a CFBoolean).
    public init(any: Any) {
        if any is NSNull { self = .null; return }
        if any is NSNumber {
            let n = any as! NSNumber
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else { self = .number(n.doubleValue) }
            return
        }
        if let b = any as? Bool { self = .bool(b); return }
        if let s = any as? String { self = .string(s); return }
        if let a = any as? [Any] { self = .array(a.map { JSONValue(any: $0) }); return }
        if let o = any as? [String: Any] { self = .object(o.mapValues { JSONValue(any: $0) }); return }
        self = .null
    }

    /// Bridge back out to Foundation JSON types (NSNull/Bool/Double/String/[Any]/[String: Any]).
    public var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map { $0.any }
        case .object(let o): return o.mapValues { $0.any }
        }
    }

    public var number: Double? { if case .number(let n) = self { return n }; return nil }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public subscript(key: String) -> JSONValue? { object?[key] }
}

func jsonString(_ value: JSONValue, indent: Int) -> String {
    func esc(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v == 0x22 { out += "\\\"" }
            else if v == 0x5C { out += "\\\\" }
            else if v == 0x0A { out += "\\n" }
            else if v == 0x0D { out += "\\r" }
            else if v == 0x09 { out += "\\t" }
            else if v == 0x08 { out += "\\b" }
            else if v == 0x0C { out += "\\f" }
            else if v < 0x20 { out += String(format: "\\u%04x", v) }
            else { out.unicodeScalars.append(scalar) }
        }
        return out + "\""
    }
    func num(_ n: Double) -> String {
        // Whole numbers render without a fractional part (240, not 240.0) — keeps
        // hand-inspectable files and the canonical gate stable.
        if n.isFinite, n == n.rounded(), abs(n) < 9_007_199_254_740_992 {
            return String(Int64(n))
        }
        return String(n)
    }
    var s = ""
    func render(_ v: JSONValue, depth: Int) {
        let pretty = indent >= 0
        let pad = pretty ? String(repeating: " ", count: depth * indent) : ""
        let padIn = pretty ? String(repeating: " ", count: (depth + 1) * indent) : ""
        let sep = pretty ? "\n" : ""
        let kv = pretty ? ": " : ":"
        switch v {
        case .null: s += "null"
        case .bool(let b): s += b ? "true" : "false"
        case .number(let n): s += num(n)
        case .string(let str): s += esc(str)
        case .array(let a):
            if a.isEmpty { s += "[]" }
            else {
                s += "[" + sep
                for (i, x) in a.enumerated() {
                    if i > 0 { s += "," + sep }
                    s += padIn
                    render(x, depth: depth + 1)
                }
                s += sep + pad + "]"
            }
        case .object(let o):
            let keys = o.keys.sorted()
            if keys.isEmpty { s += "{}" }
            else {
                s += "{" + sep
                for (i, k) in keys.enumerated() {
                    if i > 0 { s += "," + sep }
                    s += padIn + esc(k) + kv
                    render(o[k]!, depth: depth + 1)
                }
                s += sep + pad + "}"
            }
        }
    }
    render(value, depth: 0)
    return s
}

/// Compact deterministic form (sorted keys, no whitespace): the tick change-gate
/// compares these strings, so an unchanged config never re-sends `cfg`.
public func canonicalJSONString(_ value: JSONValue) -> String {
    jsonString(value, indent: -1)
}

/// The on-disk form: 2-space pretty, sorted keys, trailing newline.
public func prettyJSONString(_ value: JSONValue) -> String {
    jsonString(value, indent: 2) + "\n"
}

// MARK: - Config schema (contract C1, schema_version 1)

/// The app's config format version — NOT the engine version (that is detected per
/// kit from release.json, D16). v1 is the first version.
public let configSchemaVersion = 1

public struct ModelFolder: Equatable {
    public var id: String        // "lmstudio" | "ollama" | "hfhub" | "splash" | "installroot" | "u-<n>"
    public var path: String
    public var source: String    // "auto" | "manual"
    public init(id: String, path: String, source: String) {
        self.id = id; self.path = path; self.source = source
    }
}

public struct EngineCfg: Equatable {
    public var mode: String          // "auto" | "manual"
    public var manualPath: String?   // required when mode == "manual" (warned, never blocks)
    public var brew: Bool            // Homebrew rung of the discovery ladder (auto mode)
    public init(mode: String = "auto", manualPath: String? = nil, brew: Bool = true) {
        self.mode = mode; self.manualPath = manualPath; self.brew = brew
    }
}

public struct GlobalCfg: Equatable {
    public var engine: EngineCfg
    public var modelFolders: [ModelFolder]
    public var port: Int
    public var apiKey: String
    public init(engine: EngineCfg = EngineCfg(), modelFolders: [ModelFolder] = [],
                port: Int = 8123, apiKey: String = "splash-standalone-1") {
        self.engine = engine; self.modelFolders = modelFolders
        self.port = port; self.apiKey = apiKey
    }
}

public struct ProfileModel: Equatable {
    public var source: String   // a model_folders id, or "hfid" (id-only), or "none"
    public var id: String?      // owner/repo[:variant]; null for "none"
    public var dir: String?     // resolved on-disk dir (scan/save time); null for "hfid"
    public init(source: String, id: String? = nil, dir: String? = nil) {
        self.source = source; self.id = id; self.dir = dir
    }
}

public struct ProfileFailure: Equatable {
    public var at: String
    public var message: String
    public init(at: String, message: String) { self.at = at; self.message = message }
}

public struct ProfileMeta: Equatable {
    public var createdAt: String?
    public var lastUsedAt: String?
    public var lastSuccessfulLaunch: String?
    public var lastFailure: ProfileFailure?
    public init(createdAt: String? = nil, lastUsedAt: String? = nil,
                lastSuccessfulLaunch: String? = nil, lastFailure: ProfileFailure? = nil) {
        self.createdAt = createdAt; self.lastUsedAt = lastUsedAt
        self.lastSuccessfulLaunch = lastSuccessfulLaunch; self.lastFailure = lastFailure
    }
}

public struct Profile: Equatable {
    public var id: String
    public var name: String
    public var model: ProfileModel
    /// Flat OptionDef-keyed value map (T10 — grouping is display-only). Unknown keys
    /// are KEPT on load (a value saved under a newer mapping must survive a downgrade);
    /// S7 renders them stale (shown-disabled), never an error.
    public var options: [String: JSONValue]
    public var meta: ProfileMeta
    public init(id: String, name: String, model: ProfileModel,
                options: [String: JSONValue] = [:], meta: ProfileMeta = ProfileMeta()) {
        self.id = id; self.name = name; self.model = model
        self.options = options; self.meta = meta
    }
}

public struct ConfigDoc: Equatable {
    public var globals: GlobalCfg
    public var profiles: [Profile]
    public var activeProfile: String?
    /// Unknown top-level keys, preserved verbatim on save (forward-compat).
    public var reserved: [String: JSONValue]
    public init(globals: GlobalCfg = GlobalCfg(), profiles: [Profile] = [],
                activeProfile: String? = nil, reserved: [String: JSONValue] = [:]) {
        self.globals = globals; self.profiles = profiles
        self.activeProfile = activeProfile; self.reserved = reserved
    }
}

/// The {ok, errors, warnings} shape that config.save / config.validate reply with
/// (one tick of `cfg.result`, then nulled).
public struct ConfigSaveResult: Equatable {
    public var ok: Bool
    public var errors: [String]
    public var warnings: [String]
    public init(ok: Bool, errors: [String] = [], warnings: [String] = []) {
        self.ok = ok; self.errors = errors; self.warnings = warnings
    }
}

/// Why a config file could not be used.
public enum ConfigLoadError: Equatable {
    /// Corrupt: unparseable JSON, or a known field with a wrong type / rule violation.
    /// The file is left untouched; the caller keeps last-good or the defaults.
    case invalidFormat(String)
    /// The file is a newer schema version: load read-only, never write (forward data).
    case versionTooNew(fileVersion: Int, appVersion: Int)
}
// MARK: - Parse / migrate / serialize

/// Strict (same-version) and lenient (forward-version) readers for known fields.
/// Missing or null -> the field's default. Present but wrong-typed -> corrupt in
/// strict mode, degraded to the default in lenient mode (forward data is never
/// destroyed; the file just isn't understood by this app).
private struct ConfigParser {
    /// Unknown keys encountered inside known containers (dropped on save; reported
    /// for a one-shot console log — the file's data is never silently lost in place).
    var dropped: [String] = []
    var lenient = false

    enum DecodeError: Error, Equatable {
        case badType(String)
        case badValue(String)
    }

    private func str(_ v: JSONValue?, _ path: String, def: String? = nil) throws -> String? {
        guard let v = v, v != .null else { return def }
        if let s = v.string { return s }
        if !lenient { throw DecodeError.badType("\(path) must be a string") }
        return def
    }
    private func int(_ v: JSONValue?, _ path: String, def: Int? = nil) throws -> Int? {
        guard let v = v, v != .null else { return def }
        if let n = v.number, n.isFinite, n == n.rounded(), abs(n) < 9_007_199_254_740_992 {
            return Int(n)
        }
        if !lenient { throw DecodeError.badType("\(path) must be an integer") }
        return def
    }
    private func bool(_ v: JSONValue?, _ path: String, def: Bool? = nil) throws -> Bool? {
        guard let v = v, v != .null else { return def }
        if let b = v.bool { return b }
        if !lenient { throw DecodeError.badType("\(path) must be a boolean") }
        return def
    }
    private func obj(_ v: JSONValue?, _ path: String) throws -> [String: JSONValue]? {
        guard let v = v, v != .null else { return nil }
        if let o = v.object { return o }
        if !lenient { throw DecodeError.badType("\(path) must be an object") }
        return nil
    }
    private func arr(_ v: JSONValue?, _ path: String) throws -> [JSONValue]? {
        guard let v = v, v != .null else { return nil }
        if let a = v.array { return a }
        if !lenient { throw DecodeError.badType("\(path) must be an array") }
        return nil
    }
    private mutating func collectDropped(_ o: [String: JSONValue], known: [String], under: String) {
        let knownSet = Set(known)
        for k in o.keys where !knownSet.contains(k) {
            dropped.append(under.isEmpty ? k : under + "." + k)
        }
    }

    private mutating func decodeEngine(_ v: JSONValue?) throws -> EngineCfg {
        guard let e = try obj(v, "globals.engine") else { return EngineCfg() }
        var mode = "auto"
        if let m = try str(e["mode"], "globals.engine.mode", def: "auto") { mode = m }
        if mode != "auto" && mode != "manual" {
            if !lenient { throw DecodeError.badValue("globals.engine.mode must be \"auto\" or \"manual\"") }
        }
        let manualPath = try str(e["manual_path"], "globals.engine.manual_path")
        let brew = (try bool(e["brew"], "globals.engine.brew", def: true)) ?? true
        collectDropped(e, known: ["mode", "manual_path", "brew"], under: "globals.engine")
        return EngineCfg(mode: mode, manualPath: manualPath, brew: brew)
    }

    private mutating func decodeGlobals(_ v: JSONValue?) throws -> GlobalCfg {
        var engine = EngineCfg()
        var folders = [ModelFolder]()
        var port = 8123
        var apiKey = "splash-standalone-1"
        guard let g = try obj(v, "globals") else {
            return GlobalCfg(engine: engine, modelFolders: folders, port: port, apiKey: apiKey)
        }
        engine = try decodeEngine(g["engine"])
        if let f = try arr(g["model_folders"], "globals.model_folders") {
            var idx = 0
            for entry in f {
                guard let o = entry.object else {
                    if lenient { idx += 1; continue }
                    throw DecodeError.badType("globals.model_folders[\(idx)] must be an object")
                }
                let id = try str(o["id"], "globals.model_folders[\(idx)].id")
                let path = try str(o["path"], "globals.model_folders[\(idx)].path")
                guard id != nil, path != nil else {
                    dropped.append("globals.model_folders[\(idx)] (missing id or path)")
                    idx += 1
                    continue
                }
                let source = (try str(o["source"], "globals.model_folders[\(idx)].source", def: "auto")) ?? "auto"
                collectDropped(o, known: ["id", "path", "source"], under: "globals.model_folders[\(idx)]")
                folders.append(ModelFolder(id: id!, path: path!, source: source))
                idx += 1
            }
        }
        port = (try int(g["port"], "globals.port", def: 8123)) ?? 8123
        apiKey = (try str(g["api_key"], "globals.api_key", def: "splash-standalone-1")) ?? "splash-standalone-1"
        collectDropped(g, known: ["engine", "model_folders", "port", "api_key"], under: "globals")
        // Strict field rules (the data contract) — enforced on same-version files;
        // a forward file degrades leniently instead.
        if !lenient {
            if !(1...65535).contains(port) {
                throw DecodeError.badValue("globals.port must be between 1 and 65535 (got \(port))")
            }
            if apiKey.isEmpty { throw DecodeError.badValue("globals.api_key must not be empty") }
        }
        return GlobalCfg(engine: engine, modelFolders: folders, port: port, apiKey: apiKey)
    }

    private mutating func decodeProfiles(_ v: JSONValue?) throws -> [Profile] {
        guard let list = try arr(v, "profiles") else { return [] }
        var out = [Profile]()
        var idx = 0
        for entry in list {
            guard let o = entry.object else {
                if lenient { idx += 1; continue }
                throw DecodeError.badType("profiles[\(idx)] must be an object")
            }
            let id = try str(o["id"], "profiles[\(idx)].id")
            let name = (try str(o["name"], "profiles[\(idx)].name", def: "")) ?? ""
            guard id != nil else {
                dropped.append("profiles[\(idx)] (missing id)")
                idx += 1
                continue
            }
            var source = "none"
            var modelId: String? = nil
            var modelDir: String? = nil
            if let m = try obj(o["model"], "profiles[\(idx)].model") {
                if let s = try str(m["source"], "profiles[\(idx)].model.source", def: "none") { source = s }
                modelId = try str(m["id"], "profiles[\(idx)].model.id")
                modelDir = try str(m["dir"], "profiles[\(idx)].model.dir")
                collectDropped(m, known: ["source", "id", "dir"], under: "profiles[\(idx)].model")
            }
            var options: [String: JSONValue] = [:]
            if let opts = try obj(o["options"], "profiles[\(idx)].options") {
                options = opts   // unknown option keys are KEPT (stale is S7; never dropped)
            }
            var meta = ProfileMeta()
            if let me = try obj(o["meta"], "profiles[\(idx)].meta") {
                let createdAt = try str(me["created_at"], "profiles[\(idx)].meta.created_at")
                let lastUsedAt = try str(me["last_used_at"], "profiles[\(idx)].meta.last_used_at")
                let lastSuccess = try str(me["last_successful_launch"], "profiles[\(idx)].meta.last_successful_launch")
                var lastFailure: ProfileFailure? = nil
                if let f = try obj(me["last_failure"], "profiles[\(idx)].meta.last_failure") {
                    let at = try str(f["at"], "profiles[\(idx)].meta.last_failure.at")
                    let message = try str(f["message"], "profiles[\(idx)].meta.last_failure.message")
                    if at != nil || message != nil {
                        lastFailure = ProfileFailure(at: at ?? "", message: message ?? "")
                    }
                    collectDropped(f, known: ["at", "message"], under: "profiles[\(idx)].meta.last_failure")
                }
                meta = ProfileMeta(createdAt: createdAt, lastUsedAt: lastUsedAt,
                                   lastSuccessfulLaunch: lastSuccess, lastFailure: lastFailure)
                collectDropped(me, known: ["created_at", "last_used_at", "last_successful_launch", "last_failure"],
                               under: "profiles[\(idx)].meta")
            }
            collectDropped(o, known: ["id", "name", "model", "options", "meta"], under: "profiles[\(idx)]")
            out.append(Profile(id: id!, name: name,
                               model: ProfileModel(source: source, id: modelId, dir: modelDir),
                               options: options, meta: meta))
            idx += 1
        }
        return out
    }

    mutating func parse(top: [String: JSONValue]) throws -> ConfigDoc {
        let globals = try decodeGlobals(top["globals"])
        let profiles = try decodeProfiles(top["profiles"])
        var active: String? = nil
        if let a = top["active_profile"], a != .null {
            active = try str(a, "active_profile")
        }
        var reserved: [String: JSONValue] = [:]
        let knownTop: Set<String> = ["schema_version", "globals", "profiles", "active_profile"]
        for (k, v) in top where !knownTop.contains(k) { reserved[k] = v }
        return ConfigDoc(globals: globals, profiles: profiles, activeProfile: active, reserved: reserved)
    }
}

/// Parse a config.json byte stream.
///
/// - Missing known fields degrade to their documented defaults (a hand-edited file
///   is recoverable); a KNOWN field with a wrong type or rule violation is corrupt.
/// - `schema_version` absent -> 1 (the first version); non-integer -> corrupt.
/// - `version < app` -> the ordered migrator runs (v1: identity).
/// - `version > app` -> lenient read-only doc (nil when even that fails) + `.versionTooNew`;
///   the file is never written back.
/// - corrupt -> `doc == nil` + `.invalidFormat` (the store keeps last-good or defaults;
///   the file is left untouched).
public func parseConfig(_ data: Data) -> (doc: ConfigDoc?, error: ConfigLoadError?, droppedKeys: [String]) {
    let tree: JSONValue
    do {
        tree = JSONValue(any: try JSONSerialization.jsonObject(with: data, options: []))
    } catch {
        return (nil, .invalidFormat("config.json is not valid JSON: \(error.localizedDescription)"), [])
    }
    guard let top = tree.object else {
        return (nil, .invalidFormat("config.json: the top level must be a JSON object"), [])
    }
    var fileVersion = 1
    if let sv = top["schema_version"], sv != .null {
        if let n = sv.number, n.isFinite, n == n.rounded(), n >= 0 {
            fileVersion = Int(n)
        } else {
            return (nil, .invalidFormat("config.json: schema_version must be a non-negative integer"), [])
        }
    }
    if fileVersion > configSchemaVersion {
        var p = ConfigParser()
        p.lenient = true
        let doc = try? p.parse(top: top)
        return (doc, .versionTooNew(fileVersion: fileVersion, appVersion: configSchemaVersion), p.dropped)
    }
    var p = ConfigParser()
    do {
        let doc = try p.parse(top: top)
        let migrated = migrate(doc, from: max(1, fileVersion), to: configSchemaVersion)
        return (migrated, nil, p.dropped)
    } catch let e as ConfigParser.DecodeError {
        let message: String
        switch e {
        case .badType(let m), .badValue(let m): message = "config.json: \(m)"
        }
        return (nil, .invalidFormat(message), p.dropped)
    } catch {
        return (nil, .invalidFormat("config.json: invalid format"), p.dropped)
    }
}

/// Ordered schema migrator: runs the version steps `from -> from+1 -> … -> to`.
/// v1 is the first version, so there is nothing to do yet (identity). Future
/// schema versions add one step each.
public func migrate(_ doc: ConfigDoc, from version: Int, to target: Int) -> ConfigDoc {
    guard version < target else { return doc }
    var d = doc
    var v = max(1, version)   // pre-v1 clamps to v1 (the first version)
    while v < target {
        d = migrateStep(d, from: v)
        v += 1
    }
    return d
}

/// One migration step: schema version `v` -> `v + 1`. v1 is the first version,
/// so the step is the identity; future schema versions add their step here
/// (the migrator runs the steps in order, v1 -> v2 -> …).
private func migrateStep(_ doc: ConfigDoc, from v: Int) -> ConfigDoc {
    switch v {
    case 1: break   // v1 -> v2 (when v2 exists) lands here.
    default: break
    }
    return doc
}

/// Serialize a doc to file bytes: stamps the current `schema_version`, preserves
/// unknown top-level keys verbatim (forward-compat), pretty-prints with sorted keys.
public func configData(_ doc: ConfigDoc, schemaVersion: Int = configSchemaVersion) -> Data {
    var top: [String: JSONValue] = [
        "schema_version": .number(Double(schemaVersion)),
        "globals": .object([
            "engine": .object([
                "mode": .string(doc.globals.engine.mode),
                "manual_path": doc.globals.engine.manualPath.map(JSONValue.string) ?? .null,
                "brew": .bool(doc.globals.engine.brew),
            ]),
            "model_folders": .array(doc.globals.modelFolders.map {
                .object(["id": .string($0.id), "path": .string($0.path), "source": .string($0.source)])
            }),
            "port": .number(Double(doc.globals.port)),
            "api_key": .string(doc.globals.apiKey),
        ]),
        "profiles": .array(doc.profiles.map { p -> JSONValue in
            .object([
                "id": .string(p.id),
                "name": .string(p.name),
                "model": .object([
                    "source": .string(p.model.source),
                    "id": p.model.id.map(JSONValue.string) ?? .null,
                    "dir": p.model.dir.map(JSONValue.string) ?? .null,
                ]),
                "options": .object(p.options),
                "meta": .object([
                    "created_at": p.meta.createdAt.map(JSONValue.string) ?? .null,
                    "last_used_at": p.meta.lastUsedAt.map(JSONValue.string) ?? .null,
                    "last_successful_launch": p.meta.lastSuccessfulLaunch.map(JSONValue.string) ?? .null,
                    "last_failure": p.meta.lastFailure.map { .object(["at": .string($0.at), "message": .string($0.message)]) } ?? .null,
                ]),
            ])
        }),
        "active_profile": doc.activeProfile.map(JSONValue.string) ?? .null,
    ]
    for (k, v) in doc.reserved where top[k] == nil {
        top[k] = v
    }
    return Data(prettyJSONString(.object(top)).utf8)
}

/// The documented defaults, encoded as data (D9): the app reads no `SPLASH_*`
/// environment variable anywhere — these ARE the 9 vars' documented values.
/// Regression anchor for S2a's byte-identical 1.3.0 argv: port 8123, key
/// `splash-standalone-1`, `--persistent-cache --max-cache-disk 100g
/// --idle-release 240m`, ANE on, the 5 auto model roots, the documented model.
public func defaultConfig(home: String, now: Date = Date()) -> ConfigDoc {
    let folders = [
        ModelFolder(id: "lmstudio", path: home + "/.lmstudio/models", source: "auto"),
        ModelFolder(id: "ollama", path: home + "/.ollama/models", source: "auto"),
        ModelFolder(id: "hfhub", path: home + "/.cache/huggingface/hub", source: "auto"),
        ModelFolder(id: "splash", path: home + "/Library/Application Support/Splash/models", source: "auto"),
        ModelFolder(id: "installroot", path: home + "/SplashUI/models", source: "auto"),
    ]
    let globals = GlobalCfg(
        engine: EngineCfg(mode: "auto", manualPath: nil, brew: true),
        modelFolders: folders, port: 8123, apiKey: "splash-standalone-1")
    // The app's historical per-profile flag set (the 9 vars' documented behavior).
    let options: [String: JSONValue] = [
        "persistent_cache": .bool(true),
        "max_cache_disk": .string("100g"),
        "idle_release": .string("240m"),
        "ane": .bool(true),
    ]
    let iso = ISO8601DateFormatter()
    let id = appProfileId(now: now)
    let profile = Profile(
        id: id, name: "Default",
        model: ProfileModel(source: "lmstudio", id: "incoai/Qwen3.8-27B-Splash", dir: nil),
        options: options,
        meta: ProfileMeta(createdAt: iso.string(from: now)))
    return ConfigDoc(globals: globals, profiles: [profile], activeProfile: id, reserved: [:])
}

/// App-generated profile id: `p-<unix-ms>-<rand4>` (not user-editable).
private func appProfileId(now: Date) -> String {
    let ms = Int(now.timeIntervalSince1970 * 1000)
    var g = SystemRandomNumberGenerator()
    let hex = "0123456789abcdef"
    var suffix = ""
    for _ in 0..<4 {
        suffix.append(hex[hex.index(hex.startIndex, offsetBy: Int.random(in: 0..<16, using: &g))])
    }
    return "p-\(ms)-\(suffix)"
}

// MARK: - Save validation / normalization / masking

/// Strict (blocking) + soft rules for a candidate document.
/// Blocking: empty profile name, out-of-range port, empty api key, duplicate names.
/// Warnings (never block — D4 spirit): dangling active_profile, manual mode
/// without a path. The planLaunch dry-run (launch-combo warnings) lands in S4.
public func validateConfig(_ doc: ConfigDoc) -> ConfigSaveResult {
    var errors = [String]()
    var warnings = [String]()
    if !(1...65535).contains(doc.globals.port) {
        errors.append("globals.port must be between 1 and 65535 (got \(doc.globals.port))")
    }
    if doc.globals.apiKey.isEmpty {
        errors.append("globals.api_key must not be empty")
    }
    var seen = Set<String>()
    var dups = [String]()
    for p in doc.profiles {
        if p.name.isEmpty { errors.append("profile \(p.id) has an empty name") }
        if !seen.insert(p.name).inserted, !dups.contains(p.name) { dups.append(p.name) }
    }
    if !dups.isEmpty {
        errors.append("duplicate profile name(s): " + dups.joined(separator: ", "))
    }
    if let a = doc.activeProfile, !doc.profiles.contains(where: { $0.id == a }) {
        warnings.append("active_profile references an unknown profile id — it will be ignored")
    }
    if doc.globals.engine.mode == "manual", (doc.globals.engine.manualPath ?? "").isEmpty {
        warnings.append("engine mode is manual but no engine path is set — the engine will not resolve")
    }
    return ConfigSaveResult(ok: errors.isEmpty, errors: errors, warnings: warnings)
}

/// Normalize: a dangling `active_profile` becomes null ("treated as null", §2.1);
/// the returned flag rides in `cfg.active_invalid`.
public func normalizeConfig(_ doc: ConfigDoc) -> (doc: ConfigDoc, activeInvalid: Bool) {
    var d = doc
    var invalid = false
    if let a = d.activeProfile, !d.profiles.contains(where: { $0.id == a }) {
        d.activeProfile = nil
        invalid = true
    }
    return (d, invalid)
}

/// Tick-safe rendering of a secret: length + first/last 4 chars. The raw value
/// never appears in tick payloads, logs, or the panel (D6).
public func maskSecret(_ s: String) -> String {
    let n = s.count
    guard n >= 8 else { return "\(n) ch · •••" }
    return "\(n) ch · \(s.prefix(4))…\(s.suffix(4))"
}

// MARK: - Tick payload (contract C4 `j.cfg`, S1a scope)

/// Build the tick's `j.cfg` sub-object from the store's state. In S1a it reflects
/// the config store (not yet the launch plan); the fields later stories own ride
/// along as nulls so the change-gate stays stable until they fill in:
/// engine.resolved/version/tried/valid/error (S3), mapping_fallback/mapping_used
/// (S2a), registry_report (S2b/S4), first_run (S1b), restart_required/reason (S3/S4),
/// picked (S5). The raw api_key never appears — only its mask (D6).
public func configTickPayload(
    doc: ConfigDoc,
    loadError: String?,
    versionTooNew: Bool,
    activeInvalid: Bool,
    firstRun: Bool,
    inFlight: Int,
    result: ConfigSaveResult?
) -> [String: Any] {
    let engine: [String: Any] = [
        "mode": doc.globals.engine.mode,
        "manual_path": doc.globals.engine.manualPath ?? NSNull(),
        "brew": doc.globals.engine.brew,
        "resolved": NSNull(), "version": NSNull(), "tried": NSNull(),
        "valid": NSNull(), "error": NSNull(),
    ]
    let folders: [Any] = doc.globals.modelFolders.map { f -> [String: Any] in
        ["id": f.id, "path": f.path, "source": f.source,
         "models": [Any](), "scanning": false, "error": NSNull()]
    }
    let profiles: [Any] = doc.profiles.map { p -> [String: Any] in
        ["id": p.id, "name": p.name,
         "model": ["source": p.model.source,
                   "id": p.model.id ?? NSNull(),
                   "dir": p.model.dir ?? NSNull()] as [String: Any],
         "options": p.options.mapValues { $0.any },
         "meta": ["created_at": p.meta.createdAt ?? NSNull(),
                  "last_used_at": p.meta.lastUsedAt ?? NSNull(),
                  "last_successful_launch": p.meta.lastSuccessfulLaunch ?? NSNull(),
                  "last_failure": p.meta.lastFailure.map { ["at": $0.at, "message": $0.message] } ?? NSNull()] as [String: Any],
         "eligibility": NSNull(), "eligibility_reason": NSNull(), "unrunnable_fix": NSNull()]
    }
    var out: [String: Any] = [
        "load_error": loadError ?? NSNull(),
        "version_too_new": versionTooNew,
        "engine": engine,
        "folders": folders,
        "port": doc.globals.port,
        "api_key_masked": maskSecret(doc.globals.apiKey),
        "profiles": profiles,
        "active_profile": doc.activeProfile ?? NSNull(),
        "active_invalid": activeInvalid,
        "mapping_fallback": NSNull(),
        "mapping_used": NSNull(),
        "registry_report": NSNull(),
        "first_run": firstRun,
        "restart_required": NSNull(),
        "restart_reason": NSNull(),
        "in_flight": inFlight,
        "result": result.map { ["ok": $0.ok, "errors": $0.errors as Any, "warnings": $0.warnings as Any] } ?? NSNull(),
        "picked": NSNull(),
    ]
    if !doc.reserved.isEmpty {
        // Reserved top-level keys ride along so the JS draft can carry them
        // through config.save (the file never loses forward data in a round-trip).
        out["reserved"] = doc.reserved.mapValues { $0.any }
    }
    return out
}
// MARK: - ConfigStore: the single owner of config.json (D1, R8)

/// Owns `~/Library/Application Support/SplashUI/config.json`:
/// - loads at app start, BEFORE the first engine launch (D1 — load must not block
///   launch; the file is small and read synchronously once);
/// - keeps the in-memory doc as the single source of truth (D9);
/// - is the ONLY code path that writes the file (R8 single-writer; the API key
///   makes this a 0600 file in a 0700 dir);
/// - writes atomically: tmp in the same dir -> fsync -> chmod 0600 -> rename(2).
///
/// All FS access goes through injected closures (T1), so the whole load/save/
/// corrupt/last-good/version-too-new state machine is unit-testable without AppKit.
/// Main-thread only (the app reads it from the bridge handler and the 1 s tick).
public final class ConfigStore {
    public static let dirName = "SplashUI"
    public static let fileName = "config.json"

    public let home: String
    public let path: String
    public let dir: String

    /// The in-memory doc — the single source of truth for the running app.
    public var doc: ConfigDoc
    /// Human-readable reason the file could not be loaded (a corrupt file). nil when healthy.
    public var loadError: String?
    /// The file on disk is a newer schema version: the store is read-only.
    public var versionTooNew = false
    /// The file's schema version as read at load (nil when the file was unreadable).
    public private(set) var fileVersion: Int?
    /// The persisted `active_profile` referenced an unknown profile id.
    public var activeInvalid = false
    /// The first-run seed ran this launch (S1b sets it; the tick consumes it one-shot).
    public var firstRun = false
    /// The last save/validate result, stamped for one tick of `cfg.result` (then nulled).
    public var saveResult: ConfigSaveResult?

    private var lastGood: ConfigDoc?
    private var loggedDropped = Set<String>()

    private let read: (String) -> Data?
    private let write: (Data, String) -> Bool
    private let ensureDir: (String, Int) -> Bool

    public init(home: String,
                path: String? = nil,
                read: @escaping (String) -> Data? = ConfigStore.defaultRead,
                write: @escaping (Data, String) -> Bool = ConfigStore.defaultWrite,
                ensureDir: @escaping (String, Int) -> Bool = ConfigStore.defaultEnsureDir) {
        self.home = home
        self.path = path ?? home + "/Library/Application Support/SplashUI/" + ConfigStore.fileName
        self.dir = (self.path as NSString).deletingLastPathComponent
        self.read = read
        self.write = write
        self.ensureDir = ensureDir
        self.doc = defaultConfig(home: home)
        self.load()
    }

    // MARK: Load

    /// (Re)load the file. Absent file -> in-memory documented defaults, no write
    /// (the first-run seed write is S1b; single-writer rule: only config.save writes).
    /// Corrupt file -> last-good (or the defaults) + `loadError`; the file is left
    /// untouched (a next valid save repairs it). Newer version -> read-only doc.
    public func load() {
        _ = ensureDir(dir, 0o700)
        guard let data = read(path) else {
            doc = defaultConfig(home: home)
            loadError = nil
            versionTooNew = false
            fileVersion = nil
            activeInvalid = false
            lastGood = doc
            return
        }
        let (parsed, error, dropped) = parseConfig(data)
        for k in dropped where !loggedDropped.contains(k) {
            loggedDropped.insert(k)
            NSLog("SplashUI config: dropping unknown key '\(k)' from config.json")
        }
        switch error {
        case .versionTooNew(let f, _):
            // Forward data: show what parses (lenient), keep the file sacred.
            let (normalized, invalid) = normalizeConfig(parsed ?? defaultConfig(home: home))
            doc = normalized
            activeInvalid = invalid
            loadError = nil
            versionTooNew = true
            fileVersion = f
        case .invalidFormat(let message):
            doc = lastGood ?? defaultConfig(home: home)
            activeInvalid = false
            loadError = message
            versionTooNew = false
            fileVersion = nil
        case nil:
            guard let d = parsed else {
                doc = defaultConfig(home: home)
                return
            }
            let (normalized, invalid) = normalizeConfig(d)
            doc = normalized
            activeInvalid = invalid
            loadError = nil
            versionTooNew = false
            fileVersion = configSchemaVersion
            lastGood = normalized
        }
    }

    // MARK: Save (the single write path)

    /// Validate a candidate doc and write it atomically (tmp -> fsync -> 0600 ->
    /// rename). The ONLY path that writes the file (R8). A version-too-new store
    /// refuses (never destroy forward data). Returns the result stamp, which also
    /// rides one tick of `cfg.result` (consumed via `consumeSaveResult`).
    @discardableResult
    public func save(candidate: ConfigDoc) -> ConfigSaveResult {
        if versionTooNew {
            let v = fileVersion.map(String.init) ?? "?"
            let r = ConfigSaveResult(ok: false,
                errors: ["config file is schema version \(v) — newer than this app's v\(configSchemaVersion) — read-only, refusing to write"],
                warnings: [])
            saveResult = r
            return r
        }
        let v = validateConfig(candidate)
        guard v.ok else {
            saveResult = v
            return v
        }
        let (normalized, invalid) = normalizeConfig(candidate)
        _ = ensureDir(dir, 0o700)
        guard write(configData(normalized), path) else {
            let r = ConfigSaveResult(ok: false, errors: ["cannot write config file: \(path)"], warnings: v.warnings)
            saveResult = r
            return r
        }
        doc = normalized
        activeInvalid = invalid
        loadError = nil
        versionTooNew = false
        lastGood = normalized
        saveResult = ConfigSaveResult(ok: true, errors: [], warnings: v.warnings)
        return saveResult!
    }

    /// Save the current in-memory doc (metadata flush, D15).
    @discardableResult
    public func saveCurrent() -> ConfigSaveResult {
        save(candidate: doc)
    }

    /// `config.save` bridge entry: parse the raw candidate doc (strict), validate, write.
    @discardableResult
    public func saveCandidate(_ data: Data) -> ConfigSaveResult {
        let (parsed, error, _) = parseConfig(data)
        if let error = error {
            let r = ConfigSaveResult(ok: false, errors: [Self.message(for: error)], warnings: [])
            saveResult = r
            return r
        }
        guard let d = parsed else {
            let r = ConfigSaveResult(ok: false, errors: ["invalid config document"], warnings: [])
            saveResult = r
            return r
        }
        return save(candidate: d)
    }

    /// `config.validate` bridge entry: the same rules, no write (JS debounces 400 ms).
    @discardableResult
    public func validateCandidate(_ data: Data) -> ConfigSaveResult {
        let (parsed, error, _) = parseConfig(data)
        if let error = error {
            return ConfigSaveResult(ok: false, errors: [Self.message(for: error)], warnings: [])
        }
        guard let d = parsed else {
            return ConfigSaveResult(ok: false, errors: ["invalid config document"], warnings: [])
        }
        return validateConfig(normalizeConfig(d).doc)
    }

    private static func message(for error: ConfigLoadError) -> String {
        switch error {
        case .invalidFormat(let m): return m
        case .versionTooNew(let f, let a):
            return "config is schema version \(f), newer than this app's v\(a) — read-only, refusing to write"
        }
    }

    /// Consume the one-shot result stamp (the tick picks it up; it is then nulled).
    public func consumeSaveResult() -> ConfigSaveResult? {
        defer { saveResult = nil }
        return saveResult
    }

    // MARK: Real-FS defaults (injectable in tests)

    public static func defaultRead(_ path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    public static func defaultEnsureDir(_ path: String, _ mode: Int) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            guard isDir.boolValue else { return false }
        } else {
            do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
            catch { return false }
        }
        // The dir holds the API key: 0700 even when it pre-existed with a wider mode.
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
        return true
    }

    /// Atomic write: create the tmp file in the SAME directory, write, fsync, chmod
    /// 0600 (before the rename, so the target is never world-readable), then
    /// rename(2) over the target. A crash at any point leaves either the old file
    /// or the complete new one — never a partial 0600 file.
    public static func defaultWrite(_ data: Data, _ path: String) -> Bool {
        let tmp = path + ".tmp"
        FileManager.default.createFile(atPath: tmp, contents: data)
        guard let fh = FileHandle(forWritingAtPath: tmp) else {
            try? FileManager.default.removeItem(atPath: tmp)
            return false
        }
        do { try fh.synchronize() } catch {   // fsync: the bytes hit the disk before the rename
            fh.closeFile()
            try? FileManager.default.removeItem(atPath: tmp)
            return false
        }
        fh.closeFile()
        guard chmod(tmp, 0o600) == 0 else {
            try? FileManager.default.removeItem(atPath: tmp)
            return false
        }
        guard rename(tmp, path) == 0 else {   // rename(2): atomic within the same directory
            try? FileManager.default.removeItem(atPath: tmp)
            return false
        }
        return true
    }
}
