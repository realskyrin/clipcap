# Changelog

## Unreleased

## [1.8.11] - 2026-07-12

### Added

- Added image preview and edit actions to the history panel (26c3906)

## [1.8.10] - 2026-07-11

### Changed

- Refined pinned image zoom interactions with an interactive preview and animated viewport transitions (7247389)

## [1.8.9] - 2026-07-10

### Fixed

- Fixed release packaging to include the Share Extension (1e97a3f)
- Scaled beautify padding to preserve the export preview ratio (15d1c99)

## [1.8.8] - 2026-07-10

### Added

- Added bulk delete support to the history panel (01212ae)

## [1.8.7] - 2026-07-09

### Fixed

- Fixed Escape key clearing for history panel multi-selection (3ff02c5)

## [1.8.6] - 2026-07-09

### Added

- Added shift and command multi-select support to the history panel (55b6e2e)

## [1.8.5] - 2026-07-06

### Fixed

- Fixed Image Merge template button text contrast in the dark theme (e1bfbd5)

## [1.8.4] - 2026-07-06

### Changed

- Refined the Image Merge workbench dark theme styling (9a20aba)

## [1.8.3] - 2026-07-04

### Added

- Added customizable image merge hotkey support and surfaced configured shortcuts in the status bar menu (6e5ccf4)

## [1.8.2] - 2026-07-03

### Added

- Added Finder image edit and pin shortcuts for selected images and clipboard images
- Added a refreshed About pane with update checking and clearer permission-light product copy

### Fixed

- Fixed the history panel shortcut so it works outside the Settings window

### Changed

- Changed the default copy-to-clipboard shortcut to Return
- Kept history panel items at a consistent compact width in notch mode

## [1.8.1] - 2026-07-03

### Added

- Added configurable image compression for file saves and clipboard copies
- Added share extension and file open handling for explicit image input workflows

### Changed

- Refreshed settings UI and localization coverage for image quality and file input flows

## [1.8.0] - 2026-07-02

### Changed

- Removed image hosting, upload providers, upload history URL handling, and upload settings
- Removed third-party translation providers, screenshot translation, dictionary mode, and translation settings
- Kept OCR text recognition, Live Text selection, image annotation, save, pin, history, and file/clipboard input workflows

## [1.7.0] - 2026-07-02

### Changed

- Repositioned the app as clipcap, a permission-light Mac image annotation tool
- Renamed the product identity, bundle id, app bundle, release artifact, update target, and Homebrew cask to clipcap
- Removed startup permission gating and global shortcut driven capture flows
- Removed direct screen capture, screen recording, window capture, Finder Automation, and permission onboarding from the active product surface
- Kept clipboard image editing, file opening, drag and drop, Open With, annotation, OCR, translation, upload, save, and history workflows
