import SwiftUI

// MARK: - Update check

private enum UpdateState {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL)
    case failed
}

private func fetchLatestRelease() async -> (tag: String, url: URL)? {
    guard let apiURL = URL(string: "https://api.github.com/repos/Noah0025/Phrased/releases/latest") else { return nil }
    var request = URLRequest(url: apiURL)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 10
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = json["tag_name"] as? String,
          let htmlURL = json["html_url"] as? String,
          let url = URL(string: htmlURL)
    else { return nil }
    return (tag, url)
}

private func isNewer(_ remote: String, than local: String) -> Bool {
    let clean: (String) -> [Int] = { v in
        v.trimmingCharacters(in: .init(charactersIn: "v"))
            .split(separator: ".")
            .compactMap { Int($0) }
    }
    let r = clean(remote), l = clean(local)
    for i in 0..<max(r.count, l.count) {
        let rv = i < r.count ? r[i] : 0
        let lv = i < l.count ? l[i] : 0
        if rv != lv { return rv > lv }
    }
    return false
}

// MARK: - About pane

extension SettingsView {
    var aboutPane: some View {
        AboutSettingsPane()
    }
}

private struct AboutSettingsPane: View {
    @State private var updateState: UpdateState = .idle

    private let repoURL = URL(string: "https://github.com/Noah0025/Phrased")!
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: PhrasedSpacing.lg) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Phrased")
                .font(.title2.bold())

            Text(String(format: String(localized: "settings.about.version_format"), currentVersion, buildNumber))
                .foregroundColor(.secondary)

            Text(Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "")
                .font(.caption)
                .foregroundColor(.secondary)

            // MARK: Update status
            updateStatusView

            Button("settings.about.view_on_github") {
                NSWorkspace.shared.open(repoURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PhrasedSpacing.xxl)
        .onAppear { checkForUpdates() }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateState {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("settings.about.update.checking")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .upToDate:
            Label("settings.about.update.up_to_date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.secondary)

        case .available(let version, let url):
            VStack(spacing: 6) {
                Label(
                    String(format: String(localized: "settings.about.update.available_format"), version),
                    systemImage: "arrow.down.circle.fill"
                )
                .font(.caption)
                .foregroundColor(.accentColor)

                Button("settings.about.update.download") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

        case .failed:
            Button {
                checkForUpdates()
            } label: {
                Label("settings.about.update.check", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    private func checkForUpdates() {
        updateState = .checking
        Task {
            guard let (tag, url) = await fetchLatestRelease() else {
                await MainActor.run { updateState = .failed }
                return
            }
            await MainActor.run {
                updateState = isNewer(tag, than: currentVersion)
                    ? .available(version: tag, url: url)
                    : .upToDate
            }
        }
    }
}
