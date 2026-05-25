// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum SGFDocumentError: Error, Equatable, Sendable {
    case missingGameTree
    case unsupportedGame
    case invalidBoardSize
    case invalidSyntax
    case illegalMove(moveNumber: Int, BoardError)
}

public struct SGFDocument: Hashable, Sendable {
    public var boardSize: BoardSize
    public var rootChildren: [GameTreeNode]
    public var metadata: GameMetadata
    public var rootComment: String

    public init(
        boardSize: BoardSize = .standard,
        moves: [PlayedMove] = [],
        metadata: GameMetadata = .empty
    ) {
        self.init(boardSize: boardSize, moves: moves, metadata: metadata, rootComment: "")
    }

    public init(
        boardSize: BoardSize = .standard,
        moves: [PlayedMove] = [],
        metadata: GameMetadata = .empty,
        rootComment: String
    ) {
        self.boardSize = boardSize
        self.rootChildren = Self.chain(from: moves.map { ParsedMoveNode(move: $0) })
        self.metadata = metadata
        self.rootComment = rootComment
    }

    public init(
        boardSize: BoardSize = .standard,
        rootChildren: [GameTreeNode],
        metadata: GameMetadata = .empty
    ) {
        self.init(boardSize: boardSize, rootChildren: rootChildren, metadata: metadata, rootComment: "")
    }

    public init(
        boardSize: BoardSize = .standard,
        rootChildren: [GameTreeNode],
        metadata: GameMetadata = .empty,
        rootComment: String
    ) {
        self.boardSize = boardSize
        self.rootChildren = rootChildren
        self.metadata = metadata
        self.rootComment = rootComment
    }

    public init(game: GameRecord) {
        self.boardSize = game.board.size
        self.rootChildren = game.rootChildren
        self.metadata = game.metadata
        self.rootComment = game.rootComment
    }

    public var moves: [PlayedMove] {
        selectedLineMoves(in: rootChildren)
    }

    public func gameRecord() throws -> GameRecord {
        try validate(
            nodes: rootChildren,
            from: GoBoard(size: boardSize),
            simpleKoReferenceBoard: nil,
            expectedPlayer: nil,
            moveNumber: 1
        )
        return try GameRecord(boardSize: boardSize, rootChildren: rootChildren, metadata: metadata, rootComment: rootComment)
    }

    public func serialize() throws -> String {
        var output = "(;GM[1]FF[4]CA[UTF-8]AP[Gokan]SZ[\(serializedBoardSize)]"
        output += serializeMetadata()
        output += serializeComment(rootComment)
        output += try serializeChildren(rootChildren)
        output += ")\n"
        return output
    }

    public static func parse(_ source: String) throws -> SGFDocument {
        guard source.contains("(;") else {
            throw SGFDocumentError.missingGameTree
        }

        var parser = SGFParser(source: source)
        let tree = try parser.parseGameTree()
        guard parser.isAtEnd() else {
            throw SGFDocumentError.invalidSyntax
        }

        if let game = tree.properties.first(where: { $0.identifier == "GM" })?.values.first, game != "1" {
            throw SGFDocumentError.unsupportedGame
        }

        let size = try parseBoardSize(from: tree.properties.first(where: { $0.identifier == "SZ" })?.values.first)
        let document = SGFDocument(
            boardSize: size,
            rootChildren: try nodes(from: tree, isTopLevel: true),
            metadata: metadata(from: tree.rootProperties),
            rootComment: rootComment(from: tree)
        )
        _ = try document.gameRecord()
        return document
    }

    private static func metadata(from rootProperties: [SGFProperty]) -> GameMetadata {
        GameMetadata(
            blackPlayerName: rootValue("PB", in: rootProperties),
            whitePlayerName: rootValue("PW", in: rootProperties),
            komi: rootValue("KM", in: rootProperties),
            result: rootValue("RE", in: rootProperties),
            gameName: rootValue("GN", in: rootProperties),
            event: rootValue("EV", in: rootProperties),
            date: rootValue("DT", in: rootProperties)
        )
    }

    private static func rootValue(_ identifier: String, in properties: [SGFProperty]) -> String {
        properties.first { $0.identifier == identifier }?.values.first ?? ""
    }

    private static func rootComment(from tree: ParsedSGFTree) -> String {
        var comments: [String] = []

        for properties in tree.nodes {
            if containsMoveProperty(in: properties) {
                break
            }

            let comment = rootValue("C", in: properties)
            if comment.isEmpty == false {
                comments.append(comment)
            }
        }

        return mergedComments(comments)
    }

    private static func parseBoardSize(from value: String?) throws -> BoardSize {
        guard let value, value.isEmpty == false else {
            return .standard
        }

        if let size = Int(value) {
            return BoardSize(width: size, height: size)
        }

        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else {
            throw SGFDocumentError.invalidBoardSize
        }

        return BoardSize(width: parts[0], height: parts[1])
    }

    private static func nodes(from tree: ParsedSGFTree, isTopLevel: Bool = false) throws -> [GameTreeNode] {
        let propertyNodes: ArraySlice<[SGFProperty]>
        if isTopLevel {
            propertyNodes = tree.nodes.drop(while: { containsMoveProperty(in: $0) == false })
        } else {
            propertyNodes = tree.nodes[...]
        }

        var lineNodes = chain(from: try parsedMoveNodes(from: propertyNodes))

        if lineNodes.isEmpty {
            return try tree.variations.flatMap { try nodes(from: $0) }
        }

        let variationNodes = try tree.variations.map { try nodes(from: $0) }.filter { $0.isEmpty == false }
        if variationNodes.isEmpty == false {
            appendVariationNodes(variationNodes, toLastNodeIn: &lineNodes)
        }
        return lineNodes
    }

    private static func parsedMoveNodes(from propertyNodes: ArraySlice<[SGFProperty]>) throws -> [ParsedMoveNode] {
        var nodes: [ParsedMoveNode] = []
        var pendingPrefixComment = ""

        for properties in propertyNodes {
            let comment = rootValue("C", in: properties)
            let moveNodes = try parsedMoveNodes(from: properties)

            if moveNodes.isEmpty {
                if comment.isEmpty == false {
                    if nodes.isEmpty {
                        pendingPrefixComment = mergedComments([pendingPrefixComment, comment])
                    } else {
                        nodes[nodes.count - 1].comment = mergedComments([nodes[nodes.count - 1].comment, comment])
                    }
                }
                continue
            }

            for (index, moveNode) in moveNodes.enumerated() {
                guard index == 0 else {
                    nodes.append(moveNode)
                    continue
                }

                nodes.append(
                    ParsedMoveNode(
                        move: moveNode.move,
                        comment: mergedComments([pendingPrefixComment, moveNode.comment])
                    )
                )
                pendingPrefixComment = ""
            }
        }

        return nodes
    }

    private static func parsedMoveNodes(from properties: [SGFProperty]) throws -> [ParsedMoveNode] {
        let comment = rootValue("C", in: properties)
        var didAttachComment = false

        return try properties.compactMap { property -> ParsedMoveNode? in
            guard property.identifier == "B" || property.identifier == "W" else {
                return nil
            }

            let color: StoneColor = property.identifier == "B" ? .black : .white
            let value = property.values.first ?? ""
            let move: Move = value.isEmpty ? .pass : .play(try SGFCoordinates.decode(value))
            let node = ParsedMoveNode(
                move: PlayedMove(color: color, move: move),
                comment: didAttachComment ? "" : comment
            )
            didAttachComment = true
            return node
        }
    }

    private static func containsMoveProperty(in properties: [SGFProperty]) -> Bool {
        properties.contains { $0.identifier == "B" || $0.identifier == "W" }
    }

    private static func mergedComments(_ comments: [String]) -> String {
        comments.filter { $0.isEmpty == false }.joined(separator: "\n")
    }

    private static func chain(from moves: [ParsedMoveNode]) -> [GameTreeNode] {
        guard let firstMove = moves.first else {
            return []
        }

        if moves.count == 1 {
            return [GameTreeNode(playedMove: firstMove.move, comment: firstMove.comment)]
        }

        let reversedMoves = moves.reversed()
        var node: GameTreeNode?
        for move in reversedMoves {
            node = GameTreeNode(playedMove: move.move, comment: move.comment, children: node.map { [$0] } ?? [])
        }
        return node.map { [$0] } ?? []
    }

    private static func appendVariationNodes(_ variations: [[GameTreeNode]], toLastNodeIn nodes: inout [GameTreeNode]) {
        guard nodes.isEmpty == false else {
            return
        }

        if nodes[0].children.isEmpty {
            nodes[0].children = variations.flatMap { $0 }
        } else {
            appendVariationNodes(variations, toLastNodeIn: &nodes[0].children)
        }
    }

    private func selectedLineMoves(in nodes: [GameTreeNode]) -> [PlayedMove] {
        guard let first = nodes.first else {
            return []
        }
        return [first.playedMove] + selectedLineMoves(in: first.children)
    }

    private func validate(
        nodes: [GameTreeNode],
        from board: GoBoard,
        simpleKoReferenceBoard: GoBoard?,
        expectedPlayer: StoneColor?,
        moveNumber: Int
    ) throws {
        for node in nodes {
            if let expectedPlayer, node.playedMove.color != expectedPlayer {
                throw SGFDocumentError.illegalMove(
                    moveNumber: moveNumber,
                    .wrongPlayer(expected: expectedPlayer, actual: node.playedMove.color)
                )
            }

            let nextBoard: GoBoard
            do {
                nextBoard = try GameRules.applying(
                    node.playedMove,
                    to: board,
                    simpleKoReferenceBoard: simpleKoReferenceBoard
                )
            } catch let error as BoardError {
                throw SGFDocumentError.illegalMove(moveNumber: moveNumber, error)
            }

            try validate(
                nodes: node.children,
                from: nextBoard,
                simpleKoReferenceBoard: board,
                expectedPlayer: node.playedMove.color.opponent,
                moveNumber: moveNumber + 1
            )
        }
    }

    private func serializeChildren(_ children: [GameTreeNode]) throws -> String {
        guard children.isEmpty == false else {
            return ""
        }

        if children.count == 1, let child = children.first {
            return try serializeLine(child)
        }

        return try children.map { child in
            "(\(try serializeLine(child)))"
        }.joined()
    }

    private func serializeLine(_ node: GameTreeNode) throws -> String {
        var output = ";"
        output += node.playedMove.color == .black ? "B" : "W"

        switch node.playedMove.move {
        case .pass:
            output += "[]"
        case .play(let point):
            output += "[\(try SGFCoordinates.encode(point))]"
        }

        output += serializeComment(node.comment)
        output += try serializeChildren(node.children)
        return output
    }

    private func serializeMetadata() -> String {
        [
            ("GN", metadata.gameName),
            ("EV", metadata.event),
            ("DT", metadata.date),
            ("PB", metadata.blackPlayerName),
            ("PW", metadata.whitePlayerName),
            ("KM", metadata.komi),
            ("RE", metadata.result),
        ]
        .filter { $0.1.isEmpty == false }
        .map { "\($0.0)[\(escapedPropertyValue($0.1))]" }
        .joined()
    }

    private func serializeComment(_ comment: String) -> String {
        guard comment.isEmpty == false else {
            return ""
        }

        return "C[\(escapedPropertyValue(comment))]"
    }

    private func escapedPropertyValue(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if character == "\\" || character == "]" {
                result.append("\\")
            }
            result.append(character)
        }
    }

    private var serializedBoardSize: String {
        boardSize.width == boardSize.height ? "\(boardSize.width)" : "\(boardSize.width):\(boardSize.height)"
    }
}

private struct ParsedMoveNode: Hashable, Sendable {
    let move: PlayedMove
    var comment: String

    init(move: PlayedMove, comment: String = "") {
        self.move = move
        self.comment = comment
    }
}

private struct ParsedSGFTree: Hashable, Sendable {
    var nodes: [[SGFProperty]]
    var variations: [ParsedSGFTree]

    var rootProperties: [SGFProperty] {
        nodes.first ?? []
    }

    var properties: [SGFProperty] {
        nodes.flatMap { $0 }
    }
}

private struct SGFProperty: Hashable, Sendable {
    let identifier: String
    let values: [String]
}

private struct SGFParser {
    private let source: String
    private var index: String.Index

    init(source: String) {
        self.source = source
        self.index = source.startIndex
    }

    mutating func parseGameTree() throws -> ParsedSGFTree {
        skipWhitespace()
        guard consume("(") else {
            throw SGFDocumentError.missingGameTree
        }

        var nodes: [[SGFProperty]] = []
        while consume(";") {
            nodes.append(parseNodeProperties())
            skipWhitespace()
        }

        var variations: [ParsedSGFTree] = []
        while peek == "(" {
            variations.append(try parseGameTree())
            skipWhitespace()
        }

        guard consume(")") else {
            throw SGFDocumentError.missingGameTree
        }

        return ParsedSGFTree(nodes: nodes, variations: variations)
    }

    mutating func isAtEnd() -> Bool {
        skipWhitespace()
        return index == source.endIndex
    }

    private mutating func parseNodeProperties() -> [SGFProperty] {
        var properties: [SGFProperty] = []
        skipWhitespace()

        while let character = peek, character.isUppercase {
            let identifier = parseIdentifier()
            var values: [String] = []

            while consume("[") {
                values.append(parsePropertyValue())
                skipWhitespace()
            }

            properties.append(SGFProperty(identifier: identifier, values: values))
            skipWhitespace()
        }

        return properties
    }

    private mutating func parseIdentifier() -> String {
        let start = index
        while let character = peek, character.isUppercase {
            advance()
        }
        return String(source[start..<index])
    }

    private mutating func parsePropertyValue() -> String {
        var value = ""

        while let character = peek {
            advance()
            if character == "\\" {
                guard let escaped = peek else {
                    break
                }
                value.append(escaped)
                advance()
            } else if character == "]" {
                break
            } else {
                value.append(character)
            }
        }

        return value
    }

    private var peek: Character? {
        index < source.endIndex ? source[index] : nil
    }

    @discardableResult
    private mutating func consume(_ character: Character) -> Bool {
        skipWhitespace()
        guard peek == character else {
            return false
        }
        advance()
        return true
    }

    private mutating func advance() {
        index = source.index(after: index)
    }

    private mutating func skipWhitespace() {
        while let character = peek, character.isWhitespace {
            advance()
        }
    }
}
