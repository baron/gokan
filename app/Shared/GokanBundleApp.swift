// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import GokanUI

@main
struct GokanBundleApp: App {
    var body: some Scene {
        WindowGroup("Gokan") {
            GokanRootView(
                initialSGFText: GokanLaunchOptions.initialSGFText,
                forceMockEngine: GokanLaunchOptions.forceMockEngine,
                initialModelCatalogData: GokanLaunchOptions.initialModelCatalogData,
                initialEngineKind: GokanLaunchOptions.initialEngineKind,
                initialKataGoModelSettings: GokanLaunchOptions.initialKataGoModelSettings
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

    static var initialModelCatalogData: Data? {
        guard let resourceName = trimmedEnvironmentValue("GOKAN_UI_TEST_PRELOAD_MODEL_CATALOG_RESOURCE") else {
            return nil
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            print("Gokan launch option ignored: model catalog resource \(resourceName).json was not found.")
            return nil
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            print("Gokan launch option ignored: could not read model catalog resource \(resourceName).json: \(error.localizedDescription)")
            return nil
        }
    }

    static var initialEngineKind: AnalysisEngineKind? {
        trimmedEnvironmentValue("GOKAN_UI_TEST_ENGINE_KIND").flatMap(AnalysisEngineKind.init(rawValue:))
    }

    static var initialKataGoModelSettings: KataGoModelSettings? {
        let profileID = trimmedEnvironmentValue("GOKAN_UI_TEST_MODEL_PROFILE_ID") ?? ""
        let cacheRootPath = trimmedEnvironmentValue("GOKAN_UI_TEST_MODEL_CACHE_ROOT") ?? ""
        guard profileID.isEmpty == false || cacheRootPath.isEmpty == false else {
            return nil
        }

        return KataGoModelSettings(selectedProfileID: profileID, cacheRootPath: cacheRootPath)
    }

    private static func trimmedEnvironmentValue(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key] else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
