// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GokanCore

public enum AnalysisRunOutcome: Equatable, Sendable {
    case running
    case succeeded
    case failed(message: String)
    case cancelled
}

public struct AnalysisRunDiagnostics: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let engineKind: AnalysisEngineKind
    public let boardSize: BoardSize
    public let moveIndex: Int
    public let moveCount: Int
    public let requestedVisits: Int
    public let startedAt: Date
    public var finishedAt: Date?
    public var durationSeconds: Double?
    public var outcome: AnalysisRunOutcome
    public var snapshotsReceived: Int
    public var completedVisits: Int?
    public var candidateCount: Int?
    public var scoreLead: Double?

    public init(
        id: UUID = UUID(),
        engineKind: AnalysisEngineKind,
        boardSize: BoardSize,
        moveIndex: Int,
        moveCount: Int,
        requestedVisits: Int,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        durationSeconds: Double? = nil,
        outcome: AnalysisRunOutcome = .running,
        snapshotsReceived: Int = 0,
        completedVisits: Int? = nil,
        candidateCount: Int? = nil,
        scoreLead: Double? = nil
    ) {
        self.id = id
        self.engineKind = engineKind
        self.boardSize = boardSize
        self.moveIndex = moveIndex
        self.moveCount = moveCount
        self.requestedVisits = requestedVisits
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationSeconds = durationSeconds
        self.outcome = outcome
        self.snapshotsReceived = snapshotsReceived
        self.completedVisits = completedVisits
        self.candidateCount = candidateCount
        self.scoreLead = scoreLead
    }
}
