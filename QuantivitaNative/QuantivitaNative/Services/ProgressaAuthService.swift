import Foundation
import Security
import UIKit

enum ProgressaAuthError: LocalizedError {
    case alreadyInProgress
    case couldNotOpen
    case invalidCallback
    case stateMismatch
    case denied(String)

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress: return "A Progressa connection is already in progress."
        case .couldNotOpen: return "Progressa could not be opened. Check your connection and try again."
        case .invalidCallback: return "Progressa did not return a valid connection code."
        case .stateMismatch: return "The Progressa callback could not be verified. Please try again."
        case let .denied(reason): return reason == "access_denied" ? "Progressa connection was cancelled." : "Progressa connection failed: \(reason)"
        }
    }
}

@MainActor
final class ProgressaAuthService {
    private let webBaseURL = URL(string: "https://api.progressa.bryandijkh.com")!
    private var pendingState: String?
    private var continuation: CheckedContinuation<String, Error>?

    func authorize() async throws -> String {
        guard continuation == nil else { throw ProgressaAuthError.alreadyInProgress }
        let state = randomState()
        pendingState = state

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            openAuthorization(state: state)
        }
    }

    @discardableResult
    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme == "quantivita",
              url.host == "quantivita.app",
              url.path == "/progressa-auth",
              continuation != nil else { return false }

        do {
            finish(.success(try Self.code(from: url, expectedState: pendingState ?? "")))
        } catch {
            finish(.failure(error))
        }
        return true
    }

    static func code(from url: URL, expectedState: String) throws -> String {
        guard url.scheme == "quantivita", url.host == "quantivita.app", url.path == "/progressa-auth" else {
            throw ProgressaAuthError.invalidCallback
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard components?.queryItems?.first(where: { $0.name == "state" })?.value == expectedState else {
            throw ProgressaAuthError.stateMismatch
        }
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            throw ProgressaAuthError.denied(error)
        }
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw ProgressaAuthError.invalidCallback
        }
        return code
    }

    private func openAuthorization(state: String) {
        let query = [
            URLQueryItem(name: "redirect_uri", value: "quantivita://quantivita.app/progressa-auth"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "workouts:read"),
        ]
        var appComponents = URLComponents()
        appComponents.scheme = "progressa"
        appComponents.host = "quantivita-connect"
        appComponents.queryItems = query

        var webComponents = URLComponents(
            url: webBaseURL.appendingPathComponent("quantivita/connect"),
            resolvingAgainstBaseURL: false
        )!
        webComponents.queryItems = query

        let appURL = appComponents.url!
        let target = UIApplication.shared.canOpenURL(appURL) ? appURL : webComponents.url!
        UIApplication.shared.open(target) { [weak self] opened in
            guard !opened else { return }
            self?.finish(.failure(ProgressaAuthError.couldNotOpen))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        let pending = continuation
        continuation = nil
        pendingState = nil
        pending?.resume(with: result)
    }

    private func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
