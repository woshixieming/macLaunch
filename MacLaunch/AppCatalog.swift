import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [AppInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var pinnedAppIDs: [String] = []
    @Published private(set) var recentAppIDs: [String] = []
    @Published private(set) var libraryOrderIDs: [String] = []

    private let settings: AppSettings
    private let pinnedAppsKey = "pinnedAppIDs"
    private let recentAppsKey = "recentAppIDs"
    private let libraryOrderKey = "libraryOrderIDs"
    private var cancellables: Set<AnyCancellable> = []
    private var applicationFolderWatchers: [DispatchSourceFileSystemObject] = []
    private var reloadDebounceTask: Task<Void, Never>?
    private var shouldReloadAfterCurrentLoad = false

    init(settings: AppSettings) {
        self.settings = settings
        pinnedAppIDs = UserDefaults.standard.stringArray(forKey: pinnedAppsKey) ?? []
        recentAppIDs = UserDefaults.standard.stringArray(forKey: recentAppsKey) ?? []
        libraryOrderIDs = UserDefaults.standard.stringArray(forKey: libraryOrderKey) ?? []

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
        guard
            sourceID != targetID,
            let sourceIndex = pinnedAppIDs.firstIndex(of: sourceID),
            let targetIndex = pinnedAppIDs.firstIndex(of: targetID)
        else {
            return
        }

        if sourceIndex < targetIndex, sourceIndex + 1 == targetIndex {
            return
        }

        let movedID = pinnedAppIDs.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        pinnedAppIDs.insert(movedID, at: adjustedTargetIndex)
        persistPinnedAppIDs()
    }

    func moveLibraryApp(_ sourceID: String, before targetID: String) {
        guard sourceID != targetID else { return }

        guard
            let sourceIndex = libraryOrderIDs.firstIndex(of: sourceID),
            let targetIndex = libraryOrderIDs.firstIndex(of: targetID)
        else {
            if libraryOrderIDs.last != sourceID {
                libraryOrderIDs.removeAll { $0 == sourceID }
                libraryOrderIDs.append(sourceID)
                persistLibraryOrderIDs()
            }
            return
        }

        if sourceIndex < targetIndex, sourceIndex + 1 == targetIndex {
            return
        }

        libraryOrderIDs.remove(at: sourceIndex)

        guard let refreshedTargetIndex = libraryOrderIDs.firstIndex(of: targetID) else {
            libraryOrderIDs.append(sourceID)
            persistLibraryOrderIDs()
            return
        }

        libraryOrderIDs.insert(sourceID, at: min(refreshedTargetIndex, libraryOrderIDs.count))
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

    private func startObservingApplicationFolders() {
        let queue = DispatchQueue(label: "com.ryan.MacLaunch.application-folder-watch")

        for root in Self.applicationRoots() where FileManager.default.fileExists(atPath: root.path) {
            let fileDescriptor = open(root.path, O_EVTONLY)
            guard fileDescriptor >= 0 else { continue }

            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend],
                queue: queue
            )

            watcher.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleReload()
                }
            }

            watcher.setCancelHandler {
                close(fileDescriptor)
            }

            watcher.resume()
            applicationFolderWatchers.append(watcher)
        }
    }

    private func persistPinnedAppIDs() {
        UserDefaults.standard.set(pinnedAppIDs, forKey: pinnedAppsKey)
    }

    private func persistRecentAppIDs() {
        UserDefaults.standard.set(recentAppIDs, forKey: recentAppsKey)
    }

    private func persistLibraryOrderIDs() {
        UserDefaults.standard.set(libraryOrderIDs, forKey: libraryOrderKey)
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

    nonisolated private static func scanInstalledApps() -> [AppInfo] {
        let fileManager = FileManager.default
        let roots = applicationRoots()

        var seen = Set<String>()
        var discoveredApps: [AppInfo] = []

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

                let bundle = Bundle(url: item)
                let bundleIdentifier = bundle?.bundleIdentifier
                let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                let appName = displayName ?? bundleName ?? item.deletingPathExtension().lastPathComponent
                let uniqueKey = bundleIdentifier ?? appName.lowercased()

                guard seen.insert(uniqueKey).inserted else {
                    continue
                }

                let icon = NSWorkspace.shared.icon(forFile: item.path)
                icon.size = NSSize(width: 64, height: 64)
                let isSystemApp = item.path.hasPrefix("/System/Applications")

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
        }

        return discoveredApps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
