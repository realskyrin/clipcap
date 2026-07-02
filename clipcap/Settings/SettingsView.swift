import AppKit

enum SettingsTab: CaseIterable {
    case general
    case toolbar
    case upload
    case translation
    case about

    var title: String {
        switch self {
        case .general: return L10n.settingsTabGeneral
        case .toolbar: return L10n.settingsTabToolbar
        case .upload: return L10n.settingsTabUpload
        case .translation: return L10n.settingsTabTranslation
        case .about: return L10n.settingsTabAbout
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .toolbar: return "slider.horizontal.3"
        case .upload: return "icloud.and.arrow.up.fill"
        case .translation: return "character.bubble.fill"
        case .about: return "info.circle.fill"
        }
    }
}

final class SettingsView: NSView {
    var isStartup: Bool = false
    var onMenuBarToggle: ((Bool) -> Void)?
    var onLaunch: (() -> Void)?

    private let sidebarStack = NSStackView()
    private let contentContainer = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var tabButtons: [SettingsTab: NSButton] = [:]
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

    init(frame frameRect: NSRect, isStartup: Bool) {
        self.isStartup = isStartup
        super.init(frame: frameRect)
        buildUI()
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
        NotificationCenter.default.removeObserver(self)
    }

    func setStartupMode(_ startup: Bool) {
        isStartup = startup
    }

    func showPermissionsTab() {
        selectTab(.general)
    }

    func cancelShortcutRecording() {}
    func cancelSelectedImagePinShortcutRecording() {}
    func cancelClipboardImagePinShortcutRecording() {}
    func cancelSelectedImageEditShortcutRecording() {}
    func cancelClipboardImageEditShortcutRecording() {}
    func cancelClipboardShortcutRecording() {}
    func cancelFileSaveShortcutRecording() {}
    func closeTransientPanels() {}

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.16, alpha: 1.0).cgColor

        let root = NSStackView()
        root.orientation = .horizontal
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        root.addArrangedSubview(sidebar)

        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 8
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        for tab in SettingsTab.allCases {
            let button = makeTabButton(tab)
            tabButtons[tab] = button
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
        }

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(content)

        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),

            sidebar.widthAnchor.constraint(equalToConstant: 176),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 64),

            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),

            contentContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            contentContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func makeTabButton(_ tab: SettingsTab) -> NSButton {
        let button = NSButton(title: tab.title, target: self, action: #selector(tabClicked(_:)))
        button.tag = SettingsTab.allCases.firstIndex(of: tab) ?? 0
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.alignment = .left
        button.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.title)
        button.imagePosition = .imageLeading
        button.contentTintColor = NSColor.white.withAlphaComponent(0.86)
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    @objc private func tabClicked(_ sender: NSButton) {
        let tabs = SettingsTab.allCases
        guard tabs.indices.contains(sender.tag) else { return }
        selectTab(tabs[sender.tag])
    }

    private func selectTab(_ tab: SettingsTab) {
        selectedTab = tab
        titleLabel.stringValue = tab.title
        for (buttonTab, button) in tabButtons {
            button.contentTintColor = buttonTab == tab ? .systemGreen : NSColor.white.withAlphaComponent(0.86)
        }
        currentPane?.removeFromSuperview()
        let pane: NSView
        switch tab {
        case .general:
            pane = makeGeneralPane()
        case .toolbar:
            pane = scrollPane(wrapping: ToolbarSettingsPane())
        case .upload:
            pane = scrollPane(wrapping: UploadSettingsPane())
        case .translation:
            pane = scrollPane(wrapping: TranslationSettingsPane())
        case .about:
            pane = makeAboutPane()
        }
        currentPane = pane
        pane.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            pane.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            pane.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private func makeGeneralPane() -> NSView {
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        let intro = cardStack()
        intro.addArrangedSubview(makeTitle("clipcap"))
        intro.addArrangedSubview(makeBody("Open clipboard images, files, drag input, and Open With"))
        stack.addArrangedSubview(card(containing: intro))

        let languageCard = cardStack()
        languageCard.addArrangedSubview(makeTitle(L10n.languageHeader))
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
        languageCard.addArrangedSubview(picker)
        stack.addArrangedSubview(card(containing: languageCard))

        let switches = cardStack()
        switches.addArrangedSubview(switchRow(title: L10n.showMenuBarIcon, subtitle: nil, isOn: Defaults.showMenuBar, action: #selector(menuBarToggled(_:))) { self.menuBarSwitch = $0 })
        switches.addArrangedSubview(switchRow(title: L10n.launchAtLogin, subtitle: nil, isOn: LaunchAtLogin.isEnabled, action: #selector(launchAtLoginToggled(_:))) { self.launchAtLoginSwitch = $0 })
        switches.addArrangedSubview(switchRow(title: L10n.pinAcrossSpaces, subtitle: L10n.pinAcrossSpacesHint, isOn: Defaults.pinAcrossSpaces, action: #selector(pinAcrossSpacesToggled(_:))) { self.pinAcrossSpacesSwitch = $0 })
        switches.addArrangedSubview(switchRow(title: L10n.autoRevealSavedFilesLabel, subtitle: L10n.autoRevealSavedFilesHint, isOn: Defaults.autoRevealSavedFiles, action: #selector(autoRevealToggled(_:))) { self.autoRevealSwitch = $0 })
        stack.addArrangedSubview(card(containing: switches))

        let history = cardStack()
        history.addArrangedSubview(switchRow(title: L10n.historyCacheToggleLabel, subtitle: L10n.historyCacheToggleHint, isOn: Defaults.historyCacheEnabled, action: #selector(historyCacheToggled(_:))) { self.historyCacheSwitch = $0 })
        let sliderRow = makeSliderRow()
        history.addArrangedSubview(sliderRow)
        stack.addArrangedSubview(card(containing: history))

        let savePath = cardStack()
        savePath.addArrangedSubview(makeTitle(L10n.savePathTitle))
        savePath.addArrangedSubview(makeBody(L10n.savePathSubtitle))
        savePath.addArrangedSubview(makeSavePathRow())
        stack.addArrangedSubview(card(containing: savePath))

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -28),
        ])
        return scrollPane(wrapping: documentView)
    }

    private func makeAboutPane() -> NSView {
        let stack = cardStack()

        stack.addArrangedSubview(makeTitle("clipcap"))
        stack.addArrangedSubview(makeBody("Image annotation for clipboard and files"))
        stack.addArrangedSubview(makeBody("Bundle ID cn.skyrin.clipcap"))
        stack.addArrangedSubview(makeBody("Repository github.com/realskyrin/clipcap"))

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        stack.addArrangedSubview(makeBody("Version \(version)"))

        let sourceButton = NSButton(title: L10n.aboutSourceCode, target: self, action: #selector(openSourceCode))
        sourceButton.bezelStyle = .rounded
        stack.addArrangedSubview(sourceButton)

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        let aboutCard = card(containing: stack)
        wrapper.addSubview(aboutCard)
        NSLayoutConstraint.activate([
            aboutCard.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 28),
            aboutCard.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -28),
            aboutCard.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
            aboutCard.bottomAnchor.constraint(lessThanOrEqualTo: wrapper.bottomAnchor, constant: -28),
        ])
        return scrollPane(wrapping: wrapper)
    }

    private func scrollPane(wrapping view: NSView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        return scrollView
    }

    private func card(containing content: NSView) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 8
        wrapper.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
        wrapper.layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        wrapper.layer?.borderWidth = 1
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -14),
        ])
        return wrapper
    }

    private func cardStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.94)
        return label
    }

    private func makeBody(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.white.withAlphaComponent(0.62)
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
        row.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(makeTitle(title))
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
        return row
    }

    private func makeSliderRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let title = makeTitle(L10n.historyCacheLabel)
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

        row.addArrangedSubview(title)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(value)
        title.setContentHuggingPriority(.required, for: .horizontal)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        value.setContentHuggingPriority(.required, for: .horizontal)
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

        let choose = NSButton(title: L10n.savePathChoose, target: self, action: #selector(chooseSavePath))
        choose.bezelStyle = .rounded
        let reveal = NSButton(title: L10n.savePathReveal, target: self, action: #selector(revealSavePath))
        reveal.bezelStyle = .rounded

        row.addArrangedSubview(pathLabel)
        row.addArrangedSubview(choose)
        row.addArrangedSubview(reveal)
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        choose.setContentHuggingPriority(.required, for: .horizontal)
        reveal.setContentHuggingPriority(.required, for: .horizontal)
        return row
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
        selectTab(selectedTab)
    }
}
