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
    public var analysis: AnalysisSnapshot?
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

    public init() {
        self.engineFactory = Self.defaultEngineFactory
        refreshEngineStatus()
    }

    public init(engine: any GoAnalysisEngine) {
        self.engineFactory = { _ in engine }
    }

    public init(engineFactory: @escaping AnalysisEngineFactory) {
        self.engineFactory = engineFactory
        refreshEngineStatus()
    }

    public func play(at point: BoardPoint) {
        do {
            try game.play(.play(point))
            positionDidChange(selectedPoint: point, clearDocumentText: true)
        } catch {
            analysisError = String(describing: error)
        }
    }

    public func pass() {
        do {
            try game.play(.pass)
            positionDidChange(selectedPoint: nil, clearDocumentText: true)
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
            let request = AnalysisRequest(board: currentGame.board, moves: currentGame.moves)
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
        refreshEngineStatus()
        analysis = nil
        analysisError = nil
        analysisRequestVersion += 1
    }

    private func refreshEngineStatus() {
        engineStatus = Self.status(for: AnalysisEngineSelection(kind: engineKind, kataGoSettings: kataGoSettings))
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
