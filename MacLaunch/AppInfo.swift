import AppKit
import Foundation

struct AppInfo: Identifiable {
    let name: String
    let url: URL
    let bundleIdentifier: String?
    let icon: NSImage
    let isSystemApp: Bool

    var id: String {
        bundleIdentifier ?? url.path
    }
}
