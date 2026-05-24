// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

internal struct KataGoAnalysisMetrics: Equatable, Sendable {
    let requestID: String
    let startedAt: ContinuousClock.Instant
    var transportStartedAt: ContinuousClock.Instant?
    var requestSentAt: ContinuousClock.Instant?
    var firstResponseAt: ContinuousClock.Instant?
    var finalResponseAt: ContinuousClock.Instant?
    var completedVisits: Int?
}

