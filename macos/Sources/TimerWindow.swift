import AppKit
import QuartzCore

final class TimerWindow: NSPanel {
    private static let baseExpandedWidth: CGFloat = 510
    private static let baseExpandedHeight: CGFloat = 118
    private static let baseCompactSize: CGFloat = 70
    private static let baseExpandedCowOrigin = NSPoint(x: 12, y: 24)
    private static let toolBackground = NSColor.fromHex("#48FFFFFF")
    private static let cardBorderColor = NSColor.fromHex("#9BFFFFFF")
    private static let dragThreshold: CGFloat = 4.0

    private let onShowSettings: () -> Void
    private let onSaveLayout: (Double, Double, Double) -> Void
    private let onChangeTopmost: (Bool) -> Void
    private let onExit: () -> Void
    private let onStateChanged: () -> Void

    private var settings: Settings
    private var theme: AppTheme
    private var fontName: String
    private var windowScale: CGFloat

    private var expandedWidth: CGFloat { round(Self.baseExpandedWidth * windowScale) }
    private var expandedHeight: CGFloat { round(Self.baseExpandedHeight * windowScale) }
    private var compactSize: CGFloat { round(Self.baseCompactSize * windowScale) }
    private var expandedCowOrigin: NSPoint {
        NSPoint(
            x: round(Self.baseExpandedCowOrigin.x * windowScale),
            y: round(Self.baseExpandedCowOrigin.y * windowScale)
        )
    }

    private let surface = FlippedView()
    private let cardView = InteractiveCardView()
    private let headingLabel = NSTextField(labelWithString: AppConstants.title)
    private let todayCaption = NSTextField(labelWithString: "今日已赚")
    private let monthCaption = NSTextField(labelWithString: "本月已赚")
    private let todayAmount: RollingAmountView
    private let monthAmount: RollingAmountView
    private let remainingLabel = NSTextField(labelWithString: "")
    private let breakCountdownLabel = NSTextField(labelWithString: "")

    private let pinButton = VectorToolButton(kind: .pin)
    private let settingsButton = VectorToolButton(kind: .settings)
    private let closeButton = VectorToolButton(kind: .close)
    private let resizeGrip = ResizeGripView()

    private let cowButton = InteractiveCowView()
    private let circleView = CircleBadgeView()
    private let mascotView: MascotView

    private var compactOffset = TimerWindow.baseExpandedCowOrigin
    private var compactRequested = false
    private var compactLayout = false
    private var collapseProgress: CGFloat = 0
    private var transitionFrom: CGFloat = 0
    private var transitionTarget: CGFloat = 0
    private var transitionStart: TimeInterval = 0
    private var transitionTimer: Timer?
    private var refreshTimer: Timer?

    private var cardDragStartMouse: NSPoint?
    private var cardDragStartOrigin: NSPoint?
    private var cardResizeStartMouse: NSPoint?
    private var cardResizeStartTopLeft: NSPoint?
    private var cardResizeStartScale: CGFloat = 1.0
    private var cardResizeMode: InteractiveCardView.ResizeEdge = .none

    private var cowPressScreen: NSPoint?
    private var cowDragging = false
    private var cowDragStartOrigin: NSPoint?

    var isCompact: Bool { compactRequested }
    var currentScale: Double { Double(windowScale) }

    init(
        settings: Settings,
        onShowSettings: @escaping () -> Void,
        onSaveLayout: @escaping (Double, Double, Double) -> Void,
        onChangeTopmost: @escaping (Bool) -> Void,
        onExit: @escaping () -> Void,
        onStateChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.theme = AppTheme.resolve(settings.themeId)
        self.fontName = settings.fontName
        self.windowScale = CGFloat(Settings.clampScale(settings.windowScale))
        self.onShowSettings = onShowSettings
        self.onSaveLayout = onSaveLayout
        self.onChangeTopmost = onChangeTopmost
        self.onExit = onExit
        self.onStateChanged = onStateChanged
        self.mascotView = MascotView(id: settings.mascotId, size: 66)
        self.todayAmount = RollingAmountView(textSize: 23, fontFamilyName: settings.fontName)
        self.monthAmount = RollingAmountView(textSize: 22, fontFamilyName: settings.fontName)

        let initW = round(Self.baseExpandedWidth * CGFloat(Settings.clampScale(settings.windowScale)))
        let initH = round(Self.baseExpandedHeight * CGFloat(Settings.clampScale(settings.windowScale)))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initW, height: initH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = AppConstants.title
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        compactOffset = expandedCowOrigin

        buildUI()
        applyScaledLayout(anchorTopLeft: nil)
        placeInitialWindow(settings: settings)
        setAppearance(
            mascotId: settings.mascotId,
            themeId: settings.themeId,
            fontName: settings.fontName,
            windowScale: settings.windowScale
        )
        applyTopmost()
        updateCowAction()
        drawPresentation(0)
        refresh(now: Date(), allowMotion: false)
        startRefreshTimer()
    }

    deinit {
        stopTimers()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func stopTimers() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        transitionTimer?.invalidate()
        transitionTimer = nil
    }

    func updateSettings(_ next: Settings) {
        settings = next
        setAppearance(
            mascotId: next.mascotId,
            themeId: next.themeId,
            fontName: next.fontName,
            windowScale: next.windowScale
        )
        applyTopmost()
        refresh(now: Date(), allowMotion: false)
        onStateChanged()
    }

    func setAppearance(mascotId: String, themeId: String, fontName: String, windowScale: Double) {
        mascotView.select(mascotId)
        let palette = AppTheme.resolve(themeId)
        theme = palette
        self.fontName = fontName

        let clampedScale = CGFloat(Settings.clampScale(windowScale))
        if abs(self.windowScale - clampedScale) > 0.001 {
            let anchor = currentTopLeftOrigin()
            self.windowScale = clampedScale
            applyScaledLayout(anchorTopLeft: anchor)
        }

        cardView.layer?.backgroundColor = theme.timerBackground.cgColor
        circleView.fillColor = theme.settingsBackground
        circleView.strokeColor = theme.fieldBorder

        headingLabel.textColor = theme.text
        todayCaption.textColor = theme.text
        monthCaption.textColor = theme.text
        remainingLabel.textColor = theme.text
        breakCountdownLabel.textColor = theme.text
        resizeGrip.gripColor = theme.text

        todayAmount.setForeground(theme.todayAmount)
        monthAmount.setForeground(theme.monthAmount)

        pinButton.strokeColor = theme.text
        settingsButton.strokeColor = theme.text
        closeButton.strokeColor = theme.text
        applyTypography()
        applyTopmost()
    }

    func resetScale() {
        let anchor = currentTopLeftOrigin()
        windowScale = CGFloat(Settings.defaultWindowScale)
        applyScaledLayout(anchorTopLeft: anchor)
        let pos = expandedPosition
        onSaveLayout(Double(pos.x), Double(pos.y), Double(windowScale))
    }

    func toggleCompactFromMenu() {
        toggleCompact()
    }

    /// Expanded top-left position in top-down desktop coordinates (primary screen top = 0).
    var expandedPosition: NSPoint {
        let currentTopLeft = currentTopLeftOrigin()
        if compactLayout {
            let desired = NSPoint(
                x: currentTopLeft.x - expandedCowOrigin.x,
                y: currentTopLeft.y - expandedCowOrigin.y
            )
            return fitExpanded(desired: desired)
        }
        return currentTopLeft
    }

    private func buildUI() {
        surface.wantsLayer = true
        surface.layer?.masksToBounds = true
        contentView = surface

        cardView.wantsLayer = true
        cardView.layer?.borderWidth = 1
        cardView.layer?.borderColor = Self.cardBorderColor.cgColor
        cardView.onMouseDown = { [weak self] event, edge in self?.handleCardMouseDown(event, edge: edge) }
        cardView.onMouseDragged = { [weak self] event in self?.handleCardMouseDragged(event) }
        cardView.onMouseUp = { [weak self] event in self?.handleCardMouseUp(event) }
        cardView.onHoverChanged = { [weak self] hovered in
            self?.resizeGrip.alphaValue = hovered ? 0.55 : 0.0
        }
        cardView.contextMenuBuilder = { [weak self] in self?.buildContextMenu() }
        surface.addSubview(cardView)

        cardView.addSubview(headingLabel)

        pinButton.onClick = { [weak self] in
            guard let self else { return }
            self.onChangeTopmost(!self.settings.alwaysOnTop)
        }
        cardView.addSubview(pinButton)

        settingsButton.toolTip = "设置"
        settingsButton.setAccessibilityLabel("设置")
        settingsButton.normalBackground = Self.toolBackground
        settingsButton.onClick = { [weak self] in self?.onShowSettings() }
        cardView.addSubview(settingsButton)

        closeButton.toolTip = "退出程序"
        closeButton.setAccessibilityLabel("退出程序")
        closeButton.normalBackground = Self.toolBackground
        closeButton.onClick = { [weak self] in self?.onExit() }
        cardView.addSubview(closeButton)

        cardView.addSubview(todayCaption)
        cardView.addSubview(todayAmount)
        remainingLabel.lineBreakMode = .byTruncatingTail
        cardView.addSubview(remainingLabel)

        cardView.addSubview(monthCaption)
        cardView.addSubview(monthAmount)
        breakCountdownLabel.lineBreakMode = .byTruncatingTail
        cardView.addSubview(breakCountdownLabel)

        resizeGrip.alphaValue = 0.0
        cardView.addSubview(resizeGrip)

        cowButton.wantsLayer = true
        cowButton.onMouseDown = { [weak self] event in self?.handleCowMouseDown(event) }
        cowButton.onMouseDragged = { [weak self] event in self?.handleCowMouseDragged(event) }
        cowButton.onMouseUp = { [weak self] event in self?.handleCowMouseUp(event) }
        cowButton.contextMenuBuilder = { [weak self] in self?.buildContextMenu() }

        cowButton.addSubview(circleView)
        cowButton.addSubview(mascotView)
        surface.addSubview(cowButton)
    }

    private func applyTypography() {
        let s = windowScale
        headingLabel.font = FontChoice.uiFont(familyName: fontName, size: 20 * s, weight: .semibold)
        let smallFont = FontChoice.uiFont(familyName: fontName, size: 13 * s, weight: .regular)
        todayCaption.font = smallFont
        monthCaption.font = smallFont
        remainingLabel.font = smallFont
        breakCountdownLabel.font = smallFont
        todayAmount.configureTypography(fontFamilyName: fontName, textSize: 23 * s)
        monthAmount.configureTypography(fontFamilyName: fontName, textSize: 22 * s)
    }

    private func applyScaledLayout(anchorTopLeft: NSPoint?) {
        let s = windowScale
        let w = expandedWidth
        let h = expandedHeight
        let cSize = compactSize

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if let anchor = anchorTopLeft {
            if compactLayout {
                setTopLeftBounds(origin: anchor, width: cSize, height: cSize)
            } else {
                setTopLeftBounds(origin: anchor, width: w, height: h)
            }
        } else {
            surface.frame = NSRect(x: 0, y: 0, width: compactLayout ? cSize : w, height: compactLayout ? cSize : h)
        }

        cardView.layer?.transform = CATransform3DIdentity
        cardView.frame = NSRect(x: 0, y: 0, width: w, height: h)
        cardView.layer?.cornerRadius = 24 * s

        let padX = 13 * s
        let col0W = 78 * s
        let col1X = padX + col0W
        let colWidth = (w - padX * 2 - col0W) / 2.0
        let col2X = col1X + colWidth

        headingLabel.frame = NSRect(x: col1X, y: 10 * s, width: colWidth * 1.25, height: 28 * s)

        let toolSize = 26 * s
        let toolGap = 4 * s
        let toolY = 9 * s
        let closeX = w - padX - toolSize
        let settingsX = closeX - toolGap - toolSize
        let pinX = settingsX - toolGap - toolSize

        pinButton.frame = NSRect(x: pinX, y: toolY, width: toolSize, height: toolSize)
        settingsButton.frame = NSRect(x: settingsX, y: toolY, width: toolSize, height: toolSize)
        closeButton.frame = NSRect(x: closeX, y: toolY, width: toolSize, height: toolSize)

        let rowTop = 48 * s
        let captionWidth = 58 * s
        let todayH = ceil(23 * s * 1.25)
        let monthH = ceil(22 * s * 1.25)

        todayCaption.frame = NSRect(x: col1X, y: rowTop + 5 * s, width: captionWidth, height: 20 * s)
        todayAmount.frame = NSRect(
            x: col1X + captionWidth + 4 * s,
            y: rowTop,
            width: max(40, colWidth - 6 * s - captionWidth - 4 * s),
            height: todayH
        )
        remainingLabel.frame = NSRect(x: col1X, y: rowTop + todayH + 3 * s, width: colWidth - 6 * s, height: 20 * s)

        monthCaption.frame = NSRect(x: col2X, y: rowTop + 5 * s, width: captionWidth, height: 20 * s)
        monthAmount.frame = NSRect(
            x: col2X + captionWidth + 4 * s,
            y: rowTop,
            width: max(40, colWidth - 4 * s - captionWidth - 4 * s),
            height: monthH
        )
        breakCountdownLabel.frame = NSRect(x: col2X, y: rowTop + monthH + 4 * s, width: colWidth - 4 * s, height: 20 * s)

        let gripSize = max(14, 16 * s)
        resizeGrip.frame = NSRect(x: w - gripSize - 5 * s, y: h - gripSize - 5 * s, width: gripSize, height: gripSize)

        circleView.frame = NSRect(x: 0, y: 0, width: cSize, height: cSize)
        let inset = 2 * s
        mascotView.frame = NSRect(x: inset, y: inset, width: cSize - inset * 2, height: cSize - inset * 2)
        compactOffset = expandedCowOrigin

        applyTypography()
        drawPresentation(collapseProgress)

        CATransaction.commit()
    }

    private func applyTopmost() {
        let enabled = settings.alwaysOnTop
        level = enabled ? .floating : .normal
        pinButton.normalBackground = enabled ? theme.pinBackground : Self.toolBackground
        pinButton.toolTip = enabled ? "始终置顶已开启，单击关闭" : "始终置顶已关闭，单击开启"
        pinButton.setAccessibilityLabel("始终置顶")
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: compactRequested ? "展开悬浮窗" : "收起悬浮窗",
            action: #selector(menuToggleCompact),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let editItem = NSMenuItem(title: "设置", action: #selector(menuShowSettings), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let pinItem = NSMenuItem(title: "始终置顶", action: #selector(menuTogglePin), keyEquivalent: "")
        pinItem.target = self
        pinItem.state = settings.alwaysOnTop ? .on : .off
        menu.addItem(pinItem)

        let resetSizeItem = NSMenuItem(title: "重置默认大小", action: #selector(menuResetSize), keyEquivalent: "")
        resetSizeItem.target = self
        resetSizeItem.isEnabled = abs(windowScale - 1.0) > 0.01
        menu.addItem(resetSizeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出计时器", action: #selector(menuExit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func menuToggleCompact() { toggleCompact() }
    @objc private func menuShowSettings() { onShowSettings() }
    @objc private func menuTogglePin() { onChangeTopmost(!settings.alwaysOnTop) }
    @objc private func menuResetSize() { resetScale() }
    @objc private func menuExit() { onExit() }

    // MARK: - Collapse / Expand Animation

    private func toggleCompact() {
        let from = collapseProgress
        compactRequested.toggle()
        updateCowAction()
        onStateChanged()

        if !compactRequested && compactLayout {
            let currentTopLeft = currentTopLeftOrigin()
            let origin = expandedPosition
            compactOffset = NSPoint(x: currentTopLeft.x - origin.x, y: currentTopLeft.y - origin.y)
            compactLayout = false
            setTopLeftBounds(origin: origin, width: expandedWidth, height: expandedHeight)
            drawPresentation(from)
            refresh(now: Date(), allowMotion: false)
        }

        cardView.isHidden = false
        cardView.isInteractive = false
        let target: CGFloat = compactRequested ? 1.0 : 0.0
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion || abs(from - target) < 0.0001 {
            finishTransition(target: target)
            return
        }

        transitionFrom = from
        transitionTarget = target
        transitionStart = ProcessInfo.processInfo.systemUptime
        transitionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.stepTransition()
        }
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
    }

    private func stepTransition() {
        let elapsedMs = (ProcessInfo.processInfo.systemUptime - transitionStart) * 1000.0
        let raw = min(1.0, max(0.0, elapsedMs / 180.0))
        let eased: Double = raw < 0.5
            ? 4.0 * raw * raw * raw
            : 1.0 - pow(-2.0 * raw + 2.0, 3.0) / 2.0
        let value = transitionFrom + (transitionTarget - transitionFrom) * CGFloat(eased)
        collapseProgress = value
        drawPresentation(value)

        if raw >= 1.0 {
            transitionTimer?.invalidate()
            transitionTimer = nil
            if compactRequested == (transitionTarget == 1.0) {
                finishTransition(target: transitionTarget)
            }
        }
    }

    private func finishTransition(target: CGFloat) {
        transitionTimer?.invalidate()
        transitionTimer = nil
        collapseProgress = target

        if target == 1.0 {
            cardView.isHidden = true
            let currentTopLeft = currentTopLeftOrigin()
            compactLayout = true
            setTopLeftBounds(
                origin: NSPoint(x: currentTopLeft.x + compactOffset.x, y: currentTopLeft.y + compactOffset.y),
                width: compactSize,
                height: compactSize
            )
        } else {
            cardView.isInteractive = true
        }

        compactOffset = expandedCowOrigin
        drawPresentation(target)
    }

    private func drawPresentation(_ progress: CGFloat) {
        let baseCow = expandedCowOrigin
        let cowX = baseCow.x + (compactOffset.x - baseCow.x) * progress
        let cowY = baseCow.y + (compactOffset.y - baseCow.y) * progress

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        cowButton.frame = NSRect(
            x: compactLayout ? 0 : cowX,
            y: compactLayout ? 0 : cowY,
            width: compactSize,
            height: compactSize
        )

        let scaleX = 1.0 - progress * (1.0 - compactSize / expandedWidth)
        let scaleY = 1.0 - progress * (1.0 - compactSize / expandedHeight)
        let pivotX = cowX + compactSize / 2.0
        let pivotY = cowY + compactSize / 2.0

        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, pivotX, pivotY, 0)
        transform = CATransform3DScale(transform, scaleX, scaleY, 1)
        transform = CATransform3DTranslate(transform, -pivotX, -pivotY, 0)
        cardView.layer?.transform = transform
        cardView.alphaValue = 1.0 - progress
        circleView.alphaValue = progress

        CATransaction.commit()
    }

    private func updateCowAction() {
        let action = compactRequested ? "展开悬浮窗" : "收起悬浮窗"
        cowButton.toolTip = action + " · 拖动移动 · 右键菜单"
        cowButton.setAccessibilityLabel(action)
    }

    // MARK: - Dragging, Resizing & Clicking

    private func handleCardMouseDown(_ event: NSEvent, edge: InteractiveCardView.ResizeEdge) {
        if edge != .none {
            cardResizeMode = edge
            cardResizeStartMouse = NSEvent.mouseLocation
            cardResizeStartTopLeft = currentTopLeftOrigin()
            cardResizeStartScale = windowScale
            cardDragStartMouse = nil
            cardDragStartOrigin = nil
            return
        }

        if event.clickCount == 2 {
            cardDragStartMouse = nil
            cardDragStartOrigin = nil
            onShowSettings()
            return
        }
        cardResizeMode = .none
        cardDragStartMouse = NSEvent.mouseLocation
        cardDragStartOrigin = frame.origin
    }

    private func handleCardMouseDragged(_ event: NSEvent) {
        if cardResizeMode != .none,
           let startMouse = cardResizeStartMouse,
           let anchorTopLeft = cardResizeStartTopLeft {
            let current = NSEvent.mouseLocation
            let dx = current.x - startMouse.x
            // AppKit screen Y increases upward; downward drag has negative dy
            let dyDown = startMouse.y - current.y

            let startW = Self.baseExpandedWidth * cardResizeStartScale
            let startH = Self.baseExpandedHeight * cardResizeStartScale

            let proposedScale: CGFloat
            switch cardResizeMode {
            case .right:
                proposedScale = (startW + dx) / Self.baseExpandedWidth
            case .bottom:
                proposedScale = (startH + dyDown) / Self.baseExpandedHeight
            case .bottomRight:
                let sx = (startW + dx) / Self.baseExpandedWidth
                let sy = (startH + dyDown) / Self.baseExpandedHeight
                proposedScale = abs(sx - cardResizeStartScale) >= abs(sy - cardResizeStartScale) ? sx : sy
            case .none:
                proposedScale = cardResizeStartScale
            }

            let clamped = CGFloat(Settings.clampScale(Double(proposedScale)))
            if abs(clamped - windowScale) >= 0.005 {
                windowScale = clamped
                applyScaledLayout(anchorTopLeft: anchorTopLeft)
            }
            return
        }

        guard let startMouse = cardDragStartMouse, let startOrigin = cardDragStartOrigin else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - startMouse.x
        let dy = current.y - startMouse.y
        setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    private func handleCardMouseUp(_ event: NSEvent) {
        if cardResizeMode != .none {
            let changed = abs(windowScale - cardResizeStartScale) > 0.001
            cardResizeMode = .none
            cardResizeStartMouse = nil
            cardResizeStartTopLeft = nil
            if changed {
                let pos = expandedPosition
                onSaveLayout(Double(pos.x), Double(pos.y), Double(windowScale))
            }
            return
        }

        guard let startOrigin = cardDragStartOrigin else { return }
        cardDragStartMouse = nil
        cardDragStartOrigin = nil
        if frame.origin != startOrigin {
            let pos = expandedPosition
            onSaveLayout(Double(pos.x), Double(pos.y), Double(windowScale))
        }
    }

    private func handleCowMouseDown(_ event: NSEvent) {
        cowPressScreen = NSEvent.mouseLocation
        cowDragStartOrigin = frame.origin
        cowDragging = false
    }

    private func handleCowMouseDragged(_ event: NSEvent) {
        guard let startMouse = cowPressScreen, let startOrigin = cowDragStartOrigin else { return }
        if !compactLayout && !cardView.isInteractive { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - startMouse.x
        let dy = current.y - startMouse.y
        if !cowDragging && abs(dx) < Self.dragThreshold && abs(dy) < Self.dragThreshold {
            return
        }
        cowDragging = true
        setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    private func handleCowMouseUp(_ event: NSEvent) {
        let wasDragging = cowDragging
        let startOrigin = cowDragStartOrigin
        cowPressScreen = nil
        cowDragStartOrigin = nil
        cowDragging = false

        if wasDragging {
            if let startOrigin, frame.origin != startOrigin {
                let pos = expandedPosition
                onSaveLayout(Double(pos.x), Double(pos.y), Double(windowScale))
            }
        } else {
            toggleCompact()
        }
    }

    // MARK: - Multi-Monitor Coordinate Helpers

    private func primaryScreenTopY() -> CGFloat {
        return NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 900
    }

    private func currentTopLeftOrigin() -> NSPoint {
        let primaryTop = primaryScreenTopY()
        return NSPoint(x: frame.origin.x, y: primaryTop - frame.origin.y - frame.height)
    }

    private func setTopLeftBounds(origin: NSPoint, width: CGFloat, height: CGFloat) {
        let primaryTop = primaryScreenTopY()
        let appKitY = primaryTop - origin.y - height
        setFrame(NSRect(x: origin.x, y: appKitY, width: width, height: height), display: true)
        surface.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func topLeftRect(for screenRect: NSRect) -> NSRect {
        let primaryTop = primaryScreenTopY()
        return NSRect(
            x: screenRect.minX,
            y: primaryTop - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    private func placeInitialWindow(settings: Settings) {
        let screens = NSScreen.screens
        let primaryTop = primaryScreenTopY()
        if let savedLeft = settings.left, let savedTop = settings.top {
            let point = NSPoint(x: savedLeft, y: savedTop)
            let visibleTopLefts = screens.map { topLeftRect(for: $0.frame) }
            if let containing = visibleTopLefts.first(where: { $0.contains(point) }) {
                let clampedX = max(containing.minX, min(point.x, containing.maxX - expandedWidth))
                let clampedY = max(containing.minY, min(point.y, containing.maxY - expandedHeight))
                setTopLeftBounds(origin: NSPoint(x: clampedX, y: clampedY), width: expandedWidth, height: expandedHeight)
                return
            }
        }

        let workArea = (NSScreen.main ?? screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let left = workArea.maxX - expandedWidth - 18
        let top = primaryTop - workArea.minY - expandedHeight - 18
        setTopLeftBounds(origin: NSPoint(x: left, y: top), width: expandedWidth, height: expandedHeight)
    }

    private func fitExpanded(desired: NSPoint) -> NSPoint {
        let activeScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = activeScreen?.visibleFrame else { return desired }
        let area = topLeftRect(for: visible)
        let clampedX = max(area.minX, min(desired.x, area.maxX - expandedWidth))
        let clampedY = max(area.minY, min(desired.y, area.maxY - expandedHeight))
        return NSPoint(x: clampedX, y: clampedY)
    }

    // MARK: - Refresh Loop

    private func startRefreshTimer() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.refresh(now: Date(), allowMotion: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refresh(now: Date, allowMotion: Bool) {
        let snapshot = PaySnapshot.at(settings: settings, now: now)
        let working = (snapshot.status == .working)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animate = allowMotion && working && !reduceMotion

        mascotView.showWork(working: working, animate: animate)
        if compactLayout { return }

        todayAmount.setAmount(snapshot.todayPay, animate: animate && !compactRequested)
        monthAmount.setAmount(snapshot.monthPay, animate: animate && !compactRequested)

        let breakText = snapshot.isOnBreak
            ? "放假中"
            : "距离放假还有 " + PaySnapshot.breakClock(remaining: snapshot.untilBreakSeconds)
        if breakCountdownLabel.stringValue != breakText {
            breakCountdownLabel.stringValue = breakText
        }

        let remainingText: String
        switch snapshot.status {
        case .working:
            remainingText = "距离下班还有  " + PaySnapshot.clock(seconds: Int64(ceil(snapshot.remainingSeconds)))
        case .beforeWork:
            remainingText = "未上班"
        case .afterWork:
            remainingText = "已下班"
        case .dayOff:
            remainingText = "今日休息"
        }
        if remainingLabel.stringValue != remainingText {
            remainingLabel.stringValue = remainingText
        }
    }
}

// MARK: - Custom Views for TimerWindow

private final class InteractiveCardView: NSView {
    enum ResizeEdge {
        case none
        case right
        case bottom
        case bottomRight
    }

    var isInteractive = true
    var onMouseDown: ((NSEvent, ResizeEdge) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var contextMenuBuilder: (() -> NSMenu?)?

    private var trackingAreaRef: NSTrackingArea?
    private var activeEdge: ResizeEdge = .none

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive else { return nil }
        return super.hitTest(point)
    }

    private func detectEdge(at localPoint: NSPoint) -> ResizeEdge {
        let cornerSize: CGFloat = 20
        let edgeThickness: CGFloat = 8
        let nearRight = localPoint.x >= bounds.width - cornerSize
        let nearBottom = localPoint.y >= bounds.height - cornerSize
        if nearRight && nearBottom {
            return .bottomRight
        }
        if localPoint.x >= bounds.width - edgeThickness && localPoint.y > 38 {
            return .right
        }
        if localPoint.y >= bounds.height - edgeThickness {
            return .bottom
        }
        return .none
    }

    private func updateCursor(for edge: ResizeEdge) {
        switch edge {
        case .right:
            NSCursor.resizeLeftRight.set()
        case .bottom:
            NSCursor.resizeUpDown.set()
        case .bottomRight:
            NSCursor.crosshair.set()
        case .none:
            NSCursor.arrow.set()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        let local = convert(event.locationInWindow, from: nil)
        activeEdge = detectEdge(at: local)
        updateCursor(for: activeEdge)
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        activeEdge = detectEdge(at: local)
        updateCursor(for: activeEdge)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        activeEdge = .none
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let edge = detectEdge(at: local)
        onMouseDown?(event, edge)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
        let local = convert(event.locationInWindow, from: nil)
        if bounds.contains(local) {
            updateCursor(for: detectEdge(at: local))
        } else {
            NSCursor.arrow.set()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return contextMenuBuilder?()
    }
}

private final class ResizeGripView: NSView {
    var gripColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setStrokeColor(gripColor.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)

        let w = bounds.width
        let h = bounds.height
        for offset in [CGFloat(4), CGFloat(8), CGFloat(12)] {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: w - offset, y: h - 2))
            ctx.addLine(to: CGPoint(x: w - 2, y: h - offset))
            ctx.strokePath()
        }
    }
}

private final class InteractiveCowView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var contextMenuBuilder: (() -> NSMenu?)?

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return contextMenuBuilder?()
    }
}

private final class CircleBadgeView: NSView {
    var fillColor: NSColor = .white {
        didSet { needsDisplay = true }
    }
    var strokeColor: NSColor = .gray {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        ctx.setFillColor(fillColor.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(strokeColor.cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokeEllipse(in: rect)
    }
}

private final class VectorToolButton: NSView {
    enum Kind {
        case pin
        case settings
        case close
    }

    private let kind: Kind
    private var isHovered = false
    private var isPressed = false
    private var trackingAreaRef: NSTrackingArea?

    var normalBackground: NSColor = NSColor.fromHex("#48FFFFFF") {
        didSet { needsDisplay = true }
    }
    var strokeColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
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
        addCursorRect(bounds, cursor: .pointingHand)
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
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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

        let bg: NSColor
        if isPressed {
            bg = NSColor.fromHex("#50A887C7")
        } else if isHovered {
            bg = NSColor.fromHex("#80FFFFFF")
        } else {
            bg = normalBackground
        }

        let buttonScale = bounds.width / 26.0
        let bgPath = CGPath(roundedRect: bounds, cornerWidth: 8 * buttonScale, cornerHeight: 8 * buttonScale, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(bg.cgColor)
        ctx.fillPath()

        ctx.saveGState()
        ctx.setStrokeColor(strokeColor.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch kind {
        case .pin:
            let iconBox = 14.0 * buttonScale
            let scale = iconBox / 20.0
            let ox = (bounds.width - 12.0 * scale) / 2.0 - 6.0 * scale
            let oy = (bounds.height - 20.0 * scale) / 2.0 - 2.0 * scale
            ctx.translateBy(x: ox, y: oy)
            ctx.scaleBy(x: scale, y: scale)
            ctx.setLineWidth(1.3 * buttonScale / scale)

            ctx.beginPath()
            ctx.move(to: CGPoint(x: 7, y: 2))
            ctx.addLine(to: CGPoint(x: 17, y: 2))
            ctx.addLine(to: CGPoint(x: 17, y: 5))
            ctx.addLine(to: CGPoint(x: 15, y: 7))
            ctx.addLine(to: CGPoint(x: 15, y: 11))
            ctx.addLine(to: CGPoint(x: 18, y: 15))
            ctx.addLine(to: CGPoint(x: 18, y: 16))
            ctx.addLine(to: CGPoint(x: 6, y: 16))
            ctx.addLine(to: CGPoint(x: 6, y: 15))
            ctx.addLine(to: CGPoint(x: 9, y: 11))
            ctx.addLine(to: CGPoint(x: 9, y: 7))
            ctx.addLine(to: CGPoint(x: 7, y: 5))
            ctx.closePath()
            ctx.move(to: CGPoint(x: 12, y: 16))
            ctx.addLine(to: CGPoint(x: 12, y: 22))
            ctx.strokePath()

        case .settings:
            let iconBox = 14.0 * buttonScale
            let scale = iconBox / 20.0
            let ox = (bounds.width - 20.0 * scale) / 2.0 - 2.0 * scale
            let oy = (bounds.height - 20.0 * scale) / 2.0 - 2.0 * scale
            ctx.translateBy(x: ox, y: oy)
            ctx.scaleBy(x: scale, y: scale)
            ctx.setLineWidth(1.3 * buttonScale / scale)

            ctx.beginPath()
            ctx.move(to: CGPoint(x: 9, y: 2))
            ctx.addLine(to: CGPoint(x: 15, y: 2))
            ctx.addLine(to: CGPoint(x: 16, y: 5))
            ctx.addLine(to: CGPoint(x: 19, y: 5))
            ctx.addLine(to: CGPoint(x: 22, y: 10))
            ctx.addLine(to: CGPoint(x: 20, y: 12))
            ctx.addLine(to: CGPoint(x: 22, y: 14))
            ctx.addLine(to: CGPoint(x: 19, y: 19))
            ctx.addLine(to: CGPoint(x: 16, y: 19))
            ctx.addLine(to: CGPoint(x: 15, y: 22))
            ctx.addLine(to: CGPoint(x: 9, y: 22))
            ctx.addLine(to: CGPoint(x: 8, y: 19))
            ctx.addLine(to: CGPoint(x: 5, y: 19))
            ctx.addLine(to: CGPoint(x: 2, y: 14))
            ctx.addLine(to: CGPoint(x: 4, y: 12))
            ctx.addLine(to: CGPoint(x: 2, y: 10))
            ctx.addLine(to: CGPoint(x: 5, y: 5))
            ctx.addLine(to: CGPoint(x: 8, y: 5))
            ctx.closePath()
            ctx.strokePath()
            ctx.strokeEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))

        case .close:
            let size = 9.0 * buttonScale
            let ox = (bounds.width - size) / 2.0
            let oy = (bounds.height - size) / 2.0
            ctx.setLineWidth(1.3 * buttonScale)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: ox, y: oy))
            ctx.addLine(to: CGPoint(x: ox + size, y: oy + size))
            ctx.move(to: CGPoint(x: ox + size, y: oy))
            ctx.addLine(to: CGPoint(x: ox, y: oy + size))
            ctx.strokePath()
        }

        ctx.restoreGState()
    }
}
