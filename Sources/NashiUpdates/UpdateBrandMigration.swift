import Foundation

/// Names displayed to the user are current. The existing Keychain account and
/// signed, frozen helper remain stable so a rebrand never asks for the PAT again.
enum UpdateBrandMigration {
    static let previous=try! GitHubRepository("orkunisitmak/tangerine")
    static let current=try! GitHubRepository("orkunisitmak/nashi")
    static func canonical(_ repository:GitHubRepository)->GitHubRepository { repository==previous ? current:repository }
    static func credentialAccount(_ repository:GitHubRepository)->GitHubRepository { repository==current ? previous:repository }
    static func acceptsArchive(owner:String,name:String,for repository:GitHubRepository)->Bool {
        let slug=owner.lowercased()+"/"+name.lowercased()
        return slug==repository.slug || (repository==current && slug==previous.slug)
    }
    /// The bridge must be installed before GitHub is renamed: the previous app
    /// rejects metadata redirects. Only this explicitly renamed repository may
    /// fall back, only while the new repository has no readable release, and all
    /// feeds/archives still require the pinned Sparkle signature.
    static func latestFeed(repository:GitHubRepository,token:String?,configuration:URLSessionConfiguration = .ephemeral) async throws -> (GitHubUpdateClient,Data) {
        let client=GitHubUpdateClient(repository:repository,token:token,configuration:configuration)
        do { return (client,try await client.fetchLatestAppcast()) }
        catch GitHubUpdateTransportError.noRelease where repository==current {
            let previousClient=GitHubUpdateClient(repository:previous,token:token,configuration:configuration)
            return (previousClient,try await previousClient.fetchLatestAppcast())
        }
    }
}
