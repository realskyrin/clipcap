import AppKit

enum SettingsTab: CaseIterable {
    case general
    case shortcuts
    case toolbar
    case upload
    case translation
    case about

    var title: String {
        switch self {
        case .general: return L10n.settingsTabGeneral
        case .shortcuts: return L10n.settingsTabShortcuts
        case .toolbar: return L10n.settingsTabToolbar
        case .upload: return L10n.settingsTabUpload
        case .translation: return L10n.settingsTabTranslation
        case .about: return L10n.settingsTabAbout
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "keyboard.fill"
        case .toolbar: return "slider.horizontal.3"
        case .upload: return "icloud.and.arrow.up.fill"
        case .translation: return "character.bubble.fill"
        case .about: return "info.circle.fill"
        }
    }

    var iconTint: NSColor {
        switch self {
        case .general: return .systemGreen
        case .shortcuts: return .systemOrange
        case .toolbar: return .systemPurple
        case .upload: return .systemBlue
        case .translation: return .systemTeal
        case .about: return .systemIndigo
        }
    }
}

final class SettingsView: NSView {
    var isStartup: Bool = false
    var onMenuBarToggle: ((Bool) -> Void)?
    var onLaunch: (() -> Void)?

    private let sidebarPanel = SidebarPanel()
    private let detailPanel = DetailPanel()
    private let sidebarStack = NSStackView()
    private let detailTitleLabel = NSTextField(labelWithString: "")
    private let detailSubtitleLabel = NSTextField(labelWithString: "")
    private let detailScrollView = NSScrollView()
    private let paneDocumentView = FlippedView()
    private let footerActionButton = ActionButton(title: "", symbolName: "power")

    private var tabButtons: [SettingsTab: TabButton] = [:]
    private var selectedTab: SettingsTab = .general
    private var currentPane: NSView?

    private var languagePicker: NSPopUpButton?
    private var menuBarSwitch: NSSwitch?
    private var launchAtLoginSwitch: NSSwitch?
    private var pinAcrossSpacesSwitch: NSSwitch?
    private var historyCacheSwitch: NSSwitch?
    private var historyCacheSlider: NSSlider?
    private var historyCacheValueLabel: NSTextField?
    private var autoRevealSwitch: NSSwitch?
    private var savePathValueLabel: NSTextField?

    private var shortcutRows: [ShortcutSlot: ShortcutRowViews] = [:]
    private var activeShortcutSlot: ShortcutSlot?
    private var shortcutRecordingMonitor: Any?

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
        layer?.sublayers?.first?.frame = bounds
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
    func closeTransientPanels() {}

    func cancelShortcutRecording() {
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
            NSColor(calibratedRed: 0.075, green: 0.095, blue: 0.13, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.105, green: 0.13, blue: 0.18, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.frame = bounds
        layer?.addSublayer(gradient)
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
            sidebarPanel.widthAnchor.constraint(equalToConstant: 224),

            detailPanel.leadingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor, constant: 12),
            detailPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            detailPanel.topAnchor.constraint(equalTo: topAnchor, constant: 38),
            detailPanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    private func buildSidebar() {
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 8
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.addSubview(sidebarStack)

        let brandStack = NSStackView()
        brandStack.orientation = .vertical
        brandStack.alignment = .leading
        brandStack.spacing = 3
        brandStack.translatesAutoresizingMaskIntoConstraints = false

        let brand = NSTextField(labelWithString: "clipcap")
        brand.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        brand.textColor = .white
        let tagline = NSTextField(labelWithString: L10n.settingsNoPermissionsNeeded)
        tagline.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        tagline.textColor = NSColor.white.withAlphaComponent(0.48)
        brandStack.addArrangedSubview(brand)
        brandStack.addArrangedSubview(tagline)
        sidebarStack.addArrangedSubview(brandStack)
        sidebarStack.setCustomSpacing(18, after: brandStack)

        for tab in SettingsTab.allCases {
            let button = TabButton(tab: tab, target: self, action: #selector(tabClicked(_:)))
            button.tag = SettingsTab.allCases.firstIndex(of: tab) ?? 0
            tabButtons[tab] = button
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        sidebarStack.addArrangedSubview(spacer)
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        footerActionButton.target = self
        footerActionButton.action = #selector(footerActionClicked)
        sidebarStack.addArrangedSubview(footerActionButton)
        footerActionButton.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
        updateFooterAction()

        NSLayoutConstraint.activate([
            sidebarStack.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor, constant: 16),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor, constant: -16),
            sidebarStack.topAnchor.constraint(equalTo: sidebarPanel.topAnchor, constant: 18),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebarPanel.bottomAnchor, constant: -16),
        ])
    }

    private func buildDetailPanel() {
        detailTitleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        detailTitleLabel.textColor = .white
        detailTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailSubtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        detailSubtitleLabel.textColor = NSColor.white.withAlphaComponent(0.48)
        detailSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailScrollView.borderType = .noBorder
        detailScrollView.drawsBackground = false
        detailScrollView.hasVerticalScroller = true
        detailScrollView.autohidesScrollers = true
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailScrollView.documentView = paneDocumentView
        paneDocumentView.translatesAutoresizingMaskIntoConstraints = false

        detailPanel.addSubview(detailTitleLabel)
        detailPanel.addSubview(detailSubtitleLabel)
        detailPanel.addSubview(detailScrollView)

        NSLayoutConstraint.activate([
            detailTitleLabel.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor, constant: 28),
            detailTitleLabel.topAnchor.constraint(equalTo: detailPanel.topAnchor, constant: 24),

            detailSubtitleLabel.leadingAnchor.constraint(equalTo: detailTitleLabel.leadingAnchor),
            detailSubtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailPanel.trailingAnchor, constant: -28),
            detailSubtitleLabel.topAnchor.constraint(equalTo: detailTitleLabel.bottomAnchor, constant: 3),

            detailScrollView.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor),
            detailScrollView.topAnchor.constraint(equalTo: detailSubtitleLabel.bottomAnchor, constant: 16),
            detailScrollView.bottomAnchor.constraint(equalTo: detailPanel.bottomAnchor),

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

    @objc private func tabClicked(_ sender: NSButton) {
        let tabs = SettingsTab.allCases
        guard tabs.indices.contains(sender.tag) else { return }
        selectTab(tabs[sender.tag])
    }

    private func selectTab(_ tab: SettingsTab) {
        selectedTab = tab
        detailTitleLabel.stringValue = tab.title
        detailSubtitleLabel.stringValue = subtitle(for: tab)
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
            pane = wrapPane(ToolbarSettingsPane(), horizontalInset: 20)
        case .upload:
            pane = wrapPane(UploadSettingsPane(), horizontalInset: 22)
        case .translation:
            pane = wrapPane(TranslationSettingsPane(), horizontalInset: 22)
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

    private func subtitle(for tab: SettingsTab) -> String {
        switch tab {
        case .general: return L10n.settingsSubtitleGeneral
        case .shortcuts: return L10n.settingsSubtitleShortcuts
        case .toolbar: return L10n.settingsSubtitleToolbar
        case .upload: return L10n.settingsSubtitleUpload
        case .translation: return L10n.settingsSubtitleTranslation
        case .about: return L10n.settingsSubtitleAbout
        }
    }

    private func wrapPane(_ content: NSView, horizontalInset: CGFloat = 26) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: horizontalInset),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -horizontalInset),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -24),
        ])
        return wrapper
    }

    private func makeGeneralPane() -> NSView {
        let stack = paneStack()

        let languageCard = CardView()
        let languageStack = cardStack()
        languageStack.addArrangedSubview(makeSectionHeader(L10n.languageHeader))
        let picker = NSPopUpButton()
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
        languagePicker = picker
        languageStack.addArrangedSubview(picker)
        languageCard.embed(languageStack)
        addCard(languageCard, to: stack)

        let togglesCard = CardView()
        let toggles = cardStack(spacing: 0)
        toggles.addArrangedSubview(switchRow(title: L10n.showMenuBarIcon, subtitle: nil, isOn: Defaults.showMenuBar, action: #selector(menuBarToggled(_:))) { self.menuBarSwitch = $0 })
        toggles.addArrangedSubview(rowDivider())
        toggles.addArrangedSubview(switchRow(title: L10n.launchAtLogin, subtitle: nil, isOn: LaunchAtLogin.isEnabled, action: #selector(launchAtLoginToggled(_:))) { self.launchAtLoginSwitch = $0 })
        toggles.addArrangedSubview(rowDivider())
        toggles.addArrangedSubview(switchRow(title: L10n.pinAcrossSpaces, subtitle: L10n.pinAcrossSpacesHint, isOn: Defaults.pinAcrossSpaces, action: #selector(pinAcrossSpacesToggled(_:))) { self.pinAcrossSpacesSwitch = $0 })
        toggles.addArrangedSubview(rowDivider())
        toggles.addArrangedSubview(switchRow(title: L10n.autoRevealSavedFilesLabel, subtitle: L10n.autoRevealSavedFilesHint, isOn: Defaults.autoRevealSavedFiles, action: #selector(autoRevealToggled(_:))) { self.autoRevealSwitch = $0 })
        togglesCard.embed(toggles)
        addCard(togglesCard, to: stack)

        let historyCard = CardView()
        let history = cardStack(spacing: 0)
        history.addArrangedSubview(switchRow(title: L10n.historyCacheToggleLabel, subtitle: L10n.historyCacheToggleHint, isOn: Defaults.historyCacheEnabled, action: #selector(historyCacheToggled(_:))) { self.historyCacheSwitch = $0 })
        history.addArrangedSubview(rowDivider())
        history.addArrangedSubview(makeSliderRow())
        historyCard.embed(history)
        addCard(historyCard, to: stack)

        let savePathCard = CardView()
        let savePath = cardStack()
        savePath.addArrangedSubview(makeSectionHeader(L10n.savePathTitle))
        savePath.addArrangedSubview(makeBody(L10n.savePathSubtitle))
        savePath.addArrangedSubview(makeSavePathRow())
        savePathCard.embed(savePath)
        addCard(savePathCard, to: stack)

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
        let card = CardView()
        let about = cardStack(spacing: 10)
        about.addArrangedSubview(makeSectionHeader("clipcap"))
        about.addArrangedSubview(makeBody("Image annotation for clipboard, files, drag input, and Open With"))
        about.addArrangedSubview(makeBody("Bundle ID cn.skyrin.clipcap"))
        about.addArrangedSubview(makeBody("Repository github.com/realskyrin/clipcap"))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        about.addArrangedSubview(makeBody("Version \(version)"))

        let sourceButton = makeButton(title: L10n.aboutSourceCode, action: #selector(openSourceCode))
        about.addArrangedSubview(sourceButton)
        card.embed(about)
        addCard(card, to: stack)
        return wrapPane(stack)
    }

    private func paneStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
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

    private func makeSectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.94)
        return label
    }

    private func makeBody(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.white.withAlphaComponent(0.6)
        label.maximumNumberOfLines = 0
        return label
    }

    private func switchRow(
        title: String,
        subtitle: String?,
        isOn: Bool,
        action: Selector,
        capture: (NSSwitch) -> Void
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(makeSectionHeader(title))
        if let subtitle {
            textStack.addArrangedSubview(makeBody(subtitle))
        }

        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = action
        capture(toggle)

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(toggle)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true
        return row
    }

    private func rowDivider() -> NSView {
        let divider = NSBox()
        divider.boxType = .separator
        divider.alphaValue = 0.35
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func makeSliderRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(makeSectionHeader(L10n.historyCacheLabel))
        textStack.addArrangedSubview(makeBody(L10n.historyCacheHint))

        let slider = NSSlider(
            value: Double(Defaults.historyCacheLimit),
            minValue: Double(Defaults.historyCacheMin),
            maxValue: Double(Defaults.historyCacheMax),
            target: self,
            action: #selector(historyLimitChanged(_:))
        )
        slider.numberOfTickMarks = ((Defaults.historyCacheMax - Defaults.historyCacheMin) / Defaults.historyCacheStep) + 1
        slider.allowsTickMarkValuesOnly = true
        slider.isEnabled = Defaults.historyCacheEnabled
        historyCacheSlider = slider

        let value = NSTextField(labelWithString: "\(Defaults.historyCacheLimit)")
        value.textColor = NSColor.white.withAlphaComponent(0.7)
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        historyCacheValueLabel = value

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(value)
        textStack.setContentHuggingPriority(.required, for: .horizontal)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        value.setContentHuggingPriority(.required, for: .horizontal)
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        return row
    }

    private func makeSavePathRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let pathLabel = NSTextField(labelWithString: SaveDestination.displayPath(Defaults.screenshotSaveDirectory))
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        savePathValueLabel = pathLabel

        let choose = makeButton(title: L10n.savePathChoose, action: #selector(chooseSavePath))
        let reveal = makeButton(title: L10n.savePathReveal, action: #selector(revealSavePath))

        row.addArrangedSubview(pathLabel)
        row.addArrangedSubview(choose)
        row.addArrangedSubview(reveal)
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        choose.setContentHuggingPriority(.required, for: .horizontal)
        reveal.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    private func shortcutCard(for slot: ShortcutSlot) -> NSView {
        let card = CardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        let title = makeSectionHeader(slot.title)
        let hint = makeBody(slot.hint)
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(hint)
        hint.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 12
        controls.translatesAutoresizingMaskIntoConstraints = false

        let display = NSTextField(labelWithString: slot.currentDisplay)
        display.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        display.textColor = .white
        display.alignment = .center
        display.wantsLayer = true
        display.layer?.cornerRadius = 7
        display.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        display.translatesAutoresizingMaskIntoConstraints = false
        display.widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
        display.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let setButton = makeButton(title: L10n.shortcutSet, action: #selector(shortcutSetClicked(_:)))
        setButton.tag = slot.rawValue
        let restoreButton = makeButton(title: L10n.shortcutRestore, action: #selector(shortcutRestoreClicked(_:)))
        restoreButton.tag = slot.rawValue

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(controls)
        controls.addArrangedSubview(spacer)
        controls.addArrangedSubview(display)
        controls.addArrangedSubview(setButton)
        controls.addArrangedSubview(restoreButton)
        textStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        controls.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        display.setContentHuggingPriority(.required, for: .horizontal)
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
        if let conflict = ShortcutSlot.allCases.first(where: {
            $0 != slot && $0.effectiveKeyCode == keyCode && $0.effectiveModifiers == modifiers
        }) {
            showShortcutConflict(conflict.message)
            return true
        }

        slot.setShortcut(keyCode: keyCode, modifiers: modifiers)
        if let monitor = shortcutRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutRecordingMonitor = nil
        }
        activeShortcutSlot = nil
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

    @objc private func autoRevealToggled(_ sender: NSSwitch) {
        Defaults.autoRevealSavedFiles = sender.state == .on
    }

    @objc private func historyCacheToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        Defaults.historyCacheEnabled = enabled
        historyCacheSlider?.isEnabled = enabled
    }

    @objc private func historyLimitChanged(_ sender: NSSlider) {
        Defaults.historyCacheLimit = Int(sender.doubleValue.rounded())
        historyCacheValueLabel?.stringValue = "\(Defaults.historyCacheLimit)"
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

    @objc private func openSourceCode() {
        guard let url = URL(string: "https://github.com/realskyrin/clipcap") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func languageChanged() {
        for tab in SettingsTab.allCases {
            tabButtons[tab]?.title = tab.title
            tabButtons[tab]?.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.title)
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

private enum ShortcutSlot: Int, CaseIterable {
    case clipboard
    case fileSave
    case previousHistoryImage
    case nextHistoryImage
    case historyPanel

    var title: String {
        switch self {
        case .clipboard: return L10n.clipboardShortcutHeader
        case .fileSave: return L10n.fileSaveShortcutHeader
        case .previousHistoryImage: return L10n.previousHistoryImageShortcutHeader
        case .nextHistoryImage: return L10n.nextHistoryImageShortcutHeader
        case .historyPanel: return L10n.historyPanelShortcutHeader
        }
    }

    var hint: String {
        switch self {
        case .clipboard: return L10n.clipboardShortcutHint
        case .fileSave: return L10n.fileSaveShortcutHint
        case .previousHistoryImage: return L10n.previousHistoryImageShortcutHint
        case .nextHistoryImage: return L10n.nextHistoryImageShortcutHint
        case .historyPanel: return L10n.historyPanelShortcutHint
        }
    }

    var currentDisplay: String {
        if let keyCode = effectiveKeyCode, let modifiers = effectiveModifiers {
            return HotkeyManager.displayString(keyCode: keyCode, modifiers: modifiers)
        }
        return L10n.historyPanelShortcutDefaultDisplay
    }

    var message: String {
        switch self {
        case .clipboard: return L10n.shortcutConflictClipboard
        case .fileSave: return L10n.shortcutConflictFileSave
        case .previousHistoryImage: return L10n.shortcutConflictPreviousHistoryImage
        case .nextHistoryImage: return L10n.shortcutConflictNextHistoryImage
        case .historyPanel: return L10n.shortcutConflictHistoryPanel
        }
    }

    var hasCustomShortcut: Bool {
        switch self {
        case .clipboard: return Defaults.hasCustomClipboardHotkey
        case .fileSave: return Defaults.hasCustomFileSaveHotkey
        case .previousHistoryImage: return Defaults.hasCustomPreviousHistoryImageHotkey
        case .nextHistoryImage: return Defaults.hasCustomNextHistoryImageHotkey
        case .historyPanel: return Defaults.hasCustomHistoryPanelHotkey
        }
    }

    var effectiveKeyCode: Int? {
        if hasCustomShortcut {
            switch self {
            case .clipboard: return Defaults.clipboardHotkeyKeyCode
            case .fileSave: return Defaults.fileSaveHotkeyKeyCode
            case .previousHistoryImage: return Defaults.previousHistoryImageHotkeyKeyCode
            case .nextHistoryImage: return Defaults.nextHistoryImageHotkeyKeyCode
            case .historyPanel: return Defaults.historyPanelHotkeyKeyCode
            }
        }
        switch self {
        case .clipboard: return 36
        case .fileSave: return 1
        case .previousHistoryImage: return 43
        case .nextHistoryImage: return 47
        case .historyPanel: return nil
        }
    }

    var effectiveModifiers: Int? {
        if hasCustomShortcut {
            switch self {
            case .clipboard: return Defaults.clipboardHotkeyModifiers
            case .fileSave: return Defaults.fileSaveHotkeyModifiers
            case .previousHistoryImage: return Defaults.previousHistoryImageHotkeyModifiers
            case .nextHistoryImage: return Defaults.nextHistoryImageHotkeyModifiers
            case .historyPanel: return Defaults.historyPanelHotkeyModifiers
            }
        }
        switch self {
        case .clipboard: return 256
        case .fileSave: return 256
        case .previousHistoryImage: return 0
        case .nextHistoryImage: return 0
        case .historyPanel: return nil
        }
    }

    func setShortcut(keyCode: Int, modifiers: Int) {
        switch self {
        case .clipboard:
            Defaults.clipboardHotkeyKeyCode = keyCode
            Defaults.clipboardHotkeyModifiers = modifiers
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
        }
    }

    func clearShortcut() {
        switch self {
        case .clipboard: Defaults.clearClipboardHotkey()
        case .fileSave: Defaults.clearFileSaveHotkey()
        case .previousHistoryImage: Defaults.clearPreviousHistoryImageHotkey()
        case .nextHistoryImage: Defaults.clearNextHistoryImageHotkey()
        case .historyPanel: Defaults.clearHistoryPanelHotkey()
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class SidebarPanel: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .sidebar
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class DetailPanel: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .underWindowBackground
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TabButton: NSButton {
    private let tab: SettingsTab
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false

    var isSelectedTab: Bool = false {
        didSet { updateAppearance() }
    }

    init(tab: SettingsTab, target: AnyObject?, action: Selector?) {
        self.tab = tab
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = tab.title
        image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.title)
        imagePosition = .imageLeading
        alignment = .left
        isBordered = false
        bezelStyle = .regularSquare
        font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 42).isActive = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.cornerRadius = 12
        if isSelectedTab {
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.28).cgColor
            contentTintColor = .white
        } else if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            contentTintColor = tab.iconTint.withAlphaComponent(0.95)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            contentTintColor = NSColor.white.withAlphaComponent(0.68)
        }
    }
}

private final class ActionButton: NSButton {
    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        imagePosition = .imageLeading
        alignment = .center
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 38).isActive = true
        configure(title: title, symbolName: symbolName)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, symbolName: String) {
        self.title = title
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        contentTintColor = .white
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }
}

private final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func embed(_ content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }
}
