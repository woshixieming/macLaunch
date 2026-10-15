import AppKit
import Combine
import Darwin
import Foundation

enum AppReorderPlacement: String {
    case before
    case after
}

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [AppInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var pinnedAppIDs: [String] = []
    @Published private(set) var recentAppIDs: [String] = []
    @Published private(set) var libraryOrderIDs: [String] = []
    @Published private(set) var hiddenAppIDs: [String] = []

    private let settings: AppSettings
    private let userDefaults: UserDefaults
    private let pinnedAppsKey = "pinnedAppIDs"
    private let recentAppsKey = "recentAppIDs"
    private let libraryOrderKey = "libraryOrderIDs"
    private let hiddenAppsKey = "hiddenAppIDs"
    private var cancellables: Set<AnyCancellable> = []
    private var applicationFolderWatchers: [DispatchSourceFileSystemObject] = []
    private var reloadDebounceTask: Task<Void, Never>?
    private var shouldReloadAfterCurrentLoad = false

    init(settings: AppSettings, userDefaults: UserDefaults = .standard) {
        self.settings = settings
        self.userDefaults = userDefaults
        pinnedAppIDs = userDefaults.stringArray(forKey: pinnedAppsKey) ?? []
        recentAppIDs = userDefaults.stringArray(forKey: recentAppsKey) ?? []
        libraryOrderIDs = userDefaults.stringArray(forKey: libraryOrderKey) ?? []
        hiddenAppIDs = userDefaults.stringArray(forKey: hiddenAppsKey) ?? []

        settings.$recentAppsLimit
            .sink { [weak self] newLimit in
                guard let self else { return }
                self.recentAppIDs = Array(self.recentAppIDs.prefix(newLimit))
                self.persistRecentAppIDs()
            }
            .store(in: &cancellables)

        startObservingApplicationFolders()
    }

    deinit {
        reloadDebounceTask?.cancel()
        applicationFolderWatchers.forEach { $0.cancel() }
    }

    var visibleApps: [AppInfo] {
        let hiddenIDs = Set(hiddenAppIDs)
        return apps.filter { !hiddenIDs.contains($0.id) }
    }

    func removeIcon(for app: AppInfo) {
        guard !hiddenAppIDs.contains(app.id) else { return }
        hiddenAppIDs.append(app.id)
        userDefaults.set(hiddenAppIDs, forKey: hiddenAppsKey)
        pinnedAppIDs.removeAll { $0 == app.id }
        recentAppIDs.removeAll { $0 == app.id }
        persistPinnedAppIDs()
        persistRecentAppIDs()
    }

    func restoreRemovedIcons() {
        hiddenAppIDs = []
        userDefaults.set(hiddenAppIDs, forKey: hiddenAppsKey)
    }

    func reload() {
        guard !isLoading else {
            shouldReloadAfterCurrentLoad = true
            return
        }

        isLoading = true

        Task { [weak self] in
            guard let self else { return }
            let scannedApps = await Task.detached(priority: .userInitiated) {
                Self.scanInstalledApps()
            }.value

            apps = scannedApps
            normalizeLibraryOrder(with: scannedApps)
            isLoading = false

            if shouldReloadAfterCurrentLoad {
                shouldReloadAfterCurrentLoad = false
                scheduleReload(delayNanoseconds: 250_000_000)
            }
        }
    }

    func isPinned(_ app: AppInfo) -> Bool {
        pinnedAppIDs.contains(app.id)
    }

    func togglePinned(_ app: AppInfo) {
        if pinnedAppIDs.contains(app.id) {
            pinnedAppIDs.removeAll { $0 == app.id }
        } else {
            pinnedAppIDs.append(app.id)
        }

        persistPinnedAppIDs()
    }

    func movePinnedApp(_ sourceID: String, before targetID: String) {
        movePinnedApp(sourceID, relativeTo: targetID, placement: .before)
    }

    func movePinnedApp(_ sourceID: String, relativeTo targetID: String, placement: AppReorderPlacement) {
        guard
            sourceID != targetID,
            let reorderedIDs = reorderedIDs(
                pinnedAppIDs,
                moving: sourceID,
                relativeTo: targetID,
                placement: placement
            ),
            reorderedIDs != pinnedAppIDs
        else {
            return
        }

        pinnedAppIDs = reorderedIDs
        persistPinnedAppIDs()
    }

    func moveLibraryApp(_ sourceID: String, before targetID: String) {
        moveLibraryApp(sourceID, relativeTo: targetID, placement: .before)
    }

    func moveLibraryApp(_ sourceID: String, relativeTo targetID: String, placement: AppReorderPlacement) {
        guard sourceID != targetID else { return }

        guard
            let reorderedIDs = reorderedIDs(
                libraryOrderIDs,
                moving: sourceID,
                relativeTo: targetID,
                placement: placement
            ),
            reorderedIDs != libraryOrderIDs
        else {
            return
        }

        libraryOrderIDs = reorderedIDs
        persistLibraryOrderIDs()
    }

    func pinOrderIndex(for app: AppInfo) -> Int? {
        pinnedAppIDs.firstIndex(of: app.id)
    }

    func libraryOrderIndex(for app: AppInfo) -> Int? {
        libraryOrderIDs.firstIndex(of: app.id)
    }

    func recordLaunch(of app: AppInfo) {
        recentAppIDs.removeAll { $0 == app.id }
        recentAppIDs.insert(app.id, at: 0)
        recentAppIDs = Array(recentAppIDs.prefix(max(settings.recentAppsLimit, 1)))
        persistRecentAppIDs()
    }

    private func scheduleReload(delayNanoseconds: UInt64 = 500_000_000) {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    private func reorderedIDs(
        _ ids: [String],
        moving sourceID: String,
        relativeTo targetID: String,
        placement: AppReorderPlacement
    ) -> [String]? {
        guard
            sourceID != targetID,
            ids.contains(sourceID),
            ids.contains(targetID)
        else {
            return nil
        }

        var reordered = ids.filter { $0 != sourceID }
        guard let targetIndex = reordered.firstIndex(of: targetID) else { return nil }

        let insertionIndex = placement == .before ? targetIndex : targetIndex + 1
        reordered.insert(sourceID, at: min(insertionIndex, reordered.count))

        return reordered
    }

    private func startObservingApplicationFolders() {
        for root in Self.applicationRoots() where FileManager.default.fileExists(atPath: root.path) {
            let fileDescriptor = open(root.path, O_EVTONLY)
            guard fileDescriptor >= 0 else { continue }

            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend],
                queue: .main
            )

            watcher.setEventHandler { [weak self] in
                self?.scheduleReload()
            }

            watcher.setCancelHandler {
                close(fileDescriptor)
            }

            watcher.resume()
            applicationFolderWatchers.append(watcher)
        }
    }

    private func persistPinnedAppIDs() {
        userDefaults.set(pinnedAppIDs, forKey: pinnedAppsKey)
    }

    private func persistRecentAppIDs() {
        userDefaults.set(recentAppIDs, forKey: recentAppsKey)
    }

    private func persistLibraryOrderIDs() {
        userDefaults.set(libraryOrderIDs, forKey: libraryOrderKey)
    }

    private func normalizeLibraryOrder(with apps: [AppInfo]) {
        let currentIDs = Set(apps.map(\.id))
        var normalized = libraryOrderIDs.filter { currentIDs.contains($0) }

        let missingIDs = apps
            .map(\.id)
            .filter { !normalized.contains($0) }
            .sorted { lhs, rhs in
                let lhsName = apps.first(where: { $0.id == lhs })?.name ?? lhs
                let rhsName = apps.first(where: { $0.id == rhs })?.name ?? rhs
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

        normalized.append(contentsOf: missingIDs)

        guard normalized != libraryOrderIDs else { return }
        libraryOrderIDs = normalized
        persistLibraryOrderIDs()
    }

    nonisolated private static func applicationRoots() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
        ]
    }

    nonisolated private static func preferredLocalizations() -> [String] {
        let preferredLanguages = Locale.preferredLanguages
        var localizations = [
            "zh_CN",
            "zh_Hans",
            "zh_Hans_CN",
            "zh",
            "zh_HK",
            "zh_TW",
            "zh_Hant",
        ]

        for language in preferredLanguages {
            let variants = localizationVariants(for: language)
            localizations.append(contentsOf: variants)
        }

        var seen = Set<String>()
        return localizations.filter { seen.insert($0).inserted }
    }

    nonisolated private static func localizationVariants(for localization: String) -> [String] {
        let normalized = localization.replacingOccurrences(of: "-", with: "_")
        var variants = [normalized]

        if normalized.hasPrefix("zh_Hans") {
            variants.append("zh_CN")
        } else if normalized.hasPrefix("zh_Hant") {
            variants.append("zh_TW")
        }

        if let languageCode = normalized.split(separator: "_").first {
            variants.append(String(languageCode))
        }

        return variants
    }

    nonisolated private static func localizedAppName(for bundle: Bundle?, at url: URL) -> String {
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fallbackName = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent

        guard let bundle else { return fallbackName }

        let localizedName = localizedInfoPlistName(in: bundle)
            ?? bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.localizedInfoDictionary?["CFBundleName"] as? String

        guard let localizedName, !localizedName.isEmpty else {
            return fallbackName
        }

        return localizedName
    }

    nonisolated private static func localizedInfoPlistName(in bundle: Bundle) -> String? {
        for localization in preferredLocalizations() {
            for variant in localizationVariants(for: localization) {
                if let name = localizedInfoPlistName(in: bundle, localization: variant) {
                    return name
                }
            }
        }

        return nil
    }

    nonisolated private static func localizedInfoPlistName(in bundle: Bundle, localization: String) -> String? {
        if let infoPlistTable = bundle.url(forResource: "InfoPlist", withExtension: "loctable"),
           let localizations = NSDictionary(contentsOf: infoPlistTable) as? [String: Any],
           let values = localizations[localization] as? [String: Any],
           let name = appName(from: values)
        {
            return name
        }

        let stringLocalizations = [
            localization,
            localization.replacingOccurrences(of: "_", with: "-"),
        ]

        for stringLocalization in stringLocalizations {
            guard let infoPlistStrings = bundle.url(
                forResource: "InfoPlist",
                withExtension: "strings",
                subdirectory: nil,
                localization: stringLocalization
            ) else {
                continue
            }

            guard let values = NSDictionary(contentsOf: infoPlistStrings) as? [String: Any] else {
                continue
            }

            if let name = appName(from: values) {
                return name
            }
        }

        return nil
    }

    nonisolated private static func appName(from values: [String: Any]) -> String? {
        if let displayName = values["CFBundleDisplayName"] as? String, !displayName.isEmpty {
            return displayName
        }

        if let bundleName = values["CFBundleName"] as? String, !bundleName.isEmpty {
            return bundleName
        }

        return nil
    }

    nonisolated private static func scanInstalledApps() -> [AppInfo] {
        let fileManager = FileManager.default
        let roots = applicationRoots()

        var seen = Set<String>()
        var discoveredApps: [AppInfo] = []

        func appendApp(at item: URL) {
            let bundle = Bundle(url: item)
            let bundleIdentifier = bundle?.bundleIdentifier
            let appName = localizedAppName(for: bundle, at: item)
            let uniqueKey = bundleIdentifier ?? appName.lowercased()

            guard seen.insert(uniqueKey).inserted else { return }

            let icon = NSWorkspace.shared.icon(forFile: item.path)
            icon.size = NSSize(width: 64, height: 64)
            let isSystemApp = item.path.hasPrefix("/System/")

            discoveredApps.append(
                AppInfo(
                    name: appName,
                    url: item,
                    bundleIdentifier: bundleIdentifier,
                    icon: icon,
                    isSystemApp: isSystemApp
                )
            )
        }

        for root in roots where fileManager.fileExists(atPath: root.path) {
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            while let item = enumerator?.nextObject() as? URL {
                guard item.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }

                appendApp(at: item)
            }
        }

        // Safari can be a hidden symlink into the system Cryptex, skipped by enumeration.
        if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari"),
           fileManager.fileExists(atPath: safariURL.path) {
            appendApp(at: safariURL.resolvingSymlinksInPath())
        }

        return discoveredApps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
