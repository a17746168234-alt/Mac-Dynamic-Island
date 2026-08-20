import SwiftUI

struct ApplicationLauncherView: View {
    @ObservedObject private var manager = ApplicationLauncherManager.shared
    @State private var searchText = ""

    private var filteredApplications: [LaunchableApplication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return manager.applications }
        return manager.applications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Applications", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Button {
                    Task { await manager.refreshApplications() }
                } label: {
                    if manager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .help("Refresh Applications")
                .disabled(manager.isLoading)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))

            if manager.isLoading && manager.applications.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading Applications…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApplications.isEmpty {
                ContentUnavailableView("No Applications Found", systemImage: "magnifyingglass")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 12)], spacing: 16) {
                        ForEach(filteredApplications) { application in
                            Button {
                                manager.open(application)
                            } label: {
                                VStack(spacing: 5) {
                                    Image(nsImage: manager.icon(for: application))
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 52, height: 52)
                                    Text(application.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(height: 30, alignment: .top)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .help(application.name)
                            .contextMenu {
                                Button(role: .destructive) {
                                    manager.quit(application)
                                } label: {
                                    Label("Quit app", systemImage: "power")
                                }
                                .disabled(!manager.isRunning(application))
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .task {
            await manager.loadIfNeeded()
            manager.startMonitoring()
            manager.refreshRanking()
        }
    }
}
