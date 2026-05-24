// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GokanModels

@Test
func cacheDerivesModelAndConfigURLs() throws {
    let root = URL(filePath: "/tmp/gokan-cache")
    let cache = GokanModelCache(rootURL: root)
    let profile = try fixtureProfile()

    #expect(cache.modelURL(for: profile).path == "/tmp/gokan-cache/models/tiny.bin.gz")
    #expect(cache.configURL(for: profile)?.path == "/tmp/gokan-cache/configs/analysis.cfg")
}

@Test
func cacheSanitizesProgrammaticProfileFileNames() {
    let root = URL(filePath: "/tmp/gokan-cache")
    let cache = GokanModelCache(rootURL: root)
    let profile = GokanModelProfile(
        id: "unsafe",
        displayName: "Unsafe",
        modelFileName: "../model.bin.gz",
        defaultConfigFileName: "configs\\analysis.cfg",
        license: GokanModelLicense(name: "Fixture")
    )

    #expect(cache.modelURL(for: profile).path == "/tmp/gokan-cache/models/.._model.bin.gz")
    #expect(cache.configURL(for: profile)?.path == "/tmp/gokan-cache/configs/configs_analysis.cfg")
}

@Test
func cacheReadinessReportsMissingModel() throws {
    let temp = try TemporaryDirectory()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try fixtureProfile()

    #expect(cache.readiness(for: profile) == .missingModel(modelURL: cache.modelURL(for: profile)))
}

@Test
func cacheReadinessReportsMissingConfig() throws {
    let temp = try TemporaryDirectory()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try fixtureProfile()
    try writeData("hello", to: cache.modelURL(for: profile))

    #expect(cache.readiness(for: profile) == .missingConfig(configURL: try #require(cache.configURL(for: profile))))
}

@Test
func cacheReadinessReportsReadyWhenFilesExist() throws {
    let temp = try TemporaryDirectory()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try fixtureProfile()
    try writeData("hello", to: cache.modelURL(for: profile))
    try writeData("config", to: try #require(cache.configURL(for: profile)))

    #expect(
        cache.readiness(for: profile)
            == .ready(modelURL: cache.modelURL(for: profile), configURL: cache.configURL(for: profile), checksum: profile.checksum)
    )
}

@Test
func cacheReadinessDoesNotRequireAbsentDefaultConfig() throws {
    let temp = try TemporaryDirectory()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = GokanModelProfile(
        id: "model-only",
        displayName: "Model Only",
        modelFileName: "model.bin.gz",
        license: GokanModelLicense(name: "Fixture")
    )
    try writeData("hello", to: cache.modelURL(for: profile))

    #expect(
        cache.readiness(for: profile)
            == .ready(modelURL: cache.modelURL(for: profile), configURL: nil, checksum: nil)
    )
}

@Test
func checksumVerificationReportsUnavailableWhenProfileHasNoChecksum() async throws {
    let temp = try TemporaryDirectory()
    let profile = GokanModelProfile(
        id: "unchecked",
        displayName: "Unchecked",
        modelFileName: "unchecked.bin.gz",
        license: GokanModelLicense(name: "Fixture")
    )
    let cache = GokanModelCache(rootURL: temp.url)
    try writeData("hello", to: cache.modelURL(for: profile))

    let result = await cache.verifyChecksum(for: profile)

    #expect(result == .checksumUnavailable(modelURL: cache.modelURL(for: profile)))
}

@Test
func checksumVerificationReportsVerifiedAndMismatch() async throws {
    let temp = try TemporaryDirectory()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try fixtureProfile()
    try writeData("hello", to: cache.modelURL(for: profile))

    let verified = await cache.verifyChecksum(for: profile)
    let mismatchedProfile = GokanModelProfile(
        id: "mismatch",
        displayName: "Mismatch",
        modelFileName: profile.modelFileName,
        checksum: try GokanModelChecksum(sha256: "0000000000000000000000000000000000000000000000000000000000000000"),
        license: GokanModelLicense(name: "Fixture")
    )
    let mismatch = await cache.verifyChecksum(for: mismatchedProfile)

    #expect(
        verified
            == .verified(
                modelURL: cache.modelURL(for: profile),
                expectedSHA256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
                actualSHA256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            )
    )
    #expect(
        mismatch
            == .mismatch(
                modelURL: cache.modelURL(for: mismatchedProfile),
                expectedSHA256: "0000000000000000000000000000000000000000000000000000000000000000",
                actualSHA256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            )
    )
}

@Test
func checksumVerificationReportsMissingFile() async throws {
    let temp = try TemporaryDirectory()
    let cache = GokanModelCache(rootURL: temp.url)
    let profile = try fixtureProfile()

    let result = await cache.verifyChecksum(for: profile)

    #expect(result == .missing(modelURL: cache.modelURL(for: profile)))
}

private func fixtureProfile() throws -> GokanModelProfile {
    GokanModelProfile(
        id: "tiny-dev",
        displayName: "Tiny Dev Model",
        modelFileName: "tiny.bin.gz",
        defaultConfigFileName: "analysis.cfg",
        checksum: try GokanModelChecksum(sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
        license: GokanModelLicense(name: "Fixture")
    )
}

private func writeData(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "gokan-model-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
