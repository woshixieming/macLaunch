import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LaunchpadView: View {
    private enum SectionKind: String {
        case pinned
        case recent
        case library
    }

    private struct SelectionTarget: Equatable {
        let section: SectionKind
        let appID: String
    }

    @ObservedObject var settings: AppSettings
    let onDismiss: () -> Void
    @StateObject private var catalog: AppCatalog
    @State private var currentPage = 0
    @State private var draggedPinnedAppID: String?
    @State private var draggedLibraryAppID: String?
    @State private var pinnedReorderTarget: ReorderTarget?
    @State private var libraryReorderTarget: ReorderTarget?
    @State private var selectedTarget: SelectionTarget?
    @State private var scrollAccumulator: CGFloat = 0
    @State private var lastScrollPageChangeTimestamp: TimeInterval = 0
    @State private var activeDragPageFlipDirection: LibraryPageFlipDirection?

    private let scrollPageChangeCooldown: TimeInterval = 0.18

    private var navigationColumns: Int {
        settings.libraryGridColumns
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 132), spacing: 20), count: navigationColumns)
    }

    init(settings: AppSettings, onDismiss: @escaping () -> Void) {
        self.settings = settings
        self.onDismiss = onDismiss
        _catalog = StateObject(wrappedValue: AppCatalog(settings: settings))
    }

    private var pinnedApps: [AppInfo] {
        let appsByID = Dictionary(uniqueKeysWithValues: catalog.visibleApps.map { ($0.id, $0) })

        return catalog.pinnedAppIDs.compactMap { id in
            appsByID[id]
        }
    }

    private var recentApps: [AppInfo] {
        guard settings.recentAppsSectionEnabled else { return [] }

        let appsByID = Dictionary(uniqueKeysWithValues: catalog.visibleApps.map { ($0.id, $0) })

        return catalog.recentAppIDs.compactMap { id in
            guard let app = appsByID[id], !catalog.isPinned(app) else { return nil }
            return app
        }
    }

    private var libraryApps: [AppInfo] {
        let libraryOrderIndexByID = Dictionary(
            uniqueKeysWithValues: catalog.libraryOrderIDs.enumerated().map { index, id in
                (id, index)
            }
        )

        return catalog.visibleApps.filter { app in
            !catalog.isPinned(app)
        }
            .sorted { lhs, rhs in
                if lhs.isSystemApp != rhs.isSystemApp {
                    return !lhs.isSystemApp && rhs.isSystemApp
                }

                switch (libraryOrderIndexByID[lhs.id], libraryOrderIndexByID[rhs.id]) {
                case let (left?, right?):
                    if left != right { return left < right }
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                default:
                    break
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var pages: [[AppInfo]] {
        guard !libraryApps.isEmpty else { return [[]] }

        let itemsPerPage = settings.libraryItemsPerPage

        return stride(from: 0, to: libraryApps.count, by: itemsPerPage).map { startIndex in
            Array(libraryApps[startIndex ..< min(startIndex + itemsPerPage, libraryApps.count)])
        }
    }

    private var safeCurrentPage: Int {
        min(currentPage, max(pages.count - 1, 0))
    }

    private var currentPageApps: [AppInfo] {
        pages[safeCurrentPage]
    }

    private var hasMultiplePages: Bool {
        pages.count > 1
    }

    private var orderedTargets: [SelectionTarget] {
        pinnedApps.map { SelectionTarget(section: .pinned, appID: $0.id) }
            + recentApps.map { SelectionTarget(section: .recent, appID: $0.id) }
            + currentPageApps.map { SelectionTarget(section: .library, appID: $0.id) }
    }

    private var totalAppCount: Int {
        catalog.visibleApps.count
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.18),
                    Color(red: 0.10, green: 0.13, blue: 0.24),
                    Color(red: 0.13, green: 0.17, blue: 0.31),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()
            BackgroundDismissView(onBackgroundClick: onDismiss)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                header
                content
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
        }
        .background(EscapeKeyHandler {
            onDismiss()
        } onKeyDown: { event in
            handleKeyDown(event)
        } onScrollWheel: { event in
            handleScrollWheel(event)
        })
        .task {
            catalog.reload()
        }
        .onChange(of: catalog.visibleApps.count) { _, _ in
            currentPage = 0
            syncSelection()
        }
        .onChange(of: settings.libraryGridColumns) { _, _ in
            currentPage = 0
        }
        .onChange(of: settings.libraryGridRows) { _, _ in
            currentPage = 0
        }
        .onChange(of: currentPage) { _, _ in
            syncSelection()
            scrollAccumulator = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .launcherFocusSearch)) { _ in
            catalog.reload()
            currentPage = 0
            selectedTarget = nil
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Text("Mac Launch")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                StatPill(label: "\(totalAppCount) 个应用", systemImage: "square.grid.3x3.fill")

                if !catalog.pinnedAppIDs.isEmpty {
                    StatPill(label: "\(catalog.pinnedAppIDs.count) 个已固定", systemImage: "pin.fill")
                }

                if settings.recentAppsSectionEnabled && !catalog.recentAppIDs.isEmpty {
                    StatPill(label: "\(recentApps.count) 个最近使用", systemImage: "clock.fill")
                }

                if catalog.isLoading {
                    StatPill(label: "正在扫描", systemImage: "arrow.trianglehead.2.clockwise")
                }

                StatPill(label: "Esc 关闭", systemImage: "escape")

                if !catalog.hiddenAppIDs.isEmpty {
                    Button {
                        catalog.restoreRemovedIcons()
                    } label: {
                        Label("恢复已删除图标", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.16))
                }
            }
        }
        .padding(.top, 10)
    }

    private var content: some View {
        VStack(spacing: 18) {
            if !pinnedApps.isEmpty {
                pinnedSection
            }

            if settings.recentAppsSectionEnabled && !recentApps.isEmpty {
                recentSection
            }

            HStack {
                Text("应用列表")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("拖拽可排序")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        LazyVGrid(columns: columns, spacing: 26) {
                            ForEach(currentPageApps) { app in
                                AppTile(
                                    app: app,
                                    isPinned: false,
                                    isSelected: isSelected(app, in: .library),
                                    showSurface: false,
                                    reorderPlacement: libraryReorderTarget?.appID == app.id
                                        ? libraryReorderTarget?.placement
                                        : nil,
                                    onLaunch: {
                                        launch(app)
                                    },
                                    onDismiss: onDismiss,
                                    onRemove: { catalog.removeIcon(for: app) },
                                    onDragStart: {
                                        draggedPinnedAppID = nil
                                        draggedLibraryAppID = app.id
                                        libraryReorderTarget = nil
                                        activeDragPageFlipDirection = nil
                                        return NSItemProvider(object: app.id as NSString)
                                    }
                                )
                                .opacity(1)
                                .background(
                                    ReorderDropZones(
                                        targetApp: app,
                                        draggedAppID: $draggedLibraryAppID,
                                        reorderTarget: $libraryReorderTarget,
                                        onDrop: { sourceAppID, placement in
                                            performReorderWithoutAnimation {
                                                catalog.moveLibraryApp(
                                                    sourceAppID,
                                                    relativeTo: app.id,
                                                    placement: placement
                                                )
                                            }
                                        },
                                        onTargetEntered: {
                                            activeDragPageFlipDirection = nil
                                        }
                                    )
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 20)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onDismiss()
                        }

                        BackgroundDismissView(onBackgroundClick: onDismiss)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if hasMultiplePages {
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: 48)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: LibraryPageFlipDropDelegate(
                                        direction: .previous,
                                        draggedAppID: $draggedLibraryAppID,
                                        onMoveToPage: {
                                            moveLibraryDragToPage(direction: .previous)
                                        },
                                        onDropEnded: clearLibraryDragState
                                    )
                                )

                            Spacer(minLength: 0)

                            Color.clear
                                .frame(width: 48)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: LibraryPageFlipDropDelegate(
                                        direction: .next,
                                        draggedAppID: $draggedLibraryAppID,
                                        onMoveToPage: {
                                            moveLibraryDragToPage(direction: .next)
                                        },
                                        onDropEnded: clearLibraryDragState
                                    )
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if hasMultiplePages {
                    BackgroundDismissView(onBackgroundClick: onDismiss)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)

                    pageControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近使用")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ZStack {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(recentApps) { app in
                            AppTile(
                                app: app,
                                isPinned: false,
                                accent: .blue,
                                isSelected: isSelected(app, in: .recent),
                                isCompact: true,
                                onLaunch: {
                                    launch(app)
                                },
                                onDismiss: onDismiss,
                                onRemove: { catalog.removeIcon(for: app) }
                            )
                            .frame(width: 94)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onDismiss()
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .frame(height: 128)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("固定应用")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("拖拽可排序")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }

            ZStack {
                ScrollView(.horizontal) {
                    HStack(spacing: 18) {
                        ForEach(pinnedApps) { app in
                            AppTile(
                                app: app,
                                isPinned: true,
                                isSelected: isSelected(app, in: .pinned),
                                reorderPlacement: pinnedReorderTarget?.appID == app.id
                                    ? pinnedReorderTarget?.placement
                                    : nil,
                                onLaunch: {
                                    launch(app)
                                },
                                onDismiss: onDismiss,
                                onRemove: { catalog.removeIcon(for: app) },
                                onDragStart: {
                                    draggedLibraryAppID = nil
                                    draggedPinnedAppID = app.id
                                    pinnedReorderTarget = nil
                                    return NSItemProvider(object: app.id as NSString)
                                }
                            )
                            .frame(width: 132)
                            .opacity(1)
                            .background(
                                ReorderDropZones(
                                    targetApp: app,
                                    draggedAppID: $draggedPinnedAppID,
                                    reorderTarget: $pinnedReorderTarget,
                                    onDrop: { sourceAppID, placement in
                                        performReorderWithoutAnimation {
                                            catalog.movePinnedApp(
                                                sourceAppID,
                                                relativeTo: app.id,
                                                placement: placement
                                            )
                                        }
                                    }
                                )
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onDismiss()
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .frame(height: 156)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private var pageControls: some View {
        HStack(spacing: 14) {
            Button {
                currentPage = max(safeCurrentPage - 1, 0)
            } label: {
                Label("上一页", systemImage: "chevron.left")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.16))
            .disabled(safeCurrentPage == 0)

            HStack(spacing: 8) {
                ForEach(Array(pages.indices), id: \.self) { index in
                    Circle()
                        .fill(index == safeCurrentPage ? .white : .white.opacity(0.28))
                        .frame(width: index == safeCurrentPage ? 10 : 8, height: index == safeCurrentPage ? 10 : 8)
                }
            }

            Text("第 \(safeCurrentPage + 1) / \(pages.count) 页")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            Button {
                currentPage = min(safeCurrentPage + 1, pages.count - 1)
            } label: {
                Label("下一页", systemImage: "chevron.right")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.16))
            .disabled(safeCurrentPage >= pages.count - 1)
        }
    }

    private func launch(_ app: AppInfo) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            guard error == nil else { return }

            Task { @MainActor in
                catalog.recordLaunch(of: app)
                onDismiss()
            }
        }
    }

    private func app(for target: SelectionTarget) -> AppInfo? {
        catalog.visibleApps.first(where: { $0.id == target.appID })
    }

    private func isSelected(_ app: AppInfo, in section: SectionKind) -> Bool {
        selectedTarget == SelectionTarget(section: section, appID: app.id)
    }

    private func syncSelection() {
        guard !orderedTargets.isEmpty else {
            selectedTarget = nil
            return
        }

        if let selectedTarget, orderedTargets.contains(selectedTarget) {
            return
        }

        self.selectedTarget = orderedTargets.first
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
           let pinnedIndex = digitShortcutIndex(for: event),
           pinnedIndex < pinnedApps.count {
            launch(pinnedApps[pinnedIndex])
            return true
        }

        switch event.keyCode {
        case 123:
            moveSelectionLeft()
            return true
        case 124:
            moveSelectionRight()
            return true
        case 125:
            moveSelectionDown()
            return true
        case 126:
            moveSelectionUp()
            return true
        case 36, 76:
            if let selectedTarget, let app = app(for: selectedTarget) {
                launch(app)
                return true
            }
            return false
        default:
            return false
        }
    }

    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard hasMultiplePages else { return false }

        let verticalDelta = event.scrollingDeltaY
        let horizontalDelta = event.scrollingDeltaX
        let dominantDelta = abs(horizontalDelta) > abs(verticalDelta) ? horizontalDelta : verticalDelta

        guard dominantDelta != 0 else {
            return false
        }

        if !event.hasPreciseScrollingDeltas {
            guard settings.mouseWheelPagingEnabled else {
                return false
            }

            return accumulateScroll(delta: dominantDelta, threshold: 1, timestamp: event.timestamp)
        }

        if event.momentumPhase != [] {
            return true
        }

        return accumulateScroll(delta: dominantDelta, threshold: settings.scrollPageThreshold, timestamp: event.timestamp)
    }

    private func accumulateScroll(delta: CGFloat, threshold: CGFloat, timestamp: TimeInterval) -> Bool {
        guard canChangePage(at: timestamp) else { return true }

        if scrollAccumulator != 0, delta * scrollAccumulator < 0 {
            scrollAccumulator = 0
        }

        scrollAccumulator += delta

        guard abs(scrollAccumulator) >= threshold else { return true }

        let previousPage = safeCurrentPage
        if scrollAccumulator < 0 {
            goToNextPage()
        } else {
            goToPreviousPage()
        }

        scrollAccumulator = 0
        if safeCurrentPage != previousPage {
            lastScrollPageChangeTimestamp = timestamp
        }

        return true
    }

    private func canChangePage(at timestamp: TimeInterval) -> Bool {
        guard lastScrollPageChangeTimestamp > 0 else { return true }
        return timestamp - lastScrollPageChangeTimestamp >= scrollPageChangeCooldown
    }

    private func digitShortcutIndex(for event: NSEvent) -> Int? {
        guard let characters = event.charactersIgnoringModifiers, let first = characters.first else {
            return nil
        }

        switch first {
        case "1"..."9":
            return Int(String(first)).map { $0 - 1 }
        default:
            return nil
        }
    }

    private func moveSelectionLeft() {
        syncSelection()
        guard let selectedTarget else { return }

        switch selectedTarget.section {
        case .pinned:
            moveInLinearSection(pinnedApps, section: .pinned, delta: -1)
        case .recent:
            moveInLinearSection(recentApps, section: .recent, delta: -1)
        case .library:
            moveInGridHorizontally(delta: -1)
        }
    }

    private func moveSelectionRight() {
        syncSelection()
        guard let selectedTarget else { return }

        switch selectedTarget.section {
        case .pinned:
            moveInLinearSection(pinnedApps, section: .pinned, delta: 1)
        case .recent:
            moveInLinearSection(recentApps, section: .recent, delta: 1)
        case .library:
            moveInGridHorizontally(delta: 1)
        }
    }

    private func moveSelectionDown() {
        syncSelection()
        guard let currentSelection = selectedTarget else { return }

        switch currentSelection.section {
        case .pinned:
            if !recentApps.isEmpty {
                self.selectedTarget = SelectionTarget(section: .recent, appID: recentApps.first!.id)
            } else if !currentPageApps.isEmpty {
                self.selectedTarget = SelectionTarget(section: .library, appID: currentPageApps.first!.id)
            }
        case .recent:
            if !currentPageApps.isEmpty {
                self.selectedTarget = SelectionTarget(section: .library, appID: currentPageApps.first!.id)
            }
        case .library:
            moveInGridVertically(delta: navigationColumns)
        }
    }

    private func moveSelectionUp() {
        syncSelection()
        guard let currentSelection = selectedTarget else { return }

        switch currentSelection.section {
        case .pinned:
            return
        case .recent:
            if !pinnedApps.isEmpty {
                self.selectedTarget = SelectionTarget(section: .pinned, appID: pinnedApps.first!.id)
            }
        case .library:
            guard let currentIndex = currentPageApps.firstIndex(where: { $0.id == currentSelection.appID }) else { return }

            let nextIndex = currentIndex - navigationColumns
            if nextIndex >= 0 {
                self.selectedTarget = SelectionTarget(section: .library, appID: currentPageApps[nextIndex].id)
            } else if safeCurrentPage > 0 {
                moveToAdjacentPage(pageDelta: -1, preferredColumn: currentIndex % navigationColumns, edge: .bottom)
            } else if !recentApps.isEmpty {
                self.selectedTarget = SelectionTarget(section: .recent, appID: recentApps.first!.id)
            } else if !pinnedApps.isEmpty {
                self.selectedTarget = SelectionTarget(section: .pinned, appID: pinnedApps.first!.id)
            }
        }
    }

    private func moveInLinearSection(_ apps: [AppInfo], section: SectionKind, delta: Int) {
        guard
            let selectedTarget,
            let currentIndex = apps.firstIndex(where: { $0.id == selectedTarget.appID })
        else {
            return
        }

        let nextIndex = max(0, min(currentIndex + delta, apps.count - 1))
        self.selectedTarget = SelectionTarget(section: section, appID: apps[nextIndex].id)
    }

    private func moveInGridHorizontally(delta: Int) {
        guard
            let selectedTarget,
            let currentIndex = currentPageApps.firstIndex(where: { $0.id == selectedTarget.appID }),
            !currentPageApps.isEmpty
        else {
            return
        }

        let nextIndex = currentIndex + delta

        if nextIndex >= 0, nextIndex < currentPageApps.count {
            self.selectedTarget = SelectionTarget(section: .library, appID: currentPageApps[nextIndex].id)
            return
        }

        if nextIndex < 0, safeCurrentPage > 0 {
            moveToAdjacentPage(pageDelta: -1, preferredColumn: nil, edge: .trailing)
            return
        }

        if nextIndex >= currentPageApps.count, safeCurrentPage < pages.count - 1 {
            moveToAdjacentPage(pageDelta: 1, preferredColumn: nil, edge: .leading)
            return
        }

        let clampedIndex = max(0, min(nextIndex, currentPageApps.count - 1))
        self.selectedTarget = SelectionTarget(section: .library, appID: currentPageApps[clampedIndex].id)
    }

    private func moveInGridVertically(delta: Int) {
        guard
            let selectedTarget,
            let currentIndex = currentPageApps.firstIndex(where: { $0.id == selectedTarget.appID }),
            !currentPageApps.isEmpty
        else {
            return
        }

        let nextIndex = currentIndex + delta

        if nextIndex >= 0, nextIndex < currentPageApps.count {
            self.selectedTarget = SelectionTarget(section: .library, appID: currentPageApps[nextIndex].id)
            return
        }

        if nextIndex >= currentPageApps.count, safeCurrentPage < pages.count - 1 {
            moveToAdjacentPage(pageDelta: 1, preferredColumn: currentIndex % navigationColumns, edge: .top)
            return
        }

        let clampedIndex = max(0, min(nextIndex, currentPageApps.count - 1))
        self.selectedTarget = SelectionTarget(section: .library, appID: currentPageApps[clampedIndex].id)
    }

    private enum PageEdge {
        case leading
        case trailing
        case top
        case bottom
    }

    private func moveToAdjacentPage(pageDelta: Int, preferredColumn: Int?, edge: PageEdge) {
        let targetPage = safeCurrentPage + pageDelta
        guard pages.indices.contains(targetPage), !pages[targetPage].isEmpty else { return }

        currentPage = targetPage
        let targetApps = pages[targetPage]

        let targetIndex: Int
        switch edge {
        case .leading:
            targetIndex = 0
        case .trailing:
            targetIndex = max(targetApps.count - 1, 0)
        case .top:
            let column = preferredColumn ?? 0
            targetIndex = min(column, targetApps.count - 1)
        case .bottom:
            let column = preferredColumn ?? 0
            let lastRowStart = max(((targetApps.count - 1) / navigationColumns) * navigationColumns, 0)
            targetIndex = min(lastRowStart + column, targetApps.count - 1)
        }

        self.selectedTarget = SelectionTarget(section: .library, appID: targetApps[targetIndex].id)
    }

    private func goToNextPage() {
        guard safeCurrentPage < pages.count - 1 else { return }
        moveToAdjacentPage(pageDelta: 1, preferredColumn: currentColumnIndex(), edge: .top)
    }

    private func goToPreviousPage() {
        guard safeCurrentPage > 0 else { return }
        moveToAdjacentPage(pageDelta: -1, preferredColumn: currentColumnIndex(), edge: .bottom)
    }

    private func moveLibraryDragToPage(direction: LibraryPageFlipDirection) {
        guard
            draggedLibraryAppID != nil,
            activeDragPageFlipDirection != direction
        else {
            return
        }

        let pageDelta = direction == .previous ? -1 : 1
        let targetPage = safeCurrentPage + pageDelta
        guard
            pages.indices.contains(targetPage),
            let targetAppID = pages[targetPage].first?.id
        else {
            return
        }

        activeDragPageFlipDirection = direction
        currentPage = targetPage
        selectedTarget = SelectionTarget(section: .library, appID: targetAppID)
    }

    private func clearLibraryDragState() {
        draggedLibraryAppID = nil
        libraryReorderTarget = nil
        activeDragPageFlipDirection = nil
    }

    private func currentColumnIndex() -> Int {
        guard
            let selectedTarget,
            let currentIndex = currentPageApps.firstIndex(where: { $0.id == selectedTarget.appID })
        else {
            return 0
        }

        return currentIndex % navigationColumns
    }
}

private struct ReorderTarget: Equatable {
    let appID: String
    let placement: AppReorderPlacement
}

private enum LibraryPageFlipDirection {
    case previous
    case next
}

private struct AppTile: View {
    let app: AppInfo
    let isPinned: Bool
    var accent: Color = .clear
    var isSelected = false
    var isCompact = false
    var showSurface = true
    var reorderPlacement: AppReorderPlacement? = nil
    let onLaunch: () -> Void
    let onDismiss: () -> Void
    let onRemove: () -> Void
    var onDragStart: (() -> NSItemProvider)? = nil

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }

            interactiveContent
                .modifier(AppTileDragModifier(onDragStart: onDragStart))
                .contextMenu {
                    Button(role: .destructive, action: onRemove) {
                        Label("删除图标", systemImage: "trash")
                    }
                }
        }
        .padding(.horizontal, isCompact ? 8 : 10)
        .padding(.vertical, isCompact ? 10 : 14)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 108 : 148, maxHeight: isCompact ? 108 : 148)
        .background(
            showSurface ? tileFillColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            if showSurface {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? .white : tileBorderColor, lineWidth: isSelected ? 2 : 1)
            }
        }
        .overlay(alignment: reorderPlacement == .before ? .leading : .trailing) {
            if reorderPlacement != nil {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.yellow)
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .shadow(color: .yellow.opacity(0.7), radius: 5)
            }
        }
        .shadow(color: showSurface && isSelected ? .white.opacity(0.26) : .clear, radius: 16)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.08), value: reorderPlacement)
    }

    private var interactiveContent: some View {
        VStack(spacing: isCompact ? 8 : 10) {
            Button {
                onLaunch()
            } label: {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: isCompact ? 44 : 68, height: isCompact ? 44 : 68)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onLaunch()
            } label: {
                Text(app.name)
                    .font(.system(size: isCompact ? 12 : 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: isCompact ? 78 : 112)
                    .frame(height: isCompact ? 16 : 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var tileFillColor: Color {
        if isPinned {
            return Color.orange.opacity(0.18)
        }

        if accent != .clear {
            return accent.opacity(0.16)
        }

        return Color.white.opacity(0.11)
    }

    private var tileBorderColor: Color {
        if isPinned {
            return .orange.opacity(0.65)
        }

        if accent != .clear {
            return accent.opacity(0.55)
        }

        return .white.opacity(0.14)
    }
}

private struct AppTileDragModifier: ViewModifier {
    let onDragStart: (() -> NSItemProvider)?

    func body(content: Content) -> some View {
        if let onDragStart {
            content.onDrag(onDragStart)
        } else {
            content
        }
    }
}

private struct StatPill: View {
    let label: String
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.10), in: Capsule())
    }
}

private struct ReorderDropZones: View {
    let targetApp: AppInfo
    @Binding var draggedAppID: String?
    @Binding var reorderTarget: ReorderTarget?
    let onDrop: (String, AppReorderPlacement) -> Void
    var onTargetEntered: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            reorderZone(placement: .before)
            reorderZone(placement: .after)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reorderZone(placement: AppReorderPlacement) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.text],
                delegate: AppReorderDropDelegate(
                    targetAppID: targetApp.id,
                    placement: placement,
                    draggedAppID: $draggedAppID,
                    reorderTarget: $reorderTarget,
                    onDrop: onDrop,
                    onTargetEntered: onTargetEntered
                )
            )
    }
}

private struct AppReorderDropDelegate: DropDelegate {
    let targetAppID: String
    let placement: AppReorderPlacement
    @Binding var draggedAppID: String?
    @Binding var reorderTarget: ReorderTarget?
    let onDrop: (String, AppReorderPlacement) -> Void
    let onTargetEntered: () -> Void

    func dropEntered(info: DropInfo) {
        updateReorderTarget()
    }

    func dropExited(info: DropInfo) {
        guard reorderTarget == ReorderTarget(appID: targetAppID, placement: placement) else { return }
        reorderTarget = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceAppID = draggedAppID else { return false }

        onDrop(sourceAppID, placement)
        draggedAppID = nil
        reorderTarget = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateReorderTarget()
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedAppID != nil
    }

    private func updateReorderTarget() {
        guard draggedAppID != nil else { return }
        reorderTarget = ReorderTarget(appID: targetAppID, placement: placement)
        onTargetEntered()
    }
}

private func performReorderWithoutAnimation(_ updates: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, updates)
}

private struct LibraryPageFlipDropDelegate: DropDelegate {
    let direction: LibraryPageFlipDirection
    @Binding var draggedAppID: String?
    let onMoveToPage: () -> Void
    let onDropEnded: () -> Void

    func dropEntered(info: DropInfo) {
        guard draggedAppID != nil else { return }
        onMoveToPage()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedAppID != nil else { return false }
        onDropEnded()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedAppID != nil
    }
}
