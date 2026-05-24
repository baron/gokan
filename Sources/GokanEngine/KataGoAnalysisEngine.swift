// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct KataGoAnalysisEngine: GoAnalysisEngine {
    public let configuration: KataGoEngineConfiguration

    private let makeTransport: @Sendable (KataGoEngineConfiguration) throws -> any KataGoTransport
    private let codec: KataGoAnalysisCodec
    private let metricsSink: (@Sendable (KataGoAnalysisMetrics) -> Void)?
    private let clock = ContinuousClock()
    private let terminationGraceNanoseconds: UInt64 = 5_000_000

    public init(configuration: KataGoEngineConfiguration) {
        self.init(configuration: configuration, makeTransport: KataGoTransportFactory.make)
    }

    internal init(
        configuration: KataGoEngineConfiguration,
        makeTransport: @escaping @Sendable (KataGoEngineConfiguration) throws -> any KataGoTransport,
        codec: KataGoAnalysisCodec = KataGoAnalysisCodec(),
        metricsSink: (@Sendable (KataGoAnalysisMetrics) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.makeTransport = makeTransport
        self.codec = codec
        self.metricsSink = metricsSink
    }

    public func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let requestID = UUID().uuidString
            let transportBox = KataGoTransportBox()
            let clock = clock
            let metricsSink = metricsSink
            let task = Task {
                var metrics = KataGoAnalysisMetrics(requestID: requestID, startedAt: clock.now)
                do {
                    let transport = try makeTransport(configuration)
                    await transportBox.set(transport)
                    let responses = transport.responses()
                    try await transport.start()
                    metrics.transportStartedAt = clock.now
                    try await transport.send(try codec.encode(request, id: requestID))
                    metrics.requestSentAt = clock.now

                    for try await line in responses {
                        try Task.checkCancellation()
                        let response = try codec.decode(line)
                        guard response.id == requestID else {
                            continue
                        }

                        if metrics.firstResponseAt == nil {
                            metrics.firstResponseAt = clock.now
                        }

                        let snapshot = try codec.snapshot(from: response, boardSize: request.board.size)
                        metrics.completedVisits = snapshot.completedVisits
                        continuation.yield(snapshot)

                        if response.isDuringSearch == false {
                            metrics.finalResponseAt = clock.now
                            metricsSink?(metrics)
                            await transport.stop()
                            continuation.finish()
                            return
                        }
                    }

                    await transport.stop()
                    continuation.finish()
                } catch is CancellationError {
                    if let transport = await transportBox.transport {
                        await transport.stop()
                    }
                    continuation.finish()
                } catch {
                    if let transport = await transportBox.transport {
                        await transport.stop()
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                Task {
                    if let transport = await transportBox.transport {
                        let terminateTask = Task {
                            try? await transport.send(codec.encodeTerminate(id: requestID))
                        }
                        try? await Task.sleep(nanoseconds: terminationGraceNanoseconds)
                        terminateTask.cancel()
                    }
                    task.cancel()
                }
            }
        }
    }
}

private actor KataGoTransportBox {
    private(set) var transport: (any KataGoTransport)?

    func set(_ transport: any KataGoTransport) {
        self.transport = transport
    }
}
