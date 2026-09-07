import SwiftUI
import ServiceManagement

/// A target entered in millions. Commits on every edit so there is nothing to save.
private struct TargetField: View {
    var value: Int
    var onCommit: (Int) -> Void

    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField("Target", text: $text)
                .frame(width: 78)
                .monospacedDigit()
            Text("million")
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: sync)
        .onChange(of: value) { _, _ in sync() }
        .onChange(of: text) { _, new in
            guard let m = Double(new.replacingOccurrences(of: ",", with: ".")), m > 0 else { return }
            onCommit(Int((m * 1e6).rounded()))
        }
    }

    private func sync() {
        let m = Double(value) / 1e6
        let formatted = m == m.rounded() ? String(format: "%.0f", m) : String(format: "%.2f", m)
        if formatted != text { text = formatted }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    @State private var alwaysOnTop = Prefs.shared.alwaysOnTop
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private let presets = [2, 5, 10, 20, 50, 500]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Providers") {
                    ForEach(store.orderedProviders) { id in
                        providerRow(id)
                    }
                }

                Section("Display") {
                    Picker("Show", selection: $store.mode) {
                        ForEach(DisplayMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(store.mode == .combined
                         ? "One ring for the enabled providers together, coloured by how close you are to the target. Hover the ring to split it by provider."
                         : "One small ring per provider, each against its own target.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(store.mode == .combined ? "Combined daily target" : "Daily targets") {
                    if store.mode == .combined {
                        LabeledContent("All providers") {
                            TargetField(value: store.combinedTarget) { store.combinedTarget = $0 }
                        }
                        HStack(spacing: 6) {
                            ForEach(presets, id: \.self) { m in
                                Button("\(m)M") { store.combinedTarget = m * 1_000_000 }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        Text("\(Fmt.grouped(store.combinedTarget)) tokens, resetting at local midnight.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.orderedProviders.filter { store.snapshot($0).quality != .unavailable }) { id in
                            LabeledContent(id.displayName) {
                                TargetField(value: store.target(id)) { store.setTarget($0, for: id) }
                            }
                        }
                        Text("Each ring resets at local midnight.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("What counts") {
                    Toggle("Count cache reads", isOn: $store.includeCacheReads)
                    Text(store.includeCacheReads
                         ? "Counting input, output, cache writes, and cache reads. Cache reads dominate, so expect hundreds of millions on a busy day."
                         : "Counting input, output, and cache writes. Cache reads are excluded, which keeps a heavy day in the single-digit millions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Panel") {
                    Picker("Refresh every", selection: $store.refreshMinutes) {
                        ForEach([1, 2, 5, 10, 15, 30], id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    Toggle("Show token breakdown", isOn: $store.showBreakdown)
                    Toggle("Float above other windows", isOn: $alwaysOnTop)
                        .onChange(of: alwaysOnTop) { _, newValue in
                            Prefs.shared.alwaysOnTop = newValue
                            AppDelegate.shared?.applyPanelLevel()
                        }
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                    if let loginError {
                        Text(loginError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Data") {
                    HStack {
                        Button("Re-scan from scratch") { store.rebuild() }
                        Spacer()
                        Text(Fmt.calls(store.combinedCounts.calls) + " today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text("Everything is read from local files. Nothing leaves your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                Spacer()
                Button("Done") { AppDelegate.shared?.closeSettings() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 640)
    }

    private func providerRow(_ id: ProviderID) -> some View {
        let snap = store.snapshot(id)
        return VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(
                get: { store.enabled.contains(id) },
                set: { on in
                    var next = store.enabled
                    if on { next.insert(id) } else { next.remove(id) }
                    // Keep at least one provider on, so the panel always has a figure.
                    if !next.isEmpty { store.enabled = next }
                }
            )) {
                HStack(spacing: 6) {
                    Circle().fill(id.tint).frame(width: 8, height: 8)
                    Text(id.displayName)
                    if !snap.installed {
                        Text("not installed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if snap.quality == .unavailable {
                        Text("no token data")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if snap.quality == .partial {
                        Text("partial data")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Text(qualityNote(id, snap))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func qualityNote(_ id: ProviderID, _ snap: ProviderSnapshot) -> String {
        guard snap.installed else {
            return "No data directory found at \(store.sourceDescription(id))."
        }
        switch id {
        case .claude:
            return "Per-call token counts with timestamps, so the figure is exact."
        case .codex:
            return "Per-turn token counts with timestamps, so the figure is exact. Codex reports cached input but no cache writes."
        case .cursor:
            return "Cursor records tokens for only some requests, and dates them by conversation rather than by message, so this figure is a floor and is marked with ≥."
        case .gemini:
            return "Per-message token counts with timestamps, so the figure is exact. Gemini reports cached input but no cache writes, and its Antigravity conversations carry no token figures."
        case .copilot:
            return "Copilot records no token counts on disk. Its session store keeps messages and timestamps with no token column, so there is no figure to show and it stays out of every total."
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription). Add Token Counter yourself in System Settings, General, Login Items."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
