import Foundation
import LocalAuthentication
import Security

/// Standalone swiftc fixture runner. It never queries or changes a Keychain.
/// Compile with CREDENTIAL_BROKER_TESTS, the shared protocol, helper source, and
/// a generated CredentialBrokerBuildIdentity fixture.
@main enum CredentialBrokerFixtures {
    static func main() {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            guard condition() else { fputs("Credential broker fixture failed: \(description)\n", stderr); exit(1) }
            assertions += 1
        }

        check(CredentialBrokerConnectionPolicy.accepts(user: 501, expectedUser: 501), "matching UID")
        check(!CredentialBrokerConnectionPolicy.accepts(user: 502, expectedUser: 501), "different UID")
        check(CredentialBrokerConnectionPolicy.callerRequirement == CredentialBrokerBuildIdentity.callerRequirement,
              "compiled caller requirement")

        for value in ["owner/repo", "Owner/Repository.Name_1-2", String(repeating: "a", count: 39) + "/" + String(repeating: "b", count: 100)] {
            check(CredentialBrokerRepository(value) != nil, "valid repository shape")
        }
        check(CredentialBrokerRepository("Owner/Repository.Name_1-2")?.account == "owner/repository.name_1-2",
              "normalized account keeps existing slug convention")
        check(CredentialBrokerRepository("owner/repo.git")?.account == "owner/repo.git", "canonical slug is not rewritten")
        for value in ["", "/", "owner", "owner/", "/repo", "owner/repo/extra", "owner//repo",
                      "https://github.com/owner/repo", " owner/repo", "owner/repo ", "owner/repo\n", "owner/repo\r",
                      "\nowner/repo", "owner/repo\0", "-owner/repo", "own_er/repo", "owner/name with spaces",
                      "İstanbul/repo", "owner/répo", "owner/.", "owner/..", "owner/a\\b", "owner/a%2Fb",
                      String(repeating: "a", count: 40) + "/repo", "owner/" + String(repeating: "b", count: 101)] {
            check(CredentialBrokerRepository(value) == nil, "invalid repository is rejected")
        }

        check(CredentialBrokerQuery.validatedToken("  fixture-token_123\n") == "fixture-token_123", "store-compatible trimming")
        check(CredentialBrokerQuery.validatedToken(String(repeating: "x", count: 1_024)) != nil, "1024-byte token limit")
        check(CredentialBrokerQuery.validatedToken("!") == "!", "visible ASCII accepts current store's minimum")
        check(CredentialBrokerQuery.validatedToken("~!@#$%^&*()_+-=[]{}:;,.?/|") != nil, "visible ASCII punctuation")
        for value in ["", " \n", "fixture token", "fixture\ntoken", "fixture\ttoken", "fixture\0token",
                      "fixture\u{7f}token", "café", "fixture🍊", String(repeating: "x", count: 1_025)] {
            check(CredentialBrokerQuery.validatedToken(value) == nil, "invalid token is rejected")
        }

        let repository = CredentialBrokerRepository("Owner/Repo")!
        for allowInteraction in [false, true] {
            let query = CredentialBrokerQuery.make(repository: repository, allowInteraction: allowInteraction)
            check(query[kSecAttrService as String] as? String == "local.tangerine.replica.github-updates", "existing service preserved")
            check(query[kSecAttrAccount as String] as? String == "owner/repo", "per-repository account preserved")
            check(query[kSecAttrSynchronizable as String] as? Bool == false, "non-synchronizing query")
            check(query[kSecUseDataProtectionKeychain as String] as? Bool == false, "legacy login Keychain")
            check((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == !allowInteraction,
                  "LAContext interaction policy")
            check(query[kSecUseAuthenticationUI as String] as? String ==
                  (allowInteraction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail) as String,
                  "Security authentication UI policy")
            check(query[kSecAttrAccess as String] == nil && query[kSecAttrAccessControl as String] == nil,
                  "no ACL or access-control override")
        }

        let broker = CredentialBroker()
        var readReply = false
        broker.readToken(repository: "owner/repo\n", allowInteraction: true) { token, error in
            check(token == nil && error?.domain == NSOSStatusErrorDomain && error?.code == Int(errSecParam),
                  "invalid read repository returns OSStatus without accessing Keychain")
            readReply = true
        }
        check(readReply, "invalid read returns immediately")
        var writeReply = false
        let invalidSyntheticToken = "REJECT_ME_SYNTHETIC token"
        broker.writeToken(invalidSyntheticToken, repository: "owner/repo") { error in
            check(error?.domain == NSOSStatusErrorDomain && error?.code == Int(errSecParam), "invalid write token returns OSStatus")
            check(error?.localizedDescription.contains(invalidSyntheticToken) == false, "error never includes token")
            writeReply = true
        }
        check(writeReply, "invalid write returns immediately")
        var deleteReply = false
        broker.deleteToken(repository: "https://github.com/owner/repo") { error in
            check(error?.domain == NSOSStatusErrorDomain && error?.code == Int(errSecParam), "invalid delete repository returns OSStatus")
            deleteReply = true
        }
        check(deleteReply, "invalid delete returns immediately")
        var handshakeReply = false
        broker.handshake { error in check(error == nil, "handshake has no credential access"); handshakeReply = true }
        check(handshakeReply, "handshake returns")

        print("Credential broker fixtures: \(assertions) checks passed; no Keychain items accessed.")
    }
}
