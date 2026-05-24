// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import GokanUI

@main
struct GokanBundleApp: App {
    var body: some Scene {
        WindowGroup("Gokan") {
            GokanRootView(
                initialSGFText: GokanLaunchOptions.initialSGFText,
                forceMockEngine: GokanLaunchOptions.forceMockEngine
            )
        }

        #if os(macOS)
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
        #endif
    }
}

private enum GokanLaunchOptions {
    static var initialSGFText: String? {
        ProcessInfo.processInfo.environment["GOKAN_UI_TEST_SGF"]
    }

    static var forceMockEngine: Bool {
        ProcessInfo.processInfo.environment["GOKAN_UI_TEST_FORCE_MOCK_ENGINE"] == "1"
    }
}
