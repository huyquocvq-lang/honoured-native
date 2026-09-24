import CryptoKit
import Foundation

/// Only one system sign-in UI at a time. Apple and Google share this lock, and
/// a Google cleanup holds it too, so a sign-out still running cannot overlap a
/// new sign-in. Main thread only.
final class ProviderPresentationGate {
    enum Holder: Equatable {
        case apple
        case google
        case googleCleanup
    }

    private(set) var holder: Holder?
    private var token = 0

    /// Returns a token for `release`, or nil when another holder is active.
    func acquire(_ holder: Holder) -> Int? {
        guard self.holder == nil else { return nil }
        self.holder = holder
        token += 1
        return token
    }

    /// Releases only the holder that owns `token`; a stale release is ignored.
    func release(_ token: Int) {
        guard token == self.token else { return }
        holder = nil
    }
}

enum AuthNonce {
    /// 32 random bytes as 64 hex characters, and the SHA-256 hex digest of that
    /// string. The provider sees the digest; Supabase gets the raw value.
    static func make() -> (raw: String, hashed: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        let raw = bytes.map { String(format: "%02x", $0) }.joined()
        return (raw, sha256Hex(raw))
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Public Google client configuration. None of these values is a secret, but a
/// malformed or missing one must turn the feature off instead of letting the
/// SDK raise an exception at presentation time.
struct GoogleClientConfig: Equatable {
    let clientID: String
    let serverClientID: String
    let callbackScheme: String

    private static let suffix = ".apps.googleusercontent.com"
    private static let schemePrefix = "com.googleusercontent.apps."

    /// - Parameter registeredSchemes: every `CFBundleURLSchemes` entry of the
    ///   app. The SDK requires the reversed iOS client ID among them.
    static func validate(
        clientID rawClientID: String,
        serverClientID rawServerClientID: String,
        registeredSchemes: [String]
    ) -> GoogleClientConfig? {
        let clientID = rawClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverClientID = rawServerClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isClientID(clientID), isClientID(serverClientID), clientID != serverClientID else { return nil }
        let scheme = schemePrefix + String(clientID.dropLast(suffix.count))
        guard registeredSchemes.contains(where: { $0.caseInsensitiveCompare(scheme) == .orderedSame }) else { return nil }
        return GoogleClientConfig(clientID: clientID, serverClientID: serverClientID, callbackScheme: scheme)
    }

    private static func isClientID(_ value: String) -> Bool {
        guard value.hasSuffix(suffix), value.count > suffix.count else { return false }
        let prefix = value.dropLast(suffix.count)
        return prefix.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}

/// Where an incoming URL goes. Only the configured Google callback scheme
/// reaches the Google SDK; everything else keeps its existing route.
enum AppURLRoute: Equatable {
    case googleCallback
    case app

    static func classify(_ url: URL, googleCallbackScheme: String?) -> AppURLRoute {
        if let googleCallbackScheme,
           let scheme = url.scheme,
           scheme.caseInsensitiveCompare(googleCallbackScheme) == .orderedSame {
            return .googleCallback
        }
        return .app
    }
}

/// The exact origin (scheme, host, port) the auth bridge trusts, derived from
/// the configured web app URL. No wildcard and no suffix matching.
struct TrustedWebOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = url.port ?? 443
    }

    func matches(scheme: String?, host: String?, port: Int?) -> Bool {
        guard let scheme = scheme?.lowercased(), let host = host?.lowercased() else { return false }
        // WebKit reports 0 for the default port of the scheme.
        let resolvedPort = (port == nil || port == 0) ? (scheme == "https" ? 443 : -1) : port!
        return scheme == self.scheme && host == self.host && resolvedPort == self.port
    }

    func matches(url: URL?) -> Bool {
        guard let url else { return false }
        return matches(scheme: url.scheme, host: url.host, port: url.port)
    }
}

/// Runs async operations strictly one after another, in submission order.
/// Used for auth session writes and billing identity changes, so a slow older
/// operation can never finish after a newer one. Submission order is the
/// order of `enqueue` calls; submit from one thread to make that meaningful.
final class SerialAsyncQueue {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    func enqueue(_ operation: @escaping () async -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let previous = tail
        tail = Task {
            await previous?.value
            await operation()
        }
    }

    /// Enqueues and waits for this operation's own result.
    func run<T>(_ operation: @escaping () async -> T) async -> T {
        await withCheckedContinuation { continuation in
            enqueue {
                continuation.resume(returning: await operation())
            }
        }
    }
}
