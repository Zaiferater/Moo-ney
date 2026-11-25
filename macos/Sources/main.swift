import AppKit

enum AppConstants {
    static let title = "牛马打气机"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.zaiferater.mooney"
    static let activateNotification = Notification.Name("com.zaiferater.mooney.activate")
}

final class TimerApplicationController: NSObject, NSApplicationDelegate {
    private let store: SettingsStore
    private var settings: Settings?
    private var loadError: String?
    private var setupWindow: SetupWindow?
    private var timerWindow: TimerWindow?

    private var statusItem: NSStatusItem?
    private var statusShowItem: NSMenuItem?
    private var statusToggleCompactItem: NSMenuItem?
    private var statusPinItem: NSMenuItem?

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        super.init()
        do {
            let (loaded, recovered) = try store.load()
            settings = loaded
            if recovered {
                loadError = "已从备份恢复上一次可用的设置。"
            }
        } catch {
            loadError = "读取设置失败，请重新填写后打开计时器。"
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalActivation),
            name: AppConstants.activateNotification,
            object: nil
        )

        if settings == nil {
            showSettings()
        } else {
            showTimer()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        timerWindow?.stopTimers()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showRunningWindow()
        return true
    }

    @objc private func handleExternalActivation() {
        DispatchQueue.main.async { [weak self] in
            self?.showRunningWindow()
        }
    }

    func showRunningWindow() {
        if let setupWindow {
            NSApp.activate(ignoringOtherApps: true)
            setupWindow.deminiaturize(nil)
            setupWindow.makeKeyAndOrderFront(nil)
            return
        }
        if let timerWindow {
            timerWindow.orderFrontRegardless()
            timerWindow.makeKey()
        } else {
            showSettings()
        }
    }

    func showSettings() {
        if setupWindow == nil {
            let window = SetupWindow(
                settings: settings,
                loadError: loadError,
                onSubmit: { [weak self] next in self?.openTimer(next) },
                onPreview: { [weak self] preview in
                    self?.timerWindow?.setAppearance(
                        mascotId: preview.mascotId,
                        themeId: preview.themeId,
                        fontName: preview.fontName,
                        windowScale: preview.windowScale
                    )
                },
                onClose: { [weak self] in
                    guard let self else { return }
                    self.setupWindow = nil
                    if self.timerWindow == nil {
                        NSApp.terminate(nil)
                    } else if let current = self.settings {
                        self.timerWindow?.setAppearance(
                            mascotId: current.mascotId,
                            themeId: current.themeId,
                            fontName: current.fontName,
                            windowScale: current.windowScale
                        )
                    }
                    self.syncStatusMenu()
                }
            )
            setupWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.deminiaturize(nil)
        setupWindow?.makeKeyAndOrderFront(nil)
        setupWindow?.focusPayField()
        syncStatusMenu()
    }

    private func openTimer(_ nextInput: Settings) {
        var next = nextInput
        if let existing = settings {
            next.alwaysOnTop = existing.alwaysOnTop
        }
        applyCurrentPosition(to: &next)
        do {
            try store.save(next)
        } catch {
            setupWindow?.showSaveError()
            return
        }
        settings = next
        loadError = nil

        if timerWindow == nil {
            showTimer()
        } else {
            timerWindow?.updateSettings(next)
        }
        setupWindow?.close()
        syncStatusMenu()
    }

    private func showTimer() {
        guard let settings else { return }
        let window = TimerWindow(
            settings: settings,
            onShowSettings: { [weak self] in self?.showSettings() },
            onSaveLayout: { [weak self] left, top, scale in self?.saveLayout(left: left, top: top, scale: scale) },
            onChangeTopmost: { [weak self] enabled in self?.changeTopmost(enabled) },
            onExit: { NSApp.terminate(nil) },
            onStateChanged: { [weak self] in self?.syncStatusMenu() }
        )
        timerWindow = window
        window.orderFrontRegardless()
        syncStatusMenu()
    }

    private func applyCurrentPosition(to next: inout Settings) {
        if let timerWindow {
            let pos = timerWindow.expandedPosition
            next.left = Double(pos.x)
            next.top = Double(pos.y)
        } else if let existing = settings {
            next.left = existing.left
            next.top = existing.top
        }
    }

    private func saveLayout(left: Double, top: Double, scale: Double) {
        guard var next = settings else { return }
        let clampedScale = Settings.clampScale(scale)
        next.left = left
        next.top = top
        next.windowScale = clampedScale
        if trySave(next, errorMessage: "无法保存悬浮窗位置或大小。") {
            settings?.left = left
            settings?.top = top
            settings?.windowScale = clampedScale
        }
    }

    private func changeTopmost(_ enabled: Bool) {
        guard var next = settings else { return }
        next.alwaysOnTop = enabled
        applyCurrentPosition(to: &next)
        if trySave(next, errorMessage: "无法保存置顶选项，请检查设置文件是否可写。") {
            settings = next
            timerWindow?.updateSettings(next)
            syncStatusMenu()
        }
    }

    private func trySave(_ next: Settings, errorMessage: String) -> Bool {
        do {
            try store.save(next)
            return true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = AppConstants.title
            alert.informativeText = errorMessage
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return false
        }
    }

    // MARK: - Menu Bar & Edit Shortcuts

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = MenuBarIcon.makeImage()
            button.toolTip = AppConstants.title
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "显示悬浮窗", action: #selector(menuShowWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        statusShowItem = showItem

        let toggleCompactItem = NSMenuItem(title: "收起悬浮窗", action: #selector(menuToggleCompact), keyEquivalent: "")
        toggleCompactItem.target = self
        menu.addItem(toggleCompactItem)
        statusToggleCompactItem = toggleCompactItem

        let pinItem = NSMenuItem(title: "始终置顶", action: #selector(menuTogglePin), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)
        statusPinItem = pinItem

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出\(AppConstants.title)", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        syncStatusMenu()
    }

    private func syncStatusMenu() {
        let hasTimer = (timerWindow != nil)
        statusToggleCompactItem?.isHidden = !hasTimer
        if let timerWindow {
            statusToggleCompactItem?.title = timerWindow.isCompact ? "展开悬浮窗" : "收起悬浮窗"
        }
        statusPinItem?.isHidden = !hasTimer
        statusPinItem?.state = (settings?.alwaysOnTop ?? true) ? .on : .off
    }

    @objc private func menuShowWindow() { showRunningWindow() }
    @objc private func menuToggleCompact() { timerWindow?.toggleCompactFromMenu() }
    @objc private func menuTogglePin() { changeTopmost(!(settings?.alwaysOnTop ?? true)) }
    @objc private func menuOpenSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    /// Enables standard Cmd+A/C/V/X/Z/W/Q keyboard shortcuts in text inputs and windows.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: AppConstants.title)
        appMenu.addItem(withTitle: "退出\(AppConstants.title)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

// MARK: - Single-Instance Guard & Entry Point

private func activateExistingInstanceIfNeeded() -> Bool {
    guard let bundleId = Bundle.main.bundleIdentifier else { return false }
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
    if !others.isEmpty {
        DistributedNotificationCenter.default().postNotificationName(
            AppConstants.activateNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
    return false
}

if activateExistingInstanceIfNeeded() {
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = TimerApplicationController()
app.delegate = controller
app.run()
