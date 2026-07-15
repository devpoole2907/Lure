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
/// Shared tvOS style for poster/card buttons: a plain pass-through that only
/// exists to suppress the default bordered-button white plate around the
/// whole cell (image + caption). The focus visuals come from
/// `posterFocusHighlight()` applied to the ARTWORK inside the label — putting
/// the system highlight on the whole label sheens the caption text and draws
/// a border around the full cell rect.
struct TVPosterFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#endif

extension View {
    /// The system highlight hover effect on tvOS — native focus scale, drop
    /// shadow, specular shimmer, and the parallax tilt that tracks Siri
    /// Remote touch-surface rubbing. No-op on other platforms. Apply to a
    /// card's artwork only, never the caption block; the effect activates
    /// when the enclosing focusable (the Button) gains focus.
    ///
    /// The shape must match the artwork's clip shape: the effect draws its
    /// lift/shine using its own hover shape, which defaults to a plain
    /// rectangle — leaving flat corners around a rounded poster.
    @ViewBuilder
    func posterFocusHighlight(cornerRadius: CGFloat) -> some View {
        posterFocusHighlight(shape: RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func posterFocusHighlight(shape: some Shape) -> some View {
        #if os(tvOS)
        // Both kinds on purpose: tvOS's highlight derives its shape from the
        // plain (.interaction) content shape — the .hoverEffect kind alone
        // leaves the focused rendering square-cornered.
        self
            .contentShape(shape)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
        #else
        self
        #endif
    }
}

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

#if DEBUG && os(iOS)
#Preview("Platform Compatibility — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    NavigationStack {
        VStack(alignment: .leading, spacing: 16) {
            Label("Cross-platform navigation title", systemImage: "rectangle.3.group")
                .font(.headline)

            Text("This panel uses Lure's grouped background color shim.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20))
        .padding()
        .lureNavigationTitle("Platform Compatibility")
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
