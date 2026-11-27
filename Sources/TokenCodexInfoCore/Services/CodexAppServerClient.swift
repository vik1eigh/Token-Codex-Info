import AppKit
import Darwin
import Foundation

public enum CodexAccountReadError: Error {
    case executableNotFound, requestFailed, timedOut
}

public protocol CodexAccountReading: Sendable {
    func readRateLimits(codexHome: URL) throws -> Data
}

/// Uses only initialize and account/rateLimits/read. No thread, turn, login,
/// credential export, or workspace operation is requested.
public struct CodexAppServerClient: CodexAccountReading, Sendable {
    private let executableURL: URL?
    private let timeoutSeconds: TimeInterval

    public init(executableURL: URL? = nil, timeoutSeconds: TimeInterval = 15) {
        self.executableURL = executableURL
        self.timeoutSeconds = timeoutSeconds
    }

    public func readRateLimits(codexHome: URL) throws -> Data {
        guard let executable = executableURL ?? CodexExecutableLocator.locate() else {
            throw CodexAccountReadError.executableNotFound
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "-c", "analytics.enabled=false"]
        process.environment = Self.subprocessEnvironment(codexHome: codexHome, inherited: ProcessInfo.processInfo.environment)
        // The request never needs access to the application's source directory.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        // Do not persist startup logs, credentials, or account information.
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        let session = RateLimitRPCSession(input: input.fileHandleForWriting)
        output.fileHandleForReading.readabilityHandler = { handle in
            session.receive(handle.availableData)
        }
        defer {
            session.stop()
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                if exited.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = exited.wait(timeout: .now() + 1)
                }
            }
            try? output.fileHandleForReading.close()
        }
        do {
            try process.run()
            try session.start()
        } catch {
            throw CodexAccountReadError.requestFailed
        }
        guard session.finished.wait(timeout: .now() + timeoutSeconds) == .success else {
            throw CodexAccountReadError.timedOut
        }
        return try session.response()
    }

    static func subprocessEnvironment(codexHome: URL, inherited: [String: String]) -> [String: String] {
        // Use Codex's own sign-in. Inherited API keys or agent access tokens
        // must not silently select a different account/authentication mode.
        let allowed = ["HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "USER", "LOGNAME",
                       "SSL_CERT_FILE", "SSL_CERT_DIR", "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY"]
        var environment = inherited.filter { allowed.contains($0.key) }
        environment["CODEX_HOME"] = codexHome.path
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return environment
    }
}

private final class RateLimitRPCSession: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
    private let input: FileHandle
    private let lock = NSLock()
    private var buffer = Data()
    private var result: Data?
    private var completed = false
    private var initialized = false

    init(input: FileHandle) { self.input = input }

    func start() throws {
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "token_codex_info", "title": "Token Codex Info", "version": "1.0.3"]
        ]])
    }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        try input.write(contentsOf: data)
    }

    func receive(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        guard !data.isEmpty, buffer.count + data.count <= 1_048_576 else {
            finish(nil)
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            // Unsolicited notifications and requests cannot trigger any action.
            guard let id = message["id"] as? Int, message["method"] == nil else { continue }
            if id == 1, !initialized {
                guard message["error"] == nil, message["result"] != nil else { finish(nil); return }
                initialized = true
                do {
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } catch { finish(nil); return }
            } else if id == 2, initialized {
                guard message["error"] == nil, let value = message["result"] as? [String: Any] else { finish(nil); return }
                // Keep quota fields only, discarding account IDs, credits, plan
                // details, and any future unrelated response fields.
                var quota: [String: Any] = [:]
                if let single = value["rateLimits"] as? [String: Any] { quota["rateLimits"] = Self.limitFields(single) }
                if let buckets = value["rateLimitsByLimitId"] as? [String: Any],
                   let codex = buckets["codex"] as? [String: Any] {
                    quota["rateLimitsByLimitId"] = ["codex": Self.limitFields(codex)]
                }
                finish(try? JSONSerialization.data(withJSONObject: quota))
                return
            }
        }
    }

    private static func limitFields(_ value: [String: Any]) -> [String: Any] {
        var clean: [String: Any] = [:]
        if let id = value["limitId"] as? String { clean["limitId"] = id }
        for name in ["primary", "secondary"] {
            if let window = value[name] as? [String: Any] {
                clean[name] = window.filter { ["usedPercent", "windowDurationMins", "resetsAt"].contains($0.key) }
            }
        }
        return clean
    }

    // Called with lock held.
    private func finish(_ data: Data?) {
        guard !completed else { return }
        result = data
        completed = true
        buffer.removeAll()
        finished.signal()
    }

    func stop() {
        lock.lock()
        completed = true
        buffer.removeAll()
        lock.unlock()
    }

    func response() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let result else { throw CodexAccountReadError.requestFailed }
        return result
    }
}

enum CodexExecutableLocator {
    static func locate() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var apps = [URL(fileURLWithPath: "/Applications/Codex.app"), home.appendingPathComponent("Applications/Codex.app"),
                    URL(fileURLWithPath: "/Applications/ChatGPT.app"), home.appendingPathComponent("Applications/ChatGPT.app")]
        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") { apps.insert(registered, at: 0) }
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return locate(applications: apps, searchPaths: paths.map { URL(fileURLWithPath: $0) })
    }

    static func locate(applications: [URL], searchPaths: [URL]) -> URL? {
        let bundledPaths = [
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex-cli/bin/codex",
            "Contents/Resources/codex",
            "Contents/Resources/bin/codex"
        ]
        var candidates = applications.flatMap { app in bundledPaths.map { app.appendingPathComponent($0) } }
        candidates += searchPaths.map { $0.appendingPathComponent("codex") }
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            let resolved = candidate.resolvingSymlinksInPath()
            if resolved.pathExtension != "js" { return resolved }
            // npm's launcher needs Node. Resolve its bundled native binary so
            // a Finder-launched app works without a shell PATH or Node process.
            #if arch(arm64)
            let triple = "aarch64-apple-darwin"
            let package = "codex-darwin-arm64"
            #else
            let triple = "x86_64-apple-darwin"
            let package = "codex-darwin-x64"
            #endif
            let root = resolved.deletingLastPathComponent().deletingLastPathComponent()
            let vendors = [root.appendingPathComponent("vendor"), root.appendingPathComponent("node_modules/@openai/\(package)/vendor"), root.deletingLastPathComponent().appendingPathComponent("\(package)/vendor")]
            for vendor in vendors {
                for suffix in ["\(triple)/bin/codex", "\(triple)/codex/codex"] {
                    let binary = vendor.appendingPathComponent(suffix)
                    if FileManager.default.isExecutableFile(atPath: binary.path) { return binary }
                }
            }
        }
        return nil
    }
}

public struct ReportedCodexUsageProvider: UsageProviding, Sendable {
    private let client: CodexAccountReading
    private let local: UsageProviding

    public init(client: CodexAccountReading = CodexAppServerClient(), local: UsageProviding = CodexUsageProvider()) {
        self.client = client
        self.local = local
    }

    public func loadUsage(settings: UsageSettings, now: Date) -> UsageSnapshot {
        guard !settings.codexHomePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              CodexFolderChecker().check(settings.expandedCodexHomeURL) == .readable else {
            return local.loadUsage(settings: settings, now: now)
        }
        do {
            let data = try client.readRateLimits(codexHome: settings.expandedCodexHomeURL)
            let result = try JSONDecoder().decode(AccountRateLimitsResponse.self, from: data)
            if var snapshot = result.snapshot(now: now) {
                snapshot.source = .liveRateLimits
                return snapshot
            }
            return .empty(limitTokens: 100, now: now)
        } catch CodexAccountReadError.executableNotFound {
            let snapshot = local.loadUsage(settings: settings, now: now)
            if snapshot.hasData || snapshot.issue != .noUsageData { return snapshot }
            return .empty(limitTokens: 100, now: now, issue: .codexUnavailable)
        } catch {
            return .empty(limitTokens: 100, now: now, issue: .liveRequestFailed)
        }
    }
}

private struct AccountRateLimitsResponse: Decodable {
    var rateLimits: CodexSessionRateLimits?
    var rateLimitsByLimitId: [String: CodexSessionRateLimits]?

    func snapshot(now: Date) -> UsageSnapshot? {
        if let codex = rateLimitsByLimitId?["codex"] { return codex.snapshot(now: now) }
        return rateLimits?.snapshot(now: now)
    }
}
