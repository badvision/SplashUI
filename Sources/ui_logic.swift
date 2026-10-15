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
// MARK: - Engine kit resolution (S3: extracted from resolveSplashPaths, D2/D9/D16)

/// The outcome of the engine-kit discovery ladder. `tried` carries every rung
/// checked (in order) so the miss error can name them (today's actionable-error
/// style). The version comes from the resolved kit's release.json (D16 —
/// detected, never user-set); nil when the kit's release.json is unreadable
/// (downstream, `contractFor` falls back).
public struct KitResolve: Equatable {
    public var kit: String?       // the resolved kit dir, or nil
    public var version: String?   // the resolved kit's release.json version
    public var tried: [String]    // every rung checked, in order
    public var error: String?     // actionable error text when kit == nil
}

/// The engine-kit ladder — the Auto discovery of D2, as a pure function.
///
/// Rungs, in order (D2: discovery ORDER, never version preference — a newer
/// engine is never auto-promoted over the one the active model package was
/// built against; that mismatch is the eligibility layer's verdict, S3):
/// 1. the manual engine path — only when `mode == "manual"` (it replaces rung 1
///    of the old env ladder; an incomplete manual kit is skipped, not fatal);
/// 2. the fixed install.sh layout: `~/SplashUI/kit/splash-1.3.0-arm64-macos26`
///    — the install.sh constants, hard-wired. D9: NO env reads — `SPLASHUI_HOME`
///    and `SPLASH_VERSION` are not user-facing, the rung is a constant, not a var;
/// 3. the Homebrew keg's `libexec` — only when the config's brew rung is enabled
///    (D10 seeds it from detection; S5 exposes it). The old gate (brew only when
///    no local model) is gone: in the config world the model is per-profile and
///    the engine global, so the ladder cannot consult it — a 1.3.1 keg under a
///    1.3.0 package model is refused by eligibility, with the 1.3.0 kit named.
///
/// A kit is the exact `isKit()` checks of the old code: a dir holding
/// `engine/splash` (executable) and a bundled `python/bin/python{,3}`. The first
/// VALID kit wins; every attempted rung is recorded for the error text.
/// PURE (T1): FS/detection through injected closures; no process env (D9).
public func resolveKit(engine: EngineCfg,
                       home: String,
                       isDir: (String) -> Bool,
                       isExecutable: (String) -> Bool,
                       brewKeg: () -> String? = { nil },
                       kitVersion: (String) -> String? = { _ in nil }) -> KitResolve {
    var tried: [String] = []
    var kit: String?
    func isKit(_ d: String) -> Bool {
        isDir(d) && isExecutable(d + "/engine/splash") &&
        (isExecutable(d + "/python/bin/python") || isExecutable(d + "/python/bin/python3"))
    }
    func tryKit(_ d: String) {
        guard !d.isEmpty else { return }
        tried.append(d)
        if kit == nil, isKit(d) { kit = d }
    }

    if engine.mode == "manual" {
        tryKit(engine.manualPath ?? "")
    }
    // The install.sh layout (install.sh's own constants — never app-read env):
    // <root>/kit/splash-<version>-arm64-macos26 with root = ~/SplashUI.
    tryKit(home + "/SplashUI/kit/splash-1.3.0-arm64-macos26")
    if engine.brew {
        if let b = brewKeg(), !b.isEmpty {
            tryKit(b + "/libexec")   // the keg's libexec IS the engine kit
        }
    }

    let version = kit.flatMap(kitVersion)
    var error: String?
    if kit == nil {
        let list = tried.isEmpty ? "(none)" : tried.joined(separator: ", ")
        error = "engine kit not found — no valid kit at: " + list +
            " — a kit needs engine/splash + python/bin/python{,3} — "
            + "point the engine at a kit folder in Settings (engine → manual), "
            + "or run `./install.sh`, or install via Homebrew (brew install incoai/tap/splash)"
    }
    return KitResolve(kit: kit, version: version, tried: tried, error: error)
}
// MARK: - Model classification + enumeration (S3: contract C3)

/// What a model directory (or an id-only model) is. C3: package/assembly/hfid/other.
public enum ModelKind: String, Equatable {
    /// A 1.3.0-format Splash package: `manifest.json` at the model root (the draft
    /// is baked in, `tokenizer/` + `draft/` subdirs). Only the module flavor (1.3.0)
    /// loads these; the 1.3.1+ engine refuses them ("Splash no longer loads").
    case package
    /// A Splash assembly: `model.json` + `config.json` at the root; the drafter
    /// lives in `draft/` (1.3.0: `draft/config.json` is required by ModelDescriptor.mm).
    case assembly
    /// A model identified by a Hugging Face id: an id-only selection, or a local
    /// copy of an HF repo (a plain config/weights or GGUF dir under an owner/repo
    /// id). Served BY THAT ID — positionally by the 1.3.0 module flavor (which
    /// then reads the local dir), download/symlink by the 1.3.1+ launcher.
    case hfid
    /// A local dir that is neither package nor assembly and carries no HF id
    /// (owner/repo): no flavor can name or load it.
    case other
}

/// The presence of the files/dirs the classifier and the eligibility table look
/// at (C3): `manifest.json`, `model.json`, `config.json`, `tokenizer/`, `draft/`,
/// `draft/config.json`. All of it is existence, read through the injected
/// closures (a nil dir leaves everything false).
public struct ModelDirFiles: Equatable {
    public var manifest: Bool
    public var modelJson: Bool
    public var config: Bool
    public var tokenizer: Bool
    public var draft: Bool
    public var draftConfig: Bool
    public init(manifest: Bool = false, modelJson: Bool = false, config: Bool = false,
                tokenizer: Bool = false, draft: Bool = false, draftConfig: Bool = false) {
        self.manifest = manifest
        self.modelJson = modelJson
        self.config = config
        self.tokenizer = tokenizer
        self.draft = draft
        self.draftConfig = draftConfig
    }
}

public func modelDirFiles(_ dir: String?,
                          isDir: (String) -> Bool,
                          fileContents: (String) -> String?) -> ModelDirFiles {
    guard let dir, !dir.isEmpty else { return ModelDirFiles() }
    return ModelDirFiles(
        manifest: fileContents(dir + "/manifest.json") != nil,
        modelJson: fileContents(dir + "/model.json") != nil,
        config: fileContents(dir + "/config.json") != nil,
        tokenizer: isDir(dir + "/tokenizer"),
        draft: isDir(dir + "/draft"),
        draftConfig: fileContents(dir + "/draft/config.json") != nil)
}

/// C3 classification: `package` (manifest.json wins) / `assembly` (model.json +
/// config.json) / `hfid` (id-only, or a local dir named by a full HF id — a plain
/// HF repo copy) / `other` (a local dir with no package/assembly marker and no
/// owner/repo id). A 1-component name is NOT an HF id (HF repos are owner/repo).
public func classifyModelDir(dir: String?,
                             id: String?,
                             isDir: (String) -> Bool,
                             fileContents: (String) -> String?) -> ModelKind {
    guard let dir, !dir.isEmpty else { return .hfid }   // an id-only model
    if fileContents(dir + "/manifest.json") != nil { return .package }
    if fileContents(dir + "/model.json") != nil && fileContents(dir + "/config.json") != nil {
        return .assembly
    }
    return id?.contains("/") == true ? .hfid : .other
}

/// One discovered model of a model folder (C3/C4: `cfg.folders[].models[]`).
/// `dir` is the on-disk dir the model loads from (nil: an ollama name — the
/// blobs are not a loadable model dir). `kind` is `classifyModelDir`'s verdict.
public struct ModelEntry: Equatable {
    public var id: String       // owner/repo (two-level roots), the repo name (1-level), or the ollama model name
    public var dir: String?
    public var source: String   // the model folder's id (lmstudio/hfhub/.../u-<n>)
    public var kind: ModelKind
    public init(id: String, dir: String? = nil, source: String, kind: ModelKind) {
        self.id = id
        self.dir = dir
        self.source = source
        self.kind = kind
    }
}

/// The per-dir enumeration bound (C3): the FIRST 200 entries in sort order,
/// hidden (dot-prefixed) entries skipped.
private func boundedEntries(_ names: [String]) -> [String] {
    names.sorted().filter { !$0.hasPrefix(".") }.prefix(200).map { $0 }
}

/// Enumerate one model folder's models (C3). PURE (T1): the folder's `path` is
/// the root; every FS access goes through the injected closures. Layout rules:
/// - `hfhub`: `models--<owner>--<repo>` dirs decode to `owner/repo`; the model
///   dir is `snapshots/<newest>` — `refs/main` names the current commit when
///   readable, else the last snapshot in sort order (ONE listing of snapshots/,
///   no recursion); a repo without snapshots is dropped; an empty hub -> [].
/// - `ollama`: the manifest paths under `manifests{,-v2}/registry.ollama.ai/
///   library/` become model names (no dir: the blobs are not loadable); an
///   empty library -> [] (NOT an error).
/// - `splash`: the launcher's selection links (install/models.py: models/
///   <owner>/<repo> symlinks; .selections/* hidden) — the two-level rule below,
///   symlinks followed by the injected closures, the link path is the dir.
/// - the two-level roots (lmstudio/installroot) and manual folders: a root entry
///   that looks like a model dir (a manifest.json/model.json/config.json marker
///   at its root) is a 1-level model (id = its name); a root entry without a
///   marker is an owner-like dir — its subdirs are the models (id = owner/repo;
///   depth <= 2, so anything deeper is not a model).
public func enumerateModels(folder: ModelFolder,
                            isDir: (String) -> Bool,
                            fileContents: (String) -> String?,
                            listDir: (String) -> [String]?) -> [ModelEntry] {
    let root = folder.path
    func entries(_ dir: String) -> [String] {
        guard let names = listDir(dir) else { return [] }
        return boundedEntries(names)
    }
    func kind(of dir: String?, id: String) -> ModelKind {
        classifyModelDir(dir: dir, id: id, isDir: isDir, fileContents: fileContents)
    }

    switch folder.id {
    case "hfhub":
        var out: [ModelEntry] = []
        for name in entries(root) where name.hasPrefix("models--") {
            let repoId = String(name.dropFirst("models--".count)).replacingOccurrences(of: "--", with: "/")
            let snapsDir = root + "/" + name + "/snapshots"
            guard let snaps = listDir(snapsDir) else { continue }
            let snapsB = boundedEntries(snaps)
            guard !snapsB.isEmpty else { continue }
            var snap: String?
            if let ref = fileContents(root + "/" + name + "/refs/main") {
                let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
                if snapsB.contains(trimmed) { snap = trimmed }
            }
            if snap == nil { snap = snapsB.last }
            guard let s = snap else { continue }
            out.append(ModelEntry(id: repoId, dir: snapsDir + "/" + s,
                                  source: folder.id, kind: kind(of: snapsDir + "/" + s, id: repoId)))
        }
        return out
    case "ollama":
        var names = Set<String>()
        for base in ["manifests", "manifests-v2"] {
            for n in entries(root + "/" + base + "/registry.ollama.ai/library") {
                names.insert(n)
            }
        }
        return names.sorted().map {
            ModelEntry(id: $0, dir: nil, source: folder.id, kind: kind(of: nil, id: $0))
        }
    default:
        // lmstudio / installroot / splash / manual (u-<n>): the two-level rule.
        var out: [ModelEntry] = []
        for name in entries(root) {
            let p = root + "/" + name
            guard isDir(p) else { continue }
            let files = modelDirFiles(p, isDir: isDir, fileContents: fileContents)
            if files.manifest || files.modelJson || files.config {
                // a model dir directly under the root (1-level).
                out.append(ModelEntry(id: name, dir: p, source: folder.id, kind: kind(of: p, id: name)))
            } else if let kids = listDir(p) {
                // an owner-like dir: its subdirs are the models (2-level).
                for k in boundedEntries(kids) {
                    let kp = p + "/" + k
                    guard isDir(kp) else { continue }
                    out.append(ModelEntry(id: name + "/" + k, dir: kp,
                                          source: folder.id, kind: kind(of: kp, id: name + "/" + k)))
                }
            }
        }
        return out
    }
}


// MARK: - Versioned launch registry (contract C2, D3/D9/D16)
//
// The UI->CLI mapping is a HAND-AUTHORED registry keyed by the kit's release.json
// version (D3): one VersionContract per version, every OptionDef verified against
// the real kits' parsers (the 1.3.0 release kit, the 1.3.1 Homebrew keg, and the
// 1.3.2 GitHub tag). The installed kit's server/serve_options.py may be parsed to
// VALIDATE the mapping and pre-populate newly-detected flags (S2b) — it never
// emits argv. The contract/version is detected from release.json (D16), never a
// stored or user-set value.

/// How a kit's server is launched from its directory.
public enum LaunchFlavor: String, Equatable {
    /// 1.3.0 style: `python -u -m server.server <MODEL_DIR> --model <ID> ...` —
    /// the on-disk dir is the positional argument (reused, never re-downloaded).
    case module
    /// 1.3.1+: `python -u install/launcher.py serve --model <HF_ID> ...` — the
    /// launcher downloads the model by id (one-time), then execs the server.
    case launcher
}

/// One option a kit's server/launcher accepts, as the registry speaks it. The
/// registry is the ONLY argv source (D3); the UI renders from these and the
/// serve_options.py assist validates them (S2b).
public struct OptionDef: Equatable {
    public enum Kind: String, Equatable {
        case value   // `--flag VALUE` — one pair per value
        case bool    // `--flag` — bare when the key's value is true (argparse store_true)
        case append  // `--flag V1 --flag V2 ...` — one pair per element
    }
    public let flag: String        // "--max-cache-disk"
    public let key: String         // "max_cache_disk" (config.json options key; the UI field id)
    public let kind: Kind
    public let group: String       // the engine help group (network/memory/cache/api/requests/model)
    public let defValue: String?   // the engine's effective default as CLI text; nil = none ("auto")
    public let choices: [String]?  // allowed values (UI + save validation); nil = free-form
    public let secret: Bool        // reaches the child via env, NEVER on argv
    public let envVar: String?     // the env var name of a secret (SPLASH_API_KEY)
    public let requires: [String]  // keys that must be effectively enabled for this option to
                                   // be valid — the engine's own cross-checks (check_serve_arguments)
    public let appDefault: String? // a value the app injects when unset (host 127.0.0.1)
    public let alwaysEmit: Bool    // structural flags the app always passes (host/port)
    public let builtFromModel: Bool // the model trio: emitted from the launch model, not the values map
    public init(flag: String, key: String, kind: Kind, group: String,
                defValue: String? = nil, choices: [String]? = nil,
                secret: Bool = false, envVar: String? = nil,
                requires: [String] = [], appDefault: String? = nil,
                alwaysEmit: Bool = false, builtFromModel: Bool = false) {
        self.flag = flag
        self.key = key
        self.kind = kind
        self.group = group
        self.defValue = defValue
        self.choices = choices
        self.secret = secret
        self.envVar = envVar
        self.requires = requires
        self.appDefault = appDefault
        self.alwaysEmit = alwaysEmit
        self.builtFromModel = builtFromModel
    }
}

/// One hand-authored entry of the versioned launch registry (D3): everything the
/// app knows about driving a kit whose release.json says `version`.
public struct VersionContract: Equatable {
    public let version: String        // the release.json version ("1.3.0")
    public let flavor: LaunchFlavor
    public let options: [OptionDef]
    /// Model family -> the DFlash2 draft repo (1.3.1/1.3.2: the kits' verified
    /// install/families.py; 1.3.0: empty — no registry, the package bakes the draft).
    public let familyRegistry: [String: String]
    /// 1.3.2's suggested drafter models (1.3.0/1.3.1: none).
    public let suggestedModels: [String]
    /// config.json -> family rules (the app's plan-time knowledge of the
    /// engine's config->family registry; 1.3.0: none — packages bake the draft).
    public let familyRules: [FamilyRule]
    public init(version: String, flavor: LaunchFlavor, options: [OptionDef],
                familyRegistry: [String: String] = [:], suggestedModels: [String] = [],
                familyRules: [FamilyRule] = []) {
        self.version = version
        self.flavor = flavor
        self.options = options
        self.familyRegistry = familyRegistry
        self.familyRules = familyRules
        self.suggestedModels = suggestedModels
    }
    public func option(_ key: String) -> OptionDef? { options.first { $0.key == key } }
    public subscript(key: String) -> OptionDef? { option(key) }
}

/// The hand-authored registry (D3): one contract per release.json version.
public struct LaunchRegistry: Equatable {
    public let contracts: [String: VersionContract]
    public init(contracts: [String: VersionContract]) { self.contracts = contracts }
}

// The 23 shared flags exactly as the real kits declare them (the serve_options.py
// SERVE_OPTIONS tuple + the parser's --port). 1.3.0 and 1.3.1 use THE SAME list —
// verified: the installed keg's server/serve_options.py is byte-identical to the
// 1.3.0 kit's. The order reproduces today's resolveSplashPaths argv: host, port,
// key, then the cache axis as the app has always emitted it (persistent-cache,
// max-cache-disk, idle-release), the rest in the engine's help order, ANE last.
private let sharedOptions130_131: [OptionDef] = [
    OptionDef(flag: "--host", key: "host", kind: .value, group: "network",
              defValue: "127.0.0.1", appDefault: "127.0.0.1", alwaysEmit: true),
    OptionDef(flag: "--port", key: "port", kind: .value, group: "network",
              defValue: "8000", alwaysEmit: true),
    OptionDef(flag: "--api-key", key: "api_key", kind: .value, group: "network",
              secret: true, envVar: "SPLASH_API_KEY"),
    OptionDef(flag: "--persistent-cache", key: "persistent_cache", kind: .bool, group: "cache",
              defValue: "false", requires: ["max_cache_disk"]),
    OptionDef(flag: "--max-cache-disk", key: "max_cache_disk", kind: .value, group: "cache",
              defValue: "0"),
    OptionDef(flag: "--idle-release", key: "idle_release", kind: .value, group: "memory",
              defValue: "10m"),
    OptionDef(flag: "--allowed-host", key: "allowed_host", kind: .append, group: "network"),
    OptionDef(flag: "--allowed-origin", key: "allowed_origin", kind: .append, group: "network"),
    OptionDef(flag: "--no-webui", key: "no_webui", kind: .bool, group: "network", defValue: "false"),
    OptionDef(flag: "--max-memory", key: "max_memory", kind: .value, group: "memory", defValue: "auto"),
    OptionDef(flag: "--max-context", key: "max_context", kind: .value, group: "memory", defValue: "auto"),
    OptionDef(flag: "--kv-format", key: "kv_format", kind: .value, group: "memory",
              defValue: "int8", choices: ["int8", "bf16"]),
    OptionDef(flag: "--cache-dir", key: "cache_dir", kind: .value, group: "cache",
              requires: ["persistent_cache"]),
    OptionDef(flag: "--served-model-name", key: "served_model_name", kind: .append, group: "api"),
    OptionDef(flag: "--announce-served-name", key: "announce_served_name", kind: .bool, group: "api",
              defValue: "false", requires: ["served_model_name"]),
    OptionDef(flag: "--default-reasoning-effort", key: "reasoning_effort", kind: .value, group: "api",
              choices: ["none", "minimal", "low", "medium", "high", "xhigh", "max"]),
    OptionDef(flag: "--max-request-size", key: "max_request_size", kind: .value, group: "requests",
              defValue: "128M"),
    OptionDef(flag: "--max-image-pixels", key: "max_image_pixels", kind: .value, group: "requests",
              defValue: "4194304"),
    OptionDef(flag: "--request-timeout", key: "request_timeout", kind: .value, group: "requests"),
    OptionDef(flag: "--queue-size", key: "queue_size", kind: .value, group: "requests", defValue: "32"),
    OptionDef(flag: "--decode-share", key: "decode_share", kind: .value, group: "requests", defValue: "0.5"),
    OptionDef(flag: "--disable-ane", key: "ane", kind: .bool, group: "requests", defValue: "true"),
    OptionDef(flag: "--allow-idle-sleep", key: "allow_idle_sleep", kind: .bool, group: "requests",
              defValue: "false"),
]

// The 1.3.2 shared set (the real 1.3.2 tag's serve_options.py, diffed against the
// 1.3.1 keg): the same order with the 1.3.2 deltas in place — --max-cache-disk
// default 0 -> auto (<=32G free), + the 4 new flags inserted beside their
// relatives (--state-format after --kv-format, --max-cache-disk-writes after
// --max-cache-disk, the thinking pair after --default-reasoning-effort). The
// engine's cross-checks survive the semantics change: --persistent-cache still
// requires a non-zero --max-cache-disk (the 1.3.2 check is `== 0`, so the
// unset->auto default passes) and --cache-dir still needs --persistent-cache.
private let sharedOptions132: [OptionDef] = [
    OptionDef(flag: "--host", key: "host", kind: .value, group: "network",
              defValue: "127.0.0.1", appDefault: "127.0.0.1", alwaysEmit: true),
    OptionDef(flag: "--port", key: "port", kind: .value, group: "network",
              defValue: "8000", alwaysEmit: true),
    OptionDef(flag: "--api-key", key: "api_key", kind: .value, group: "network",
              secret: true, envVar: "SPLASH_API_KEY"),
    OptionDef(flag: "--persistent-cache", key: "persistent_cache", kind: .bool, group: "cache",
              defValue: "false", requires: ["max_cache_disk"]),
    OptionDef(flag: "--max-cache-disk", key: "max_cache_disk", kind: .value, group: "cache",
              defValue: "auto"),
    OptionDef(flag: "--max-cache-disk-writes", key: "max_cache_disk_writes", kind: .value, group: "cache",
              defValue: "0", requires: ["max_cache_disk"]),
    OptionDef(flag: "--idle-release", key: "idle_release", kind: .value, group: "memory",
              defValue: "10m"),
    OptionDef(flag: "--allowed-host", key: "allowed_host", kind: .append, group: "network"),
    OptionDef(flag: "--allowed-origin", key: "allowed_origin", kind: .append, group: "network"),
    OptionDef(flag: "--no-webui", key: "no_webui", kind: .bool, group: "network", defValue: "false"),
    OptionDef(flag: "--max-memory", key: "max_memory", kind: .value, group: "memory", defValue: "auto"),
    OptionDef(flag: "--max-context", key: "max_context", kind: .value, group: "memory", defValue: "auto"),
    OptionDef(flag: "--kv-format", key: "kv_format", kind: .value, group: "memory",
              defValue: "int8", choices: ["int8", "bf16"]),
    OptionDef(flag: "--state-format", key: "state_format", kind: .value, group: "memory",
              defValue: "fp32", choices: ["fp32", "bf16"]),
    OptionDef(flag: "--cache-dir", key: "cache_dir", kind: .value, group: "cache",
              requires: ["persistent_cache"]),
    OptionDef(flag: "--served-model-name", key: "served_model_name", kind: .append, group: "api"),
    OptionDef(flag: "--announce-served-name", key: "announce_served_name", kind: .bool, group: "api",
              defValue: "false", requires: ["served_model_name"]),
    OptionDef(flag: "--default-reasoning-effort", key: "reasoning_effort", kind: .value, group: "api",
              choices: ["none", "minimal", "low", "medium", "high", "xhigh", "max"]),
    OptionDef(flag: "--thinking-token-budget", key: "thinking_token_budget", kind: .value, group: "api"),
    OptionDef(flag: "--thinking-end-text", key: "thinking_end_text", kind: .value, group: "api"),
    OptionDef(flag: "--max-request-size", key: "max_request_size", kind: .value, group: "requests",
              defValue: "128M"),
    OptionDef(flag: "--max-image-pixels", key: "max_image_pixels", kind: .value, group: "requests",
              defValue: "4194304"),
    OptionDef(flag: "--request-timeout", key: "request_timeout", kind: .value, group: "requests"),
    OptionDef(flag: "--queue-size", key: "queue_size", kind: .value, group: "requests", defValue: "32"),
    OptionDef(flag: "--decode-share", key: "decode_share", kind: .value, group: "requests", defValue: "0.5"),
    OptionDef(flag: "--disable-ane", key: "ane", kind: .bool, group: "requests", defValue: "true"),
    OptionDef(flag: "--allow-idle-sleep", key: "allow_idle_sleep", kind: .bool, group: "requests",
              defValue: "false"),
]

// The model trio of each flavor. The model is always identified by its HF id
// regardless of flavor; the on-disk dir is used ONLY by the module flavor (it
// loads the dir positionally, never re-downloading; the launcher downloads).
let moduleModelOptions: [OptionDef] = [
    OptionDef(flag: "--model", key: "model", kind: .value, group: "model",
              alwaysEmit: true, builtFromModel: true),
    OptionDef(flag: "--tokenizer", key: "tokenizer", kind: .value, group: "model",
              alwaysEmit: true, builtFromModel: true),
    OptionDef(flag: "--binary", key: "binary", kind: .value, group: "model",
              alwaysEmit: true, builtFromModel: true),
]

let launcherModelOptions: [OptionDef] = [
    OptionDef(flag: "--model", key: "model", kind: .value, group: "model",
              alwaysEmit: true, builtFromModel: true),
    OptionDef(flag: "--revision", key: "revision", kind: .value, group: "model"),
    OptionDef(flag: "--draft-model", key: "draft_model", kind: .value, group: "model"),
    OptionDef(flag: "--language-only", key: "language_only", kind: .bool, group: "model", defValue: "false"),
    OptionDef(flag: "--offline", key: "offline", kind: .bool, group: "model", defValue: "false"),
]

/// The 1.3.0 contract: the module flavor. 26 flags = the 23 shared + the model
/// trio. No family registry (1.3.0 predates the DFlash2 registry: a package
/// bakes its draft, an assembly needs draft/config.json).
public let contract130 = VersionContract(
    version: "1.3.0", flavor: .module,
    options: sharedOptions130_131 + moduleModelOptions)

/// The 1.3.1 contract: the launcher flavor. The shared 23 are byte-identical to
/// 1.3.0's; + the launcher model-axis flags, + the 2 verified DFlash2 families
/// (the keg's install/families.py).
public let contract131 = VersionContract(
    version: "1.3.1", flavor: .launcher,
    options: sharedOptions130_131 + launcherModelOptions,
    familyRegistry: [
        "Qwen3.8-27B": "incoai/Qwen3.8-27B-DFlash2",
        "Qwen3.6-35B-A3B": "incoai/Qwen3.6-35B-A3B-DFlash2",
    ],
    familyRules: [
        // verified: the mlx-community/Qwen3.8-27B-4bit config.json on this
        // machine says model_type "qwen3_5", and the engine's registry maps the
        // Qwen3.8-27B family (the repo name alone would mislead).
        FamilyRule(configKey: "model_type", value: "qwen3_5", family: "Qwen3.8-27B"),
    ])

/// The 1.3.2 contract: 1.3.1 + the 4 new flags; --max-cache-disk default
/// auto; --persistent-cache stays a plain store_true on the Python CLI (the
/// "on|off" of the issue matrix is the ENGINE's shape — the server passes it to
/// the binary internally; the app maps UI options to the Python CLI, never to
/// the C++ binary). The 1.3.2 tag's families.py is unchanged from 1.3.1's.
public let contract132 = VersionContract(
    version: "1.3.2", flavor: .launcher,
    options: sharedOptions132 + launcherModelOptions,
    familyRegistry: [
        "Qwen3.8-27B": "incoai/Qwen3.8-27B-DFlash2",
        "Qwen3.6-35B-A3B": "incoai/Qwen3.6-35B-A3B-DFlash2",
    ],
    familyRules: [
        FamilyRule(configKey: "model_type", value: "qwen3_5", family: "Qwen3.8-27B"),
    ])

/// The default registry: every authored version.
public let launchRegistry = LaunchRegistry(contracts: [
    "1.3.0": contract130,
    "1.3.1": contract131,
    "1.3.2": contract132,
])

/// D16: the contract for a kit's release.json version. An exact hit when the
/// version is authored; otherwise the LATEST authored contract with
/// `fallback` = true (D3: launch proceeds on it; S7 shows the visible
/// "FALLBACK MAPPING" indicator). A nil version (release.json unreadable) also
/// falls back.
public func contractFor(_ version: String?, registry: LaunchRegistry) -> (contract: VersionContract, fallback: Bool) {
    if let version, let exact = registry.contracts[version] {
        return (exact, false)
    }
    var latest: VersionContract?
    for contract in registry.contracts.values {
        if latest == nil || !versionGE(latest!.version, contract.version) {
            latest = contract
        }
    }
    precondition(latest != nil, "a launch registry must carry at least one contract")
    return (latest!, true)
}

/// A buildArgv diagnostic. `.warning` = an option was dropped for a `requires`
/// violation (D4: warn, never block — the launch proceeds; the engine would
/// have hard-errored). `.error` = no argv can be built at all (the plan layer
/// refuses pre-flight with the message).
public struct ArgvIssue: Equatable {
    public enum Severity: String, Equatable { case warning, error }
    public let severity: Severity
    public let message: String
    public init(severity: Severity = .warning, message: String) {
        self.severity = severity
        self.message = message
    }
}

/// A JSON value as engine CLI text: strings pass through, numbers in their
/// shortest form, bools as true/false; nil for null/compound (malformed for a
/// value option).
private func jsonText(_ v: JSONValue) -> String? {
    switch v {
    case .string(let s): return s
    case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
    case .bool(let b): return b ? "true" : "false"
    case .null, .array, .object: return nil
    }
}

/// The profile's value for `opt` as engine CLI text (nil when unset).
private func profileText(_ opt: OptionDef, _ values: [String: JSONValue]) -> String? {
    jsonText(values[opt.key] ?? .null)
}

/// The engine-effective value of `ref` as CLI text: the profile value, else the
/// contract's app default, else the engine default — what the engine would see
/// (the `requires` check evaluates THIS, so a default that satisfies the
/// engine's cross-check — 1.3.2's auto cache — satisfies it too). An append
/// option is "set" iff its list is non-empty (its first element's text).
private func effectiveText(_ ref: OptionDef, _ values: [String: JSONValue]) -> String? {
    if ref.kind == .append {
        return values[ref.key]?.array?.first.flatMap(jsonText)
    }
    return profileText(ref, values) ?? ref.appDefault ?? ref.defValue
}

/// A `requires` violation for `opt`, as a warning message (D4: warn, never
/// block). The engine would refuse to start (check_serve_arguments); the app
/// drops the offending flag instead and tells the user why.
private func requiresViolation(_ opt: OptionDef, contract: VersionContract, _ values: [String: JSONValue]) -> String? {
    for key in opt.requires {
        guard let ref = contract.option(key) else {
            return "\(opt.flag) requires \(key), which this kit's contract does not define"
        }
        guard let text = effectiveText(ref, values) else {
            return "\(opt.flag) needs \(ref.flag) (not set — the engine would refuse to start)"
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // "0"/"false" are the disabled states for a value/bool option (the
        // engine's 0 = no SSD cache, store_true false = off). For an append
        // option a "name" is never a disabled state — any non-empty list is set.
        if ref.kind != .append && (trimmed == "0" || trimmed == "false") {
            return "\(opt.flag) needs \(ref.flag) enabled (it is '\(text)' — the disabled state)"
        }
    }
    return nil
}

/// Build the engine argv + child env for one launch. PURE (T1): the registry
/// contract, the profile's option values, the model, and the globals in — no
/// environment reads (D9: config.json is the single source of truth).
///
/// Emission rules (the registry is the only argv source, D3):
/// - a SECRET (the api key) goes into the child env (SPLASH_API_KEY), NEVER on
///   argv — uniform across both flavors (open item 5: the 1.3.0 server reads
///   SPLASH_API_KEY from its environment, verified in its serve_options.py);
/// - an effective value equal to the engine's default (defValue) is OMITTED —
///   the engine reads it itself (1.3.2's thinking/state flags: emit only when
///   set, their defValue is nil);
/// - structural flags (alwaysEmit: host/port) are always emitted, even at their
///   engine default — today's resolveSplashPaths passes `--host 127.0.0.1
///   --port <port>` unconditionally, and the D9(b) anchor requires it;
/// - a `requires`-unmet option is DROPPED with an ArgvIssue.warning (D4: warn,
///   never block);
/// - builtFromModel flags (model/tokenizer/binary) are emitted from the launch
///   model in the structural prefix, never from the values map.
///
/// The argv excludes the python executable itself: the caller runs
/// `<kit>/python/bin/python <args>` from the kit dir (today's engineArgs shape).
public func buildArgv(_ contract: VersionContract,
                      profileValues: [String: JSONValue],
                      model: ProfileModel,
                      globals: GlobalCfg) -> (args: [String], env: [String: String], issues: [ArgvIssue]) {
    // D6: port + api key are service-level (globals), not per-profile options.
    // They sit in the values map under their option keys, and a globals value
    // overrides a stale same-named profile entry.
    var values = profileValues
    values["port"] = .string(String(globals.port))
    if !globals.apiKey.isEmpty { values["api_key"] = .string(globals.apiKey) }

    var env: [String: String] = [:]
    var args: [String] = []
    var issues: [ArgvIssue] = []

    // The structural prefix — today's resolveSplashPaths shape, verbatim.
    switch contract.flavor {
    case .launcher:
        guard let id = model.id else {
            return (args: [], env: env, issues: [
                ArgvIssue(severity: .error, message: "the launcher form needs a model id (a HF repo id such as owner/repo)")
            ])
        }
        args = ["-u", "install/launcher.py", "serve", "--model", id]
    case .module:
        guard let dir = model.dir else {
            return (args: [], env: env, issues: [
                ArgvIssue(severity: .error, message: "the module form needs the model's on-disk directory (it loads the dir positionally, never re-downloading)")
            ])
        }
        guard let id = model.id else {
            return (args: [], env: env, issues: [
                ArgvIssue(severity: .error, message: "the module form needs the model's id (server.py requires --model OWNER/REPO)")
            ])
        }
        args = ["-u", "-m", "server.server", dir,
                "--model", id,
                "--tokenizer", dir + "/tokenizer",
                "--binary", "./engine/splash"]
    }

    for opt in contract.options where !opt.builtFromModel {
        if opt.kind == .append {
            guard let list = values[opt.key]?.array, !list.isEmpty else { continue }
            if let violation = requiresViolation(opt, contract: contract, values) {
                issues.append(ArgvIssue(severity: .warning, message: violation))
                continue
            }
            for item in list {
                if let text = jsonText(item) {
                    args.append(opt.flag)
                    args.append(text)
                }
            }
            continue
        }
        let profile = profileText(opt, values)
        let effective = profile ?? (opt.alwaysEmit ? opt.appDefault : nil)
        // A secret: env only, never argv (open item 5: both flavors).
        if opt.secret {
            if let text = effective, !text.isEmpty, let name = opt.envVar {
                env[name] = text
            }
            continue
        }
        guard let text = effective else { continue }
        // Omission: equal to the engine default — the engine reads it itself.
        // alwaysEmit bypasses (host/port are always passed, today's behavior).
        if !opt.alwaysEmit && text == opt.defValue { continue }
        if let violation = requiresViolation(opt, contract: contract, values) {
            issues.append(ArgvIssue(severity: .warning, message: violation))
            continue
        }
        if opt.kind == .bool {
            args.append(opt.flag)   // a store_true flag is bare
        } else {
            args.append(opt.flag)
            args.append(text)
        }
    }
    return (args: args, env: env, issues: issues)
}
// MARK: - S3: family rules, eligibility, and the launch planner (C3, D4, D9, D16)

/// One config.json -> family rule: the app's plan-time knowledge of the engine's
/// config->family registry (1.3.1/1.3.2). The engine's family comes from the model
/// CONFIG, not the repo name, so a repo named ...Qwen... can still be a different
/// family. The one verified pair: model_type "qwen3_5" -> Qwen3.8-27B (checked
/// against the mlx-community repo's config.json on this machine AND the registry).
public struct FamilyRule: Equatable {
    public let configKey: String   // e.g. "model_type"
    public let value: String       // e.g. "qwen3_5"
    public let family: String      // e.g. "Qwen3.8-27B"
    public init(configKey: String, value: String, family: String) {
        self.configKey = configKey
        self.value = value
        self.family = family
    }
}

/// The plan-time family of a model, from its config.json. D4: undecidable (no
/// readable config, or no rule matches) -> nil, which becomes the `unknown`
/// verdict upstream — the engine is the final arbiter. NEVER a guess.
public func deriveFamily(config: String?, contract: VersionContract) -> String? {
    guard let config, let data = config.data(using: .utf8),
          let any = try? JSONSerialization.jsonObject(with: data, options: []),
          let obj = any as? [String: Any],
          let dict = JSONValue(any: obj).object else { return nil }
    for rule in contract.familyRules {
        if case .string(let v) = dict[rule.configKey] ?? .null, v == rule.value {
            return rule.family
        }
    }
    return nil
}

/// A plan-time eligibility verdict for (model kind x engine contract). D4: static
/// + conservative — never a false-runnable, never a false-block:
/// - `runnable`   the plan launches;
/// - `unrunnable` saveable (D4) but the start is refused pre-flight with the fix;
/// - `blocked`    a hard gate: the engine categorically refuses the combo (the
///                1.3.0 package under 1.3.1+), launch is never attempted;
/// - `unknown`    the app cannot decide (the family comes from the model config at
///                load) — the launch proceeds; the engine decides, its own error
///                surfaces in the existing LAUNCH FAIL state.
public struct Eligibility: Equatable {
    public enum Verdict: String, Equatable {
        case runnable, unrunnable, blocked, unknown
    }
    public var verdict: Verdict
    public var reason: String?
    public init(verdict: Verdict, reason: String? = nil) {
        self.verdict = verdict
        self.reason = reason
    }
}

/// The plan-time table (C3), row by model kind, column by engine flavor.
public func eligibility(kind: ModelKind,
                        contract: VersionContract,
                        modelId: String?,
                        modelDir: String?,
                        draftModel: String?,
                        family: String?,
                        files: ModelDirFiles) -> Eligibility {
    let v = contract.version
    switch kind {
    case .package:
        if contract.flavor == .launcher {
            return Eligibility(verdict: .blocked, reason:
                "engine v\(v) refuses 1.3.0 packages ('Splash no longer loads') — "
                + "run a 1.3.0 kit (engine → manual path), or switch the model to its HF repo id")
        }
        var missing = [String]()
        if !files.tokenizer { missing.append("tokenizer/") }
        if !files.draft { missing.append("draft/") }
        guard !missing.isEmpty else { return Eligibility(verdict: .runnable) }
        return Eligibility(verdict: .unrunnable, reason:
            "the 1.3.0 package \(modelId ?? "") is missing \(missing.joined(separator: " + ")) — "
            + "a package needs both subdirs (the 1.3.0 engine bakes no draft in at load)")
    case .assembly:
        if contract.flavor == .launcher {
            return Eligibility(verdict: .blocked, reason:
                "engine v\(v) serves models by HF id — it cannot load a local assembly "
                + "directory (model.json) — pick the model's HF repo id, or run a 1.3.0 kit")
        }
        var missing = [String]()
        if !files.config { missing.append("config.json") }
        if !files.draftConfig { missing.append("draft/config.json") }
        guard !missing.isEmpty else { return Eligibility(verdict: .runnable) }
        return Eligibility(verdict: .unrunnable, reason:
            "the assembly \(modelId ?? "") is missing \(missing.joined(separator: " + ")) — "
            + "an assembly needs both (the drafter requires a draft in both engine versions)")
    case .hfid:
        if contract.flavor == .module {
            if modelId == nil || !modelId!.contains("/") {
                return Eligibility(verdict: .unrunnable, reason:
                    "the 1.3.0 engine requires --model in OWNER/REPO form — this model has no "
                    + "Hugging Face id — rename it, or use a 1.3.1+ engine")
            }
            if modelDir == nil {
                return Eligibility(verdict: .unrunnable, reason:
                    "the 1.3.0 engine loads the model directory positionally (it never downloads) — "
                    + "no local directory for \(modelId!) was found — download the model into a model "
                    + "folder, or use a 1.3.1+ engine (it downloads by id)")
            }
            if files.config { return Eligibility(verdict: .runnable) }
            return Eligibility(verdict: .unrunnable, reason:
                "the 1.3.0 engine needs a config.json in the model dir to load it positionally — "
                + "\(modelId!) has none")
        }
        // The launcher (1.3.1+): serves by HF id, one-time download.
        if modelId == nil || !modelId!.contains("/") {
            let shown = (modelId?.isEmpty == false) ? modelId! : "the model"
            return Eligibility(verdict: .unrunnable, reason:
                "\(shown) is not an HF id (owner/repo) — the v\(v) engine serves models by HF id")
        }
        if !(draftModel ?? "").isEmpty {
            return Eligibility(verdict: .runnable, reason: "an explicit --draft-model is set")
        }
        if let family {
            if let draft = contract.familyRegistry[family] {
                return Eligibility(verdict: .runnable,
                                   reason: "family \(family) is in the v\(v) registry (draft \(draft))")
            }
            return Eligibility(verdict: .unrunnable, reason:
                "no DFlash2 draft is known for the \(family) family (the engine refuses at start) — "
                + "set --draft-model to a local dir or HF repo, or run a 1.3.0 kit")
        }
        return Eligibility(verdict: .unknown, reason:
            "engine decides at load — the model's family comes from its config (not its repo name); "
            + "the v\(v) registry decides then")
    case .other:
        if contract.flavor == .module {
            return Eligibility(verdict: .unrunnable, reason:
                "the 1.3.0 engine loads a Splash package (manifest.json) or an assembly (model.json) — "
                + "this model is neither — point the profile at a model it can load, or use a 1.3.1+ engine")
        }
        return Eligibility(verdict: .unrunnable, reason:
            "the v\(v) engine serves models by Hugging Face id — this local directory has no repo id to serve by")
    }
}

/// The launch result (C3): everything `ServerProc.launch` consumes, + the plan
/// signature (D13) and the actionable error text (when the plan cannot launch).
public struct LaunchConfig: Equatable {
    public var workDir: String?       // the kit dir (the engine's cwd)
    public var executable: String?    // the kit's bundled python
    public var base: String?          // the kit root (= workDir)
    public var engineArgs: [String]   // the full argv after the executable
    public var engineEnv: [String: String]   // SPLASH_API_KEY — env only, never argv
    public var port: Int?
    public var modelId: String?       // the model actually served
    public var modelDir: String?      // the on-disk dir (the module form's positional arg)
    public var version: String?       // the kit's release.json version
    public var mappingFallback: Bool  // D3: the visible FALLBACK indicator's source
    public var error: String?         // actionable text; nil = the plan launches
    public var profileId: String?
    public var profileName: String?
    public var restartRequired: Bool  // D13: COMPUTED by S4 from the signature; a
                                       // fresh plan never requires a restart
    public var restartReason: String?
    public var signature: String      // D13: hash-free plan signature (see planLaunch)
    public var issues: [String]       // warning-level (dropped options) for S7
    public init(workDir: String? = nil, executable: String? = nil, base: String? = nil,
                engineArgs: [String] = [], engineEnv: [String: String] = [:],
                port: Int? = nil, modelId: String? = nil, modelDir: String? = nil,
                version: String? = nil, mappingFallback: Bool = false,
                error: String? = nil, profileId: String? = nil, profileName: String? = nil,
                restartRequired: Bool = false, restartReason: String? = nil,
                signature: String = "", issues: [String] = []) {
        self.workDir = workDir
        self.executable = executable
        self.base = base
        self.engineArgs = engineArgs
        self.engineEnv = engineEnv
        self.port = port
        self.modelId = modelId
        self.modelDir = modelDir
        self.version = version
        self.mappingFallback = mappingFallback
        self.error = error
        self.profileId = profileId
        self.profileName = profileName
        self.restartRequired = restartRequired
        self.restartReason = restartReason
        self.signature = signature
        self.issues = issues
    }
}

/// The pure launch planner (C3): config.json text + injected FS -> `LaunchConfig`.
///
/// Pipeline: parse -> active profile -> `resolveKit` (the kit ladder; D9: NO env)
/// -> `contractFor` (D16: the kit's release.json) -> `enumerateModels` +
/// `classifyModelDir` + `eligibility` (D4) -> `buildArgv` (S2a) -> the plan
/// signature (D13). Every dependency is an injected closure — PURE, testable,
/// no process env reads anywhere (D9: the config is the single source of truth).
/// `now` is reserved for S4 (metadata timestamps); the plan itself is timeless.
public func planLaunch(_ data: Data,
                       home: String,
                       isDir: (String) -> Bool,
                       isExecutable: (String) -> Bool,
                       brewKeg: () -> String? = { nil },
                       kitVersion: (String) -> String? = { _ in nil },
                       fileContents: (String) -> String? = { _ in nil },
                       listDir: (String) -> [String]? = { _ in nil },
                       now: Date = Date()) -> LaunchConfig {
    // 1. the config (the store validated it at save; a plan is a dry-run of it).
    guard let doc = parseConfig(data).doc else {
        return LaunchConfig(error: "config.json is corrupt — the last good config remains in effect")
    }
    // 2. the active profile (S1b guarantees exactly one at startup).
    guard let pid = doc.activeProfile,
          let profile = doc.profiles.first(where: { $0.id == pid }) else {
        return LaunchConfig(error: "no profile is selected — pick one in Settings (06)")
    }
    let g = doc.globals
    // 3. the engine kit (the D2 ladder; D9: nothing from the process environment).
    let kr = resolveKit(engine: g.engine, home: home, isDir: isDir,
                        isExecutable: isExecutable, brewKeg: brewKeg,
                        kitVersion: kitVersion)
    guard let kit = kr.kit else {
        return LaunchConfig(version: kr.version, error: kr.error,
                            profileId: profile.id, profileName: profile.name)
    }
    // 4. the contract for THAT kit (D16: exact, else the latest fallback).
    let (contract, fallback) = contractFor(kr.version, registry: launchRegistry)
    // 5. the model: the profile's pick, resolved against the folders by
    //    enumeration (the fresh discovery beats a stale stored dir).
    let model = profile.model
    guard model.source != "none", let mid = model.id, !mid.isEmpty else {
        return LaunchConfig(version: kr.version,
                            error: "no model selected — pick one in Settings (06)",
                            profileId: profile.id, profileName: profile.name)
    }
    var dir = model.dir
    var kind: ModelKind?
    for folder in g.modelFolders {
        let entries = enumerateModels(folder: folder, isDir: isDir,
                                      fileContents: fileContents, listDir: listDir)
        if let e = entries.first(where: { $0.id == mid }) {
            kind = e.kind
            if let d = e.dir { dir = d }
            break
        }
    }
    // A model the enumeration cannot find (a folder moved since the last save)
    // is classified from its stored dir; an id with no dir at all is an hfid.
    if kind == nil {
        kind = dir == nil ? .hfid
            : classifyModelDir(dir: dir, id: mid, isDir: isDir, fileContents: fileContents)
    }
    let files = modelDirFiles(dir, isDir: isDir, fileContents: fileContents)
    let draftModel = profile.options["draft_model"]?.string
    let family: String? = {
        guard let dir else { return nil }
        return deriveFamily(config: fileContents(dir + "/config.json"), contract: contract)
    }()
    // 6. the eligibility gate (D4): blocked/unrunnable -> a clean error with the
    //    fix; unknown is NOT a gate (the engine decides at load).
    let elig = eligibility(kind: kind!, contract: contract, modelId: mid, modelDir: dir,
                           draftModel: draftModel, family: family, files: files)
    if elig.verdict == .blocked || elig.verdict == .unrunnable {
        return LaunchConfig(modelId: mid, modelDir: dir, version: kr.version,
                            mappingFallback: fallback, error: elig.reason,
                            profileId: profile.id, profileName: profile.name)
    }
    // 7. the argv (the registry is the ONLY source; D9: the key via env). The
    //    on-disk dir is the resolved one (the module form's positional argument).
    var launchModel = model
    launchModel.dir = dir
    let built = buildArgv(contract, profileValues: profile.options,
                          model: launchModel, globals: g)
    if built.args.isEmpty {
        let msg = built.issues.first(where: { $0.severity == .error })?.message
            ?? "cannot build the launch argv"
        return LaunchConfig(modelId: mid, modelDir: dir, version: kr.version,
                            mappingFallback: fallback, error: msg,
                            profileId: profile.id, profileName: profile.name)
    }
    // 8. assemble. The executable: the kit's bundled python (python, then python3).
    let executable: String? =
        isExecutable(kit + "/python/bin/python") ? kit + "/python/bin/python"
        : isExecutable(kit + "/python/bin/python3") ? kit + "/python/bin/python3"
        : nil
    guard let executable else {
        return LaunchConfig(workDir: kit, base: kit, modelId: mid, modelDir: dir,
                            version: kr.version, mappingFallback: fallback,
                            error: "the kit at \(kit) has no usable python (python/bin/python{,3})",
                            profileId: profile.id, profileName: profile.name)
    }
    // The plan signature (D13): everything that reaches the engine — the workdir,
    // the version (the binary itself), the full argv, the key env. A profile
    // rename changes none of these; a port/key/ANE/model/kit/fallback change does.
    var sigParts = [kit, kr.version ?? ""]
    sigParts += built.args
    if let key = built.env["SPLASH_API_KEY"] { sigParts.append(key) }
    return LaunchConfig(workDir: kit, executable: executable, base: kit,
                        engineArgs: built.args, engineEnv: built.env,
                        port: g.port, modelId: mid, modelDir: dir,
                        version: kr.version, mappingFallback: fallback,
                        profileId: profile.id, profileName: profile.name,
                        signature: sigParts.joined(separator: "\u{1F}"),
                        issues: built.issues.filter { $0.severity == .warning }.map { $0.message })
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
    let id = appProfileId(now: now)
    let profile = Profile(
        id: id, name: "Default",
        model: ProfileModel(source: "lmstudio", id: "incoai/Qwen3.8-27B-Splash", dir: nil),
        options: options,
        meta: ProfileMeta(createdAt: iso8601(now)))
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

/// ISO-8601 (UTC, whole seconds) — the timestamp form config.json uses for
/// `created_at` / `last_used_at` / … and the form `startupActivation` parses.
public func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

/// The first-run seed (D10): the doc the app writes when `config.json` is ABSENT
/// at load (a corrupt file is S1a's last-good path, not this one).
///
/// Documented defaults (port / key / the 5 auto roots / the per-profile options —
/// `defaultConfig`) plus the runtime-dependent parts, detected (never user-set,
/// D16):
/// - a Homebrew keg is present -> engine **auto** (the D2 ladder; the detected
///   runtime becomes the default) and one "Default" profile (D11) preconfigured
///   with that runtime's default model: 1.3.1+ -> the MLX id `mlx-community/
///   Qwen3.8-27B-4bit` (hfid; the 1.3.0 package it cannot read is NOT the keg
///   default); 1.3.0-style, or an unreadable version -> the local 1.3.0 package
///   (the module flavor, as `resolveSplashPaths` does).
/// - no runtime found -> engine **manual** + empty path + model unset
///   (unrunnable until the user configures an engine).
/// `active_profile` = the "Default" profile's id; `created_at` stamped.
/// Pure: FS/detection go through injected closures (T1), `now` is injectable.
public func firstRunConfig(home: String,
                           brewKeg: () -> String?,
                           kitVersion: (String) -> String?,
                           isDir: (String) -> Bool,
                           now: Date = Date()) -> ConfigDoc {
    var d = defaultConfig(home: home, now: now)   // the documented defaults (D10)
    if let keg = brewKeg(), keg != "", isDir(keg + "/libexec") {
        // The keg's libexec IS the engine kit (same layout as the release kit).
        d.globals.engine = EngineCfg(mode: "auto", manualPath: nil, brew: true)
        let version = kitVersion(keg + "/libexec")
        if let v = version, versionGE(v, "1.3.1") {
            d.profiles[0].model = ProfileModel(source: "hfid", id: "mlx-community/Qwen3.8-27B-4bit", dir: nil)
        }
        // else: 1.3.0-style (or version unreadable) -> the local package, as seeded.
    } else {
        d.globals.engine = EngineCfg(mode: "manual", manualPath: nil, brew: true)
        d.profiles[0].model = ProfileModel(source: "none", id: nil, dir: nil)
    }
    return d
}

/// D12 startup activation: the profile the app should run on start.
/// 1. the most recent `meta.last_used_at` wins (nil or unparseable = unused);
/// 2. a tie on the most recent, or all-nil -> the persisted `active_profile`
///    id, if it still references an existing profile;
/// 3. still none -> the first profile in array order.
/// Pure; an empty profile list -> nil. The caller stamps `last_used_at` (D13).
public func startupActivation(_ profiles: [Profile], persistedActive: String?) -> String? {
    guard !profiles.isEmpty else { return nil }
    let fmt = ISO8601DateFormatter()
    var best: (date: Date, id: String)? = nil
    var tied = false
    for p in profiles {
        guard let s = p.meta.lastUsedAt, let date = fmt.date(from: s) else { continue }
        if let b = best {
            if date > b.date { best = (date, p.id); tied = false }
            else if date == b.date { tied = true }
        } else {
            best = (date, p.id)
        }
    }
    if let b = best, !tied { return b.id }
    if let a = persistedActive, profiles.contains(where: { $0.id == a }) { return a }
    return profiles[0].id
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
// MARK: - Real-FS runtime detection (moved from main.swift)

/// A path is a directory.
public func isDir(_ path: String) -> Bool {
    var values = [FileAttributeKey: Any]()
    do { try values = FileManager.default.attributesOfItem(atPath: path) } catch { return false }
    return values[.type] as? FileAttributeType == .typeDirectory
}

/// The Homebrew keg of the splash formula, if installed. The formula versions
/// its Cellar path per release, so the newest version dir is picked.
public func findBrewKeg() -> String? {
    for base in ["/opt/homebrew", "/usr/local"] {
        let cellar = base + "/Cellar/splash"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: cellar)) ?? []
        if let v = versions.sorted().last {
            let keg = cellar + "/" + v
            if access(keg + "/bin/splash", X_OK) == 0 { return keg }
        }
    }
    return nil
}

/// A kit's on-disk engine version, from its release.json — the flavor
/// discriminator the launch contract is keyed to. nil when absent (the test
/// harness injects its own).
public func kitVersion(_ kit: String) -> String? {
    guard let data = FileManager.default.contents(atPath: kit + "/release.json") else { return nil }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return obj["version"] as? String
}

// MARK: - ConfigStore: the single owner of config.json (D1, R8)

/// Owns `~/Library/Application Support/SplashUI/config.json`:
/// - loads at app start, BEFORE the first engine launch (D1 — load must not
///   block launch; the file is small and read synchronously once);
/// - first run (file absent, not corrupt): seeds `firstRunConfig` synchronously
///   and writes it 0600 exactly once, before the first launch/adopt (D10, R10);
/// - startup activation: after load/seed, picks the D12 profile, stamps
///   `last_used_at` (D13), and persists a changed choice (D15);
/// - keeps the in-memory doc as the single source of truth (D9);
/// - is the ONLY code path that writes the file (R8 single-writer; the API key
///   makes this a 0600 file in a 0700 dir);
/// - writes atomically: tmp in the same dir -> fsync -> chmod 0600 -> rename(2).
///
/// All FS/detection access goes through injected closures (T1), so the whole
/// load/seed/save/corrupt/last-good/version-too-new state machine is
/// unit-testable without AppKit.
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
    /// First-run runtime detection (D10): the Homebrew keg prefix or nil, the
    /// kit version from release.json, directory existence — injected so the seed
    /// is testable (T1); the real-FS implementations are the defaults. (Names
    /// differ from the free functions so those stay reachable unqualified.)
    private let detectKeg: () -> String?
    private let detectKitVersion: (String) -> String?
    private let detectIsDir: (String) -> Bool

    public init(home: String,
                path: String? = nil,
                read: @escaping (String) -> Data? = ConfigStore.defaultRead,
                write: @escaping (Data, String) -> Bool = ConfigStore.defaultWrite,
                ensureDir: @escaping (String, Int) -> Bool = ConfigStore.defaultEnsureDir,
                brewKeg: @escaping () -> String? = ConfigStore.defaultBrewKeg,
                kitVersion: @escaping (String) -> String? = ConfigStore.defaultKitVersion,
                isDir: @escaping (String) -> Bool = ConfigStore.defaultIsDir) {
        self.home = home
        self.path = path ?? home + "/Library/Application Support/SplashUI/" + ConfigStore.fileName
        self.dir = (self.path as NSString).deletingLastPathComponent
        self.read = read
        self.write = write
        self.ensureDir = ensureDir
        self.detectKeg = brewKeg
        self.detectKitVersion = kitVersion
        self.detectIsDir = isDir
        self.doc = defaultConfig(home: home)
        self.load()
    }

    // MARK: Load

    /// (Re)load the file. Absent file -> first-run seed (D10): `firstRunConfig`
    /// (documented defaults + detected runtime) is written 0600 atomically,
    /// exactly once this launch (R10 — this load is synchronous in
    /// applicationDidFinishLaunching, ahead of the first server.launch/adopt and
    /// of any config command), and `firstRun` = true; it is derived from "file
    /// absent at load" (T12), so a deleted file re-arms the next launch (intended).
    /// Corrupt file -> last-good (or the defaults) + `loadError`; the file is left
    /// untouched (a next valid save repairs it). Newer version -> read-only doc.
    public func load() {
        _ = ensureDir(dir, 0o700)
        guard let data = read(path) else {
            doc = firstRunConfig(home: home, brewKeg: detectKeg, kitVersion: detectKitVersion, isDir: detectIsDir)
            firstRun = true
            let ok = commit(doc)
            loadError = ok ? nil : "could not write config.json (first-run seed): \(path)"
            versionTooNew = false
            fileVersion = ok ? configSchemaVersion : nil
            return
        }
        firstRun = false
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

    /// The shared write core: normalize + ensureDir + the atomic 0600 write
    /// (tmp -> fsync -> chmod -> rename) + the in-memory state update. `save()`
    /// runs strict validation first and stamps a result; the startup activation
    /// (D12) reuses it WITHOUT a result stamp — it is not a user action
    /// (`cfg.result` replies to config.save/config.validate only).
    @discardableResult
    private func commit(_ candidate: ConfigDoc) -> Bool {
        let (normalized, invalid) = normalizeConfig(candidate)
        _ = ensureDir(dir, 0o700)
        guard write(configData(normalized), path) else { return false }
        doc = normalized
        activeInvalid = invalid
        loadError = nil
        versionTooNew = false
        lastGood = normalized
        return true
    }

    /// Validate a candidate doc and write it atomically (tmp -> fsync -> 0600 ->
    /// rename). The ONLY path that writes the file on user action (R8). A
    /// version-too-new store refuses (never destroy forward data). Returns the
    /// result stamp, which also rides one tick of `cfg.result` (consumed via
    /// `consumeSaveResult`).
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
        guard commit(candidate) else {
            let r = ConfigSaveResult(ok: false, errors: ["cannot write config file: \(path)"], warnings: v.warnings)
            saveResult = r
            return r
        }
        saveResult = ConfigSaveResult(ok: true, errors: [], warnings: v.warnings)
        return saveResult!
    }

    // MARK: Startup activation (D12 — after load/seed, before the first launch)

    /// D12: pick the profile the app runs on — most-recent `last_used_at` -> the
    /// persisted `active_profile` -> the first profile — stamp it (D13), and
    /// persist the choice with one explicit save when it changed the active
    /// profile, before the first planLaunch/launch. On a fresh seed the pick is
    /// the seeded "Default" itself, already on disk via the seed write (R10: one
    /// write); a pick matching the persisted active profile stamps in memory
    /// only and flushes with the next explicit save (D15: no background writes).
    /// A corrupt file stays untouched (S1a) and a forward file (version-too-new)
    /// stays sacred: the pick applies in memory.
    public func activateStartup(now: Date = Date()) {
        guard let pick = startupActivation(doc.profiles, persistedActive: doc.activeProfile) else { return }
        if let i = doc.profiles.firstIndex(where: { $0.id == pick }) {
            doc.profiles[i].meta.lastUsedAt = iso8601(now)   // D13: activation stamps last_used_at
        }
        guard pick != doc.activeProfile else { return }   // choice unchanged: already persisted (or a fresh seed)
        doc.activeProfile = pick
        guard validateConfig(doc).ok, loadError == nil, !versionTooNew else { return }
        _ = commit(doc)   // the single explicit save of the D12 choice (no result stamp)
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

    /// The real runtime detection (the free functions above, which main.swift's
    /// `resolve()` uses as well): the Homebrew keg prefix or nil, the kit
    /// version from release.json, directory existence.
    public static func defaultBrewKeg() -> String? { findBrewKeg() }
    public static func defaultKitVersion(_ kit: String) -> String? { kitVersion(kit) }
    public static func defaultIsDir(_ path: String) -> Bool { isDir(path) }

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
