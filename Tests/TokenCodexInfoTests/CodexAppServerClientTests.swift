import Foundation
import XCTest
@testable import TokenCodexInfoCore

final class CodexAppServerClientTests: XCTestCase {
    func testInheritedApiCredentialsCannotOverrideCodexSignIn() {
        let environment = CodexAppServerClient.subprocessEnvironment(
            codexHome: URL(fileURLWithPath: "/chosen-codex-folder"),
            inherited: ["HOME": "/home", "OPENAI_API_KEY": "fixture-only", "CODEX_ACCESS_TOKEN": "fixture-only", "CODEX_HOME": "/other-folder"]
        )
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertNil(environment["CODEX_ACCESS_TOKEN"])
        XCTAssertEqual(environment["CODEX_HOME"], "/chosen-codex-folder")
        XCTAssertEqual(environment["HOME"], "/home")
    }

    private func withExecutable(_ script: String, body: (URL, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = folder.appendingPathComponent("fake-codex.py")
        try ("#!/usr/bin/python3\n" + script + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try body(executable, folder)
    }

    func testHandshakeRequestsOnlyLimitsAndDiscardsAccountMetadata() throws {
        try withExecutable("""
        import sys, json, os
        first = json.loads(sys.stdin.readline())
        assert first['method'] == 'initialize'
        print(json.dumps({'id':first['id'],'result':{'userAgent':'fixture'}}), flush=True)
        assert json.loads(sys.stdin.readline())['method'] == 'initialized'
        request = json.loads(sys.stdin.readline())
        assert request['method'] == 'account/rateLimits/read'
        assert os.path.realpath(os.environ['CODEX_HOME']) == os.path.dirname(os.path.realpath(__file__))
        print(json.dumps({'id':request['id'],'result':{
            'accountId':'private-fixture-account',
            'rateLimits':{'limitId':'codex','primary':{'usedPercent':17,'windowDurationMins':300,'resetsAt':23600,'extra':'must-not-leave-transport'}},
            'unrelated':'must-not-leave-transport'
        }}), flush=True)
        sys.stdin.read()
        """) { executable, folder in
            let data = try CodexAppServerClient(executableURL: executable, timeoutSeconds: 3).readRateLimits(codexHome: folder)
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(text.contains("usedPercent"))
            XCTAssertFalse(text.contains("private-fixture-account"))
            XCTAssertFalse(text.contains("must-not-leave-transport"))
            XCTAssertFalse(text.contains("accountId"))
        }
    }

    func testHungServerTimesOutInsteadOfLeavingRefreshStuck() throws {
        try withExecutable("import time\ntime.sleep(30)") { executable, folder in
            let started = Date()
            XCTAssertThrowsError(try CodexAppServerClient(executableURL: executable, timeoutSeconds: 0.1).readRateLimits(codexHome: folder)) { error in
                guard case CodexAccountReadError.timedOut = error else { return XCTFail("Expected a timeout") }
            }
            XCTAssertLessThan(Date().timeIntervalSince(started), 4)
        }
    }

    func testRawServerErrorsAreNotExposed() throws {
        try withExecutable("""
        import sys, json
        request = json.loads(sys.stdin.readline())
        print(json.dumps({'id':request['id'],'error':{'code':-32000,'message':'private-fixture-account'}}), flush=True)
        sys.stdin.read()
        """) { executable, folder in
            XCTAssertThrowsError(try CodexAppServerClient(executableURL: executable, timeoutSeconds: 3).readRateLimits(codexHome: folder)) { error in
                XCTAssertFalse(error.localizedDescription.contains("private-fixture-account"))
            }
        }
    }
}
