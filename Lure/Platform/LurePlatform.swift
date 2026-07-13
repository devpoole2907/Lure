import Foundation

enum LurePlatform {
    static var isTV: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static var isVision: Bool {
        #if os(visionOS)
        true
        #else
        false
        #endif
    }

    static var usesFocusNavigation: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    static var supportsOrientationLock: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    static var supportsDedicatedPlayerWindow: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}
