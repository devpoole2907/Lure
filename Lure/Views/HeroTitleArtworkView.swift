import SwiftUI

struct HeroTitleArtworkView: View {
    let title: String
    let logoURL: URL?
    var font: Font = .largeTitle.weight(.black)
    var maxWidth: CGFloat = 430
    var maxLogoHeight: CGFloat = 150
    var horizontalAlignment: HorizontalAlignment = .center
    var reportTitleBottom: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if logoURL != nil {
                logoReadabilityScrim
            }

            titleContent
        }
        .frame(maxWidth: maxWidth, minHeight: maxLogoHeight, maxHeight: maxLogoHeight, alignment: frameAlignment)
        .background(titleBottomReporter)
    }

    @ViewBuilder
    private var titleContent: some View {
        Group {
            if let logoURL {
                CachedRemoteImage(url: logoURL, contentMode: .fit, trimsTransparentPadding: true) {
                    fallbackTitle
                }
                .frame(maxWidth: maxWidth * 0.94, maxHeight: maxLogoHeight * 0.9, alignment: frameAlignment)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
                .accessibilityLabel(title)
            } else {
                fallbackTitle
                    .frame(maxWidth: maxWidth * 0.94, alignment: frameAlignment)
            }
        }
    }

    private var fallbackTitle: some View {
        Text(title)
            .font(font)
            .foregroundStyle(.white)
            .multilineTextAlignment(textAlignment)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    private var frameAlignment: Alignment {
        horizontalAlignment == .leading ? .bottomLeading : .bottom
    }

    private var textAlignment: TextAlignment {
        horizontalAlignment == .leading ? .leading : .center
    }

    private var logoReadabilityScrim: some View {
        Rectangle()
            .fill(.linearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.34), location: 0.24),
                    .init(color: .black.opacity(0.34), location: 0.76),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.28),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxWidth: maxWidth, minHeight: maxLogoHeight * 0.78, maxHeight: maxLogoHeight * 0.78)
            .blur(radius: 14)
            .allowsHitTesting(false)
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
