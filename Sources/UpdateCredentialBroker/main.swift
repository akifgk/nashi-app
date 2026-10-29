// Adapted from the Tendedero personal fork credential broker; see Resources/licenses/Tendedero-MIT.txt.
import Foundation
import LocalAuthentication
import Security
import Darwin

/// NSXPC authenticates each incoming message against the caller requirement
/// compiled into this frozen executable. A PID or caller-supplied path is never
/// an identity; matching the UID is an additional boundary.
enum CredentialBrokerConnectionPolicy {
    static func accepts(user: uid_t, expectedUser: uid_t = getuid()) -> Bool { user == expectedUser }
    static var callerRequirement: String { CredentialBrokerBuildIdentity.callerRequirement }
}

struct CredentialBrokerRepository: Equatable {
    let account: String

    init?(_ value: String) {
        guard value.utf8.count <= 140 else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let owner = parts[0], name = parts[1]
        func alphanumeric(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
        guard (1...39).contains(owner.utf8.count), (1...100).contains(name.utf8.count),
              let first = owner.utf8.first, alphanumeric(first),
              owner.utf8.allSatisfy({ alphanumeric($0) || $0 == 45 }),
              name.utf8.allSatisfy({ alphanumeric($0) || $0 == 45 || $0 == 46 || $0 == 95 }),
              name != ".", name != ".." else { return nil }
        account = owner.lowercased() + "/" + name.lowercased()
    }
}

enum CredentialBrokerQuery {
    // Preserve the existing service and per-repository account, so adopting the
    // helper does not move, replace, or delete a previously saved credential.
    static let service = "local.tangerine.replica.github-updates"

    static func make(repository: CredentialBrokerRepository, allowInteraction: Bool = false) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: repository.account,
                kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: false,
                kSecUseAuthenticationContext as String: context,
                kSecUseAuthenticationUI as String: allowInteraction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail]
    }

    static func validatedToken(_ token: String) -> String? {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 1_024,
              value.utf8.allSatisfy({ (33...126).contains($0) }) else { return nil }
        return value
    }
}

final class CredentialBroker: NSObject, UpdateCredentialBrokerProtocol {
    // The legacy interaction switch is process-global. Every instance shares
    // this queue, so an explicit authorization cannot enable UI for another
    // read, write, or deletion. No operation changes an ACL or partition list.
    private static let queue = DispatchQueue(label: "local.tangerine.replica.credentials.keychain")

    private func error(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "GitHub credential access is unavailable. Authorize access from Tangerine settings."
        ])
    }

    private func perform(allowInteraction: Bool = false, onFailure: @escaping (NSError) -> Void,
                         _ operation: @escaping () -> Void) {
        Self.queue.async { [self] in
            let status = SecKeychainSetUserInteractionAllowed(allowInteraction)
            defer { if SecKeychainSetUserInteractionAllowed(false) != errSecSuccess { _exit(1) } }
            guard status == errSecSuccess else { onFailure(error(status)); return }
            operation()
        }
    }

    public func handshake(withReply reply: @escaping (NSError?) -> Void) { reply(nil) }

    public func readToken(repository: String, allowInteraction: Bool, withReply reply: @escaping (String?, NSError?) -> Void) {
        guard let repository = CredentialBrokerRepository(repository) else { reply(nil, error(errSecParam)); return }
        perform(allowInteraction: allowInteraction, onFailure: { reply(nil, $0) }) { [self] in
            var query = CredentialBrokerQuery.make(repository: repository, allowInteraction: allowInteraction)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            if status == errSecItemNotFound { reply(nil, nil); return }
            guard status == errSecSuccess, let data = value as? Data,
                  let text = String(data: data, encoding: .utf8),
                  let token = CredentialBrokerQuery.validatedToken(text) else {
                reply(nil, error(status == errSecSuccess ? errSecDecode : status)); return
            }
            reply(token, nil)
        }
    }

    public func writeToken(_ token: String, repository: String, withReply reply: @escaping (NSError?) -> Void) {
        guard let repository = CredentialBrokerRepository(repository),
              let token = CredentialBrokerQuery.validatedToken(token) else { reply(error(errSecParam)); return }
        perform(onFailure: reply) { [self] in
            let query = CredentialBrokerQuery.make(repository: repository)
            let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                           kSecAttrLabel as String: "Tangerine updates · \(repository.account)"]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                attributes.forEach { item[$0.key] = $0.value }
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            reply(status == errSecSuccess ? nil : error(status))
        }
    }

    public func deleteToken(repository: String, withReply reply: @escaping (NSError?) -> Void) {
        guard let repository = CredentialBrokerRepository(repository) else { reply(error(errSecParam)); return }
        perform(onFailure: reply) { [self] in
            let status = SecItemDelete(CredentialBrokerQuery.make(repository: repository) as CFDictionary)
            reply(status == errSecSuccess || status == errSecItemNotFound ? nil : error(status))
        }
    }
}

final class CredentialBrokerListener: NSObject, NSXPCListenerDelegate {
    private let broker = CredentialBroker()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard CredentialBrokerConnectionPolicy.accepts(user: connection.effectiveUserIdentifier) else { return false }
        connection.setCodeSigningRequirement(CredentialBrokerConnectionPolicy.callerRequirement)
        connection.exportedInterface = NSXPCInterface(with: UpdateCredentialBrokerProtocol.self)
        connection.exportedObject = broker
        connection.resume()
        return true
    }
}

#if !CREDENTIAL_BROKER_TESTS
@main enum CredentialBrokerMain {
    static func main() {
        guard SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { exit(1) }
        let delegate = CredentialBrokerListener()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        // The frozen service uses RunLoopType=dispatch_main, matching Tende.
        withExtendedLifetime(delegate) { listener.resume() }
    }
}
#endif
