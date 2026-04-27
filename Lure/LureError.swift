import Foundation

enum LureError: LocalizedError, Sendable {
    case notAuthenticated
    case invalidCredentials
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case serverError(statusCode: Int, message: String?)
    case noServerConfigured
    case connectionFailed
    case keychainError
    case quotaExceeded
    case duplicateRequest
    case blacklistedMedia

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Not signed in. Please log in again."
        case .invalidCredentials: "Invalid username or password."
        case .networkError(let e): "Network error: \(e.localizedDescription)"
        case .invalidResponse: "Invalid response from server."
        case .decodingError(let e): "Failed to parse response: \(e.localizedDescription)"
        case .serverError(let code, let msg): "Server error (\(code)): \(msg ?? "Unknown")"
        case .noServerConfigured: "No server configured."
        case .connectionFailed: "Could not connect to server."
        case .keychainError: "Failed to access secure storage."
        case .quotaExceeded: "You've reached your request quota."
        case .duplicateRequest: "This has already been requested."
        case .blacklistedMedia: "This title is not available for request."
        }
    }
}
