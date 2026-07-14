import SwiftUI
#if canImport(UIKit)
import UIKit

struct PageControlView: UIViewRepresentable {
    let numberOfPages: Int
    let currentPage: Int

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.allowsContinuousInteraction = false
        control.currentPageIndicatorTintColor = .white
        control.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.32)
        control.backgroundStyle = .minimal
        control.isUserInteractionEnabled = false
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        control.numberOfPages = numberOfPages
        control.currentPage = min(max(currentPage, 0), max(numberOfPages - 1, 0))
        control.isHidden = numberOfPages <= 1
    }
}
#else
/// AppKit has no `UIPageControl`; render an equivalent row of dots in SwiftUI.
struct PageControlView: View {
    let numberOfPages: Int
    let currentPage: Int

    var body: some View {
        if numberOfPages > 1 {
            HStack(spacing: 7) {
                ForEach(0..<numberOfPages, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(index == currentPage ? 1 : 0.32))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }
}
#endif

#if DEBUG && os(iOS)
#Preview("Page Control — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    ZStack {
        Color.black.ignoresSafeArea()
        PageControlView(numberOfPages: 6, currentPage: 2)
    }
}
#endif
