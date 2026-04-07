import SwiftUI
import AppKit

// MARK: - Typography

enum PhrasedFont {
    static let body = Font.title3
    static let bodyMedium = Font.title3.weight(.medium)
    static let ui = Font.body
    static let uiMedium = Font.body.weight(.medium)
    static let secondary = Font.callout
    static let secondaryMedium = Font.callout.weight(.medium)
    static let secondarySemibold = Font.callout.weight(.semibold)
    static let caption = Font.caption
    static let captionMedium = Font.caption.weight(.medium)

    // NSFont equivalents for NSViewRepresentable (requires macOS 13+)
    static let nsBody: NSFont = .preferredFont(forTextStyle: .title3)
    static let nsUI: NSFont = .preferredFont(forTextStyle: .body, options: [:])
}

// MARK: - Spacing

enum PhrasedSpacing {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 24
    static let xxl:  CGFloat = 40
}

// MARK: - Corner Radius

enum PhrasedRadius {
    static let sm:      CGFloat = 6      // buttons, tags, badges
    static let md:      CGFloat = 10     // cards, panels
    static let lg:      CGFloat = 16     // main capsule window
}

// MARK: - Opacity

enum PhrasedOpacity {
    static let subtleFill:  Double = 0.05   // faint backgrounds
    static let lightFill:   Double = 0.08   // hover / card backgrounds
    static let border:      Double = 0.12   // strokes, dividers
    static let dimmed:      Double = 0.4    // disabled, tertiary text
    static let muted:       Double = 0.6    // secondary icons
}

// MARK: - Animation

enum PhrasedAnimation {
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let quick  = Animation.easeInOut(duration: 0.15)
}
