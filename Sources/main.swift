import AppKit
import WebKit
import Foundation
import Darwin

// MARK: - Configuration (mirrors start.sh)

enum Cfg {
    private static let env = ProcessInfo.processInfo.environment
    static let host = "127.0.0.1"
    static let port = Int(env["SPLASH_PORT"] ?? "") ?? 8123
    static let apiKey = env["SPLASH_KEY"] ?? "splash-standalone-1"
    static let kitDir = env["SPLASH_KIT_DIR"] ?? NSHomeDirectory() + "/SplashUI/kit/splash-1.2.1-arm64-macos26"
    static let python = kitDir + "/python/bin/python"
    static let modelRoot = env["SPLASH_MODEL_ROOT"] ?? NSHomeDirectory() + "/SplashUI/models/incoai/Qwen3.8-27B-Splash"
    static let modelId = "incoai/Qwen3.8-27B-Splash"
    static let maxCacheDisk = env["SPLASH_MAX_CACHE_DISK"] ?? "100g"
    static let idleRelease = env["SPLASH_IDLE_RELEASE"] ?? "240m"
    static let logLink = "/tmp/splashui.log"
    static var base: String { "http://\(host):\(port)" }
    static var engineArgs: [String] {
        ["-u", "-m", "server.server", modelRoot,
         "--tokenizer", modelRoot + "/tokenizer",
         "--model", modelId, "--binary", "./engine/splash",
         "--host", host, "--port", String(port), "--api-key", apiKey,
         "--persistent-cache", "--max-cache-disk", maxCacheDisk,
         "--idle-release", idleRelease]
    }
}

// MARK: - Process helpers

func serverPids() -> [Int32] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    // Bracket, not dot: a dot would also match a *concurrent pgrep's own argv* (the
    // pattern text appears there verbatim), which looks like a phantom server.
    p.arguments = ["-f", "server[.]server.*--port " + String(Cfg.port)]
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
func portAlive() -> Bool {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = UInt16(Cfg.port).bigEndian
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
    private var launchDate = Date()
    private var restartDates: [Date] = []
    private var outHandle: FileHandle?

    var pid: Int32? {
        if let p = process, p.isRunning { return p.processIdentifier }
        return serverPids().first
    }

    func upSeconds() -> Double {
        guard let pid = pid else { return 0 }
        if launchedByApp, let p = process, p.isRunning { return Date().timeIntervalSince(launchDate) }
        return processUptime(pid)
    }

    func launch() {
        guard pid == nil, !portAlive() else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        let logPath = "/tmp/splash-standalone-\(stamp).log"
        FileManager.default.createFile(atPath: logPath, contents: Data())
        try? FileManager.default.createSymbolicLink(atPath: Cfg.logLink, withDestinationPath: logPath)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Cfg.python)
        p.currentDirectoryURL = URL(fileURLWithPath: Cfg.kitDir)
        p.arguments = Cfg.engineArgs
        guard let out = FileHandle(forWritingAtPath: logPath) else { return }
        p.standardOutput = out
        p.standardError = out
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.outHandle?.closeFile()
                self?.outHandle = nil
                self?.terminated(proc)
            }
        }
        do { try p.run() } catch { out.closeFile(); return }
        // Keep the parent-side copy alive while the child runs: Foundation's async
        // task-launch references the fd after run() returns; closing it early throws
        // NSFileHandleOperationException -> uncaught ObjC exception -> SIGABRT.
        outHandle = out
        process = p
        launchedByApp = true
        userStopped = false
        pendingRestart = false
        restartsExhausted = false
        launchDate = Date()
    }

    func stop() {
        userStopped = true
        pendingRestart = false
        if let p = process, p.isRunning {
            p.terminationHandler = nil
            kill(p.processIdentifier, SIGTERM)
        }
        outHandle?.closeFile()
        outHandle = nil
        for pid in serverPids() { kill(pid, SIGTERM) }
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
    var t: task_t = task_t(MACH_PORT_NULL)
    guard task_for_pid(mach_task_self_, pid, &t) == KERN_SUCCESS else { return nil }
    defer { mach_port_deallocate(mach_task_self_, t) }
    var info = task_vm_info_data_t()
    var cnt = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(cnt)) { task_info(t, task_flavor_t(TASK_VM_INFO), $0, &cnt) }
    }
    guard kr == KERN_SUCCESS else { return nil }
    return Int64(info.phys_footprint)
}

// MARK: - Server log tail (Request / Done lines)

final class LogTail {
    struct ActiveReq {
        var id: Int
        var input: Int
        var start: Date
        var rowsBase: Double?
    }
    struct DoneReq {
        var id: Int; var input: Int; var cached: Int; var output: Int
        var ttft: Double; var tps: Double?
    }
    private var realPath: String?
    private var offset: UInt64 = 0
    private var pending = ""
    var active: [Int: ActiveReq] = [:]
    private(set) var recent: [DoneReq] = []

    func poll() {
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
            active[id] = ActiveReq(id: id, input: input, start: Date(), rowsBase: nil)
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
            if let id = id { d.id = id; active.removeValue(forKey: id) }
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
    private var metrics: [String: Double] = [:]
    private var statusJSON: [String: Any]?
    private var lastServerSeen = Date.distantPast
    private var downSince: Date?

    private let orange = NSColor(red: 0.98, green: 0.54, blue: 0.24, alpha: 1)
    private let teal = NSColor(red: 0.25, green: 0.76, blue: 0.79, alpha: 1)

    func applicationDidFinishLaunching(_ note: Notification) {
        setupStatusItem()
        setupPanel()
        if server.pid == nil {
            // pgrep alone can race the process table — confirm via the port: only
            // launch a server when the port is actually not serving (otherwise adopt).
            get("/status") { [weak self] data in
                guard let self = self else { return }
                if data == nil { self.server.launch() }
            }
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
        guard let cmd = message.body as? String else { return }
        switch cmd {
        case "start": server.launch()
        case "stop":
            server.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.quitApp() }
        case "restart":
            server.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.server.launch() }
        default: break
        }
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
        statusItem.button?.attributedTitle = NSAttributedString(string: " " + detail, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
        ])
    }

    // MARK: Polling

    private func get(_ path: String, _ done: @escaping (Data?) -> Void) {
        guard let url = URL(string: Cfg.base + path) else { done(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.5
        req.setValue(Cfg.apiKey, forHTTPHeaderField: "x-api-key")
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
            guard let v = Double(l[l.index(after: space)...]) else { continue }
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
        get("/status") { [weak self] data in
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let j = j { self.statusJSON = j; self.lastServerSeen = Date() }
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

        let prefilling = (metrics["splash_scheduler_prefilling"] ?? 0) > 0
        let decoding = (metrics["splash_scheduler_decoding"] ?? 0) > 0 || decodeRate != nil
        let queued = ((metrics["splash_scheduler_queued"] ?? 0) + (metrics["splash_scheduler_waiting_resources"] ?? 0)) > 0

        // ---- log tail
        tail.poll()
        tail.active = tail.active.filter { Date().timeIntervalSince($0.value.start) < 3600 }
        let rowsTotal = metrics["splash_target_prefill_rows_total"]
        for (id, var req) in tail.active {
            if req.rowsBase == nil { req.rowsBase = rowsTotal ?? 0 }
            tail.active[id] = req
        }
        let activeList = tail.active.values.map { req -> [String: Any] in
            let pct: Double
            if let base = req.rowsBase, let rows = rowsTotal, req.input > 0 {
                pct = min(100, max(0, (rows - base) * 100.0 / Double(req.input)))
            } else { pct = 0 }
            return ["id": req.id, "input": Double(req.input), "age_s": Date().timeIntervalSince(req.start), "pct": pct]
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
            state = server.launchedByApp && server.pendingRestart && !server.restartsExhausted ? "restarting" : "down"
        }
        else if down { state = "down" }
        else if !ready { state = "loading" }
        else if prefilling { state = "prefill" }
        else if decoding || !tail.active.isEmpty { state = "decode" }
        else if queued { state = "queue" }

        // ---- the UI never outlives the service: quit 10 s after the service is gone
        if procGone {
            if downSince == nil { downSince = Date() }
            else if let ds = downSince, Date().timeIntervalSince(ds) > 10 {
                NSApplication.shared.terminate(nil)
            }
        } else {
            downSince = nil
        }

        // ---- tray
        switch state {
        case "down": updateTray(detail: "DOWN", color: .systemRed, fill: 0)
        case "restarting": updateTray(detail: "RESTART", color: .systemYellow, fill: 0.3)
        case "loading": updateTray(detail: "LOAD", color: .systemYellow, fill: 0.4)
        case "prefill":
            let pct = (activeList.first?["pct"] as? Double) ?? 0
            updateTray(detail: "PREF \(Int(pct))%", color: orange, fill: pct / 100)
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
            "model": Cfg.modelId,
            "ctx": js(fld("maximum_context_tokens")),
        ]
        j["engine"] = [
            "metal_healthy": js(metrics["splash_metal_healthy"]),
            "pressure": js(statusJSON?["memory_pressure"]),
            "loop_tick_ms": js(fld("loop", "max_tick_ms")),
            "ttft_p50_ms": js(metrics["splash_ttft_p50_milliseconds"]),
            "ttft_p95_ms": js(metrics["splash_ttft_p95_milliseconds"]),
            "itl_p50_ms": js(metrics["splash_itl_p50_milliseconds"]),
            "itl_p95_ms": js(metrics["splash_itl_p95_milliseconds"]),
            "draft_accept": js(metrics["splash_draft_acceptance_ratio"]),
        ]
        j["rates"] = [
            "decode_tps": js(decodeRate),
            "decode_avg": js(gaugeDecode),
            "prefill_tps": js(prefillTps),
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
            j["prefill"] = ["pct": first["pct"] as? Double ?? 0, "input": first["input"] as? Double ?? 0]
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
        ]

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
