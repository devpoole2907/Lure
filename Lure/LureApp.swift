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
    @State private var watchTogetherCoordinator: WatchTogetherCoordinator
#if os(macOS)
    @State private var macSettingsPresenter = MacSettingsPresenter()
#endif

    init() {
        let jellyfinService = JellyfinService()
        _jellyfinService = State(wrappedValue: jellyfinService)
        let playerCoordinator = PlayerCoordinator(jellyfinService: jellyfinService)
        _playerCoordinator = State(wrappedValue: playerCoordinator)
        _watchTogetherCoordinator = State(wrappedValue: WatchTogetherCoordinator(playerCoordinator: playerCoordinator))

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
            Group {
                #if DEBUG
                if DebugPlaybackHarnessView.isEnabled {
                    DebugPlaybackHarnessView(
                        jellyfinService: jellyfinService,
                        playerCoordinator: playerCoordinator,
                        watchTogetherCoordinator: watchTogetherCoordinator
                    )
                } else {
                    ContentView(
                        jellyfinService: jellyfinService,
                        playerCoordinator: playerCoordinator,
                        watchTogetherCoordinator: watchTogetherCoordinator
                    )
                }
                #else
                ContentView(
                    jellyfinService: jellyfinService,
                    playerCoordinator: playerCoordinator,
                    watchTogetherCoordinator: watchTogetherCoordinator
                )
                #endif
            }
            .lureMainWindowMinimumSize()
#if os(macOS)
            .environment(macSettingsPresenter)
#endif
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 1320, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    macSettingsPresenter.present()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        WindowGroup("Player", id: PlayerWindowScene.id, for: PlayableMedia.self) { $media in
            if let media {
                PlayerWindowView(media: media)
                    .environment(jellyfinService)
                    .environment(watchTogetherCoordinator)
                    .frame(minWidth: 960, minHeight: 540)
            } else {
                Color.black
            }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentMinSize)
        // Borderless video window like the TV app's player: the traffic lights
        // float over the video instead of sitting in an opaque title bar.
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}

private extension View {
    @ViewBuilder
    func lureMainWindowMinimumSize() -> some View {
        #if os(macOS)
        self.frame(minWidth: 1080, minHeight: 700)
        #else
        self
        #endif
    }
}

#if DEBUG
private struct DebugPlaybackHarnessView: View {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LURE_DEBUG_JELLYFIN_ITEM_ID"]?.isEmpty == false
    }

    let jellyfinService: JellyfinService
    let playerCoordinator: PlayerCoordinator
    // Not wired to a `.task { listenForIncomingSessions() }` in the debug harness
    // (manual local-item-playback tool, not the real login flow) -- injected only so
    // `PlayerView`'s non-optional `@Environment(WatchTogetherCoordinator.self)` lookup
    // doesn't crash when a debug session opens the player.
    let watchTogetherCoordinator: WatchTogetherCoordinator

    @State private var notificationCenter = InAppNotificationCenter()
    @State private var didStart = false
    @State private var status = "Preparing debug playback..."

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                Text(status)
                    .foregroundStyle(.white)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .playerPresentation()
        .environment(notificationCenter)
        .environment(jellyfinService)
        .environment(playerCoordinator)
        .environment(watchTogetherCoordinator)
        .task { await startIfNeeded() }
    }

    @MainActor
    private func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true

        let env = ProcessInfo.processInfo.environment
        guard let server = env["LURE_DEBUG_JELLYFIN_SERVER"], !server.isEmpty,
              let username = env["LURE_DEBUG_JELLYFIN_USERNAME"], !username.isEmpty,
              let password = env["LURE_DEBUG_JELLYFIN_PASSWORD"], !password.isEmpty,
              let itemId = env["LURE_DEBUG_JELLYFIN_ITEM_ID"], !itemId.isEmpty
        else {
            status = "Missing LURE_DEBUG_JELLYFIN_* launch environment."
            return
        }

        let title = env["LURE_DEBUG_JELLYFIN_TITLE"] ?? "Debug Playback"
        let mediaType = env["LURE_DEBUG_JELLYFIN_MEDIA_TYPE"] ?? "movie"

        do {
            status = "Signing into Jellyfin..."
            let credentials = try await JellyfinAPIClient.authenticate(
                serverURL: server,
                username: username,
                password: password
            )
            try await credentials.save()
            await jellyfinService.reload()
            status = "Starting \(title)..."
            playerCoordinator.present(
                itemId: itemId,
                title: title,
                mediaType: mediaType
            )
        } catch {
            status = "Debug playback failed: \(error.localizedDescription)"
        }
    }
}
#endif
