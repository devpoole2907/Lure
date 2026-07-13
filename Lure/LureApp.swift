import SwiftUI
import SwiftData
import UserNotifications

#if os(iOS) || os(visionOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    /// The app's resting orientation: portrait-only on iPhone, free on iPad.
    static let defaultOrientationMask: UIInterfaceOrientationMask =
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait

    /// Drives which interface orientations UIKit permits. The player locks this to
    /// landscape while it's on screen (see `PlayerOrientationController`); the rest
    /// of the app runs in `defaultOrientationMask`.
    static var orientationLock: UIInterfaceOrientationMask = AppDelegate.defaultOrientationMask

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

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
    @State private var jellyfinService: JellyfinService
    @State private var playerCoordinator: PlayerCoordinator

    init() {
        let jellyfinService = JellyfinService()
        _jellyfinService = State(wrappedValue: jellyfinService)
        _playerCoordinator = State(wrappedValue: PlayerCoordinator(jellyfinService: jellyfinService))

        let schema = Schema([
            LureServerProfile.self,
            CachedLibraryItem.self,
            CachedRequestItem.self
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
            ContentView(
                jellyfinService: jellyfinService,
                playerCoordinator: playerCoordinator
            )
        }
        .modelContainer(modelContainer)

        #if os(macOS)
        WindowGroup("Player", id: PlayerWindowScene.id, for: PlayableMedia.self) { $media in
            if let media {
                PlayerWindowView(media: media)
                    .environment(jellyfinService)
                    .frame(minWidth: 960, minHeight: 540)
            } else {
                Color.black
            }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentMinSize)
        #endif
    }
}
