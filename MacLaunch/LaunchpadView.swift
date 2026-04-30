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
    @State private var lastPinnedDropTargetID: String?
    @State private var lastLibraryDropTargetID: String?
    @State private var selectedTarget: SelectionTarget?
    @State private var scrollAccumulator: CGFloat = 0

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
        catalog.pinnedAppIDs.compactMap { id in
            catalog.apps.first(where: { $0.id == id })
        }
    }

    private var recentApps: [AppInfo] {
        guard settings.recentAppsSectionEnabled else { return [] }

        return catalog.recentAppIDs.compactMap { id in
            catalog.apps.first(where: { $0.id == id && !catalog.isPinned($0) })
        }
    }

    private var libraryApps: [AppInfo] {
        catalog.apps.filter { app in
            !catalog.isPinned(app)
        }
            .sorted { lhs, rhs in
                if lhs.isSystemApp != rhs.isSystemApp {
                    return !lhs.isSystemApp && rhs.isSystemApp
                }

                switch (catalog.libraryOrderIndex(for: lhs), catalog.libraryOrderIndex(for: rhs)) {
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
        catalog.apps.count
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
        .onChange(of: catalog.apps.count) { _, _ in
            currentPage = 0
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

            ZStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 26) {
                        ForEach(currentPageApps) { app in
                            Button {
                                launch(app)
                            } label: {
                                AppTile(
                                    app: app,
                                    isPinned: false,
                                    isSelected: isSelected(app, in: .library),
                                    showSurface: false
                                )
                            }
                            .buttonStyle(.plain)
                            .opacity(draggedLibraryAppID == app.id ? 0.45 : 1)
                            .onDrag {
                                draggedLibraryAppID = app.id
                                lastLibraryDropTargetID = nil
                                return NSItemProvider(object: app.id as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: LibraryReorderDropDelegate(
                                    targetApp: app,
                                    catalog: catalog,
                                    draggedAppID: $draggedLibraryAppID,
                                    lastDropTargetID: $lastLibraryDropTargetID
                                )
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollIndicators(.hidden)

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
                                    currentPage: safeCurrentPage,
                                    totalPages: pages.count,
                                    draggedAppID: $draggedLibraryAppID,
                                    onMoveToPage: moveLibraryDragToPreviousPage
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
                                    currentPage: safeCurrentPage,
                                    totalPages: pages.count,
                                    draggedAppID: $draggedLibraryAppID,
                                    onMoveToPage: moveLibraryDragToNextPage
                                )
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasMultiplePages {
                pageControls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近使用")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(recentApps) { app in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                launch(app)
                            } label: {
                                AppTile(
                                    app: app,
                                    isPinned: false,
                                    accent: .blue,
                                    isSelected: isSelected(app, in: .recent),
                                    isCompact: true
                                )
                                    .frame(width: 94)
                            }
                            .buttonStyle(.plain)

                            Button {
                                catalog.togglePinned(app)
                            } label: {
                                Image(systemName: "pin")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(9)
                                    .background(Circle().fill(Color.black.opacity(0.26)))
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .help("固定到常用区")
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
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

            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(pinnedApps) { app in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                launch(app)
                            } label: {
                                AppTile(
                                    app: app,
                                    isPinned: true,
                                    isSelected: isSelected(app, in: .pinned)
                                )
                                    .frame(width: 132)
                                    .opacity(draggedPinnedAppID == app.id ? 0.45 : 1)
                            }
                            .buttonStyle(.plain)
                            .onDrag {
                                draggedPinnedAppID = app.id
                                lastPinnedDropTargetID = nil
                                return NSItemProvider(object: app.id as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: PinnedReorderDropDelegate(
                                    targetApp: app,
                                    catalog: catalog,
                                    draggedAppID: $draggedPinnedAppID,
                                    lastDropTargetID: $lastPinnedDropTargetID
                                )
                            )

                            Button {
                                catalog.togglePinned(app)
                            } label: {
                                Image(systemName: "pin.slash")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(9)
                                    .background(Circle().fill(Color.black.opacity(0.26)))
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .help("取消固定")
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
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
        catalog.apps.first(where: { $0.id == target.appID })
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

            if dominantDelta < 0 {
                goToNextPage()
            } else {
                goToPreviousPage()
            }
            return true
        }

        scrollAccumulator += dominantDelta
        let threshold: CGFloat = settings.scrollPageThreshold

        guard abs(scrollAccumulator) >= threshold else {
            return true
        }

        if scrollAccumulator < 0 {
            goToNextPage()
        } else {
            goToPreviousPage()
        }

        scrollAccumulator = 0
        return true
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

    private func moveLibraryDragToNextPage() {
        guard
            let draggedAppID = draggedLibraryAppID,
            safeCurrentPage < pages.count - 1
        else {
            return
        }

        let targetPage = safeCurrentPage + 1
        guard let targetAppID = pages[targetPage].first?.id else { return }

        currentPage = targetPage
        catalog.moveLibraryApp(draggedAppID, before: targetAppID)
        selectedTarget = SelectionTarget(section: .library, appID: targetAppID)
        lastLibraryDropTargetID = nil
    }

    private func moveLibraryDragToPreviousPage() {
        guard
            let draggedAppID = draggedLibraryAppID,
            safeCurrentPage > 0
        else {
            return
        }

        let targetPage = safeCurrentPage - 1
        guard let targetAppID = pages[targetPage].first?.id else { return }

        currentPage = targetPage
        catalog.moveLibraryApp(draggedAppID, before: targetAppID)
        selectedTarget = SelectionTarget(section: .library, appID: targetAppID)
        lastLibraryDropTargetID = nil
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

private struct AppTile: View {
    let app: AppInfo
    let isPinned: Bool
    var accent: Color = .clear
    var isSelected = false
    var isCompact = false
    var showSurface = true

    var body: some View {
        VStack(spacing: isCompact ? 8 : 10) {
            Image(nsImage: app.icon)
                .resizable()
                .scaledToFit()
                .frame(width: isCompact ? 44 : 68, height: isCompact ? 44 : 68)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 8)

            Text(app.name)
                .font(.system(size: isCompact ? 12 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .frame(height: isCompact ? 16 : 18)
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
        .shadow(color: showSurface && isSelected ? .white.opacity(0.26) : .clear, radius: 16)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: isSelected)
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

private struct PinnedReorderDropDelegate: DropDelegate {
    let targetApp: AppInfo
    let catalog: AppCatalog
    @Binding var draggedAppID: String?
    @Binding var lastDropTargetID: String?

    func dropEntered(info: DropInfo) {
        guard let draggedAppID, lastDropTargetID != targetApp.id else { return }
        lastDropTargetID = targetApp.id
        catalog.movePinnedApp(draggedAppID, before: targetApp.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedAppID = nil
        lastDropTargetID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedAppID != nil
    }
}

private struct LibraryReorderDropDelegate: DropDelegate {
    let targetApp: AppInfo
    let catalog: AppCatalog
    @Binding var draggedAppID: String?
    @Binding var lastDropTargetID: String?

    func dropEntered(info: DropInfo) {
        guard let draggedAppID, lastDropTargetID != targetApp.id else { return }
        lastDropTargetID = targetApp.id
        catalog.moveLibraryApp(draggedAppID, before: targetApp.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedAppID = nil
        lastDropTargetID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedAppID != nil
    }
}

private struct LibraryPageFlipDropDelegate: DropDelegate {
    enum Direction {
        case previous
        case next
    }

    let direction: Direction
    let currentPage: Int
    let totalPages: Int
    @Binding var draggedAppID: String?
    let onMoveToPage: () -> Void

    func dropEntered(info: DropInfo) {
        guard draggedAppID != nil else { return }

        switch direction {
        case .previous where currentPage > 0:
            onMoveToPage()
        case .next where currentPage < totalPages - 1:
            onMoveToPage()
        default:
            break
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedAppID != nil else { return false }

        switch direction {
        case .previous where currentPage > 0:
            onMoveToPage()
        case .next where currentPage < totalPages - 1:
            onMoveToPage()
        default:
            break
        }

        self.draggedAppID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedAppID != nil
    }
}
