//
//  TabSelectionView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
}

private let primaryTabs = [
    TabModel(label: String(localized: "Home"), icon: "house.fill", view: .home),
    TabModel(label: String(localized: "Shelf"), icon: "tray.fill", view: .shelf),
    TabModel(label: String(localized: "Tools"), icon: "square.grid.2x2.fill", view: .tools)
]

private var utilityTabs: [TabModel] {
    var result: [TabModel] = []
    if Defaults[.settingsIconInNotch] {
        result.append(TabModel(label: String(localized: "Settings"), icon: "gear", view: .settings))
    }
    result.append(TabModel(label: String(localized: "Application Launcher"), icon: "square.grid.3x3.fill", view: .launcher))
    return result
}

private struct HeaderTabBar: View {
    let tabs: [TabModel]
    let deselectsToHome: Bool
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 3) {
            ForEach(tabs) { tab in
                let selected = coordinator.currentView == tab.view
                TabButton(label: tab.label, icon: tab.icon, selected: selected) {
                    withAnimation(.smooth) {
                        coordinator.currentView = selected && deselectsToHome ? .home : tab.view
                    }
                }
                .background {
                    if selected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: selectionAnimation)
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}

struct TabSelectionView: View {
    var body: some View {
        HeaderTabBar(tabs: primaryTabs, deselectsToHome: false)
    }
}

struct UtilityTabSelectionView: View {
    var body: some View {
        HeaderTabBar(tabs: utilityTabs, deselectsToHome: true)
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
