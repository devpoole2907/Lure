import SwiftUI
import CryptoKit

enum APNSConfig {
    static let appSecret = "YOUR_APP_SECRET_HERE" // The user will replace this
}

@Observable
final class NotificationManager {
    static let shared = NotificationManager()
    
    var isRegistered: Bool = false
    
    private init() {
        // Listen for the device token from AppDelegate
        NotificationCenter.default.addObserver(forName: NSNotification.Name("didReceiveDeviceToken"), object: nil, queue: .main) { [weak self] notification in
            if let token = notification.object as? String {
                Task {
                    await self?.handleTokenReceived(token)
                }
            }
        }
    }
    
    private var currentWorkerURL: String?
    private var currentServerURL: String?
    private var currentUsername: String?
    
    func register(workerURL: String, serverURL: String, username: String) {
        self.currentWorkerURL = workerURL
        self.currentServerURL = serverURL
        self.currentUsername = username
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("Notification permission denied: \(String(describing: error))")
            }
        }
    }
    
    func unregister(workerURL: String, serverURL: String, deviceToken: String) async {
        guard let url = URL(string: workerURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        
        let unregisterURL = url.appendingPathComponent("unregister")
        let serverId = NotificationManager.hashServerURL(serverURL)
        
        let payload: [String: Any] = [
            "serverId": serverId,
            "deviceToken": deviceToken
        ]
        
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        
        var request = URLRequest(url: unregisterURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(APNSConfig.appSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = payloadData
        
        do {
            _ = try await URLSession.shared.data(for: request)
            await MainActor.run {
                self.isRegistered = false
            }
        } catch {
            print("Error unregistering device token: \(error)")
        }
    }
    
    private func handleTokenReceived(_ token: String) async {
        guard let workerURLString = currentWorkerURL,
              let serverURL = currentServerURL,
              let username = currentUsername,
              let workerURL = URL(string: workerURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        
        let registerURL = workerURL.appendingPathComponent("register")
        let serverId = NotificationManager.hashServerURL(serverURL)
        
        let payload: [String: Any] = [
            "serverId": serverId,
            "deviceToken": token,
            "username": username,
            "isSandbox": false // Set to true if testing in sandbox
        ]
        
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        
        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(APNSConfig.appSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = payloadData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await MainActor.run {
                    self.isRegistered = true
                }
                print("Successfully registered for push notifications")
                // Save the token locally to allow unregistering later
                UserDefaults.standard.set(token, forKey: "LureDeviceToken")
            } else {
                print("Failed to register with worker. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0), Response: \(String(data: data, encoding: .utf8) ?? "")")
            }
        } catch {
            print("Error registering device token: \(error)")
        }
    }
    
    static func hashServerURL(_ urlString: String) -> String {
        let normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let data = Data(normalized.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
