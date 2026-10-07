import AuthenticationServices
import Security
import UIKit

/// Offers to keep an email and password in the person's Passwords (iCloud
/// Keychain) for the web app's domain. A web view never shows iOS's own "Save
/// Password?" prompt, so the app asks for it after a successful sign-in,
/// sign-up or password change. iOS asks the person first; with the domain's
/// `webcredentials` association, the keyboard then offers the password on the
/// sign-in form, unlocked with Face ID or Touch ID.
enum WebCredentialSaver {
    enum SaveError: Error {
        case noWindow
    }

    @MainActor
    static func save(_ credential: WebCredential, host: String, anchor: UIWindow?) async throws {
        if #available(iOS 26.2, *) {
            guard let anchor else { throw SaveError.noWindow }
            try await ASCredentialDataManager().save(
                password: ASPasswordCredential(user: credential.email, password: credential.password),
                for: ASAutoFillURLScope(host: host),
                anchor: anchor
            )
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                SecAddSharedWebCredential(host as CFString, credential.email as CFString, credential.password as CFString) { error in
                    if let error {
                        continuation.resume(throwing: error as Error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}
