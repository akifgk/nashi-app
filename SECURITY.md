# Security policy

Nashi processes files locally. It does not run a cloud API, collect analytics,
import browser cookies, or ask for an account for official public updates.
Web downloads contact the URL/site you choose. Updates use HTTPS and a pinned
Ed25519 public key; signing private keys and developer certificates are never
part of the source repository or application resources.

Please report a suspected vulnerability using GitHub's private **Report a
vulnerability** form in this repository's Security tab. Do not post credentials,
private documents, exploit attachments or personal data in a public issue.
If private reporting is temporarily unavailable, open an issue asking for a
private contact without disclosing the vulnerability details.

Only the latest stable release is supported. No audit can guarantee that a
media/document parser or a dependency is free of vulnerabilities. Avoid opening
files from untrusted sources and keep the app and operating system current.

## Contribution and release boundaries

Pull-request checks receive read-only repository permissions and no signing
secrets. Do not add `pull_request_target` jobs that execute contributor code,
self-hosted runners, plaintext credentials, or user-provided shell command text.
Production updates must be signed by the maintainer's offline/local signing
identity, then verified before publication. A successful build artifact alone
is not an official signed release.

Private workspaces, historical analysis, credentials, certificates, browser
profiles, local paths, and raw user files are excluded from this repository.
