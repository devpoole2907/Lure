import SwiftUI

enum LureDesign {

    enum CornerRadius {
        static let card: CGFloat = 16
        static let smallCard: CGFloat = 12
        static let button: CGFloat = 14
        static let poster: CGFloat = 10
        static let smallPoster: CGFloat = 8
        static let listPoster: CGFloat = 6
        static let tinyPoster: CGFloat = 4
    }

    enum Opacity {
        static let badgeBackground: Double = 0.12
        static let iconBackground: Double = 0.15
        static let gradientStart: Double = 0.18
        static let gradientRadial: Double = 0.14
        static let notificationTint: Double = 0.18
    }

    enum Spacing {
        static let card: CGFloat = 16
        static let section: CGFloat = 24
        static let row: CGFloat = 12
        static let tight: CGFloat = 8
        static let badge: CGFloat = 4
    }

    enum IconSize {
        static let rowIcon: CGFloat = 44
        static let rowIconFont: CGFloat = 19
        static let profileIcon: CGFloat = 50
        static let profileIconFont: CGFloat = 20
        static let statusDot: CGFloat = 8
    }
}