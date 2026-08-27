import AppKit
import Foundation
import SystemConfiguration

@MainActor
final class ClashVergeProxyManager: ObservableObject {
    static let shared = ClashVergeProxyManager()

    @Published private(set) var isSystemProxyEnabled = false
    @Published private(set) var isClashVergeRunning = false
    @Published private(set) var isInstalled = false
    @Published private(set) var isChanging = false
    @Published private(set) var isLoadingNodes = false
    @Published private(set) var isTestingDelay = false
    @Published private(set) var nodeGroupName = ""
    @Published private(set) var availableNodes: [String] = []
    @Published private(set) var selectedNode = ""
    @Published private(set) var selectedNodeDelay: Int?
    @Published var errorMessage: String?

    private let bundleIdentifier = "io.github.clash-verge-rev.clash-verge-rev"
    private var timer: Timer?
    private var lastNodeRefresh = Date.distantPast

    private init() {
        refresh()
        Task { await refreshNodes() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        isInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        isClashVergeRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        isSystemProxyEnabled = Self.localProxyIsEnabled()
        if isClashVergeRunning, Date().timeIntervalSince(lastNodeRefresh) > 15 {
            Task { await refreshNodes() }
        }
    }

    func setSystemProxyEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        errorMessage = nil
        refresh()

        guard isInstalled else {
            errorMessage = String(localized: "Clash Verge is not installed.")
            return
        }
        if isSystemProxyEnabled == enabled { return }

        isChanging = true
        defer { isChanging = false }

        if !isClashVergeRunning {
            guard enabled,
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            else {
                errorMessage = String(localized: "Clash Verge is not running.")
                return
            }
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                try? await Task.sleep(for: .seconds(1.5))
            } catch {
                errorMessage = String(localized: "Unable to open Clash Verge.")
                return
            }
        }

        let result = await XPCHelperClient.shared.setClashVergeSystemProxyEnabled(enabled)
        guard result.success else {
            switch result.errorCode {
            case "notRunning":
                errorMessage = String(localized: "Clash Verge is not running.")
            default:
                errorMessage = String(localized: "Unable to change the Clash Verge system proxy.")
            }
            return
        }

        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(250))
            refresh()
            if isSystemProxyEnabled == enabled { return }
        }
        errorMessage = String(localized: "The system proxy state did not change. Please check Clash Verge.")
    }

    func toggleSystemProxy() async {
        await setSystemProxyEnabled(!isSystemProxyEnabled)
    }

    func refreshNodes() async {
        guard !isLoadingNodes else { return }
        isLoadingNodes = true
        defer { isLoadingNodes = false }

        let (json, errorCode) = await XPCHelperClient.shared.fetchClashVergeProxyOverview()
        guard let json,
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let proxies = root["proxies"] as? [String: [String: Any]]
        else {
            if errorCode != nil { errorMessage = String(localized: "Unable to read Clash Verge nodes.") }
            return
        }

        let selectable = proxies.compactMap { name, details -> (String, [String], String)? in
            guard details["type"] as? String == "Selector",
                  name != "GLOBAL",
                  let all = details["all"] as? [String],
                  let now = details["now"] as? String,
                  !all.isEmpty
            else { return nil }
            return (name, all, now)
        }
        guard let group = selectable.max(by: { $0.1.count < $1.1.count }) else {
            errorMessage = String(localized: "No switchable Clash Verge node group was found.")
            return
        }

        nodeGroupName = group.0
        availableNodes = group.1.filter { name in
            guard let details = proxies[name], let type = details["type"] as? String else { return false }
            return !["Direct", "Reject", "RejectDrop", "Pass", "Compatible"].contains(type)
                && !name.contains("剩余流量")
                && !name.contains("套餐到期")
        }
        selectedNode = group.2
        lastNodeRefresh = Date()
        errorMessage = nil
    }

    func selectNode(_ node: String) async {
        guard !nodeGroupName.isEmpty, node != selectedNode else { return }
        let result = await XPCHelperClient.shared.selectClashVergeNode(node, group: nodeGroupName)
        if result.success {
            selectedNode = node
            selectedNodeDelay = nil
            errorMessage = nil
        } else {
            errorMessage = String(localized: "Unable to switch the Clash Verge node.")
        }
    }

    func testSelectedNodeDelay() async {
        guard !selectedNode.isEmpty, !isTestingDelay else { return }
        isTestingDelay = true
        defer { isTestingDelay = false }
        let (delay, _) = await XPCHelperClient.shared.testClashVergeNodeDelay(selectedNode)
        if let delay {
            selectedNodeDelay = delay
            errorMessage = nil
        } else {
            selectedNodeDelay = nil
            errorMessage = String(localized: "Unable to test the selected node latency.")
        }
    }

    private static func localProxyIsEnabled() -> Bool {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return false }
        let configurations: [(CFString, CFString)] = [
            (kSCPropNetProxiesHTTPEnable, kSCPropNetProxiesHTTPProxy),
            (kSCPropNetProxiesHTTPSEnable, kSCPropNetProxiesHTTPSProxy),
            (kSCPropNetProxiesSOCKSEnable, kSCPropNetProxiesSOCKSProxy)
        ]
        return configurations.contains { enabledKey, hostKey in
            let enabled = (settings[enabledKey as String] as? NSNumber)?.boolValue ?? false
            let host = (settings[hostKey as String] as? String)?.lowercased()
            return enabled && (host == "127.0.0.1" || host == "localhost" || host == "::1")
        }
    }
}
