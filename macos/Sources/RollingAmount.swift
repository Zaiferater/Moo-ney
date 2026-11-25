import AppKit

final class RollingAmountView: NSView {
    private var font: NSFont
    private var fontFamilyName: String
    private var textSize: CGFloat
    private var foreground: NSColor = .labelColor
    private var previousChars: [Character] = []
    private var currentChars: [Character] = []
    private var currentText = ""
    private var currentAmount: Decimal = 0
    private var transitionStart: TimeInterval = 0
    private var animationTimer: Timer?
    private var isAnimating = false

    private var cellWidth: CGFloat = 12
    private var lineHeight: CGFloat = 24

    init(textSize: CGFloat, fontFamilyName: String = "") {
        self.textSize = textSize
        self.fontFamilyName = fontFamilyName
        self.font = FontChoice.amountFont(familyName: fontFamilyName, size: textSize)
        let height = ceil(textSize * 1.25)
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: height))
        wantsLayer = true
        layer?.masksToBounds = true
        recomputeMetrics()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopAnimation()
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(textSize * 1.25))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func configureTypography(fontFamilyName: String, textSize: CGFloat) {
        if self.fontFamilyName == fontFamilyName && abs(self.textSize - textSize) < 0.01 {
            return
        }
        self.fontFamilyName = fontFamilyName
        self.textSize = textSize
        self.font = FontChoice.amountFont(familyName: fontFamilyName, size: textSize)
        recomputeMetrics()
        needsDisplay = true
    }

    private func recomputeMetrics() {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        for ch in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "¥"] {
            let size = (ch as NSString).size(withAttributes: attrs)
            maxWidth = max(maxWidth, size.width)
            maxHeight = max(maxHeight, size.height)
        }
        cellWidth = max(1, maxWidth)
        lineHeight = max(1, maxHeight)
    }

    func setForeground(_ color: NSColor) {
        if foreground == color { return }
        foreground = color
        needsDisplay = true
    }

    func setAmount(_ amount: Decimal, animate: Bool) {
        let next = PaySnapshot.formatAmount(amount)
        if next == currentText {
            if !animate && isAnimating {
                stopAnimation()
                needsDisplay = true
            }
            return
        }

        let moves = animate && !currentText.isEmpty && amount > currentAmount
        previousChars = currentChars
        currentText = next
        currentChars = Array(next)
        currentAmount = amount
        setAccessibilityLabel(next)

        if moves {
            transitionStart = ProcessInfo.processInfo.systemUptime
            startAnimation()
        } else {
            stopAnimation()
        }
        needsDisplay = true
    }

    private func startAnimation() {
        if isAnimating { return }
        isAnimating = true
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.onFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func onFrame() {
        let elapsedMs = (ProcessInfo.processInfo.systemUptime - transitionStart) * 1000.0
        if elapsedMs >= 44.0 {
            stopAnimation()
        }
        needsDisplay = true
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        isAnimating = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !currentChars.isEmpty, cellWidth > 0, bounds.width > 0,
              let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }

        let totalWidth = cellWidth * CGFloat(currentChars.count)
        let scale = min(1.0, bounds.width / totalWidth)
        if scale <= 0 { return }

        ctx.saveGState()
        ctx.clip(to: bounds)
        ctx.scaleBy(x: scale, y: 1.0)

        let baseline = (bounds.height - lineHeight) / 2.0
        let elapsedMs = (ProcessInfo.processInfo.systemUptime - transitionStart) * 1000.0
        let progress = CGFloat(min(1.0, max(0.0, elapsedMs / 44.0)))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground
        ]

        for index in 0..<currentChars.count {
            let digit = currentChars[index]
            let x = CGFloat(index) * cellWidth
            let prevIndex = index + previousChars.count - currentChars.count
            let old: Character = (prevIndex >= 0 && prevIndex < previousChars.count) ? previousChars[prevIndex] : " "

            if isAnimating && isDigit(digit) && isDigit(old) && digit != old {
                drawGlyph(old, at: NSPoint(x: x, y: baseline - progress * lineHeight), attrs: attrs)
                drawGlyph(digit, at: NSPoint(x: x, y: baseline + (1.0 - progress) * lineHeight), attrs: attrs)
            } else {
                drawGlyph(digit, at: NSPoint(x: x, y: baseline), attrs: attrs)
            }
        }

        ctx.restoreGState()
    }

    private func drawGlyph(_ char: Character, at origin: NSPoint, attrs: [NSAttributedString.Key: Any]) {
        let str = String(char) as NSString
        let size = str.size(withAttributes: attrs)
        let dx = (cellWidth - size.width) / 2.0
        let dy = (lineHeight - size.height) / 2.0
        str.draw(at: NSPoint(x: origin.x + dx, y: origin.y + dy), withAttributes: attrs)
    }

    private func isDigit(_ char: Character) -> Bool {
        return char >= "0" && char <= "9"
    }
}
