// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct PlayedMove: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let color: StoneColor
    public let move: Move

    public init(id: UUID = UUID(), color: StoneColor, move: Move) {
        self.id = id
        self.color = color
        self.move = move
    }
}

public struct GameTreeNode: Hashable, Sendable, Identifiable {
    public let id: UUID
    public var playedMove: PlayedMove
    public var comment: String
    public var children: [GameTreeNode]

    public init(
        id: UUID = UUID(),
        playedMove: PlayedMove,
        comment: String = "",
        children: [GameTreeNode] = []
    ) {
        self.id = id
        self.playedMove = playedMove
        self.comment = comment
        self.children = children
    }
}

public struct GameVariationChoice: Hashable, Sendable, Identifiable {
    public let index: Int
    public let move: PlayedMove
    public let isSelected: Bool

    public var id: Int {
        index
    }

    public init(index: Int, move: PlayedMove, isSelected: Bool) {
        self.index = index
        self.move = move
        self.isSelected = isSelected
    }
}

public struct GameMoveListItem: Hashable, Sendable, Identifiable {
    public let index: Int
    public let move: PlayedMove?
    public let isCurrent: Bool

    public var id: Int {
        index
    }

    public init(index: Int, move: PlayedMove?, isCurrent: Bool) {
        self.index = index
        self.move = move
        self.isCurrent = isCurrent
    }
}

public struct GameRecord: Hashable, Sendable {
    public private(set) var board: GoBoard
    public private(set) var nextPlayer: StoneColor
    public private(set) var currentMoveIndex: Int
    public private(set) var rootChildren: [GameTreeNode]
    public var metadata: GameMetadata
    public var rootComment: String

    private var selectedLinePath: [Int]
    private var simpleKoReferenceBoard: GoBoard?

    public init(boardSize: BoardSize = .standard, metadata: GameMetadata = .empty) {
        self.init(boardSize: boardSize, metadata: metadata, rootComment: "")
    }

    public init(
        boardSize: BoardSize = .standard,
        metadata: GameMetadata = .empty,
        rootComment: String
    ) {
        self.board = GoBoard(size: boardSize)
        self.nextPlayer = .black
        self.currentMoveIndex = 0
        self.rootChildren = []
        self.metadata = metadata
        self.rootComment = rootComment
        self.selectedLinePath = []
        self.simpleKoReferenceBoard = nil
    }

    public init(
        boardSize: BoardSize = .standard,
        rootChildren: [GameTreeNode],
        metadata: GameMetadata = .empty
    ) throws {
        try self.init(boardSize: boardSize, rootChildren: rootChildren, metadata: metadata, rootComment: "")
    }

    public init(
        boardSize: BoardSize = .standard,
        rootChildren: [GameTreeNode],
        metadata: GameMetadata = .empty,
        rootComment: String
    ) throws {
        self.board = GoBoard(size: boardSize)
        self.nextPlayer = .black
        self.currentMoveIndex = 0
        self.rootChildren = rootChildren
        self.metadata = metadata
        self.rootComment = rootComment
        self.selectedLinePath = []
        self.simpleKoReferenceBoard = nil
        self.selectedLinePath = selectedLineFollowingFirstChildren(from: [])
        try goToEnd()
    }

    public var moves: [PlayedMove] {
        nodes(along: selectedLinePath).map(\.playedMove)
    }

    public var appliedMoves: [PlayedMove] {
        Array(moves.prefix(currentMoveIndex))
    }

    public var currentNodeComment: String {
        get {
            guard currentMoveIndex > 0 else {
                return rootComment
            }

            let path = Array(selectedLinePath.prefix(currentMoveIndex))
            return node(at: path)?.comment ?? ""
        }
        set {
            guard currentMoveIndex > 0 else {
                rootComment = newValue
                return
            }

            let path = Array(selectedLinePath.prefix(currentMoveIndex))
            Self.updateNodeComment(&rootChildren, at: path, to: newValue)
        }
    }

    public var moveListItems: [GameMoveListItem] {
        let rootItem = GameMoveListItem(
            index: 0,
            move: nil,
            isCurrent: currentMoveIndex == 0
        )
        let moveItems = moves.enumerated().map { offset, move in
            let index = offset + 1
            return GameMoveListItem(
                index: index,
                move: move,
                isCurrent: index == currentMoveIndex
            )
        }
        return [rootItem] + moveItems
    }

    public var canStepBackward: Bool {
        currentMoveIndex > 0
    }

    public var canStepForward: Bool {
        currentMoveIndex < moves.count
    }

    public var variationChoices: [GameVariationChoice] {
        let path = Array(selectedLinePath.prefix(currentMoveIndex))
        let selectedIndex = currentMoveIndex < selectedLinePath.count ? selectedLinePath[currentMoveIndex] : nil
        return children(at: path).enumerated().map { index, node in
            GameVariationChoice(index: index, move: node.playedMove, isSelected: index == selectedIndex)
        }
    }

    public mutating func play(_ move: Move) throws {
        try play(PlayedMove(color: nextPlayer, move: move))
    }

    public mutating func play(_ playedMove: PlayedMove) throws {
        if let expectedPlayer = expectedPlayerForNewMove(), playedMove.color != expectedPlayer {
            throw BoardError.wrongPlayer(expected: expectedPlayer, actual: playedMove.color)
        }

        _ = try GameRules.applying(
            playedMove,
            to: board,
            simpleKoReferenceBoard: simpleKoReferenceBoard
        )

        let parentPath = Array(selectedLinePath.prefix(currentMoveIndex))
        let childIndex = appendOrFindChild(GameTreeNode(playedMove: playedMove), to: parentPath)
        selectedLinePath = selectedLineFollowingFirstChildren(from: parentPath + [childIndex])
        currentMoveIndex = parentPath.count + 1
        try refreshReviewedPosition()
    }

    public mutating func stepBackward() throws {
        try goToMove(currentMoveIndex - 1)
    }

    public mutating func stepForward() throws {
        try goToMove(currentMoveIndex + 1)
    }

    public mutating func goToStart() throws {
        try goToMove(0)
    }

    public mutating func goToEnd() throws {
        try goToMove(moves.count)
    }

    public mutating func goToMove(_ moveIndex: Int) throws {
        currentMoveIndex = min(max(moveIndex, 0), moves.count)
        try refreshReviewedPosition()
    }

    public mutating func selectVariation(at index: Int) throws {
        let parentPath = Array(selectedLinePath.prefix(currentMoveIndex))
        let availableChildren = children(at: parentPath)
        guard availableChildren.indices.contains(index) else {
            return
        }

        selectedLinePath = selectedLineFollowingFirstChildren(from: parentPath + [index])
        currentMoveIndex = parentPath.count + 1
        try refreshReviewedPosition()
    }

    private mutating func refreshReviewedPosition() throws {
        var rebuiltBoard = GoBoard(size: board.size)
        var rebuiltSimpleKoReferenceBoard: GoBoard?
        var expectedPlayer: StoneColor?

        for playedMove in appliedMoves {
            if let expectedPlayer, playedMove.color != expectedPlayer {
                throw BoardError.wrongPlayer(expected: expectedPlayer, actual: playedMove.color)
            }

            let beforeMove = rebuiltBoard
            rebuiltBoard = try GameRules.applying(
                playedMove,
                to: rebuiltBoard,
                simpleKoReferenceBoard: rebuiltSimpleKoReferenceBoard
            )
            rebuiltSimpleKoReferenceBoard = beforeMove
            expectedPlayer = playedMove.color.opponent
        }

        board = rebuiltBoard
        simpleKoReferenceBoard = rebuiltSimpleKoReferenceBoard
        nextPlayer = nextPlayerAfterMove(at: currentMoveIndex)
    }

    private func nextPlayerAfterMove(at moveIndex: Int) -> StoneColor {
        let selectedMoves = moves
        if moveIndex < selectedMoves.count {
            return selectedMoves[moveIndex].color
        }
        return selectedMoves.prefix(moveIndex).last?.color.opponent ?? .black
    }

    private func expectedPlayerForNewMove() -> StoneColor? {
        currentMoveIndex == 0 ? nil : nextPlayer
    }

    private func selectedLineFollowingFirstChildren(from path: [Int]) -> [Int] {
        var path = path
        while let node = node(at: path), node.children.isEmpty == false {
            path.append(0)
        }
        if path.isEmpty, rootChildren.isEmpty == false {
            return selectedLineFollowingFirstChildren(from: [0])
        }
        return path
    }

    private func nodes(along path: [Int]) -> [GameTreeNode] {
        var result: [GameTreeNode] = []
        var children = rootChildren
        for index in path {
            guard children.indices.contains(index) else {
                break
            }
            let node = children[index]
            result.append(node)
            children = node.children
        }
        return result
    }

    private func node(at path: [Int]) -> GameTreeNode? {
        nodes(along: path).last
    }

    private func children(at path: [Int]) -> [GameTreeNode] {
        guard path.isEmpty == false else {
            return rootChildren
        }
        return node(at: path)?.children ?? []
    }

    private mutating func appendOrFindChild(_ child: GameTreeNode, to path: [Int]) -> Int {
        if let existingIndex = children(at: path).firstIndex(where: { $0.playedMove.move == child.playedMove.move && $0.playedMove.color == child.playedMove.color }) {
            return existingIndex
        }

        if path.isEmpty {
            rootChildren.append(child)
            return rootChildren.count - 1
        }

        return Self.appendChild(&rootChildren, child, to: path)
    }

    private static func appendChild(_ nodes: inout [GameTreeNode], _ child: GameTreeNode, to path: [Int]) -> Int {
        guard let index = path.first, nodes.indices.contains(index) else {
            nodes.append(child)
            return nodes.count - 1
        }

        if path.count == 1 {
            nodes[index].children.append(child)
            return nodes[index].children.count - 1
        }

        return appendChild(&nodes[index].children, child, to: Array(path.dropFirst()))
    }

    private static func updateNodeComment(_ nodes: inout [GameTreeNode], at path: [Int], to comment: String) {
        guard let index = path.first, nodes.indices.contains(index) else {
            return
        }

        if path.count == 1 {
            nodes[index].comment = comment
            return
        }

        updateNodeComment(&nodes[index].children, at: Array(path.dropFirst()), to: comment)
    }
}
