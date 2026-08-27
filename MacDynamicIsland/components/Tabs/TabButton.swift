//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let preservesTrailingIconPosition: Bool
    let selectionAnimation: Namespace.ID
    let onClick: () -> Void

    private var iconAlignment: Alignment {
        preservesTrailingIconPosition ? .trailing : .center
    }

    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .imageScale(.medium)
                .scaleEffect(1)
                .foregroundColor(selected ? .blue : .gray)
                // Keep the selection circle attached to the symbol itself.
                // The Settings symbol intentionally keeps its historical
                // trailing position; its circle moves with it instead of
                // pulling the symbol left into the old circle position.
                .background {
                    if selected {
                        Circle()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .frame(
                                width: BoringHeaderLayout.tabButtonSize,
                                height: BoringHeaderLayout.tabButtonSize
                            )
                            .matchedGeometryEffect(id: "capsule", in: selectionAnimation)
                    }
                }
                .frame(
                    width: BoringHeaderLayout.tabButtonSize,
                    height: BoringHeaderLayout.tabButtonSize,
                    alignment: iconAlignment
                )
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct TabButtonPreview: View {
    @Namespace private var selectionAnimation

    var body: some View {
        TabButton(
            label: "Home",
            icon: "tray.fill",
            selected: true,
            preservesTrailingIconPosition: false,
            selectionAnimation: selectionAnimation
        ) {
            print("Tapped")
        }
    }
}

#Preview {
    TabButtonPreview()
}
