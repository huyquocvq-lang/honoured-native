import Foundation
import GoogleSignIn
import UIKit

/// Runs Google's own sign-in UI and hands back an ID token for the web app to
/// verify with Supabase. Native never decides that anyone is signed in to
/// Honoured, never restores a cached Google user on launch and never logs the
/// token or the nonce.
@MainActor
final class GoogleSignInCoordinator {
    static let shared = GoogleSignInCoordinator()

    enum Outcome {
        case success(idToken: String, accessToken: String?)
        case failure(GoogleAuthFailure)
    }

    /// Nil when the public client IDs are missing, malformed or the callback
    /// scheme is not registered: the feature then reports `configured: false`
    /// instead of letting the SDK raise an exception.
    let config: GoogleClientConfig?

    private init() {
        config = AppConfig.googleClientConfig
    }

    var isConfigured: Bool {
        #if DEBUG
        if BridgeStub.fakeGoogleOutcome != nil { return true }
        #endif
        return config != nil
    }

    var callbackScheme: String? { config?.callbackScheme }

    /// Presents Google's UI. `hashedNonce` is what Google embeds in the ID
    /// token; the caller keeps the raw value for Supabase.
    func present(hashedNonce: String) async -> Outcome {
        #if DEBUG
        if let fake = BridgeStub.fakeGoogleOutcome {
            return await BridgeStub.fakeGoogle(fake, hashedNonce: hashedNonce)
        }
        #endif
        guard let config else { return .failure(.notConfigured) }
        guard let presenter = Self.topViewController() else { return .failure(.provider) }

        let signIn = GIDSignIn.sharedInstance
        signIn.configuration = GIDConfiguration(clientID: config.clientID, serverClientID: config.serverClientID)
        return await withCheckedContinuation { continuation in
            signIn.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            ) { result, error in
                if let error {
                    continuation.resume(returning: .failure(Self.failure(for: error)))
                    return
                }
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString, !idToken.isEmpty else {
                    continuation.resume(returning: .failure(.provider))
                    return
                }
                let accessToken = user.accessToken.tokenString
                continuation.resume(returning: .success(
                    idToken: idToken,
                    accessToken: accessToken.isEmpty ? nil : accessToken
                ))
            }
        }
    }

    /// Clears the SDK's own cached Google user on this device. It does not
    /// revoke access and touches no other device.
    func signOut() {
        #if DEBUG
        if BridgeStub.fakeGoogleOutcome != nil { return }
        #endif
        guard config != nil else { return }
        GIDSignIn.sharedInstance.signOut()
    }

    /// Only URLs with the configured callback scheme reach the SDK.
    func handle(_ url: URL) -> Bool {
        guard config != nil else { return false }
        return GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Private

    /// Maps SDK errors to the bridge taxonomy without copying their text,
    /// which could echo request details.
    nonisolated private static func failure(for error: Error) -> GoogleAuthFailure {
        let nsError = error as NSError
        if nsError.domain == GIDSignInError.errorDomain {
            switch nsError.code {
            case GIDSignInError.Code.canceled.rawValue:
                return .cancelled
            case GIDSignInError.Code.hasNoAuthInKeychain.rawValue:
                return .noCredential
            default:
                return .provider
            }
        }
        if nsError.domain == NSURLErrorDomain || Self.isNetworkError(nsError) {
            return .network
        }
        return .provider
    }

    /// AppAuth reports transport failures as its general network error.
    nonisolated private static func isNetworkError(_ error: NSError) -> Bool {
        if error.domain == "org.openid.appauth.general", error.code == -5 { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.domain == NSURLErrorDomain || isNetworkError(underlying)
        }
        return false
    }

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Routes `onOpenURL`. Google's callback goes to the SDK; everything else
/// (the Live Activity `honoured://contract/…` links) keeps its existing route.
@MainActor
enum AppURLRouter {
    static func handle(_ url: URL) {
        switch AppURLRoute.classify(url, googleCallbackScheme: GoogleSignInCoordinator.shared.callbackScheme) {
        case .googleCallback:
            _ = GoogleSignInCoordinator.shared.handle(url)
        case .app:
            LiveActivityCoordinator.shared.open(url)
        }
    }
}
