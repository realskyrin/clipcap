# clipcap

clipcap is a macOS menu bar image annotation tool. It does not capture the screen directly, does not record the screen, does not listen for global keyboard events, and does not need Screen Recording or Accessibility permission

## Recommended Workflow

1. Press `Control + Shift + Command + 4` to use the macOS system screenshot tool and copy a selected region to the clipboard
2. Open clipcap from the menu bar and choose “Edit Clipboard Image”
3. Annotate, OCR, translate, upload, save, or copy the result

You can also drag image files to the app, choose “Open Image”, use Finder “Open With clipcap”, or copy an image to the clipboard before editing it in clipcap

## Features

- Edit clipboard images and local image files
- Add arrows, shapes, lines, pen strokes, highlights, mosaic, text, numbers, inserted images, and QR recognition
- OCR, translation, dictionary mode, and configurable translation providers
- Upload images to your own image host and copy a URL or Markdown
- Save to a local folder, keep history, and re-copy previous images
- Menu bar app with no Dock icon

## Privacy Boundary

clipcap only works with images the user gives it through the clipboard, file picker, drag and drop, Open With, or explicit file selection. It does not request or reuse the old-app TCC grants, does not trigger capture from global hotkeys, and does not read Finder selection through Automation

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
