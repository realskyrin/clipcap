import AppKit
import AVFoundation

/// Owns both finite and indefinite playback, with a stop control independent of the editor
@MainActor
final class ReminderSoundPlayer: NSObject, AVAudioPlayerDelegate {
    private var audio: AVAudioPlayer?
    private var panel: NSPanel?
    var isPlaying: Bool { audio?.isPlaying == true }

    func play(filename: String, count: Int, message: String, showStopControl: Bool = false) {
        stop()
        guard let url = ReminderController.sounds.first(where: { $0.lastPathComponent == filename }),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = count == 0 ? -1 : max(0, min(10, count) - 1)
        player.delegate = self
        audio = player
        guard player.play() else { stop(); return }
        guard showStopControl else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 130), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = Localizer.string("reminderTitle")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        let label = NSTextField(wrappingLabelWithString: message)
        label.maximumNumberOfLines = 2
        let stop = NSButton(title: Localizer.string("reminderStopSound"), target: self, action: #selector(stopSound))
        stop.bezelStyle = .rounded
        let stack = NSStackView(views: [label, stop])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor)
        ])
        self.panel = panel
        panel.center()
        panel.orderFrontRegardless()
    }

    @objc private func stopSound() { stop() }
    func stop() {
        audio?.stop()
        audio = nil
        panel?.close()
        panel = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard self?.audio === player else { return }
            self?.stop()
        }
    }
}
