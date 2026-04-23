import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    private struct GridPreset: Identifiable {
        let columns: Int
        let rows: Int

        var id: String { "\(columns)x\(rows)" }
    }

    private let presets: [GridPreset] = [
        .init(columns: 6, rows: 6),
        .init(columns: 6, rows: 8),
        .init(columns: 7, rows: 8),
        .init(columns: 8, rows: 8),
        .init(columns: 8, rows: 9),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Mac Launch")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 10) {
                Text("全局快捷键")
                    .font(.headline)

                Picker("全局快捷键", selection: $settings.hotKeyPreset) {
                    ForEach(AppSettings.HotKeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("最近使用数量")
                    .font(.headline)

                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(settings.recentAppsLimit) },
                            set: { settings.recentAppsLimit = Int($0.rounded()) }
                        ),
                        in: 6...20,
                        step: 1
                    )

                    Text("\(settings.recentAppsLimit)")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("鼠标滚轮翻页")
                    .font(.headline)

                Toggle("启用鼠标滚轮直接翻页", isOn: $settings.mouseWheelPagingEnabled)

                Text("开启后，鼠标滚轮会直接翻页，不和触控板灵敏度共用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("滚轮翻页灵敏度")
                    .font(.headline)

                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(settings.scrollPageSensitivity) },
                            set: { settings.scrollPageSensitivity = Int($0.rounded()) }
                        ),
                        in: 1...10,
                        step: 1
                    )

                    Text("\(settings.scrollPageSensitivity)")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }

                HStack {
                    Text("仅触控板")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("更敏捷")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("库区列数")
                    .font(.headline)

                HStack {
                    Stepper(
                        value: $settings.libraryGridColumns,
                        in: 3...10,
                        step: 1
                    ) {
                        Text("\(settings.libraryGridColumns) 列")
                            .monospacedDigit()
                    }

                    Spacer()

                    Text("每页 \(settings.libraryItemsPerPage) 个应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(settings.libraryGridColumns) },
                        set: { settings.libraryGridColumns = Int($0.rounded()) }
                    ),
                    in: 3...10,
                    step: 1
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("库区行数")
                    .font(.headline)

                HStack {
                    Stepper(
                        value: $settings.libraryGridRows,
                        in: 2...12,
                        step: 1
                    ) {
                        Text("\(settings.libraryGridRows) 行")
                            .monospacedDigit()
                    }

                    Spacer()

                    Text("自动适配显示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(settings.libraryGridRows) },
                        set: { settings.libraryGridRows = Int($0.rounded()) }
                    ),
                    in: 2...12,
                    step: 1
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("常用方案")
                    .font(.headline)

                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        Button {
                            settings.libraryGridColumns = preset.columns
                            settings.libraryGridRows = preset.rows
                        } label: {
                            Text("\(preset.columns) x \(preset.rows)")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(settings.libraryGridColumns == preset.columns && settings.libraryGridRows == preset.rows ? .accentColor : .secondary.opacity(0.18))
                    }
                }
            }

            Text("关闭面板不会退出应用，修改会立即生效。鼠标滚轮和触控板现在是分开控制的。")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(24)
        .frame(width: 420)
        .background(SettingsWindowAccessor())
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        }
    }
}
