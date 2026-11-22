import Foundation

public protocol SQLiteQuerying: Sendable {
    func runReadOnlyQuery(databasePath: String, query: String) throws -> String
}

public enum SQLiteClientConstants {
    public static let fieldSeparator: Character = Character(UnicodeScalar(31)!)
}

public struct SQLiteCommandClient: SQLiteQuerying, Sendable {
    private let executablePath: String
    private let timeoutSeconds: Int

    public init(executablePath: String = "/usr/bin/sqlite3", timeoutSeconds: Int = 10) {
        self.executablePath = executablePath
        self.timeoutSeconds = timeoutSeconds
    }

    public func runReadOnlyQuery(databasePath: String, query: String) throws -> String {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let outputURL = temporaryDirectory.appendingPathComponent("TokenCodexInfo-\(UUID().uuidString).sqlite.stdout")
        let errorURL = temporaryDirectory.appendingPathComponent("TokenCodexInfo-\(UUID().uuidString).sqlite.stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        guard let outputHandle = FileHandle(forWritingAtPath: outputURL.path),
              let errorHandle = FileHandle(forWritingAtPath: errorURL.path)
        else {
            throw SQLiteCommandError(exitCode: -1, message: "Unable to create temporary sqlite output files.")
        }
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-readonly", "-separator", String(SQLiteClientConstants.fieldSeparator), databasePath, query]
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        try process.run()

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        if finished.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + .seconds(2))
            throw SQLiteCommandError(exitCode: -1, message: "sqlite3 timed out.")
        }

        try outputHandle.close()
        try errorHandle.close()

        let output = try String(contentsOf: outputURL, encoding: .utf8)
        let errorOutput = try String(contentsOf: errorURL, encoding: .utf8)

        guard process.terminationStatus == 0 else {
            throw SQLiteCommandError(exitCode: process.terminationStatus, message: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }
}

public struct SQLiteCommandError: LocalizedError, Equatable {
    public var exitCode: Int32
    public var message: String

    public var errorDescription: String? {
        if message.isEmpty {
            return "sqlite3 exited with code \(exitCode)"
        }
        return message
    }
}
