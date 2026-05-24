// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import GokanCore
import GokanEngine
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

    public init(kind: AnalysisEngineKind, kataGoSettings: KataGoPathSettings) {
        self.kind = kind
        self.kataGoSettings = kataGoSettings
    }
}

private enum EngineSettingsDefaultsKey {
    static let engineKind = "Gokan.analysisEngine.kind"
    static let executablePath = "Gokan.kataGo.executablePath"
    static let modelPath = "Gokan.kataGo.modelPath"
    static let configPath = "Gokan.kataGo.configPath"
}

public enum EngineStatus: Equatable, Sendable {
    case mock
    case kataGoConfigured
    case kataGoIncomplete(missingFields: [String])
    case error(String)

    public var message: String {
        switch self {
        case .mock:
            "Using built-in mock analysis."
        case .kataGoConfigured:
            "KataGo paths are configured."
        case .kataGoIncomplete(let missingFields):
            "Missing \(missingFields.joined(separator: ", "))."
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
    public private(set) var engineStatus: EngineStatus = .mock

    private let engineFactory: AnalysisEngineFactory
    private let settingsDefaults: UserDefaults?
    private var isRestoringEngineSelection = false

    public init() {
        self.engineFactory = Self.defaultEngineFactory
        self.settingsDefaults = .standard
        restoreEngineSelection(Self.loadPersistedEngineSelection(from: .standard))
        refreshEngineStatus()
    }

    public init(engine: any GoAnalysisEngine, settingsDefaults: UserDefaults? = nil) {
        self.engineFactory = { _ in engine }
        self.settingsDefaults = settingsDefaults
        if let settingsDefaults {
            restoreEngineSelection(Self.loadPersistedEngineSelection(from: settingsDefaults))
        }
        refreshEngineStatus()
    }

    public init(engineFactory: @escaping AnalysisEngineFactory, settingsDefaults: UserDefaults? = nil) {
        self.engineFactory = engineFactory
        self.settingsDefaults = settingsDefaults
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

    public func analyze() async {
        let version = positionVersion
        let analysisVersion = analysisRequestVersion
        let currentGame = game
        do {
            let engine = try makeAnalysisEngine()
            let request = AnalysisRequest(board: currentGame.board, moves: currentGame.appliedMoves)
            let stream = try await engine.analyze(request)
            for try await snapshot in stream {
                guard Task.isCancelled == false,
                      version == positionVersion,
                      analysisVersion == analysisRequestVersion else {
                    return
                }
                analysis = snapshot
            }
        } catch {
            guard Task.isCancelled == false,
                  version == positionVersion,
                  analysisVersion == analysisRequestVersion else {
                return
            }
            if let engineStatus = error as? EngineStatus {
                self.engineStatus = engineStatus
            } else {
                engineStatus = .error(error.localizedDescription)
            }
            analysisError = error.localizedDescription
        }
    }

    public func makeAnalysisEngine() throws -> any GoAnalysisEngine {
        let selection = AnalysisEngineSelection(kind: engineKind, kataGoSettings: kataGoSettings)
        if case .kataGoIncomplete = engineStatus {
            throw engineStatus
        }
        return try engineFactory(selection)
    }

    private func positionDidChange(selectedPoint: BoardPoint?, clearDocumentText: Bool) {
        self.selectedPoint = selectedPoint
        analysis = nil
        analysisError = nil
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
        analysisRequestVersion += 1
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
        engineStatus = Self.status(for: AnalysisEngineSelection(kind: engineKind, kataGoSettings: kataGoSettings))
    }

    private func restoreEngineSelection(_ selection: AnalysisEngineSelection) {
        isRestoringEngineSelection = true
        engineKind = selection.kind
        kataGoSettings = selection.kataGoSettings
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
    }

    private nonisolated static func loadPersistedEngineSelection(from defaults: UserDefaults) -> AnalysisEngineSelection {
        let rawKind = defaults.string(forKey: EngineSettingsDefaultsKey.engineKind)
        let kind = rawKind.flatMap(AnalysisEngineKind.init(rawValue:)) ?? .mock
        let settings = KataGoPathSettings(
            executablePath: defaults.string(forKey: EngineSettingsDefaultsKey.executablePath) ?? "",
            modelPath: defaults.string(forKey: EngineSettingsDefaultsKey.modelPath) ?? "",
            configPath: defaults.string(forKey: EngineSettingsDefaultsKey.configPath) ?? ""
        )
        return AnalysisEngineSelection(kind: kind, kataGoSettings: settings)
    }

    private nonisolated static func status(for selection: AnalysisEngineSelection) -> EngineStatus {
        switch selection.kind {
        case .mock:
            return .mock
        case .kataGo:
            let missingFields = selection.kataGoSettings.missingFields
            return missingFields.isEmpty ? .kataGoConfigured : .kataGoIncomplete(missingFields: missingFields)
        }
    }

    public nonisolated static func defaultEngineFactory(selection: AnalysisEngineSelection) throws -> any GoAnalysisEngine {
        switch selection.kind {
        case .mock:
            return MockAnalysisEngine()
        case .kataGo:
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
    }
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
            fields.append("executable path")
        }
        if modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append("model path")
        }
        if configPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append("config path")
        }
        return fields
    }
}
