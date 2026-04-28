import SwiftUI
import SwiftData
import UserNotifications

#if os(iOS) || os(visionOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        NotificationCenter.default.post(name: NSNotification.Name("didReceiveDeviceToken"), object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
}
#endif

@main
struct LureApp: App {
#if os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            LureServerProfile.self
        ])
        let config = ModelConfiguration()
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("Failed to create ModelContainer: \(error.localizedDescription). Falling back to in-memory store.")
            let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [inMemoryConfig])
            } catch {
                fatalError("Could not create in-memory ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
