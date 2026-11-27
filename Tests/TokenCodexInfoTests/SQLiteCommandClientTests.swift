import Foundation
import XCTest
@testable import TokenCodexInfoCore

final class SQLiteCommandClientTests: XCTestCase {
    func testTemporaryQueryOutputIsReadableOnlyByItsOwner() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("check-output-permissions.py")
        try """
        #!/usr/bin/python3
        import os, stat
        print(format(stat.S_IMODE(os.fstat(1).st_mode), 'o'))
        print(format(stat.S_IMODE(os.fstat(2).st_mode), 'o'))
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let output = try SQLiteCommandClient(executablePath: executable.path)
            .runReadOnlyQuery(databasePath: directory.appendingPathComponent("unused.sqlite").path, query: "SELECT 1;")

        XCTAssertEqual(output.split(whereSeparator: \.isNewline).map(String.init), ["600", "600"])
    }
}
