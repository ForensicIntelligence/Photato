import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class InkModeArchiveWorkflowTests: XCTestCase {
  @MainActor func testNative48HTTPPreservesInkDataAndCanExitLayerlessMode() async throws {
    let gray = try InkPlane(width: 3, height: 1, bytes: Data([0, 128, 255]))
    let duo = try CraftDocument(width: 3, height: 1).replacingInkMode(.duotone(.init(gray: gray,
      settings: .init(inks: [.init(name: "Blue", color: Pixel(0.1, 0.2, 0.8))]))))
    var multi = duo; try InkModeInput.multichannel(in: duo).apply(to: &multi)
    let helper = AutomationTests(), files = DocumentIOWorkflowTests()
    for original in [duo, multi] {
      try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
        document.store.session = EditorSession(document: original)
        try service.share(document); service.setDocumentTransfersEnabled(true)
        let share = try XCTUnwrap(service.shares.first), route = "/v1/documents/\(share.id)/file.photato"
        XCTAssertTrue(document.store.canBeginDocumentMode)
        XCTAssertEqual(document.store.documentModeState["components"] as? [String], original.colorChannelNames)
        for version in [nil, "47"] as [String?] {
          let rejected = try await files.request(service, path: route, headers: version.map { ["X-Photato-Archive-Version": $0] } ?? [:])
          XCTAssertEqual(rejected.0.statusCode, 422)
          XCTAssertTrue(String(decoding: rejected.1, as: UTF8.self).contains("48"))
        }
        let native = try await files.request(service, path: route, headers: ["X-Photato-Archive-Version": "48"])
        XCTAssertEqual(native.0.statusCode, 200)
        XCTAssertTrue(try NativeArchive.decode(native.1) == original)
        let stale = try await files.request(service, path: route, headers: ["X-Photato-Archive-Version": "48", "X-Photato-Revision": "stale"])
        XCTAssertEqual(stale.0.statusCode, 409)
        let imported = try await files.request(service, path: "/v1/documents/import", data: native.1, type: "application/vnd.photato.document")
        XCTAssertEqual(imported.0.statusCode, 201)
        let reopened = try XCTUnwrap(service.controller.documents.compactMap { $0 as? CraftNSDocument }.first { $0 !== document })
        XCTAssertTrue(reopened.store.document == original)
        reopened.updateChangeCount(.changeCleared); reopened.close()
        var expected = original; try Command.rotateCanvas(.clockwise).apply(to: &expected)
        let rotation = try await helper.edit(service, document, "document.rotate", ["turn": "clockwise"])
        XCTAssertEqual(rotation, 200); XCTAssertTrue(document.store.document == expected)
        let geometryUndo = try await helper.edit(service, document, "history.undo")
        XCTAssertEqual(geometryUndo, 200); XCTAssertTrue(document.store.document == original)
        let conversion = try await helper.edit(service, document, "document.convertMode", ["mode": "rgb", "depth": 8])
        XCTAssertEqual(conversion, 200); XCTAssertNil(document.store.document.inkMode)
        let undoStatus = try await helper.edit(service, document, "history.undo")
        XCTAssertEqual(undoStatus, 200)
        XCTAssertTrue(document.store.document == original)
        let cap = try XCTUnwrap(AutomationService.documentTransferCapabilities["nativeArchives"] as? [String: Any])
        XCTAssertEqual(cap["inkModeVersion"] as? Int, 48); XCTAssertEqual(cap["readVersions"] as? [Int], Array(1...61))
      }
    }
  }
}
