import AppKit

/// Shared visual language for Hearsay's chrome — a quiet, monochrome,
/// card-and-hover aesthetic (matching the Managerie UX revamp).
///
/// Rules of thumb:
/// - Monochrome by default; accent color only for the *active* selection.
/// - Backgrounds are `Color.primary.opacity(...)` style washes, not solid fills.
/// - Continuous rounded corners, generous vertical padding, tertiary metadata.
enum Theme {

    // MARK: - Corner radii

    enum Radius {
        static let card: CGFloat = 8
        static let row: CGFloat = 7
        static let control: CGFloat = 6
        static let pill: CGFloat = 999
    }

    // MARK: - Spacing

    enum Space {
        static let rowH: CGFloat = 9
        static let rowV: CGFloat = 6
        static let cardH: CGFloat = 11
        static let cardV: CGFloat = 9
        static let sectionGap: CGFloat = 16
    }

    // MARK: - Type scale

    enum Font {
        static let sidebarItem = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let sidebarItemActive = NSFont.systemFont(ofSize: 13, weight: .medium)
        static let identity = NSFont.systemFont(ofSize: 16, weight: .semibold)
        static let cardTitle = NSFont.systemFont(ofSize: 13, weight: .regular)
        static let meta = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let metaDigits = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        static let sectionHeader = NSFont.systemFont(ofSize: 11, weight: .semibold)
        static let badge = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
    }

    // MARK: - Monochrome washes

    /// `Color.primary.opacity(alpha)` equivalent — adapts to light/dark.
    static func wash(_ alpha: CGFloat) -> NSColor {
        NSColor.labelColor.withAlphaComponent(alpha)
    }

    enum Wash {
        static let cardIdle: CGFloat = 0.035
        static let cardHover: CGFloat = 0.08
        static let rowHover: CGFloat = 0.06
        static let control: CGFloat = 0.07
        static let hairline: CGFloat = 0.08
    }

    /// Accent tint used for the active sidebar row. Slightly stronger in dark mode.
    static func activeTint(for view: NSView) -> NSColor {
        let dark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.controlAccentColor.withAlphaComponent(dark ? 0.18 : 0.12)
    }

    // MARK: - Motion

    enum Motion {
        /// Hover backgrounds — instant-feeling.
        static let hover: TimeInterval = 0.15
        /// Quick feedback: presses, toggles.
        static let snappy: TimeInterval = 0.12
        /// Primary transitions: pane switches.
        static let smooth: TimeInterval = 0.22
    }

    // MARK: - Helpers

    /// A rounded card background that follows the system appearance.
    static func makeCard(radius: CGFloat = Radius.card, alpha: CGFloat = Wash.cardIdle) -> NSView {
        AdaptiveBackgroundView(color: wash(alpha), cornerRadius: radius)
    }

    /// A 1px hairline divider that follows the system appearance.
    static func makeHairline(vertical: Bool = false) -> NSView {
        let line = AdaptiveBackgroundView(color: wash(Wash.hairline))
        line.translatesAutoresizingMaskIntoConstraints = false
        if vertical {
            line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        } else {
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        }
        return line
    }

    /// Left-aligned pane heading + subhead, matching the Settings pane.
    static func styleHeading(_ title: NSTextField, _ subtitle: NSTextField) {
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.alignment = .left
        title.textColor = .labelColor

        subtitle.font = .systemFont(ofSize: 12)
        subtitle.alignment = .left
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2
    }

    /// Relative, short-form timestamp ("2m", "3h", "yest") for metadata slots.
    static func relativeShort(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "1d" : "\(days)d"
    }
}
