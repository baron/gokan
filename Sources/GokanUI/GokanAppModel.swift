// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GokanCore
import GokanEngine
import GokanModels
import Observation

public enum AnalysisEngineKind: String, CaseIterable, Identifiable, Sendable {
    case mock
    case kataGo

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .mock:
            "Mock"
        case .kataGo:
            "KataGo"
        }
    }
}

public struct KataGoPathSettings: Equatable, Sendable {
    public var executablePath: String
    public var modelPath: String
    public var configPath: String

    public init(executablePath: String = "", modelPath: String = "", configPath: String = "") {
        self.executablePath = executablePath
        self.modelPath = modelPath
        self.configPath = configPath
    }
}

public struct AnalysisEngineSelection: Equatable, Sendable {
    public var kind: AnalysisEngineKind
    public var kataGoSettings: KataGoPathSettings
    public var kataGoModelSettings: KataGoModelSettings
    public var resolvedKataGoConfiguration: KataGoEngineConfiguration?

    public init(
        kind: AnalysisEngineKind,
        kataGoSettings: KataGoPathSettings,
        kataGoModelSettings: KataGoModelSettings = KataGoModelSettings(),
        resolvedKataGoConfiguration: KataGoEngineConfiguration? = nil
    ) {
        self.kind = kind
        self.kataGoSettings = kataGoSettings
        self.kataGoModelSettings = kataGoModelSettings
        self.resolvedKataGoConfiguration = resolvedKataGoConfiguration
    }
}

public struct KataGoModelSettings: Equatable, Sendable {
    public var selectedProfileID: String
    public var cacheRootPath: String

    public init(selectedProfileID: String = "", cacheRootPath: String = "") {
        self.selectedProfileID = selectedProfileID
        self.cacheRootPath = cacheRootPath
    }
}

public enum KataGoModelStatus: Equatable, Sendable {
    case notSelected
    case manualPath(path: String)
    case profileReady(profileID: String, displayName: String, modelPath: String, configPath: String?)
    case profileUnavailable(profileID: String)
    case missingCacheRoot(profileID: String)
    case missingCachedModel(profileID: String, path: String)
    case missingCachedConfig(profileID: String, path: String)
    case checksumUnavailable(profileID: String)
    case checksumVerified(profileID: String, sha256: String)
    case checksumMismatch(profileID: String, expected: String, actual: String)
    case verificationFailed(profileID: String, message: String)

    public var message: String {
        switch self {
        case .notSelected:
            "No model profile selected."
        case .manualPath(let path):
            "Using manual model path: \(path)"
        case .profileReady(_, let displayName, let modelPath, _):
            "\(displayName) is available at \(modelPath)."
        case .profileUnavailable(let profileID):
            "Model profile \(profileID) is not in the catalog."
        case .missingCacheRoot:
            "Model cache root is not configured."
        case .missingCachedModel(_, let path):
            "Cached model file is missing at \(path)."
        case .missingCachedConfig(_, let path):
            "Cached config file is missing at \(path)."
        case .checksumUnavailable:
            "No checksum is available for the selected model profile."
        case .checksumVerified(_, let sha256):
            "Model checksum verified: \(sha256)."
        case .checksumMismatch(_, let expected, let actual):
            "Model checksum mismatch. Expected \(expected), got \(actual)."
        case .verificationFailed(_, let message):
            message
        }
    }
}

private enum EngineSettingsDefaultsKey {
    static let engineKind = "Gokan.analysisEngine.kind"
    static let executablePath = "Gokan.kataGo.executablePath"
    static let modelPath = "Gokan.kataGo.modelPath"
    static let configPath = "Gokan.kataGo.configPath"
    static let modelProfileID = "Gokan.kataGo.modelProfileID"
    static let modelCacheRootPath = "Gokan.kataGo.modelCacheRootPath"
}

public enum EngineStatus: Equatable, Sendable {
    case mock
    case kataGoConfigured
    case kataGoIncomplete(missingFields: [String])
    case kataGoUnsupported
    case error(String)

    public var message: String {
        switch self {
        case .mock:
            "Using built-in mock analysis."
        case .kataGoConfigured:
            "KataGo paths are configured."
        case .kataGoIncomplete(let missingFields):
            "Missing \(missingFields.joined(separator: ", "))."
        case .kataGoUnsupported:
            "KataGo analysis is not available on iOS in this build."
        case .error(let message):
            message
        }
    }
}

public typealias AnalysisEngineFactory = @Sendable (AnalysisEngineSelection) throws -> any GoAnalysisEngine

@MainActor
@Observable
public final class GokanAppModel {
    public var game = GameRecord()
    public var selectedPoint: BoardPoint?
    public var analysis: AnalysisSnapshot? {
        didSet {
            reconcileSelectedAnalysisCandidate()
        }
    }
    public var analysisError: String?
    public var documentError: String?
    public var sgfText = "" {
        didSet {
            guard sgfText != oldValue else {
                return
            }
            documentError = nil
            exportedSGFText = ""
        }
    }
    public var exportedSGFText = ""
    public private(set) var positionVersion = 0
    public private(set) var analysisRequestVersion = 0
    public private(set) var selectedAnalysisCandidatePoint: BoardPoint?
    public private(set) var analysisDiagnostics: AnalysisRunDiagnostics?
    public var engineKind: AnalysisEngineKind = .mock {
        didSet {
            engineSelectionDidChange()
        }
    }
    public var kataGoSettings = KataGoPathSettings() {
        didSet {
            engineSelectionDidChange()
        }
    }
    public var kataGoModelSettings = KataGoModelSettings() {
        didSet {
            engineSelectionDidChange()
        }
    }
    public private(set) var engineStatus: EngineStatus = .mock
    public private(set) var kataGoModelStatus: KataGoModelStatus = .notSelected
    public private(set) var modelCatalog: GokanModelCatalog

    private let engineFactory: AnalysisEngineFactory
    private let settingsDefaults: UserDefaults?
    private let supportsKataGoSubprocess: Bool
    private var isRestoringEngineSelection = false

    public init(modelCatalog: GokanModelCatalog = .empty) {
        self.modelCatalog = modelCatalog
        self.engineFactory = Self.defaultEngineFactory
        self.settingsDefaults = .standard
        self.supportsKataGoSubprocess = Self.defaultSupportsKataGoSubprocess
        restoreEngineSelection(Self.loadPersistedEngineSelection(from: .standard))
        refreshEngineStatus()
    }

    public init(
        engine: any GoAnalysisEngine,
        settingsDefaults: UserDefaults? = nil,
        supportsKataGoSubprocess: Bool? = nil,
        modelCatalog: GokanModelCatalog = .empty
    ) {
        self.modelCatalog = modelCatalog
        self.engineFactory = { _ in engine }
        self.settingsDefaults = settingsDefaults
        self.supportsKataGoSubprocess = supportsKataGoSubprocess ?? Self.defaultSupportsKataGoSubprocess
        if let settingsDefaults {
            restoreEngineSelection(Self.loadPersistedEngineSelection(from: settingsDefaults))
        }
        refreshEngineStatus()
    }

    public init(
        engineFactory: @escaping AnalysisEngineFactory,
        settingsDefaults: UserDefaults? = nil,
        supportsKataGoSubprocess: Bool? = nil,
        modelCatalog: GokanModelCatalog = .empty
    ) {
        self.modelCatalog = modelCatalog
        self.engineFactory = engineFactory
        self.settingsDefaults = settingsDefaults
        self.supportsKataGoSubprocess = supportsKataGoSubprocess ?? Self.defaultSupportsKataGoSubprocess
        if let settingsDefaults {
            restoreEngineSelection(Self.loadPersistedEngineSelection(from: settingsDefaults))
        }
        refreshEngineStatus()
    }

    public var selectedAnalysisCandidate: CandidateMove? {
        guard let selectedAnalysisCandidatePoint else {
            return nil
        }

        return analysis?.candidateMoves.first { $0.point == selectedAnalysisCandidatePoint }
    }

    public var canPlaySelectedAnalysisCandidate: Bool {
        guard let candidate = selectedAnalysisCandidate else {
            return false
        }

        var probe = game
        do {
            try probe.play(.play(candidate.point))
            return true
        } catch {
            return false
        }
    }

    public var gameMetadata: GameMetadata {
        get {
            game.metadata
        }
        set {
            guard game.metadata != newValue else {
                return
            }

            game.metadata = newValue
            sgfText = ""
            exportedSGFText = ""
            documentError = nil
        }
    }

    public func play(at point: BoardPoint) {
        do {
            try game.play(.play(point))
            positionDidChange(selectedPoint: point, clearDocumentText: true)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func selectAnalysisCandidate(_ candidate: CandidateMove) {
        selectAnalysisCandidate(at: candidate.point)
    }

    public func selectAnalysisCandidate(at point: BoardPoint) {
        guard analysis?.candidateMoves.contains(where: { $0.point == point }) == true else {
            return
        }

        selectedAnalysisCandidatePoint = point
    }

    public func playSelectedAnalysisCandidate() {
        guard canPlaySelectedAnalysisCandidate,
              let point = selectedAnalysisCandidate?.point else {
            return
        }

        play(at: point)
    }

    public func pass() {
        do {
            try game.play(.pass)
            positionDidChange(selectedPoint: nil, clearDocumentText: true)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func previousMove() {
        guard game.canStepBackward else {
            return
        }

        do {
            try game.stepBackward()
            positionDidChange(selectedPoint: selectedMovePoint, clearDocumentText: false)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func nextMove() {
        guard game.canStepForward else {
            return
        }

        do {
            try game.stepForward()
            positionDidChange(selectedPoint: selectedMovePoint, clearDocumentText: false)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func goToFirstMove() {
        guard game.canStepBackward else {
            return
        }

        do {
            try game.goToStart()
            positionDidChange(selectedPoint: nil, clearDocumentText: false)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func goToLastMove() {
        guard game.canStepForward else {
            return
        }

        do {
            try game.goToEnd()
            positionDidChange(selectedPoint: selectedMovePoint, clearDocumentText: false)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func goToMove(_ moveIndex: Int) {
        let targetIndex = min(max(moveIndex, 0), game.moves.count)
        guard targetIndex != game.currentMoveIndex else {
            return
        }

        do {
            try game.goToMove(targetIndex)
            positionDidChange(selectedPoint: selectedMovePoint, clearDocumentText: false)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func selectVariation(at index: Int) {
        do {
            try game.selectVariation(at: index)
            positionDidChange(selectedPoint: selectedMovePoint, clearDocumentText: false)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func newGame(boardSize: BoardSize = .standard) {
        game = GameRecord(boardSize: boardSize)
        sgfText = ""
        exportedSGFText = ""
        positionDidChange(selectedPoint: nil, clearDocumentText: false)
    }

    public func loadSGFText(_ text: String) {
        do {
            let document = try SGFDocument.parse(text)
            let nextGame = try document.gameRecord()
            game = nextGame
            sgfText = text
            exportedSGFText = ""
            positionDidChange(selectedPoint: nil, clearDocumentText: false)
        } catch {
            documentError = String(describing: error)
        }
    }

    public func loadSGFData(_ data: Data) {
        do {
            let document = try SGFFileDocument(data: data)
            loadSGFText(document.text)
        } catch {
            documentError = error.localizedDescription
        }
    }

    public func loadSGFFile(at url: URL) {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            loadSGFData(try Data(contentsOf: url))
        } catch {
            documentError = error.localizedDescription
        }
    }

    @discardableResult
    public func exportSGFText() throws -> String {
        let text = try SGFDocument(game: game).serialize()
        exportedSGFText = text
        documentError = nil
        return text
    }

    public func exportSGFData() throws -> Data {
        try SGFFileDocument(text: exportSGFText()).data()
    }

    public func verifySelectedKataGoModelChecksum() async {
        guard kataGoSettings.modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            kataGoModelStatus = .manualPath(path: kataGoSettings.modelPath)
            return
        }
        guard let profile = selectedModelProfile() else {
            if kataGoModelSettings.selectedProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                kataGoModelStatus = .notSelected
            } else {
                kataGoModelStatus = .profileUnavailable(profileID: kataGoModelSettings.selectedProfileID)
            }
            return
        }
        guard kataGoModelSettings.cacheRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            kataGoModelStatus = .missingCacheRoot(profileID: profile.id)
            return
        }

        let cache = GokanModelCache(rootURL: URL(filePath: kataGoModelSettings.cacheRootPath))
        let result = await cache.verifyChecksum(for: profile)
        kataGoModelStatus = status(for: result, profile: profile)
        if case .checksumMismatch = kataGoModelStatus {
            engineStatus = .error(kataGoModelStatus.message)
        } else if case .verificationFailed = kataGoModelStatus {
            engineStatus = .error(kataGoModelStatus.message)
        }
    }

    public func analyze() async {
        let version = positionVersion
        let analysisVersion = analysisRequestVersion
        let currentGame = game
        let request = AnalysisRequest(board: currentGame.board, moves: currentGame.appliedMoves)
        let runID = UUID()
        let startedAt = Date()
        analysisDiagnostics = AnalysisRunDiagnostics(
            id: runID,
            engineKind: engineKind,
            boardSize: currentGame.board.size,
            moveIndex: currentGame.currentMoveIndex,
            moveCount: currentGame.moves.count,
            requestedVisits: request.visits,
            startedAt: startedAt
        )

        do {
            let engine = try makeAnalysisEngine()
            let stream = try await engine.analyze(request)
            for try await snapshot in stream {
                if Task.isCancelled {
                    finishDiagnosticsIfCurrent(
                        runID: runID,
                        version: version,
                        analysisVersion: analysisVersion,
                        startedAt: startedAt,
                        outcome: .cancelled
                    )
                    return
                }

                guard isCurrentAnalysisRun(
                    runID: runID,
                    version: version,
                    analysisVersion: analysisVersion
                ) else {
                    return
                }
                analysis = snapshot
                updateDiagnosticsIfCurrent(runID: runID) { diagnostics in
                    diagnostics.snapshotsReceived += 1
                    diagnostics.completedVisits = snapshot.completedVisits
                    diagnostics.candidateCount = snapshot.candidateMoves.count
                    diagnostics.scoreLead = snapshot.scoreLead
                }
            }

            if Task.isCancelled {
                finishDiagnosticsIfCurrent(
                    runID: runID,
                    version: version,
                    analysisVersion: analysisVersion,
                    startedAt: startedAt,
                    outcome: .cancelled
                )
                return
            }

            guard isCurrentAnalysisRun(
                runID: runID,
                version: version,
                analysisVersion: analysisVersion
            ) else {
                return
            }

            finishDiagnosticsIfCurrent(
                runID: runID,
                version: version,
                analysisVersion: analysisVersion,
                startedAt: startedAt,
                outcome: .succeeded
            )
        } catch {
            if Task.isCancelled || error is CancellationError {
                finishDiagnosticsIfCurrent(
                    runID: runID,
                    version: version,
                    analysisVersion: analysisVersion,
                    startedAt: startedAt,
                    outcome: .cancelled
                )
                return
            }

            guard isCurrentAnalysisRun(
                runID: runID,
                version: version,
                analysisVersion: analysisVersion
            ) else {
                return
            }

            if let engineStatus = error as? EngineStatus {
                self.engineStatus = engineStatus
            } else {
                engineStatus = .error(error.localizedDescription)
            }
            analysisError = error.localizedDescription
            finishDiagnosticsIfCurrent(
                runID: runID,
                version: version,
                analysisVersion: analysisVersion,
                startedAt: startedAt,
                outcome: .failed(message: error.localizedDescription)
            )
        }
    }

    public func makeAnalysisEngine() throws -> any GoAnalysisEngine {
        let selection = currentAnalysisEngineSelection()
        switch engineStatus {
        case .kataGoIncomplete, .kataGoUnsupported:
            throw engineStatus
        case .mock, .kataGoConfigured, .error:
            break
        }
        return try engineFactory(selection)
    }

    private func positionDidChange(selectedPoint: BoardPoint?, clearDocumentText: Bool) {
        self.selectedPoint = selectedPoint
        analysis = nil
        analysisError = nil
        analysisDiagnostics = nil
        documentError = nil
        if clearDocumentText {
            sgfText = ""
            exportedSGFText = ""
        }
        positionVersion += 1
        analysisRequestVersion += 1
    }

    private func engineSelectionDidChange() {
        guard isRestoringEngineSelection == false else {
            return
        }

        persistEngineSelection()
        refreshEngineStatus()
        analysis = nil
        analysisError = nil
        analysisDiagnostics = nil
        analysisRequestVersion += 1
    }

    private func isCurrentAnalysisRun(
        runID: UUID,
        version: Int,
        analysisVersion: Int
    ) -> Bool {
        analysisDiagnostics?.id == runID
            && version == positionVersion
            && analysisVersion == analysisRequestVersion
    }

    private func updateDiagnosticsIfCurrent(
        runID: UUID,
        _ update: (inout AnalysisRunDiagnostics) -> Void
    ) {
        guard var diagnostics = analysisDiagnostics,
              diagnostics.id == runID else {
            return
        }

        update(&diagnostics)
        analysisDiagnostics = diagnostics
    }

    private func finishDiagnosticsIfCurrent(
        runID: UUID,
        version: Int,
        analysisVersion: Int,
        startedAt: Date,
        outcome: AnalysisRunOutcome
    ) {
        guard isCurrentAnalysisRun(
            runID: runID,
            version: version,
            analysisVersion: analysisVersion
        ) else {
            return
        }

        let finishedAt = Date()
        updateDiagnosticsIfCurrent(runID: runID) { diagnostics in
            diagnostics.finishedAt = finishedAt
            diagnostics.durationSeconds = max(0, finishedAt.timeIntervalSince(startedAt))
            diagnostics.outcome = outcome
        }
    }

    private func reconcileSelectedAnalysisCandidate() {
        guard let candidateMoves = analysis?.candidateMoves,
              candidateMoves.isEmpty == false else {
            selectedAnalysisCandidatePoint = nil
            return
        }

        if let selectedAnalysisCandidatePoint,
           candidateMoves.contains(where: { $0.point == selectedAnalysisCandidatePoint }) {
            return
        }

        selectedAnalysisCandidatePoint = candidateMoves.first?.point
    }

    private var selectedMovePoint: BoardPoint? {
        guard game.currentMoveIndex > 0 else {
            return nil
        }

        switch game.moves[game.currentMoveIndex - 1].move {
        case .play(let point):
            return point
        case .pass:
            return nil
        }
    }

    private func refreshEngineStatus() {
        let resolution = resolveKataGoConfiguration()
        kataGoModelStatus = resolution.modelStatus

        switch engineKind {
        case .mock:
            engineStatus = .mock
        case .kataGo:
            guard supportsKataGoSubprocess else {
                engineStatus = .kataGoUnsupported
                return
            }

            engineStatus = resolution.missingFields.isEmpty
                ? .kataGoConfigured
                : .kataGoIncomplete(missingFields: resolution.missingFields)
        }
    }

    private func restoreEngineSelection(_ selection: AnalysisEngineSelection) {
        isRestoringEngineSelection = true
        engineKind = selection.kind
        kataGoSettings = selection.kataGoSettings
        kataGoModelSettings = selection.kataGoModelSettings
        isRestoringEngineSelection = false
    }

    private func persistEngineSelection() {
        guard let settingsDefaults else {
            return
        }

        settingsDefaults.set(engineKind.rawValue, forKey: EngineSettingsDefaultsKey.engineKind)
        settingsDefaults.set(kataGoSettings.executablePath, forKey: EngineSettingsDefaultsKey.executablePath)
        settingsDefaults.set(kataGoSettings.modelPath, forKey: EngineSettingsDefaultsKey.modelPath)
        settingsDefaults.set(kataGoSettings.configPath, forKey: EngineSettingsDefaultsKey.configPath)
        settingsDefaults.set(kataGoModelSettings.selectedProfileID, forKey: EngineSettingsDefaultsKey.modelProfileID)
        settingsDefaults.set(kataGoModelSettings.cacheRootPath, forKey: EngineSettingsDefaultsKey.modelCacheRootPath)
    }

    private nonisolated static func loadPersistedEngineSelection(from defaults: UserDefaults) -> AnalysisEngineSelection {
        let rawKind = defaults.string(forKey: EngineSettingsDefaultsKey.engineKind)
        let kind = rawKind.flatMap(AnalysisEngineKind.init(rawValue:)) ?? .mock
        let settings = KataGoPathSettings(
            executablePath: defaults.string(forKey: EngineSettingsDefaultsKey.executablePath) ?? "",
            modelPath: defaults.string(forKey: EngineSettingsDefaultsKey.modelPath) ?? "",
            configPath: defaults.string(forKey: EngineSettingsDefaultsKey.configPath) ?? ""
        )
        let modelSettings = KataGoModelSettings(
            selectedProfileID: defaults.string(forKey: EngineSettingsDefaultsKey.modelProfileID) ?? "",
            cacheRootPath: defaults.string(forKey: EngineSettingsDefaultsKey.modelCacheRootPath) ?? ""
        )
        return AnalysisEngineSelection(kind: kind, kataGoSettings: settings, kataGoModelSettings: modelSettings)
    }

    private func currentAnalysisEngineSelection() -> AnalysisEngineSelection {
        AnalysisEngineSelection(
            kind: engineKind,
            kataGoSettings: kataGoSettings,
            kataGoModelSettings: kataGoModelSettings,
            resolvedKataGoConfiguration: resolveKataGoConfiguration().configuration
        )
    }

    private func resolveKataGoConfiguration() -> KataGoConfigurationResolution {
        var missingFields: [String] = []
        var modelStatus: KataGoModelStatus = .notSelected

        let executablePath = trimmed(kataGoSettings.executablePath)
        if executablePath.isEmpty {
            missingFields.append("executable path")
        }

        let modelResolution = resolveModelURL()
        modelStatus = modelResolution.status
        if let missingField = modelResolution.missingField {
            missingFields.appendMissingField(missingField)
        }

        let configResolution = modelResolution.missingField == "cached model file"
            ? PathResolution(url: nil, missingField: nil, status: modelStatus)
            : resolveConfigURL()
        if let missingField = configResolution.missingField {
            missingFields.appendMissingField(missingField)
        }

        guard missingFields.isEmpty,
              let modelURL = modelResolution.url,
              let configURL = configResolution.url else {
            return KataGoConfigurationResolution(configuration: nil, missingFields: missingFields, modelStatus: modelStatus)
        }

        return KataGoConfigurationResolution(
            configuration: KataGoEngineConfiguration(
                executableURL: URL(filePath: executablePath),
                modelURL: modelURL,
                configURL: configURL
            ),
            missingFields: [],
            modelStatus: modelStatus
        )
    }

    private func resolveModelURL() -> PathResolution {
        let rawModelPath = trimmed(kataGoSettings.modelPath)
        if rawModelPath.isEmpty == false {
            return PathResolution(url: URL(filePath: rawModelPath), missingField: nil, status: .manualPath(path: rawModelPath))
        }

        guard let profile = selectedModelProfile() else {
            return missingProfilePathResolution(missingFieldWhenUnselected: "model path")
        }
        guard trimmed(kataGoModelSettings.cacheRootPath).isEmpty == false else {
            return PathResolution(url: nil, missingField: "model cache root", status: .missingCacheRoot(profileID: profile.id))
        }

        let cache = GokanModelCache(rootURL: URL(filePath: kataGoModelSettings.cacheRootPath))
        switch cache.readiness(for: profile) {
        case .ready(let modelURL, let configURL, _):
            return PathResolution(
                url: modelURL,
                missingField: nil,
                status: .profileReady(
                    profileID: profile.id,
                    displayName: profile.displayName,
                    modelPath: modelURL.path,
                    configPath: configURL?.path
                )
            )
        case .missingModel(let modelURL):
            return PathResolution(url: nil, missingField: "cached model file", status: .missingCachedModel(profileID: profile.id, path: modelURL.path))
        case .missingConfig(let configURL):
            return PathResolution(url: nil, missingField: "cached config file", status: .missingCachedConfig(profileID: profile.id, path: configURL.path))
        }
    }

    private func resolveConfigURL() -> PathResolution {
        let rawConfigPath = trimmed(kataGoSettings.configPath)
        if rawConfigPath.isEmpty == false {
            return PathResolution(url: URL(filePath: rawConfigPath), missingField: nil, status: kataGoModelStatus)
        }

        guard let profile = selectedModelProfile() else {
            return missingProfilePathResolution(missingFieldWhenUnselected: "config path")
        }
        guard trimmed(kataGoModelSettings.cacheRootPath).isEmpty == false else {
            return PathResolution(url: nil, missingField: "model cache root", status: .missingCacheRoot(profileID: profile.id))
        }

        let cache = GokanModelCache(rootURL: URL(filePath: kataGoModelSettings.cacheRootPath))
        guard let configURL = cache.configURL(for: profile) else {
            return PathResolution(url: nil, missingField: "config path", status: kataGoModelStatus)
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return PathResolution(url: nil, missingField: "cached config file", status: .missingCachedConfig(profileID: profile.id, path: configURL.path))
        }

        return PathResolution(url: configURL, missingField: nil, status: kataGoModelStatus)
    }

    private func missingProfilePathResolution(missingFieldWhenUnselected: String) -> PathResolution {
        let profileID = trimmed(kataGoModelSettings.selectedProfileID)
        if profileID.isEmpty {
            return PathResolution(url: nil, missingField: missingFieldWhenUnselected, status: .notSelected)
        }

        return PathResolution(url: nil, missingField: "model profile", status: .profileUnavailable(profileID: profileID))
    }

    private func selectedModelProfile() -> GokanModelProfile? {
        let profileID = trimmed(kataGoModelSettings.selectedProfileID)
        guard profileID.isEmpty == false else {
            return nil
        }

        return modelCatalog.profile(id: profileID)
    }

    private func status(for result: GokanModelVerificationResult, profile: GokanModelProfile) -> KataGoModelStatus {
        switch result {
        case .checksumUnavailable:
            .checksumUnavailable(profileID: profile.id)
        case .verified(_, let expectedSHA256, _):
            .checksumVerified(profileID: profile.id, sha256: expectedSHA256)
        case .mismatch(_, let expectedSHA256, let actualSHA256):
            .checksumMismatch(profileID: profile.id, expected: expectedSHA256, actual: actualSHA256)
        case .missing(let modelURL):
            .missingCachedModel(profileID: profile.id, path: modelURL.path)
        case .failed(_, let message):
            .verificationFailed(profileID: profile.id, message: message)
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public nonisolated static func defaultEngineFactory(selection: AnalysisEngineSelection) throws -> any GoAnalysisEngine {
        switch selection.kind {
        case .mock:
            return MockAnalysisEngine()
        case .kataGo:
            guard let configuration = selection.resolvedKataGoConfiguration else {
                let missingFields = selection.kataGoSettings.missingFields
                guard missingFields.isEmpty else {
                    throw EngineStatus.kataGoIncomplete(missingFields: missingFields)
                }

                return KataGoAnalysisEngine(
                    configuration: KataGoEngineConfiguration(
                        executableURL: URL(filePath: selection.kataGoSettings.executablePath),
                        modelURL: URL(filePath: selection.kataGoSettings.modelPath),
                        configURL: URL(filePath: selection.kataGoSettings.configPath)
                    )
                )
            }

            return KataGoAnalysisEngine(configuration: configuration)
        }
    }

    private nonisolated static var defaultSupportsKataGoSubprocess: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

private struct KataGoConfigurationResolution {
    var configuration: KataGoEngineConfiguration?
    var missingFields: [String]
    var modelStatus: KataGoModelStatus
}

private struct PathResolution {
    var url: URL?
    var missingField: String?
    var status: KataGoModelStatus
}

extension EngineStatus: LocalizedError {
    public var errorDescription: String? {
        message
    }
}

private extension KataGoPathSettings {
    var missingFields: [String] {
        var fields: [String] = []
        if executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.appendMissingField("executable path")
        }
        if modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.appendMissingField("model path")
        }
        if configPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.appendMissingField("config path")
        }
        return fields
    }
}

private extension Array where Element == String {
    mutating func appendMissingField(_ field: String) {
        if contains(field) == false {
            append(field)
        }
    }
}
