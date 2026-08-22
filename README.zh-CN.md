# clipcap

clipcap is a macOS menu bar image annotation tool. It does not capture the screen directly, does not record the screen, does not listen for global keyboard events, and does not need Screen Recording or Accessibility permission

## Recommended Workflow

1. Turn on “Automatically open system screenshots” in Settings > General
2. Choose automatic setup, or manually set the Screenshot save location to `~/Pictures/ClipCap Screenshots`
3. Use a macOS system screenshot shortcut and clipcap opens the image, removes the loaded source file from the dedicated folder, and applies the existing ClipCap history setting to completed edits
4. For the fastest handoff, turn off “Show Floating Thumbnail” in Screenshot Options

If you do not want to change the system screenshot location, press `Control + Shift + Command + 4` to copy the screenshot, then choose “Edit Clipboard Image”. You can also drag image files to the app, choose “Open Image”, use Finder “Open With clipcap”, or copy an image to the clipboard before editing it in clipcap

## Features

- Edit clipboard images and local image files
- Watch a dedicated system screenshot folder, queue consecutive screenshots for editing, and remove each source file after loading it
- Add arrows, shapes, lines, pen strokes, highlights, mosaic, text, numbers, inserted images, and QR recognition
- OCR, translation, dictionary mode, and configurable translation providers
- Upload images to your own image host and copy a URL or Markdown
- Save locally and re-copy history items; hover to favorite with the bottom-right star, filter favorites, batch-favorite selections, and keep favorites through automatic pruning and Delete All History
- Keep the Mac awake indefinitely, for preset durations, or until a chosen time without extra permissions
- Menu bar app with no Dock icon

## Privacy Boundary

clipcap only works with images the user gives it through the clipboard, file picker, drag and drop, Open With, explicit file selection, or the dedicated system screenshot folder the user opts into. It does not request or reuse the old-app TCC grants, does not trigger capture from global hotkeys, and does not read Finder selection through Automation

## Install

```bash
brew install --cask realskyrin/tap/clipcap
```

Manual builds output `build/clipcap.app`

```bash
bash scripts/compile-check.sh
bash scripts/rebuild-and-open.sh
```

## Project Layout

- `clipcap/App/` — app entry point and bundle metadata
- `clipcap/Capture/` — clipboard, history, pinning, and image-edit launch paths
- `clipcap/Editor/` — annotation model, canvas, toolbar, save, upload, OCR, and translation entry points
- `clipcap/Settings/` — settings, toolbar, upload, and translation panes
- `clipcap/Upload/` — image host implementations
- `clipcap/Utilities/` — defaults, localization, updates, logs, and save paths
- `scripts/` — build, package, install, and signing scripts

## Release Identity

Bundle ID: `cn.skyrin.clipcap`

App bundle: `clipcap.app`

Release artifact: `clipcap-<version>-macos.dmg`

Homebrew cask: `clipcap`
