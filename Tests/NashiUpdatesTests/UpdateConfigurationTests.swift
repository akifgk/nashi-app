import XCTest
@testable import NashiUpdates

final class UpdateConfigurationTests: XCTestCase {
    private var info: [String: Any] {
        ["SUFeedURL": "https://updates.example.com/appcast.xml",
         "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
         "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true]
    }

    func testUnconfiguredBuildCannotStartNetworkUpdates() {
        XCTAssertThrowsError(try UpdateConfiguration(info: [:])) { XCTAssertEqual($0 as? UpdateConfiguration.ConfigurationError, .notConfigured) }
    }
    func testBundledKeyCanEnableAUserSelectedGitHubRepoWithoutAnotherBootstrap() throws {
        var candidate = info
        candidate.removeValue(forKey: "SUFeedURL")
        XCTAssertThrowsError(try UpdateConfiguration(info: candidate)) {
            XCTAssertEqual($0 as? UpdateConfiguration.ConfigurationError, .missingFeed)
        }
        let configuration = try UpdateConfiguration(info: candidate, repository: GitHubRepository("example/private"))
        XCTAssertEqual(configuration.feedURL.absoluteString, "https://github.com/example/private/releases/latest/download/appcast.xml")
        XCTAssertEqual(configuration.publicKey, info["SUPublicEDKey"] as? String)
    }
    func testRepositoryCannotSupplyOrReplaceTheBundledTrustKey() throws {
        var candidate = info
        candidate.removeValue(forKey: "SUFeedURL")
        candidate.removeValue(forKey: "SUPublicEDKey")
        XCTAssertThrowsError(try UpdateConfiguration(info: candidate, repository: GitHubRepository("example/private"))) {
            XCTAssertEqual($0 as? UpdateConfiguration.ConfigurationError, .notConfigured)
        }
        candidate["SUPublicEDKey"] = "invalid"
        XCTAssertThrowsError(try UpdateConfiguration(info: candidate, repository: GitHubRepository("example/private"))) {
            XCTAssertEqual($0 as? UpdateConfiguration.ConfigurationError, .invalidPublicKey)
        }
    }
    func testHTTPSAndPinnedEd25519Key() throws {
        let configuration = try UpdateConfiguration(info: info)
        XCTAssertEqual(configuration.feedURL.absoluteString, "https://updates.example.com/appcast.xml")
        XCTAssertEqual(Data(base64Encoded: configuration.publicKey)?.count, 32)
    }
    func testRejectsUntrustedFeedAddresses() {
        for address in ["http://updates.example.com/feed", "file:///tmp/appcast.xml", "https://user:password@example.com/feed", "https://example.com/feed#fragment", "appcast.xml"] {
            var candidate = info; candidate["SUFeedURL"] = address
            XCTAssertThrowsError(try UpdateConfiguration(info: candidate), address)
        }
    }
    func testDevelopmentHTTPExceptionIsLimitedToLoopback() throws {
        for address in ["http://127.0.0.1:8765/appcast.xml", "http://localhost:8765/appcast.xml", "http://[::1]:8765/appcast.xml"] {
            var candidate = info; candidate["SUFeedURL"] = address
            XCTAssertThrowsError(try UpdateConfiguration(info: candidate))
            candidate["NashiLocalUpdateFeed"] = true
            XCTAssertNoThrow(try UpdateConfiguration(info: candidate))
        }
        for address in ["http://192.168.1.2/feed", "http://localhost.example.com/feed", "http://127.0.0.1.example.com/feed"] {
            var candidate = info; candidate["NashiLocalUpdateFeed"] = true; candidate["SUFeedURL"] = address
            XCTAssertThrowsError(try UpdateConfiguration(info: candidate))
        }
    }
    func testRejectsMalformedAndIncorrectLengthSigningKeys() {
        for key in ["not-a-key", Data(repeating: 1, count: 31).base64EncodedString(), Data(repeating: 1, count: 64).base64EncodedString()] {
            var candidate = info; candidate["SUPublicEDKey"] = key
            XCTAssertThrowsError(try UpdateConfiguration(info: candidate))
        }
    }
    func testBothFeedAndArchiveVerificationAreRequired() {
        for flag in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"] {
            var candidate = info; candidate[flag] = false
            XCTAssertThrowsError(try UpdateConfiguration(info: candidate)) { XCTAssertEqual($0 as? UpdateConfiguration.ConfigurationError, .missingVerification) }
        }
    }
}
