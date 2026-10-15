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
    private var showsManualInstructions = false
    private var hasConfigurationError = false
    private var locationTimer: Timer?
    private var lastLocationActive = false
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showIfNeeded() {
        guard !Defaults.screenshotSetupGuidePresented else { return }
        // Existing users with a working handoff do not need an interruption.
        if Defaults.systemScreenshotAutoOpenEnabled,
           SystemScreenshotLocationManager.shared.isTargetLocationActive {
            Defaults.screenshotSetupGuidePresented = true
            return
        }
        showGuide()
    }

    func showGuide() {
        if window?.isVisible != true {
            step = .welcome
            showsManualInstructions = false
            hasConfigurationError = false
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

        let symbols = ["sparkles", "folder.badge.gearshape", "checkmark.circle.fill"]
        let icon = NSImageView(image: NSImage(systemSymbolName: symbols[step.rawValue], accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = step == .ready ? .systemGreen : .controlAccentColor
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
            let active = SystemScreenshotLocationManager.shared.isTargetLocationActive
            lastLocationActive = active
            add(text(L10n.screenshotGuideFolderTitle, size: 26, weight: .bold))
            add(text(L10n.screenshotGuideFolderBody, size: 14, secondary: true))
            let path = text(SaveDestination.displayPath(SystemScreenshotAutoOpen.directoryURL), size: 13, weight: .medium)
            path.isSelectable = true
            let status = text(active ? L10n.systemScreenshotFolderConfigured : L10n.screenshotGuideFolderPending, size: 12)
            status.textColor = active ? .systemGreen : .systemOrange
            add(card([text(L10n.systemScreenshotFolderLabel, size: 14, weight: .semibold), path, status]))
            let setupHint = active ? L10n.screenshotGuideAlreadyConfigured
                : (showsManualInstructions ? L10n.screenshotGuideManualIntro : L10n.screenshotGuideSystemChange)
            add(text(setupHint, size: 12, secondary: true))
            if hasConfigurationError {
                let error = text(L10n.systemScreenshotSetupFailedMessage, size: 13)
                error.textColor = .systemOrange
                add(error)
            }
            if showsManualInstructions {
                add(card([
                    text(L10n.screenshotGuideManualSteps, size: 13),
                    button(L10n.screenshotGuideCopyPath, #selector(copyPath)),
                    button(L10n.systemScreenshotSetupManual, #selector(openScreenshotOptions)),
                    button(L10n.screenshotGuideAutomatic, #selector(showAutomatic))
                ]))
            } else {
                add(button(L10n.screenshotGuideManual, #selector(showManual)))
            }
            primary.title = active ? L10n.screenshotGuideContinue
                : (showsManualInstructions ? L10n.screenshotGuideCheck : L10n.screenshotGuideConfigure)
        case .ready:
            add(text(L10n.screenshotGuideReadyTitle, size: 26, weight: .bold))
            add(text(L10n.screenshotGuideReadyBody, size: 14, secondary: true))
            add(card([
                text("⇧⌘4", size: 30, weight: .medium),
                text(L10n.screenshotGuideShortcutHint, size: 13, secondary: true),
                text(L10n.screenshotGuideRecordingHint, size: 13, secondary: true)
            ]))
            add(card([
                text(L10n.screenshotGuideThumbnailTitle, size: 14, weight: .semibold),
                text(L10n.screenshotGuideThumbnailBody, size: 13, secondary: true),
                button(L10n.screenshotGuideTry, #selector(tryScreenshot))
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
            let manager = SystemScreenshotLocationManager.shared
            let wasActive = manager.isTargetLocationActive
            if showsManualInstructions, !wasActive {
                ToastWindow.show(message: L10n.screenshotGuideFolderPending)
                render()
                return
            }
            guard manager.configureAutomatically() else {
                hasConfigurationError = true
                showsManualInstructions = true
                render()
                return
            }
            if !wasActive { SystemScreenshotAutoOpen.refreshSystemScreenshotServices() }
            Defaults.systemScreenshotAutoOpenEnabled = true
            guard manager.isTargetLocationActive, Defaults.systemScreenshotAutoOpenEnabled else {
                hasConfigurationError = true
                render()
                return
            }
            hasConfigurationError = false
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

    @objc private func showManual() {
        showsManualInstructions = true
        render()
    }

    @objc private func showAutomatic() {
        showsManualInstructions = false
        render()
    }

    @objc private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SystemScreenshotAutoOpen.directoryURL.path, forType: .string)
        ToastWindow.show(message: L10n.screenshotGuidePathCopied)
    }

    @objc private func openScreenshotOptions() {
        guard SystemScreenshotAutoOpen.ensureDirectoryExists() else {
            hasConfigurationError = true
            render()
            return
        }
        SystemScreenshotAutoOpen.openScreenshotTool()
    }

    @objc private func tryScreenshot() { finish(openScreenshotTool: true) }

    private func finish(openScreenshotTool: Bool) {
        // Recheck because the user can change the system location while the guide is open.
        guard SystemScreenshotLocationManager.shared.isTargetLocationActive,
              Defaults.systemScreenshotAutoOpenEnabled else {
            step = .folder
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
        if step == .ready, !active || !Defaults.systemScreenshotAutoOpenEnabled {
            step = .folder
            render()
        } else if step == .folder, active != lastLocationActive {
            render()
        }
    }

    @objc private func languageChanged() {
        if window?.isVisible == true { render() }
    }

    func windowWillClose(_ notification: Notification) {
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
