import AppKit

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private let onEditClipboardImage: () -> Void
    private let onOpenImage: () -> Void
    private let onMergeImages: () -> Void
    private let onOpenHistoryPanel: () -> Void
    private let onOpenSettings: () -> Void
    private let caffeinationController = CaffeinationController.shared
    private var caffeinationMenu: NSMenu?
    private var caffeinationItem: NSMenuItem?
    private var activeCaffeinationMenuItem: NSMenuItem?
    private var activeCaffeinationBaseTitle = ""
    private var activeCaffeinationIsUntil = false
    private var caffeinationCountdownTimer: Timer?

    init(
        onEditClipboardImage: @escaping () -> Void,
        onOpenImage: @escaping () -> Void,
        onMergeImages: @escaping () -> Void,
        onOpenHistoryPanel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onEditClipboardImage = onEditClipboardImage
        self.onOpenImage = onOpenImage
        self.onMergeImages = onMergeImages
        self.onOpenHistoryPanel = onOpenHistoryPanel
        self.onOpenSettings = onOpenSettings

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true

        super.init()

        if let button = statusItem.button {
            button.image = Self.statusBarIcon()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        setupMenu()

        NotificationCenter.default.addObserver(forName: .languageDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
        }
        NotificationCenter.default.addObserver(forName: .historyCacheEnabledDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
        }
        NotificationCenter.default.addObserver(forName: .clipboardTextCacheEnabledDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
        }
        NotificationCenter.default.addObserver(forName: .hotkeyDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
        }
        NotificationCenter.default.addObserver(forName: .updateStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
            self?.syncUpdateProgressHUD()
        }
        NotificationCenter.default.addObserver(forName: .caffeinationStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refreshCaffeinationItemState()
        }
    }

    private func setupMenu() {
        stopCaffeinationCountdown()
        let menu = NSMenu()

        let clipboardItem = NSMenuItem(title: L10n.editClipboardImage, action: #selector(editClipboardImage), keyEquivalent: "")
        clipboardItem.target = self
        clipboardItem.image = Self.menuIcon(systemName: "doc.on.clipboard")
        HotkeyManager.applyClipboardImageEditToMenuItem(clipboardItem)
        menu.addItem(clipboardItem)

        let openImageItem = NSMenuItem(title: L10n.openImage, action: #selector(openImage), keyEquivalent: "")
        openImageItem.target = self
        openImageItem.image = Self.menuIcon(systemName: "folder")
        menu.addItem(openImageItem)

        let mergeItem = NSMenuItem(title: L10n.mergeImages, action: #selector(mergeImages), keyEquivalent: "")
        mergeItem.target = self
        mergeItem.image = Self.menuIcon(systemName: "square.grid.2x2")
        HotkeyManager.applyImageMergeToMenuItem(mergeItem)
        menu.addItem(mergeItem)

        let caffeinationItem = NSMenuItem(title: L10n.caffeinateMenu, action: nil, keyEquivalent: "")
        let caffeinationMenu = NSMenu(title: L10n.caffeinateMenu)
        caffeinationMenu.delegate = self
        caffeinationItem.submenu = caffeinationMenu
        self.caffeinationItem = caffeinationItem
        self.caffeinationMenu = caffeinationMenu
        menu.addItem(caffeinationItem)
        refreshCaffeinationItemState(rebuildSubmenu: false)

        menu.addItem(NSMenuItem.separator())

        if Defaults.isHistoryCacheAvailable {
            let historyPanelItem = NSMenuItem(title: L10n.historyPanelMenu, action: #selector(openHistoryPanel), keyEquivalent: "")
            historyPanelItem.target = self
            historyPanelItem.image = Self.menuIcon(systemName: "rectangle.stack")
            HotkeyManager.applyHistoryPanelToMenuItem(historyPanelItem)
            menu.addItem(historyPanelItem)

            menu.addItem(NSMenuItem.separator())
        }

        let settingsItem = NSMenuItem(title: L10n.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = Self.menuIcon(systemName: "gearshape")
        menu.addItem(settingsItem)

        menu.addItem(makeUpdateMenuItem())

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quitApp, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = Self.menuIcon(systemName: "power")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    fileprivate static func menuIcon(systemName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    private static func statusBarIcon() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = size
            image.isTemplate = true
            return image
        }

        let image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "clipcap")
            ?? NSImage(size: size)
        image.size = size
        image.isTemplate = true
        return image
    }

    private func refreshCaffeinationItemState(rebuildSubmenu: Bool = true) {
        let symbolName = caffeinationController.isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        caffeinationItem?.image = Self.menuIcon(systemName: symbolName)
        if rebuildSubmenu, let caffeinationMenu {
            rebuildCaffeinationMenu(caffeinationMenu)
        }
    }

    @objc private func editClipboardImage() {
        onEditClipboardImage()
    }

    @objc private func openImage() {
        onOpenImage()
    }

    @objc private func mergeImages() {
        onMergeImages()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openHistoryPanel() {
        onOpenHistoryPanel()
    }

    @objc private func decaffeinate() {
        caffeinationController.stop()
    }

    @objc private func toggleIndefiniteCaffeination() {
        if caffeinationController.isIndefinite {
            caffeinationController.stop()
            return
        }
        guard caffeinationController.startIndefinitely() else {
            ToastWindow.show(message: L10n.caffeinateFailed)
            return
        }
    }

    @objc private func caffeinationPresetClicked(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? CaffeinationPreset else { return }
        if caffeinationController.activePreset == preset {
            caffeinationController.stop()
            return
        }
        guard caffeinationController.start(preset: preset) else {
            ToastWindow.show(message: L10n.caffeinateFailed)
            return
        }
    }

    @objc private func caffeinateUntilClicked() {
        if let session = caffeinationController.activeSession,
           session.endDate != nil,
           session.preset == nil {
            caffeinationController.stop()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.presentCaffeinateUntilPicker()
        }
    }

    private func presentCaffeinateUntilPicker() {
        let now = Date()
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.locale = Locale(identifier: L10n.lang.lprojName)
        picker.minDate = now.addingTimeInterval(60)
        picker.dateValue = now.addingTimeInterval(60 * 60)

        let alert = NSAlert()
        alert.messageText = L10n.caffeinateUntilTitle
        alert.informativeText = L10n.caffeinateUntilHint
        alert.accessoryView = picker
        alert.addButton(withTitle: L10n.caffeinateStart)
        alert.addButton(withTitle: L10n.caffeinateCancel)
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard picker.dateValue.timeIntervalSinceNow > 0 else {
            ToastWindow.show(message: L10n.caffeinateFutureTimeRequired)
            return
        }
        guard caffeinationController.start(until: picker.dateValue) else {
            ToastWindow.show(message: L10n.caffeinateFailed)
            return
        }
    }

    private func rebuildCaffeinationMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        activeCaffeinationMenuItem = nil
        activeCaffeinationBaseTitle = ""
        activeCaffeinationIsUntil = false

        if caffeinationController.isActive {
            let stopItem = NSMenuItem(title: L10n.decaffeinate, action: #selector(decaffeinate), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
            menu.addItem(NSMenuItem.separator())
        }

        menu.addItem(NSMenuItem.sectionHeader(title: L10n.caffeinateMenu))

        let indefinite = NSMenuItem(
            title: L10n.caffeinateIndefinitely,
            action: #selector(toggleIndefiniteCaffeination),
            keyEquivalent: ""
        )
        indefinite.target = self
        indefinite.state = caffeinationController.isIndefinite ? .on : .off
        menu.addItem(indefinite)

        for preset in CaffeinationPreset.allCases {
            let title = caffeinationTitle(for: preset)
            let item = NSMenuItem(title: title, action: #selector(caffeinationPresetClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            if caffeinationController.activePreset == preset {
                item.state = .on
                activeCaffeinationMenuItem = item
                activeCaffeinationBaseTitle = title
            }
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let untilItem = NSMenuItem(title: L10n.caffeinateUntil, action: #selector(caffeinateUntilClicked), keyEquivalent: "")
        untilItem.target = self
        if let session = caffeinationController.activeSession,
           session.endDate != nil,
           session.preset == nil {
            untilItem.state = .on
            activeCaffeinationMenuItem = untilItem
            activeCaffeinationBaseTitle = L10n.caffeinateUntil
            activeCaffeinationIsUntil = true
        }
        menu.addItem(untilItem)

        updateCaffeinationCountdown()
    }

    private func caffeinationTitle(for preset: CaffeinationPreset) -> String {
        switch preset {
        case .tenMinutes: return L10n.caffeinateTenMinutes
        case .thirtyMinutes: return L10n.caffeinateThirtyMinutes
        case .oneHour: return L10n.caffeinateOneHour
        case .twoHours: return L10n.caffeinateTwoHours
        case .fourHours: return L10n.caffeinateFourHours
        case .eightHours: return L10n.caffeinateEightHours
        case .twelveHours: return L10n.caffeinateTwelveHours
        }
    }

    private func startCaffeinationCountdown() {
        stopCaffeinationCountdown()
        guard caffeinationController.activeEndDate != nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateCaffeinationCountdown()
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        caffeinationCountdownTimer = timer
        updateCaffeinationCountdown()
    }

    private func stopCaffeinationCountdown() {
        caffeinationCountdownTimer?.invalidate()
        caffeinationCountdownTimer = nil
    }

    private func updateCaffeinationCountdown() {
        guard let item = activeCaffeinationMenuItem,
              let endDate = caffeinationController.activeEndDate,
              let remaining = caffeinationController.remainingTime()
        else { return }

        let remainingText = L10n.caffeinateRemaining(Self.compactDuration(remaining))
        let detail = activeCaffeinationIsUntil
            ? "\(Self.caffeinationEndDateText(endDate)) — \(remainingText)"
            : remainingText

        if #available(macOS 14.4, *) {
            item.title = activeCaffeinationBaseTitle
            item.subtitle = detail
        } else {
            item.title = "\(activeCaffeinationBaseTitle)  \(detail)"
        }
    }

    private static func compactDuration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(interval)))
        guard seconds > 0 else { return "0s" }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.maximumUnitCount = 3
        formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: L10n.lang.lprojName)
        formatter.calendar = calendar
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
    }

    private static func caffeinationEndDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.lang.lprojName)
        if Calendar.current.isDateInToday(date) {
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    /// Builds the update menu item — its title and action track the current
    /// state: an installable "new version" entry, a passive download/install
    /// progress line, or a "Check for Updates" action.
    private func makeUpdateMenuItem() -> NSMenuItem {
        let item: NSMenuItem
        switch UpdateChecker.shared.state {
        case .available(let version):
            item = NSMenuItem(title: L10n.updateAvailableMenu(version),
                              action: #selector(updateMenuItemClicked), keyEquivalent: "")
            item.image = Self.menuIcon(systemName: "arrow.down.circle.fill")
        case .downloading(_, let fraction):
            item = NSMenuItem(title: L10n.updateDownloadingMenu(Int(fraction * 100)),
                              action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = Self.menuIcon(systemName: "arrow.down.circle")
        case .installing:
            item = NSMenuItem(title: L10n.updateInstallingMenu, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = Self.menuIcon(systemName: "arrow.down.circle")
        case .installFailed:
            item = NSMenuItem(title: L10n.updateInstallFailedMenu,
                              action: #selector(updateMenuItemClicked), keyEquivalent: "")
            item.image = Self.menuIcon(systemName: "exclamationmark.triangle")
        case .checking:
            item = NSMenuItem(title: L10n.checkingForUpdatesMenu, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = Self.menuIcon(systemName: "arrow.triangle.2.circlepath")
        default:
            item = NSMenuItem(title: L10n.checkForUpdatesMenu,
                              action: #selector(checkForUpdatesClicked), keyEquivalent: "")
            item.image = Self.menuIcon(systemName: "arrow.triangle.2.circlepath")
        }
        item.target = self
        return item
    }

    @objc private func checkForUpdatesClicked() {
        // Give the manual check immediate feedback — the GitHub round trip can
        // take a moment, and otherwise nothing visible happens until it lands.
        UpdateProgressWindow.show(message: L10n.updateCheckingHUD, style: .spinner)
        UpdateChecker.shared.check(manual: true) { state in
            UpdateProgressWindow.dismiss()
            Self.presentManualCheckResult(state)
        }
    }

    /// Reflects an in-flight download/install into the progress HUD. The
    /// checking HUD and every dismissal are driven explicitly by the
    /// manual-check and install-failure paths, so this only advances the HUD
    /// through the download and install phases.
    private func syncUpdateProgressHUD() {
        switch UpdateChecker.shared.state {
        case .downloading(_, let fraction):
            UpdateProgressWindow.show(
                message: L10n.updateDownloadingHUD(Int(fraction * 100)),
                style: .bar(fraction: fraction)
            )
        case .installing(_, let phase):
            let message: String
            switch phase {
            case .verifying:  message = L10n.updateVerifyingHUD
            case .unzipping:  message = L10n.updateUnzippingHUD
            case .installing: message = L10n.updateInstallingHUD
            }
            UpdateProgressWindow.show(message: message, style: .spinner)
        default:
            break
        }
    }

    /// Handles a click on the update menu item once a release is known: offers
    /// the install prompt, or — after a failed install — the release page.
    @objc private func updateMenuItemClicked() {
        switch UpdateChecker.shared.state {
        case .available(let version):
            Self.presentUpdateAvailableAlertAfterRefresh(fallbackVersion: version)
        case .installFailed:
            if let url = UpdateChecker.shared.latestPageURL {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    /// Reports the outcome of a user-initiated check with a standard alert.
    /// Background launch checks stay silent and only update the menu item.
    private static func presentManualCheckResult(_ state: UpdateState) {
        switch state {
        case .available(let version):
            presentUpdateAvailableAlert(version: version)
        case .upToDate:
            let alert = NSAlert()
            alert.messageText = L10n.updateUpToDateTitle
            alert.informativeText = L10n.updateUpToDateBody(UpdateChecker.shared.currentVersion)
            alert.addButton(withTitle: L10n.updateOKButton)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .failed:
            let alert = NSAlert()
            alert.messageText = L10n.updateFailedTitle
            alert.informativeText = L10n.updateFailedBody
            alert.addButton(withTitle: L10n.updateOKButton)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .idle, .checking, .downloading, .installing, .installFailed:
            // Either a check was already in flight, or an install is being
            // driven elsewhere — nothing to report here.
            break
        }
    }

    /// Prompts the user to install a newer release. The download/install runs
    /// in the background; on success the app relaunches itself.
    static func presentUpdateAvailableAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = L10n.updateAvailableTitle(version)
        alert.informativeText = L10n.updateAvailableBody
        alert.addButton(withTitle: L10n.updateInstallNowButton)
        alert.addButton(withTitle: L10n.updateSkipButton)
        alert.addButton(withTitle: L10n.updateLaterButton)
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            UpdateChecker.shared.downloadAndInstall(onFailure: presentInstallFailedAlert)
        case .alertSecondButtonReturn:
            UpdateChecker.shared.skipVersion()
        default:
            break
        }
    }

    /// Refreshes GitHub before showing the install prompt so a long-running app
    /// does not offer an older release after a newer one is published.
    static func presentUpdateAvailableAlertAfterRefresh(fallbackVersion: String) {
        UpdateProgressWindow.show(message: L10n.updateCheckingHUD, style: .spinner)
        UpdateChecker.shared.check(manual: true) { state in
            UpdateProgressWindow.dismiss()
            switch state {
            case .available(let version):
                presentUpdateAvailableAlert(version: version)
            case .upToDate, .failed:
                presentManualCheckResult(state)
            case .idle, .checking, .downloading, .installing, .installFailed:
                presentUpdateAvailableAlert(version: fallbackVersion)
            }
        }
    }

    /// Shown when a download or install fails — offers the release page as a
    /// manual fallback.
    static func presentInstallFailedAlert() {
        UpdateProgressWindow.dismiss()
        let alert = NSAlert()
        alert.messageText = L10n.updateInstallFailedTitle
        alert.informativeText = L10n.updateInstallFailedBody
        alert.addButton(withTitle: L10n.updateOpenPageButton)
        alert.addButton(withTitle: L10n.updateOKButton)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = UpdateChecker.shared.latestPageURL {
            NSWorkspace.shared.open(url)
        }
    }

    func setMenuBarVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === caffeinationMenu else { return }
        rebuildCaffeinationMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === caffeinationMenu else { return }
        startCaffeinationCountdown()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === caffeinationMenu else { return }
        stopCaffeinationCountdown()
    }
}

private final class InstantTooltipLabel: NSTextField {
    private let tipMessage: String
    private var tipTrackingArea: NSTrackingArea?

    init(text: String, tipMessage: String) {
        self.tipMessage = tipMessage
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        backgroundColor = .clear
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = tipTrackingArea {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tipTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        InstantTooltipPresenter.shared.show(message: tipMessage, anchoredTo: self)
    }

    override func mouseExited(with event: NSEvent) {
        InstantTooltipPresenter.shared.hide()
    }

    override func mouseUp(with event: NSEvent) {
        superview?.mouseUp(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            InstantTooltipPresenter.shared.hide()
        }
    }
}

private final class InstantTooltipPresenter {
    static let shared = InstantTooltipPresenter()

    private var panel: NSPanel?

    func show(message: String, anchoredTo view: NSView) {
        hide()
        guard let anchorWindow = view.window else { return }

        let font = NSFont.systemFont(ofSize: 12, weight: .regular)
        let maxTextWidth: CGFloat = 280
        let padding = NSEdgeInsets(top: 7, left: 9, bottom: 7, right: 9)
        let textRect = (message as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let textSize = NSSize(width: ceil(textRect.width), height: ceil(textRect.height))
        let panelSize = NSSize(
            width: textSize.width + padding.left + padding.right,
            height: textSize.height + padding.top + padding.bottom
        )

        let contentView = NSView(frame: NSRect(origin: .zero, size: panelSize))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 6
        contentView.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.94).cgColor

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = font
        label.textColor = .white
        label.alignment = .left
        label.frame = NSRect(
            x: padding.left,
            y: padding.bottom,
            width: textSize.width,
            height: textSize.height
        )
        contentView.addSubview(label)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = contentView

        let anchorRect = anchorWindow.convertToScreen(view.convert(view.bounds, to: nil))
        let gap: CGFloat = 6
        var origin = NSPoint(
            x: anchorRect.midX - panelSize.width / 2,
            y: anchorRect.maxY + gap
        )
        let visibleFrame = (anchorWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        if origin.y + panelSize.height > visibleFrame.maxY {
            origin.y = anchorRect.minY - gap - panelSize.height
        }
        origin.x = min(max(origin.x, visibleFrame.minX + 6), visibleFrame.maxX - panelSize.width - 6)
        origin.y = min(max(origin.y, visibleFrame.minY + 6), visibleFrame.maxY - panelSize.height - 6)

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
