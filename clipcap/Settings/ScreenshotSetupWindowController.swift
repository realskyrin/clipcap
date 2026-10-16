import AppKit

private final class ScreenshotSetupWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Explains the file handoff before explicitly changing the system destination.
/// Merely opening or dismissing this guide never changes screenshot preferences.
final class ScreenshotSetupWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ScreenshotSetupWindowController()

    private enum Step: Int { case welcome, folder, ready }
    private var step: Step = .welcome
    private var hasConfigurationError = false
    private var locationTimer: Timer?
    private var lastLocationActive = false
    private var verificationStartedAt: Date?
    private var hasReceivedTestScreenshot = false
    private let root = NSView()
    private let progress = NSStackView()
    private let content = NSStackView()
    private let primary = NSButton()
    private let back = NSButton()
    private let later = NSButton()

    private init() {
        let window = ScreenshotSetupWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 660),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.minSize = NSSize(width: 680, height: 600)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.16, alpha: 1)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildLayout()
        NotificationCenter.default.addObserver(self, selector: #selector(locationMayHaveChanged),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
                                               name: .languageDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(testScreenshotImported(_:)),
                                               name: .systemScreenshotImageImported, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showIfNeeded() {
        if Defaults.screenshotSetupGuidePresented,
           Defaults.systemScreenshotVerifiedDirectory == SystemScreenshotAutoOpen.directoryURL.path,
           SystemScreenshotLocationManager.shared.isTargetLocationActive { return }
        showGuide()
    }

    func showGuide() {
        if window?.isVisible != true {
            step = .welcome
            hasConfigurationError = false
            verificationStartedAt = nil
            hasReceivedTestScreenshot = false
        }
        Defaults.screenshotSetupGuidePresented = true
        render()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startLocationChecks()
    }

    private func buildLayout() {
        window?.contentView = root
        // Keep the window stable while rebuilding the step's arranged subviews.
        // Window minSize alone does not constrain AppKit's automatic fitting pass.
        root.widthAnchor.constraint(greaterThanOrEqualToConstant: 680).isActive = true
        root.heightAnchor.constraint(greaterThanOrEqualToConstant: 578).isActive = true
        progress.orientation = .horizontal
        progress.distribution = .fillEqually
        progress.spacing = 12

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = ScreenshotSetupDocumentView()
        scroll.documentView = document
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18
        document.addSubview(content)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        for (button, action) in [(later, #selector(dismissGuide)), (back, #selector(goBack)),
                                 (primary, #selector(advance))] {
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.target = self
            button.action = action
        }
        primary.keyEquivalent = "\r"
        footer.addArrangedSubview(later)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(back)
        footer.addArrangedSubview(primary)

        for view in [progress, scroll, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        document.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: root.topAnchor, constant: 32),
            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            progress.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            progress.heightAnchor.constraint(equalToConstant: 56),
            scroll.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 24),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -18),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8)
        ])
    }

    private func render() {
        let previousFrame = window?.frame
        defer {
            root.layoutSubtreeIfNeeded()
            if let previousFrame { window?.setFrame(previousFrame, display: true) }
        }
        window?.title = L10n.screenshotGuideTitle
        clear(progress)
        clear(content)
        let titles = [L10n.screenshotGuideStepWelcome, L10n.screenshotGuideStepFolder, L10n.screenshotGuideStepReady]
        for (index, title) in titles.enumerated() {
            progress.addArrangedSubview(stepCard(index: index, title: title))
        }

        let active = SystemScreenshotLocationManager.shared.isTargetLocationActive
        lastLocationActive = active
        let verified = active && hasReceivedTestScreenshot
        primary.isEnabled = step != .ready || verified
        primary.keyEquivalent = primary.isEnabled ? "\r" : ""
        let symbols = ["sparkles", "folder.badge.gearshape", verified ? "checkmark.circle.fill" : "exclamationmark.circle.fill"]
        let icon = NSImageView(image: NSImage(systemSymbolName: symbols[step.rawValue], accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = step == .ready ? (verified ? .systemGreen : .systemOrange) : .controlAccentColor
        icon.symbolConfiguration = .init(pointSize: 34, weight: .medium)
        icon.heightAnchor.constraint(equalToConstant: 42).isActive = true
        content.addArrangedSubview(icon)

        switch step {
        case .welcome:
            add(text(L10n.screenshotGuideWelcomeTitle, size: 26, weight: .bold))
            add(text(L10n.screenshotGuideWelcomeBody, size: 14, secondary: true))
            add(card([
                text(L10n.screenshotGuideFlow, size: 16, weight: .semibold),
                text(L10n.screenshotGuideWhy, size: 13, secondary: true)
            ]))
            add(text(L10n.screenshotGuideFilePolicy, size: 12, secondary: true))
            primary.title = L10n.screenshotGuideBegin
        case .folder:
            add(text(L10n.screenshotGuideFolderTitle, size: 26, weight: .bold))
            add(text(L10n.screenshotGuideFolderBody, size: 14, secondary: true))
            let path = text(SaveDestination.displayPath(SystemScreenshotAutoOpen.directoryURL), size: 13, weight: .medium)
            path.isSelectable = true
            let status = text(L10n.screenshotGuideFolderSelected, size: 12)
            status.textColor = .secondaryLabelColor
            add(card([text(L10n.systemScreenshotFolderLabel, size: 14, weight: .semibold), path, status]))
            add(text(L10n.screenshotGuideFolderNext, size: 12, secondary: true))
            if hasConfigurationError {
                let error = text(L10n.systemScreenshotSetupFailedMessage, size: 13)
                error.textColor = .systemOrange
                add(error)
            }
            content.addArrangedSubview(button(L10n.screenshotGuideChangeDirectory, #selector(changeDirectory)))
            primary.title = L10n.screenshotGuideContinue
        case .ready:
            add(text(verified ? L10n.screenshotGuideReadyTitle : L10n.screenshotGuideRequiredTitle, size: 26, weight: .bold))
            add(text(verified ? L10n.screenshotGuideReadyBody : L10n.screenshotGuideRequiredBody, size: 14, secondary: true))
            let setup = button(L10n.screenshotGuideSetSystem, #selector(showSystemScreenshotGuide))
            setup.controlSize = .large
            setup.bezelColor = .controlAccentColor
            setup.contentTintColor = .white
            if !verified { setup.keyEquivalent = "\r" }
            let verify = button(L10n.screenshotGuideVerify, #selector(verifyScreenshot))
            verify.isEnabled = active
            let status = text(verified ? L10n.screenshotGuideVerified
                              : (active ? L10n.screenshotGuideLocationMatched : L10n.screenshotGuideFolderPending), size: 13, weight: .medium)
            status.textColor = active ? .systemGreen : .systemOrange
            add(card([setup, status, text(L10n.screenshotGuideVerifyHint, size: 13, secondary: true), verify]))
            add(card([
                text("⇧⌘4", size: 30, weight: .medium),
                text(L10n.screenshotGuideShortcutHint, size: 13, secondary: true),
                text(L10n.screenshotGuideRecordingHint, size: 13, secondary: true)
            ]))
            add(text(L10n.screenshotGuideReopen, size: 12, secondary: true))
            primary.title = L10n.screenshotGuideFinish
        }
        back.title = L10n.screenshotGuideBack
        back.isHidden = step == .welcome
        later.title = L10n.screenshotGuideLater
        later.isHidden = step == .ready
    }

    @objc private func advance() {
        switch step {
        case .welcome:
            step = .folder
        case .folder:
            guard SystemScreenshotAutoOpen.ensureDirectoryExists() else {
                hasConfigurationError = true
                render()
                return
            }
            hasConfigurationError = false
            hasReceivedTestScreenshot = false
            verificationStartedAt = nil
            NotificationCenter.default.post(name: .systemScreenshotDirectoryDidChange, object: nil)
            step = .ready
        case .ready:
            finish(openScreenshotTool: false)
            return
        }
        render()
    }

    @objc private func goBack() {
        step = Step(rawValue: max(0, step.rawValue - 1)) ?? .welcome
        render()
    }

    @objc private func dismissGuide() { close() }

    @objc private func changeDirectory() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.screenshotGuideChangeDirectory
        panel.prompt = L10n.savePathChoose
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = SystemScreenshotAutoOpen.directoryURL
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Defaults.systemScreenshotDirectory = url
            self.hasConfigurationError = false
            self.hasReceivedTestScreenshot = false
            self.verificationStartedAt = nil
            self.render()
        }
    }

    @objc private func showSystemScreenshotGuide() {
        guard let window, window.attachedSheet == nil else { return }
        let sheet = ScreenshotSetupWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        sheet.appearance = NSAppearance(named: .darkAqua)
        sheet.backgroundColor = window.backgroundColor
        sheet.title = L10n.screenshotGuideSetSystem
        sheet.minSize = NSSize(width: 600, height: 480)
        sheet.isReleasedWhenClosed = false
        let root = NSView()
        sheet.contentView = root
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let document = ScreenshotSetupDocumentView()
        scroll.documentView = document
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        document.addSubview(stack)
        let path = text(SaveDestination.displayPath(SystemScreenshotAutoOpen.directoryURL), size: 13)
        path.isSelectable = true
        for view in [text(L10n.screenshotGuideSystemDirectory, size: 14, weight: .semibold), path] {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.addArrangedSubview(button(L10n.screenshotGuideCopyPath, #selector(copyPath)))
        for (name, caption) in [("screenshot-options", L10n.screenshotGuideOptionsStep),
                                ("screenshot-preferences", L10n.screenshotGuidePreferencesStep)] {
            let label = text(caption, size: 14, weight: .semibold)
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "ScreenshotGuide"),
               let image = NSImage(contentsOf: url) {
                let view = ScreenshotSetupImageView(image: image)
                view.imageScaling = .scaleProportionallyUpOrDown
                stack.addArrangedSubview(view)
                NSLayoutConstraint.activate([
                    view.widthAnchor.constraint(equalTo: stack.widthAnchor),
                    view.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: image.size.height / image.size.width)
                ])
            }
        }
        let open = button(L10n.systemScreenshotSetupManual, #selector(openScreenshotOptions))
        let close = button(L10n.imageMergeClose, #selector(closeSystemScreenshotGuide))
        close.keyEquivalent = "\u{1b}"
        for view in [scroll, open, close] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: open.topAnchor, constant: -16),
            open.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -12),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            close.centerYAnchor.constraint(equalTo: open.centerYAnchor),
            open.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)
        ])
        window.beginSheet(sheet)
    }

    @objc private func closeSystemScreenshotGuide() {
        if let sheet = window?.attachedSheet { window?.endSheet(sheet) }
    }

    @objc private func openScreenshotOptions() {
        closeSystemScreenshotGuide()
        SystemScreenshotLocationManager.shared.relinquishAutomaticallyManagedLocation()
        verificationStartedAt = Date()
        hasReceivedTestScreenshot = false
        render()
        SystemScreenshotAutoOpen.openScreenshotTool()
    }

    @objc private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SystemScreenshotAutoOpen.directoryURL.path, forType: .string)
        ToastWindow.show(message: L10n.screenshotGuidePathCopied)
    }

    @objc private func verifyScreenshot() {
        guard SystemScreenshotLocationManager.shared.isTargetLocationActive else {
            render()
            return
        }
        verificationStartedAt = Date()
        SystemScreenshotAutoOpen.openScreenshotTool()
    }

    @objc private func testScreenshotImported(_ notification: Notification) {
        guard window?.isVisible == true, step == .ready,
              let startedAt = verificationStartedAt,
              let createdAt = notification.userInfo?["createdAt"] as? Date, createdAt >= startedAt,
              let url = notification.object as? URL,
              url.deletingLastPathComponent().resolvingSymlinksInPath()
                == SystemScreenshotAutoOpen.directoryURL.resolvingSymlinksInPath(),
              SystemScreenshotLocationManager.shared.isTargetLocationActive else { return }
        hasReceivedTestScreenshot = true
        Defaults.systemScreenshotVerifiedDirectory = SystemScreenshotAutoOpen.directoryURL.path
        NotificationCenter.default.post(name: .systemScreenshotVerificationDidChange, object: nil)
        render()
    }

    private func finish(openScreenshotTool: Bool) {
        // Recheck because the user can change the system location while the guide is open.
        guard SystemScreenshotLocationManager.shared.isTargetLocationActive,
              hasReceivedTestScreenshot else {
            step = .ready
            render()
            return
        }
        close()
        if openScreenshotTool { SystemScreenshotAutoOpen.openScreenshotTool() }
    }

    private func startLocationChecks() {
        locationTimer?.invalidate()
        locationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.locationMayHaveChanged()
        }
    }

    @objc private func locationMayHaveChanged() {
        guard window?.isVisible == true, step != .welcome else { return }
        let active = SystemScreenshotLocationManager.shared.isTargetLocationActive
        if active != lastLocationActive {
            if !active {
                hasReceivedTestScreenshot = false
                Defaults.systemScreenshotVerifiedDirectory = nil
            }
            render()
        }
    }

    @objc private func languageChanged() {
        if window?.isVisible == true { render() }
    }

    func windowWillClose(_ notification: Notification) {
        closeSystemScreenshotGuide()
        locationTimer?.invalidate()
        locationTimer = nil
    }

    private func clear(_ stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func stepCard(index: Int, title: String) -> NSView {
        let active = index == step.rawValue
        let completed = index < step.rawValue
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = (active
            ? NSColor.controlAccentColor.withAlphaComponent(0.20)
            : NSColor.white.withAlphaComponent(0.045)).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = (active
            ? NSColor.controlAccentColor.withAlphaComponent(0.55)
            : NSColor.white.withAlphaComponent(0.07)).cgColor

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 14
        badge.layer?.backgroundColor = (active ? NSColor.controlAccentColor
            : (completed ? NSColor.systemGreen.withAlphaComponent(0.18)
               : NSColor.white.withAlphaComponent(0.09))).cgColor
        let number = NSTextField(labelWithString: completed ? "✓" : String(index + 1))
        number.font = .systemFont(ofSize: 13, weight: .semibold)
        number.textColor = completed ? .systemGreen : (active ? .white : .secondaryLabelColor)
        badge.addSubview(number)

        let label = text(title, size: 13, weight: .semibold)
        label.textColor = active ? .white : .secondaryLabelColor
        card.addSubview(badge)
        card.addSubview(label)
        for view in [badge, number, label] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 56),
            badge.widthAnchor.constraint(equalToConstant: 28),
            badge.heightAnchor.constraint(equalToConstant: 28),
            badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            badge.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            number.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            number.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    private func add(_ view: NSView) {
        content.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    private func text(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular,
                      secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func card(_ views: [NSView]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        for view in views {
            stack.addArrangedSubview(view)
            if view is NSTextField { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }
}

private final class ScreenshotSetupDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Let the scroll viewport determine illustration size instead of the source pixels.
private final class ScreenshotSetupImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
