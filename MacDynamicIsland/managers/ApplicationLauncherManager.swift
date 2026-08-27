import AppKit
import Foundation

struct LaunchableApplication: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
}

@MainActor
final class ApplicationLauncherManager: ObservableObject {
    static let shared = ApplicationLauncherManager()

    @Published private(set) var applications: [LaunchableApplication] = []
    @Published private(set) var isLoading = false

    private struct UsageRecord: Codable {
        var launchCount: Int
        var lastLaunchedAt: Date
    }

    private static let usageDefaultsKey = "applicationLauncherUsage"

    /// Useful utilities that should stay easy to reach without overtaking learned usage.
    private static let frontBundleIdentifiers = [
        "com.apple.ActivityMonitor"
    ]

    /// The user's current Dock apps, kept at medium priority and in Dock order.
    /// Running apps and usage learned from this launcher always take priority.
    private static let dockBundleIdentifiers = [
        "com.google.Chrome",
        "com.apple.MobileSMS",
        "com.apple.Photos",
        "com.apple.mobilephone",
        "com.tencent.xinWeChat",
        "com.tencent.qq",
        "com.apple.systempreferences",
        "com.netease.163music",
        "com.apple.Music",
        "com.bytedance.douyin.desktop",
        "com.bilibili.bilibiliPC",
        "com.youku.mac",
        "io.github.clash-verge-rev.clash-verge-rev",
        "com.openai.codex",
        "com.bot.pc.doubao",
        "com.moonshot.kimichat",
        "com.lemon.lvpro",
        "com.tencent.Lemon"
    ]

    private var hasLoaded = false
    private var discoveredApplications: [LaunchableApplication] = []
    private let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()
    private var usageRecords: [String: UsageRecord]
    private var refreshTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.usageDefaultsKey),
           let records = try? JSONDecoder().decode([String: UsageRecord].self, from: data)
        {
            usageRecords = records
        } else {
            usageRecords = [:]
        }
    }

    func loadIfNeeded(force: Bool = false) async {
        guard force || !hasLoaded else { return }
        await refreshApplications()
    }

    /// Re-scans the Applications folders. This is intentionally separate from the
    /// initial-load check so the launcher refresh control always performs real work.
    func refreshApplications() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]

        let scanned = await Task.detached(priority: .utility) {
            Self.scanApplications(in: roots)
        }.value
        discoveredApplications = scanned
        applications = ranked(scanned)
        iconCache.removeAllObjects()
        hasLoaded = true
    }

    /// Keeps the launcher current only while its view is visible. A long interval
    /// avoids repeatedly walking all Applications folders during normal use.
    func startMonitoring() {
        guard refreshTask == nil else { return }

        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, let self else { return }
                await self.refreshApplications()
            }
        }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
        iconCache.removeAllObjects()
    }

    func icon(for application: LaunchableApplication) -> NSImage {
        let key = application.id as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }

        let loaded = NSWorkspace.shared.icon(forFile: application.url.path)
        let pixelWidth = max(1, Int(loaded.size.width))
        let pixelHeight = max(1, Int(loaded.size.height))
        iconCache.setObject(loaded, forKey: key, cost: pixelWidth * pixelHeight * 4)
        return loaded
    }

    func open(_ application: LaunchableApplication) {
        recordLaunch(of: application)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration)
    }

    func isRunning(_ application: LaunchableApplication) -> Bool {
        !runningInstances(of: application).isEmpty
    }

    func quit(_ application: LaunchableApplication) {
        let instances = runningInstances(of: application)
        guard !instances.isEmpty else { return }

        Task { [weak self] in
            let helperHandledRequest = await XPCHelperClient.shared.terminateApplication(
                bundleIdentifier: application.id
            )
            if !helperHandledRequest {
                for instance in instances {
                    instance.terminate()
                }
            }

            try? await Task.sleep(for: .milliseconds(800))
            self?.refreshRanking()
        }
    }

    func refreshRanking() {
        guard !discoveredApplications.isEmpty else { return }
        applications = ranked(discoveredApplications)
    }

    private func recordLaunch(of application: LaunchableApplication) {
        var record = usageRecords[application.id] ?? UsageRecord(launchCount: 0, lastLaunchedAt: .distantPast)
        record.launchCount += 1
        record.lastLaunchedAt = Date()
        usageRecords[application.id] = record

        if let data = try? JSONEncoder().encode(usageRecords) {
            UserDefaults.standard.set(data, forKey: Self.usageDefaultsKey)
        }
        refreshRanking()
    }

    private func runningInstances(of application: LaunchableApplication) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { runningApplication in
            if runningApplication.bundleIdentifier == application.id {
                return true
            }

            guard let runningURL = runningApplication.bundleURL else { return false }
            return runningURL.standardizedFileURL == application.url.standardizedFileURL
        }
    }

    private func ranked(_ source: [LaunchableApplication]) -> [LaunchableApplication] {
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )

        return source.sorted { lhs, rhs in
            let left = rankingKey(for: lhs, runningBundleIDs: runningBundleIDs)
            let right = rankingKey(for: rhs, runningBundleIDs: runningBundleIDs)

            if left.group != right.group { return left.group < right.group }
            if left.launchCount != right.launchCount { return left.launchCount > right.launchCount }
            if left.lastLaunchedAt != right.lastLaunchedAt { return left.lastLaunchedAt > right.lastLaunchedAt }
            if left.priorityIndex != right.priorityIndex { return left.priorityIndex < right.priorityIndex }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func rankingKey(
        for application: LaunchableApplication,
        runningBundleIDs: Set<String>
    ) -> (group: Int, launchCount: Int, lastLaunchedAt: Date, priorityIndex: Int) {
        let usage = usageRecords[application.id]
        let frontIndex = Self.frontBundleIdentifiers.firstIndex(of: application.id)
        let dockIndex = Self.dockBundleIdentifiers.firstIndex(of: application.id) ?? Int.max

        let group: Int
        if runningBundleIDs.contains(application.id) {
            group = 0
        } else if usage != nil {
            group = 1
        } else if frontIndex != nil {
            group = 2
        } else if dockIndex != Int.max {
            group = 3
        } else {
            group = 4
        }

        return (
            group,
            usage?.launchCount ?? 0,
            usage?.lastLaunchedAt ?? .distantPast,
            frontIndex ?? dockIndex
        )
    }

    nonisolated private static func scanApplications(in roots: [URL]) -> [LaunchableApplication] {
        var discovered: [LaunchableApplication] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .nameKey]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                let bundle = Bundle(url: url)
                let identifier = bundle?.bundleIdentifier ?? url.path
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                discovered.append(LaunchableApplication(id: identifier, name: displayName, url: url))
            }
        }

        return deduplicated(discovered).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Some apps leave an older copy behind or ship under different bundle IDs.
    /// Keep one result for each bundle ID and visible app name.
    nonisolated private static func deduplicated(
        _ applications: [LaunchableApplication]
    ) -> [LaunchableApplication] {
        let uniqueIdentifiers = applications.reduce(into: [String: LaunchableApplication]()) { result, app in
            if let existing = result[app.id] {
                result[app.id] = preferred(app, over: existing)
            } else {
                result[app.id] = app
            }
        }

        return uniqueIdentifiers.values.reduce(into: [String: LaunchableApplication]()) { result, app in
            let key = normalizedName(app.name)
            if let existing = result[key] {
                result[key] = preferred(app, over: existing)
            } else {
                result[key] = app
            }
        }.values.map { $0 }
    }

    nonisolated private static func preferred(
        _ candidate: LaunchableApplication,
        over existing: LaunchableApplication
    ) -> LaunchableApplication {
        let candidatePriority = locationPriority(for: candidate.url)
        let existingPriority = locationPriority(for: existing.url)

        if candidatePriority != existingPriority {
            return candidatePriority < existingPriority ? candidate : existing
        }
        return candidate.url.path.localizedStandardCompare(existing.url.path) == .orderedAscending
            ? candidate
            : existing
    }

    nonisolated private static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    nonisolated private static func locationPriority(for url: URL) -> Int {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/Applications/") { return 0 }
        if path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/") { return 1 }
        if path.hasPrefix("/System/Applications/") { return 2 }
        return 3
    }
}
