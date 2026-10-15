import AppKit
import WebKit
import Foundation
import Darwin

// MARK: - Configuration

enum Cfg {
    static let host = "127.0.0.1"
    static let logLink = "/tmp/splash-standalone.log"
}

// Resolve the engine paths + engine argv from the documented env contract
// (README "Configuration (environment)"). Re-resolved on every launch attempt so a
// user fixing the install while the app is running takes effect on the next try.
// (`isDir`, `findBrewKeg`, and `kitVersion` live in ui_logic.swift: the config
// store needs the same real-FS runtime detection for the D10 first-run seed.)

// The README ./install.sh default install root (SPLASHUI_HOME).
let defaultRoot = NSHomeDirectory() + "/SplashUI"

func resolve() -> SplashPaths {
    resolveSplashPaths(
        env: ProcessInfo.processInfo.environment,
        defaultRoot: defaultRoot,
        home: NSHomeDirectory(),
        isDir: isDir,
        isExecutable: { access($0, X_OK) == 0 },
        brewKeg: findBrewKeg,
        kitVersion: kitVersion)
}

// MARK: - Process helpers

func serverPids(port: Int) -> [Int32] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    // Bracket, not dot: a dot would also match a *concurrent pgrep's own argv* (the
    // pattern text appears there verbatim), which looks like a phantom server.
    p.arguments = ["-f", "server[.]server.*--port " + String(port)]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return [] }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    return text.split(separator: "\n").compactMap { Int32($0) }
}

// Is anything listening on the engine port? Ground truth for "a server exists" —
// a raw socket connect: no child process, no pgrep, immune to spawn flakiness.
func portAlive(port: Int) -> Bool {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = UInt16(port).bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr(Cfg.host))
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    return ok == 0
}

func processUptime(_ pid: Int32) -> Double {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "etimes=", "-p", String(pid)]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return 0 }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return Double((String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}

// MARK: - Server lifecycle

final class ServerProc {
    private(set) var process: Process?
    private(set) var launchedByApp = false
    private(set) var userStopped = false
    private(set) var pendingRestart = false
    private(set) var restartsExhausted = false
    // Launch-failure record (surfaced in the panel + engine log) and retry bookkeeping.
    private(set) var lastLaunchError: LaunchError?
    private(set) var launchFailRetries = 0
    // True once the app has started (or adopted) a server that is serving: the
    // auto-quit policy only applies to a service that actually ran.
    private(set) var everUp = false
    private var launchDate = Date()
    private var restartDates: [Date] = []
    private var outHandle: FileHandle?

    // Resolved engine paths/config. Re-resolved on every launch attempt so a fixed
    // install takes effect; also read each tick for the poll endpoint's port.
    var slash: SplashPaths

    init() { slash = resolve() }

    var pid: Int32? {
        if let p = process, p.isRunning { return p.processIdentifier }
        return serverPids(port: slash.port).first
    }

    func upSeconds() -> Double {
        guard let pid = pid else { return 0 }
        if launchedByApp, let p = process, p.isRunning { return Date().timeIntervalSince(launchDate) }
        return processUptime(pid)
    }

    // App-side adoption of an already-serving engine (e.g. one started by start.sh).
    func adopt() { everUp = true }

    // Clear the error state so a user-pressed Start/Restart begins a fresh attempt.
    func clearLaunchError() {
        lastLaunchError = nil
        launchFailRetries = 0
    }

    func launch() {
        slash = resolve()
        guard pid == nil, !portAlive(port: slash.port) else { return }
        // Fresh engine log + tail symlink on every attempt, before the pre-flight,
        // so even a missing-install failure lands in /tmp (the panel + `tail -f`).
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        let logPath = "/tmp/splash-standalone-\(stamp).log"
        FileManager.default.createFile(atPath: logPath, contents: Data())
        // Re-point the tail's link each launch: createSymbolicLink silently fails
        // when a link from a previous run exists, stranding the new log out of view.
        try? FileManager.default.removeItem(atPath: Cfg.logLink)
        try? FileManager.default.createSymbolicLink(atPath: Cfg.logLink, withDestinationPath: logPath)

        // Pre-flight: if the install is missing/broken, record it and stop —
        // no process is touched, and the app stays up showing the actionable error.
        if let e = slash.error { recordLaunchFailure(e, logPath: logPath); return }
        guard let executable = slash.executable else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        if let dir = slash.workDir { p.currentDirectoryURL = URL(fileURLWithPath: dir) }
        p.arguments = slash.engineArgs
        guard let out = FileHandle(forWritingAtPath: logPath) else {
            recordLaunchFailure("cannot write engine log: \(logPath)", logPath: logPath)
            return
        }
        p.standardOutput = out
        p.standardError = out
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.outHandle?.closeFile()
                self?.outHandle = nil
                self?.terminated(proc)
            }
        }
        do { try p.run() } catch {
            out.closeFile()
            recordLaunchFailure(error.localizedDescription, logPath: logPath)
            return
        }
        // Keep the parent-side copy alive while the child runs: Foundation's async
        // task-launch references the fd after run() returns; closing it early throws
        // NSFileHandleOperationException -> uncaught ObjC exception -> SIGABRT.
        outHandle = out
        process = p
        launchedByApp = true
        everUp = true
        userStopped = false
        pendingRestart = false
        restartsExhausted = false
        lastLaunchError = nil
        launchFailRetries = 0
        launchDate = Date()
    }

    // One line to NSLog (Console.app) and an append to the engine log stream, so
    // `tail -f /tmp/splashui.log` shows launch failures alongside engine output.
    private func recordLaunchFailure(_ message: String, logPath: String) {
        lastLaunchError = LaunchError(message: message, attempt: Date())
        launchFailRetries += 1
        let line = "SplashUI launch failed (attempt \(launchFailRetries)): \(message)\n"
        NSLog("%@", line)
        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile()
            if let d = line.data(using: .utf8) { h.write(d) }
            h.closeFile()
        }
    }

    func stop() {
        userStopped = true
        pendingRestart = false
        everUp = false
        lastLaunchError = nil
        launchFailRetries = 0
        if let p = process, p.isRunning {
            p.terminationHandler = nil
            kill(p.processIdentifier, SIGTERM)
        }
        outHandle?.closeFile()
        outHandle = nil
        for pid in serverPids(port: slash.port) { kill(pid, SIGTERM) }
        process = nil
    }

    private func terminated(_ proc: Process) {
        if proc === process { process = nil }
        guard !userStopped else { return }
        // backoff: max 3 automatic restarts in 10 minutes
        let cutoff = Date().addingTimeInterval(-600)
        restartDates = restartDates.filter { $0 > cutoff }
        guard restartDates.count < 3 else { restartsExhausted = true; return }
        restartDates.append(Date())
        pendingRestart = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            self.pendingRestart = false
            guard self.pid == nil else { return }
            self.launch()
        }
    }
}

struct LaunchError { let message: String; let attempt: Date }

// MARK: - System memory
// vm.swapusage ABI on this macOS: 32 bytes = {i64 total, i64 avail, i64 used, u32 pagesize, u32 flags}, values in bytes
struct SwapUsage { var total: Int64 = 0; var avail: Int64 = 0; var used: Int64 = 0; var pagesize: UInt32 = 0; var flags: UInt32 = 0 }
func sampleSystem() -> [String: Any] {
    var out: [String: Any] = [:]
    var stats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    if kr == KERN_SUCCESS {
        let page = Int64(vm_kernel_page_size)
        out["free_bytes"] = Int64(stats.free_count) * page
        out["active_bytes"] = Int64(stats.active_count) * page
        out["inactive_bytes"] = Int64(stats.inactive_count) * page
        out["wired_bytes"] = Int64(stats.wire_count) * page
        out["compressed_bytes"] = Int64(stats.compressor_page_count) * page
    }
    var memsize: Int64 = 0
    var size = MemoryLayout<Int64>.size
    if sysctlbyname("hw.memsize", &memsize, &size, nil, 0) == 0 { out["phys_bytes"] = memsize }
    var swap = SwapUsage()
    size = MemoryLayout<SwapUsage>.size
    if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
        out["swap_total_bytes"] = swap.total
        out["swap_used_bytes"] = swap.used
    }
    return out
}

func engineFootprint(_ pid: Int32) -> Int64? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "rss=", "-p", String(pid)]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return rssBytesFromPsOutput(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
}

// MARK: - Server log tail (Request / Done lines)

final class LogTail {
    struct ActiveReq {
        var id: Int
        var input: Int
        var start: Date
        var prefillBase: Double?
        var cacheBase: Double?
        var resumeBase: Double?
        var lastDone: Double = 0
        var ageAtLastCommit: Double = 0
    }
    struct DoneReq {
        var id: Int; var input: Int; var cached: Int; var output: Int
        var ttft: Double; var tps: Double?
    }
    private var realPath: String?
    private var offset: UInt64 = 0
    private var pending = ""
    private var nextId = 0
    private var seededIds = false
    var active: [Int: ActiveReq] = [:]
    private(set) var recent: [DoneReq] = []

    // Token-weighted prefix-cache hit rate over the most recent completions. The engine
    // only reports a request's exact prefix match at completion, so in-flight work is
    // estimated from this window.
    var recentHitRate: Double? {
        let ins = recent.reduce(0) { $0 + $1.input }
        guard ins > 0 else { return nil }
        return min(1.0, Double(recent.reduce(0) { $0 + $1.cached }) / Double(ins))
    }

    func poll(completed: Int, cancelled: Int) {
        if !seededIds {
            nextId = max(completed, cancelled)
            seededIds = true
        }
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: Cfg.logLink) else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: dest))?[.size] as? UInt64 ?? 0
        if dest != realPath { realPath = dest; offset = 0; pending = "" }
        guard size >= offset, let fh = FileHandle(forReadingAtPath: dest) else {
            if size < offset { offset = 0; pending = "" }
            return
        }
        fh.seek(toFileOffset: offset)
        let chunk = (try? fh.readToEnd()) ?? Data()
        offset = size
        guard !chunk.isEmpty else { return }
        var text = pending + (String(data: chunk, encoding: .utf8) ?? "")
        guard let nl = text.lastIndex(of: "\n") else { pending = text; return }
        pending = String(text[text.index(after: nl)...])
        text = String(text[..<nl])
        for line in text.split(separator: "\n") { handle(String(line)) }
    }

    // "input 179,226" -> "179,226" (trimmed); nil when the label is absent
    private func labeled(_ s: String, _ label: String) -> String? {
        guard s.hasPrefix(label) else { return nil }
        return String(s.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
    }
    // Int/Double strict parsing fails on leading whitespace — trim first
    private func num(_ s: String) -> Int {
        Int(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private func handle(_ line: String) {
        let parts = line.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        let first = parts.first ?? ""
        if first.hasSuffix("Request") {
            // "17:08:44 Request · input 183,271 · 14"
            guard let id = Int(parts.last ?? ""), id > 0 else { return }
            var input = 0
            for p in parts { if let v = labeled(p, "input") { input = num(v) } }
            active[id] = ActiveReq(id: id, input: input, start: Date(), prefillBase: nil, cacheBase: nil, resumeBase: nil)
        } else if first.hasSuffix("Done") || first.hasSuffix("Cancelled") {
            var d = DoneReq(id: 0, input: 0, cached: 0, output: 0, ttft: 0, tps: nil)
            var id: Int?
            for p in parts {
                if p.hasPrefix("#") { id = Int(p.dropFirst()) }
                else if let v = labeled(p, "input") { d.input = num(v) }
                else if let v = labeled(p, "cached") { d.cached = num(v) }
                else if let v = labeled(p, "output") { d.output = num(v) }
                else if let v = labeled(p, "TTFT") { d.ttft = Double(v.replacingOccurrences(of: "s", with: "") ) ?? 0 }
                else if p.hasSuffix("tok/s") { d.tps = Double(p.replacingOccurrences(of: "tok/s", with: "").trimmingCharacters(in: .whitespaces)) }
            }
            let row = requestRowId(current: nextId, lineHasId: id)
            d.id = row.id
            nextId = row.next
            if let id = id { active.removeValue(forKey: id) }
            recent.insert(d, at: 0)
            if recent.count > 8 { recent.removeLast() }
        }
    }
}

// MARK: - JSON helpers

func js(_ v: Any?) -> Any {
    guard let v = v else { return NSNull() }
    if let d = v as? Double { return d.isFinite ? d as Any : NSNull() }
    if let n = v as? NSNumber { return n }
    if let s = v as? String { return s }
    if let b = v as? Bool { return b }
    return NSNull()
}

// MARK: - App delegate

// A borderless window will never become key without this override — and the
// WebView only receives mouse events in a key window.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var statusItem: NSStatusItem!
    var panel: KeyablePanel!
    var webView: WKWebView!
    let server = ServerProc()
    let tail = LogTail()
    private var timer: Timer?
    private var globalMonitor: Any?

    private var lastDecodeOut: Double?
    private var lastDecodeOutAt: Date?
    private var lastDecodeSample: (v: Double, t: Date)?
    private var lastPrefillTok: Double?
    private var lastPrefillWall: Double?
    private var lastPrefillSample: (v: Double, t: Date)?
    private var lastPrefillPayload: (p: [String: Any], t: Date)?
    private var synthesizedRequest: LogTail.ActiveReq?
    private var wasPrefilling = false
    private var metrics: [String: Double] = [:]
    private var statusJSON: [String: Any]?
    private var lastServerSeen = Date.distantPast
    private var downSince: Date?

    // config.json store — the single source of truth for engine/model/profile
    // configuration (D9). Loaded before the first engine launch (D1); the ONLY
    // code path that writes the file (R8 single-writer).
    private var configStore: ConfigStore!
    // Last canonical j.cfg JSON: the change gate (cfg ticks only when it changed).
    private var lastCfgJSON: String?

    private let orange = NSColor(red: 0.98, green: 0.54, blue: 0.24, alpha: 1)
    private let teal = NSColor(red: 0.25, green: 0.76, blue: 0.79, alpha: 1)

    func applicationDidFinishLaunching(_ note: Notification) {
        // The config loads first (small file, one synchronous read) — before any
        // engine launch reads the configuration it replaces (D1). If the file was
        // absent, the load SEEDS it (D10): that write happens synchronously here,
        // ahead of the launch/adopt below and of any config command (R10).
        configStore = ConfigStore(home: NSHomeDirectory())
        // D12: pick the startup profile (most-recent last_used_at -> the persisted
        // active id -> first), stamp it (D13), and persist the choice — still before
        // the first launch below. On a fresh seed this re-picks its own "Default"
        // (a no-op write: the seed IS the persistence).
        configStore.activateStartup()
        setupStatusItem()
        setupPanel()
        if server.pid == nil {
            // pgrep alone can race the process table — confirm via the port: only
            // launch a server when the port is actually not serving (otherwise adopt).
            get("/status") { [weak self] data in
                guard let self = self else { return }
                if data == nil { self.server.launch() } else { self.server.adopt() }
            }
        } else {
            // An engine is already running (e.g. started by start.sh): it is as much a
            // service "in charge" as one we launched, so it counts as up — 0.3 quit 10 s
            // after such a server died, and this must stay true.
            server.adopt()
        }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    // MARK: UI setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = ""
        statusItem.button?.image = trayImage(color: .systemGray, fill: 0)
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.target = self
    }

    private func setupPanel() {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 800),
                             styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hidesOnDeactivate = false

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "cmd")
        cfg.userContentController.add(self, name: "size")
        webView = WKWebView(frame: panel.contentView!.bounds, configuration: cfg)
        webView.autoresizingMask = [.width, .height]
        panel.contentView = webView
        if let url = Bundle.main.url(forResource: "panel", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        NotificationCenter.default.addObserver(self, selector: #selector(hidePanel),
                                               name: NSWindow.didResignKeyNotification, object: panel)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() }
        else { showPanel() }
    }

    private func showPanel() {
        if let button = statusItem.button, let win = button.window {
            let f = win.frame
            let maxX = (NSScreen.main?.frame.maxX ?? 2000) - 528
            panel.setFrame(NSRect(x: min(f.maxX - 528, maxX), y: f.minY - panel.frame.height - 8, width: 520, height: panel.frame.height),
                           display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "size" {
            if let h = message.body as? Int { applyPanelHeight(h) }
            return
        }
        // Object-body commands: the JS sends {cmd: "…", …args} (T8 clean cutover —
        // string bodies are no longer accepted).
        guard let body = message.body as? [String: Any] else { return }
        let cmd = body["cmd"] as? String ?? ""
        switch cmd {
        case "start": server.clearLaunchError(); server.launch()
        case "stop":
            server.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.quitApp() }
        case "restart":
            // stop() clears the failure record + retry count, so a fresh attempt
            // starts at attempt 1 with no stale error in the UI.
            server.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.server.launch() }
        case "config.get": respondConfigGet()
        case "config.save": respondConfigSave(body)
        case "config.validate": respondConfigValidate(body)
        default: break
        }
    }

    // MARK: Config bridge (config.get / config.save / config.validate)

    /// The whole doc, raw (the edit form needs the unmasked api_key to round-trip
    /// it — the tick payload only ever carries the mask, D6).
    private func respondConfigGet() {
        let data = configData(configStore.doc)
        guard let str = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__cfgGet(\(str))", completionHandler: nil)
    }

    /// Parse the candidate strictly, validate, write (the single-writer path).
    private func respondConfigSave(_ body: [String: Any]) {
        guard let docObj = body["doc"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: docObj) else { return }
        let r = configStore.saveCandidate(data)
        sendConfigResult(r, to: "window.__cfgSave")
    }

    /// The same rules, no write (syntax/strict check only — unsupported combos
    /// never block; that is S3's eligibility, D4).
    private func respondConfigValidate(_ body: [String: Any]) {
        guard let docObj = body["doc"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: docObj) else { return }
        let r = configStore.validateCandidate(data)
        sendConfigResult(r, to: "window.__cfgValidate")
    }

    private func sendConfigResult(_ r: ConfigSaveResult, to fn: String) {
        let res: [String: Any] = ["ok": r.ok, "errors": r.errors, "warnings": r.warnings]
        guard let data = try? JSONSerialization.data(withJSONObject: res),
              let str = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("\(fn)(\(str))", completionHandler: nil)
    }

    // JS reports natural content height; panel grows/shrinks to fit (top edge pinned)
    private func applyPanelHeight(_ h: Int) {
        let screenH = NSScreen.main?.frame.height ?? 1200
        let target = min(max(320, CGFloat(h + 16)), screenH - 120)
        let f = panel.frame
        guard abs(f.height - target) > 4 else { return }
        panel.setFrame(NSRect(x: f.minX, y: f.origin.y - (target - f.height), width: f.width, height: target), display: true)
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: Tray icon

    private func trayImage(color: NSColor, fill: Double) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        let frame = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 5, width: 13, height: 6), xRadius: 3, yRadius: 3)
        color.withAlphaComponent(0.3).setFill()
        frame.fill()
        if fill > 0.02 {
            let w = max(3.0, 13 * CGFloat(min(1, fill)))
            let bar = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 5, width: w, height: 6), xRadius: 3, yRadius: 3)
            color.setFill()
            bar.fill()
        }
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private func updateTray(detail: String, color: NSColor, fill: Double) {
        statusItem.button?.image = trayImage(color: color, fill: fill)
        // Drop shadow so the colored badge text stays legible on both light and
        // dark menu bars (macOS doesn't tint status-item text to contrast).
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        statusItem.button?.attributedTitle = NSAttributedString(string: " " + detail, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .shadow: shadow,
        ])
    }

    // MARK: Polling

    private func get(_ path: String, _ done: @escaping (Data?) -> Void) {
        guard let url = URL(string: server.slash.base + path) else { done(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.5
        req.setValue(server.slash.apiKey, forHTTPHeaderField: "x-api-key")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { done(ok ? data : nil) }
        }.resume()
    }

    private func parseProm(_ text: String) -> [String: Double] {
        var d: [String: Double] = [:]
        for line in text.split(separator: "\n") {
            guard !line.hasPrefix("#") else { continue }
            let l = line.trimmingCharacters(in: .whitespaces)
            guard let space = l.lastIndex(of: " ") else { continue }
            let namePart = l[l.startIndex..<space]
            guard let v = Double(l[l.index(after: space)...]), v.isFinite else { continue }
            let name: String
            if let b = namePart.firstIndex(of: "{") { name = String(namePart[namePart.startIndex..<b]) }
            else { name = String(namePart) }
            d[name] = v
        }
        return d
    }

    // decode rate = committed output tokens ÷ real elapsed time between /metrics samples.
    // The counter accrues over the whole sample interval (~1 s), so the sample age is
    // the correct denominator — a tick-elapsed denominator with a 0.1 s floor inflates
    // a 1 s delta ~10× (a local server answers well inside the floor).
    private func updateDecodeRate(from m: [String: Double]) {
        guard let d = m["splash_decode_output_tokens_total"] else { return }
        if let last = lastDecodeOut, let t0 = lastDecodeOutAt {
            let dt = Date().timeIntervalSince(t0)
            if dt >= 0.5, d - last > 0 {
                lastDecodeSample = ((d - last) / dt, Date())
            }
        }
        lastDecodeOut = d
        lastDecodeOutAt = Date()
    }

    private func tick() {
        // Keep the resolved port/key fresh (env changes + user fixing the install).
        server.slash = resolve()
        get("/status") { [weak self] data in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let j = j {
                    self.statusJSON = j
                    self.lastServerSeen = Date()
                    if let completed = self.fld("requests", "completed"), let cancelled = self.fld("requests", "cancelled") {
                        self.tail.poll(completed: telemetryInt(completed), cancelled: telemetryInt(cancelled))
                    }
                }
                self.tickRender()
            }
        }
        get("/metrics") { [weak self] data in
            guard let self = self, let data = data, let text = String(data: data, encoding: .utf8) else { return }
            let m = self.parseProm(text)
            DispatchQueue.main.async {
                self.metrics = m
                self.lastServerSeen = Date()
                self.updateDecodeRate(from: m)
                self.tickRender()
            }
        }
    }

    // nested lookup into /status JSON
    private func fld(_ path: String...) -> Double? {
        var cur: Any? = statusJSON
        for k in path {
            guard let d = cur as? [String: Any] else { return nil }
            cur = d[k]
        }
        return (cur as? NSNumber)?.doubleValue
    }

    private func tickRender() {
        let now = Date()
        // ---- decode rate: lastDecodeSample is set in updateDecodeRate() on each /metrics
        // sample; latch the most recent real sample for up to 15 s so the readout doesn't
        // flicker back to "—" when the counter freezes between samples.
        let decodeRate: Double? = lastDecodeSample.flatMap { Date().timeIntervalSince($0.t) < 15 ? $0.v : nil }
        let gaugeDecode = metrics["splash_decode_tokens_per_second"]

        var prefillTps: Double?
        if let t = metrics["splash_prefill_input_tokens_total"], let w = metrics["splash_prefill_wall_milliseconds_total"],
           let lt = lastPrefillTok, let lw = lastPrefillWall {
            let dw = (w - lw) / 1000.0
            let dt = t - lt
            if dw > 0.05, dt > 0 { prefillTps = dt / dw }
        }
        lastPrefillTok = metrics["splash_prefill_input_tokens_total"]
        lastPrefillWall = metrics["splash_prefill_wall_milliseconds_total"]
        if let p = prefillTps { lastPrefillSample = (p, now) }
        // Latch like the decode rate: prefill on a cached session lasts only a few
        // seconds, so the last real per-prefill sample is held for up to 15 s.
        let prefillLatch = lastPrefillSample.flatMap { now.timeIntervalSince($0.t) < 15 ? $0.v : nil }
        // Displayed tok/s = the LIVE per-prefill measurement (live sample, held up to
        // 15 s) — never the session average.
        let prefillRate: Double? = prefillTps ?? prefillLatch
        // Extrapolation/ETA rate: three rungs — live per-prefill sample → 15 s latch
        // → the engine's session-wide splash_prefill_tokens_per_second (a stable
        // average the engine publishes even at idle, so a cold request on a warm
        // engine still climbs from the start). This feeds only the projected
        // done-value and the ETA, never the displayed tok/s.
        let engineRate = metrics["splash_prefill_tokens_per_second"]
        let projRate = prefillProjRate(live: prefillTps, latch: prefillLatch, engine: engineRate)

        let prefillCount = telemetryInt(fld("scheduler", "prefilling") ?? metrics["splash_scheduler_prefilling"])
        let decodeCount = telemetryInt(fld("scheduler", "decoding") ?? metrics["splash_scheduler_decoding"])
        let frontendCount = telemetryInt(fld("frontend", "active") ?? metrics["splash_frontend_active"])
        let prefilling = prefillCount > 0
        let decoding = (metrics["splash_scheduler_decoding"] ?? 0) > 0 || decodeRate != nil
        let queued = ((metrics["splash_scheduler_queued"] ?? 0) + (metrics["splash_scheduler_waiting_resources"] ?? 0)) > 0

        // ---- log tail
        tail.active = tail.active.filter { Date().timeIntervalSince($0.value.start) < 3600 }
        // Cumulative tokens actually prefilled — moves live during prefill. (The
        // target_prefill_rows counter is a draft-context snapshot that does not move
        // per request, which is why the old readout sat at 0%.)
        let prefilledTotal = metrics["splash_prefill_input_tokens_total"]
        let cacheBlock = statusJSON?["cache"] as? [String: Any]
        let cacheTokensNow = ((cacheBlock?["kv_hit_tokens"] as? Double) ?? 0)
            + ((cacheBlock?["kv_disk_hit_tokens"] as? Double) ?? 0)
            + ((cacheBlock?["reused_tokens"] as? Double) ?? 0)
        let resumptionsNow = (cacheBlock?["resource_resumptions"] as? Double) ?? 0
        // Track when the counter last moved per in-flight request so pct/eta can
        // extrapolate from the live prefill rate over the time since then. The
        // engine commits splash_prefill_input_tokens_total in ~2048-token ANE-FFN
        // steps, so the counter sits flat most of a chunk; lastDone detects the
        // commit edge and ageAtLastCommit stamps it with the row's age.
        func recordCommit(_ req: inout LogTail.ActiveReq) {
            if let wd = prefilledTotal.flatMap({ prefillProgress(prefilledTotal: $0, prefillBase: req.prefillBase) }),
               wd > 0, wd > req.lastDone {
                req.lastDone = wd
                req.ageAtLastCommit = now.timeIntervalSince(req.start)
            }
        }
        if inFlight(prefilling: prefillCount, decoding: decodeCount, frontendActive: frontendCount) {
            if synthesizedRequest == nil {
                synthesizedRequest = LogTail.ActiveReq(id: 0, input: 0, start: now, prefillBase: nil,
                    cacheBase: cacheTokensNow, resumeBase: resumptionsNow)
            }
            let baseline = prefillBaseline(prefilling: prefilling, wasPrefilling: wasPrefilling,
                current: synthesizedRequest?.prefillBase, prefilledTotal: prefilledTotal)
            synthesizedRequest?.prefillBase = baseline
            if var syn = synthesizedRequest {
                recordCommit(&syn)
                synthesizedRequest = syn
            }
        } else {
            synthesizedRequest = nil
        }
        wasPrefilling = prefilling
        for (id, var req) in tail.active {
            if req.prefillBase == nil, let total = prefilledTotal, total.isFinite { req.prefillBase = total }
            if req.cacheBase == nil { req.cacheBase = cacheTokensNow }
            if req.resumeBase == nil { req.resumeBase = resumptionsNow }
            recordCommit(&req)
            tail.active[id] = req
        }
        // Prefix-cache hit rate: token-weighted over the last 8 completions, falling
        // back to session counters (cached vs prefilled tokens) until the window fills.
        var hitRate = tail.recentHitRate
        // Session fallback for a synthesized row (prompt size not yet logged): the
        // mean fresh (uncached) tail over the last 8 completions.
        let meanFresh = meanFreshTail(fresh: tail.recent.map { ($0.input, $0.cached) })
        if hitRate == nil,
           let kt = (statusJSON?["cache"] as? [String: Any])?["kv_hit_tokens"] as? Double,
           let pt = metrics["splash_prefill_input_tokens_total"] {
            let den = kt + pt
            if den > 0 { hitRate = min(1.0, kt / den) }
        }
        let requests = tail.active.isEmpty ? synthesizedRequest.map { [$0] } ?? [] : Array(tail.active.values)
        let activeList = requests.map { req -> [String: Any] in
            let workDone = prefilledTotal.flatMap { prefillProgress(prefilledTotal: $0, prefillBase: req.prefillBase) }
            var r: [String: Any] = ["id": req.id, "input": Double(req.input), "age_s": now.timeIntervalSince(req.start),
                                    "tokens": js(workDone), "tps": js(prefillRate)]
            let resumed = (req.resumeBase.flatMap { resumptionsNow - $0 } ?? 0) >= 1
            // Completion % (pill, tray, and this row all read it) = 100 × done /
            // estFresh, where done is the fresh (uncached) prefill counter delta
            // since the request started and estFresh estimates that same fresh
            // tail. The request's total input is not observable in-flight by a
            // passive monitor, so estFresh is an estimate: a real row (input > 0,
            // from the Request log) uses the measured cache delta when the engine
            // has credited this request's hits (resident KV + SSD restores + state
            // resumption; the full-resume path returns before token accounting, so
            // its counters stay silent → whole prompt resumed), else a
            // token-weighted hit-rate guess, else the whole input (cold). A
            // synthesized row (input 0 — the log hasn't arrived) falls back to the
            // session mean fresh tail; an empty window → nil → no honest
            // percentage, the tok/tok/s fallback shows instead.
            var estFresh: Double?
            if req.input > 0 {
                let cacheTokens = ((cacheBlock?["kv_hit_tokens"] as? Double) ?? 0)
                    + ((cacheBlock?["kv_disk_hit_tokens"] as? Double) ?? 0)
                    + ((cacheBlock?["reused_tokens"] as? Double) ?? 0)
                var cachedNow = min(Double(req.input), max(0, cacheTokens - (req.cacheBase ?? 0)))
                if resumed { cachedNow = Double(req.input) }
                if cachedNow > 0 {
                    estFresh = max(0, Double(req.input) - cachedNow)
                } else if let hr = hitRate {
                    estFresh = Double(req.input) * (1 - hr)
                } else {
                    estFresh = Double(req.input)
                }
            } else {
                estFresh = meanFresh
            }
            // The counter commits in chunks, so extrapolate the done value from the
            // extrapolation rate (live sample → 15 s latch → engine session rate) over
            // the time since the counter last moved → pct and ETA rise smoothly from
            // the start instead of sitting flat until the first commit. The tok readout
            // (r["tokens"]) stays the REAL counter delta, never projected, and the tps
            // readout stays the LIVE per-prefill rate, never the session average.
            let age = now.timeIntervalSince(req.start)
            // Request-cumulative rate (committed fresh tokens ÷ real elapsed time):
            // self-averaged over the request's life, so it is free of the chunk-edge
            // spike a 1 s-delta sample reads when a ~2048-token commit lands inside
            // the poll window. Used only to guard the extrapolation rung below — the
            // displayed tok/s (r["tps"]) stays the LIVE per-prefill measurement.
            let cumRate = workDone.flatMap { prefillCumulativeRate(workDone: $0, age: age) }
            let reqProjRate = calibratePrefillRate(raw: projRate, cumulative: cumRate)
            let proj = workDone.map {
                prefillProjectedDone(workDone: $0, ageAtLastCommit: req.ageAtLastCommit,
                                     age: age, rate: reqProjRate, estFresh: estFresh)
            }
            // Hold the completion % below 100 while the engine still reports an
            // in-flight prefill: the extrapolated pct can otherwise flash 100% a few
            // seconds before the first token. The scheduler flip (prefilling → 0)
            // lifts the cap, so the last 1% comes from the exact prefill→decode
            // signal, not the estimate.
            if let p = proj, let pct = prefillPct(done: p, estFresh: estFresh, cap: prefilling ? 99 : nil) {
                r["pct"] = pct
            }
            // ETA autoregresses the same (spike-guarded) extrapolation rate over the
            // remaining fresh tail; nil (no estimate) → nothing rendered.
            if let p = proj {
                r["eta"] = js(prefillEtaText(sec: prefillEta(done: p, estFresh: estFresh, rate: reqProjRate)))
            }
            // cached_pct (real rows only): the measured cached share of the prompt.
            if req.input > 0, let workDone = workDone {
                let cacheTokens = ((cacheBlock?["kv_hit_tokens"] as? Double) ?? 0)
                    + ((cacheBlock?["kv_disk_hit_tokens"] as? Double) ?? 0)
                    + ((cacheBlock?["reused_tokens"] as? Double) ?? 0)
                var cachedNow = min(Double(req.input), max(0, cacheTokens - (req.cacheBase ?? 0)))
                if resumed {
                    // The full-resume path (e.g. an exact duplicate) returns before
                    // token accounting runs, so the counters stay silent — treat the
                    // whole prompt as resumed.
                    cachedNow = Double(req.input)
                }
                var est: Double?
                if cachedNow > 0 {
                    est = max(1, Double(req.input) - cachedNow)
                } else if let hr = hitRate {
                    est = Double(req.input) * (1 - hr)
                }
                if cachedNow > 0 {
                    r["cached_pct"] = cachedNow * 100.0 / Double(req.input)
                } else if let hr = hitRate, (est == nil || est! >= workDone) {
                    r["cached_pct"] = hr * 100
                }
            }
            return r
        }.sorted { ($0["id"] as? Int) ?? 0 > ($1["id"] as? Int) ?? 0 }
        let recentList = tail.recent.map { r -> [String: Any] in
            var d: [String: Any] = ["id": r.id, "input": r.input, "cached": r.cached,
                                    "output": r.output, "ttft_s": r.ttft]
            d["tps"] = js(r.tps)
            return d
        }

        // ---- state machine
        let down = Date().timeIntervalSince(lastServerSeen) > 3
        let ready = (statusJSON?["ready"] as? Bool) ?? false
        // pgrep alone can flap — the service counts as gone only when the port stops answering too
        let procGone = server.pid == nil && !server.userStopped && Date().timeIntervalSince(lastServerSeen) > 5
        var state = "idle"
        if procGone {
            // pendingRestart means the engine *ran* and just died (crash path, 3×/10 min
            // backoff), so it wins over a launch-failure record.
            if server.launchedByApp && server.pendingRestart && !server.restartsExhausted { state = "restarting" }
            else if server.lastLaunchError != nil { state = "launchfailed" }
            else { state = "down" }
        }
        else if down { state = server.launchedByApp && server.pid != nil ? "loading" : "down" }
        else if !ready { state = "loading" }
        else if prefilling { state = "prefill" }
        else if decoding || !tail.active.isEmpty { state = "decode" }
        else if queued { state = "queue" }

        // ---- the UI never outlives the *service*: quit 10 s after a server that was
        // observed up goes away (crash, or an adopted external server dying). A launch
        // that never came up (everUp == false) must NOT quit — the menu bar stays
        // available with the actionable error on display; Stop is always the exit.
        if procGone {
            if downSince == nil { downSince = Date() }
            else if let ds = downSince,
                    autoQuitDecision(procGone: procGone, everUp: server.everUp,
                                     downFor: Date().timeIntervalSince(ds), userStopped: server.userStopped) {
                NSApplication.shared.terminate(nil)
            }
        } else {
            downSince = nil
        }

        // ---- auto-retry a failed launch: every 30 s, up to 10 total attempts. The
        // user may have installed/fixed the kit meanwhile; launch() re-resolves
        // paths fresh and clears the error on success, re-records on failure.
        if server.lastLaunchError != nil && !server.userStopped &&
            launchRetryDue(error: server.lastLaunchError?.attempt,
                           retries: server.launchFailRetries, now: Date()) {
            server.launch()
        }
        // ---- tray
        switch state {
        case "down": updateTray(detail: "DOWN", color: .systemRed, fill: 0)
        case "launchfailed": updateTray(detail: "ERR", color: .systemRed, fill: 0)
        case "restarting": updateTray(detail: "RESTART", color: .systemYellow, fill: 0.3)
        case "loading": updateTray(detail: "LOAD", color: .systemYellow, fill: 0.4)
        case "prefill":
            // Append the prefill ETA ("· 12 s" / "· 1m 23 s") when available so the
            // badge shows both progress and time-remaining; nil until the estimate lands.
            let etaSfx = (activeList.first?["eta"] as? String).map { " · \($0)" } ?? ""
            if let pct = activeList.first?["pct"] as? Double, pct.isFinite {
                updateTray(detail: String(format: "PREF %.0f%%", pct) + etaSfx, color: orange, fill: pct / 100)
            } else {
                let tokens = activeList.first?["tokens"] as? Double
                let count = tokens.map { String(format: "%.0f", $0) } ?? "…"
                let rate = prefillRate.map { String(format: "%.0f", $0) } ?? "—"
                updateTray(detail: "PREF \(count) tok · \(rate) t/s" + etaSfx, color: orange, fill: 0.5)
            }
        case "decode":
            let tps = decodeRate ?? gaugeDecode ?? 0
            updateTray(detail: String(format: "%.0f t/s", tps), color: teal, fill: 1)
        case "queue": updateTray(detail: "QUEUE", color: .systemYellow, fill: 0.5)
        default: updateTray(detail: "IDLE", color: .systemGray, fill: 0.15)
        }

        // ---- system + engine footprint
        var sys = sampleSystem()
        sys["engine_footprint_bytes"] = js(server.pid.flatMap { engineFootprint($0) })

        // ---- assemble JSON
        var j: [String: Any] = [
            "t": now.timeIntervalSince1970,
            "state": state,
            "ready": ready,
            "model": js(server.slash.modelId),
            "ctx": js(fld("maximum_context_tokens")),
        ]
        j["engine"] = [
            "version": js(server.slash.version),
            "metal_healthy": js(metrics["splash_metal_healthy"]),
            "pressure": js(statusJSON?["memory_pressure"]),
            "loop_tick_ms": js(fld("loop", "max_tick_ms")),
            "ttft_p50_ms": js(metrics["splash_ttft_p50_milliseconds"]),
            "ttft_p95_ms": js(metrics["splash_ttft_p95_milliseconds"]),
            "itl_p50_ms": js(metrics["splash_itl_p50_milliseconds"]),
            "itl_p95_ms": js(metrics["splash_itl_p95_milliseconds"]),
            "draft_accept": js(metrics["splash_draft_acceptance_ratio"]),
        ]
        if let a = statusJSON?["ane_ffn"] as? [String: Any] {
            j["ane"] = [
                "state": a["state"] ?? NSNull(),
                "share": js(a["share"]),
                "minimum_rows": js(a["minimum_rows"]),
                "reason": a["reason"] ?? NSNull(),
            ]
        } else {
            j["ane"] = NSNull()
        }
        j["rates"] = [
            "decode_tps": js(decodeRate),
            "decode_avg": js(gaugeDecode),
            "prefill_tps": js(prefillRate),
        ]
        j["sched"] = [
            "prefilling": js(metrics["splash_scheduler_prefilling"]),
            "decoding": js(metrics["splash_scheduler_decoding"]),
            "queued": js(metrics["splash_scheduler_queued"]),
            "waiting_resources": js(metrics["splash_scheduler_waiting_resources"]),
            "waiting_prefix": js(metrics["splash_scheduler_waiting_prefix"]),
            "frontend_active": js(metrics["splash_frontend_active"]),
            "frontend_waiting": js(metrics["splash_frontend_waiting"]),
        ]
        j["admission"] = [
            "waiting": js(fld("admission", "waiting")),
            "waiting_memory": js(fld("admission", "waiting_memory")),
            "oldest_wait_ms": js(fld("admission", "oldest_wait_ms")),
        ]
        let pressure = statusJSON?["memory_pressure"] as? String
        if let pressure = pressure { j["pressure"] = pressure }
        if state == "prefill", let first = activeList.first {
            var pf: [String: Any] = ["pct": js(first["pct"]), "input": first["input"] as? Double ?? 0,
                                     "tokens": js(first["tokens"]), "tps": js(first["tps"])]
            if let c = first["cached_pct"] as? Double { pf["cached_pct"] = c }
            lastPrefillPayload = (pf, now)
            j["prefill"] = pf
        } else if let lp = lastPrefillPayload, now.timeIntervalSince(lp.t) < 15 {
            j["prefill"] = lp.p
        } else {
            j["prefill"] = NSNull()
        }
        j["kv"] = [
            "allocated_bytes": js(fld("kv", "allocated_bytes") ?? metrics["splash_kv_allocated_bytes"]),
            "active_pages": js(fld("kv", "pages_active") ?? metrics["splash_kv_pages_active"]),
            "cache_pages": js(fld("kv", "pages_cache") ?? metrics["splash_kv_pages_cache"]),
            "free_pages": js(fld("kv", "pages_free") ?? metrics["splash_kv_free_allocated_pages"]),
            "capacity_bytes": js(fld("memory_plan", "budget", "kv_capacity_bytes")),
        ]
        if let kvIdent = ((statusJSON?["identity"] as? [String: Any])?["kv"]) as? [String: Any] {
            j["kv_fmt"] = js(kvIdent["format"])
        } else {
            j["kv_fmt"] = NSNull()
        }
        j["state_mem"] = [
            "bytes": js(fld("state", "bytes") ?? metrics["splash_state_bytes"]),
            "entries": js(fld("state", "entries") ?? metrics["splash_state_entries"]),
            "in_use": js(fld("state", "in_use") ?? metrics["splash_state_in_use"]),
            "active_lanes": js(fld("state", "active_lanes") ?? metrics["splash_state_active_lanes"]),
        ]
        j["eng_mem"] = [
            "current_bytes": js(metrics["splash_memory_current_bytes"]),
            "peak_bytes": js(metrics["splash_memory_peak_bytes"]),
            "limit_bytes": js(metrics["splash_memory_limit_bytes"]),
            "headroom_bytes": js(metrics["splash_memory_headroom_bytes"]),
            "host_available_bytes": js(fld("memory_governor", "host_available_bytes")),
        ]
        j["ssd"] = [
            "bytes": js(fld("disk", "used_bytes")),
            "quota": js(fld("disk", "capacity_bytes")),
            "kv_bytes": js(fld("disk", "kv_bytes")),
            "state_bytes": js(fld("state", "disk_bytes")),
            "restores": js(fld("disk", "kv_restores")),
            "reads": js(fld("disk", "read_bytes")),
            "writes": js(fld("disk", "written_bytes")),
            "persistent": js((statusJSON?["disk"] as? [String: Any])?["persistent"]),
        ]
        j["cache"] = [
            "hits": js(metrics["splash_cache_hits_total"]),
            "cold_misses": js(metrics["splash_cache_cold_misses_total"]),
            "reused_tokens": js(metrics["splash_cache_reused_tokens_total"]),
        ]
        j["req"] = [
            "active": activeList,
            "recent": recentList,
            "completed_total": js(metrics["splash_requests_completed_total"]),
            "failed_total": js(metrics["splash_requests_failed_total"]),
            "cancelled_total": js(metrics["splash_requests_cancelled_total"]),
        ]
        j["sys"] = sys
        j["server"] = [
            "pid": Int(server.pid ?? 0),
            "launched_by_app": server.launchedByApp && server.pid != nil,
            "up_seconds": server.upSeconds(),
            "launch_error": js(server.lastLaunchError?.message),
            "kit_dir": js(server.slash.workDir),
        ]

        // ---- cfg (change gate: it ticks only when it changed; unchanged -> the
        // key is omitted and the JS keeps its last copy). In S1a it reflects the
        // config store; the fields later stories own ride along as stable nulls.
        let cfgInFlight = prefillCount + decodeCount + frontendCount
        let cfgPayload = configTickPayload(
            doc: configStore.doc,
            loadError: configStore.loadError,
            versionTooNew: configStore.versionTooNew,
            activeInvalid: configStore.activeInvalid,
            firstRun: configStore.firstRun,
            inFlight: cfgInFlight,
            result: configStore.consumeSaveResult())
        let cfgJSON = jsonString(JSONValue(any: cfgPayload), indent: 0)
        if cfgJSON != lastCfgJSON {
            lastCfgJSON = cfgJSON
            j["cfg"] = cfgPayload
        }
        if let data = try? JSONSerialization.data(withJSONObject: j),
           let str = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("window.update(\(str))")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
