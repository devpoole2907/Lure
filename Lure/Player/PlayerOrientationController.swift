import SwiftUI
import UIKit

@MainActor
enum PlayerOrientationController {
    static func lockLandscape() {
        setOrientations(.landscape)
    }

    static func unlock() {
        setOrientations(AppDelegate.defaultOrientationMask)
    }

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
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow)
    }
}
