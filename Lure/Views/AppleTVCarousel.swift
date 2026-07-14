import SwiftUI

struct AppleTVCarousel<Content: View>: View {
    var movement: CGFloat = 60
    /// When true the subviews are NOT inset by safe area padding — used for
    /// full-bleed hero artwork on tvOS where the image must reach the screen edges.
    var fullBleed: Bool = false
    @Binding var scrollPositionID: String?
    @ViewBuilder var content: Content
    var scrollProgress: (CGFloat) -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    Group(subviews: content) { collection in
                        ForEach(collection) { subview in
                            let index = collection.firstIndex(where: { $0.id == subview.id }) ?? 0
                            let isLast = index == collection.count - 1
                            let opacity = isLast ? 0 : max(min(progress - CGFloat(index), 1), 0)

                            Group {
                                if fullBleed {
                                    subview
                                        .frame(width: size.width, height: size.height)
                                        .clipped()
                                } else {
                                    subview
                                        .frame(width: size.width, height: size.height)
                                        .clipped()
                                        .safeAreaPadding(.horizontal, movement + 10)
                                        .mask {
                                            Rectangle()
                                                .ignoresSafeArea()
                                        }
                                }
                            }
                            .frame(width: size.width, height: size.height)
                            .compositingGroup()
                            .opacity(1 - opacity)
                            .visualEffect { [movement] content, proxy in
                                let minX = proxy.frame(in: .scrollView(axis: .horizontal)).minX
                                let movementProgress = max(min(minX / size.width, 1), -1)

                                return content
                                    .offset(x: -minX)
                                    .offset(x: movement * movementProgress)
                            }
                            .zIndex(Double(-index))
                        }
                    }
                }
                .scrollTargetLayout()
            }
            #if os(tvOS)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            #else
            .scrollTargetBehavior(.paging)
            #endif
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollPosition(id: $scrollPositionID)
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.x + $0.contentInsets.leading
            } action: { _, newValue in
                progress = max(newValue / max(size.width, 1), 0)
                scrollProgress(progress)
            }
        }
    }
}
