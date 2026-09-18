import AppKit
import Carbon

enum SettingsTab: CaseIterable {
    case general
    case shortcuts
    case toolbar
    case history
    case files
    case about

    var title: String {
        switch self {
        case .general: return L10n.settingsTabGeneral
        case .shortcuts: return L10n.settingsTabShortcuts
        case .toolbar: return L10n.settingsTabToolbar
        case .history: return L10n.settingsGeneralHistory
        case .files: return L10n.settingsGeneralFiles
        case .about: return L10n.settingsTabAbout
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "keyboard.fill"
        case .toolbar: return "slider.horizontal.3"
        case .history: return "clock"
        case .files: return "doc"
        case .about: return "info.circle.fill"
        }
    }

    var iconTint: NSColor {
        switch self {
        case .general: return NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.72, alpha: 1.0)
        case .shortcuts: return NSColor(calibratedRed: 0.36, green: 0.66, blue: 0.98, alpha: 1.0)
        case .toolbar: return NSColor(calibratedRed: 0.95, green: 0.54, blue: 0.62, alpha: 1.0)
        case .files:
            return NSColor(calibratedRed: 0.38, green: 0.80, blue: 0.78, alpha: 1.0)
        case .about, .history:
            return NSColor(calibratedRed: 0.70, green: 0.56, blue: 0.96, alpha: 1.0)
        }
    }
}

private enum HistoryPanelSettingsMode {
    case dialog
    case notch
}

final class SettingsView: NSView {
    var isStartup: Bool = false
    var onMenuBarToggle: ((Bool) -> Void)?
    var onLaunch: (() -> Void)?

    private let sidebarPanel = SidebarPanel()
    private let detailPanel = DetailPanel()
    private let sidebarStack = NSStackView()
    private let detailTitleLabel = NSTextField(labelWithString: "")
    private let detailScrollView = NSScrollView()
    private let paneDocumentView = FlippedView()
    private let footerActionButton = ActionButton(title: "", symbolName: "power")
    private var gradientLayer: CAGradientLayer?

    private var tabButtons: [SettingsTab: TabButton] = [:]
    private var selectedTab: SettingsTab = .general
    private var currentPane: NSView?

    private var languagePicker: NSPopUpButton?
    private var menuBarSwitch: NSSwitch?
    private var launchAtLoginSwitch: NSSwitch?
    private var pinAcrossSpacesSwitch: NSSwitch?
    private var systemScreenshotAutoOpenSwitch: NSSwitch?
    private var systemScreenshotStatusLabel: NSTextField?
    private var systemScreenshotSetupButton: NSButton?
    private var historyCacheSwitch: NSSwitch?
    private var clipboardTextCacheSwitch: NSSwitch?
    private var historyCacheSlider: NSSlider?
    private var historyCacheValueLabel: NSTextField?
    private var clipboardTextHistoryLimitSlider: NSSlider?
    private var clipboardTextHistoryLimitValueLabel: NSTextField?
    private var historyPanelModePreview: HistoryPanelModePreviewView?
    private var historyPanelDialogOption: HistoryPanelModeOptionView?
    private var historyPanelNotchOption: HistoryPanelModeOptionView?
    private var historyPanelDisplayModeTitleLabel: NSTextField?
    private var historyPanelDisplayModeHintLabel: NSTextField?
    private var historyPanelDialogModeTitleLabel: NSTextField?
    private var historyPanelDialogModeHintLabel: NSTextField?
    private var historyPanelNotchModeTitleLabel: NSTextField?
    private var historyPanelNotchModeHintLabel: NSTextField?
    private var historyNotchTriggerRow: NSView?
    private var historyNotchTriggerLabel: NSTextField?
    private var historyNotchTriggerPopup: NSPopUpButton?
    private var autoRevealSwitch: NSSwitch?
    private var savePathValueLabel: NSTextField?
    private var screenshotQualitySavePopup: NSPopUpButton?
    private var screenshotQualitySaveHintLabel: NSTextField?
    private var screenshotQualityClipboardPopup: NSPopUpButton?
    private var screenshotQualityClipboardHintLabel: NSTextField?

    private var shortcutRows: [ShortcutSlot: ShortcutRowViews] = [:]
    private var activeShortcutSlot: ShortcutSlot?
    private var shortcutRecordingMonitor: Any?
    private var aboutUpdateStatusLabel: NSTextField?
    private var aboutUpdateButton: NSButton?

    override var acceptsFirstResponder: Bool { true }

    init(frame frameRect: NSRect, isStartup: Bool) {
        self.isStartup = isStartup
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        setupBackground()
        setupUI()
        selectTab(.general)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: .languageDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshUpdateRow),
            name: .updateStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshSystemScreenshotAutoOpenControls),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancelShortcutRecording()
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        gradientLayer?.frame = bounds
    }

    func setStartupMode(_ startup: Bool) {
        isStartup = startup
        updateFooterAction()
    }

    func showPermissionsTab() {
        selectTab(.general)
    }

    func cancelSelectedImagePinShortcutRecording() { cancelShortcutRecording() }
    func cancelClipboardImagePinShortcutRecording() { cancelShortcutRecording() }
    func cancelSelectedImageEditShortcutRecording() { cancelShortcutRecording() }
    func cancelClipboardImageEditShortcutRecording() { cancelShortcutRecording() }
    func cancelClipboardShortcutRecording() { cancelShortcutRecording() }
    func cancelFileSaveShortcutRecording() { cancelShortcutRecording() }
    func closeTransientPanels() { activeToolbarPane?.cancelShortcutRecording() }

    private weak var activeToolbarPane: ToolbarSettingsPane?

    func cancelShortcutRecording() {
        activeToolbarPane?.cancelShortcutRecording()
        guard activeShortcutSlot != nil || shortcutRecordingMonitor != nil else { return }
        if let monitor = shortcutRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutRecordingMonitor = nil
        }
        activeShortcutSlot = nil
        refreshShortcutRows()
    }

    private func setupBackground() {
        wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.17, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.10, alpha: 1.0).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.frame = bounds
        layer?.addSublayer(gradient)
        gradientLayer = gradient
    }

    private func setupUI() {
        buildSidebar()
        buildDetailPanel()

        addSubview(sidebarPanel)
        addSubview(detailPanel)
        sidebarPanel.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            sidebarPanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            sidebarPanel.topAnchor.constraint(equalTo: topAnchor, constant: 38),
            sidebarPanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            sidebarPanel.widthAnchor.constraint(equalToConstant: 180),

            detailPanel.leadingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor, constant: 12),
            detailPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            detailPanel.topAnchor.constraint(equalTo: topAnchor, constant: 38),
            detailPanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    private func buildSidebar() {
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 6
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.addSubview(sidebarStack)

        for tab in SettingsTab.allCases {
            if tab == .history {
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
                separator.translatesAutoresizingMaskIntoConstraints = false
                sidebarStack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
            let button = TabButton(tab: tab, target: self, action: #selector(tabClicked(_:)))
            tabButtons[tab] = button
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
        }

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.addSubview(divider)

        footerActionButton.target = self
        footerActionButton.action = #selector(footerActionClicked)
        sidebarPanel.addSubview(footerActionButton)
        updateFooterAction()

        NSLayoutConstraint.activate([
            sidebarStack.topAnchor.constraint(equalTo: sidebarPanel.topAnchor, constant: 14),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor, constant: 14),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor, constant: -14),
            sidebarStack.bottomAnchor.constraint(lessThanOrEqualTo: divider.topAnchor, constant: -8),

            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor, constant: 14),
            divider.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor, constant: -14),
            divider.bottomAnchor.constraint(equalTo: footerActionButton.topAnchor, constant: -8),

            footerActionButton.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor, constant: 14),
            footerActionButton.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor, constant: -14),
            footerActionButton.bottomAnchor.constraint(equalTo: sidebarPanel.bottomAnchor, constant: -10),
        ])
    }

    private func buildDetailPanel() {
        detailTitleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        detailTitleLabel.textColor = NSColor.white.withAlphaComponent(0.96)
        detailTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailScrollView.borderType = .noBorder
        detailScrollView.drawsBackground = false
        detailScrollView.hasVerticalScroller = true
        detailScrollView.autohidesScrollers = true
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailScrollView.documentView = paneDocumentView
        paneDocumentView.translatesAutoresizingMaskIntoConstraints = false

        detailPanel.addSubview(detailTitleLabel)
        detailPanel.addSubview(detailScrollView)

        NSLayoutConstraint.activate([
            detailTitleLabel.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor, constant: 22),
            detailTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailPanel.trailingAnchor, constant: -22),
            detailTitleLabel.topAnchor.constraint(equalTo: detailPanel.topAnchor, constant: 18),

            detailScrollView.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor),
            detailScrollView.topAnchor.constraint(equalTo: detailTitleLabel.bottomAnchor, constant: 10),
            detailScrollView.bottomAnchor.constraint(equalTo: detailPanel.bottomAnchor),

            paneDocumentView.topAnchor.constraint(equalTo: detailScrollView.contentView.topAnchor),
            paneDocumentView.leadingAnchor.constraint(equalTo: detailScrollView.contentView.leadingAnchor),
            paneDocumentView.trailingAnchor.constraint(equalTo: detailScrollView.contentView.trailingAnchor),
            paneDocumentView.widthAnchor.constraint(equalTo: detailScrollView.contentView.widthAnchor),
        ])
    }

    private func updateFooterAction() {
        let title = isStartup ? L10n.launchApp : L10n.quitApp
        let symbol = isStartup ? "checkmark.circle.fill" : "power"
        footerActionButton.configure(title: title, symbolName: symbol)
    }

    @objc private func footerActionClicked() {
        if isStartup {
            onLaunch?()
        } else {
            NSApp.terminate(nil)
        }
    }

    @objc private func tabClicked(_ sender: TabButton) {
        selectTab(sender.tab)
    }

    private func selectTab(_ tab: SettingsTab) {
        activeToolbarPane?.cancelShortcutRecording()
        selectedTab = tab
        detailTitleLabel.stringValue = tab.title
        tabButtons.values.forEach { $0.isSelectedTab = false }
        tabButtons[tab]?.isSelectedTab = true

        currentPane?.removeFromSuperview()
        let pane: NSView
        switch tab {
        case .general:
            pane = makeGeneralPane()
        case .shortcuts:
            pane = makeShortcutsPane()
        case .toolbar:
            let toolbarPane = ToolbarSettingsPane()
            activeToolbarPane = toolbarPane
            pane = toolbarPane
        case .history:
            pane = makeHistoryPane()
        case .files:
            pane = makeFilesPane()
        case .about:
            pane = makeAboutPane()
        }

        currentPane = pane
        pane.translatesAutoresizingMaskIntoConstraints = false
        paneDocumentView.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: paneDocumentView.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: paneDocumentView.trailingAnchor),
            pane.topAnchor.constraint(equalTo: paneDocumentView.topAnchor),
            pane.bottomAnchor.constraint(equalTo: paneDocumentView.bottomAnchor),
        ])
        paneDocumentView.needsLayout = true
        detailScrollView.contentView.scroll(to: .zero)
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
    }

    private func wrapPane(_ content: NSView, horizontalInset: CGFloat = 22) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: horizontalInset),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -horizontalInset),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -22),
        ])
        return wrapper
    }

    private func makeGeneralPane() -> NSView {
        let stack = paneStack()

        let languageCard = CardView()
        let languageRow = NSStackView()
        languageRow.orientation = .horizontal
        languageRow.alignment = .centerY
        languageRow.spacing = 10
        languageRow.translatesAutoresizingMaskIntoConstraints = false
        languageCard.addSubview(languageRow)
        pin(languageRow, to: languageCard, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        languageRow.addArrangedSubview(primaryLabel(L10n.languageHeader))
        languageRow.addArrangedSubview(flexSpacer())

        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.translatesAutoresizingMaskIntoConstraints = false
        for language in AppLanguage.allCases {
            picker.addItem(withTitle: language.displayName)
            picker.lastItem?.representedObject = language.rawValue
        }
        if let index = AppLanguage.allCases.firstIndex(of: Defaults.language) {
            picker.selectItem(at: index)
        }
        picker.target = self
        picker.action = #selector(languagePicked(_:))
        picker.controlSize = .small
        picker.font = NSFont.systemFont(ofSize: 12)
        languagePicker = picker
        languageRow.addArrangedSubview(picker)
        addCard(languageCard, to: stack)

        let togglesCard = CardView()
        let toggles = verticalInnerStack()
        togglesCard.addSubview(toggles)
        pin(toggles, to: togglesCard, insets: NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14))
        addFullWidth(
            switchRow(title: L10n.showMenuBarIcon, subtitle: nil, isOn: Defaults.showMenuBar, action: #selector(menuBarToggled(_:))) { self.menuBarSwitch = $0 },
            to: toggles
        )
        addFullWidth(rowDivider(), to: toggles)
        addFullWidth(
            switchRow(title: L10n.launchAtLogin, subtitle: nil, isOn: LaunchAtLogin.isEnabled, action: #selector(launchAtLoginToggled(_:))) { self.launchAtLoginSwitch = $0 },
            to: toggles
        )
        addFullWidth(rowDivider(), to: toggles)
        addFullWidth(
            switchRow(title: L10n.pinAcrossSpaces, subtitle: L10n.pinAcrossSpacesHint, isOn: Defaults.pinAcrossSpaces, action: #selector(pinAcrossSpacesToggled(_:))) { self.pinAcrossSpacesSwitch = $0 },
            to: toggles
        )
        addCard(togglesCard, to: stack)

        addCard(makeSystemScreenshotAutoOpenCard(), to: stack)

        return wrapPane(stack)
    }

    private func makeHistoryPane() -> NSView {
        let stack = paneStack()

        let historyCard = CardView()
        let history = NSStackView()
        history.orientation = .vertical
        history.alignment = .leading
        history.spacing = 10
        history.translatesAutoresizingMaskIntoConstraints = false
        historyCard.addSubview(history)
        pin(history, to: historyCard, insets: NSEdgeInsets(top: 4, left: 14, bottom: 14, right: 14))
        addFullWidth(
            switchRow(title: L10n.historyCacheToggleLabel, subtitle: L10n.historyCacheToggleHint, isOn: Defaults.historyCacheEnabled, action: #selector(historyCacheToggled(_:))) { self.historyCacheSwitch = $0 },
            to: history
        )
        addFullWidth(makeHistoryCacheSliderRow(), to: history)
        addFullWidth(rowDivider(), to: history)
        addFullWidth(
            switchRow(title: L10n.clipboardTextCacheToggleLabel, subtitle: L10n.clipboardTextCacheToggleHint, isOn: Defaults.clipboardTextCacheEnabled, action: #selector(clipboardTextCacheToggled(_:))) { self.clipboardTextCacheSwitch = $0 },
            to: history
        )
        addFullWidth(makeClipboardTextHistoryLimitSliderRow(), to: history)
        addCard(historyCard, to: stack)

        addCard(makeHistoryPanelModeCard(), to: stack)

        return wrapPane(stack)
    }

    private func makeFilesPane() -> NSView {
        let stack = paneStack()

        addCard(makeScreenshotQualityCard(), to: stack)

        let savePathCard = CardView()
        let savePath = NSStackView()
        savePath.orientation = .vertical
        savePath.alignment = .leading
        savePath.spacing = 10
        savePath.translatesAutoresizingMaskIntoConstraints = false
        savePathCard.addSubview(savePath)
        pin(savePath, to: savePathCard, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))

        let saveHeader = NSStackView()
        saveHeader.orientation = .vertical
        saveHeader.alignment = .leading
        saveHeader.spacing = 3
        saveHeader.translatesAutoresizingMaskIntoConstraints = false
        let saveTitle = primaryLabel(L10n.savePathTitle)
        let saveSubtitle = secondaryLabel(L10n.savePathSubtitle, wrapping: true)
        saveHeader.addArrangedSubview(saveTitle)
        saveHeader.addArrangedSubview(saveSubtitle)
        addFullWidth(saveHeader, to: savePath)
        saveSubtitle.widthAnchor.constraint(equalTo: saveHeader.widthAnchor).isActive = true

        addFullWidth(rowDivider(), to: savePath)
        addFullWidth(
            switchRow(title: L10n.autoRevealSavedFilesLabel, subtitle: L10n.autoRevealSavedFilesHint, isOn: Defaults.autoRevealSavedFiles, action: #selector(autoRevealToggled(_:))) { self.autoRevealSwitch = $0 },
            to: savePath
        )
        addFullWidth(rowDivider(), to: savePath)
        addFullWidth(makeSavePathRow(), to: savePath)
        addCard(savePathCard, to: stack)
        addCard(makeRecordingCard(), to: stack)

        return wrapPane(stack)
    }

    private func makeShortcutsPane() -> NSView {
        shortcutRows.removeAll()
        let stack = paneStack()
        for slot in ShortcutSlot.allCases {
            let card = shortcutCard(for: slot)
            addCard(card, to: stack)
        }
        refreshShortcutRows()
        return wrapPane(stack)
    }

    private func makeAboutPane() -> NSView {
        let stack = paneStack()

        let headerCard = CardView()
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 16
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerCard.embed(headerRow)

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let nameLabel = NSTextField(labelWithString: "clipcap")
        nameLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.96)

        let versionLabel = NSTextField(labelWithString: appVersionDisplayString())
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        versionLabel.textColor = NSColor.white.withAlphaComponent(0.56)

        let taglineLabel = secondaryLabel(L10n.aboutTagline, wrapping: true)

        let textStack = NSStackView(views: [nameLabel, versionLabel, taglineLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        headerRow.addArrangedSubview(iconView)
        headerRow.addArrangedSubview(textStack)
        headerRow.addArrangedSubview(flexSpacer())

        addCard(headerCard, to: stack)

        let infoCard = CardView()
        infoCard.layer?.masksToBounds = true
        let infoInner = verticalInnerStack()
        infoCard.addSubview(infoInner)
        pin(infoInner, to: infoCard, insets: NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))

        let updateRow = makeUpdateRow()
        addFullWidth(updateRow, to: infoInner)
        addFullWidth(rowDivider(), to: infoInner)

        let license = makeInfoRow(title: L10n.aboutLicense, value: "MIT")
        addFullWidth(license, to: infoInner)
        addFullWidth(rowDivider(), to: infoInner)

        let source = makeLinkRow(
            title: L10n.aboutSourceCode,
            value: "github.com/realskyrin/clipcap",
            action: #selector(openSourceRepo)
        )
        addFullWidth(source, to: infoInner)

        addCard(infoCard, to: stack)
        return wrapPane(stack)
    }

    private var debugLogStatus: NSTextField?

    @objc private func debugLogToggled(_ sender: NSSwitch) {
        DebugLog.isEnabled = sender.state == .on
        debugLogStatus?.stringValue = ""
    }

    @objc private func copyDebugLog() {
        do {
            let contents = try DebugLog.contents()
            guard !contents.isEmpty else {
                debugLogStatus?.stringValue = L10n.debugLogEmpty
                return
            }
            NSPasteboard.general.clearContents()
            let copied = NSPasteboard.general.setString(contents, forType: .string)
            debugLogStatus?.stringValue = copied ? L10n.debugLogCopied : L10n.debugLogFailed
        } catch {
            debugLogStatus?.stringValue = L10n.debugLogFailed
        }
    }

    @objc private func clearDebugLog() {
        do {
            try DebugLog.clear()
            debugLogStatus?.stringValue = L10n.debugLogCleared
        } catch {
            debugLogStatus?.stringValue = L10n.debugLogFailed
        }
    }

    private func appVersionDisplayString() -> String {
        "v\(UpdateChecker.shared.currentVersion)"
    }

    private func paneStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func verticalInnerStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func cardStack(spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func addCard(_ card: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func flexSpacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return view
    }

    private func primaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.94)
        return label
    }

    private func secondaryLabel(_ text: String, wrapping: Bool = false) -> NSTextField {
        let label = wrapping ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.white.withAlphaComponent(0.58)
        if wrapping {
            label.maximumNumberOfLines = 0
            label.preferredMaxLayoutWidth = 360
        }
        return label
    }

    private func pin(_ child: NSView, to parent: NSView, insets: NSEdgeInsets) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
        ])
    }

    private func makeSectionHeader(_ text: String) -> NSTextField {
        primaryLabel(text)
    }

    private func makeBody(_ text: String) -> NSTextField {
        let label = secondaryLabel(text, wrapping: true)
        label.maximumNumberOfLines = 0
        return label
    }

    private func makeRepositorySection() -> NSView {
        let stack = cardStack(spacing: 6)
        stack.addArrangedSubview(makeSectionHeader(L10n.aboutRepositoriesTitle))
        stack.addArrangedSubview(makeRepositoryRow(name: "clipcap", urlString: "https://github.com/realskyrin/clipcap"))
        stack.addArrangedSubview(makeRepositoryRow(name: "capcap", urlString: "https://github.com/realskyrin/capcap"))
        return stack
    }

    private func makeRepositoryRow(name: String, urlString: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = primaryLabel(name)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        nameLabel.widthAnchor.constraint(equalToConstant: 54).isActive = true

        let linkButton = makeLinkButton(title: urlString, urlString: urlString)
        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(linkButton)
        return row
    }

    private func makeLinkButton(title: String, urlString: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(openRepositoryLink(_:)))
        button.isBordered = false
        button.controlSize = .small
        button.identifier = NSUserInterfaceItemIdentifier(rawValue: urlString)
        button.toolTip = title
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func makeInfoRow(title: String, value: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        valueLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
        ])
        return row
    }

    private func makeLinkRow(title: String, value: String, action: Selector) -> NSView {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.momentaryChange)

        let titleLabel = primaryLabel(title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = NSColor(calibratedRed: 0.42, green: 0.66, blue: 0.98, alpha: 1.0)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let chevron = NSTextField(labelWithString: "\u{203A}")
        chevron.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        chevron.textColor = NSColor.white.withAlphaComponent(0.32)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        button.addSubview(titleLabel)
        button.addSubview(valueLabel)
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
        ])
        return button
    }

    private func makeUpdateRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(L10n.aboutUpdateTitle)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        aboutUpdateStatusLabel = statusLabel

        let button = NSButton(title: L10n.checkForUpdates, target: self, action: #selector(aboutUpdateButtonClicked))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        aboutUpdateButton = button

        row.addSubview(titleLabel)
        row.addSubview(statusLabel)
        row.addSubview(button)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
        ])

        refreshUpdateRow()
        return row
    }

    private func switchRow(
        title: String,
        subtitle: String?,
        isOn: Bool,
        action: Selector,
        capture: (NSSwitch) -> Void
    ) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(primaryLabel(title))
        if let subtitle {
            textStack.addArrangedSubview(secondaryLabel(subtitle, wrapping: true))
        }

        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        capture(toggle)

        row.addSubview(textStack)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),

            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
        ])
        return row
    }

    private func rowDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func makeHistoryCacheSliderRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        header.addArrangedSubview(primaryLabel(L10n.historyCacheLabel))
        header.addArrangedSubview(flexSpacer())

        let slider = NSSlider(
            value: Double(Defaults.historyCacheLimit),
            minValue: Double(Defaults.historyCacheMin),
            maxValue: Double(Defaults.historyCacheMax),
            target: self,
            action: #selector(historyLimitChanged(_:))
        )
        slider.numberOfTickMarks = ((Defaults.historyCacheMax - Defaults.historyCacheMin) / Defaults.historyCacheStep) + 1
        slider.allowsTickMarkValuesOnly = true
        slider.controlSize = .small
        slider.isEnabled = Defaults.historyCacheEnabled
        historyCacheSlider = slider

        let value = NSTextField(labelWithString: "\(Defaults.historyCacheLimit)")
        value.textColor = NSColor.white.withAlphaComponent(0.88)
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        historyCacheValueLabel = value
        header.addArrangedSubview(value)

        addFullWidth(header, to: stack)
        addFullWidth(slider, to: stack)
        return stack
    }

    private func makeClipboardTextHistoryLimitSliderRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        header.addArrangedSubview(primaryLabel(L10n.clipboardTextHistoryLimitLabel))
        header.addArrangedSubview(flexSpacer())

        let slider = NSSlider(
            value: Double(Defaults.clipboardTextHistoryLimit),
            minValue: Double(Defaults.clipboardTextHistoryLimitMin),
            maxValue: Double(Defaults.clipboardTextHistoryLimitMax),
            target: self,
            action: #selector(clipboardTextHistoryLimitChanged(_:))
        )
        slider.numberOfTickMarks = (
            (Defaults.clipboardTextHistoryLimitMax - Defaults.clipboardTextHistoryLimitMin)
                / Defaults.clipboardTextHistoryLimitStep
        ) + 1
        slider.allowsTickMarkValuesOnly = true
        slider.controlSize = .small
        slider.isEnabled = Defaults.clipboardTextCacheEnabled
        clipboardTextHistoryLimitSlider = slider

        let value = NSTextField(labelWithString: "\(Defaults.clipboardTextHistoryLimit)")
        value.textColor = NSColor.white.withAlphaComponent(0.88)
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        clipboardTextHistoryLimitValueLabel = value
        header.addArrangedSubview(value)

        addFullWidth(header, to: stack)
        addFullWidth(slider, to: stack)
        return stack
    }

    private func makeHistoryPanelModeCard() -> NSView {
        let card = CardView()
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 14
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        pin(inner, to: card, insets: NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16))

        let title = primaryLabel(L10n.historyPanelDisplayModeLabel)
        let hint = secondaryLabel(L10n.historyPanelDisplayModeHint, wrapping: true)
        historyPanelDisplayModeTitleLabel = title
        historyPanelDisplayModeHintLabel = hint
        inner.addArrangedSubview(title)
        inner.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let preview = HistoryPanelModePreviewView(mode: selectedHistoryPanelMode())
        preview.translatesAutoresizingMaskIntoConstraints = false
        historyPanelModePreview = preview
        inner.addArrangedSubview(preview)
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalTo: inner.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: 136),
        ])

        let optionRow = NSStackView()
        optionRow.orientation = .horizontal
        optionRow.alignment = .top
        optionRow.distribution = .fillEqually
        optionRow.spacing = 12
        optionRow.translatesAutoresizingMaskIntoConstraints = false

        let dialog = HistoryPanelModeOptionView(
            mode: .dialog,
            title: L10n.historyPanelDialogMode,
            subtitle: L10n.historyPanelDialogModeHint
        )
        historyPanelDialogModeTitleLabel = dialog.title
        historyPanelDialogModeHintLabel = dialog.subtitle
        historyPanelDialogOption = dialog
        dialog.target = self
        dialog.action = #selector(historyPanelModeOptionClicked(_:))

        let notch = HistoryPanelModeOptionView(
            mode: .notch,
            title: L10n.historyPanelNotchMode,
            subtitle: L10n.historyPanelNotchModeHint
        )
        historyPanelNotchModeTitleLabel = notch.title
        historyPanelNotchModeHintLabel = notch.subtitle
        historyPanelNotchOption = notch
        notch.target = self
        notch.action = #selector(historyPanelModeOptionClicked(_:))

        optionRow.addArrangedSubview(dialog)
        optionRow.addArrangedSubview(notch)
        inner.addArrangedSubview(optionRow)
        optionRow.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        let triggerRow = NSStackView()
        triggerRow.orientation = .horizontal
        triggerRow.alignment = .centerY
        triggerRow.spacing = 10
        historyNotchTriggerRow = triggerRow

        let triggerLabel = primaryLabel(L10n.historyNotchTriggerLabel)
        historyNotchTriggerLabel = triggerLabel
        triggerRow.addArrangedSubview(triggerLabel)
        triggerRow.addArrangedSubview(flexSpacer())

        let triggerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        triggerPopup.controlSize = .small
        triggerPopup.font = NSFont.systemFont(ofSize: 12)
        triggerPopup.addItems(withTitles: Defaults.HistoryNotchTriggerMode.allCases.map(\.localizedTitle))
        triggerPopup.setAccessibilityLabel(L10n.historyNotchTriggerLabel)
        triggerPopup.target = self
        triggerPopup.action = #selector(historyNotchTriggerChanged(_:))
        historyNotchTriggerPopup = triggerPopup
        triggerRow.addArrangedSubview(triggerPopup)
        inner.addArrangedSubview(triggerRow)
        triggerRow.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        updateHistoryPanelModeControlsEnabled()
        return card
    }

    private func updateHistoryPanelModeControlsEnabled() {
        let historyAvailable = Defaults.isHistoryCacheAvailable
        let notchAvailable = Defaults.historyPanelNotchAvailable
        let dialogEnabled = historyAvailable
        let notchEnabled = historyAvailable && notchAvailable
        let mode = selectedHistoryPanelMode()

        historyPanelModePreview?.mode = mode
        historyPanelModePreview?.isEffectEnabled = historyAvailable
        historyPanelDialogOption?.isEnabled = dialogEnabled
        historyPanelNotchOption?.isEnabled = notchEnabled
        historyPanelDialogOption?.isSelected = mode == .dialog
        historyPanelNotchOption?.isSelected = mode == .notch

        let triggerEnabled = notchEnabled && mode == .notch
        historyNotchTriggerPopup?.isEnabled = triggerEnabled
        historyNotchTriggerPopup?.selectItem(
            at: Defaults.HistoryNotchTriggerMode.allCases.firstIndex(of: Defaults.historyNotchTriggerMode) ?? 0
        )
        historyNotchTriggerRow?.isHidden = mode != .notch
        historyNotchTriggerLabel?.textColor = NSColor.white.withAlphaComponent(triggerEnabled ? 0.94 : 0.4)

        historyPanelDisplayModeTitleLabel?.textColor = NSColor.white.withAlphaComponent(historyAvailable ? 0.94 : 0.4)
        historyPanelDisplayModeHintLabel?.textColor = NSColor.white.withAlphaComponent(historyAvailable ? 0.58 : 0.35)
        historyPanelDialogModeTitleLabel?.textColor = NSColor.white.withAlphaComponent(dialogEnabled ? 0.94 : 0.4)
        historyPanelDialogModeHintLabel?.textColor = NSColor.white.withAlphaComponent(dialogEnabled ? 0.58 : 0.35)
        historyPanelNotchModeTitleLabel?.textColor = NSColor.white.withAlphaComponent(notchEnabled ? 0.94 : 0.4)
        historyPanelNotchModeHintLabel?.textColor = NSColor.white.withAlphaComponent(notchEnabled ? 0.58 : 0.35)
    }

    private func selectedHistoryPanelMode() -> HistoryPanelSettingsMode {
        Defaults.historyPanelNotchEnabled ? .notch : .dialog
    }

    private func makeSavePathRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 3
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = primaryLabel(L10n.screenshotSavePathLabel)
        let pathLabel = secondaryLabel(SaveDestination.displayPath(Defaults.screenshotSaveDirectory), wrapping: false)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        savePathValueLabel = pathLabel
        labelStack.addArrangedSubview(titleLabel)
        labelStack.addArrangedSubview(pathLabel)

        let choose = makeButton(title: L10n.savePathChoose, action: #selector(chooseSavePath))
        let reveal = makeButton(title: L10n.savePathReveal, action: #selector(revealSavePath))

        row.addArrangedSubview(labelStack)
        labelStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        row.addArrangedSubview(flexSpacer())
        row.addArrangedSubview(choose)
        row.addArrangedSubview(reveal)
        choose.setContentHuggingPriority(.required, for: .horizontal)
        reveal.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func makeRecordingCard() -> NSView {
        let card = CardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        pin(stack, to: card, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        for (key, labels, action, selected) in [
            ("recordingFormatTitle", [Localizer.string("recordingManual"), "MP4", "GIF"], #selector(recordingFormatChanged(_:)), ["manual", "mp4", "gif"].firstIndex(of: RecordingImport.format) ?? 0),
            ("recordingCompressionTitle", [Localizer.string("recordingOriginal"), Localizer.string("recordingCompressed")], #selector(recordingCompressionChanged(_:)), RecordingImport.compress ? 1 : 0)
        ] {
            let row = NSStackView()
            row.orientation = .horizontal
            row.addArrangedSubview(primaryLabel(Localizer.string(key)))
            row.addArrangedSubview(flexSpacer())
            let popup = NSPopUpButton()
            popup.addItems(withTitles: labels)
            popup.selectItem(at: selected)
            popup.target = self
            popup.action = action
            row.addArrangedSubview(popup)
            addFullWidth(row, to: stack)
        }
        addFullWidth(secondaryLabel(Localizer.string("recordingSystemHint"), wrapping: true), to: stack)
        return card
    }
    @objc private func recordingFormatChanged(_ sender: NSPopUpButton) {
        RecordingImport.format = ["manual", "mp4", "gif"][sender.indexOfSelectedItem]
    }
    @objc private func recordingCompressionChanged(_ sender: NSPopUpButton) {
        RecordingImport.compress = sender.indexOfSelectedItem == 1
    }
    private func makeScreenshotQualityCard() -> NSView {
        let card = CardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3
        header.translatesAutoresizingMaskIntoConstraints = false
        let title = primaryLabel(L10n.screenshotQualityTitle)
        let subtitle = secondaryLabel(L10n.screenshotQualitySubtitle, wrapping: true)
        header.addArrangedSubview(title)
        header.addArrangedSubview(subtitle)
        addFullWidth(header, to: stack)
        subtitle.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true

        addFullWidth(rowDivider(), to: stack)

        let save = makeScreenshotQualityRow(
            title: L10n.screenshotQualitySaveLabel,
            quality: Defaults.screenshotSaveQuality,
            action: #selector(screenshotSaveQualityChanged(_:))
        )
        screenshotQualitySaveHintLabel = save.hint
        screenshotQualitySavePopup = save.popup
        addFullWidth(save.row, to: stack)

        addFullWidth(rowDivider(), to: stack)

        let clipboard = makeScreenshotQualityRow(
            title: L10n.screenshotQualityClipboardLabel,
            quality: Defaults.screenshotClipboardQuality,
            action: #selector(screenshotClipboardQualityChanged(_:))
        )
        screenshotQualityClipboardHintLabel = clipboard.hint
        screenshotQualityClipboardPopup = clipboard.popup
        addFullWidth(clipboard.row, to: stack)

        refreshScreenshotQualityControls()
        card.embed(stack)
        return card
    }

    private func makeSystemScreenshotAutoOpenCard() -> NSView {
        let card = CardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        addFullWidth(
            switchRow(
                title: L10n.systemScreenshotAutoOpenLabel,
                subtitle: L10n.systemScreenshotAutoOpenHint,
                isOn: Defaults.systemScreenshotAutoOpenEnabled,
                action: #selector(systemScreenshotAutoOpenToggled(_:))
            ) { self.systemScreenshotAutoOpenSwitch = $0 },
            to: stack
        )

        addFullWidth(rowDivider(), to: stack)

        let folderRow = NSStackView()
        folderRow.orientation = .horizontal
        folderRow.alignment = .centerY
        folderRow.spacing = 10
        folderRow.translatesAutoresizingMaskIntoConstraints = false

        let folderText = NSStackView()
        folderText.orientation = .vertical
        folderText.alignment = .leading
        folderText.spacing = 3
        folderText.translatesAutoresizingMaskIntoConstraints = false
        folderText.addArrangedSubview(primaryLabel(L10n.systemScreenshotFolderLabel))

        let pathLabel = secondaryLabel(
            SaveDestination.displayPath(SystemScreenshotAutoOpen.directoryURL),
            wrapping: false
        )
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        folderText.addArrangedSubview(pathLabel)

        let setup = makeButton(
            title: L10n.systemScreenshotSetup,
            action: #selector(configureSystemScreenshotAutoOpen)
        )
        systemScreenshotSetupButton = setup
        let reveal = makeButton(
            title: L10n.systemScreenshotRevealFolder,
            action: #selector(revealSystemScreenshotFolder)
        )

        folderRow.addArrangedSubview(folderText)
        folderText.widthAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true
        folderRow.addArrangedSubview(flexSpacer())
        folderRow.addArrangedSubview(setup)
        folderRow.addArrangedSubview(reveal)
        setup.setContentHuggingPriority(.required, for: .horizontal)
        reveal.setContentHuggingPriority(.required, for: .horizontal)
        addFullWidth(folderRow, to: stack)

        let status = secondaryLabel("", wrapping: true)
        status.maximumNumberOfLines = 0
        systemScreenshotStatusLabel = status
        addFullWidth(status, to: stack)

        let thumbnailHint = secondaryLabel(L10n.systemScreenshotFloatingThumbnailHint, wrapping: true)
        thumbnailHint.maximumNumberOfLines = 0
        addFullWidth(thumbnailHint, to: stack)

        card.embed(stack)
        refreshSystemScreenshotAutoOpenControls()
        return card
    }

    private func makeScreenshotQualityRow(
        title: String,
        quality: ScreenshotImageQuality,
        action: Selector
    ) -> (row: NSView, hint: NSTextField, popup: NSPopUpButton) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 3
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        labelStack.addArrangedSubview(primaryLabel(title))
        let hintLabel = secondaryLabel(quality.localizedHint, wrapping: true)
        labelStack.addArrangedSubview(hintLabel)
        row.addArrangedSubview(labelStack)
        labelStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        row.addArrangedSubview(flexSpacer())

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: 12)
        popup.target = self
        popup.action = action
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        row.addArrangedSubview(popup)

        return (row, hintLabel, popup)
    }

    private func refreshScreenshotQualityControls() {
        refreshScreenshotQualityPopup(screenshotQualitySavePopup, selected: Defaults.screenshotSaveQuality)
        refreshScreenshotQualityPopup(screenshotQualityClipboardPopup, selected: Defaults.screenshotClipboardQuality)
        screenshotQualitySaveHintLabel?.stringValue = Defaults.screenshotSaveQuality.localizedHint
        screenshotQualityClipboardHintLabel?.stringValue = Defaults.screenshotClipboardQuality.localizedHint
    }

    private func refreshScreenshotQualityPopup(
        _ popup: NSPopUpButton?,
        selected: ScreenshotImageQuality
    ) {
        guard let popup else { return }
        popup.removeAllItems()
        for quality in ScreenshotImageQuality.allCases {
            popup.addItem(withTitle: quality.localizedTitle)
            popup.lastItem?.representedObject = quality.rawValue
        }
        if let index = ScreenshotImageQuality.allCases.firstIndex(of: selected) {
            popup.selectItem(at: index)
        }
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 11)
        return button
    }

    private func shortcutCard(for slot: ShortcutSlot) -> NSView {
        let card = CardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let title = makeSectionHeader(slot.title)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let displayContainer = NSView()
        displayContainer.wantsLayer = true
        displayContainer.layer?.cornerRadius = 7
        displayContainer.layer?.cornerCurve = .continuous
        displayContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        displayContainer.translatesAutoresizingMaskIntoConstraints = false
        displayContainer.widthAnchor.constraint(equalToConstant: 96).isActive = true
        displayContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let display = NSTextField(labelWithString: slot.currentDisplay)
        display.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        display.textColor = .white
        display.alignment = .center
        display.lineBreakMode = .byTruncatingTail
        display.translatesAutoresizingMaskIntoConstraints = false
        displayContainer.addSubview(display)
        NSLayoutConstraint.activate([
            display.leadingAnchor.constraint(greaterThanOrEqualTo: displayContainer.leadingAnchor, constant: 8),
            display.trailingAnchor.constraint(lessThanOrEqualTo: displayContainer.trailingAnchor, constant: -8),
            display.centerXAnchor.constraint(equalTo: displayContainer.centerXAnchor),
            display.centerYAnchor.constraint(equalTo: displayContainer.centerYAnchor),
        ])

        let setButton = makeButton(title: L10n.shortcutSet, action: #selector(shortcutSetClicked(_:)))
        setButton.tag = slot.rawValue
        let restoreButton = makeButton(title: L10n.shortcutRestore, action: #selector(shortcutRestoreClicked(_:)))
        restoreButton.tag = slot.rawValue

        row.addArrangedSubview(title)
        row.addArrangedSubview(flexSpacer())
        row.addArrangedSubview(displayContainer)
        row.addArrangedSubview(setButton)
        row.addArrangedSubview(restoreButton)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        displayContainer.setContentHuggingPriority(.required, for: .horizontal)
        displayContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
        setButton.setContentHuggingPriority(.required, for: .horizontal)
        restoreButton.setContentHuggingPriority(.required, for: .horizontal)

        shortcutRows[slot] = ShortcutRowViews(display: display, setButton: setButton, restoreButton: restoreButton)
        card.embed(stack)
        return card
    }

    private func refreshShortcutRows() {
        for (slot, views) in shortcutRows {
            let isRecording = activeShortcutSlot == slot
            views.display.stringValue = isRecording ? L10n.shortcutWaiting : slot.currentDisplay
            views.setButton.title = isRecording ? L10n.shortcutCancel : L10n.shortcutSet
            views.restoreButton.isEnabled = slot.hasCustomShortcut && !isRecording
        }
    }

    @objc private func shortcutSetClicked(_ sender: NSButton) {
        guard let slot = ShortcutSlot(rawValue: sender.tag) else { return }
        if activeShortcutSlot == slot {
            cancelShortcutRecording()
        } else {
            beginShortcutRecording(slot)
        }
    }

    @objc private func shortcutRestoreClicked(_ sender: NSButton) {
        guard let slot = ShortcutSlot(rawValue: sender.tag) else { return }
        slot.clearShortcut()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshShortcutRows()
    }

    private func beginShortcutRecording(_ slot: ShortcutSlot) {
        cancelShortcutRecording()
        activeShortcutSlot = slot
        window?.makeFirstResponder(self)
        refreshShortcutRows()
        shortcutRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.recordShortcut(event) == true ? nil : event
        }
    }

    private func recordShortcut(_ event: NSEvent) -> Bool {
        guard let slot = activeShortcutSlot else { return false }
        if event.keyCode == 53 {
            cancelShortcutRecording()
            return true
        }

        let keyCode = Int(event.keyCode)
        let modifiers = HotkeyManager.legacyModifiers(from: event.modifierFlags)
        if slot.requiresRegisteredHotkey,
           modifiers == 0,
           !HotkeyManager.isFunctionKey(event.keyCode) {
            return true
        }
        if let conflict = ShortcutSlot.allCases.first(where: {
            $0 != slot && $0.effectiveKeyCode == keyCode && $0.effectiveModifiers == modifiers
        }) {
            showShortcutConflict(conflict.message)
            return true
        }

        let binding = EditorShortcutBinding(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        if let conflict = EditorShortcutAction.allCases.first(where: { action in
            if slot == .fileSave, action == .toolbar(.save) { return false }
            if slot == .clipboard, action == .toolbar(.confirm) { return false }
            return EditorShortcutRegistry.binding(for: action)?.conflicts(with: binding) == true
        }) {
            showShortcutConflict(L10n.editorShortcutConflict(conflict.localizedTitle))
            return true
        }
        slot.setShortcut(keyCode: keyCode, modifiers: modifiers)
        if let monitor = shortcutRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutRecordingMonitor = nil
        }
        activeShortcutSlot = nil
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refreshShortcutRows()
        return true
    }

    private func showShortcutConflict(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.shortcutConflictTitle
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSWindow()) { _ in }
    }

    @objc private func languagePicked(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard AppLanguage.allCases.indices.contains(index) else { return }
        Defaults.language = AppLanguage.allCases[index]
    }

    @objc private func menuBarToggled(_ sender: NSSwitch) {
        let visible = sender.state == .on
        Defaults.showMenuBar = visible
        onMenuBarToggle?(visible)
    }

    @objc private func launchAtLoginToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        if !LaunchAtLogin.setEnabled(enabled) {
            sender.state = LaunchAtLogin.isEnabled ? .on : .off
        }
    }

    @objc private func pinAcrossSpacesToggled(_ sender: NSSwitch) {
        Defaults.pinAcrossSpaces = sender.state == .on
    }

    @objc private func systemScreenshotAutoOpenToggled(_ sender: NSSwitch) {
        if sender.state == .on {
            if SystemScreenshotLocationManager.shared.isTargetLocationActive {
                Defaults.systemScreenshotAutoOpenEnabled = true
                refreshSystemScreenshotAutoOpenControls()
            } else {
                sender.state = .off
                presentSystemScreenshotSetup()
            }
            return
        }

        guard SystemScreenshotLocationManager.shared.isAutomaticallyManaged else {
            Defaults.systemScreenshotAutoOpenEnabled = false
            refreshSystemScreenshotAutoOpenControls()
            return
        }

        sender.state = .on
        presentSystemScreenshotDisableConfirmation()
    }

    @objc private func configureSystemScreenshotAutoOpen() {
        presentSystemScreenshotSetup()
    }

    @objc private func revealSystemScreenshotFolder() {
        SystemScreenshotAutoOpen.revealDirectory()
    }

    private func presentSystemScreenshotSetup() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.systemScreenshotSetupTitle
        alert.informativeText = L10n.systemScreenshotSetupMessage
        alert.addButton(withTitle: L10n.systemScreenshotSetupAutomatic)
        alert.addButton(withTitle: L10n.systemScreenshotSetupManual)
        alert.addButton(withTitle: L10n.systemScreenshotSetupCancel)
        beginAlert(alert) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                let wasAlreadyConfigured = SystemScreenshotLocationManager.shared.isTargetLocationActive
                guard SystemScreenshotLocationManager.shared.configureAutomatically() else {
                    self.presentSystemScreenshotConfigurationFailure()
                    self.refreshSystemScreenshotAutoOpenControls()
                    return
                }
                if !wasAlreadyConfigured {
                    SystemScreenshotAutoOpen.refreshSystemScreenshotServices()
                }
                Defaults.systemScreenshotAutoOpenEnabled = true
                self.refreshSystemScreenshotAutoOpenControls()
            case .alertSecondButtonReturn:
                guard SystemScreenshotAutoOpen.ensureDirectoryExists() else {
                    self.presentSystemScreenshotConfigurationFailure()
                    return
                }
                Defaults.systemScreenshotAutoOpenEnabled = true
                SystemScreenshotAutoOpen.revealDirectory()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    SystemScreenshotAutoOpen.openScreenshotTool()
                }
                self.refreshSystemScreenshotAutoOpenControls()
            default:
                self.refreshSystemScreenshotAutoOpenControls()
            }
        }
    }

    private func presentSystemScreenshotDisableConfirmation() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.systemScreenshotDisableTitle
        alert.informativeText = L10n.systemScreenshotDisableMessage
        alert.addButton(withTitle: L10n.systemScreenshotDisableRestore)
        alert.addButton(withTitle: L10n.systemScreenshotDisableKeep)
        alert.addButton(withTitle: L10n.systemScreenshotSetupCancel)
        beginAlert(alert) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                let result = SystemScreenshotLocationManager.shared.restoreAutomaticallyConfiguredLocation()
                switch result {
                case .restored:
                    SystemScreenshotAutoOpen.refreshSystemScreenshotServices()
                    Defaults.systemScreenshotAutoOpenEnabled = false
                case .notManaged, .changedExternally:
                    Defaults.systemScreenshotAutoOpenEnabled = false
                case .failed:
                    self.presentSystemScreenshotRestoreFailure()
                }
            case .alertSecondButtonReturn:
                SystemScreenshotLocationManager.shared.relinquishAutomaticallyManagedLocation()
                Defaults.systemScreenshotAutoOpenEnabled = false
            default:
                break
            }
            self.refreshSystemScreenshotAutoOpenControls()
        }
    }

    private func presentSystemScreenshotConfigurationFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.systemScreenshotSetupFailedTitle
        alert.informativeText = L10n.systemScreenshotSetupFailedMessage
        alert.addButton(withTitle: L10n.systemScreenshotSetupCancel)
        beginAlert(alert) { _ in }
    }

    private func presentSystemScreenshotRestoreFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.systemScreenshotRestoreFailedTitle
        alert.informativeText = L10n.systemScreenshotRestoreFailedMessage
        alert.addButton(withTitle: L10n.systemScreenshotSetupCancel)
        beginAlert(alert) { _ in }
    }

    private func beginAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    @objc private func refreshSystemScreenshotAutoOpenControls() {
        systemScreenshotAutoOpenSwitch?.state = Defaults.systemScreenshotAutoOpenEnabled ? .on : .off
        let isConfigured = SystemScreenshotLocationManager.shared.isTargetLocationActive
        systemScreenshotStatusLabel?.stringValue = isConfigured
            ? L10n.systemScreenshotFolderConfigured
            : L10n.systemScreenshotFolderNeedsSetup
        systemScreenshotStatusLabel?.textColor = isConfigured
            ? NSColor.systemGreen.withAlphaComponent(0.86)
            : NSColor.systemOrange.withAlphaComponent(0.86)
        systemScreenshotSetupButton?.isEnabled = true
    }

    @objc private func autoRevealToggled(_ sender: NSSwitch) {
        Defaults.autoRevealSavedFiles = sender.state == .on
    }

    @objc private func historyCacheToggled(_ sender: NSSwitch) {
        Defaults.historyCacheEnabled = sender.state == .on
        historyCacheSlider?.isEnabled = Defaults.historyCacheEnabled
        updateHistoryPanelModeControlsEnabled()
    }

    @objc private func clipboardTextCacheToggled(_ sender: NSSwitch) {
        Defaults.clipboardTextCacheEnabled = sender.state == .on
        clipboardTextHistoryLimitSlider?.isEnabled = Defaults.clipboardTextCacheEnabled
        updateHistoryPanelModeControlsEnabled()
    }

    @objc private func historyNotchTriggerChanged(_ sender: NSPopUpButton) {
        let modes = Defaults.HistoryNotchTriggerMode.allCases
        guard modes.indices.contains(sender.indexOfSelectedItem) else { return }
        Defaults.historyNotchTriggerMode = modes[sender.indexOfSelectedItem]
    }

    @objc private func historyPanelModeOptionClicked(_ sender: HistoryPanelModeOptionView) {
        guard Defaults.isHistoryCacheAvailable else { return }
        switch sender.mode {
        case .dialog:
            Defaults.historyPanelDialogEnabled = true
        case .notch:
            guard Defaults.historyPanelNotchAvailable else {
                updateHistoryPanelModeControlsEnabled()
                return
            }
            Defaults.historyPanelNotchEnabled = true
        }
        updateHistoryPanelModeControlsEnabled()
    }

    @objc private func screenParametersChanged() {
        updateHistoryPanelModeControlsEnabled()
    }

    @objc private func historyLimitChanged(_ sender: NSSlider) {
        guard Defaults.historyCacheEnabled else {
            sender.doubleValue = Double(Defaults.historyCacheLimit)
            return
        }
        Defaults.historyCacheLimit = Int(sender.doubleValue.rounded())
        let normalizedValue = Defaults.historyCacheLimit
        sender.doubleValue = Double(normalizedValue)
        historyCacheValueLabel?.stringValue = "\(normalizedValue)"
    }

    @objc private func clipboardTextHistoryLimitChanged(_ sender: NSSlider) {
        guard Defaults.clipboardTextCacheEnabled else {
            sender.doubleValue = Double(Defaults.clipboardTextHistoryLimit)
            return
        }
        Defaults.clipboardTextHistoryLimit = Int(sender.doubleValue.rounded())
        let normalizedValue = Defaults.clipboardTextHistoryLimit
        sender.doubleValue = Double(normalizedValue)
        clipboardTextHistoryLimitValueLabel?.stringValue = "\(normalizedValue)"
    }

    @objc private func screenshotSaveQualityChanged(_ sender: NSPopUpButton) {
        guard let quality = selectedScreenshotQuality(from: sender) else { return }
        Defaults.screenshotSaveQuality = quality
        refreshScreenshotQualityControls()
    }

    @objc private func screenshotClipboardQualityChanged(_ sender: NSPopUpButton) {
        guard let quality = selectedScreenshotQuality(from: sender) else { return }
        Defaults.screenshotClipboardQuality = quality
        refreshScreenshotQualityControls()
    }

    private func selectedScreenshotQuality(from sender: NSPopUpButton) -> ScreenshotImageQuality? {
        guard let raw = sender.selectedItem?.representedObject as? String else { return nil }
        return ScreenshotImageQuality(rawValue: raw)
    }

    @objc private func chooseSavePath() {
        let panel = NSOpenPanel()
        panel.title = L10n.chooseScreenshotSavePathTitle
        panel.prompt = L10n.savePathChoose
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Defaults.screenshotSaveDirectory
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Defaults.screenshotSaveDirectory = url
            self?.savePathValueLabel?.stringValue = SaveDestination.displayPath(url)
        }
    }

    @objc private func revealSavePath() {
        let url = Defaults.screenshotSaveDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openRepositoryLink(_ sender: NSButton) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let url = URL(string: rawValue)
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSourceRepo() {
        guard let url = URL(string: "https://github.com/realskyrin/clipcap") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func aboutUpdateButtonClicked() {
        switch UpdateChecker.shared.state {
        case .available(let version):
            StatusBarController.presentUpdateAvailableAlertAfterRefresh(fallbackVersion: version)
        case .installFailed:
            if let url = UpdateChecker.shared.latestPageURL {
                NSWorkspace.shared.open(url)
            }
        default:
            UpdateChecker.shared.check(manual: true)
        }
    }

    @objc private func refreshUpdateRow() {
        guard let statusLabel = aboutUpdateStatusLabel,
              let button = aboutUpdateButton
        else { return }

        let muted = NSColor.white.withAlphaComponent(0.58)
        let accent = NSColor(calibratedRed: 0.42, green: 0.66, blue: 0.98, alpha: 1.0)
        let warning = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.45, alpha: 1.0)

        switch UpdateChecker.shared.state {
        case .idle:
            statusLabel.stringValue = appVersionDisplayString()
            statusLabel.textColor = muted
            button.title = L10n.checkForUpdates
            button.isEnabled = true
        case .checking:
            statusLabel.stringValue = L10n.updateChecking
            statusLabel.textColor = muted
            button.title = L10n.checkForUpdates
            button.isEnabled = false
        case .upToDate:
            statusLabel.stringValue = L10n.updateUpToDateStatus
            statusLabel.textColor = muted
            button.title = L10n.checkForUpdates
            button.isEnabled = true
        case .available(let version):
            statusLabel.stringValue = L10n.updateNewVersionStatus(version)
            statusLabel.textColor = accent
            button.title = L10n.updateInstallNowButton
            button.isEnabled = true
        case .downloading(_, let fraction):
            statusLabel.stringValue = L10n.updateDownloadingStatus(Int(fraction * 100))
            statusLabel.textColor = accent
            button.title = L10n.updateInstallNowButton
            button.isEnabled = false
        case .installing:
            statusLabel.stringValue = L10n.updateInstallingStatus
            statusLabel.textColor = accent
            button.title = L10n.updateInstallNowButton
            button.isEnabled = false
        case .failed:
            statusLabel.stringValue = L10n.updateFailedStatus
            statusLabel.textColor = warning
            button.title = L10n.updateRetryButton
            button.isEnabled = true
        case .installFailed:
            statusLabel.stringValue = L10n.updateInstallFailedStatus
            statusLabel.textColor = warning
            button.title = L10n.updateDownloadButton
            button.isEnabled = true
        }
    }

    @objc private func languageChanged() {
        for tab in SettingsTab.allCases {
            tabButtons[tab]?.refreshTitle()
        }
        updateFooterAction()
        selectTab(selectedTab)
    }
}

private struct ShortcutRowViews {
    let display: NSTextField
    let setButton: NSButton
    let restoreButton: NSButton
}

enum ShortcutSlot: Int, CaseIterable {
    case clipboard
    case copyPath
    case fileSave
    case previousHistoryImage
    case nextHistoryImage
    case selectedImageEdit
    case clipboardImageEdit
    case selectedImagePin
    case clipboardImagePin
    case historyPanel
    case imageMerge

    var title: String {
        switch self {
        case .selectedImageEdit: return L10n.selectedImageEditShortcutHeader
        case .clipboardImageEdit: return L10n.clipboardImageEditShortcutHeader
        case .selectedImagePin: return L10n.selectedImagePinShortcutHeader
        case .clipboardImagePin: return L10n.clipboardImagePinShortcutHeader
        case .clipboard: return L10n.clipboardShortcutHeader
        case .copyPath: return L10n.copyPathShortcutHeader
        case .fileSave: return L10n.fileSaveShortcutHeader
        case .previousHistoryImage: return L10n.previousHistoryImageShortcutHeader
        case .nextHistoryImage: return L10n.nextHistoryImageShortcutHeader
        case .historyPanel: return L10n.historyPanelShortcutHeader
        case .imageMerge: return L10n.imageMergeShortcutHeader
        }
    }

    var hint: String {
        switch self {
        case .selectedImageEdit: return L10n.selectedImageEditShortcutHint
        case .clipboardImageEdit: return L10n.clipboardImageEditShortcutHint
        case .selectedImagePin: return ""
        case .clipboardImagePin: return ""
        case .clipboard: return L10n.clipboardShortcutHint
        case .copyPath: return L10n.copyPathShortcutHint
        case .fileSave: return L10n.fileSaveShortcutHint
        case .previousHistoryImage: return L10n.previousHistoryImageShortcutHint
        case .nextHistoryImage: return L10n.nextHistoryImageShortcutHint
        case .historyPanel: return L10n.historyPanelShortcutHint
        case .imageMerge: return ""
        }
    }

    var currentDisplay: String {
        if let keyCode = effectiveKeyCode, let modifiers = effectiveModifiers {
            return HotkeyManager.displayString(keyCode: keyCode, modifiers: modifiers)
        }
        return defaultDisplay
    }

    var defaultDisplay: String {
        switch self {
        case .selectedImageEdit: return L10n.selectedImageEditShortcutDefaultDisplay
        case .clipboardImageEdit: return L10n.clipboardImageEditShortcutDefaultDisplay
        case .selectedImagePin: return L10n.selectedImagePinShortcutDefaultDisplay
        case .clipboardImagePin: return L10n.clipboardImagePinShortcutDefaultDisplay
        case .copyPath: return L10n.historyPanelShortcutDefaultDisplay
        case .historyPanel: return L10n.historyPanelShortcutDefaultDisplay
        case .imageMerge: return L10n.imageMergeShortcutDefaultDisplay
        default: return L10n.historyPanelShortcutDefaultDisplay
        }
    }

    var message: String {
        switch self {
        case .selectedImageEdit: return L10n.shortcutConflictSelectedImageEdit
        case .clipboardImageEdit: return L10n.shortcutConflictClipboardImageEdit
        case .selectedImagePin: return L10n.shortcutConflictSelectedImagePin
        case .clipboardImagePin: return L10n.shortcutConflictClipboardImagePin
        case .clipboard: return L10n.shortcutConflictClipboard
        case .copyPath: return L10n.shortcutConflictCopyPath
        case .fileSave: return L10n.shortcutConflictFileSave
        case .previousHistoryImage: return L10n.shortcutConflictPreviousHistoryImage
        case .nextHistoryImage: return L10n.shortcutConflictNextHistoryImage
        case .historyPanel: return L10n.shortcutConflictHistoryPanel
        case .imageMerge: return L10n.shortcutConflictImageMerge
        }
    }

    var hasCustomShortcut: Bool {
        switch self {
        case .selectedImageEdit: return Defaults.hasCustomSelectedImageEditHotkey
        case .clipboardImageEdit: return Defaults.hasCustomClipboardImageEditHotkey
        case .selectedImagePin: return Defaults.hasCustomSelectedImagePinHotkey
        case .clipboardImagePin: return Defaults.hasCustomClipboardImagePinHotkey
        case .clipboard: return Defaults.hasCustomClipboardHotkey
        case .copyPath: return Defaults.hasCustomCopyPathHotkey
        case .fileSave: return Defaults.hasCustomFileSaveHotkey
        case .previousHistoryImage: return Defaults.hasCustomPreviousHistoryImageHotkey
        case .nextHistoryImage: return Defaults.hasCustomNextHistoryImageHotkey
        case .historyPanel: return Defaults.hasCustomHistoryPanelHotkey
        case .imageMerge: return Defaults.hasCustomImageMergeHotkey
        }
    }

    var effectiveKeyCode: Int? {
        if hasCustomShortcut {
            switch self {
            case .selectedImageEdit: return Defaults.selectedImageEditHotkeyKeyCode
            case .clipboardImageEdit: return Defaults.clipboardImageEditHotkeyKeyCode
            case .selectedImagePin: return Defaults.selectedImagePinHotkeyKeyCode
            case .clipboardImagePin: return Defaults.clipboardImagePinHotkeyKeyCode
            case .clipboard: return Defaults.clipboardHotkeyKeyCode
            case .copyPath: return Defaults.copyPathHotkeyKeyCode
            case .fileSave: return Defaults.fileSaveHotkeyKeyCode
            case .previousHistoryImage: return Defaults.previousHistoryImageHotkeyKeyCode
            case .nextHistoryImage: return Defaults.nextHistoryImageHotkeyKeyCode
            case .historyPanel: return Defaults.historyPanelHotkeyKeyCode
            case .imageMerge: return Defaults.imageMergeHotkeyKeyCode
            }
        }
        switch self {
        case .selectedImageEdit, .clipboardImageEdit, .selectedImagePin, .clipboardImagePin:
            return nil
        case .clipboard: return 36
        case .copyPath: return nil
        case .fileSave: return 1
        case .previousHistoryImage: return 43
        case .nextHistoryImage: return 47
        case .historyPanel, .imageMerge: return nil
        }
    }

    var effectiveModifiers: Int? {
        if hasCustomShortcut {
            switch self {
            case .selectedImageEdit: return Defaults.selectedImageEditHotkeyModifiers
            case .clipboardImageEdit: return Defaults.clipboardImageEditHotkeyModifiers
            case .selectedImagePin: return Defaults.selectedImagePinHotkeyModifiers
            case .clipboardImagePin: return Defaults.clipboardImagePinHotkeyModifiers
            case .clipboard: return Defaults.clipboardHotkeyModifiers
            case .copyPath: return Defaults.copyPathHotkeyModifiers
            case .fileSave: return Defaults.fileSaveHotkeyModifiers
            case .previousHistoryImage: return Defaults.previousHistoryImageHotkeyModifiers
            case .nextHistoryImage: return Defaults.nextHistoryImageHotkeyModifiers
            case .historyPanel: return Defaults.historyPanelHotkeyModifiers
            case .imageMerge: return Defaults.imageMergeHotkeyModifiers
            }
        }
        switch self {
        case .selectedImageEdit, .clipboardImageEdit, .selectedImagePin, .clipboardImagePin:
            return nil
        case .clipboard: return 0
        case .copyPath: return nil
        case .fileSave: return 256
        case .previousHistoryImage: return 0
        case .nextHistoryImage: return 0
        case .historyPanel, .imageMerge: return nil
        }
    }

    func setShortcut(keyCode: Int, modifiers: Int) {
        switch self {
        case .selectedImageEdit:
            Defaults.selectedImageEditHotkeyKeyCode = keyCode
            Defaults.selectedImageEditHotkeyModifiers = modifiers
        case .clipboardImageEdit:
            Defaults.clipboardImageEditHotkeyKeyCode = keyCode
            Defaults.clipboardImageEditHotkeyModifiers = modifiers
        case .selectedImagePin:
            Defaults.selectedImagePinHotkeyKeyCode = keyCode
            Defaults.selectedImagePinHotkeyModifiers = modifiers
        case .clipboardImagePin:
            Defaults.clipboardImagePinHotkeyKeyCode = keyCode
            Defaults.clipboardImagePinHotkeyModifiers = modifiers
        case .clipboard:
            Defaults.clipboardHotkeyKeyCode = keyCode
            Defaults.clipboardHotkeyModifiers = modifiers
        case .copyPath:
            Defaults.copyPathHotkeyKeyCode = keyCode
            Defaults.copyPathHotkeyModifiers = modifiers
        case .fileSave:
            Defaults.fileSaveHotkeyKeyCode = keyCode
            Defaults.fileSaveHotkeyModifiers = modifiers
        case .previousHistoryImage:
            Defaults.previousHistoryImageHotkeyKeyCode = keyCode
            Defaults.previousHistoryImageHotkeyModifiers = modifiers
        case .nextHistoryImage:
            Defaults.nextHistoryImageHotkeyKeyCode = keyCode
            Defaults.nextHistoryImageHotkeyModifiers = modifiers
        case .historyPanel:
            Defaults.historyPanelHotkeyKeyCode = keyCode
            Defaults.historyPanelHotkeyModifiers = modifiers
        case .imageMerge:
            Defaults.imageMergeHotkeyKeyCode = keyCode
            Defaults.imageMergeHotkeyModifiers = modifiers
        }
    }

    func clearShortcut() {
        switch self {
        case .selectedImageEdit: Defaults.clearSelectedImageEditHotkey()
        case .clipboardImageEdit: Defaults.clearClipboardImageEditHotkey()
        case .selectedImagePin: Defaults.clearSelectedImagePinHotkey()
        case .clipboardImagePin: Defaults.clearClipboardImagePinHotkey()
        case .clipboard: Defaults.clearClipboardHotkey()
        case .copyPath: Defaults.clearCopyPathHotkey()
        case .fileSave: Defaults.clearFileSaveHotkey()
        case .previousHistoryImage: Defaults.clearPreviousHistoryImageHotkey()
        case .nextHistoryImage: Defaults.clearNextHistoryImageHotkey()
        case .historyPanel: Defaults.clearHistoryPanelHotkey()
        case .imageMerge: Defaults.clearImageMergeHotkey()
        }
    }

    var requiresRegisteredHotkey: Bool {
        switch self {
        case .selectedImageEdit, .clipboardImageEdit, .selectedImagePin, .clipboardImagePin, .historyPanel, .imageMerge:
            return true
        case .clipboard, .copyPath, .fileSave, .previousHistoryImage, .nextHistoryImage:
            return false
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class SidebarPanel: NSView {
    private var gradientLayer: CAGradientLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 1

        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(calibratedRed: 0.11, green: 0.17, blue: 0.25, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.18, alpha: 1.0).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.cornerRadius = 22
        layer?.insertSublayer(gradient, at: 0)
        gradientLayer = gradient
    }

    override func layout() {
        super.layout()
        gradientLayer?.frame = bounds
    }
}

private final class DetailPanel: NSView {
    private var gradientLayer: CAGradientLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.cornerCurve = .continuous
        layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1

        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.cornerRadius = 24
        layer?.insertSublayer(gradient, at: 0)
        gradientLayer = gradient
    }

    override func layout() {
        super.layout()
        gradientLayer?.frame = bounds
    }
}

private final class TabButton: NSControl {
    let tab: SettingsTab
    private let iconChip = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?

    var isSelectedTab: Bool = false {
        didSet { updateAppearance() }
    }

    init(tab: SettingsTab, target: AnyObject?, action: Selector?) {
        self.tab = tab
        super.init(frame: .zero)
        self.target = target
        self.action = action
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        iconChip.translatesAutoresizingMaskIntoConstraints = false
        iconChip.wantsLayer = true
        iconChip.layer?.cornerRadius = 8
        iconChip.layer?.cornerCurve = .continuous
        iconChip.layer?.borderWidth = 1
        addSubview(iconChip)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown
        iconChip.addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.stringValue = tab.title
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),

            iconChip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconChip.widthAnchor.constraint(equalToConstant: 28),
            iconChip.heightAnchor.constraint(equalToConstant: 28),

            iconView.centerXAnchor.constraint(equalTo: iconChip.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconChip.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconChip.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshTitle() {
        label.stringValue = tab.title
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelectedTab {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelectedTab {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override var acceptsFirstResponder: Bool { true }

    private func updateAppearance() {
        if isSelectedTab {
            layer?.backgroundColor = NSColor(calibratedRed: 0.22, green: 0.40, blue: 0.85, alpha: 1.0).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            layer?.borderWidth = 1
            label.textColor = .white
            iconChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            iconChip.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
            iconView.contentTintColor = .white
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            label.textColor = NSColor.white.withAlphaComponent(0.82)
            iconChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            iconChip.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            iconView.contentTintColor = tab.iconTint
        }
    }
}

private final class ActionButton: NSControl {
    private let iconChip = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private var tint: NSColor = .systemGreen

    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        iconChip.translatesAutoresizingMaskIntoConstraints = false
        iconChip.wantsLayer = true
        iconChip.layer?.cornerRadius = 8
        iconChip.layer?.cornerCurve = .continuous
        iconChip.layer?.borderWidth = 1
        addSubview(iconChip)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyDown
        iconChip.addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),

            iconChip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconChip.widthAnchor.constraint(equalToConstant: 28),
            iconChip.heightAnchor.constraint(equalToConstant: 28),

            iconView.centerXAnchor.constraint(equalTo: iconChip.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconChip.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconChip.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])

        configure(title: title, symbolName: symbolName)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, symbolName: String) {
        tint = symbolName == "power" && title == L10n.quitApp ? .systemRed : .systemGreen
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        label.stringValue = title
        updateAppearance()
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1.0 : 0.45 }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        sendAction(action, to: target)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    }

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEnabled, event.charactersIgnoringModifiers == "\r" {
            sendAction(action, to: target)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.clear.cgColor
        iconChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        iconChip.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        iconView.contentTintColor = tint
        label.textColor = tint
    }
}

private final class HistoryPanelModePreviewView: NSView {
    var mode: HistoryPanelSettingsMode {
        didSet { needsDisplay = true }
    }

    var isEffectEnabled: Bool = true {
        didSet { needsDisplay = true }
    }

    private let accentBlue = NSColor(
        calibratedRed: 0x11 / 255.0,
        green: 0x7D / 255.0,
        blue: 0xFF / 255.0,
        alpha: 1.0
    )
    private let surfaceColor = NSColor.black

    init(mode: HistoryPanelSettingsMode) {
        self.mode = mode
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }

        let rect = bounds
        let backdrop = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        ctx.saveGraphicsState()
        backdrop.addClip()

        NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.18, alpha: 1).setFill()
        backdrop.fill()
        ctx.cgContext.setAlpha(isEffectEnabled ? 1 : 0.42)
        switch mode {
        case .dialog:
            drawDialogPreview(in: rect.insetBy(dx: 24, dy: 18))
        case .notch:
            drawNotchPreview(in: rect.insetBy(dx: 24, dy: 0))
        }
        ctx.restoreGraphicsState()

        NSColor.white.withAlphaComponent(isEffectEnabled ? 0.08 : 0.04).setStroke()
        backdrop.lineWidth = 1
        backdrop.stroke()
    }

    private func drawDialogPreview(in rect: NSRect) {
        let panelWidth = min(rect.width * 0.82, 560)
        let panelHeight = min(rect.height - 14, 86)
        let panelRect = NSRect(
            x: rect.midX - panelWidth / 2,
            y: rect.midY - panelHeight / 2 - 6,
            width: panelWidth,
            height: panelHeight
        )
        drawFloatingSurface(in: panelRect, radius: 18, shadow: true)
        drawToolbarLine(in: panelRect)
        drawTileRow(in: panelRect.insetBy(dx: 18, dy: 16), count: 4)
    }

    private func drawNotchPreview(in rect: NSRect) {
        let panelWidth = min(rect.width * 0.88, 620)
        let panelHeight = min(rect.height * 0.78, 106)
        let panelRect = NSRect(
            x: rect.midX - panelWidth / 2,
            y: rect.maxY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )

        drawTopAttachedSurface(in: panelRect)
        drawToolbarLine(in: panelRect, leadingInset: 36)
        drawTileRow(in: panelRect.insetBy(dx: 34, dy: 16), count: 5)
    }

    private func drawFloatingSurface(in rect: NSRect, radius: CGFloat, shadow: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        if shadow {
            let panelShadow = NSShadow()
            panelShadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
            panelShadow.shadowBlurRadius = 18
            panelShadow.shadowOffset = NSSize(width: 0, height: -6)
            panelShadow.set()
        }
        surfaceColor.withAlphaComponent(0.92).setFill()
        path.fill()
        ctx.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawTopAttachedSurface(in rect: NSRect) {
        let path = notchPath(in: rect, flare: 14, bottomRadius: 18)
        surfaceColor.withAlphaComponent(0.92).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawToolbarLine(in panelRect: NSRect, leadingInset: CGFloat = 18) {
        let y = panelRect.maxY - 22
        let active = NSRect(x: panelRect.minX + leadingInset, y: y, width: 46, height: 10)
        accentBlue.setFill()
        NSBezierPath(roundedRect: active, xRadius: 5, yRadius: 5).fill()

        var x = active.maxX + 10
        for _ in 0..<3 {
            let pill = NSRect(x: x, y: y, width: 34, height: 10)
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
            x += 44
        }
    }

    private func drawTileRow(in rect: NSRect, count: Int) {
        let contentRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(28, rect.height - 28)
        )
        let gap: CGFloat = 10
        let tileWidth = max(34, (contentRect.width - gap * CGFloat(count - 1)) / CGFloat(count))
        for index in 0..<count {
            let tileRect = NSRect(
                x: contentRect.minX + CGFloat(index) * (tileWidth + gap),
                y: contentRect.minY,
                width: tileWidth,
                height: contentRect.height
            )
            NSColor.white.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: tileRect, xRadius: 8, yRadius: 8).fill()

            let bar = NSRect(
                x: tileRect.minX + 8,
                y: tileRect.midY - 4,
                width: max(18, tileRect.width - 16),
                height: 8
            )
            (index == 0 ? accentBlue : NSColor.white.withAlphaComponent(0.24)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
        }
    }

    private func notchPath(in rect: NSRect, flare: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
        let flare = max(0, min(flare, rect.width * 0.25, rect.height))
        let bodyLeft = rect.minX + flare
        let bodyRight = rect.maxX - flare
        let bottom = max(0, min(bottomRadius, (bodyRight - bodyLeft) * 0.5, rect.height))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.curve(
            to: NSPoint(x: bodyRight, y: rect.maxY - flare),
            controlPoint1: NSPoint(x: rect.maxX - flare * 0.5, y: rect.maxY),
            controlPoint2: NSPoint(x: bodyRight, y: rect.maxY - flare * 0.5)
        )
        path.line(to: NSPoint(x: bodyRight, y: rect.minY + bottom))
        path.curve(
            to: NSPoint(x: bodyRight - bottom, y: rect.minY),
            controlPoint1: NSPoint(x: bodyRight, y: rect.minY + bottom * 0.45),
            controlPoint2: NSPoint(x: bodyRight - bottom * 0.45, y: rect.minY)
        )
        path.line(to: NSPoint(x: bodyLeft + bottom, y: rect.minY))
        path.curve(
            to: NSPoint(x: bodyLeft, y: rect.minY + bottom),
            controlPoint1: NSPoint(x: bodyLeft + bottom * 0.45, y: rect.minY),
            controlPoint2: NSPoint(x: bodyLeft, y: rect.minY + bottom * 0.45)
        )
        path.line(to: NSPoint(x: bodyLeft, y: rect.maxY - flare))
        path.curve(
            to: NSPoint(x: rect.minX, y: rect.maxY),
            controlPoint1: NSPoint(x: bodyLeft, y: rect.maxY - flare * 0.5),
            controlPoint2: NSPoint(x: rect.minX + flare * 0.5, y: rect.maxY)
        )
        path.close()
        return path
    }
}

private final class HistoryPanelModeOptionView: NSControl {
    let mode: HistoryPanelSettingsMode
    let title: NSTextField
    let subtitle: NSTextField

    var isSelected: Bool = false {
        didSet { applyAppearance() }
    }

    override var isEnabled: Bool {
        didSet { applyAppearance() }
    }

    private let checkView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { applyAppearance() }
    }

    private let accentBlue = NSColor(
        calibratedRed: 0x11 / 255.0,
        green: 0x7D / 255.0,
        blue: 0xFF / 255.0,
        alpha: 1.0
    )

    init(mode: HistoryPanelSettingsMode, title: String, subtitle: String) {
        self.mode = mode
        self.title = NSTextField(labelWithString: title)
        self.subtitle = NSTextField(wrappingLabelWithString: subtitle)
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title.stringValue)
        setAccessibilityHelp(subtitle.stringValue)

        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.isEditable = false
        title.isSelectable = false
        title.refusesFirstResponder = true
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitle.isEditable = false
        subtitle.isSelectable = false
        subtitle.refusesFirstResponder = true
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitle)

        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        checkView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        checkView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(checkView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92),

            checkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            checkView.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            checkView.widthAnchor.constraint(equalToConstant: 18),
            checkView.heightAnchor.constraint(equalToConstant: 18),

            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            title.trailingAnchor.constraint(lessThanOrEqualTo: checkView.leadingAnchor, constant: -8),

            subtitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            subtitle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])

        setContentCompressionResistancePriority(.required, for: .vertical)
        applyAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        guard let result else { return nil }
        return result === self ? result : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        sendAction(action, to: target)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        sendAction(action, to: target)
        return true
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        let keyCode = Int(event.keyCode)
        if keyCode == kVK_Space || keyCode == kVK_Return {
            sendAction(action, to: target)
        } else {
            super.keyDown(with: event)
        }
    }

    private func applyAppearance() {
        let enabledAlpha: CGFloat = isEnabled ? 1 : 0.42
        let backgroundAlpha: CGFloat
        if isSelected {
            backgroundAlpha = 0.052
        } else if isHovered {
            backgroundAlpha = 0.044
        } else {
            backgroundAlpha = 0.018
        }

        layer?.backgroundColor = NSColor.white.withAlphaComponent(backgroundAlpha * enabledAlpha).cgColor
        layer?.borderColor = (isSelected ? accentBlue : NSColor.white.withAlphaComponent(0.09 * enabledAlpha)).cgColor
        layer?.borderWidth = isSelected ? 2 : 1

        title.textColor = NSColor.white.withAlphaComponent(isEnabled ? 0.94 : 0.4)
        subtitle.textColor = NSColor.white.withAlphaComponent(isEnabled ? 0.58 : 0.35)
        checkView.isHidden = !isSelected
        checkView.contentTintColor = accentBlue.withAlphaComponent(enabledAlpha)
        setAccessibilityValue(isSelected ? 1 : 0)
    }
}

private final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1
    }

    func embed(_ content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }
}
