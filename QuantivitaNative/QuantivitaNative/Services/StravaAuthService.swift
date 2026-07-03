import AuthenticationServices
import Foundation
import Security

enum StravaAuthError: LocalizedError {
    case invalidCallback
    case stateMismatch
    case denied(String)
    case alreadyAuthorizing
    case cancelled
    var errorDescription: String? {
        switch self {
        case .invalidCallback: return "Strava did not return an authorization code."
        case .stateMismatch: return "The Strava callback could not be verified."
        case let .denied(reason): return "Strava authorization failed: \(reason)"
        case .alreadyAuthorizing: return "Strava authorization is already open."
        case .cancelled: return "Strava authorization was cancelled."
        }
    }
}

struct StravaAuthorization: Equatable {
    let code: String
    let scopes: [String]
}

@MainActor
final class StravaAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var state: String?
    private var session: ASWebAuthenticationSession?

    func newState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return UUID().uuidString }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }

    func authorize(url: URL, state: String) async throws -> StravaAuthorization {
        guard session == nil else { throw StravaAuthError.alreadyAuthorizing }
        self.state = state
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "quantivita") { [weak self] callback, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.session = nil
                    defer { self.state = nil }
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: StravaAuthError.cancelled)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else if let callback {
                        do { continuation.resume(returning: try Self.authorization(from: callback, expectedState: self.state ?? "")) }
                        catch { continuation.resume(throwing: error) }
                    } else {
                        continuation.resume(throwing: StravaAuthError.invalidCallback)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            guard session.start() else {
                self.session = nil
                self.state = nil
                continuation.resume(throwing: StravaAuthError.invalidCallback)
                return
            }
        }
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        session != nil && url.scheme == "quantivita" && url.host == "quantivita.app" && url.path == "/strava-auth"
    }

    static func code(from url: URL, expectedState: String) throws -> String {
        try authorization(from: url, expectedState: expectedState).code
    }

    static func authorization(from url: URL, expectedState: String) throws -> StravaAuthorization {
        guard url.scheme == "quantivita", url.host == "quantivita.app", url.path == "/strava-auth" else {
            throw StravaAuthError.invalidCallback
        }
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard values.first(where: { $0.name == "state" })?.value == expectedState else {
            throw StravaAuthError.stateMismatch
        }
        if let error = values.first(where: { $0.name == "error" })?.value {
            throw StravaAuthError.denied(error)
        }
        guard let code = values.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw StravaAuthError.invalidCallback
        }
        let scopes = values.first(where: { $0.name == "scope" })?.value?
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        return StravaAuthorization(code: code, scopes: scopes)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
