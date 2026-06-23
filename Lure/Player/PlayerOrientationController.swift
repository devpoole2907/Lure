import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Drives interface-orientation locking while the player is on screen.
/// Orientation locking only applies on iPhone/iPad; it is a no-op on macOS
/// and visionOS, where the system manages window geometry.
@MainActor
enum PlayerOrientationController {
    static func lockLandscape() {
        #if os(iOS)
        setOrientations(.landscape)
        #endif
    }

    static func unlock() {
        #if os(iOS)
        setOrientations(AppDelegate.defaultOrientationMask)
        #endif
    }

    #if os(iOS)
    private static func setOrientations(_ orientations: UIInterfaceOrientationMask) {
        // Gate UIKit's permitted orientations first, otherwise the geometry update
        // below is immediately reverted by `supportedInterfaceOrientationsFor`.
        AppDelegate.orientationLock = orientations
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { scene in
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                    #if DEBUG
                    print("[PlayerOrientationController] geometry update failed: \(error.localizedDescription)")
                    #endif
                }
                scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
    }
    #endif
}

#if os(iOS)
private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow)
    }
}
#endif
