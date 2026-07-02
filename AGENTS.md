# clipcap

macOS menu bar image annotation tool. Pure AppKit, Swift Package Manager, no third-party dependencies.

clipcap does not directly capture or record the screen, does not listen to global keyboard events, and must not request Screen Recording or Accessibility permissions. Users provide images through macOS system screenshots copied to the clipboard, file open, drag and drop, Open With, or other explicit file input.

## Build & Verification

After every code change, run the compile check:

```bash
bash scripts/compile-check.sh
```

For runtime-sensitive UI changes, run the rebuild script too:

```bash
bash scripts/rebuild-and-open.sh
```

This script builds `build/clipcap.app`, kills any running instance, installs `/Applications/clipcap.app`, launches it, and confirms it started.

## Project Structure

- `clipcap/App/` — Entry point, AppDelegate, and Info.plist
- `clipcap/Capture/` — Clipboard, history, pinning, and image-edit launch paths
- `clipcap/Editor/` — Post-input annotation editor
- `clipcap/Settings/` — Settings dialog and preferences
- `clipcap/Translation/` — OCR and translation result presentation
- `clipcap/UI/` — Status bar, toast, cursor chip, and auxiliary windows
- `clipcap/Upload/` — Image host providers
- `clipcap/Utilities/` — UserDefaults, localization, updates, logs, and save paths
- `scripts/` — Build and bundle scripts

## Key Rules

- Always run `bash scripts/compile-check.sh` after modifying code
- No SwiftUI — this project uses AppKit exclusively with programmatic UI
- No storyboards or XIBs
- Minimum deployment target: macOS 14.0
- Do not add screen capture, screen recording, global keyboard monitoring, Finder Automation, or permission-onboarding flows
- All newly added user-facing copy must not end with punctuation. Punctuation inside the sentence is fine, but the final character of every visible string, tooltip, alert, toast, menu item, placeholder, and localized value must not be punctuation

## Packaging

- Bundle ID is `cn.skyrin.clipcap`
- App bundle is `clipcap.app`
- Release artifact is `clipcap-<version>-macos.dmg`
- Homebrew cask token is `clipcap`
- Do not install or overwrite `the original app bundle`
- If SwiftPM target resources are added later, update `scripts/bundle.sh` and the release workflow to copy the generated resource bundle into `clipcap.app/Contents/Resources/`

## Hotspot Ownership

- `clipcap/Editor/EditWindowController.swift` owns editor session wiring, toolbar callbacks, crop mode, and output actions
- `clipcap/Editor/EditCanvasView.swift` owns annotation state, mouse handling, selection chrome, undo/redo, and export compositing
- `clipcap/Editor/ToolbarLayout.swift` owns which editor tools are visible
- `clipcap/Settings/SettingsView.swift` owns the settings window and preference controls
- `clipcap/Translation/OCRTranslatePanel.swift` owns OCR and translation result presentation
- `clipcap/Capture/PinLauncher.swift` owns pinned-image window behavior
- `clipcap/Utilities/Defaults.swift` owns persisted preferences and localized string accessors
- `clipcap/Settings/UploadSettingsPane.swift` owns image-host provider settings

## Adding an Editor Tool

Whenever a new annotation/editor tool is added, it must also be wired into the toolbar.

- Add the `ToolbarItemID` case and update `editTool`, `symbolName`, `tooltip`, and the `kind` switch in `ToolbarLayout.swift`
- Add the case to `ToolbarLayout.canonicalOrder` and the default layout buckets
- Add the `tipXxx` localization key to `Defaults.swift` and every `Resources/*.lproj/Localizable.strings` file
- If the user has not told you where the tool should sit in the toolbar by default, ask before placing it
