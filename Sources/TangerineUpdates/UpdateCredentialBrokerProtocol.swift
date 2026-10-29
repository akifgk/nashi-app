// Adapted from the Tendedero personal fork credential broker; see Resources/licenses/Tendedero-MIT.txt.
import Foundation

/// Shared by the app and its frozen, mutually authenticated XPC service.
/// Credentials have no command-line or standard-output interface.
@objc(TangerineUpdateCredentialBrokerProtocol)
public protocol UpdateCredentialBrokerProtocol {
    func handshake(withReply reply: @escaping (NSError?) -> Void)
    func readToken(repository: String, allowInteraction: Bool, withReply reply: @escaping (String?, NSError?) -> Void)
    func writeToken(_ token: String, repository: String, withReply reply: @escaping (NSError?) -> Void)
    func deleteToken(repository: String, withReply reply: @escaping (NSError?) -> Void)
}
