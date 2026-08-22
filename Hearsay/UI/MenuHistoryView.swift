import AppKit

/// A single recent-transcription row rendered *inside* the menubar dropdown.
///
/// AppKit menus can host arbitrary views via `NSMenuItem.view`, but they then
/// stop drawing the highlight and stop routing clicks — so this view does both
/// itself: a rounded monochrome hover wash (Managerie-style) and a click that
/// fires the item's action before dismissing the menu.
final class MenuHistoryRowView: NSView {

    private let item: TranscriptionItem
    private let onSelect: (TranscriptionItem) -> Void

    private let background = AdaptiveBackgroundView(color: .clear, cornerRadius: Theme.Radius.control)
    private let textLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let glyph = NSImageView()

    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false {
        didSet { updateHighlight() }
    }

    /// Menus lay their content views out at the menu's width; this is the
    /// intrinsic height of one row.
    static let rowHeight: CGFloat = 38

    init(item: TranscriptionItem, onSelect: @escaping (TranscriptionItem) -> Void) {
        self.item = item
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: Self.rowHeight))
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let symbolName = item.isFailed ? "exclamationmark.triangle" : "text.quote"
        glyph.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        glyph.contentTintColor = .tertiaryLabelColor
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        textLabel.stringValue = Self.preview(for: item)
        textLabel.font = Theme.Font.cardTitle
        textLabel.textColor = item.isFailed ? .secondaryLabelColor : .labelColor
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(textLabel)

        timeLabel.stringValue = Theme.relativeShort(item.timestamp)
        timeLabel.font = Theme.Font.metaDigits
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(timeLabel)

        toolTip = "\(item.formattedTime)\n\n\(item.text)"

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.rowHeight),

            // Inset the wash so it reads as a rounded row, not a full-bleed band.
            background.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            background.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            background.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            background.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            // Lands the label on the standard ~30pt menu text inset.
            glyph.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 5),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 14),

            textLabel.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 7),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textLabel.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private static func preview(for item: TranscriptionItem) -> String {
        if item.isFailed { return "Transcription failed" }
        let collapsed = item.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 44 else { return collapsed }
        return String(collapsed.prefix(44)) + "…"
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    private func updateHighlight() {
        background.backgroundColor = isHovering ? Theme.wash(Theme.Wash.cardHover) : .clear
    }

    // MARK: - Click

    override func mouseUp(with event: NSEvent) {
        onSelect(item)
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

/// Section header for a group of custom rows in the menubar dropdown
/// ("RECENT", with a trailing count), styled to read like a menu section title.
final class MenuSectionHeaderView: NSView {

    init(title: String, trailing: String? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title.uppercased())
        label.font = Theme.Font.sectionHeader
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        if let trailing {
            let count = NSTextField(labelWithString: trailing)
            count.font = Theme.Font.metaDigits
            count.textColor = .tertiaryLabelColor
            count.translatesAutoresizingMaskIntoConstraints = false
            addSubview(count)
            NSLayoutConstraint.activate([
                count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                count.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Empty-state row shown when there are no transcriptions yet.
final class MenuEmptyStateView: NSView {

    init(message: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 34))
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: message)
        label.font = Theme.Font.cardTitle
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 31),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
