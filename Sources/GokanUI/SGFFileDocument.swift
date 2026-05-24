// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
    static let sgf = UTType(exportedAs: "com.gokan.sgf", conformingTo: .plainText)
}

public struct SGFFileDocument: FileDocument, Equatable, Sendable {
    public static var readableContentTypes: [UTType] {
        [.sgf]
    }

    public static var writableContentTypes: [UTType] {
        [.sgf]
    }

    public var text: String

    public init(text: String = "") {
        self.text = text
    }

    public init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SGFFileDocumentError.unsupportedEncoding
        }
        self.text = text
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw SGFFileDocumentError.unreadableFile
        }
        try self.init(data: data)
    }

    public func data() -> Data {
        Data(text.utf8)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data())
    }
}

public enum SGFFileDocumentError: LocalizedError, Equatable, Sendable {
    case unreadableFile
    case unsupportedEncoding

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "The selected SGF file could not be read."
        case .unsupportedEncoding:
            "SGF files must be UTF-8 text."
        }
    }
}
