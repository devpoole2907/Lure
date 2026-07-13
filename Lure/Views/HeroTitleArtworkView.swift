import SwiftUI

struct HeroTitleArtworkView: View {
    let title: String
    let logoURL: URL?
    var font: Font = .largeTitle.weight(.black)
    var maxWidth: CGFloat = 430
    var maxLogoHeight: CGFloat = 150
    var reportTitleBottom: Bool = false

    var body: some View {
        Group {
            if let logoURL {
                CachedRemoteImage(url: logoURL, contentMode: .fit) {
                    fallbackTitle
                }
                .frame(maxWidth: maxWidth, maxHeight: maxLogoHeight)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
                .accessibilityLabel(title)
            } else {
                fallbackTitle
            }
        }
        .background(titleBottomReporter)
    }

    private var fallbackTitle: some View {
        Text(title)
            .font(font)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    @ViewBuilder
    private var titleBottomReporter: some View {
        if reportTitleBottom {
            GeometryReader { geo in
                Color.clear.preference(
                    key: HeroTitleBottomKey.self,
                    value: geo.frame(in: .global).maxY
                )
            }
        }
    }
}
