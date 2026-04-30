import Carbon
import CoreGraphics
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    enum HotKeyPreset: String, CaseIterable, Identifiable {
        case optionSpace
        case controlSpace
        case commandOptionSpace
        case shiftOptionSpace

        var id: String { rawValue }

        var title: String {
            switch self {
            case .optionSpace:
                return "Option + Space"
            case .controlSpace:
                return "Control + Space"
            case .commandOptionSpace:
                return "Command + Option + Space"
            case .shiftOptionSpace:
                return "Shift + Option + Space"
            }
        }

        var carbonModifiers: UInt32 {
            switch self {
            case .optionSpace:
                return UInt32(optionKey)
            case .controlSpace:
                return UInt32(controlKey)
            case .commandOptionSpace:
                return UInt32(cmdKey | optionKey)
            case .shiftOptionSpace:
                return UInt32(shiftKey | optionKey)
            }
        }

        var keyCode: UInt32 {
            UInt32(kVK_Space)
        }
    }

    @Published var libraryGridColumns: Int {
        didSet { persist(libraryGridColumns, key: Self.libraryGridColumnsKey) }
    }

    @Published var libraryGridRows: Int {
        didSet { persist(libraryGridRows, key: Self.libraryGridRowsKey) }
    }

    @Published var recentAppsLimit: Int {
        didSet { persist(recentAppsLimit, key: Self.recentAppsLimitKey) }
    }

    @Published var recentAppsSectionEnabled: Bool {
        didSet { persist(recentAppsSectionEnabled, key: Self.recentAppsSectionEnabledKey) }
    }

    @Published var scrollPageSensitivity: Int {
        didSet { persist(scrollPageSensitivity, key: Self.scrollPageSensitivityKey) }
    }

    @Published var mouseWheelPagingEnabled: Bool {
        didSet { persist(mouseWheelPagingEnabled, key: Self.mouseWheelPagingEnabledKey) }
    }

    @Published var hotKeyPreset: HotKeyPreset {
        didSet { persist(hotKeyPreset.rawValue, key: Self.hotKeyPresetKey) }
    }

    private static let libraryGridColumnsKey = "settings.libraryGridColumns"
    private static let libraryGridRowsKey = "settings.libraryGridRows"
    private static let recentAppsLimitKey = "settings.recentAppsLimit"
    private static let recentAppsSectionEnabledKey = "settings.recentAppsSectionEnabled"
    private static let scrollPageSensitivityKey = "settings.scrollPageSensitivity"
    private static let mouseWheelPagingEnabledKey = "settings.mouseWheelPagingEnabled"
    private static let hotKeyPresetKey = "settings.hotKeyPreset"

    init(userDefaults: UserDefaults = .standard) {
        let storedLibraryGridColumns = userDefaults.object(forKey: Self.libraryGridColumnsKey) as? Int ?? 6
        let storedLibraryGridRows = userDefaults.object(forKey: Self.libraryGridRowsKey) as? Int ?? 8
        let storedRecentAppsLimit = userDefaults.object(forKey: Self.recentAppsLimitKey) as? Int ?? 12
        let storedRecentAppsSectionEnabled = userDefaults.object(forKey: Self.recentAppsSectionEnabledKey) as? Bool ?? true
        let storedScrollPageSensitivity = userDefaults.object(forKey: Self.scrollPageSensitivityKey) as? Int ?? 7
        let storedMouseWheelPagingEnabled = userDefaults.object(forKey: Self.mouseWheelPagingEnabledKey) as? Bool ?? true
        let storedHotKey = userDefaults.string(forKey: Self.hotKeyPresetKey)

        libraryGridColumns = min(max(storedLibraryGridColumns, 3), 10)
        libraryGridRows = min(max(storedLibraryGridRows, 2), 12)
        recentAppsLimit = min(max(storedRecentAppsLimit, 6), 20)
        recentAppsSectionEnabled = storedRecentAppsSectionEnabled
        scrollPageSensitivity = min(max(storedScrollPageSensitivity, 1), 10)
        mouseWheelPagingEnabled = storedMouseWheelPagingEnabled
        hotKeyPreset = HotKeyPreset(rawValue: storedHotKey ?? "") ?? .optionSpace
    }

    var libraryItemsPerPage: Int {
        libraryGridColumns * libraryGridRows
    }

    var scrollPageThreshold: CGFloat {
        CGFloat(max(2, 12 - scrollPageSensitivity))
    }

    private func persist(_ value: Any, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
