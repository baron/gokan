// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import GokanCore
@testable import GokanEngine

@Test
func kataGoAnalysisEngineYieldsSnapshotsFromInjectedTransport() async throws {
    let transport = ScriptedKataGoTransport()
    let engine = KataGoAnalysisEngine(
        configuration: KataGoEngineConfiguration(
            executableURL: URL(filePath: "/katago"),
            modelURL: URL(filePath: "/model.bin.gz"),
            configURL: URL(filePath: "/analysis.cfg")
        ),
        makeTransport: { _ in transport }
    )

    let stream = try await engine.analyze(
        AnalysisRequest(board: GoBoard(), moves: [], visits: 50)
    )
    var snapshots: [AnalysisSnapshot] = []

    for try await snapshot in stream {
        snapshots.append(snapshot)
    }

    #expect(transport.didStart)
    #expect(transport.sentLineCount == 1)
    #expect(transport.didStop)
    #expect(snapshots.count == 2)
    #expect(snapshots[0].completedVisits == 10)
    #expect(snapshots[1].completedVisits == 50)
    #expect(snapshots[1].candidateMoves[0].point == BoardPoint(x: 15, y: 15))
}

@Test
func kataGoAnalysisEngineTerminatesTransportOnCancellation() async throws {
    let transport = HangingKataGoTransport()
    let engine = KataGoAnalysisEngine(
        configuration: KataGoEngineConfiguration(
            executableURL: URL(filePath: "/katago"),
            modelURL: URL(filePath: "/model.bin.gz"),
            configURL: URL(filePath: "/analysis.cfg")
        ),
        makeTransport: { _ in transport }
    )

    let stream = try await engine.analyze(
        AnalysisRequest(board: GoBoard(), moves: [], visits: 50)
    )
    let task = Task {
        for try await _ in stream {}
    }

    try await Task.sleep(nanoseconds: 20_000_000)
    task.cancel()
    _ = await task.result
    try await Task.sleep(nanoseconds: 20_000_000)

    #expect(transport.analysisLineCount == 1)
    #expect(transport.terminateLineCount == 1)
    #expect(transport.didStop)
}

private final class ScriptedKataGoTransport: KataGoTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private(set) var didStart = false
    private(set) var didStop = false
    private(set) var sentLineCount = 0

    func start() async throws {
        withLock {
            didStart = true
        }
    }

    func send(_ line: Data) async throws {
        let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        let id = try #require(object?["id"] as? String)

        withLock {
            sentLineCount += 1
            continuation?.yield(
                Data(
                    """
                    {"id":"\(id)","isDuringSearch":true,"rootInfo":{"scoreLead":0.25,"visits":10},"moveInfos":[{"move":"Q4","winrate":0.52,"prior":0.20,"visits":5}]}
                    """.utf8
                )
            )
            continuation?.yield(
                Data(
                    """
                    {"id":"\(id)","isDuringSearch":false,"rootInfo":{"scoreLead":0.75,"visits":50},"moveInfos":[{"move":"Q4","winrate":0.58,"prior":0.30,"visits":30}]}
                    """.utf8
                )
            )
            continuation?.finish()
        }
    }

    func responses() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            withLock {
                self.continuation = continuation
            }
        }
    }

    func stop() async {
        withLock {
            didStop = true
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class HangingKataGoTransport: KataGoTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private(set) var didStop = false
    private(set) var analysisLineCount = 0
    private(set) var terminateLineCount = 0

    func start() async throws {}

    func send(_ line: Data) async throws {
        let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        withLock {
            if object?["action"] as? String == "terminate" {
                terminateLineCount += 1
            } else {
                analysisLineCount += 1
            }
        }
    }

    func responses() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            withLock {
                self.continuation = continuation
            }
        }
    }

    func stop() async {
        withLock {
            didStop = true
            continuation?.finish()
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
