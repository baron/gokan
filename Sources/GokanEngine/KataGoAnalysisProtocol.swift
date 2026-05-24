// SPDX-License-Identifier: GPL-3.0-or-later
//
// Re-implements the subset of KataGo's public analysis JSON line protocol
// Gokan needs. Reference: https://github.com/lightvector/KataGo/blob/master/docs/Analysis_Engine.md

import Foundation

internal struct KataGoAnalysisRequestPayload: Encodable {
    let id: String
    let rules: String
    let komi: Double
    let boardXSize: Int
    let boardYSize: Int
    let initialPlayer: String
    let initialStones: [[String]]
    let moves: [[String]]
    let maxVisits: Int
    let includePolicy: Bool
    let includeOwnership: Bool
}

internal struct KataGoAnalysisTerminatePayload: Encodable {
    let id: String
    let action = "terminate"
}

internal struct KataGoAnalysisResponse: Decodable, Sendable {
    let id: String
    let isDuringSearch: Bool?
    let rootInfo: RootInfo?
    let moveInfos: [MoveInfo]

    struct RootInfo: Decodable, Sendable {
        let scoreLead: Double?
        let visits: Int?
    }

    struct MoveInfo: Decodable, Sendable {
        let move: String
        let winrate: Double?
        let prior: Double?
        let visits: Int?
    }
}
