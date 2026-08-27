import SwiftUI

struct UtilityDashboardView: View {
    @ObservedObject private var clipboard = ClipboardHistoryManager.shared

    var body: some View {
        clipboardCard
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
                                .frame(width: 132, height: 104, alignment: .leading)
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

}
