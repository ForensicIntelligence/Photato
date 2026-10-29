import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private actor TypeTransport: AdobeResourceTransport {
  let data: Data
  init(_ data: Data) { self.data = data }
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("No upload in this fixture.") }
}
final class NativeTypeWorkflowTests: XCTestCase {
  @MainActor func testNativeCaretFormattingCommitCancelAndHistory() async throws {
    _ = NSApplication.shared
    let store = EditorStore(document: try CraftDocument(width: 400, height: 200))
    defer { store.renderTask?.cancel() }
    let original = store.document
    store.beginType(at: CGPoint(x: 10, y: 10), end: CGPoint(x: 10, y: 10))
    let draft = try XCTUnwrap(store.typeEditingDraft)
    let editor = try CanvasTypeEditor(store: store, draft: draft); store.typeEditor = editor
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = editor; window.makeFirstResponder(editor)
    defer { editor.delegate = nil; window.contentView = nil; window.orderOut(nil) }
    let manager = try XCTUnwrap(editor.undoManager); manager.groupsByEvent = false
    manager.beginUndoGrouping(); editor.insertText("Hello native", replacementRange: NSRange(location: 0, length: 0)); manager.endUndoGrouping()
    XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(editor.string, "Hello native")
    XCTAssertEqual(draft.content.text, "Hello native")
    XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("undo:"), with: nil)); XCTAssertEqual(editor.string, "")
    XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("redo:"), with: nil)); XCTAssertEqual(editor.string, "Hello native")
    editor.setSelectedRange(NSRange(location: 0, length: 5))
    manager.beginUndoGrouping(); editor.format(paragraph: false) { s, _ in s.color = Pixel(1, 0, 0); s.underline = true }; manager.endUndoGrouping()
    XCTAssertEqual(draft.content.typography?.runs.first?.length, 5)
    XCTAssertTrue(store.finishType()); XCTAssertNil(store.error)
    let edited = store.document
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo(); XCTAssertEqual(store.document, original)
    await store.redo(); XCTAssertEqual(store.document, edited)
    store.typeEditor = nil
    store.beginType(try XCTUnwrap(store.activeLayer)); store.typeEditingDraft?.content.text = "cancel me"
    XCTAssertTrue(store.finishType(cancel: true)); XCTAssertEqual(store.document, edited)
    store.setTypeFrame(.paragraph, width: 160, height: 80)
    XCTAssertEqual(store.editableType?.typography?.kind, .paragraph)
    XCTAssertNil(DocumentIO.persistenceIssue(store.document, format: .psd))
  }
  @MainActor func testNativeHTTPTypeStateArchiveBusyStaleAndInvalid() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: try CraftDocument(width: 400, height: 180))
      try service.share(shared); service.setDocumentTransfersEnabled(true)
      let type: [String: Any] = ["text": "API type", "style": ["font": "HelveticaNeue", "size": 25]]
      let create = try await helper.edit(service, shared, "text.create", ["text": type, "x": 12, "y": 18, "name": "Caption"])
      XCTAssertEqual(create, 200)
      let layer = try XCTUnwrap(shared.store.activeLayer), before = shared.store.document
      guard case .text(let content) = layer.content else { return XCTFail("Expected editable text") }
      XCTAssertEqual(content.typography?.defaultStyle.size, 25)
      let share = try XCTUnwrap(service.shares.first)
      let state = service.state(share, document: shared)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: state))
      let native = try await helper.request(service, path: "/v1/documents/\(share.id)/file.photato", headers: ["X-Photato-Archive-Version": "16"])
      XCTAssertEqual(native.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(native.1), before)
      let update: [String: Any] = ["layerID": layer.id.uuidString, "text": ["text": "Edited", "kind": "paragraph", "width": 100, "height": 80]]
      let status = try await helper.edit(service, shared, "text.set", update); XCTAssertEqual(status, 200)
      let undo = try await helper.edit(service, shared, "history.undo"); XCTAssertEqual(undo, 200); XCTAssertEqual(shared.store.document, before)
      let stale = try await helper.edit(service, shared, "text.set", update, revision: "stale"); XCTAssertEqual(stale, 409)
      shared.store.beginType(layer)
      let busy = try await helper.edit(service, shared, "text.set", update); XCTAssertEqual(busy, 409)
      shared.store.finishType(cancel: true)
      let bad = try await helper.edit(service, shared, "text.set", ["layerID": layer.id.uuidString, "text": ["text": "bad", "style": ["size": true]]])
      XCTAssertEqual(bad, 400); XCTAssertEqual(shared.store.document, before)
    }
  }
  func request(_ edits: [[String: Any]], fonts: [String: Any]? = nil) throws -> AdobeActionsRequest {
    var input: [String: Any] = ["image": ["source": ["url": "https://example.test/base.psd"]], "edits": ["layers": edits],
      "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]]
    input["fontOptions"] = fonts
    return try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: input), createComposite: true)
  }
  func addition() -> [String: Any] {
    ["type": "text_layer", "operation": ["type": "add", "placement": ["type": "top"]], "name": "Caption",
      "text": ["content": "One\nTwo", "frame": ["type": "area", "bounds": ["left": 10, "top": 20, "right": 210, "bottom": 150]],
        "characterStyles": [["apply": ["from": 0, "to": 2], "characterStyle": ["font": ["postScriptName": "HelveticaNeue"], "fontSize": 24, "underline": true]]],
        "paragraphStyles": [["apply": ["from": 1, "to": 1], "paragraphStyle": ["alignment": "right"]]]]]
  }
  func testAdobeInclusiveCharacterAndParagraphRanges() throws {
    var doc = try CraftDocument(width: 300, height: 200); doc.resolution = 144
    let result = try request([addition()]).applying(to: doc).session.document
    let layer = try XCTUnwrap(result.layers.last)
    guard case .text(let text) = layer.content else { return XCTFail("Type not retained") }
    XCTAssertEqual(text.typography?.runs.first?.length, 3)
    XCTAssertEqual(text.typography?.runs.first?.style.size, 12)
    XCTAssertEqual(text.typography?.runs.last?.paragraph.alignment, .right)
    XCTAssertEqual(layer.coordinateTransform.tx, 10); XCTAssertEqual(layer.coordinateTransform.ty, 20)
    let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(result))
    guard case .text(let imported) = reopened.layers.last?.content else { return XCTFail("PSD type missing") }
    XCTAssertEqual(imported.text, text.text); XCTAssertEqual(imported.typography?.runs, text.typography?.runs)
    let edit: [String: Any] = ["type": "text_layer", "operation": ["type": "edit"], "name": "Caption", "text": ["content": "New words"]]
    let updated = try request([edit]).applying(to: reopened).session.document
    guard case .text(let content) = updated.layers.last?.content else { return XCTFail() }; XCTAssertEqual(content.text, "New words")
  }
  @MainActor func testPublishedCompositeJobKeepsTypeEditable() async throws {
    let doc = try CraftDocument(width: 300, height: 200), transport = TypeTransport(try PSDCodec.writeRasterLayers(CraftDocument(width: 300, height: 200)))
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      service.setResourceJobsEnabled(true)
      let before = shared.store.document
      var vertical=addition();var style=vertical["text"] as! [String:Any];style["textOrientation"]="vertical";vertical["text"]=style
      let payload: [String: Any] = ["image": ["source": ["url": "https://example.test/base.psd"]], "edits": ["layers": [vertical]],
        "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]]
      let output = try await AutomationActionJobsTests().output(service, submit: "/v2/create-composite", payload: payload)
      let result = try PSDCodec.read(output.2)
      guard case .text(let text) = result.layers.last?.content else { return XCTFail("Published job flattened type") }
      XCTAssertEqual(text.text, "One\nTwo"); XCTAssertEqual(result.width, doc.width);XCTAssertEqual(text.typography?.writingOrientation,.vertical)
      XCTAssertEqual(shared.store.document, before)
    }
  }
  func testMalformedAndUnsupportedAdobeTypeAreAtomic() throws {
    let doc = try CraftDocument(width: 300, height: 200)
    for text: [String: Any] in [
      ["content": "A😀B", "characterStyles": [["apply": ["from": 1, "to": 1], "characterStyle": ["underline": true]]]],
      ["content": "test", "textOrientation": "diagonal"],
      ["content": "test", "characterStyles": [["characterStyle": ["font": ["postScriptName": "Missing_162"]]]]]
    ] {
      var edit = addition(); edit["text"] = text
      XCTAssertThrowsError(try request([edit]).applying(to: doc)); XCTAssertEqual(doc.layers.count, 1)
    }
    var edit = addition(); edit["text"] = ["content": "fallback", "characterStyles": [["characterStyle": ["font": ["postScriptName": "Missing_162"]]]]]
    XCTAssertNoThrow(try request([edit], fonts: ["missingFontStrategy": "use_default", "defaultFontPostScriptName": "HelveticaNeue"]).applying(to: doc))
  }
}
