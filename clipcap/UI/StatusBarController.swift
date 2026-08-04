import AppKit

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private let onEditClipboardImage: () -> Void
    private let onOpenImage: () -> Void
    private let onMergeImages: () -> Void
    private let onOpenHistoryPanel: () -> Void
    private let onOpenSettings: () -> Void
    private var historyMenu: NSMenu?
    private var historyItem: NSMenuItem?
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
        NotificationCenter.default.addObserver(forName: .historyDidUpdate, object: nil, queue: .main) { [weak self] _ in
            self?.refreshHistoryItemState()
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
            let history = NSMenuItem(title: L10n.historyMenu, action: nil, keyEquivalent: "")
            history.image = Self.menuIcon(systemName: "clock.arrow.circlepath")
            let historySubmenu = NSMenu(title: L10n.historyMenu)
            historySubmenu.delegate = self
            history.submenu = historySubmenu
            historyMenu = historySubmenu
            historyItem = history
            menu.addItem(history)

            let historyPanelItem = NSMenuItem(title: L10n.historyPanelMenu, action: #selector(openHistoryPanel), keyEquivalent: "")
            historyPanelItem.target = self
            historyPanelItem.image = Self.menuIcon(systemName: "rectangle.stack")
            HotkeyManager.applyHistoryPanelToMenuItem(historyPanelItem)
            menu.addItem(historyPanelItem)

            menu.addItem(NSMenuItem.separator())
        } else {
            historyMenu = nil
            historyItem = nil
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

        refreshHistoryItemState()
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

    private func refreshHistoryItemState() {
        historyItem?.isEnabled = Defaults.isHistoryCacheAvailable
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

    @objc fileprivate func historyItemClicked(_ sender: Any?) {
        let entry: HistoryEntry?
        if let row = sender as? HistoryMenuRow {
            entry = row.entry
            row.enclosingMenuItem?.menu?.cancelTracking()
        } else if let item = sender as? NSMenuItem,
                  let stored = item.representedObject as? HistoryEntry {
            entry = stored
        } else {
            entry = nil
        }
        guard let entry = entry else { return }
        switch entry.kind {
        case .image:
            guard let image = NSImage(contentsOf: entry.fileURL) else { return }
            ClipboardManager.copyToClipboard(image: image)
            ToastWindow.show()
        case .color(let hex):
            ClipboardManager.copyColorToClipboard(hex: hex)
            ToastWindow.show(message: L10n.colorCopied(hex))
        case .text(let text):
            ClipboardManager.copyHistoryTextToClipboard(text.value)
            ToastWindow.show(message: L10n.copiedToClipboard)
        }
    }

    @objc private func clearHistoryClicked() {
        HistoryManager.shared.clearAll {
            ToastWindow.show(message: L10n.historyCleared)
        }
    }

    @objc private func showHistoryInFinderClicked() {
        NSWorkspace.shared.open(HistoryManager.shared.cacheDirectoryURL())
    }

    func setMenuBarVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === caffeinationMenu {
            rebuildCaffeinationMenu(menu)
            return
        }
        guard Defaults.isHistoryCacheAvailable, menu === historyMenu else { return }
        menu.removeAllItems()

        let entries = HistoryManager.shared.entries()
        addHistoryUtilityItems(to: menu, hasEntries: !entries.isEmpty)

        if entries.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let empty = NSMenuItem(title: L10n.historyEmpty, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        menu.addItem(NSMenuItem.separator())

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"

        for entry in entries {
            let item = NSMenuItem()
            let timestamp = formatter.string(from: entry.createdAt)
            let row = HistoryMenuRow(
                entry: entry,
                timestamp: timestamp,
                target: self,
                action: #selector(historyItemClicked(_:))
            )
            item.view = row
            item.representedObject = entry
            menu.addItem(item)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === caffeinationMenu else { return }
        startCaffeinationCountdown()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === caffeinationMenu else { return }
        stopCaffeinationCountdown()
    }

    private func addHistoryUtilityItems(to menu: NSMenu, hasEntries: Bool) {
        let clearItem = NSMenuItem(title: L10n.historyClear, action: #selector(clearHistoryClicked), keyEquivalent: "")
        clearItem.target = self
        clearItem.image = Self.menuIcon(systemName: "trash")
        clearItem.isEnabled = hasEntries
        menu.addItem(clearItem)

        let showInFinderItem = NSMenuItem(
            title: L10n.historyShowInFinder,
            action: #selector(showHistoryInFinderClicked),
            keyEquivalent: ""
        )
        showInFinderItem.target = self
        showInFinderItem.image = Self.menuIcon(systemName: "folder")
        menu.addItem(showInFinderItem)
    }
}

private final class HistoryMenuRow: NSView {
    static let itemWidth: CGFloat = 220
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 6
    static let labelHeight: CGFloat = 14
    static let spacing: CGFloat = 4
    static let thumbnailHeight: CGFloat = 96
    static let colorSwatchSize: CGFloat = 28
    static let textPreviewHeight: CGFloat = 64

    let entry: HistoryEntry
    private weak var target: AnyObject?
    private let action: Selector
    private let timeLabel: NSTextField

    init(entry: HistoryEntry, timestamp: String, target: AnyObject, action: Selector) {
        self.entry = entry
        self.target = target
        self.action = action

        let contentWidth = Self.itemWidth - Self.horizontalPadding * 2
        let previewBlock: (NSView, CGFloat) = {
            switch entry.kind {
            case .image:
                return Self.makeImagePreview(
                    url: entry.fileURL,
                    maxWidth: contentWidth,
                    badgeKind: HistoryMediaBadgeKind(entry: entry)
                )
            case .color(let hex):
                return Self.makeColorPreview(hex: hex, maxWidth: contentWidth)
            case .text(let text):
                return Self.makeTextPreview(text.value, maxWidth: contentWidth)
            }
        }()
        let preview = previewBlock.0
        let previewHeight = previewBlock.1
        let totalHeight = Self.verticalPadding * 2 + Self.labelHeight + Self.spacing + previewHeight

        timeLabel = NSTextField(labelWithString: timestamp)
        timeLabel.isSelectable = false
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.frame = NSRect(
            x: Self.horizontalPadding,
            y: totalHeight - Self.verticalPadding - Self.labelHeight,
            width: contentWidth,
            height: Self.labelHeight
        )
        timeLabel.autoresizingMask = [.minYMargin]

        super.init(frame: NSRect(x: 0, y: 0, width: Self.itemWidth, height: totalHeight))
        autoresizingMask = [.width]
        addSubview(timeLabel)
        addSubview(preview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseUp(with event: NSEvent) {
        if let target = target {
            _ = target.perform(action, with: self)
        }
    }

    private static func makeImagePreview(
        url: URL,
        maxWidth: CGFloat,
        badgeKind: HistoryMediaBadgeKind?
    ) -> (NSView, CGFloat) {
        makeMediaPreview(url: url, maxWidth: maxWidth, badgeKind: badgeKind)
    }

    private static func makeMediaPreview(
        url: URL,
        maxWidth: CGFloat,
        badgeKind: HistoryMediaBadgeKind?
    ) -> (NSView, CGFloat) {
        let previewHeight = Self.thumbnailHeight
        let container = HistoryMenuPreviewView(frame: NSRect(
            x: Self.horizontalPadding,
            y: Self.verticalPadding,
            width: maxWidth,
            height: previewHeight
        ))

        let imageView = NSImageView()
        imageView.isEditable = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        imageView.frame = container.bounds
        container.addSubview(imageView)

        if let badgeKind {
            let badge = HistoryMediaBadgeView(kind: badgeKind)
            let badgeSize = badge.intrinsicContentSize
            badge.frame = NSRect(
                x: maxWidth - badgeSize.width - 6,
                y: previewHeight - badgeSize.height - 6,
                width: badgeSize.width,
                height: badgeSize.height
            )
            container.addSubview(badge)
        }

        let pixelSize = Int(max(maxWidth, previewHeight) * (NSScreen.main?.backingScaleFactor ?? 2.0))
        let completion: (HistoryImagePreview) -> Void = { [weak imageView] preview in
            guard let imageView, let cgImage = preview.cgImage else { return }
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            imageView.image = NSImage(cgImage: cgImage, size: size)
            imageView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        HistoryImagePreviewLoader.shared.load(url: url, pixelSize: pixelSize, completion: completion)

        return (container, previewHeight)
    }

    private static func makeColorPreview(hex: String, maxWidth: CGFloat) -> (NSView, CGFloat) {
        let blockHeight = Self.colorSwatchSize
        let container = HistoryMenuPreviewView(frame: NSRect(
            x: Self.horizontalPadding,
            y: Self.verticalPadding,
            width: maxWidth,
            height: blockHeight
        ))

        let swatch = NSView(frame: NSRect(x: 0, y: 0, width: blockHeight, height: blockHeight))
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 6
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.separatorColor.cgColor
        swatch.layer?.backgroundColor = (NSColor(hex: hex) ?? .black).cgColor
        container.addSubview(swatch)

        let hexLabel = NSTextField(labelWithString: hex.uppercased())
        hexLabel.isSelectable = false
        hexLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        hexLabel.textColor = .labelColor
        hexLabel.alignment = .left
        hexLabel.frame = NSRect(
            x: blockHeight + 8,
            y: 0,
            width: maxWidth - blockHeight - 8,
            height: blockHeight
        )
        hexLabel.cell?.usesSingleLineMode = true
        hexLabel.cell?.lineBreakMode = .byTruncatingTail
        container.addSubview(hexLabel)

        return (container, blockHeight)
    }

    private static func makeTextPreview(_ text: String, maxWidth: CGFloat) -> (NSView, CGFloat) {
        let container = HistoryMenuPreviewView(frame: NSRect(
            x: Self.horizontalPadding,
            y: Self.verticalPadding,
            width: maxWidth,
            height: Self.textPreviewHeight
        ))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor

        let label = NSTextField(wrappingLabelWithString: text)
        label.isSelectable = false
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 4
        label.frame = container.bounds.insetBy(dx: 9, dy: 7)
        label.autoresizingMask = [.width, .height]
        label.toolTip = text
        container.addSubview(label)
        return (container, Self.textPreviewHeight)
    }
}

private final class HistoryMenuPreviewView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        return self
    }

    override func mouseUp(with event: NSEvent) {
        superview?.mouseUp(with: event)
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

private extension NSColor {
    convenience init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
