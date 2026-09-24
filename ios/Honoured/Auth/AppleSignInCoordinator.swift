import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Runs Sign in with Apple on behalf of the web app. Native only produces the
/// credential: the web app links it to the current (anonymous) Supabase user
/// with `linkIdentity`, which is what keeps every synced HealthKit row attached
/// to the same `user_id`. Nothing here is ever logged — the identity token,
/// the authorization code and the nonce all travel straight to the bridge.
@MainActor
final class AppleSignInCoordinator: NSObject {
    static let shared = AppleSignInCoordinator()

    enum Outcome {
        case success(payload: [String: Any])
        case cancelled
        case failed(message: String)
    }

    /// Posted when Apple reports the stored credential as revoked or missing,
    /// either at launch or through `credentialRevokedNotification`.
    static let revokedEventType = "APPLE_CREDENTIAL_REVOKED"

    private let appleUserIDKey = "apple.user-id"
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var rawNonce: String?
    private var revocationObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    // MARK: - Sign in

    /// Shows the system sheet. One request at a time: a second call while the
    /// sheet is up fails immediately instead of stacking presentations.
    func signIn() async -> Outcome {
        guard continuation == nil else {
            return .failed(message: "A Sign in with Apple request is already in progress")
        }

        let nonce = Self.randomNonce()
        rawNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256Hex(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    // MARK: - Credential state

    /// Checks the stored Apple user at launch. Apple asks apps to do this so a
    /// credential revoked from Settings does not keep working silently; the web
    /// app decides what signing out means for the account.
    func checkCredentialStateIfNeeded() {
        guard let userID = storedAppleUserID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            switch state {
            case .revoked, .notFound:
                Task { @MainActor in self?.handleRevocation(reason: state == .revoked ? "revoked" : "not_found") }
            case .authorized, .transferred:
                break
            @unknown default:
                break
            }
        }
    }

    func observeRevocation() {
        guard revocationObserver == nil else { return }
        revocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleRevocation(reason: "revoked") }
        }
    }

    /// The account changed or signed out: the Apple user no longer describes
    /// whoever native is syncing for.
    func clear() {
        UserDefaults.standard.removeObject(forKey: appleUserIDKey)
    }

    private var storedAppleUserID: String? {
        UserDefaults.standard.string(forKey: appleUserIDKey)
    }

    private func handleRevocation(reason: String) {
        guard let userID = storedAppleUserID else { return }
        clear()
        NativeBridgeEvents.post(type: Self.revokedEventType, payload: ["userId": userID, "reason": reason])
    }

    // MARK: - Completion

    private func finish(_ outcome: Outcome) {
        let continuation = continuation
        self.continuation = nil
        controller = nil
        rawNonce = nil
        continuation?.resume(returning: outcome)
    }

    // MARK: - Nonce

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // SecRandomCopyBytes only fails when the system RNG is unavailable;
            // fall back to the CSPRNG behind SystemRandomNumberGenerator.
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty,
              let rawNonce else {
            finish(.failed(message: "Apple did not return an identity token"))
            return
        }

        UserDefaults.standard.set(credential.user, forKey: appleUserIDKey)

        var user: [String: Any] = ["id": credential.user]
        // Email and name arrive on the very first authorization only. Absent keys,
        // not empty strings, so the web app can tell "not provided" apart.
        if let email = credential.email, !email.isEmpty {
            user["email"] = email
        }
        if let components = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let fullName = formatter.string(from: components).trimmingCharacters(in: .whitespaces)
            if !fullName.isEmpty {
                user["fullName"] = fullName
            }
        }

        var payload: [String: Any] = [
            "identityToken": identityToken,
            "rawNonce": rawNonce,
            "user": user
        ]
        if let codeData = credential.authorizationCode,
           let authorizationCode = String(data: codeData, encoding: .utf8),
           !authorizationCode.isEmpty {
            payload["authorizationCode"] = authorizationCode
        }

        finish(.success(payload: payload))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            finish(.cancelled)
            return
        }
        finish(.failed(message: error.localizedDescription))
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}
