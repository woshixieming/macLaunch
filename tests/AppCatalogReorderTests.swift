import Foundation

@main
struct AppCatalogReorderTests {
    private struct ReorderCase {
        let name: String
        let initial: [String]
        let source: String
        let target: String
        let placement: AppReorderPlacement
        let expected: [String]
    }

    @MainActor
    static func main() {
        let ids = ["A", "B", "C", "D"]
        let cases = [
            ReorderCase(name: "already before adjacent target", initial: ids,
                        source: "A", target: "B", placement: .before, expected: ids),
            ReorderCase(name: "already after adjacent target", initial: ids,
                        source: "B", target: "A", placement: .after, expected: ids),
            ReorderCase(name: "last item already in place", initial: ids,
                        source: "D", target: "C", placement: .after, expected: ids),
            ReorderCase(name: "drop on self before", initial: ids,
                        source: "B", target: "B", placement: .before, expected: ids),
            ReorderCase(name: "drop on self after", initial: ids,
                        source: "B", target: "B", placement: .after, expected: ids),
            ReorderCase(name: "missing source", initial: ids,
                        source: "missing", target: "B", placement: .before, expected: ids),
            ReorderCase(name: "missing target before", initial: ids,
                        source: "B", target: "missing", placement: .before, expected: ids),
            ReorderCase(name: "missing target after", initial: ids,
                        source: "B", target: "missing", placement: .after, expected: ids),
            ReorderCase(name: "both IDs missing", initial: ids,
                        source: "missing", target: "other", placement: .after, expected: ids),
            ReorderCase(name: "empty list", initial: [],
                        source: "A", target: "B", placement: .before, expected: []),
            ReorderCase(name: "single item", initial: ["A"],
                        source: "A", target: "A", placement: .after, expected: ["A"]),
            ReorderCase(name: "adjacent swap forward", initial: ids,
                        source: "A", target: "B", placement: .after, expected: ["B", "A", "C", "D"]),
            ReorderCase(name: "adjacent swap backward", initial: ids,
                        source: "B", target: "A", placement: .before, expected: ["B", "A", "C", "D"]),
            ReorderCase(name: "move forward before", initial: ids,
                        source: "A", target: "D", placement: .before, expected: ["B", "C", "A", "D"]),
            ReorderCase(name: "move forward after", initial: ids,
                        source: "A", target: "D", placement: .after, expected: ["B", "C", "D", "A"]),
            ReorderCase(name: "move backward before", initial: ids,
                        source: "D", target: "A", placement: .before, expected: ["D", "A", "B", "C"]),
            ReorderCase(name: "move backward after", initial: ids,
                        source: "D", target: "A", placement: .after, expected: ["A", "D", "B", "C"]),
        ]

        let suiteName = "com.ryan.MacLaunch.ReorderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(userDefaults: defaults)

        // Page-sized lists exercise the same global order used by cross-page drops.
        let pageSize = settings.libraryItemsPerPage
        let pagedIDs = (1...(pageSize * 2 + 1)).map { "app-\($0)" }
        let pageBoundaryCases = [
            ReorderCase(name: "already before next page", initial: pagedIDs,
                        source: pagedIDs[pageSize - 1], target: pagedIDs[pageSize],
                        placement: .before, expected: pagedIDs),
            ReorderCase(name: "already after previous page", initial: pagedIDs,
                        source: pagedIDs[pageSize], target: pagedIDs[pageSize - 1],
                        placement: .after, expected: pagedIDs),
            ReorderCase(name: "move into next page", initial: pagedIDs,
                        source: pagedIDs[0], target: pagedIDs[pageSize], placement: .after,
                        expected: Array(pagedIDs[1...pageSize]) + [pagedIDs[0]] + Array(pagedIDs[(pageSize + 1)...])),
            ReorderCase(name: "move into previous page", initial: pagedIDs,
                        source: pagedIDs[pageSize], target: pagedIDs[0], placement: .before,
                        expected: [pagedIDs[pageSize]] + Array(pagedIDs[..<pageSize]) + Array(pagedIDs[(pageSize + 1)...])),
        ]

        var passed = 0
        for testCase in cases + pageBoundaryCases {
            for isPinned in [false, true] {
                run(testCase, isPinned: isPinned, settings: settings, defaults: defaults)
                passed += 1
            }
        }
        print("PASS: \(passed) reorder cases, including persisted order after catalog recreation")
    }

    @MainActor
    private static func run(
        _ testCase: ReorderCase,
        isPinned: Bool,
        settings: AppSettings,
        defaults: UserDefaults
    ) {
        defaults.set(testCase.initial, forKey: "libraryOrderIDs")
        defaults.set(testCase.initial, forKey: "pinnedAppIDs")
        let catalog = AppCatalog(settings: settings, userDefaults: defaults)

        if isPinned {
            catalog.movePinnedApp(testCase.source, relativeTo: testCase.target, placement: testCase.placement)
        } else {
            catalog.moveLibraryApp(testCase.source, relativeTo: testCase.target, placement: testCase.placement)
        }

        let section = isPinned ? "pinned" : "library"
        let actual = isPinned ? catalog.pinnedAppIDs : catalog.libraryOrderIDs
        precondition(actual == testCase.expected, "\(section): \(testCase.name): unexpected order")
        let otherSection = isPinned ? catalog.libraryOrderIDs : catalog.pinnedAppIDs
        precondition(otherSection == testCase.initial, "\(section): changed the other section")

        let restored = AppCatalog(settings: settings, userDefaults: defaults)
        let persisted = isPinned ? restored.pinnedAppIDs : restored.libraryOrderIDs
        precondition(persisted == testCase.expected, "\(section): \(testCase.name): order not persisted")
        print("PASS: \(section): \(testCase.name)")
    }
}
