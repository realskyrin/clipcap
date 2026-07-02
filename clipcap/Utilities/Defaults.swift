import Foundation

/// A language the app's UI can be displayed in. Raw values double as the
/// `appLanguage` UserDefaults value (kept stable for backward compatibility).
enum AppLanguage: String, CaseIterable {
    case zh
    case zhTW = "zh-Hant"
    case en
    case ja
    case ko
    case fr
    case ru
    case vi

    /// Folder name (without extension) of the matching `.lproj` bundle inside
    /// `clipcap.app/Contents/Resources/`.
    var lprojName: String {
        switch self {
        case .zh: return "zh-Hans"
        case .zhTW: return "zh-Hant"
        default:  return rawValue
        }
    }

    /// Native language name shown in the in-app language picker.
    var displayName: String {
        switch self {
        case .zh: return "简体中文"
        case .zhTW: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .ru: return "Русский"
        case .vi: return "Tiếng Việt"
        }
    }

    /// Best-effort match of the system's preferred languages to a supported
    /// app language — used on first launch before the user picks explicitly.
    static var systemDefault: AppLanguage {
        for code in Locale.preferredLanguages {
            let lower = code.lowercased()
            if lower.hasPrefix("zh-hant") ||
                lower.hasPrefix("zh-tw") ||
                lower.hasPrefix("zh-hk") ||
                lower.hasPrefix("zh-mo") {
                return .zhTW
            }
            if lower.hasPrefix("zh") { return .zh }
            if lower.hasPrefix("ja") { return .ja }
            if lower.hasPrefix("ko") { return .ko }
            if lower.hasPrefix("fr") { return .fr }
            if lower.hasPrefix("ru") { return .ru }
            if lower.hasPrefix("vi") { return .vi }
            if lower.hasPrefix("en") { return .en }
        }
        return .en
    }
}

extension Notification.Name {
    static let languageDidChange = Notification.Name("clipcap.languageDidChange")
    static let historyCacheEnabledDidChange = Notification.Name("clipcap.historyCacheEnabledDidChange")
    static let historyCacheLimitDidChange = Notification.Name("clipcap.historyCacheLimitDidChange")
    static let historyDidUpdate = Notification.Name("clipcap.historyDidUpdate")
    static let historyPanelDisplayModesDidChange = Notification.Name("clipcap.historyPanelDisplayModesDidChange")
    static let hotkeyDidChange = Notification.Name("clipcap.hotkeyDidChange")
}

/// Centralized accessor for every user-facing string. Each property resolves a
/// key from the current language's `Localizable.strings`; the localized values
/// live in `Resources/<lang>.lproj/Localizable.strings`.
enum L10n {
    static var lang: AppLanguage { Defaults.language }

    private static func s(_ key: String) -> String { Localizer.string(key) }

    // Settings
    static var settingsTitle: String { s("settingsTitle") }
    static var showMenuBarIcon: String { s("showMenuBarIcon") }
    static var permissionsHeader: String { s("permissionsHeader") }
    static var launchApp: String { s("launchApp") }
    static var launchAtLogin: String { s("launchAtLogin") }
    static var pinAcrossSpaces: String { s("pinAcrossSpaces") }
    static var pinAcrossSpacesHint: String { s("pinAcrossSpacesHint") }
    static var historyCacheToggleLabel: String { s("historyCacheToggleLabel") }
    static var historyCacheToggleHint: String { s("historyCacheToggleHint") }
    static var historyCacheLabel: String { s("historyCacheLabel") }
    static var historyCacheHint: String { s("historyCacheHint") }
    static var historyPanelDisplayModeLabel: String { s("historyPanelDisplayModeLabel") }
    static var historyPanelDisplayModeHint: String { s("historyPanelDisplayModeHint") }
    static var historyPanelDialogMode: String { s("historyPanelDialogMode") }
    static var historyPanelDialogModeHint: String { s("historyPanelDialogModeHint") }
    static var historyPanelNotchMode: String { s("historyPanelNotchMode") }
    static var historyPanelNotchModeHint: String { s("historyPanelNotchModeHint") }
    static var windowShadowToggleLabel: String { s("windowShadowToggleLabel") }
    static var windowShadowToggleHint: String { s("windowShadowToggleHint") }
    static var windowShadowSizeLabel: String { s("windowShadowSizeLabel") }
    static var windowShadowSizeHint: String { s("windowShadowSizeHint") }
    static var savePathTitle: String { s("savePathTitle") }
    static var savePathSubtitle: String { s("savePathSubtitle") }
    static var autoRevealSavedFilesLabel: String { s("autoRevealSavedFilesLabel") }
    static var autoRevealSavedFilesHint: String { s("autoRevealSavedFilesHint") }
    static var screenshotSavePathLabel: String { s("screenshotSavePathLabel") }
    static var savePathChoose: String { s("savePathChoose") }
    static var savePathReveal: String { s("savePathReveal") }
    static var chooseScreenshotSavePathTitle: String { s("chooseScreenshotSavePathTitle") }

    // Screenshot shortcut
    static var shortcutHeader: String { s("shortcutHeader") }
    static var shortcutHint: String { s("shortcutHint") }
    static var shortcutDefaultDisplay: String { s("shortcutDefaultDisplay") }
    static var shortcutSet: String { s("shortcutSet") }
    static var shortcutCancel: String { s("shortcutCancel") }
    static var shortcutWaiting: String { s("shortcutWaiting") }
    static var shortcutRestore: String { s("shortcutRestore") }

    // Pin-image shortcut
    static var selectedImagePinShortcutHeader: String { s("selectedImagePinShortcutHeader") }
    static var selectedImagePinShortcutDefaultDisplay: String { s("selectedImagePinShortcutDefaultDisplay") }
    static var selectedImagePinShortcutClear: String { s("selectedImagePinShortcutClear") }
    static var clipboardImagePinShortcutHeader: String { s("clipboardImagePinShortcutHeader") }
    static var clipboardImagePinShortcutDefaultDisplay: String { s("clipboardImagePinShortcutDefaultDisplay") }
    static var clipboardImagePinShortcutClear: String { s("clipboardImagePinShortcutClear") }
    static var clipboardTextPinShortcutHeader: String { s("clipboardTextPinShortcutHeader") }
    static var clipboardTextPinShortcutDefaultDisplay: String { s("clipboardTextPinShortcutDefaultDisplay") }
    static var clipboardTextPinShortcutClear: String { s("clipboardTextPinShortcutClear") }
    static var selectedImagePinNoImage: String { s("selectedImagePinNoImage") }
    static var clipboardImagePinNoImage: String { s("clipboardImagePinNoImage") }
    static var clipboardTextPinNoText: String { s("clipboardTextPinNoText") }
    static var pinFromFinderHint: String { s("pinFromFinderHint") }
    static var pinFromClipboardHint: String { s("pinFromClipboardHint") }
    static var pinFromClipboardTextHint: String { s("pinFromClipboardTextHint") }
    static var pinToolbarEdit: String { s("pinToolbarEdit") }
    static var pinToolbarEditText: String { s("pinToolbarEditText") }

    // Image-edit shortcuts
    static var selectedImageEditShortcutHeader: String { s("selectedImageEditShortcutHeader") }
    static var selectedImageEditShortcutHint: String { s("selectedImageEditShortcutHint") }
    static var selectedImageEditShortcutDefaultDisplay: String { s("selectedImageEditShortcutDefaultDisplay") }
    static var clipboardImageEditShortcutHeader: String { s("clipboardImageEditShortcutHeader") }
    static var clipboardImageEditShortcutHint: String { s("clipboardImageEditShortcutHint") }
    static var clipboardImageEditShortcutDefaultDisplay: String { s("clipboardImageEditShortcutDefaultDisplay") }
    static var textRecognitionShortcutHeader: String { s("textRecognitionShortcutHeader") }
    static var textRecognitionShortcutDefaultDisplay: String { s("textRecognitionShortcutDefaultDisplay") }
    static var copyImageTextShortcutHeader: String { s("copyImageTextShortcutHeader") }
    static var copyImageTextShortcutDefaultDisplay: String { s("copyImageTextShortcutDefaultDisplay") }
    static var imageMergeShortcutHeader: String { s("imageMergeShortcutHeader") }
    static var imageMergeShortcutDefaultDisplay: String { s("imageMergeShortcutDefaultDisplay") }
    static var fullScreenScreenshotShortcutHeader: String { s("fullScreenScreenshotShortcutHeader") }
    static var fullScreenScreenshotShortcutDefaultDisplay: String { s("fullScreenScreenshotShortcutDefaultDisplay") }
    static var colorPickerShortcutHeader: String { s("colorPickerShortcutHeader") }
    static var colorPickerShortcutDefaultDisplay: String { s("colorPickerShortcutDefaultDisplay") }

    // Copy-to-clipboard shortcut (editor confirm)
    static var clipboardShortcutHeader: String { s("clipboardShortcutHeader") }
    static var clipboardShortcutHint: String { s("clipboardShortcutHint") }
    static var clipboardShortcutDefaultDisplay: String { s("clipboardShortcutDefaultDisplay") }

    // History navigation shortcuts (editor)
    static var previousHistoryImageShortcutHeader: String { s("previousHistoryImageShortcutHeader") }
    static var previousHistoryImageShortcutHint: String { s("previousHistoryImageShortcutHint") }
    static var nextHistoryImageShortcutHeader: String { s("nextHistoryImageShortcutHeader") }
    static var nextHistoryImageShortcutHint: String { s("nextHistoryImageShortcutHint") }
    static var historyPanelShortcutHeader: String { s("historyPanelShortcutHeader") }
    static var historyPanelShortcutHint: String { s("historyPanelShortcutHint") }
    static var historyPanelShortcutDefaultDisplay: String { s("historyPanelShortcutDefaultDisplay") }

    // Save-to-file shortcut (editor save)
    static var fileSaveShortcutHeader: String { s("fileSaveShortcutHeader") }
    static var fileSaveShortcutHint: String { s("fileSaveShortcutHint") }

    // Shortcut conflict
    static var shortcutConflictTitle: String { s("shortcutConflictTitle") }
    static var shortcutConflictScreenshot: String { s("shortcutConflictScreenshot") }
    static var shortcutConflictSelectedImagePin: String { s("shortcutConflictSelectedImagePin") }
    static var shortcutConflictClipboardImagePin: String { s("shortcutConflictClipboardImagePin") }
    static var shortcutConflictClipboardTextPin: String { s("shortcutConflictClipboardTextPin") }
    static var shortcutConflictClipboard: String { s("shortcutConflictClipboard") }
    static var shortcutConflictFileSave: String { s("shortcutConflictFileSave") }
    static var shortcutConflictPreviousHistoryImage: String { s("shortcutConflictPreviousHistoryImage") }
    static var shortcutConflictNextHistoryImage: String { s("shortcutConflictNextHistoryImage") }
    static var shortcutConflictHistoryPanel: String { s("shortcutConflictHistoryPanel") }
    static var shortcutConflictSelectedImageEdit: String { s("shortcutConflictSelectedImageEdit") }
    static var shortcutConflictClipboardImageEdit: String { s("shortcutConflictClipboardImageEdit") }
    static var shortcutConflictTextRecognition: String { s("shortcutConflictTextRecognition") }
    static var shortcutConflictCopyImageText: String { s("shortcutConflictCopyImageText") }
    static var shortcutConflictImageMerge: String { s("shortcutConflictImageMerge") }
    static var shortcutConflictFullScreenScreenshot: String { s("shortcutConflictFullScreenScreenshot") }
    static var shortcutConflictColorPicker: String { s("shortcutConflictColorPicker") }

    // Menu bar
    static var takeScreenshot: String { s("takeScreenshot") }
    static var takeFullScreenScreenshot: String { s("takeFullScreenScreenshot") }
    static var editClipboardImage: String { s("editClipboardImage") }
    static var openImage: String { s("openImage") }
    static var openImageNoImage: String { s("openImageNoImage") }
    static var mergeImages: String { s("mergeImages") }
    static var colorPicker: String { s("colorPicker") }
    static var settings: String { s("settings") }
    static var quitApp: String { s("quitApp") }
    static var historyMenu: String { s("historyMenu") }
    static var historyEmpty: String { s("historyEmpty") }
    static var historyClear: String { s("historyClear") }
    static var historyCleared: String { s("historyCleared") }
    static var historyShowInFinder: String { s("historyShowInFinder") }
    static var historyPanelMenu: String { s("historyPanelMenu") }
    static var historyPanelFilterAll: String { s("historyPanelFilterAll") }
    static var historyPanelFilterScreenshots: String { s("historyPanelFilterScreenshots") }
    static var historyPanelFilterGIF: String { s("historyPanelFilterGIF") }
    static var historyPanelFilterColors: String { s("historyPanelFilterColors") }
    static var historyPanelCopyHint: String { s("historyPanelCopyHint") }
    static var historyPanelCopyDragHint: String { s("historyPanelCopyDragHint") }
    static var historyPanelEmpty: String { s("historyPanelEmpty") }

    // Cursor chip
    static var dragToScreenshot: String { s("dragToScreenshot") }
    static var dragToScreenshotAspectFree: String { s("dragToScreenshotAspectFree") }
    static func dragToScreenshotAspect(_ ratio: String) -> String {
        String(format: s("dragToScreenshotAspect"), ratio)
    }
    static var dragToTextRecognition: String { s("dragToTextRecognition") }
    static var dragToCopyImageText: String { s("dragToCopyImageText") }
    // Toast
    static var copiedToClipboard: String { s("copiedToClipboard") }
    static var mergedLongScreenshot: String { s("mergedLongScreenshot") }
    static var cropLongScreenshotHint: String { s("cropLongScreenshotHint") }
    static var scrollCaptureHint: String { s("scrollCaptureHint") }
    static var scrollCaptureManualHint: String { s("scrollCaptureManualHint") }
    static var finderEditExitHint: String { s("finderEditExitHint") }
    static var clipboardEditExitHint: String { s("clipboardEditExitHint") }
    static var pinEditExitHint: String { s("pinEditExitHint") }
    static var fullScreenEditExitHint: String { s("fullScreenEditExitHint") }
    static var editSuspendedToast: String { s("editSuspendedToast") }
    static var editSuspendedResumeToast: String { s("editSuspendedResumeToast") }
    static var fullScreenScreenshotFailed: String { s("fullScreenScreenshotFailed") }
    static var selectedImageEditNoImage: String { s("selectedImageEditNoImage") }
    static var clipboardImageEditNoImage: String { s("clipboardImageEditNoImage") }
    static var mergeEditExitHint: String { s("mergeEditExitHint") }
    static var imageMergeNeedTwoImages: String { s("imageMergeNeedTwoImages") }
    static var imageMergeSomeImagesSkipped: String { s("imageMergeSomeImagesSkipped") }
    static var imageMergeNoClipboardImage: String { s("imageMergeNoClipboardImage") }
    static var imageMergeFailed: String { s("imageMergeFailed") }
    static var imageMergeSaved: String { s("imageMergeSaved") }
    static func screenshotSaved(to path: String) -> String {
        String(format: s("screenshotSaved"), path)
    }
    static func screenshotSaveFailed(_ message: String) -> String {
        String(format: s("screenshotSaveFailed"), message)
    }
    static func colorCopied(_ hex: String) -> String {
        String(format: s("colorCopied"), hex)
    }
    static var qrCodeCopied: String { s("qrCodeCopied") }
    static var qrCodeNotFound: String { s("qrCodeNotFound") }

    // Toolbar tooltips
    static var tipRectangle: String { s("tipRectangle") }
    static var tipEllipse: String { s("tipEllipse") }
    static var tipArrow: String { s("tipArrow") }
    static var tipLine: String { s("tipLine") }
    static var tipPen: String { s("tipPen") }
    static var tipMarker: String { s("tipMarker") }
    static var tipMosaic: String { s("tipMosaic") }
    static var mosaicGranularity: String { s("mosaicGranularity") }
    static var tipEraser: String { s("tipEraser") }
    static var tipMagnifier: String { s("tipMagnifier") }
    static var tipNumbered: String { s("tipNumbered") }
    static var tipText: String { s("tipText") }
    static var tipQRCode: String { s("tipQRCode") }
    static var tipEmoji: String { s("tipEmoji") }
    static var tipMoreEmoji: String { s("tipMoreEmoji") }
    static var tipInsertImage: String { s("tipInsertImage") }
    static var tipColorPicker: String { s("tipColorPicker") }
    static var tipPickedInkBottle: String { s("tipPickedInkBottle") }
    static var tipUndo: String { s("tipUndo") }
    static var tipRedo: String { s("tipRedo") }
    static var tipMoveSelection: String { s("tipMoveSelection") }
    static var tipScrollCapture: String { s("tipScrollCapture") }
    static var tipBeautify: String { s("tipBeautify") }
    static var tipOCR: String { s("tipOCR") }
    static var tipSave: String { s("tipSave") }
    static var tipPin: String { s("tipPin") }
    static var tipCancel: String { s("tipCancel") }
    static var tipConfirm: String { s("tipConfirm") }
    static var tipScrollCropConfirm: String { s("tipScrollCropConfirm") }
    static var copyQRCodeContent: String { s("copyQRCodeContent") }

    // Beautify
    static var beautify: String { s("beautify") }
    static var beautifyPresetPeachBlue: String { s("beautifyPresetPeachBlue") }
    static var beautifyPresetMintTeal: String { s("beautifyPresetMintTeal") }
    static var beautifyPresetPeachPink: String { s("beautifyPresetPeachPink") }
    static var beautifyPresetBluePurple: String { s("beautifyPresetBluePurple") }
    static var beautifyPresetWarmOrange: String { s("beautifyPresetWarmOrange") }
    static var beautifyPresetTealPink: String { s("beautifyPresetTealPink") }
    static var beautifyPresetDeepPurple: String { s("beautifyPresetDeepPurple") }
    static var beautifyPresetNeutralGray: String { s("beautifyPresetNeutralGray") }
    static var beautifyPresetWallpaper: String { s("beautifyPresetWallpaper") }
    static var beautifyShadowEffect: String { s("beautifyShadowEffect") }

    // Text tool
    static var textStrokeEffect: String { s("textStrokeEffect") }
    static var textCalloutEffect: String { s("textCalloutEffect") }

    // Shape tool
    static var shapeFillEffect: String { s("shapeFillEffect") }
    static var shapeFillNone: String { s("shapeFillNone") }
    static var shapeFillOpaque: String { s("shapeFillOpaque") }
    static var shapeFillTranslucent: String { s("shapeFillTranslucent") }
    static var shapeStyleStandard: String { s("shapeStyleStandard") }
    static var shapeStyleRounded: String { s("shapeStyleRounded") }
    static var shapeStyleHandDrawn: String { s("shapeStyleHandDrawn") }

    // Insert tools
    static var insertImageFromClipboard: String { s("insertImageFromClipboard") }
    static var insertImageFromFile: String { s("insertImageFromFile") }
    static var insertImageChooseFile: String { s("insertImageChooseFile") }
    static var insertImageNoClipboardImage: String { s("insertImageNoClipboardImage") }
    static var scrollCaptureAutoScroll: String { s("scrollCaptureAutoScroll") }
    static var scrollCaptureManualScroll: String { s("scrollCaptureManualScroll") }

    // Language
    static var languageHeader: String { s("languageHeader") }

    // Settings sidebar tabs
    static var settingsTabGeneral: String { s("settingsTabGeneral") }
    static var settingsTabShortcuts: String { s("settingsTabShortcuts") }
    static var settingsTabPermissions: String { s("settingsTabPermissions") }
    static var settingsTabAbout: String { s("settingsTabAbout") }
    static var settingsTabToolbar: String { s("settingsTabToolbar") }
    static var settingsNoPermissionsNeeded: String { s("settingsNoPermissionsNeeded") }
    static var settingsSubtitleGeneral: String { s("settingsSubtitleGeneral") }
    static var settingsSubtitleShortcuts: String { s("settingsSubtitleShortcuts") }
    static var settingsSubtitleToolbar: String { s("settingsSubtitleToolbar") }
    static var settingsSubtitleAbout: String { s("settingsSubtitleAbout") }
    static var settingsQuit: String { s("settingsQuit") }

    // Toolbar settings
    static var toolbarSettingsPrimaryTitle: String { s("toolbarSettingsPrimaryTitle") }
    static var toolbarSettingsPrimaryHint: String { s("toolbarSettingsPrimaryHint") }
    static var toolbarSettingsSideTitle: String { s("toolbarSettingsSideTitle") }
    static var toolbarSettingsSideHint: String { s("toolbarSettingsSideHint") }
    static var toolbarSettingsHiddenTitle: String { s("toolbarSettingsHiddenTitle") }
    static var toolbarSettingsHiddenHint: String { s("toolbarSettingsHiddenHint") }
    static var toolbarSettingsFootnote: String { s("toolbarSettingsFootnote") }
    static var toolbarSettingsReset: String { s("toolbarSettingsReset") }
    static var toolbarSettingsCancel: String { s("toolbarSettingsCancel") }
    static var toolbarSettingsApply: String { s("toolbarSettingsApply") }

    // About pane
    static var aboutTagline: String { s("aboutTagline") }
    static var aboutLicense: String { s("aboutLicense") }
    static var aboutSourceCode: String { s("aboutSourceCode") }
    static var aboutStarOnGitHub: String { s("aboutStarOnGitHub") }
    static var aboutFeatureRequest: String { s("aboutFeatureRequest") }
    static var aboutBugReport: String { s("aboutBugReport") }
    static var aboutUpdateTitle: String { s("aboutUpdateTitle") }

    // Error log — About pane
    static var aboutErrorLog: String { s("aboutErrorLog") }
    static var aboutErrorLogNoCrash: String { s("aboutErrorLogNoCrash") }
    static func aboutErrorLogLastCrash(_ date: String) -> String {
        String(format: s("aboutErrorLogLastCrash"), date)
    }
    static var aboutErrorLogCopy: String { s("aboutErrorLogCopy") }
    static var aboutErrorLogCopied: String { s("aboutErrorLogCopied") }
    static var aboutErrorLogReveal: String { s("aboutErrorLogReveal") }
    static var aboutErrorLogRefresh: String { s("aboutErrorLogRefresh") }
    static var aboutErrorLogClear: String { s("aboutErrorLogClear") }
    static var aboutErrorLogEmptyBody: String { s("aboutErrorLogEmptyBody") }

    // Updates — About pane
    static var checkForUpdates: String { s("checkForUpdates") }
    static var updateChecking: String { s("updateChecking") }
    static var updateUpToDateStatus: String { s("updateUpToDateStatus") }
    static func updateNewVersionStatus(_ v: String) -> String {
        String(format: s("updateNewVersionStatus"), v)
    }
    static var updateFailedStatus: String { s("updateFailedStatus") }
    static var updateDownloadButton: String { s("updateDownloadButton") }
    static var updateRetryButton: String { s("updateRetryButton") }
    static var updateInstallNowButton: String { s("updateInstallNowButton") }
    static func updateDownloadingStatus(_ percent: Int) -> String {
        String(format: s("updateDownloadingStatus"), percent)
    }
    static var updateInstallingStatus: String { s("updateInstallingStatus") }
    static var updateInstallFailedStatus: String { s("updateInstallFailedStatus") }

    // Updates — menu bar
    static var checkForUpdatesMenu: String { s("checkForUpdatesMenu") }
    static var checkingForUpdatesMenu: String { s("checkingForUpdatesMenu") }
    static func updateAvailableMenu(_ v: String) -> String {
        String(format: s("updateAvailableMenu"), v)
    }
    static func updateDownloadingMenu(_ percent: Int) -> String {
        String(format: s("updateDownloadingMenu"), percent)
    }
    static var updateInstallingMenu: String { s("updateInstallingMenu") }
    static var updateInstallFailedMenu: String { s("updateInstallFailedMenu") }

    // Updates — progress HUD
    static var updateCheckingHUD: String { s("updateCheckingHUD") }
    static func updateDownloadingHUD(_ percent: Int) -> String {
        String(format: s("updateDownloadingHUD"), percent)
    }
    static var updateVerifyingHUD: String { s("updateVerifyingHUD") }
    static var updateUnzippingHUD: String { s("updateUnzippingHUD") }
    static var updateInstallingHUD: String { s("updateInstallingHUD") }

    // Updates — manual check result alert
    static func updateAvailableTitle(_ v: String) -> String {
        String(format: s("updateAvailableTitle"), v)
    }
    static var updateAvailableBody: String { s("updateAvailableBody") }
    static var updateUpToDateTitle: String { s("updateUpToDateTitle") }
    static func updateUpToDateBody(_ v: String) -> String {
        String(format: s("updateUpToDateBody"), v)
    }
    static var updateFailedTitle: String { s("updateFailedTitle") }
    static var updateFailedBody: String { s("updateFailedBody") }
    static var updateInstallFailedTitle: String { s("updateInstallFailedTitle") }
    static var updateInstallFailedBody: String { s("updateInstallFailedBody") }
    static var updateOpenPageButton: String { s("updateOpenPageButton") }
    static var updateSkipButton: String { s("updateSkipButton") }
    static var updateLaterButton: String { s("updateLaterButton") }
    static var updateOKButton: String { s("updateOKButton") }

    // Quit confirmation dialog
    static var quitConfirmTitle: String { s("quitConfirmTitle") }
    static var quitConfirmMessage: String { s("quitConfirmMessage") }
    static var quitConfirmAction: String { s("quitConfirmAction") }
    static var quitConfirmCancel: String { s("quitConfirmCancel") }

    // Permissions — status label
    static var permissionGranted: String { s("permissionGranted") }
    static var permissionNotGranted: String { s("permissionNotGranted") }

    // OCR result panel
    static var ocrTextHeader: String { s("ocrTextHeader") }
    static var ocrRecognizing: String { s("ocrRecognizing") }
    static var ocrNoText: String { s("ocrNoText") }
    static var ocrCopy: String { s("ocrCopy") }
    static var ocrCopied: String { s("ocrCopied") }
    static var ocrLineCopied: String { s("ocrLineCopied") }
    static var copyImageTextCopying: String { s("copyImageTextCopying") }
    static var copyImageTextCopied: String { s("copyImageTextCopied") }
    static var copyImageTextNoText: String { s("copyImageTextNoText") }

    // Image Merge workbench
    static var imageMergeWindowTitle: String { s("imageMergeWindowTitle") }
    static var imageMergeSources: String { s("imageMergeSources") }
    static var imageMergeAddFiles: String { s("imageMergeAddFiles") }
    static var imageMergeAddFromClipboard: String { s("imageMergeAddFromClipboard") }
    static var imageMergeImageList: String { s("imageMergeImageList") }
    static var imageMergeTemplate: String { s("imageMergeTemplate") }
    static var imageMergeTemplateHorizontal: String { s("imageMergeTemplateHorizontal") }
    static var imageMergeTemplateVertical: String { s("imageMergeTemplateVertical") }
    static var imageMergeTemplateGrid: String { s("imageMergeTemplateGrid") }
    static var imageMergeTemplateLongStitch: String { s("imageMergeTemplateLongStitch") }
    static var imageMergeLayout: String { s("imageMergeLayout") }
    static var imageMergeSpacing: String { s("imageMergeSpacing") }
    static var imageMergeMargin: String { s("imageMergeMargin") }
    static var imageMergeCornerRadius: String { s("imageMergeCornerRadius") }
    static var imageMergeBackground: String { s("imageMergeBackground") }
    static var imageMergeTransparent: String { s("imageMergeTransparent") }
    static var imageMergeSolid: String { s("imageMergeSolid") }
    static var imageMergeOutput: String { s("imageMergeOutput") }
    static var imageMergeCopy: String { s("imageMergeCopy") }
    static var imageMergeSave: String { s("imageMergeSave") }
    static var imageMergeContinueEditing: String { s("imageMergeContinueEditing") }
    static var imageMergeClose: String { s("imageMergeClose") }
    static var imageMergeEmptyTitle: String { s("imageMergeEmptyTitle") }
    static var imageMergeEmptyBody: String { s("imageMergeEmptyBody") }
    static var imageMergeClipboardSourceName: String { s("imageMergeClipboardSourceName") }
}

struct Defaults {
    private static var defaults: UserDefaults {
        UserDefaults.standard
    }

    static var doubleTapInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: "doubleTapInterval")
            return val > 0 ? val : 0.3
        }
        set {
            defaults.set(newValue, forKey: "doubleTapInterval")
        }
    }

    // Legacy screenshot hotkey preferences retained only for migration.
    // Modifiers are stored using the old numeric flag values.

    static var screenshotHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "screenshotHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "screenshotHotkeyKeyCode") }
    }

    static var screenshotHotkeyModifiers: Int {
        get { defaults.integer(forKey: "screenshotHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "screenshotHotkeyModifiers") }
    }

    static var hasCustomScreenshotHotkey: Bool {
        defaults.object(forKey: "screenshotHotkeyKeyCode") != nil
    }

    static func clearScreenshotHotkey() {
        defaults.removeObject(forKey: "screenshotHotkeyKeyCode")
        defaults.removeObject(forKey: "screenshotHotkeyModifiers")
    }

    static let selectionAspectRatioPresets: [CGFloat] = [
        1.0,
        2.35,
        3.0,
        3.0 / 2.0,
        4.0 / 3.0,
        9.0 / 16.0,
        16.0 / 9.0,
    ]

    static var selectionAspectRatio: Double {
        get {
            let ratio = defaults.double(forKey: "selectionAspectRatio")
            return ratio > 0 && ratio.isFinite ? ratio : 0
        }
        set {
            guard newValue > 0, newValue.isFinite else {
                clearSelectionAspectRatio()
                return
            }
            defaults.set(newValue, forKey: "selectionAspectRatio")
        }
    }

    static var hasSelectionAspectRatio: Bool {
        defaults.object(forKey: "selectionAspectRatio") != nil && selectionAspectRatio > 0
    }

    static func clearSelectionAspectRatio() {
        defaults.removeObject(forKey: "selectionAspectRatio")
    }

    private static func clearLegacyPinHotkey() {
        defaults.removeObject(forKey: "pinHotkeyKeyCode")
        defaults.removeObject(forKey: "pinHotkeyModifiers")
    }

    // Legacy pin-image hotkey preferences retained only for migration.

    static var selectedImagePinHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "selectedImagePinHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "selectedImagePinHotkeyKeyCode") }
    }

    static var selectedImagePinHotkeyModifiers: Int {
        get { defaults.integer(forKey: "selectedImagePinHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "selectedImagePinHotkeyModifiers") }
    }

    static var hasCustomSelectedImagePinHotkey: Bool {
        defaults.object(forKey: "selectedImagePinHotkeyKeyCode") != nil
    }

    static func clearSelectedImagePinHotkey() {
        defaults.removeObject(forKey: "selectedImagePinHotkeyKeyCode")
        defaults.removeObject(forKey: "selectedImagePinHotkeyModifiers")
    }

    static var clipboardImagePinHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "clipboardImagePinHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "clipboardImagePinHotkeyKeyCode") }
    }

    static var clipboardImagePinHotkeyModifiers: Int {
        get { defaults.integer(forKey: "clipboardImagePinHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "clipboardImagePinHotkeyModifiers") }
    }

    static var hasCustomClipboardImagePinHotkey: Bool {
        defaults.object(forKey: "clipboardImagePinHotkeyKeyCode") != nil
    }

    static func clearClipboardImagePinHotkey() {
        defaults.removeObject(forKey: "clipboardImagePinHotkeyKeyCode")
        defaults.removeObject(forKey: "clipboardImagePinHotkeyModifiers")
    }

    static var clipboardTextPinHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "clipboardTextPinHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "clipboardTextPinHotkeyKeyCode") }
    }

    static var clipboardTextPinHotkeyModifiers: Int {
        get { defaults.integer(forKey: "clipboardTextPinHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "clipboardTextPinHotkeyModifiers") }
    }

    static var hasCustomClipboardTextPinHotkey: Bool {
        defaults.object(forKey: "clipboardTextPinHotkeyKeyCode") != nil
    }

    static func clearClipboardTextPinHotkey() {
        defaults.removeObject(forKey: "clipboardTextPinHotkeyKeyCode")
        defaults.removeObject(forKey: "clipboardTextPinHotkeyModifiers")
    }

    static func resetShortcutHotkeysToDefaults() {
        clearScreenshotHotkey()
        clearLegacyPinHotkey()
        clearSelectedImagePinHotkey()
        clearClipboardImagePinHotkey()
        clearClipboardTextPinHotkey()
        clearSelectedImageEditHotkey()
        clearClipboardImageEditHotkey()
        clearTextRecognitionHotkey()
        clearCopyImageTextHotkey()
        clearImageMergeHotkey()
        clearFullScreenScreenshotHotkey()
        clearColorPickerHotkey()
        clearClipboardHotkey()
        clearFileSaveHotkey()
        clearPreviousHistoryImageHotkey()
        clearNextHistoryImageHotkey()
        clearHistoryPanelHotkey()
    }

    // Legacy image-edit hotkey preferences retained only for migration.

    static var selectedImageEditHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "selectedImageEditHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "selectedImageEditHotkeyKeyCode") }
    }

    static var selectedImageEditHotkeyModifiers: Int {
        get { defaults.integer(forKey: "selectedImageEditHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "selectedImageEditHotkeyModifiers") }
    }

    static var hasCustomSelectedImageEditHotkey: Bool {
        defaults.object(forKey: "selectedImageEditHotkeyKeyCode") != nil
    }

    static func clearSelectedImageEditHotkey() {
        defaults.removeObject(forKey: "selectedImageEditHotkeyKeyCode")
        defaults.removeObject(forKey: "selectedImageEditHotkeyModifiers")
    }

    static var clipboardImageEditHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "clipboardImageEditHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "clipboardImageEditHotkeyKeyCode") }
    }

    static var clipboardImageEditHotkeyModifiers: Int {
        get { defaults.integer(forKey: "clipboardImageEditHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "clipboardImageEditHotkeyModifiers") }
    }

    static var hasCustomClipboardImageEditHotkey: Bool {
        defaults.object(forKey: "clipboardImageEditHotkeyKeyCode") != nil
    }

    static func clearClipboardImageEditHotkey() {
        defaults.removeObject(forKey: "clipboardImageEditHotkeyKeyCode")
        defaults.removeObject(forKey: "clipboardImageEditHotkeyModifiers")
    }

    // Legacy OCR hotkey preferences retained only for migration.

    static var textRecognitionHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "textRecognitionHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "textRecognitionHotkeyKeyCode") }
    }

    static var textRecognitionHotkeyModifiers: Int {
        get { defaults.integer(forKey: "textRecognitionHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "textRecognitionHotkeyModifiers") }
    }

    static var hasCustomTextRecognitionHotkey: Bool {
        defaults.object(forKey: "textRecognitionHotkeyKeyCode") != nil
    }

    static func clearTextRecognitionHotkey() {
        defaults.removeObject(forKey: "textRecognitionHotkeyKeyCode")
        defaults.removeObject(forKey: "textRecognitionHotkeyModifiers")
    }

    static var copyImageTextHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "copyImageTextHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "copyImageTextHotkeyKeyCode") }
    }

    static var copyImageTextHotkeyModifiers: Int {
        get { defaults.integer(forKey: "copyImageTextHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "copyImageTextHotkeyModifiers") }
    }

    static var hasCustomCopyImageTextHotkey: Bool {
        defaults.object(forKey: "copyImageTextHotkeyKeyCode") != nil
    }

    static func clearCopyImageTextHotkey() {
        defaults.removeObject(forKey: "copyImageTextHotkeyKeyCode")
        defaults.removeObject(forKey: "copyImageTextHotkeyModifiers")
    }

    static var imageMergeHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "imageMergeHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "imageMergeHotkeyKeyCode") }
    }

    static var imageMergeHotkeyModifiers: Int {
        get { defaults.integer(forKey: "imageMergeHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "imageMergeHotkeyModifiers") }
    }

    static var hasCustomImageMergeHotkey: Bool {
        defaults.object(forKey: "imageMergeHotkeyKeyCode") != nil
    }

    static func clearImageMergeHotkey() {
        defaults.removeObject(forKey: "imageMergeHotkeyKeyCode")
        defaults.removeObject(forKey: "imageMergeHotkeyModifiers")
    }

    static var fullScreenScreenshotHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "fullScreenScreenshotHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "fullScreenScreenshotHotkeyKeyCode") }
    }

    static var fullScreenScreenshotHotkeyModifiers: Int {
        get { defaults.integer(forKey: "fullScreenScreenshotHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "fullScreenScreenshotHotkeyModifiers") }
    }

    static var hasCustomFullScreenScreenshotHotkey: Bool {
        defaults.object(forKey: "fullScreenScreenshotHotkeyKeyCode") != nil
    }

    static func clearFullScreenScreenshotHotkey() {
        defaults.removeObject(forKey: "fullScreenScreenshotHotkeyKeyCode")
        defaults.removeObject(forKey: "fullScreenScreenshotHotkeyModifiers")
    }

    static var colorPickerHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "colorPickerHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "colorPickerHotkeyKeyCode") }
    }

    static var colorPickerHotkeyModifiers: Int {
        get { defaults.integer(forKey: "colorPickerHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "colorPickerHotkeyModifiers") }
    }

    static var hasCustomColorPickerHotkey: Bool {
        defaults.object(forKey: "colorPickerHotkeyKeyCode") != nil
    }

    static func clearColorPickerHotkey() {
        defaults.removeObject(forKey: "colorPickerHotkeyKeyCode")
        defaults.removeObject(forKey: "colorPickerHotkeyModifiers")
    }

    static var imageMergeTemplate: ImageMergeTemplate {
        get {
            let rawValue = defaults.integer(forKey: "imageMergeTemplate")
            return ImageMergeTemplate(rawValue: rawValue) ?? .horizontal
        }
        set {
            defaults.set(newValue.rawValue, forKey: "imageMergeTemplate")
        }
    }

    static var imageMergeSpacing: Double {
        get {
            if defaults.object(forKey: "imageMergeSpacing") == nil {
                return 12
            }
            return min(max(defaults.double(forKey: "imageMergeSpacing"), 0), 80)
        }
        set {
            defaults.set(min(max(newValue.rounded(), 0), 80), forKey: "imageMergeSpacing")
        }
    }

    static var imageMergeMargin: Double {
        get {
            if defaults.object(forKey: "imageMergeMargin") == nil {
                return 24
            }
            return min(max(defaults.double(forKey: "imageMergeMargin"), 0), 120)
        }
        set {
            defaults.set(min(max(newValue.rounded(), 0), 120), forKey: "imageMergeMargin")
        }
    }

    static var imageMergeCornerRadius: Double {
        get {
            if defaults.object(forKey: "imageMergeCornerRadius") == nil {
                return 0
            }
            return min(max(defaults.double(forKey: "imageMergeCornerRadius"), 0), 80)
        }
        set {
            defaults.set(min(max(newValue.rounded(), 0), 80), forKey: "imageMergeCornerRadius")
        }
    }

    static var imageMergeBackgroundIsSolid: Bool {
        get { defaults.bool(forKey: "imageMergeBackgroundIsSolid") }
        set { defaults.set(newValue, forKey: "imageMergeBackgroundIsSolid") }
    }

    static var imageMergeBackgroundColorHex: String {
        get {
            normalizedHexColor(defaults.string(forKey: "imageMergeBackgroundColorHex")) ?? "#FFFFFF"
        }
        set {
            defaults.set(normalizedHexColor(newValue) ?? "#FFFFFF", forKey: "imageMergeBackgroundColorHex")
        }
    }

    static var autoRevealSavedFiles: Bool {
        get {
            if defaults.object(forKey: "autoRevealSavedFiles") == nil {
                return true
            }
            return defaults.bool(forKey: "autoRevealSavedFiles")
        }
        set {
            defaults.set(newValue, forKey: "autoRevealSavedFiles")
        }
    }

    static var defaultScreenshotSaveDirectory: URL {
        defaultDocumentsDirectory.appendingPathComponent("clipcap", isDirectory: true)
    }

    static var screenshotSaveDirectory: URL {
        get {
            normalizedDirectoryURL(
                defaults.string(forKey: "screenshotSaveDirectory"),
                fallback: defaultScreenshotSaveDirectory
            )
        }
        set {
            defaults.set(newValue.standardizedFileURL.path, forKey: "screenshotSaveDirectory")
        }
    }

    static let defaultImageFilenameTemplate = "clipcap-{date}-{time}"

    static var imageFilenameTemplate: String {
        get {
            normalizedFilenameTemplate(
                defaults.string(forKey: "imageFilenameTemplate"),
                fallback: defaultImageFilenameTemplate
            )
        }
        set {
            defaults.set(
                normalizedFilenameTemplate(newValue, fallback: defaultImageFilenameTemplate),
                forKey: "imageFilenameTemplate"
            )
        }
    }

    private static func normalizedFilenameTemplate(_ value: String?, fallback: String) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static var defaultDocumentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
    }

    private static func normalizedDirectoryURL(_ value: String?, fallback: URL) -> URL {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback.standardizedFileURL }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    static func filenameSequenceValue(scope: String, dayStamp: String?, consume: Bool) -> Int {
        if let dayStamp {
            let counterKey = "filenameDailyCounter.\(scope)"
            let dayKey = "filenameDailyCounterDay.\(scope)"
            let currentDay = defaults.string(forKey: dayKey)
            let currentValue = currentDay == dayStamp ? defaults.integer(forKey: counterKey) : 0
            let nextValue = currentValue + 1
            if consume {
                defaults.set(dayStamp, forKey: dayKey)
                defaults.set(nextValue, forKey: counterKey)
            }
            return nextValue
        }

        let key = "filenameCounter.\(scope)"
        let nextValue = defaults.integer(forKey: key) + 1
        if consume {
            defaults.set(nextValue, forKey: key)
        }
        return nextValue
    }

    // Custom copy-to-clipboard hotkey used inside the editor overlay.
    // This is matched locally against keyDown events, so it
    // may be bare (no modifiers). Presence must be checked via
    // `hasCustomClipboardHotkey` since key code 0 (`A`) is a valid value.

    private static func migrateLegacySaveHotkeyIfNeeded() {
        // Older builds stored this same hotkey under "saveHotkey*". Migrate
        // once on first read so existing users keep their binding.
        let migratedKey = "clipboardHotkeyMigrated"
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard defaults.object(forKey: "saveHotkeyKeyCode") != nil,
              defaults.object(forKey: "clipboardHotkeyKeyCode") == nil
        else { return }
        defaults.set(defaults.integer(forKey: "saveHotkeyKeyCode"), forKey: "clipboardHotkeyKeyCode")
        defaults.set(defaults.integer(forKey: "saveHotkeyModifiers"), forKey: "clipboardHotkeyModifiers")
        defaults.removeObject(forKey: "saveHotkeyKeyCode")
        defaults.removeObject(forKey: "saveHotkeyModifiers")
    }

    static var clipboardHotkeyKeyCode: Int {
        get {
            migrateLegacySaveHotkeyIfNeeded()
            return defaults.integer(forKey: "clipboardHotkeyKeyCode")
        }
        set { defaults.set(newValue, forKey: "clipboardHotkeyKeyCode") }
    }

    static var clipboardHotkeyModifiers: Int {
        get {
            migrateLegacySaveHotkeyIfNeeded()
            return defaults.integer(forKey: "clipboardHotkeyModifiers")
        }
        set { defaults.set(newValue, forKey: "clipboardHotkeyModifiers") }
    }

    static var hasCustomClipboardHotkey: Bool {
        migrateLegacySaveHotkeyIfNeeded()
        return defaults.object(forKey: "clipboardHotkeyKeyCode") != nil
    }

    static func clearClipboardHotkey() {
        defaults.removeObject(forKey: "clipboardHotkeyKeyCode")
        defaults.removeObject(forKey: "clipboardHotkeyModifiers")
    }

    // Custom save-to-file hotkey used inside the editor overlay to invoke
    // the configured-directory file save. When absent, defaults to ⌘S.
    // Matched locally against keyDown events, same as the clipboard hotkey.

    static var fileSaveHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "fileSaveHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "fileSaveHotkeyKeyCode") }
    }

    static var fileSaveHotkeyModifiers: Int {
        get { defaults.integer(forKey: "fileSaveHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "fileSaveHotkeyModifiers") }
    }

    static var hasCustomFileSaveHotkey: Bool {
        defaults.object(forKey: "fileSaveHotkeyKeyCode") != nil
    }

    static func clearFileSaveHotkey() {
        defaults.removeObject(forKey: "fileSaveHotkeyKeyCode")
        defaults.removeObject(forKey: "fileSaveHotkeyModifiers")
    }

    // History navigation hotkeys used inside the editor overlay. Defaults are
    // comma for previous and period for next. Like clipboard/save editor
    // hotkeys, bare keys are allowed because matching is local to the editor.

    static var previousHistoryImageHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "previousHistoryImageHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "previousHistoryImageHotkeyKeyCode") }
    }

    static var previousHistoryImageHotkeyModifiers: Int {
        get { defaults.integer(forKey: "previousHistoryImageHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "previousHistoryImageHotkeyModifiers") }
    }

    static var hasCustomPreviousHistoryImageHotkey: Bool {
        defaults.object(forKey: "previousHistoryImageHotkeyKeyCode") != nil
    }

    static func clearPreviousHistoryImageHotkey() {
        defaults.removeObject(forKey: "previousHistoryImageHotkeyKeyCode")
        defaults.removeObject(forKey: "previousHistoryImageHotkeyModifiers")
    }

    static var nextHistoryImageHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "nextHistoryImageHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "nextHistoryImageHotkeyKeyCode") }
    }

    static var nextHistoryImageHotkeyModifiers: Int {
        get { defaults.integer(forKey: "nextHistoryImageHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "nextHistoryImageHotkeyModifiers") }
    }

    static var hasCustomNextHistoryImageHotkey: Bool {
        defaults.object(forKey: "nextHistoryImageHotkeyKeyCode") != nil
    }

    static func clearNextHistoryImageHotkey() {
        defaults.removeObject(forKey: "nextHistoryImageHotkeyKeyCode")
        defaults.removeObject(forKey: "nextHistoryImageHotkeyModifiers")
    }

    // History panel shortcut. Defaults to unset; users can opt in from
    // Settings. The global hotkey opens the dialog mode when enabled, or the
    // notch mode when dialog mode is disabled.

    static var historyPanelHotkeyKeyCode: Int {
        get { defaults.integer(forKey: "historyPanelHotkeyKeyCode") }
        set { defaults.set(newValue, forKey: "historyPanelHotkeyKeyCode") }
    }

    static var historyPanelHotkeyModifiers: Int {
        get { defaults.integer(forKey: "historyPanelHotkeyModifiers") }
        set { defaults.set(newValue, forKey: "historyPanelHotkeyModifiers") }
    }

    static var hasCustomHistoryPanelHotkey: Bool {
        defaults.object(forKey: "historyPanelHotkeyKeyCode") != nil
    }

    static func clearHistoryPanelHotkey() {
        defaults.removeObject(forKey: "historyPanelHotkeyKeyCode")
        defaults.removeObject(forKey: "historyPanelHotkeyModifiers")
    }

    static var penColor: Int {
        get {
            let val = defaults.integer(forKey: "penColor")
            return val == 0 ? 0xFF0000 : val
        }
        set {
            defaults.set(newValue, forKey: "penColor")
        }
    }

    static var penWidth: Double {
        get {
            let val = defaults.double(forKey: "penWidth")
            return val > 0 ? val : 3.0
        }
        set {
            defaults.set(newValue, forKey: "penWidth")
        }
    }

    static let editorLineWidthMin: Double = 1
    static let editorLineWidthMax: Double = 16
    static let markerLineWidthMax: Double = 10

    static var lastEditorColorHex: String? {
        get {
            normalizedHexColor(defaults.string(forKey: "lastEditorColorHex"))
        }
        set {
            if let normalized = normalizedHexColor(newValue) {
                defaults.set(normalized, forKey: "lastEditorColorHex")
            } else {
                defaults.removeObject(forKey: "lastEditorColorHex")
            }
        }
    }

    static var lastEditorLineWidth: Double {
        get {
            if defaults.object(forKey: "lastEditorLineWidth") == nil {
                return 4.0
            }
            return clampedEditorLineWidth(defaults.double(forKey: "lastEditorLineWidth"))
        }
        set {
            defaults.set(clampedEditorLineWidth(newValue), forKey: "lastEditorLineWidth")
        }
    }

    static var lastMarkerColorHex: String? {
        get {
            normalizedHexColor(defaults.string(forKey: "lastMarkerColorHex"))
        }
        set {
            if let normalized = normalizedHexColor(newValue) {
                defaults.set(normalized, forKey: "lastMarkerColorHex")
            } else {
                defaults.removeObject(forKey: "lastMarkerColorHex")
            }
        }
    }

    static var lastMarkerLineWidth: Double {
        get {
            if defaults.object(forKey: "lastMarkerLineWidth") == nil {
                return 5.0
            }
            return clampedMarkerLineWidth(defaults.double(forKey: "lastMarkerLineWidth"))
        }
        set {
            defaults.set(clampedMarkerLineWidth(newValue), forKey: "lastMarkerLineWidth")
        }
    }

    static var mosaicBlockSize: Double {
        get {
            let val = defaults.double(forKey: "mosaicBlockSize")
            guard val > 0 else { return 12.0 }
            return min(max(val, mosaicBlockSizeMin), mosaicBlockSizeMax)
        }
        set {
            defaults.set(min(max(newValue, mosaicBlockSizeMin), mosaicBlockSizeMax), forKey: "mosaicBlockSize")
        }
    }

    static let mosaicBlockSizeMin: Double = 4
    static let mosaicBlockSizeMax: Double = 48

    static let textFontSizeMin: Double = 10
    static let textFontSizeMax: Double = 100

    static var lastTextFontSize: Double {
        get {
            if defaults.object(forKey: "lastTextFontSize") == nil {
                return 20
            }
            let val = defaults.double(forKey: "lastTextFontSize")
            return min(max(val, textFontSizeMin), textFontSizeMax)
        }
        set {
            defaults.set(min(max(newValue, textFontSizeMin), textFontSizeMax), forKey: "lastTextFontSize")
        }
    }

    /// Whether the text tool's outline checkbox was last left on.
    static var lastTextStroke: Bool {
        get { defaults.bool(forKey: "lastTextStroke") }
        set { defaults.set(newValue, forKey: "lastTextStroke") }
    }

    /// Whether the text tool's callout checkbox was last left on.
    static var lastTextCallout: Bool {
        get { defaults.bool(forKey: "lastTextCallout") }
        set { defaults.set(newValue, forKey: "lastTextCallout") }
    }

    /// Last rectangle/ellipse fill mode. Migrates the previous checkbox
    /// preference by treating its "on" state as the old opaque fill.
    static var lastShapeFillMode: ShapeFillMode {
        get {
            guard let raw = defaults.string(forKey: "lastShapeFillMode"),
                  let mode = ShapeFillMode(rawValue: raw) else {
                return defaults.bool(forKey: "lastShapeFill") ? .opaque : .none
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: "lastShapeFillMode")
            defaults.set(newValue.isFilled, forKey: "lastShapeFill")
        }
    }

    static var lastShapeStrokeStyle: ShapeStrokeStyle {
        get {
            guard let raw = defaults.string(forKey: "lastShapeStrokeStyle"),
                  let style = ShapeStrokeStyle(rawValue: raw) else {
                return .standard
            }
            return style
        }
        set {
            defaults.set(newValue.rawValue, forKey: "lastShapeStrokeStyle")
        }
    }

    /// Whether the rectangle/ellipse tool's legacy fill checkbox was last left on.
    static var lastShapeFill: Bool {
        get { lastShapeFillMode.isFilled }
        set { lastShapeFillMode = newValue ? .opaque : .none }
    }

    static var lastArrowStyle: ArrowStyle {
        get {
            guard let raw = defaults.string(forKey: "lastArrowStyle"),
                  let style = ArrowStyle(rawValue: raw) else {
                return .tapered
            }
            return style
        }
        set {
            defaults.set(newValue.rawValue, forKey: "lastArrowStyle")
        }
    }

    static var lastPickedColorHex: String? {
        get {
            guard historyCacheEnabled else { return nil }
            return normalizedHexColor(defaults.string(forKey: "lastPickedColorHex"))
        }
        set {
            if let normalized = normalizedHexColor(newValue) {
                defaults.set(normalized, forKey: "lastPickedColorHex")
            } else {
                defaults.removeObject(forKey: "lastPickedColorHex")
            }
        }
    }

    static var recentEmojis: [String] {
        get {
            normalizedEmojiList(defaults.stringArray(forKey: "recentEmojis") ?? [])
        }
        set {
            let normalized = normalizedEmojiList(newValue)
            if normalized.isEmpty {
                defaults.removeObject(forKey: "recentEmojis")
            } else {
                defaults.set(normalized, forKey: "recentEmojis")
            }
        }
    }

    private static func normalizedEmojiList(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { continue }
            result.append(trimmed)
            if result.count == 10 { break }
        }
        return result
    }

    private static func normalizedHexColor(_ hex: String?) -> String? {
        guard var trimmed = hex?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return nil
        }
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, UInt32(trimmed, radix: 16) != nil else { return nil }
        return "#\(trimmed)"
    }

    private static func clampedEditorLineWidth(_ width: Double) -> Double {
        min(max(width, editorLineWidthMin), editorLineWidthMax)
    }

    private static func clampedMarkerLineWidth(_ width: Double) -> Double {
        min(max(width, editorLineWidthMin), markerLineWidthMax)
    }

    static var lastBeautifyPresetID: String? {
        get { defaults.string(forKey: "lastBeautifyPresetID") }
        set { defaults.set(newValue, forKey: "lastBeautifyPresetID") }
    }

    static var lastBeautifyPadding: Double {
        get {
            if defaults.object(forKey: "lastBeautifyPadding") == nil {
                return 24
            }
            let val = defaults.double(forKey: "lastBeautifyPadding")
            return min(max(val, 0), 56)
        }
        set {
            defaults.set(min(max(newValue, 0), 56), forKey: "lastBeautifyPadding")
        }
    }

    static var lastBeautifyShadowEnabled: Bool {
        get {
            if defaults.object(forKey: "lastBeautifyShadowEnabled") == nil {
                return true
            }
            return defaults.bool(forKey: "lastBeautifyShadowEnabled")
        }
        set {
            defaults.set(newValue, forKey: "lastBeautifyShadowEnabled")
        }
    }

    static let historyCacheMin: Int = 10
    static let historyCacheMax: Int = 100
    static let historyCacheStep: Int = 10

    static var historyCacheEnabled: Bool {
        get {
            if defaults.object(forKey: "historyCacheEnabled") == nil {
                return true
            }
            return defaults.bool(forKey: "historyCacheEnabled")
        }
        set {
            let oldValue = historyCacheEnabled
            defaults.set(newValue, forKey: "historyCacheEnabled")
            if !newValue {
                lastPickedColorHex = nil
            }
            if oldValue != newValue {
                NotificationCenter.default.post(name: .historyCacheEnabledDidChange, object: nil)
            }
        }
    }

    static var historyCacheLimit: Int {
        get {
            if defaults.object(forKey: "historyCacheLimit") == nil {
                return 10
            }
            let val = defaults.integer(forKey: "historyCacheLimit")
            return normalizedHistoryCacheLimit(val)
        }
        set {
            defaults.set(normalizedHistoryCacheLimit(newValue), forKey: "historyCacheLimit")
            NotificationCenter.default.post(name: .historyCacheLimitDidChange, object: nil)
        }
    }

    private static func normalizedHistoryCacheLimit(_ value: Int) -> Int {
        let clamped = min(max(value, historyCacheMin), historyCacheMax)
        let offset = clamped - historyCacheMin
        let snapped = historyCacheMin + ((offset + historyCacheStep / 2) / historyCacheStep) * historyCacheStep
        return min(max(snapped, historyCacheMin), historyCacheMax)
    }

    static var historyPanelDialogEnabled: Bool {
        get {
            historyPanelDisplayMode == .dialog
        }
        set {
            if newValue {
                setHistoryPanelDisplayMode(.dialog)
            }
        }
    }

    static var historyPanelNotchEnabled: Bool {
        get {
            historyPanelDisplayMode == .notch
        }
        set {
            if newValue {
                setHistoryPanelDisplayMode(historyPanelNotchAvailable ? .notch : .dialog)
            }
        }
    }

    static var historyPanelNotchAvailable: Bool {
        DisplayCapabilities.supportsHistoryPanelNotch
    }

    private enum HistoryPanelDisplayMode {
        case dialog
        case notch
    }

    private static var historyPanelDisplayMode: HistoryPanelDisplayMode {
        let hasDialog = defaults.object(forKey: "historyPanelDialogEnabled") != nil
        let hasNotch = defaults.object(forKey: "historyPanelNotchEnabled") != nil
        guard hasDialog || hasNotch else {
            return historyPanelNotchAvailable ? .notch : .dialog
        }

        let dialog = hasDialog ? defaults.bool(forKey: "historyPanelDialogEnabled") : false
        let notch = hasNotch ? defaults.bool(forKey: "historyPanelNotchEnabled") : false
        if dialog { return .dialog }
        if notch, historyPanelNotchAvailable { return .notch }
        return .dialog
    }

    private static func setHistoryPanelDisplayMode(_ mode: HistoryPanelDisplayMode) {
        let mode = mode == .notch && !historyPanelNotchAvailable ? .dialog : mode
        let oldMode = historyPanelDisplayMode
        defaults.set(mode == .dialog, forKey: "historyPanelDialogEnabled")
        defaults.set(mode == .notch, forKey: "historyPanelNotchEnabled")
        if oldMode != mode {
            NotificationCenter.default.post(name: .historyPanelDisplayModesDidChange, object: nil)
        }
    }

    static var showMenuBar: Bool {
        get {
            if defaults.object(forKey: "showMenuBar") == nil {
                return true
            }
            return defaults.bool(forKey: "showMenuBar")
        }
        set {
            defaults.set(newValue, forKey: "showMenuBar")
        }
    }

    static var pinAcrossSpaces: Bool {
        get { defaults.bool(forKey: "pinAcrossSpaces") }
        set { defaults.set(newValue, forKey: "pinAcrossSpaces") }
    }

    // Window-capture drop shadow. When enabled, single-window screenshots get
    // rounded corners and a macOS-style drop shadow in the final output.
    // Rounded corners are always applied to window captures; this toggle only
    // governs the shadow.

    static let windowShadowSizeMin: Double = 6
    static let windowShadowSizeMax: Double = 60

    static var windowShadowEnabled: Bool {
        get {
            if defaults.object(forKey: "windowShadowEnabled") == nil {
                return true
            }
            return defaults.bool(forKey: "windowShadowEnabled")
        }
        set {
            defaults.set(newValue, forKey: "windowShadowEnabled")
        }
    }

    static var windowShadowSize: Double {
        get {
            if defaults.object(forKey: "windowShadowSize") == nil {
                return 22
            }
            let val = defaults.double(forKey: "windowShadowSize")
            return min(max(val, windowShadowSizeMin), windowShadowSizeMax)
        }
        set {
            defaults.set(min(max(newValue, windowShadowSizeMin), windowShadowSizeMax), forKey: "windowShadowSize")
        }
    }

    static var language: AppLanguage {
        get {
            // Explicit user choice wins; otherwise follow the system locale on
            // first launch so a fresh install opens in a familiar language.
            if let raw = defaults.string(forKey: "appLanguage"),
               let lang = AppLanguage(rawValue: raw) {
                return lang
            }
            return AppLanguage.systemDefault
        }
        set {
            let old = language
            defaults.set(newValue.rawValue, forKey: "appLanguage")
            if newValue != old {
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }
    }
}
