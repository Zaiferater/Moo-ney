import AppKit

final class ThemedButton: NSControl {
    var titleText: String {
        didSet { needsDisplay = true }
    }
    var fillColor: NSColor {
        didSet { needsDisplay = true }
    }
    var borderColor: NSColor {
        didSet { needsDisplay = true }
    }
    var textColor: NSColor {
        didSet { needsDisplay = true }
    }
    var titleFont: NSFont {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat = 5 {
        didSet { needsDisplay = true }
    }
    var borderWidth: CGFloat = 1 {
        didSet { needsDisplay = true }
    }
    var isSelectedState: Bool = false {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?

    private var isHovered = false
    private var isPressed = false
    private var trackingAreaRef: NSTrackingArea?

    init(
        title: String,
        fillColor: NSColor,
        borderColor: NSColor,
        textColor: NSColor,
        font: NSFont = NSFont.systemFont(ofSize: 13),
        frame: NSRect = .zero
    ) {
        self.titleText = title
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.textColor = textColor
        self.titleFont = font
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressed = isPressed
        isPressed = false
        needsDisplay = true
        if wasPressed && inside {
            onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let alpha: CGFloat
        if !isEnabled {
            alpha = 0.42
        } else if isPressed {
            alpha = 0.72
        } else if isHovered {
            alpha = 0.84
        } else {
            alpha = 1.0
        }

        ctx.saveGState()
        ctx.setAlpha(alpha)

        let inset = borderWidth / 2.0
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(fillColor.cgColor)
        ctx.fillPath()

        if borderWidth > 0 {
            ctx.addPath(path)
            ctx.setStrokeColor(borderColor.cgColor)
            ctx.setLineWidth(borderWidth)
            ctx.strokePath()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: textColor
        ]
        let nsTitle = titleText as NSString
        let size = nsTitle.size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2.0,
            y: (bounds.height - size.height) / 2.0
        )
        nsTitle.draw(at: point, withAttributes: attrs)
        ctx.restoreGState()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class WorkdayCalendarWindow: NSWindow {
    private static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    private var overrides: Set<CalendarDay>
    private let theme: AppTheme
    private var month: CalendarDay
    private var onComplete: (([CalendarDay]?) -> Void)?

    private let monthLabel = NSTextField(labelWithString: "")
    private let selectedCountLabel = NSTextField(labelWithString: "")
    private let daysContainer = FlippedView()
    private var previousButton: ThemedButton!
    private var nextButton: ThemedButton!
    private var dayButtons: [(CalendarDay, ThemedButton)] = []

    init(overrides: [CalendarDay], theme: AppTheme, today: CalendarDay, onComplete: @escaping ([CalendarDay]?) -> Void) {
        self.overrides = Set(overrides)
        self.theme = theme
        self.month = CalendarDay(year: today.year, month: today.month, day: 1)
        self.onComplete = onComplete

        let width: CGFloat = 384
        let height: CGFloat = 414
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "自定义工作日"
        isReleasedWhenClosed = false
        backgroundColor = theme.settingsBackground
        appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)

        buildUI(width: width, height: height)
        showMonth()
    }

    override func cancelOperation(_ sender: Any?) {
        finish(confirmed: false)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            finish(confirmed: true)
            return
        }
        if event.keyCode == 53 { // Escape
            finish(confirmed: false)
            return
        }
        super.keyDown(with: event)
    }

    private func buildUI(width: CGFloat, height: CGFloat) {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.backgroundColor = theme.settingsBackground.cgColor
        contentView = root

        let margin: CGFloat = 20
        let contentWidth = width - margin * 2
        var y: CGFloat = 20

        let hint = NSTextField(wrappingLabelWithString: "点击日期切换，选中的日期计薪。")
        hint.font = NSFont.systemFont(ofSize: 13)
        hint.textColor = theme.text
        hint.frame = NSRect(x: margin, y: y, width: contentWidth, height: 20)
        root.addSubview(hint)
        y += 30

        // Month navigation bar
        previousButton = ThemedButton(
            title: "‹",
            fillColor: theme.fieldBackground,
            borderColor: theme.fieldBorder,
            textColor: theme.text,
            font: NSFont.systemFont(ofSize: 19),
            frame: NSRect(x: margin + 2, y: y, width: 32, height: 32)
        )
        previousButton.toolTip = "上一月"
        previousButton.setAccessibilityLabel("上一月")
        previousButton.onClick = { [weak self] in self?.shiftMonth(-1) }
        root.addSubview(previousButton)

        nextButton = ThemedButton(
            title: "›",
            fillColor: theme.fieldBackground,
            borderColor: theme.fieldBorder,
            textColor: theme.text,
            font: NSFont.systemFont(ofSize: 19),
            frame: NSRect(x: width - margin - 34, y: y, width: 32, height: 32)
        )
        nextButton.toolTip = "下一月"
        nextButton.setAccessibilityLabel("下一月")
        nextButton.onClick = { [weak self] in self?.shiftMonth(1) }
        root.addSubview(nextButton)

        monthLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        monthLabel.textColor = theme.text
        monthLabel.alignment = .center
        monthLabel.frame = NSRect(x: margin + 40, y: y + 5, width: contentWidth - 80, height: 24)
        root.addSubview(monthLabel)
        y += 42

        // Weekday header
        let cellWidth = contentWidth / 7.0
        for (idx, name) in Self.weekdayNames.enumerated() {
            let label = NSTextField(labelWithString: name)
            label.font = NSFont.systemFont(ofSize: 13)
            label.textColor = theme.text
            label.alignment = .center
            label.frame = NSRect(x: margin + CGFloat(idx) * cellWidth, y: y, width: cellWidth, height: 20)
            root.addSubview(label)
        }
        y += 24

        // 6x7 day grid
        let rowHeight: CGFloat = 37
        daysContainer.frame = NSRect(x: margin, y: y, width: contentWidth, height: rowHeight * 6)
        root.addSubview(daysContainer)
        y += rowHeight * 6 + 14

        // Footer
        selectedCountLabel.font = NSFont.systemFont(ofSize: 13)
        selectedCountLabel.textColor = theme.text
        selectedCountLabel.frame = NSRect(x: margin, y: y + 7, width: 160, height: 20)
        root.addSubview(selectedCountLabel)

        let confirm = ThemedButton(
            title: "确定",
            fillColor: theme.action,
            borderColor: theme.action,
            textColor: theme.actionText,
            font: NSFont.systemFont(ofSize: 13, weight: .medium),
            frame: NSRect(x: width - margin - 68, y: y, width: 68, height: 32)
        )
        confirm.onClick = { [weak self] in self?.finish(confirmed: true) }
        root.addSubview(confirm)

        let cancel = ThemedButton(
            title: "取消",
            fillColor: theme.fieldBackground,
            borderColor: theme.fieldBorder,
            textColor: theme.text,
            font: NSFont.systemFont(ofSize: 13),
            frame: NSRect(x: width - margin - 68 - 7 - 68, y: y, width: 68, height: 32)
        )
        cancel.onClick = { [weak self] in self?.finish(confirmed: false) }
        root.addSubview(cancel)
    }

    private func shiftMonth(_ offset: Int) {
        guard let next = month.addingMonths(offset) else { return }
        month = next
        showMonth()
    }

    private func showMonth() {
        monthLabel.stringValue = "\(month.year)年 \(month.month)月"
        previousButton.isEnabled = (month.year > 1 || month.month > 1)
        nextButton.isEnabled = (month.year < 9999 || month.month < 12)

        for sub in daysContainer.subviews {
            sub.removeFromSuperview()
        }
        dayButtons.removeAll()

        let firstColumn = month.mondayBasedWeekday
        let totalDays = CalendarDay.daysInMonth(year: month.year, month: month.month)
        let cellWidth = daysContainer.bounds.width / 7.0
        let cellHeight: CGFloat = 37

        for dayNum in 1...totalDays {
            let slot = firstColumn + (dayNum - 1)
            let col = slot % 7
            let row = slot / 7
            let date = CalendarDay(year: month.year, month: month.month, day: dayNum)
            let selected = isWorkday(date)

            let rect = NSRect(
                x: CGFloat(col) * cellWidth + 2,
                y: CGFloat(row) * cellHeight + 2,
                width: cellWidth - 4,
                height: cellHeight - 4
            )
            let button = ThemedButton(
                title: "\(dayNum)",
                fillColor: selected ? theme.action : theme.fieldBackground,
                borderColor: selected ? theme.action : theme.fieldBorder,
                textColor: selected ? theme.actionText : theme.text,
                font: NSFont.systemFont(ofSize: 13),
                frame: rect
            )
            button.isSelectedState = selected
            button.setAccessibilityLabel(date.chineseLabel)
            button.onClick = { [weak self, weak button] in
                guard let self, let button else { return }
                self.toggleDay(date, button: button)
            }
            daysContainer.addSubview(button)
            dayButtons.append((date, button))
        }
        updateCount()
    }

    private func toggleDay(_ date: CalendarDay, button: ThemedButton) {
        let nextSelected = !button.isSelectedState
        button.isSelectedState = nextSelected
        if nextSelected == date.isWeekday {
            overrides.remove(date)
        } else {
            overrides.insert(date)
        }
        button.fillColor = nextSelected ? theme.action : theme.fieldBackground
        button.borderColor = nextSelected ? theme.action : theme.fieldBorder
        button.textColor = nextSelected ? theme.actionText : theme.text
        updateCount()
    }

    private func isWorkday(_ date: CalendarDay) -> Bool {
        return date.isWeekday != overrides.contains(date)
    }

    private func updateCount() {
        let count = dayButtons.reduce(0) { $0 + ($1.1.isSelectedState ? 1 : 0) }
        selectedCountLabel.stringValue = "本月计薪 \(count) 天"
    }

    private func finish(confirmed: Bool) {
        let handler = onComplete
        onComplete = nil
        if let parent = sheetParent {
            parent.endSheet(self, returnCode: confirmed ? .OK : .cancel)
        } else {
            close()
        }
        handler?(confirmed ? Array(overrides).sorted() : nil)
    }
}
