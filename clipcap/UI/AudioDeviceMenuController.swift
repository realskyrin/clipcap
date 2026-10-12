import AppKit
import CoreAudio

/// Only reads device metadata and changes default routes; never opens an audio stream.
final class AudioDeviceMenuController: NSObject, NSMenuDelegate {
    private enum Direction: CaseIterable {
        case output, input

        var scope: AudioObjectPropertyScope {
            self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        }
        var selector: AudioObjectPropertySelector {
            self == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        }
        var title: String { self == .input ? L10n.audioInput : L10n.audioOutput }
    }

    private struct Selection {
        let device: AudioDeviceID
        let direction: Direction
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.audioDevices, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
        let menu = NSMenu(title: L10n.audioDevices)
        menu.delegate = self
        item.submenu = menu
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let devices = deviceIDs() else {
            menu.addItem(disabledItem(L10n.audioDevicesUnavailable))
            return
        }
        for direction in Direction.allCases {
            if direction == .input { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: direction.title))
            let current = uintProperty(AudioObjectID(kAudioObjectSystemObject), direction.selector)
            let eligible = devices.filter {
                uintProperty($0, kAudioDevicePropertyDeviceIsAlive) == 1 &&
                uintProperty($0, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: direction.scope) == 1
            }.map { ($0, deviceName($0)) }.sorted {
                $0.1.localizedStandardCompare($1.1) == .orderedAscending
            }
            if eligible.isEmpty { menu.addItem(disabledItem(L10n.audioNoDevices)) }
            for (device, name) in eligible {
                let item = NSMenuItem(title: name, action: #selector(selectDevice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = Selection(device: device, direction: direction)
                item.state = current == device ? .on : .off
                menu.addItem(item)
            }
        }
    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? Selection else { return }
        // Revalidate because a device may have disconnected while the menu was open.
        guard uintProperty(selection.device, kAudioDevicePropertyDeviceIsAlive) == 1,
              uintProperty(selection.device, kAudioDevicePropertyDeviceCanBeDefaultDevice,
                           scope: selection.direction.scope) == 1 else {
            ToastWindow.show(message: L10n.audioDeviceSwitchFailed)
            return
        }
        var address = propertyAddress(selection.direction.selector)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(AudioObjectID(kAudioObjectSystemObject), &address, &settable) == noErr,
              settable.boolValue else {
            ToastWindow.show(message: L10n.audioDeviceSwitchFailed)
            return
        }
        var device = selection.device
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                               0, nil, UInt32(MemoryLayout.size(ofValue: device)), &device)
        if status != noErr { ToastWindow.show(message: L10n.audioDeviceSwitchFailed) }
        // Re-read on every opening so changes made in System Settings are reflected too.
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func propertyAddress(_ selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func uintProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = propertyAddress(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func deviceIDs() -> [AudioDeviceID]? {
        var address = propertyAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        // Retry once if hot-plugging changes the list between the size and data reads.
        for _ in 0..<2 {
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
            if size == 0 { return [] }
            var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
            let status = devices.withUnsafeMutableBytes {
                AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
            }
            if status == noErr { return Array(devices.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size)) }
        }
        return nil
    }

    private func deviceName(_ device: AudioDeviceID) -> String {
        var address = propertyAddress(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let fallback = "\(L10n.audioDevices) \(device)"
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name else { return fallback }
        // Core Audio transfers ownership of this property to the caller.
        let value = name.takeRetainedValue() as String
        return value.isEmpty ? fallback : value
    }
}
