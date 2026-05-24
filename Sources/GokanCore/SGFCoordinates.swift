// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum SGFCoordinateError: Error, Equatable, Sendable {
    case unsupportedPoint
    case malformedCoordinate
}

public enum SGFCoordinates {
    public static func encode(_ point: BoardPoint) throws -> String {
        guard (0..<52).contains(point.x), (0..<52).contains(point.y) else {
            throw SGFCoordinateError.unsupportedPoint
        }

        return "\(character(for: point.x))\(character(for: point.y))"
    }

    public static func decode(_ coordinate: String) throws -> BoardPoint {
        guard coordinate.count == 2 else {
            throw SGFCoordinateError.malformedCoordinate
        }

        let values = coordinate.compactMap(value(for:))
        guard values.count == 2 else {
            throw SGFCoordinateError.malformedCoordinate
        }

        return BoardPoint(x: values[0], y: values[1])
    }

    private static func character(for value: Int) -> Character {
        let scalar: UnicodeScalar
        if value < 26 {
            scalar = UnicodeScalar(UInt8(ascii: "a") + UInt8(value))
        } else {
            scalar = UnicodeScalar(UInt8(ascii: "A") + UInt8(value - 26))
        }
        return Character(scalar)
    }

    private static func value(for character: Character) -> Int? {
        guard let ascii = character.asciiValue else {
            return nil
        }

        if ascii >= UInt8(ascii: "a"), ascii <= UInt8(ascii: "z") {
            return Int(ascii - UInt8(ascii: "a"))
        }

        if ascii >= UInt8(ascii: "A"), ascii <= UInt8(ascii: "Z") {
            return Int(ascii - UInt8(ascii: "A")) + 26
        }

        return nil
    }
}
