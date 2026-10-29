import Foundation
import Security
import LocalAuthentication

public enum UpdateCredentialError: LocalizedError, Equatable {
    case missing, locked, invalidToken, unavailable(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .missing: return "Enter a GitHub token to connect this private repository."
        case .locked: return "macOS could not authorize access to the saved update token. Unlock your login Keychain or save the connection again."
        case .invalidToken: return "Enter a token without spaces or line breaks."
        case .unavailable: return "macOS could not access the saved update token. Try again after unlocking your login Keychain."
        }
    }
}

/// Only the token lives here. Repository selection and UI preferences are not secrets.
public protocol UpdateCredentialStore: Sendable {
    func token(for repository: GitHubRepository) throws -> String
    func authorizeToken(for repository: GitHubRepository) throws -> String
    func save(_ token: String, for repository: GitHubRepository) throws
    func remove(for repository: GitHubRepository) throws
}

public extension UpdateCredentialStore {
    func authorizeToken(for repository: GitHubRepository) throws -> String { try token(for: repository) }

    /// Security.framework can wait on the login Keychain. Never block the UI executor.
    func loadToken(for repository: GitHubRepository, authorizingAccess: Bool = false) async throws -> String {
        let token = try await Task.detached {
            try authorizingAccess ? self.authorizeToken(for: repository) : self.token(for: repository)
        }.value
        try Task.checkCancellation()
        return token
    }

    func storeToken(_ token: String, for repository: GitHubRepository) async throws {
        try await Task.detached { try self.save(token, for: repository) }.value
    }

    func removeToken(for repository: GitHubRepository) async throws {
        try await Task.detached { try self.remove(for: repository) }.value
    }
}

public final class KeychainUpdateCredentialStore: UpdateCredentialStore, @unchecked Sendable {
    // Legacy Keychain's interaction flag is process-wide. Serialize every operation
    // in this store so an explicit save cannot overlap a silent background read.
    private static let interactionLock = NSLock()
    private let service: String

    public init(service: String = "local.tangerine.replica.github-updates") {
        self.service = service
    }

    public static func validate(_ token: String) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 1_024,
              trimmed.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            throw UpdateCredentialError.invalidToken
        }
        return trimmed
    }

    private func query(for repository: GitHubRepository) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: repository.slug.lowercased(),
         kSecAttrSynchronizable as String: false]
    }

    public func token(for repository: GitHubRepository) throws -> String {
        try readToken(for: repository, allowingInteraction: false)
    }

    /// Used only by the explicit Save Connection action, never scheduled checks.
    public func authorizeToken(for repository: GitHubRepository) throws -> String {
        try readToken(for: repository, allowingInteraction: true)
    }

    private func readToken(for repository: GitHubRepository, allowingInteraction: Bool) throws -> String {
        Self.interactionLock.lock()
        defer { Self.interactionLock.unlock() }
        var query = query(for: repository)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // LAContext only suppresses authentication UI for the Data Protection
        // Keychain. File-based login Keychains also need this legacy scoped flag.
        // The deprecated API remains necessary on macOS; the modern replacement
        // does not cover these items (see Security.framework's SecItem.h).
        var interactionWasAllowed: DarwinBoolean = false
        try check(SecKeychainGetUserInteractionAllowed(&interactionWasAllowed))
        try check(SecKeychainSetUserInteractionAllowed(allowingInteraction))
        defer { SecKeychainSetUserInteractionAllowed(interactionWasAllowed.boolValue) }
        let context = LAContext()
        context.interactionNotAllowed = !allowingInteraction
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        try check(status)
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw UpdateCredentialError.missing
        }
        return try Self.validate(token)
    }

    public func save(_ token: String, for repository: GitHubRepository) throws {
        let token = try Self.validate(token)
        Self.interactionLock.lock()
        defer { Self.interactionLock.unlock() }
        let query = query(for: repository)
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                       kSecAttrLabel as String: "Nashi updates · \(repository.slug)"]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            // Default login-Keychain access is restricted to the saving app.
            // Do not grant all applications access to hide signing/ACL prompts.
            status = SecItemAdd(item as CFDictionary, nil)
        }
        try check(status)
    }

    public func remove(for repository: GitHubRepository) throws {
        Self.interactionLock.lock()
        defer { Self.interactionLock.unlock() }
        let status = SecItemDelete(query(for: repository) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecItemNotFound: throw UpdateCredentialError.missing
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: throw UpdateCredentialError.locked
        default: throw UpdateCredentialError.unavailable(status)
        }
    }
}
