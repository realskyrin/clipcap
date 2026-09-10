import AppKit

private final class ReminderWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown,
           modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class ReminderBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

private final class ReminderRowView: NSTableRowView {
    // Keep native controls in their normal appearance instead of tinting them
    // as selected source-list content
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class ReminderActionButton: NSButton {
    var handler: (() -> Void)?
    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(invoke)
    }
    @objc private func invoke() { handler?() }
}

private final class ReminderToggle: NSSwitch {
    var handler: ((Bool) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        target = self
        action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func invoke() { handler?(state == .on) }
}

@MainActor
final class ReminderWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSWindowDelegate {
    static let shared = ReminderWindowController()
    private let table = NSTableView()
    private let count = NSTextField(labelWithString: "")
    private let activeCount = NSTextField(labelWithString: "")
    private let editor = NSStackView()
    private let empty = NSTextField(labelWithString: "")
    private let time = NSDatePicker()
    private let frequency = NSSegmentedControl()
    private var weekdayButtons: [NSButton] = []
    private let message = NSTextView()
    private let sound = NSPopUpButton()
    private let soundRepeats = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var entries: [ReminderEntry] = []
    private var selectedID: String?
    private var loading = false
    private var preview: ReminderSoundPlayer?
    // All writes, including deletion, run in order even when notification APIs suspend
    private var pending: Task<Void, Never>?
    private var revision = 0

    init(entries initialEntries: [ReminderEntry] = []) {
        let window = ReminderWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 820, height: 550)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        entries = initialEntries
        selectedID = entries.first?.id
        refresh()
        loadEditor()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func text(_ key: String) -> String { Localizer.string(key) }
    private func label(_ key: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text(key))
        field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        return field
    }
    private func vertical(_ views: [NSView], spacing: CGFloat = 14) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }
    private func pin(_ view: NSView, in parent: NSView, inset: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
    }
    private func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }
    private func row(_ key: String, control: NSView) -> NSStackView {
        let spacer = NSView()
        return NSStackView(views: [label(key), spacer, control])
    }
    private func group(_ views: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.borderType = .lineBorder
        box.borderColor = .separatorColor
        box.borderWidth = 0.5
        box.cornerRadius = 9
        box.fillColor = .controlBackgroundColor
        box.contentViewMargins = NSSize(width: 16, height: 16)
        let stack = vertical(views, spacing: 14)
        pin(stack, in: box.contentView!)
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return box
    }
    private func build() {
        guard let window else { return }
        window.title = text("reminderTitle")
        let root = ReminderBackgroundView()
        window.contentView = root
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        let divider = separator()
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)
        let detail = NSView()
        detail.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(detail)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.topAnchor.constraint(equalTo: root.topAnchor), sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 310),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), divider.widthAnchor.constraint(equalToConstant: 1), divider.topAnchor.constraint(equalTo: root.topAnchor), divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: divider.trailingAnchor), detail.trailingAnchor.constraint(equalTo: root.trailingAnchor), detail.topAnchor.constraint(equalTo: root.topAnchor), detail.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        count.textColor = .secondaryLabelColor
        let heading = vertical([label("reminderListTitle", size: 18, bold: true), count], spacing: 5)
        heading.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(heading)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("reminders"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 76
        table.style = .sourceList
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(scroll)
        activeCount.textColor = .secondaryLabelColor
        activeCount.font = .systemFont(ofSize: 12)
        let add = ReminderActionButton(title: text("reminderAdd")) { [weak self] in self?.addReminder() }
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        add.imagePosition = .imageLeading
        add.bezelStyle = .rounded
        let footer = NSStackView(views: [activeCount, NSView(), add])
        footer.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(footer)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20), heading.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 24),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 14), scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8), scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16), footer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16), footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -16)
        ])
        editor.orientation = .vertical
        editor.alignment = .leading
        editor.spacing = 18
        editor.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(editor)
        NSLayoutConstraint.activate([editor.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 24), editor.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -24), editor.topAnchor.constraint(equalTo: detail.topAnchor, constant: 24)])
        editor.addArrangedSubview(label("reminderEditorTitle", size: 18, bold: true))
        let subtitle = label("reminderEditorSubtitle")
        subtitle.textColor = .secondaryLabelColor
        editor.addArrangedSubview(subtitle)
        time.datePickerStyle = .textFieldAndStepper
        time.datePickerElements = .hourMinute
        time.target = self
        time.action = #selector(fieldsChanged)
        frequency.segmentCount = 3
        frequency.setLabel(text("reminderDaily"), forSegment: 0)
        frequency.setLabel(text("reminderWeekdaysShort"), forSegment: 1)
        frequency.setLabel(text("reminderWeekend"), forSegment: 2)
        frequency.trackingMode = .selectOne
        frequency.target = self
        frequency.action = #selector(presetChanged)
        weekdayButtons = [2, 3, 4, 5, 6, 7, 1].map { day in
            let button = NSButton(title: text("reminderDay\(day)"), target: self, action: #selector(weekdayChanged(_:)))
            button.tag = day
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12)
            button.setAccessibilityLabel(button.title)
            return button
        }
        let days = NSStackView(views: weekdayButtons)
        days.distribution = .fillEqually
        days.spacing = 6
        editor.addArrangedSubview(group([row("reminderTime", control: time), separator(), row("reminderRepeat", control: frequency), days]))
        message.font = .systemFont(ofSize: 14)
        message.isRichText = false
        message.allowsUndo = true
        message.isAutomaticQuoteSubstitutionEnabled = false
        message.textContainerInset = NSSize(width: 9, height: 9)
        message.isVerticallyResizable = true
        message.isHorizontallyResizable = false
        message.autoresizingMask = [.width]
        message.textContainer?.widthTracksTextView = true
        message.delegate = self
        let messageScroll = NSScrollView()
        messageScroll.borderType = .bezelBorder
        messageScroll.hasVerticalScroller = true
        messageScroll.documentView = message
        messageScroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        sound.addItem(withTitle: text("reminderSilent"))
        sound.lastItem?.representedObject = ""
        for url in ReminderController.sounds {
            sound.addItem(withTitle: url.deletingPathExtension().lastPathComponent)
            sound.lastItem?.representedObject = url.lastPathComponent
        }
        sound.target = self
        sound.action = #selector(fieldsChanged)
        for count in 1...10 {
            soundRepeats.addItem(withTitle: String(format: text("reminderSoundTimes"), count))
            soundRepeats.lastItem?.representedObject = count
        }
        soundRepeats.addItem(withTitle: text("reminderSoundInfinite"))
        soundRepeats.lastItem?.representedObject = 0
        soundRepeats.setAccessibilityLabel(text("reminderSoundRepeat"))
        soundRepeats.toolTip = text("reminderSoundRepeat")
        soundRepeats.target = self
        soundRepeats.action = #selector(fieldsChanged)
        let play = ReminderActionButton(title: text("reminderPreview")) { [weak self] in self?.playSound() }
        play.bezelStyle = .rounded
        play.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
        play.imagePosition = .imageLeading
        editor.addArrangedSubview(group([label("reminderMessage"), messageScroll, separator(), row("reminderSound", control: NSStackView(views: [sound, soundRepeats, play]))]))
        let hint = NSTextField(wrappingLabelWithString: text("reminderSoundLoopHint"))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        editor.addArrangedSubview(hint)
        status.textColor = .systemRed
        status.font = .systemFont(ofSize: 12)
        editor.addArrangedSubview(status)
        for view in editor.arrangedSubviews { view.widthAnchor.constraint(equalTo: editor.widthAnchor).isActive = true }
        empty.stringValue = text("reminderEmpty")
        empty.textColor = .secondaryLabelColor
        empty.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(empty)
        NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: detail.centerXAnchor), empty.centerYAnchor.constraint(equalTo: detail.centerYAnchor)])
    }
    func open() {
        if window?.isVisible != true {
            if pending == nil { entries = ReminderController.shared.entries }
            selectedID = entries.first(where: { $0.id == selectedID })?.id ?? entries.first?.id
            refresh()
            loadEditor()
            window?.center()
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func refresh() {
        loading = true
        table.reloadData()
        if let index = entries.firstIndex(where: { $0.id == selectedID }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        count.stringValue = String(format: text("reminderCount"), entries.count)
        activeCount.stringValue = String(format: text("reminderActiveCount"), entries.filter { $0.settings.enabled }.count)
        loading = false
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ReminderRowView()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let value = entry.settings
        let clock = NSTextField(labelWithString: String(format: "%02d:%02d", value.hour, value.minute))
        clock.font = .monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        let summary = NSTextField(labelWithString: repeatSummary(value) + " · " + value.message)
        summary.textColor = .secondaryLabelColor
        summary.lineBreakMode = .byTruncatingTail
        let words = vertical([clock, summary], spacing: 4)
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let toggle = ReminderToggle(frame: .zero)
        toggle.controlSize = .small
        toggle.state = value.enabled ? .on : .off
        toggle.setAccessibilityLabel(text("reminderEnabled"))
        toggle.handler = { [weak self] enabled in
            guard let self, let index = self.entries.firstIndex(where: { $0.id == entry.id }) else { return }
            self.entries[index].settings.enabled = enabled
            self.enqueue(self.entries[index])
            self.refresh()
        }
        let delete = ReminderActionButton(title: "") { [weak self] in self?.delete(entry.id) }
        delete.image = NSImage(systemSymbolName: "trash", accessibilityDescription: text("reminderDelete"))
        delete.isBordered = false
        delete.toolTip = text("reminderDelete")
        let cell = NSTableCellView()
        for view in [words, toggle, delete] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        NSLayoutConstraint.activate([
            // Source-list cells already inset their content by 16 points
            // 8-point scroll inset + 16 - 4 matches the 20-point heading inset
            words.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: -4),
            words.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            words.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -10),
            toggle.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: delete.leadingAnchor, constant: -10),
            delete.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            delete.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            delete.widthAnchor.constraint(equalToConstant: 22),
            delete.heightAnchor.constraint(equalToConstant: 26)
        ])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !loading, entries.indices.contains(table.selectedRow) else { return }
        selectedID = entries[table.selectedRow].id
        loadEditor()
    }
    private func loadEditor() {
        preview?.stop()
        loading = true
        defer { loading = false }
        let entry = entries.first { $0.id == selectedID }
        editor.isHidden = entry == nil
        empty.isHidden = entry != nil
        guard let value = entry?.settings else { return }
        time.dateValue = Calendar.current.date(bySettingHour: value.hour, minute: value.minute, second: 0, of: Date()) ?? Date()
        updateRepeatControls(value)
        message.string = value.message
        soundRepeats.selectItem(at: value.playbackCount == 0 ? 10 : value.playbackCount - 1)
        sound.selectItem(at: sound.itemArray.firstIndex { ($0.representedObject as? String) == value.sound } ?? 0)
    }
    func textDidChange(_ notification: Notification) {
        guard !message.hasMarkedText() else { return }
        fieldsChanged()
    }
    @objc private func fieldsChanged() {
        guard !loading, let index = entries.firstIndex(where: { $0.id == selectedID }) else { return }
        entries[index].settings.hour = Calendar.current.component(.hour, from: time.dateValue)
        entries[index].settings.minute = Calendar.current.component(.minute, from: time.dateValue)
        entries[index].settings.message = message.string
        entries[index].settings.sound = sound.selectedItem?.representedObject as? String ?? ""
        entries[index].settings.soundRepeatCount = soundRepeats.selectedItem?.representedObject as? Int ?? 1
        preview?.stop()
        enqueue(entries[index])
        refresh()
    }
    private func repeatSummary(_ value: ReminderSettings) -> String {
        if let preset = value.repeatPreset {
            return text(["reminderDaily", "reminderWeekdaysShort", "reminderWeekend"][preset])
        }
        let days = [2, 3, 4, 5, 6, 7, 1].filter { value.selectedWeekdays.contains($0) }
        return days.isEmpty ? text("reminderNoDays") : days.map { text("reminderDay\($0)") }.joined(separator: " ")
    }
    private func updateRepeatControls(_ value: ReminderSettings) {
        for index in 0..<3 { frequency.setSelected(value.repeatPreset == index, forSegment: index) }
        for button in weekdayButtons {
            button.state = value.selectedWeekdays.contains(button.tag) ? .on : .off
        }
    }
    @objc private func presetChanged() {
        guard !loading, let index = entries.firstIndex(where: { $0.id == selectedID }),
              (0..<3).contains(frequency.selectedSegment) else { return }
        entries[index].settings.selectedWeekdays = ReminderSettings.repeatPresets[frequency.selectedSegment]
        updateRepeatControls(entries[index].settings)
        fieldsChanged()
    }
    @objc private func weekdayChanged(_ sender: NSButton) {
        guard !loading, let index = entries.firstIndex(where: { $0.id == selectedID }) else { return }
        entries[index].settings.selectedWeekdays = Set(weekdayButtons.filter { $0.state == .on }.map(\.tag))
        updateRepeatControls(entries[index].settings)
        fieldsChanged()
    }
    private func addReminder() {
        let entry = ReminderEntry()
        entries.append(entry)
        selectedID = entry.id
        enqueue(entry)
        refresh()
        loadEditor()
        window?.makeFirstResponder(message)
    }
    private func delete(_ id: String) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        if selectedID == id { selectedID = entries.first?.id; loadEditor() }
        enqueue(entry, deleting: true)
        refresh()
    }
    private func enqueue(_ entry: ReminderEntry, deleting: Bool = false) {
        revision += 1
        let current = revision
        let previous = pending
        pending = Task { @MainActor in
            await previous?.value
            do {
                if deleting { try await ReminderController.shared.delete(entry) }
                else { try await ReminderController.shared.save(entry) }
                if current == revision { status.stringValue = ""; pending = nil }
            } catch {
                status.stringValue = (error as? ReminderController.ReminderError)?.errorDescription ?? text("reminderSaveError")
                if current == revision {
                    pending = nil
                    entries = ReminderController.shared.entries
                    selectedID = entries.first(where: { $0.id == selectedID })?.id ?? entries.first?.id
                    refresh()
                    loadEditor()
                }
            }
        }
    }
    private func playSound() {
        preview?.stop()
        guard let filename = sound.selectedItem?.representedObject as? String, !filename.isEmpty else { return }
        preview = ReminderSoundPlayer()
        preview?.play(filename: filename, count: soundRepeats.selectedItem?.representedObject as? Int ?? 1, message: text("reminderPreview"), showStopControl: true)
    }
    func windowWillClose(_ notification: Notification) { preview?.stop() }
}
