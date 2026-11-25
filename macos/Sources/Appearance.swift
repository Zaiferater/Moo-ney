import AppKit

extension NSColor {
    /// Parses `#RRGGBB` or `#AARRGGBB` (matching WPF hex color format).
    static func fromHex(_ hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        if cleaned.count == 8 {
            let a = CGFloat((value >> 24) & 0xFF) / 255.0
            let r = CGFloat((value >> 16) & 0xFF) / 255.0
            let g = CGFloat((value >> 8) & 0xFF) / 255.0
            let b = CGFloat(value & 0xFF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

final class AppTheme: Equatable {
    static let defaultId = Settings.defaultThemeId
    static let choices: [AppTheme] = [
        AppTheme(
            id: defaultId, name: "薰衣草紫",
            timerBackground: "#B1EADAFB", text: "#312343", todayAmount: "#563277", monthAmount: "#404177",
            settingsBackground: "#F7F0FC", fieldBackground: "#FFFAFF", fieldBorder: "#CFBBE1",
            action: "#64428B", actionText: "#FFFFFF", pinBackground: "#C4AFDF", error: "#983C45",
            isDark: false
        ),
        AppTheme(
            id: "mint", name: "薄荷青",
            timerBackground: "#B9D8EEE6", text: "#193B34", todayAmount: "#245B4C", monthAmount: "#205D60",
            settingsBackground: "#EDF8F4", fieldBackground: "#F7FFFB", fieldBorder: "#A5C8BB",
            action: "#28695D", actionText: "#FFFFFF", pinBackground: "#ABD3C5", error: "#963C35",
            isDark: false
        ),
        AppTheme(
            id: "peach", name: "杏桃橙",
            timerBackground: "#BCFCE4CE", text: "#492D23", todayAmount: "#833D21", monthAmount: "#775025",
            settingsBackground: "#FFF4E8", fieldBackground: "#FFFBF5", fieldBorder: "#E5BFA2",
            action: "#914B2B", actionText: "#FFFFFF", pinBackground: "#EAB797", error: "#9C372E",
            isDark: false
        ),
        AppTheme(
            id: "glacier", name: "冰川蓝",
            timerBackground: "#BADEEEFF", text: "#17364E", todayAmount: "#16487B", monthAmount: "#205763",
            settingsBackground: "#EDF6FF", fieldBackground: "#F8FCFF", fieldBorder: "#AAC6DF",
            action: "#286188", actionText: "#FFFFFF", pinBackground: "#A7C9E9", error: "#8D3540",
            isDark: false
        ),
        AppTheme(
            id: "smoke", name: "烟灰蓝",
            timerBackground: "#C8324258", text: "#F8FAFF", todayAmount: "#FFE9AD", monthAmount: "#D5F4FF",
            settingsBackground: "#3E5066", fieldBackground: "#4B5D74", fieldBorder: "#8298B0",
            action: "#C8DEFA", actionText: "#1C2F44", pinBackground: "#536B86", error: "#FFD1CC",
            isDark: true
        )
    ]

    let id: String
    let name: String
    let timerBackground: NSColor
    let text: NSColor
    let todayAmount: NSColor
    let monthAmount: NSColor
    let settingsBackground: NSColor
    let fieldBackground: NSColor
    let fieldBorder: NSColor
    let action: NSColor
    let actionText: NSColor
    let pinBackground: NSColor
    let error: NSColor
    let isDark: Bool

    private init(
        id: String, name: String, timerBackground: String, text: String, todayAmount: String,
        monthAmount: String, settingsBackground: String, fieldBackground: String, fieldBorder: String,
        action: String, actionText: String, pinBackground: String, error: String, isDark: Bool
    ) {
        self.id = id
        self.name = name
        self.timerBackground = NSColor.fromHex(timerBackground)
        self.text = NSColor.fromHex(text)
        self.todayAmount = NSColor.fromHex(todayAmount)
        self.monthAmount = NSColor.fromHex(monthAmount)
        self.settingsBackground = NSColor.fromHex(settingsBackground)
        self.fieldBackground = NSColor.fromHex(fieldBackground)
        self.fieldBorder = NSColor.fromHex(fieldBorder)
        self.action = NSColor.fromHex(action)
        self.actionText = NSColor.fromHex(actionText)
        self.pinBackground = NSColor.fromHex(pinBackground)
        self.error = NSColor.fromHex(error)
        self.isDark = isDark
    }

    static func resolve(_ id: String?) -> AppTheme {
        if let id, let found = choices.first(where: { $0.id == id }) {
            return found
        }
        return choices[0]
    }

    static func == (lhs: AppTheme, rhs: AppTheme) -> Bool {
        return lhs.id == rhs.id
    }
}

struct MascotChoice {
    static let defaultId = Settings.defaultMascotId
    static let choices: [MascotChoice] = [
        MascotChoice(id: defaultId, name: "打字小牛"),
        MascotChoice(id: "panda", name: "开会小熊猫"),
        MascotChoice(id: "cat", name: "赶日报的橘猫"),
        MascotChoice(id: "penguin", name: "改稿企鹅")
    ]

    let id: String
    let name: String

    static func resolve(_ id: String?) -> MascotChoice {
        if let id, let found = choices.first(where: { $0.id == id }) {
            return found
        }
        return choices[0]
    }
}

protocol WorkMascotView: NSView {
    func showWork(working: Bool, animate: Bool)
}

final class MascotView: NSView {
    private var mascot: WorkMascotView?
    private(set) var mascotId: String = ""

    init(id: String?, size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        select(id)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        return frame.size
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func select(_ id: String?) {
        let choice = MascotChoice.resolve(id)
        if mascotId == choice.id { return }
        mascotId = choice.id

        mascot?.removeFromSuperview()
        let art: WorkMascotView = (choice.id == MascotChoice.defaultId)
            ? TypingCowView(frame: bounds)
            : SpriteMascotView(id: choice.id, frame: bounds)
        art.autoresizingMask = [.width, .height]
        addSubview(art)
        mascot = art
        setAccessibilityLabel(choice.name)
    }

    func showWork(working: Bool, animate: Bool) {
        mascot?.showWork(working: working, animate: animate)
    }

    /// Renders a static preview image (e.g., for popup menu items).
    static func previewImage(id: String, size: CGFloat) -> NSImage {
        let view = MascotView(id: id, size: size)
        view.showWork(working: true, animate: false)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: ctx, flipped: false))
        }
        image.unlockFocus()
        return image
    }
}

final class SpriteMascotView: NSView, WorkMascotView {
    // First 12 cells show each working pose; next 12 repeat the poses with a blink.
    private static let poseCount = 12
    private static var cache: [String: [CGImage]] = [:]

    private let frames: [CGImage]
    private var clockStart: TimeInterval?
    private var frameIndex = 0

    init(id: String, frame: NSRect) {
        self.frames = Self.loadFrames(id: id)
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    private static func loadFrames(id: String) -> [CGImage] {
        if let cached = cache[id] {
            return cached
        }
        guard let url = resourceURL(for: id),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let strip = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return []
        }

        let cellSize = strip.height
        let total = 2 * poseCount
        var result: [CGImage] = []
        result.reserveCapacity(total)
        for index in 0..<total {
            let rect = CGRect(x: index * cellSize, y: 0, width: cellSize, height: cellSize)
            if let cropped = strip.cropping(to: rect) {
                result.append(cropped)
            }
        }
        cache[id] = result
        return result
    }

    private static func resourceURL(for id: String) -> URL? {
        if let url = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "Mascots") {
            return url
        }
        if let url = Bundle.main.url(forResource: id, withExtension: "png") {
            return url
        }
        // Fallback when running unbundled binary during local development
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("Mascots/\(id).png"),
            cwd.appendingPathComponent("../Mascots/\(id).png")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func showWork(working: Bool, animate: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if working && animate {
            if clockStart == nil {
                clockStart = now
            }
        } else {
            clockStart = nil
        }

        let elapsedMs: Int64
        if let start = clockStart {
            elapsedMs = max(0, Int64((now - start) * 1000.0))
        } else {
            elapsedMs = 0
        }

        let tick = elapsedMs / 142
        let next = Int(tick % Int64(Self.poseCount)) + (tick % 25 == 22 ? Self.poseCount : 0)
        if next == frameIndex { return }
        frameIndex = next
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !frames.isEmpty, frameIndex < frames.count,
              let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }
        ctx.interpolationQuality = .high
        ctx.draw(frames[frameIndex], in: bounds)
    }
}

struct FontChoice {
    let familyName: String   // "" means system default
    let displayName: String

    static let defaultChoice = FontChoice(familyName: "", displayName: "系统默认（苹方 / Menlo）")

    private static let preferredFamilies: [String] = [
        "PingFang SC",
        "Hiragino Sans GB",
        "Heiti SC",
        "Kaiti SC",
        "Songti SC",
        "Yuanti SC",
        "Lantinghei SC",
        "Wawati SC",
        "Weibei SC",
        "Xingkai SC",
        "Menlo",
        "SF Mono",
        "Avenir Next",
        "Helvetica Neue",
        "Georgia",
        "Courier New"
    ]

    static func availableChoices() -> [FontChoice] {
        let manager = NSFontManager.shared
        let allFamilies = Set(manager.availableFontFamilies)
        var choices: [FontChoice] = [defaultChoice]
        var seen = Set<String>()

        for family in preferredFamilies where allFamilies.contains(family) {
            seen.insert(family)
            let label = manager.localizedName(forFamily: family, face: nil)
            choices.append(FontChoice(familyName: family, displayName: label))
        }

        let remaining = allFamilies
            .filter { !seen.contains($0) && !$0.hasPrefix(".") }
            .sorted {
                let a = manager.localizedName(forFamily: $0, face: nil)
                let b = manager.localizedName(forFamily: $1, face: nil)
                return a.localizedStandardCompare(b) == .orderedAscending
            }

        for family in remaining {
            let label = manager.localizedName(forFamily: family, face: nil)
            choices.append(FontChoice(familyName: family, displayName: label))
        }

        return choices
    }

    static func uiFont(familyName: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        guard !familyName.isEmpty else {
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
        let manager = NSFontManager.shared
        let traits: NSFontTraitMask = (weight.rawValue >= NSFont.Weight.semibold.rawValue) ? .boldFontMask : []
        let weightNum = (weight.rawValue >= NSFont.Weight.semibold.rawValue) ? 9 : 5
        if let font = manager.font(withFamily: familyName, traits: traits, weight: weightNum, size: size) {
            return font
        }
        if let font = NSFont(name: familyName, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func amountFont(familyName: String, size: CGFloat) -> NSFont {
        guard !familyName.isEmpty else {
            return NSFont(name: "Menlo-Regular", size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        let manager = NSFontManager.shared
        if let font = manager.font(withFamily: familyName, traits: [], weight: 5, size: size) {
            return font
        }
        if let font = NSFont(name: familyName, size: size) {
            return font
        }
        return NSFont(name: "Menlo-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

enum MenuBarIcon {
    /// Crisp 18x18 template icon for macOS status bar (automatically adapts to light/dark menu bar).
    static func makeImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Horns
            let leftHorn = NSBezierPath()
            leftHorn.lineWidth = 1.5
            leftHorn.lineCapStyle = .round
            leftHorn.move(to: NSPoint(x: 5.5, y: 5.0))
            leftHorn.curve(to: NSPoint(x: 4.5, y: 2.0),
                           controlPoint1: NSPoint(x: 4.2, y: 4.2),
                           controlPoint2: NSPoint(x: 4.0, y: 2.8))
            leftHorn.stroke()

            let rightHorn = NSBezierPath()
            rightHorn.lineWidth = 1.5
            rightHorn.lineCapStyle = .round
            rightHorn.move(to: NSPoint(x: 12.5, y: 5.0))
            rightHorn.curve(to: NSPoint(x: 13.5, y: 2.0),
                            controlPoint1: NSPoint(x: 13.8, y: 4.2),
                            controlPoint2: NSPoint(x: 14.0, y: 2.8))
            rightHorn.stroke()

            // Ears
            NSBezierPath(ovalIn: NSRect(x: 1.4, y: 5.3, width: 3.3, height: 2.2)).fill()
            NSBezierPath(ovalIn: NSRect(x: 13.3, y: 5.3, width: 3.3, height: 2.2)).fill()

            // Head outline
            let head = NSBezierPath(ovalIn: NSRect(x: 3.5, y: 4.0, width: 11.0, height: 9.8))
            head.lineWidth = 1.4
            head.stroke()

            // Eyes
            NSBezierPath(ovalIn: NSRect(x: 6.2, y: 7.1, width: 1.5, height: 1.8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.3, y: 7.1, width: 1.5, height: 1.8)).fill()

            // Snout
            let snout = NSBezierPath(roundedRect: NSRect(x: 5.4, y: 10.1, width: 7.2, height: 4.8), xRadius: 2.3, yRadius: 2.3)
            NSColor.black.withAlphaComponent(0.18).setFill()
            snout.fill()
            NSColor.black.setStroke()
            snout.lineWidth = 1.3
            snout.stroke()

            // Nostrils
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7.1, y: 11.7, width: 1.2, height: 1.2)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9.7, y: 11.7, width: 1.2, height: 1.2)).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
