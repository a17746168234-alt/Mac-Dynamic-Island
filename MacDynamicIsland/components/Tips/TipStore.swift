//
//  TipStore.swift
//  boringNotch
//
//  Created by Richard Kunkli on 15/09/2024.
//

import SwiftUI
import TipKit

struct HUDsTip: Tip {
    var title: Text {
        Text("Enhance your experience with HUDs")
    }
    
    
    var message: Text? {
        Text("Unlock advanced features and improve your experience. Upgrade now for more customizations!")
    }
    
    
    var image: Image? {
        AppIcon(for: "theboringteam.boringNotch")
    }
    
    var actions: [Action] {
        Action {
            Text("More")
        }
    }
}

struct CBTip: Tip {
    var title: Text {
        Text("Use Clipboard History for quicker access")
    }
    
    
    var message: Text? {
        Text("Keep recent text, images, and files locally, then reopen them with Shift-Command-C.")
    }
    
    
    var image: Image? {
        AppIcon(for: "theboringteam.boringNotch")
    }
    
    var actions: [Action] {
        Action {
            Text("More")
        }
    }
}

struct TipsView: View {
    var hudTip = HUDsTip()
    var cbTip = CBTip()
    var body: some View {
        VStack {
            TipView(hudTip)
            TipView(cbTip)
        }
        .task {
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        }
    }
}

#Preview {
    TipsView()
}
