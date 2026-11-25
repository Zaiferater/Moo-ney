import AppKit

struct AppearancePreview {
    let mascotId: String
    let themeId: String
    let fontName: String
    let windowScale: Double
}

final class SetupWindow: NSWindow, NSWindowDelegate {
    private static let fixedWidth: CGFloat = 398

    private let onSubmit: (Settings) -> Void
    private let onPreview: ((AppearancePreview) -> Void)?
    private let onClose: () -> Void

    private var workdayOverrides: [CalendarDay]
    private var currentTheme: AppTheme
    private var fontChoices: [FontChoice] = []

    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let headingLabel = NSTextField(labelWithString: AppConstants.title)
    private var fieldLabels: [NSTextField] = []
    private var separatorColons: [NSTextField] = []

    private let weekdaysRadio = NSButton(radioButtonWithTitle: "周一至周五", target: nil, action: nil)
    private let customWorkdaysRadio = NSButton(radioButtonWithTitle: "自定义工作日", target: nil, action: nil)
    private var editCalendarButton: ThemedButton!

    private let payContainer = NSView()
    private let payInput = NSTextField()

    private let startHourPopup = NSPopUpButton()
    private let startMinutePopup = NSPopUpButton()
    private let endHourPopup = NSPopUpButton()
    private let endMinutePopup = NSPopUpButton()

    private let mascotPopup = NSPopUpButton()
    private let themePopup = NSPopUpButton()
    private let previewFrame = NSView()
    private var mascotPreview: MascotView!

    private let fontPopup = NSPopUpButton()
    private let scaleSlider = NSSlider()
    private let scaleValueLabel = NSTextField(labelWithString: "100%")
    private var resetScaleButton: ThemedButton!

    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    private var submitButton: ThemedButton!
    private var footerStartY: CGFloat = 0
    private var previewTimer: Timer?
    private var calendarSheet: WorkdayCalendarWindow?

    init(
        settings: Settings?,
        loadError: String?,
        onSubmit: @escaping (Settings) -> Void,
        onPreview: ((AppearancePreview) -> Void)?,
        onClose: @escaping () -> Void
    ) {
        self.onSubmit = onSubmit
        self.onPreview = onPreview
        self.onClose = onClose
        self.workdayOverrides = settings?.workdayOverrides ?? []
        let initialMascotId = MascotChoice.resolve(settings?.mascotId).id
        let initialTheme = AppTheme.resolve(settings?.themeId)
        let initialFontName = settings?.fontName ?? Settings.defaultFontName
        let initialScale = Settings.clampScale(settings?.windowScale ?? Settings.defaultWindowScale)
        self.currentTheme = initialTheme

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.fixedWidth, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = AppConstants.title
        isReleasedWhenClosed = false
        delegate = self
        minSize = NSSize(width: Self.fixedWidth, height: 360)
        maxSize = NSSize(width: Self.fixedWidth, height: 960)

        buildUI(
            settings: settings,
            loadError: loadError,
            initialMascotId: initialMascotId,
            initialThemeId: initialTheme.id,
            initialFontName: initialFontName,
            initialScale: initialScale
        )
        applyAppearance(
            mascotId: initialMascotId,
            themeId: initialTheme.id,
            fontName: initialFontName
        )
        center()
        startPreviewTimer()
    }

    deinit {
        previewTimer?.invalidate()
    }

    func focusPayField() {
        makeFirstResponder(payInput)
        payInput.selectText(nil)
    }

    func showSaveError() {
        showError("保存设置失败，请确认当前用户有权限写入本地应用数据。", focus: nil)
    }

    func windowWillClose(_ notification: Notification) {
        previewTimer?.invalidate()
        previewTimer = nil
        onClose()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            applyAndSubmit()
            return
        }
        super.keyDown(with: event)
    }

    private func buildUI(
        settings: Settings?,
        loadError: String?,
        initialMascotId: String,
        initialThemeId: String,
        initialFontName: String,
        initialScale: Double
    ) {
        let width = Self.fixedWidth
        let marginX: CGFloat = 24
        let contentWidth = width - marginX * 2

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        documentView.wantsLayer = true
        scrollView.documentView = documentView
        contentView = scrollView

        var y: CGFloat = 20

        headingLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        headingLabel.frame = NSRect(x: marginX, y: y, width: contentWidth, height: 34)
        documentView.addSubview(headingLabel)
        y += 44

        // 1. 计薪日期
        addFieldLabel("计薪日期", at: &y, x: marginX, width: contentWidth)
        let useCustom = settings?.useCustomWorkdays ?? false
        weekdaysRadio.target = self
        weekdaysRadio.action = #selector(workdayModeChanged(_:))
        weekdaysRadio.state = useCustom ? .off : .on
        weekdaysRadio.font = NSFont.systemFont(ofSize: 13)
        weekdaysRadio.frame = NSRect(x: marginX, y: y + 4, width: 100, height: 22)
        documentView.addSubview(weekdaysRadio)

        customWorkdaysRadio.target = self
        customWorkdaysRadio.action = #selector(workdayModeChanged(_:))
        customWorkdaysRadio.state = useCustom ? .on : .off
        customWorkdaysRadio.font = NSFont.systemFont(ofSize: 13)
        customWorkdaysRadio.frame = NSRect(x: marginX + 104, y: y + 4, width: 112, height: 22)
        documentView.addSubview(customWorkdaysRadio)

        editCalendarButton = ThemedButton(
            title: "编辑日历…",
            fillColor: currentTheme.fieldBackground,
            borderColor: currentTheme.fieldBorder,
            textColor: currentTheme.text,
            font: NSFont.systemFont(ofSize: 13),
            frame: NSRect(x: marginX + 220, y: y, width: 88, height: 29)
        )
        editCalendarButton.isHidden = !useCustom
        editCalendarButton.onClick = { [weak self] in self?.openCalendarSheet() }
        documentView.addSubview(editCalendarButton)
        y += 40

        // 2. 月薪（元）
        addFieldLabel("月薪（元）", at: &y, x: marginX, width: contentWidth)
        payContainer.wantsLayer = true
        payContainer.layer?.cornerRadius = 5
        payContainer.layer?.borderWidth = 1
        payContainer.frame = NSRect(x: marginX, y: y, width: contentWidth, height: 32)

        payInput.stringValue = settings.map { Settings.formatMonthlyPayInput($0.monthlyPay) } ?? ""
        payInput.isBordered = false
        payInput.drawsBackground = false
        payInput.focusRingType = .none
        payInput.font = NSFont.systemFont(ofSize: 13)
        payInput.placeholderString = "例如 15000"
        payInput.target = self
        payInput.action = #selector(submitFromField(_:))
        payInput.frame = NSRect(x: 8, y: 7, width: contentWidth - 16, height: 18)
        payContainer.addSubview(payInput)
        documentView.addSubview(payContainer)
        y += 42

        // 3. 上班时间
        let startMins = settings?.startMinutes ?? (9 * 60)
        addFieldLabel("上班时间", at: &y, x: marginX, width: contentWidth)
        buildTimeRow(hourPopup: startHourPopup, minutePopup: startMinutePopup, totalMinutes: startMins, x: marginX, y: y)
        y += 40

        // 4. 下班时间
        let endMins = settings?.endMinutes ?? (18 * 60)
        addFieldLabel("下班时间", at: &y, x: marginX, width: contentWidth)
        buildTimeRow(hourPopup: endHourPopup, minutePopup: endMinutePopup, totalMinutes: endMins, x: marginX, y: y)
        y += 42

        // 5. 形象 & 主题色 + circular preview
        let pickerWidth = contentWidth - 98
        let appearanceTop = y

        addFieldLabel("形象", at: &y, x: marginX, width: pickerWidth)
        configureMascotPopup(selectedId: initialMascotId)
        mascotPopup.frame = NSRect(x: marginX, y: y, width: pickerWidth, height: 32)
        documentView.addSubview(mascotPopup)
        y += 42

        addFieldLabel("主题色", at: &y, x: marginX, width: pickerWidth)
        configureThemePopup(selectedId: initialThemeId)
        themePopup.frame = NSRect(x: marginX, y: y, width: pickerWidth, height: 32)
        documentView.addSubview(themePopup)
        y += 42

        previewFrame.wantsLayer = true
        previewFrame.layer?.cornerRadius = 41.5
        previewFrame.layer?.borderWidth = 1
        let previewY = appearanceTop + ((y - appearanceTop - 8) - 83) / 2.0
        previewFrame.frame = NSRect(x: marginX + pickerWidth + 15, y: previewY, width: 83, height: 83)
        mascotPreview = MascotView(id: initialMascotId, size: 66)
        mascotPreview.frame = NSRect(x: 8.5, y: 8.5, width: 66, height: 66)
        previewFrame.addSubview(mascotPreview)
        documentView.addSubview(previewFrame)

        // 6. 字体
        addFieldLabel("字体", at: &y, x: marginX, width: contentWidth)
        configureFontPopup(selectedFamily: initialFontName)
        fontPopup.frame = NSRect(x: marginX, y: y, width: contentWidth, height: 30)
        documentView.addSubview(fontPopup)
        y += 42

        // 7. 悬浮窗大小
        addFieldLabel("悬浮窗大小（也可直接拖动悬浮窗右下角调整）", at: &y, x: marginX, width: contentWidth)
        scaleSlider.minValue = Settings.minWindowScale
        scaleSlider.maxValue = Settings.maxWindowScale
        scaleSlider.doubleValue = initialScale
        scaleSlider.isContinuous = true
        scaleSlider.target = self
        scaleSlider.action = #selector(scaleSliderChanged(_:))
        scaleSlider.frame = NSRect(x: marginX, y: y + 4, width: contentWidth - 114, height: 22)
        documentView.addSubview(scaleSlider)

        scaleValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        scaleValueLabel.alignment = .right
        scaleValueLabel.stringValue = formatScalePercent(initialScale)
        scaleValueLabel.frame = NSRect(x: marginX + contentWidth - 110, y: y + 5, width: 48, height: 18)
        documentView.addSubview(scaleValueLabel)

        resetScaleButton = ThemedButton(
            title: "重置",
            fillColor: currentTheme.fieldBackground,
            borderColor: currentTheme.fieldBorder,
            textColor: currentTheme.text,
            font: NSFont.systemFont(ofSize: 12.5),
            frame: NSRect(x: marginX + contentWidth - 54, y: y + 1, width: 54, height: 26)
        )
        resetScaleButton.onClick = { [weak self] in self?.resetScaleToDefault() }
        documentView.addSubview(resetScaleButton)
        y += 40

        footerStartY = y

        // Feedback label
        feedbackLabel.font = NSFont.systemFont(ofSize: 12.5)
        feedbackLabel.stringValue = loadError ?? ""
        feedbackLabel.isHidden = (loadError == nil)
        feedbackLabel.frame = NSRect(x: marginX, y: footerStartY, width: contentWidth, height: 20)
        documentView.addSubview(feedbackLabel)

        // Submit button
        submitButton = ThemedButton(
            title: settings == nil ? "打开计时器" : "保存设置",
            fillColor: currentTheme.action,
            borderColor: currentTheme.action,
            textColor: currentTheme.actionText,
            font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
            frame: NSRect(x: marginX, y: footerStartY, width: contentWidth, height: 38)
        )
        submitButton.cornerRadius = 6
        submitButton.onClick = { [weak self] in self?.applyAndSubmit() }
        documentView.addSubview(submitButton)

        relayoutDocument(resizeWindow: true)
    }

    private func addFieldLabel(_ text: String, at y: inout CGFloat, x: CGFloat, width: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.frame = NSRect(x: x, y: y, width: width, height: 18)
        documentView.addSubview(label)
        fieldLabels.append(label)
        y += 22
    }

    private func buildTimeRow(
        hourPopup: NSPopUpButton,
        minutePopup: NSPopUpButton,
        totalMinutes: Int,
        x: CGFloat,
        y: CGFloat
    ) {
        configureNumberPopup(hourPopup, count: 24, selected: max(0, min(23, totalMinutes / 60)))
        hourPopup.frame = NSRect(x: x, y: y, width: 76, height: 30)
        documentView.addSubview(hourPopup)

        let colon = NSTextField(labelWithString: ":")
        colon.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        colon.alignment = .center
        colon.frame = NSRect(x: x + 78, y: y + 5, width: 16, height: 20)
        documentView.addSubview(colon)
        separatorColons.append(colon)

        configureNumberPopup(minutePopup, count: 60, selected: max(0, min(59, totalMinutes % 60)))
        minutePopup.frame = NSRect(x: x + 96, y: y, width: 76, height: 30)
        documentView.addSubview(minutePopup)
    }

    private func configureNumberPopup(_ popup: NSPopUpButton, count: Int, selected: Int) {
        popup.removeAllItems()
        for value in 0..<count {
            popup.addItem(withTitle: String(format: "%02d", value))
        }
        popup.selectItem(at: selected)
        popup.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    }

    private func configureMascotPopup(selectedId: String) {
        mascotPopup.removeAllItems()
        for choice in MascotChoice.choices {
            let item = NSMenuItem(title: choice.name, action: nil, keyEquivalent: "")
            item.representedObject = choice.id
            item.image = MascotView.previewImage(id: choice.id, size: 22)
            mascotPopup.menu?.addItem(item)
        }
        if let idx = MascotChoice.choices.firstIndex(where: { $0.id == selectedId }) {
            mascotPopup.selectItem(at: idx)
        }
        mascotPopup.target = self
        mascotPopup.action = #selector(appearanceSelectionChanged(_:))
    }

    private func configureThemePopup(selectedId: String) {
        themePopup.removeAllItems()
        for choice in AppTheme.choices {
            let item = NSMenuItem(title: choice.name, action: nil, keyEquivalent: "")
            item.representedObject = choice.id
            item.image = makeSwatchImage(fill: choice.timerBackground, border: choice.fieldBorder)
            themePopup.menu?.addItem(item)
        }
        if let idx = AppTheme.choices.firstIndex(where: { $0.id == selectedId }) {
            themePopup.selectItem(at: idx)
        }
        themePopup.target = self
        themePopup.action = #selector(appearanceSelectionChanged(_:))
    }

    private func configureFontPopup(selectedFamily: String) {
        fontChoices = FontChoice.availableChoices()
        fontPopup.removeAllItems()

        for (index, choice) in fontChoices.enumerated() {
            if index == 1 {
                fontPopup.menu?.addItem(.separator())
            }
            let item = NSMenuItem(title: choice.displayName, action: nil, keyEquivalent: "")
            item.representedObject = choice.familyName
            let previewFont = FontChoice.uiFont(familyName: choice.familyName, size: 13)
            item.attributedTitle = NSAttributedString(string: choice.displayName, attributes: [.font: previewFont])
            fontPopup.menu?.addItem(item)
        }

        if let menu = fontPopup.menu,
           let match = menu.items.first(where: { ($0.representedObject as? String) == selectedFamily }) {
            fontPopup.select(match)
        } else {
            fontPopup.selectItem(at: 0)
        }
        fontPopup.target = self
        fontPopup.action = #selector(appearanceSelectionChanged(_:))
    }

    private func makeSwatchImage(fill: NSColor, border: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: inset, xRadius: 4, yRadius: 4)
            fill.setFill()
            path.fill()
            border.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }

    private func relayoutDocument(resizeWindow: Bool) {
        let marginX: CGFloat = 24
        let contentWidth = Self.fixedWidth - marginX * 2
        var buttonY = footerStartY

        if !feedbackLabel.isHidden && !feedbackLabel.stringValue.isEmpty {
            let textHeight = ceil((feedbackLabel.stringValue as NSString).boundingRect(
                with: NSSize(width: contentWidth, height: 120),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: feedbackLabel.font ?? NSFont.systemFont(ofSize: 12.5)]
            ).height) + 4
            feedbackLabel.frame = NSRect(x: marginX, y: footerStartY, width: contentWidth, height: textHeight)
            buttonY = footerStartY + textHeight + 10
        }

        submitButton.frame = NSRect(x: marginX, y: buttonY, width: contentWidth, height: 38)
        let totalHeight = buttonY + 38 + 24
        documentView.frame = NSRect(x: 0, y: 0, width: Self.fixedWidth, height: totalHeight)

        if resizeWindow {
            let screenHeight = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 760
            let maxInitialHeight = max(420, screenHeight - 90)
            let windowContentHeight = min(totalHeight, maxInitialHeight)
            setContentSize(NSSize(width: Self.fixedWidth, height: windowContentHeight))
            documentView.scroll(NSPoint(x: 0, y: 0))
        }
    }

    private func applyAppearance(mascotId: String, themeId: String, fontName: String) {
        let theme = AppTheme.resolve(themeId)
        currentTheme = theme

        appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        backgroundColor = theme.settingsBackground
        documentView.layer?.backgroundColor = theme.settingsBackground.cgColor

        headingLabel.textColor = theme.text
        headingLabel.font = FontChoice.uiFont(familyName: fontName, size: 24, weight: .semibold)
        for label in fieldLabels { label.textColor = theme.text }
        for colon in separatorColons { colon.textColor = theme.text }
        scaleValueLabel.textColor = theme.text

        let radioAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: theme.text
        ]
        weekdaysRadio.attributedTitle = NSAttributedString(string: "周一至周五", attributes: radioAttrs)
        customWorkdaysRadio.attributedTitle = NSAttributedString(string: "自定义工作日", attributes: radioAttrs)

        editCalendarButton.fillColor = theme.fieldBackground
        editCalendarButton.borderColor = theme.fieldBorder
        editCalendarButton.textColor = theme.text

        resetScaleButton.fillColor = theme.fieldBackground
        resetScaleButton.borderColor = theme.fieldBorder
        resetScaleButton.textColor = theme.text

        payContainer.layer?.backgroundColor = theme.fieldBackground.cgColor
        payContainer.layer?.borderColor = theme.fieldBorder.cgColor
        payInput.textColor = theme.text

        previewFrame.layer?.backgroundColor = theme.fieldBackground.cgColor
        previewFrame.layer?.borderColor = theme.fieldBorder.cgColor

        feedbackLabel.textColor = theme.error

        submitButton.fillColor = theme.action
        submitButton.borderColor = theme.action
        submitButton.textColor = theme.actionText

        mascotPreview.select(mascotId)
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        mascotPreview.showWork(working: true, animate: animate)
    }

    private func startPreviewTimer() {
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self else { return }
            let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            self.mascotPreview.showWork(working: true, animate: animate)
        }
        RunLoop.main.add(timer, forMode: .common)
        previewTimer = timer
    }

    private func selectedMascotId() -> String {
        return (mascotPopup.selectedItem?.representedObject as? String) ?? MascotChoice.defaultId
    }

    private func selectedThemeId() -> String {
        return (themePopup.selectedItem?.representedObject as? String) ?? AppTheme.defaultId
    }

    private func selectedFontName() -> String {
        return (fontPopup.selectedItem?.representedObject as? String) ?? Settings.defaultFontName
    }

    private func selectedWindowScale() -> Double {
        return Settings.clampScale(scaleSlider.doubleValue)
    }

    private func formatScalePercent(_ scale: Double) -> String {
        return "\(Int((scale * 100.0).rounded()))%"
    }

    private func emitPreview() {
        let preview = AppearancePreview(
            mascotId: selectedMascotId(),
            themeId: selectedThemeId(),
            fontName: selectedFontName(),
            windowScale: selectedWindowScale()
        )
        onPreview?(preview)
    }

    @objc private func workdayModeChanged(_ sender: NSButton) {
        let useCustom = (sender == customWorkdaysRadio)
        weekdaysRadio.state = useCustom ? .off : .on
        customWorkdaysRadio.state = useCustom ? .on : .off
        editCalendarButton.isHidden = !useCustom
    }

    @objc private func appearanceSelectionChanged(_ sender: Any?) {
        applyAppearance(
            mascotId: selectedMascotId(),
            themeId: selectedThemeId(),
            fontName: selectedFontName()
        )
        emitPreview()
    }

    @objc private func scaleSliderChanged(_ sender: NSSlider) {
        let scale = selectedWindowScale()
        scaleValueLabel.stringValue = formatScalePercent(scale)
        emitPreview()
    }

    private func resetScaleToDefault() {
        scaleSlider.doubleValue = Settings.defaultWindowScale
        scaleValueLabel.stringValue = formatScalePercent(Settings.defaultWindowScale)
        emitPreview()
    }

    @objc private func submitFromField(_ sender: Any?) {
        applyAndSubmit()
    }

    private func openCalendarSheet() {
        let sheet = WorkdayCalendarWindow(
            overrides: workdayOverrides,
            theme: AppTheme.resolve(selectedThemeId()),
            today: CalendarDay.today()
        ) { [weak self] updated in
            guard let self else { return }
            self.calendarSheet = nil
            if let updated {
                self.workdayOverrides = updated
            }
        }
        calendarSheet = sheet
        beginSheet(sheet, completionHandler: nil)
    }

    private func applyAndSubmit() {
        guard let pay = Settings.parseMonthlyPay(payInput.stringValue) else {
            showError("请输入 0 至 99999999.99 元的月薪，最多两位小数。", focus: payInput)
            payInput.selectText(nil)
            return
        }
        let start = startHourPopup.indexOfSelectedItem * 60 + startMinutePopup.indexOfSelectedItem
        let end = endHourPopup.indexOfSelectedItem * 60 + endMinutePopup.indexOfSelectedItem
        if end <= start {
            showError("下班时间须晚于当天的上班时间。", focus: endHourPopup)
            return
        }

        let next = Settings(
            monthlyPay: pay,
            startMinutes: start,
            endMinutes: end,
            mascotId: MascotChoice.resolve(selectedMascotId()).id,
            themeId: AppTheme.resolve(selectedThemeId()).id,
            windowScale: selectedWindowScale(),
            fontName: selectedFontName(),
            useCustomWorkdays: customWorkdaysRadio.state == .on,
            workdayOverrides: workdayOverrides
        )
        onSubmit(next)
    }

    private func showError(_ message: String, focus: NSView?) {
        feedbackLabel.stringValue = message
        feedbackLabel.isHidden = false
        relayoutDocument(resizeWindow: false)
        documentView.scrollToVisible(feedbackLabel.frame.union(submitButton.frame))
        if let focus {
            makeFirstResponder(focus)
        }
    }
}
