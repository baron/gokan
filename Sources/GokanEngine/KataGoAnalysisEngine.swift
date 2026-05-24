// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct KataGoAnalysisEngine: GoAnalysisEngine {
    public let configuration: KataGoEngineConfiguration

    private let makeTransport: @Sendable (KataGoEngineConfiguration) throws -> any KataGoTransport
    private let codec: KataGoAnalysisCodec

    public init(configuration: KataGoEngineConfiguration) {
        self.init(configuration: configuration, makeTransport: KataGoTransportFactory.make)
    }

    internal init(
        configuration: KataGoEngineConfiguration,
        makeTransport: @escaping @Sendable (KataGoEngineConfiguration) throws -> any KataGoTransport,
        codec: KataGoAnalysisCodec = KataGoAnalysisCodec()
    ) {
        self.configuration = configuration
        self.makeTransport = makeTransport
        self.codec = codec
    }

    public func analyze(_ request: AnalysisRequest) async throws -> AsyncThrowingStream<AnalysisSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let requestID = UUID().uuidString
            let transportBox = KataGoTransportBox()
            let task = Task {
                do {
                    let transport = try makeTransport(configuration)
                    await transportBox.set(transport)
                    let responses = transport.responses()
                    try await transport.start()
                    try await transport.send(try codec.encode(request, id: requestID))

                    for try await line in responses {
                        try Task.checkCancellation()
                        let response = try codec.decode(line)
                        guard response.id == requestID else {
                            continue
                        }

                        continuation.yield(try codec.snapshot(from: response, boardSize: request.board.size))

                        if response.isDuringSearch == false {
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
                task.cancel()
                Task {
                    if let transport = await transportBox.transport {
                        try? await transport.send(codec.encodeTerminate(id: requestID))
                        await transport.stop()
                    }
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
