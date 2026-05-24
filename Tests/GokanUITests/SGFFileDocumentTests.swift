// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import GokanUI

@Test
func sgfFileDocumentReadsUTF8Text() throws {
    let document = try SGFFileDocument(data: Data("(;GM[1]FF[4]SZ[9])".utf8))

    #expect(document.text == "(;GM[1]FF[4]SZ[9])")
}

@Test
func sgfFileDocumentWritesUTF8Text() {
    let document = SGFFileDocument(text: "(;GM[1]FF[4]SZ[9];B[ee])\n")

    #expect(String(data: document.data(), encoding: .utf8) == "(;GM[1]FF[4]SZ[9];B[ee])\n")
}

@Test
func sgfFileDocumentRejectsNonUTF8Data() {
    #expect(throws: SGFFileDocumentError.unsupportedEncoding) {
        try SGFFileDocument(data: Data([0xFF, 0xFE, 0x00]))
    }
}

@Test
func sgfUniformTypeUsesProjectIdentifier() {
    #expect(UTType.sgf.identifier == "com.gokan.sgf")
    #expect(SGFFileDocument.readableContentTypes == [.sgf])
    #expect(SGFFileDocument.writableContentTypes == [.sgf])
}

@Test(arguments: ["Info-iOS.plist", "Info-macOS.plist"])
func appInfoPlistsRegisterSGFDocuments(plistName: String) throws {
    let plist = try appInfoPlist(named: plistName)
    let documentTypes = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
    let sgfDocument = try #require(documentTypes.first)

    #expect(sgfDocument["CFBundleTypeName"] as? String == "Smart Game Format")
    #expect(sgfDocument["CFBundleTypeRole"] as? String == "Editor")
    #expect(sgfDocument["LSHandlerRank"] as? String == "Alternate")
    #expect(sgfDocument["LSItemContentTypes"] as? [String] == ["com.gokan.sgf"])

    let typeDeclarations = try #require(plist["UTImportedTypeDeclarations"] as? [[String: Any]])
    let sgfType = try #require(typeDeclarations.first)
    #expect(sgfType["UTTypeIdentifier"] as? String == "com.gokan.sgf")
    #expect(sgfType["UTTypeDescription"] as? String == "Smart Game Format")
    #expect(sgfType["UTTypeConformsTo"] as? [String] == ["public.plain-text"])

    let tagSpecification = try #require(sgfType["UTTypeTagSpecification"] as? [String: Any])
    #expect(tagSpecification["public.filename-extension"] as? [String] == ["sgf"])
    #expect(tagSpecification["public.mime-type"] as? String == "application/x-go-sgf")
}

private func appInfoPlist(named plistName: String) throws -> [String: Any] {
    let testsDirectory = URL(filePath: #filePath).deletingLastPathComponent()
    let packageRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
    let plistURL = packageRoot.appending(path: "app/Shared").appending(path: plistName)
    let data = try Data(contentsOf: plistURL)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(plist as? [String: Any])
}
