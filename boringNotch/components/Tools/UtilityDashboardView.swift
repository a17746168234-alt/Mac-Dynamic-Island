import SwiftUI

struct UtilityDashboardView: View {
    @ObservedObject private var clipboard = ClipboardHistoryManager.shared
    @ObservedObject private var proxy = ClashVergeProxyManager.shared

    var body: some View {
        HStack(spacing: 10) {
            clipboardCard
                .frame(width: 310)

            VStack(spacing: 8) {
                systemProxyCard
                nodeCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 4)
    }

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Clipboard History", systemImage: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("", isOn: $clipboard.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Button {
                    clipboard.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear Clipboard History")
                .disabled(clipboard.items.isEmpty)
            }

            if clipboard.items.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: clipboard.isEnabled ? "clipboard" : "clipboard.fill")
                        .font(.title3)
                    Text(clipboard.isEnabled ? "Copied items will appear here." : "Clipboard history is paused.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(clipboard.items) { item in
                            Button {
                                clipboard.copy(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Image(systemName: item.iconName)
                                        .foregroundStyle(.secondary)
                                    Text(item.previewText)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                        .font(.caption)
                                    Spacer(minLength: 0)
                                    Text(item.createdAt, style: .time)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(8)
                                .frame(width: 92, height: 88, alignment: .leading)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .help("Copy to Clipboard")
                            .contextMenu {
                                Button("Copy") { clipboard.copy(item) }
                                Button("Delete", role: .destructive) { clipboard.remove(item) }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var systemProxyCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("System Proxy")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { proxy.isSystemProxyEnabled },
                    set: { enabled in Task { await proxy.setSystemProxyEnabled(enabled) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(proxy.isChanging || !proxy.isInstalled)
            }

            Text(proxy.isSystemProxyEnabled ? "System proxy is on" : "System proxy is off")
                .font(.caption)
                .foregroundStyle(proxy.isSystemProxyEnabled ? .green : .secondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var nodeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Node & Latency", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if proxy.isLoadingNodes { ProgressView().controlSize(.mini) }
            }

            HStack(spacing: 6) {
                Picker("Node", selection: Binding(
                    get: { proxy.selectedNode },
                    set: { node in Task { await proxy.selectNode(node) } }
                )) {
                    if proxy.availableNodes.isEmpty {
                        Text("No nodes available").tag("")
                    } else {
                        ForEach(proxy.availableNodes, id: \.self) { node in
                            Text(node).tag(node)
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(proxy.availableNodes.isEmpty)

                Button {
                    Task { await proxy.testSelectedNodeDelay() }
                } label: {
                    if proxy.isTestingDelay {
                        ProgressView().controlSize(.mini)
                    } else if let delay = proxy.selectedNodeDelay {
                        Text("\(delay) ms")
                    } else {
                        Label("Test Latency", systemImage: "speedometer")
                    }
                }
                .disabled(proxy.selectedNode.isEmpty || proxy.isTestingDelay)
            }
            .controlSize(.small)

            if let errorMessage = proxy.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if !proxy.isInstalled {
                Text("Clash Verge is not installed.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }
}
