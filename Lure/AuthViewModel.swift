import Foundation
import Observation
import SwiftData

@Observable
final class AuthViewModel {
    var username: String = ""
    var password: String = ""
    var isAuthenticating: Bool = false
    var error: String?
    var currentUser: SeerrUser?
    var isLoggedIn: Bool = false
    var publicSettings: SeerrPublicSettings?

    private(set) var apiClient: SeerrAPIClient?

    // MARK: - Server Validation (deep link or manual entry)

    var serverURL: String = ""

    func validateServer() async -> Bool {
        let url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            error = "Server URL is required."
            return false
        }
        let client = SeerrAPIClient(baseURL: url)
        do {
            publicSettings = try await client.getPublicSettings()
            guard publicSettings?.initialized == true else {
                error = "This Seerr instance has not been set up yet."
                return false
            }
            apiClient = client
            error = nil
            return true
        } catch {
            self.error = "Could not connect to Seerr at that URL."
            return false
        }
    }

    // MARK: - Login

    func login(modelContext: ModelContext) async -> Bool {
        guard let client = apiClient else {
            error = "No server configured."
            return false
        }

        guard !username.isEmpty, !password.isEmpty else {
            error = "Username and password are required."
            return false
        }

        isAuthenticating = true
        error = nil

        do {
            let user = try await client.loginJellyfin(username: username, password: password)
            currentUser = user
            isLoggedIn = true

            // Remove any existing profiles for this server URL to avoid duplicates
            let allProfiles = (try? modelContext.fetch(FetchDescriptor<LureServerProfile>())) ?? []
            let normalizedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let stale = allProfiles.filter {
                $0.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedURL
            }
            
            let existingWorkerURL = stale.compactMap(\.apnsWorkerURL).first
            
            for existing in stale {
                try? await LureKeychain.shared.delete(key: existing.sessionCookieKey)
                modelContext.delete(existing)
            }

            let profile = LureServerProfile(
                displayName: publicSettings?.applicationTitle ?? serverURL,
                serverURL: serverURL
            )
            profile.apnsWorkerURL = existingWorkerURL
            modelContext.insert(profile)

            if let cookie = await client.getSessionCookie() {
                try await LureKeychain.shared.save(key: profile.sessionCookieKey, value: cookie)
            }

            try modelContext.save()
            
            if let workerURL = profile.apnsWorkerURL {
                NotificationManager.shared.register(workerURL: workerURL, serverURL: profile.serverURL, username: user.displayName)
            }

            isAuthenticating = false
            return true
        } catch let error as LureError {
            self.error = error.errorDescription
            isAuthenticating = false
            return false
        } catch {
            self.error = error.localizedDescription
            isAuthenticating = false
            return false
        }
    }

    // MARK: - Session Restore

    func restoreSession(from profile: LureServerProfile) async -> Bool {
        guard let cookie = await LureKeychain.shared.read(key: profile.sessionCookieKey) else {
            return false
        }

        let client = SeerrAPIClient(baseURL: profile.baseURL, sessionCookie: cookie)

        do {
            let user = try await client.getCurrentUser()
            apiClient = client
            currentUser = user
            serverURL = profile.baseURL
            isLoggedIn = true
            publicSettings = try? await client.getPublicSettings()
            
            if let workerURL = profile.apnsWorkerURL {
                NotificationManager.shared.register(workerURL: workerURL, serverURL: profile.serverURL, username: user.displayName)
            }
            
            return true
        } catch {
            // Cookie expired
            return false
        }
    }

    // MARK: - Logout

    func logout(profile: LureServerProfile?, modelContext: ModelContext) async {
        try? await apiClient?.logout()
        if let profile {
            if let workerURL = profile.apnsWorkerURL, let token = UserDefaults.standard.string(forKey: "LureDeviceToken") {
                await NotificationManager.shared.unregister(workerURL: workerURL, serverURL: profile.serverURL, deviceToken: token)
            }
            try? await LureKeychain.shared.delete(key: profile.sessionCookieKey)
            profile.isActive = false
            try? modelContext.save()
        }
        apiClient = nil
        currentUser = nil
        isLoggedIn = false
        username = ""
        password = ""
    }
}