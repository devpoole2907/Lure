import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform shims so the iOS-first view layer compiles unchanged on native
/// macOS (AppKit). Each shim mirrors the iOS modifier's signature and degrades to
/// a sensible no-op or AppKit equivalent. These are only defined on macOS, where
/// the corresponding SwiftUI/UIKit symbols are unavailable, so there is no
/// collision with the real APIs on iOS / visionOS / tvOS.

extension Color {
    /// `secondarySystemGroupedBackground` equivalent that resolves on all platforms.
    static var secondaryGroupedBackground: Color {
        #if os(iOS) || os(visionOS)
        Color(.secondarySystemGroupedBackground)
        #elseif os(tvOS)
        Color.gray.opacity(0.12)
        #elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.gray.opacity(0.12)
        #endif
    }
}

/// Opens a URL in the user's default browser/handler on any platform.
@MainActor
func openExternalURL(_ url: URL) {
    #if canImport(UIKit)
    UIApplication.shared.open(url)
    #elseif canImport(AppKit)
    NSWorkspace.shared.open(url)
    #endif
}

extension View {
    /// `.navigationTitle` that is blanked on tvOS. tvOS `NavigationStack` renders
    /// the title as a huge faded scene title floating over the content (ghost
    /// title), so screens suppress it there and keep normal bar titles elsewhere.
    @ViewBuilder
    func lureNavigationTitle(_ title: String) -> some View {
        #if os(tvOS)
        self.navigationTitle("")
        #else
        self.navigationTitle(title)
        #endif
    }
}

#if os(tvOS)
/// Shared tvOS focus treatment for poster/card buttons: scales the card with a
/// drop shadow when focused, WITHOUT the default bordered-button white plate
/// that would otherwise wrap the whole cell (image + caption).
struct TVPosterFocusButtonStyle: ButtonStyle {
    var scale: CGFloat = 1.08

    func makeBody(configuration: Configuration) -> some View {
        TVPosterFocusBody(configuration: configuration, scale: scale)
    }

    private struct TVPosterFocusBody: View {
        let configuration: ButtonStyle.Configuration
        let scale: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .scaleEffect(isFocused ? scale : 1.0)
                .shadow(color: isFocused ? .black.opacity(0.45) : .clear, radius: 18, y: 8)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isFocused)
        }
    }
}
#endif

#if os(macOS) || os(tvOS)

// MARK: - navigationBarTitleDisplayMode

enum NavigationBarItem {
    enum TitleDisplayMode {
        case automatic, inline, large
    }
}

extension View {
    /// No-op on macOS/tvOS; large/inline title styling is not applicable.
    func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }
}

#endif

#if os(macOS)

// MARK: - keyboardType

enum UIKeyboardType {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad
    case phonePad, namePhonePad, emailAddress, decimalPad, twitter
    case webSearch, asciiCapableNumberPad
}

extension View {
    /// macOS has no on-screen keyboard; the hint is irrelevant.
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
}

// MARK: - textInputAutocapitalization

enum TextInputAutocapitalization {
    case never, words, sentences, characters
}

extension View {
    func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View {
        self
    }
}

// MARK: - fullScreenCover → sheet

extension View {
    /// macOS has no full-screen cover; present as a sheet instead.
    func fullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss, content: content)
    }

    func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }
}

#endif
