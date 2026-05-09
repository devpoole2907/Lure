import SwiftUI
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
