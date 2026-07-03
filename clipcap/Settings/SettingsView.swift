import AppKit

enum SettingsTab: CaseIterable {
    case general
    case shortcuts
    case toolbar
    case about

    var title: String {
        switch self {
        case .general: return L10n.settingsTabGeneral
        case .shortcuts: return L10n.settingsTabShortcuts
        case .toolbar: return L10n.settingsTabToolbar
        case .about: return L10n.settingsTabAbout
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "keyboard.fill"
        case .toolbar: return "slider.horizontal.3"
        case .about: return "info.circle.fill"
        }
    }

    var iconTint: NSColor {
        switch self {
        case .general: return NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.72, alpha: 1.0)
        case .shortcuts: return NSColor(calibratedRed: 0.36, green: 0.66, blue: 0.98, alpha: 1.0)
        case .toolbar: return NSColor(calibratedRed: 0.95, green: 0.54, blue: 0.62, alpha: 1.0)
        case .about: return NSColor(calibratedRed: 0.70, green: 0.56, blue: 0.96, alpha: 1.0)
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
            pane = wrapPane(ToolbarSettingsPane())
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
        addFullWidth(rowDivider(), to: history)
        addFullWidth(makeSliderRow(), to: history)
        addCard(historyCard, to: stack)

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
        about.addArrangedSubview(makeBody(L10n.aboutTagline))
        about.addArrangedSubview(makeBody(L10n.aboutDescription))
        about.addArrangedSubview(makeBody(L10n.aboutBundleID("cn.skyrin.clipcap")))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        about.addArrangedSubview(makeBody(L10n.aboutVersion(version)))

        about.addArrangedSubview(makeRepositorySection())
        card.embed(about)
        addCard(card, to: stack)
        return wrapPane(stack)
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

    private func makeSliderRow() -> NSView {
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

        let hint = secondaryLabel(L10n.historyCacheHint, wrapping: true)

        addFullWidth(header, to: stack)
        addFullWidth(slider, to: stack)
        addFullWidth(hint, to: stack)
        return stack
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

    @objc private func openRepositoryLink(_ sender: NSButton) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let url = URL(string: rawValue)
        else { return }
        NSWorkspace.shared.open(url)
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
