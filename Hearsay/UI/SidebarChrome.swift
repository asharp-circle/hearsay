import AppKit

// MARK: - Adaptive background

/// A layer-backed view whose background follows the system appearance.
///
/// `NSColor.cgColor` resolves a *dynamic* colour against whatever appearance is
/// current at that instant, producing a fixed colour. Assigning it once (the
/// usual `layer?.backgroundColor = someColor.cgColor`) means the view keeps its
/// launch-time colour forever — so flipping to Dark Mode at runtime left light
/// panels with light-on-light (invisible) text. Redrawing through
/// `updateLayer()` re-resolves the colour every time the appearance changes.
final class AdaptiveBackgroundView: NSView {

    var backgroundColor: NSColor {
        didSet { needsDisplay = true }
    }

    var cornerRadius: CGFloat {
        didSet { needsDisplay = true }
    }

    init(color: NSColor, cornerRadius: CGFloat = 0) {
        self.backgroundColor = color
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        // Resolve the dynamic colour against *this view's* appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = backgroundColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Flipped container

/// A top-down view. AppKit's default origin is bottom-left, so an unflipped
/// document view inside an `NSScrollView` stacks its content from the bottom and
/// starts scrolled to the bottom. Use this for list document views.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Row list (scroll view document)

/// Document view for the rule/replacement lists.
///
/// It lays out its own rows from its *own* bounds and reports an
/// `intrinsicContentSize`, so nothing has to read `scrollView.contentSize`
/// during a layout pass (which is zero before the scroller has been sized, and
/// was leaving the rows invisible).
final class RowListView: FlippedView {

    var rowHeight: CGFloat = 38
    var rowGap: CGFloat = 6

    private(set) var rows: [NSView] = []

    func setRows(_ views: [NSView]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = views
        views.forEach { addSubview($0) }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    var contentHeight: CGFloat {
        guard !rows.isEmpty else { return 0 }
        return CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * rowGap
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
    }

    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: 0,
                y: CGFloat(index) * (rowHeight + rowGap),
                width: bounds.width,
                height: rowHeight
            )
        }
    }
}

// MARK: - Card section

/// A titled content card: an optional all-caps section label above a rounded
/// monochrome panel holding a vertical stack of rows.
///
/// This replaces `NSBox` in the revamped panes. `NSBox` positions its
/// `contentView` during its own layout pass, so the common
/// `box.frame = …; box.contentView!.bounds` pattern reads a *stale* size and
/// scatters children outside the drawn box. Auto Layout removes the whole
/// class of bug.
final class CardSectionView: NSView {

    private let panel = AdaptiveBackgroundView(
        color: Theme.wash(Theme.Wash.cardIdle),
        cornerRadius: Theme.Radius.card
    )
    let stack = NSStackView()

    init(title: String?, spacing: CGFloat = 10) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        var topAnchorForPanel = topAnchor
        var topConstant: CGFloat = 0

        if let title {
            let header = NSTextField(labelWithString: title.uppercased())
            header.font = Theme.Font.sectionHeader
            header.textColor = .tertiaryLabelColor
            header.translatesAutoresizingMaskIntoConstraints = false
            addSubview(header)
            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: topAnchor),
                header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            ])
            topAnchorForPanel = header.bottomAnchor
            topConstant = 7
        }

        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)

        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: topAnchorForPanel, constant: topConstant),
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Adds a row and stretches it to the card's width.
    func addRow(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

}

// MARK: - Sidebar material

/// A real translucent macOS sidebar surface (`.sidebar` material, blended with
/// whatever is behind the window).
final class SidebarMaterialView: NSVisualEffectView {
    init() {
        super.init(frame: .zero)
        material = .sidebar
        blendingMode = .behindWindow
        state = .followsWindowActiveState
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Sidebar row

/// One navigation row: icon + label, optional trailing badge.
///
/// Quiet by default, a soft monochrome wash on hover, and an accent-tinted
/// rounded rect when active — the same behaviour as Managerie's sidebar.
final class SidebarItemView: NSView {

    let identifier_: String
    private let onSelect: (String) -> Void

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let badgeBackground = AdaptiveBackgroundView(
        color: Theme.wash(Theme.Wash.cardHover),
        cornerRadius: 8
    )

    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false { didSet { updateAppearance() } }
    var isActive = false { didSet { updateAppearance() } }

    var badge: String? {
        didSet {
            let text = badge ?? ""
            badgeLabel.stringValue = text
            badgeBackground.isHidden = text.isEmpty
            badgeLabel.isHidden = text.isEmpty
        }
    }

    init(id: String, title: String, symbol: String, onSelect: @escaping (String) -> Void) {
        self.identifier_ = id
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = Theme.Radius.row
        layer?.cornerCurve = .continuous

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.stringValue = title
        label.font = Theme.Font.sidebarItem
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        badgeBackground.translatesAutoresizingMaskIntoConstraints = false
        badgeBackground.isHidden = true
        addSubview(badgeBackground)

        badgeLabel.font = Theme.Font.badge
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.isHidden = true
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Space.rowH),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            badgeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Space.rowH),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            badgeBackground.leadingAnchor.constraint(equalTo: badgeLabel.leadingAnchor, constant: -6),
            badgeBackground.trailingAnchor.constraint(equalTo: badgeLabel.trailingAnchor, constant: 6),
            badgeBackground.centerYAnchor.constraint(equalTo: badgeLabel.centerYAnchor),
            badgeBackground.heightAnchor.constraint(equalToConstant: 16),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Appearance

    private func updateAppearance() {
        let background: NSColor
        if isActive {
            background = Theme.activeTint(for: self)
        } else if isHovering {
            background = Theme.wash(Theme.Wash.rowHover)
        } else {
            background = .clear
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Motion.hover
            // Resolve against this view's appearance, not whatever is current.
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = background.cgColor
            }
        }

        iconView.contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
        label.font = isActive ? Theme.Font.sidebarItemActive : Theme.Font.sidebarItem
        label.textColor = (isActive || isHovering) ? .labelColor : .secondaryLabelColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    // MARK: Interaction

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        // Press feedback, then commit on mouse-up inside.
        alphaValue = 0.75
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = 1.0
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onSelect(identifier_)
    }
}

// MARK: - Sidebar section label

/// A small all-caps grouping label ("GENERAL", "TEXT", …).
final class SidebarSectionLabel: NSView {

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title.uppercased())
        label.font = Theme.Font.sectionHeader
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Space.rowH + 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Sidebar footer

/// Status dot + label on the left, version on the right — quiet, tertiary.
final class SidebarFooterView: NSView {

    private let dot = AdaptiveBackgroundView(color: Theme.wash(0.45), cornerRadius: 3)
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let versionLabel = NSTextField(labelWithString: "")

    init(version: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        statusLabel.font = Theme.Font.meta
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        versionLabel.stringValue = version
        versionLabel.font = Theme.Font.metaDigits
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(versionLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),

            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Space.rowH + 1),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            statusLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            versionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statusLabel.trailingAnchor, constant: 6),
            versionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Space.rowH),
            versionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `enabled` drives the dot's presence; `text` is the short status line.
    func update(text: String, enabled: Bool) {
        statusLabel.stringValue = text
        dot.backgroundColor = Theme.wash(enabled ? 0.45 : 0.15)
    }
}

// MARK: - Sidebar identity header

/// App glyph + wordmark, sitting below the traffic lights.
final class SidebarIdentityView: NSView {

    init(title: String, image: NSImage?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = image
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let label = NSTextField(labelWithString: title)
        label.font = Theme.Font.identity
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Space.rowH + 1),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
