// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import GokanCore
import GokanEngine

public struct GoBoardView: View {
    public let board: GoBoard
    public let selectedPoint: BoardPoint?
    public let candidateMoves: [CandidateMove]
    public let onPlay: (BoardPoint) -> Void

    public init(
        board: GoBoard,
        selectedPoint: BoardPoint? = nil,
        candidateMoves: [CandidateMove] = [],
        onPlay: @escaping (BoardPoint) -> Void
    ) {
        self.board = board
        self.selectedPoint = selectedPoint
        self.candidateMoves = candidateMoves
        self.onPlay = onPlay
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let origin = CGPoint(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2
            )
            let spacing = side / CGFloat(max(board.size.width, board.size.height))
            let inset = spacing / 2

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.78, green: 0.58, blue: 0.34).gradient)
                    .frame(width: side, height: side)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                Canvas { context, _ in
                    var path = Path()

                    for index in 0..<board.size.width {
                        let x = origin.x + inset + CGFloat(index) * spacing
                        path.move(to: CGPoint(x: x, y: origin.y + inset))
                        path.addLine(to: CGPoint(x: x, y: origin.y + side - inset))
                    }

                    for index in 0..<board.size.height {
                        let y = origin.y + inset + CGFloat(index) * spacing
                        path.move(to: CGPoint(x: origin.x + inset, y: y))
                        path.addLine(to: CGPoint(x: origin.x + side - inset, y: y))
                    }

                    context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 1)
                }

                ForEach(board.size.points) { point in
                    BoardIntersectionView(
                        point: point,
                        color: board[point],
                        candidate: candidateMoves.first { $0.point == point },
                        isSelected: selectedPoint == point,
                        spacing: spacing,
                        onPlay: onPlay
                    )
                    .position(
                        x: origin.x + inset + CGFloat(point.x) * spacing,
                        y: origin.y + inset + CGFloat(point.y) * spacing
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(minWidth: 320, minHeight: 320)
        .accessibilityLabel("Go board")
    }
}

private struct BoardIntersectionView: View {
    let point: BoardPoint
    let color: StoneColor?
    let candidate: CandidateMove?
    let isSelected: Bool
    let spacing: CGFloat
    let onPlay: (BoardPoint) -> Void

    var body: some View {
        Button {
            onPlay(point)
        } label: {
            ZStack {
                Circle()
                    .fill(stoneFill)
                    .shadow(color: shadowColor, radius: 2, y: 1)
                    .opacity(color == nil ? 0 : 1)

                if let candidate, color == nil {
                    Circle()
                        .stroke(.blue.opacity(0.7), lineWidth: 2)
                    Text("\(Int(candidate.winRate * 100))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.blue)
                }

                if isSelected {
                    Circle()
                        .stroke(.yellow, lineWidth: 3)
                }
            }
            .frame(width: spacing * 0.82, height: spacing * 0.82)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Point \(point.x + 1), \(point.y + 1)")
    }

    private var stoneFill: some ShapeStyle {
        switch color {
        case .black:
            AnyShapeStyle(Color.black.gradient)
        case .white:
            AnyShapeStyle(Color.white.gradient)
        case nil:
            AnyShapeStyle(Color.clear)
        }
    }

    private var shadowColor: Color {
        color == nil ? .clear : .black.opacity(0.35)
    }
}
