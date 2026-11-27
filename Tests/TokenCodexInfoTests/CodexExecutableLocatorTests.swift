import Foundation
import XCTest
@testable import TokenCodexInfoCore

final class CodexExecutableLocatorTests: XCTestCase {
    private func withApp(named name: String, executablePath: String, body: (URL, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appendingPathComponent(name)
        let executable = app.appendingPathComponent(executablePath)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture executable; never run".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try body(app, executable)
    }

    func testFindsCurrentDesktopBundleWithoutASeparateCliInstallation() throws {
        try withApp(named: "ChatGPT.app", executablePath: "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex") { app, executable in
            XCTAssertEqual(CodexExecutableLocator.locate(applications: [app], searchPaths: []), executable.resolvingSymlinksInPath())
        }
    }

    func testFindsDesktopWrapperInAnAppAtANonstandardLocation() throws {
        try withApp(named: "Renamed Codex.app", executablePath: "Contents/Resources/codex-cli/bin/codex") { app, executable in
            XCTAssertEqual(CodexExecutableLocator.locate(applications: [app], searchPaths: []), executable.resolvingSymlinksInPath())
        }
    }

    func testStillFindsLegacyDesktopBundle() throws {
        try withApp(named: "Codex.app", executablePath: "Contents/Resources/codex") { app, executable in
            XCTAssertEqual(CodexExecutableLocator.locate(applications: [app], searchPaths: []), executable.resolvingSymlinksInPath())
        }
    }
}
