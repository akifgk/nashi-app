import XCTest
@testable import NashiUpdates

final class UpdateCredentialStoreTests: XCTestCase {
    private final class WaitingCredentials: UpdateCredentialStore, @unchecked Sendable {
        let entered: XCTestExpectation
        let release = DispatchSemaphore(value: 0)
        init(entered: XCTestExpectation) { self.entered = entered }
        func token(for repository: GitHubRepository) throws -> String {
            XCTAssertFalse(Thread.isMainThread, "Keychain waits must not run on the UI thread")
            entered.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return "github_pat_waiting_fixture"
        }
        func save(_ token: String, for repository: GitHubRepository) throws { }
        func remove(for repository: GitHubRepository) throws { }
    }

    func testCredentialWaitLeavesMainActorResponsive() async throws {
        let entered = expectation(description: "Credential query started")
        let store = WaitingCredentials(entered: entered)
        defer { store.release.signal() }
        let repository = try GitHubRepository("example/waiting-fixture")
        let started = ProcessInfo.processInfo.systemUptime
        let read = Task { @MainActor in try await store.loadToken(for: repository) }
        await fulfillment(of: [entered], timeout: 1)
        let heartbeat = await MainActor.run { ProcessInfo.processInfo.systemUptime }
        XCTAssertLessThan(heartbeat - started, 1, "The main actor must run while credential access is still waiting")
        store.release.signal()
        let value = try await read.value
        XCTAssertEqual(value, "github_pat_waiting_fixture")
    }

    func testTokenValidationTrimsPasteButRejectsHeaderInjection() throws {
        XCTAssertEqual(try KeychainUpdateCredentialStore.validate("  github_pat_testonly\n"), "github_pat_testonly")
        for token in ["", " \n", "abc def", "abc\r\nAuthorization: other", "abc\u{0}def", "şifre", String(repeating: "x", count: 1_025)] {
            XCTAssertThrowsError(try KeychainUpdateCredentialStore.validate(token)) { error in
                XCTAssertEqual(error as? UpdateCredentialError, .invalidToken)
            }
        }
    }

    func testKeychainRoundTripReplacementAndRepositoryIsolation() throws {
        // Fresh service/account names; never read or delete a user's real item.
        let store = KeychainUpdateCredentialStore(service: "local.nashi.tests.updates.\(UUID().uuidString)")
        let first = try GitHubRepository("example/updater-test")
        let same = try GitHubRepository("EXAMPLE/UPDATER-TEST")
        let other = try GitHubRepository("example/another-test")
        defer { try? store.remove(for: first); try? store.remove(for: other) }
        XCTAssertThrowsError(try store.token(for: first)) { XCTAssertEqual($0 as? UpdateCredentialError, .missing) }
        try store.save("github_pat_fixture_one", for: first)
        XCTAssertEqual(try store.token(for: same), "github_pat_fixture_one")
        XCTAssertThrowsError(try store.token(for: other)) { XCTAssertEqual($0 as? UpdateCredentialError, .missing) }
        try store.save("github_pat_fixture_two", for: same)
        XCTAssertEqual(try store.token(for: first), "github_pat_fixture_two")
        XCTAssertThrowsError(try store.save("invalid token", for: first))
        XCTAssertEqual(try store.token(for: first), "github_pat_fixture_two")
        try store.remove(for: same)
        XCTAssertThrowsError(try store.token(for: first)) { XCTAssertEqual($0 as? UpdateCredentialError, .missing) }
        XCTAssertNoThrow(try store.remove(for: first))
    }

    func testCredentialErrorsNeverIncludeTheToken() {
        for error in [UpdateCredentialError.missing, .locked, .invalidToken, .unavailable(-1)] {
            XCTAssertFalse(error.localizedDescription.contains("github_pat_fixture"))
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
