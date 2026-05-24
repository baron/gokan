// SPDX-License-Identifier: GPL-3.0-or-later

#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import GokanEngine

@Test
func processTransportEchoesJsonLinesThroughCat() async throws {
    try #require(FileManager.default.fileExists(atPath: "/bin/cat"))
    let transport = ProcessKataGoTransport(
        configuration: makeProcessTransportConfiguration(executablePath: "/bin/cat"),
        launchArguments: []
    )
    let responses = transport.responses()

    do {
        try await transport.start()
        try await transport.send(Data(#"{"id":"transport-echo","isDuringSearch":false,"moveInfos":[]}"#.utf8) + Data([0x0A]))

        let response = try await firstResponse(from: responses)
        #expect(String(decoding: response, as: UTF8.self) == #"{"id":"transport-echo","isDuringSearch":false,"moveInfos":[]}"#)
        await transport.stop()
    } catch {
        await transport.stop()
        throw error
    }
}

@Test
func processTransportSendBeforeStartReportsUnavailableStdin() async throws {
    let transport = ProcessKataGoTransport(
        configuration: makeProcessTransportConfiguration(executablePath: "/bin/cat"),
        launchArguments: []
    )

    do {
        try await transport.send(Data("{}\n".utf8))
        Issue.record("Expected send before start to throw.")
    } catch KataGoEngineError.startupFailed(let reason) {
        #expect(reason.localizedCaseInsensitiveContains("stdin"))
        #expect(reason.localizedCaseInsensitiveContains("unavailable"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func processTransportReplacingResponsesFinishesPreviousStream() async throws {
    let transport = ProcessKataGoTransport(
        configuration: makeProcessTransportConfiguration(executablePath: "/bin/cat"),
        launchArguments: []
    )
    let firstResponses = transport.responses()
    _ = transport.responses()

    let error = try await streamFailure(from: firstResponses)

    guard case KataGoEngineError.startupFailed(let reason) = error else {
        Issue.record("Unexpected error: \(error)")
        return
    }
    #expect(reason == "Response stream was replaced.")
}

@Test
func processTransportReportsNonZeroExitWithStderrTail() async throws {
    try #require(FileManager.default.fileExists(atPath: "/bin/sh"))
    let marker = "gokan-transport-stderr-marker"
    let transport = ProcessKataGoTransport(
        configuration: makeProcessTransportConfiguration(executablePath: "/bin/sh"),
        launchArguments: ["-c", "echo \(marker) >&2; exit 7"]
    )
    let responses = transport.responses()

    do {
        try await transport.start()
        let error = try await streamFailure(from: responses)

        guard case KataGoEngineError.engineTerminated(let exitCode, let stderrTail) = error else {
            Issue.record("Unexpected error: \(error)")
            await transport.stop()
            return
        }

        #expect(exitCode == 7)
        #expect(stderrTail.contains(marker))
        await transport.stop()
    } catch {
        await transport.stop()
        throw error
    }
}

@Test
func processTransportWaitsForReadinessBannerBeforeSending() async throws {
    try #require(FileManager.default.fileExists(atPath: "/bin/sh"))
    let transport = ProcessKataGoTransport(
        configuration: makeProcessTransportConfiguration(executablePath: "/bin/sh"),
        launchArguments: [
            "-c",
            "echo 'Started, ready to begin handling requests' >&2; exec /bin/cat",
        ],
        readinessPolicy: .kataGoDefault
    )
    let responses = transport.responses()

    do {
        try await transport.start()
        try await transport.send(Data(#"{"id":"ready-echo","isDuringSearch":false,"moveInfos":[]}"#.utf8) + Data([0x0A]))

        let response = try await firstResponse(from: responses)
        #expect(String(decoding: response, as: UTF8.self) == #"{"id":"ready-echo","isDuringSearch":false,"moveInfos":[]}"#)
        await transport.stop()
    } catch {
        await transport.stop()
        throw error
    }
}

@Test
func processTransportAcceptsReadinessBannerWithoutTrailingNewline() async throws {
    try #require(FileManager.default.fileExists(atPath: "/bin/sh"))
    let transport = ProcessKataGoTransport(
        configuration: makeProcessTransportConfiguration(executablePath: "/bin/sh"),
        launchArguments: [
            "-c",
            "printf 'Started, ready to begin handling requests' >&2; exec /bin/cat",
        ],
        readinessPolicy: .kataGoDefault
    )
    let responses = transport.responses()

    do {
        try await transport.start()
        try await transport.send(Data(#"{"id":"ready-no-newline","isDuringSearch":false,"moveInfos":[]}"#.utf8) + Data([0x0A]))

        let response = try await firstResponse(from: responses)
        #expect(String(decoding: response, as: UTF8.self) == #"{"id":"ready-no-newline","isDuringSearch":false,"moveInfos":[]}"#)
        await transport.stop()
    } catch {
        await transport.stop()
        throw error
    }
}

@Test
func processTransportStartTimesOutWithoutReadinessBanner() async throws {
    try #require(FileManager.default.fileExists(atPath: "/bin/sh"))
    let banner = "Started, ready to begin handling requests"
    let transport = ProcessKataGoTransport(
        configuration: makeProcessTransportConfiguration(executablePath: "/bin/sh"),
        launchArguments: ["-c", "sleep 2"],
        readinessPolicy: .stderrBanner(banner, timeoutSeconds: 0.05)
    )
    let responses = transport.responses()

    do {
        try await transport.start()
        Issue.record("Expected start to time out before readiness.")
    } catch KataGoEngineError.startupFailed(let reason) {
        #expect(reason.contains("Timed out"))
        #expect(reason.contains(banner))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let error = try await streamFailure(from: responses)
    guard case KataGoEngineError.startupFailed(let reason) = error else {
        Issue.record("Unexpected stream error: \(error)")
        await transport.stop()
        return
    }
    #expect(reason.contains("Timed out"))
    await transport.stop()
}

@Test
func processTransportStartCancellationUnblocksReadinessWait() async throws {
    try #require(FileManager.default.fileExists(atPath: "/bin/sh"))
    let pidURL = FileManager.default.temporaryDirectory
        .appending(path: "gokan-start-cancel-\(UUID().uuidString).pid")
    defer {
        try? FileManager.default.removeItem(at: pidURL)
    }
    let transport = ProcessKataGoTransport(
        configuration: makeProcessTransportConfiguration(executablePath: "/bin/sh"),
        launchArguments: ["-c", "echo $$ > \(pidURL.path); sleep 30"],
        readinessPolicy: .kataGoDefault
    )
    let responses = transport.responses()

    let startTask = Task {
        try await transport.start()
    }

    try await waitForFile(at: pidURL)
    startTask.cancel()

    do {
        try await withTimeout(seconds: 1) {
            try await startTask.value
        }
        Issue.record("Expected cancelled start to throw.")
    } catch is CancellationError {
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let streamError = try await streamFailure(from: responses)
    #expect(streamError is CancellationError)
    let pidText = try String(contentsOf: pidURL, encoding: .utf8)
    let pid = try #require(Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
    try await waitForProcessExit(pid)
    await transport.stop()
}

@Test
func processTransportStartFailsWhenProcessExitsBeforeReadiness() async throws {
    try #require(FileManager.default.fileExists(atPath: "/bin/sh"))
    let marker = "gokan-readiness-exit-marker"
    let transport = ProcessKataGoTransport(
        configuration: makeProcessTransportConfiguration(executablePath: "/bin/sh"),
        launchArguments: ["-c", "echo \(marker) >&2; exit 7"],
        readinessPolicy: .kataGoDefault
    )
    let responses = transport.responses()

    do {
        try await transport.start()
        Issue.record("Expected start to fail before readiness.")
    } catch KataGoEngineError.engineTerminated(let exitCode, let stderrTail) {
        #expect(exitCode == 7)
        #expect(stderrTail.contains(marker))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let error = try await streamFailure(from: responses)
    guard case KataGoEngineError.engineTerminated(let exitCode, let stderrTail) = error else {
        Issue.record("Unexpected stream error: \(error)")
        await transport.stop()
        return
    }
    #expect(exitCode == 7)
    #expect(stderrTail.contains(marker))
    await transport.stop()
}

@Test
func processTransportDefaultLaunchArgumentsUseKataGoAnalysisMode() {
    let configuration = KataGoEngineConfiguration(
        executableURL: URL(filePath: "/katago"),
        modelURL: URL(filePath: "/models/model.bin.gz"),
        configURL: URL(filePath: "/configs/analysis.cfg")
    )

    #expect(ProcessKataGoTransport.defaultLaunchArguments(for: configuration) == [
        "analysis",
        "-model",
        "/models/model.bin.gz",
        "-config",
        "/configs/analysis.cfg",
    ])
}

private func makeProcessTransportConfiguration(executablePath: String) -> KataGoEngineConfiguration {
    KataGoEngineConfiguration(
        executableURL: URL(filePath: executablePath),
        modelURL: URL(filePath: "/tmp/gokan-test-model.bin.gz"),
        configURL: URL(filePath: "/tmp/gokan-test-analysis.cfg")
    )
}

private func firstResponse(from stream: AsyncThrowingStream<Data, Error>) async throws -> Data {
    try await withTimeout(seconds: 5) {
        var iterator = stream.makeAsyncIterator()
        guard let response = try await iterator.next() else {
            throw ProcessTransportTestError.streamFinishedWithoutError
        }
        return response
    }
}

private func streamFailure(from stream: AsyncThrowingStream<Data, Error>) async throws -> Error {
    do {
        try await withTimeout(seconds: 5) {
            var iterator = stream.makeAsyncIterator()
            while try await iterator.next() != nil {}
        }
        throw ProcessTransportTestError.streamFinishedWithoutError
    } catch ProcessTransportTestError.timedOut {
        throw ProcessTransportTestError.timedOut
    } catch {
        return error
    }
}

private func waitForFile(at url: URL) async throws {
    try await withTimeout(seconds: 1) {
        while FileManager.default.fileExists(atPath: url.path) == false {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private func waitForProcessExit(_ pid: Int32) async throws {
    try await withTimeout(seconds: 1) {
        while processExists(pid) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private func processExists(_ pid: Int32) -> Bool {
    Darwin.kill(pid_t(pid), 0) == 0 || errno == EPERM
}

private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let state = TimeoutState<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            state.setOperationTask(
                Task {
                    do {
                        state.resume(.success(try await operation()), continuation: continuation)
                    } catch {
                        state.resume(.failure(error), continuation: continuation)
                    }
                }
            )
            state.setTimeoutTask(
                Task {
                    do {
                        let nanoseconds = UInt64(seconds * 1_000_000_000)
                        try await Task.sleep(nanoseconds: nanoseconds)
                        state.cancelOperation()
                        state.resume(.failure(ProcessTransportTestError.timedOut), continuation: continuation)
                    } catch {}
                }
            )
        }
    } onCancel: {
        state.cancelAll()
    }
}

private final class TimeoutState<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func setOperationTask(_ task: Task<Void, Never>) {
        withLock {
            operationTask = task
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        withLock {
            timeoutTask = task
        }
    }

    func cancelOperation() {
        withLock {
            operationTask?.cancel()
        }
    }

    func cancelAll() {
        withLock {
            operationTask?.cancel()
            timeoutTask?.cancel()
        }
    }

    func resume(_ result: Result<T, Error>, continuation: CheckedContinuation<T, Error>) {
        let shouldResume = withLock {
            guard didResume == false else {
                return false
            }
            didResume = true
            return true
        }

        guard shouldResume else {
            return
        }

        cancelAll()
        continuation.resume(with: result)
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer {
            lock.unlock()
        }
        return body()
    }
}

private enum ProcessTransportTestError: Error {
    case timedOut
    case streamFinishedWithoutError
}
#endif
