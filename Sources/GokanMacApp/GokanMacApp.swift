// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import GokanUI

@main
struct GokanMacApp: App {
    var body: some Scene {
        WindowGroup("Gokan") {
            GokanRootView()
        }
        .commands {
            SidebarCommands()
        }

        Settings {
            Form {
                Text("Gokan 碁冠")
                    .font(.title2)
                Text("Open Go analysis for Apple Silicon.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 360)
        }
    }
}
