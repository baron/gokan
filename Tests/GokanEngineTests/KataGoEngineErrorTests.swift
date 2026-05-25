// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GokanEngine

@Test
func engineConfigurationValidatesFilePresenceWithoutTransport() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "gokan-engine-configuration-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let executable = directory.appending(path: "katago")
    let model = directory.appending(path: "model.bin.gz")
    let config = directory.appending(path: "analysis.cfg")
    let configuration = KataGoEngineConfiguration(executableURL: executable, modelURL: model, configURL: config)

    do {
        try configuration.validateFilePresence()
        Issue.record("Expected missing executable to throw.")
    } catch KataGoEngineError.executableMissing(let url) {
        #expect(url == executable)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    FileManager.default.createFile(atPath: executable.path, contents: Data())
    do {
        try configuration.validateFilePresence()
        Issue.record("Expected missing model to throw.")
    } catch KataGoEngineError.modelMissing(let url) {
        #expect(url == model)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    FileManager.default.createFile(atPath: model.path, contents: Data())
    do {
        try configuration.validateFilePresence()
        Issue.record("Expected missing config to throw.")
    } catch KataGoEngineError.configMissing(let url) {
        #expect(url == config)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    FileManager.default.createFile(atPath: config.path, contents: Data())
    try configuration.validateFilePresence()
}

@Test
func transportFactoryReportsMissingExecutableBeforeSpawning() throws {
    let configuration = KataGoEngineConfiguration(
        executableURL: URL(filePath: "/tmp/gokan-missing-katago"),
        modelURL: URL(filePath: "/tmp/gokan-missing-model.bin.gz"),
        configURL: URL(filePath: "/tmp/gokan-missing-analysis.cfg")
    )

    do {
        _ = try KataGoTransportFactory.make(for: configuration)
        Issue.record("Expected missing executable to throw.")
    } catch KataGoEngineError.executableMissing(let url) {
        #expect(url.path == "/tmp/gokan-missing-katago")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func transportFactoryReportsMissingModelAndConfig() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "gokan-engine-error-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let executable = directory.appending(path: "katago")
    let model = directory.appending(path: "model.bin.gz")
    let config = directory.appending(path: "analysis.cfg")
    FileManager.default.createFile(atPath: executable.path, contents: Data())

    do {
        _ = try KataGoTransportFactory.make(
            for: KataGoEngineConfiguration(executableURL: executable, modelURL: model, configURL: config)
        )
        Issue.record("Expected missing model to throw.")
    } catch KataGoEngineError.modelMissing(let url) {
        #expect(url == model)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    FileManager.default.createFile(atPath: model.path, contents: Data())
    do {
        _ = try KataGoTransportFactory.make(
            for: KataGoEngineConfiguration(executableURL: executable, modelURL: model, configURL: config)
        )
        Issue.record("Expected missing config to throw.")
    } catch KataGoEngineError.configMissing(let url) {
        #expect(url == config)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func kataGoEngineErrorsExposeLocalizedDescriptions() {
    let errors: [KataGoEngineError] = [
        .platformUnsupported,
        .executableMissing(URL(filePath: "/missing/katago")),
        .modelMissing(URL(filePath: "/missing/model.bin.gz")),
        .configMissing(URL(filePath: "/missing/analysis.cfg")),
        .startupFailed(reason: "permission denied"),
        .protocolViolation(reason: "malformed json"),
        .engineTerminated(exitCode: 7, stderrTail: "boom"),
    ]

    for error in errors {
        #expect(error.localizedDescription == error.description)
    }
}
