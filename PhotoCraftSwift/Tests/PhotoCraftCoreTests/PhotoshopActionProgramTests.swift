import Foundation
import XCTest

@testable import PhotoCraftCore

final class PhotoshopActionProgramTests: XCTestCase {
  private func json(_ values: [[String: Any]]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
  }
  private func select(_ channel: String) -> [String: Any] {
    ["_obj": "select", "_target": [["_ref": "$Chnl", "_enum": "$Chnl", "_value": channel]]]
  }
  private func fill(_ value: String = "white", _ opacity: Double = 100) -> [String: Any] {
    [
      "_obj": "fill", "using": ["_enum": "fillContents", "_value": value],
      "opacity": ["_unit": "percentUnit", "_value": opacity],
      "mode": ["_enum": "blendMode", "_value": "normal"],
    ]
  }

  func testActionAdapterMatchesAllIndependentPhotoshopOutputBytes() throws {
    struct Fixture: Decodable {
      struct Item: Decodable {
        let width: Int, height: Int, offset: Int
        let value: Float, opacity: Float
      }
      let cases: [Item]
    }
    func resource(_ ext: String) throws -> Data {
      try Data(
        contentsOf: XCTUnwrap(
          Bundle.module.url(
            forResource: "photoshop-component-fill-rgb8", withExtension: ext,
            subdirectory: "Fixtures")))
    }
    let references = try JSONDecoder().decode(Fixture.self, from: resource("json"))
    let bytes = try resource("bin")
    var total = 0
    for reference in references.cases {
      var pixels = try Surface(width: reference.width, height: reference.height)
      for y in 0..<reference.height {
        for x in 0..<reference.width {
          let at = reference.offset + (y * reference.width + x) * 4
          pixels.setPixel(
            x: x, y: y,
            Pixel(
              Float(bytes[at]) / 255, Float(bytes[at + 1]) / 255,
              Float(bytes[at + 2]) / 255, Float(bytes[at + 3]) / 255))
        }
      }
      var document = try CraftDocument(width: reference.width, height: reference.height)
      document.layers[0].content = .raster(pixels)
      let program = try PhotoshopActionProgram(
        actionJSON: json([
          select("$Rd  "),
          fill(reference.value == 0 ? "black" : "white", Double(reference.opacity) * 100),
        ]))
      var result = try program.applying(to: document)
      guard case .raster(let actual) = result.session.document.layers[0].content else {
        return XCTFail()
      }
      let count = reference.width * reference.height * 4
      XCTAssertEqual(
        try actual.rgbaData(depth: .u8),
        bytes.subdata(
          in: reference.offset + count..<reference.offset + 2 * count))
      XCTAssertEqual(result.components, .red)
      XCTAssertEqual(result.session.undoStack.map(\.label), ["Fill"])
      result.session.undo()
      XCTAssertEqual(result.session.document, document)
      total += count
    }
    XCTAssertEqual(total, 122_880)
  }

  func testRecordedFactoryDescriptorShapesAndTerminologyAliases() throws {
    let raw: [[String: Any]] = [
      ["_obj": "$slct", "null": [["_ref": "$Chnl", "_enum": "$Chnl", "_value": "$Grn "]]],
      [
        "_obj": "$Fl  ", "$Usng": ["_enum": "$FlCn", "_value": "$Gry "],
        "$Opct": ["_unit": "$#Prc", "_value": 100], "$Md  ": ["_enum": "$BlnM", "_value": "$Nrml"],
      ],
      select("$Bl  "), fill("black", 50), select("$RGB "),
    ]
    let program = try PhotoshopActionProgram(actionJSON: json(raw))
    XCTAssertEqual(
      program.steps,
      [
        .selectComponents(.green), .fill(value: 0.5, opacity: 1),
        .selectComponents(.blue), .fill(value: 0, opacity: 0.5), .selectComponents(nil),
      ])
    var document = try CraftDocument(width: 1, height: 1)
    document.layers[0].content = .raster(
      try Surface(width: 1, height: 1, fill: Pixel(0.2, 0.3, 1, 0)))
    let result = try program.applying(to: document)
    XCTAssertNil(result.components)
    XCTAssertEqual(result.session.undoStack.count, 2)
    guard case .raster(let pixels) = result.session.document.layers[0].content else {
      return XCTFail()
    }
    XCTAssertEqual(
      pixels.pixel(x: 0, y: 0), Pixel(Float(51) / 255, Float(128) / 255, Float(127) / 255, 0))
  }

  func testCurrentDocumentReferenceAndNoninteractiveOptions() throws {
    var action = select("red")
    action["_target"] = [
      ["_ref": "channel", "_enum": "channel", "_value": "red"],
      ["_ref": "document", "_enum": "ordinal", "_value": "targetEnum"],
    ]
    action["_isCommand"] = true
    action["_options"] = ["dialogOptions": "dontDisplay", "suppressProgressBar": true]
    let program = try PhotoshopActionProgram(actionJSON: json([action]))
    let document = try CraftDocument(width: 1, height: 1)
    let result = try program.applying(to: document)
    XCTAssertEqual(result.components, .red)
    XCTAssertEqual(result.session.document, document)
    XCTAssertTrue(result.session.undoStack.isEmpty)
  }

  func testUnsupportedActionsAndUnknownParametersAreNeverSilentlySkipped() throws {
    var cases: [[String: Any]] = [["_obj": "unknown"], ["_obj": "select"]]
    var action = fill()
    action["unrecognized"] = 1
    cases.append(action)
    action = fill()
    action["$Opct"] = ["_unit": "$#Prc", "_value": 50]
    cases.append(action)
    action = fill()
    action["mode"] = ["_enum": "blendMode", "_value": "multiply"]
    cases.append(action)
    action = fill()
    action["using"] = ["_enum": "fillContents", "_value": "foregroundColor"]
    cases.append(action)
    action = fill()
    action["preserveTransparency"] = true
    cases.append(action)
    action = fill()
    action["_options"] = ["dialogOptions": "display"]
    cases.append(action)
    action = select("mask")
    cases.append(action)
    action = select("red")
    action["makeVisible"] = false
    cases.append(action)
    action = select("red")
    action["null"] = action["_target"]
    cases.append(action)
    for action in cases {
      XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON: json([select("red"), action])))
    }
  }

  func testOpacityTypesEnumerationsAndSizeBudgetsRejectMalformedInput() throws {
    for value: Any in [-0.01, 100.01, true, "50", NSNull()] {
      var action = fill()
      action["opacity"] = ["_unit": "percentUnit", "_value": value]
      XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON: json([action])))
    }
    for raw in ["{}", "null", "[]", "[1]", "[true]", "[{}]", "[", "[NaN]"] {
      XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON: raw))
    }
    XCTAssertThrowsError(
      try PhotoshopActionProgram(
        actionJSON:
          String(repeating: "[", count: 65) + String(repeating: "]", count: 65)))
    XCTAssertThrowsError(
      try PhotoshopActionProgram(
        actionJSON:
          "[\"" + String(repeating: "e\u{0301}", count: 26_000) + "\"]"))
    XCTAssertThrowsError(
      try PhotoshopActionProgram(
        actionJSON:
          json(Array(repeating: ["_obj": "x"], count: 1_025))))
  }

  func testLaterExecutionFailureLeavesInputUnchangedAndContextsExplicit() throws {
    let document = try CraftDocument(width: 2, height: 2)
    let before = document
    let program = try PhotoshopActionProgram(
      actionJSON: json([
        select("red"), fill(), select("RGB"), fill(),
      ]))
    XCTAssertThrowsError(try program.applying(to: document))
    XCTAssertEqual(document, before)
    for depth in [PixelDepth.u16, .f32] {
      let highDepth = try CraftDocument(width: 2, height: 2, depth: depth)
      let composite = try PhotoshopActionProgram(actionJSON: json([select("RGB")]))
      XCTAssertEqual(try composite.applying(to: highDepth).session.document, highDepth)
      XCTAssertThrowsError(try composite.applying(to: highDepth, components: .red))
      XCTAssertThrowsError(
        try PhotoshopActionProgram(actionJSON: json([select("red")])).applying(to: highDepth))
      XCTAssertThrowsError(
        try PhotoshopActionProgram(actionJSON: json([select("blue"), fill()]))
          .applying(to: CraftDocument(width: 2, height: 2, depth: depth)))
    }
    XCTAssertThrowsError(try program.applying(to: document, components: []))
    let direct = try PhotoshopActionProgram(actionJSON: json([fill()]))
    XCTAssertThrowsError(try direct.applying(to: document))
    XCTAssertEqual(try direct.applying(to: document, components: .red).components, .red)
  }

  func testCancelledProgramDoesNotExecute() async throws {
    let document = try CraftDocument(width: 2, height: 2)
    let program = try PhotoshopActionProgram(actionJSON: json([select("red"), fill()]))
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try program.applying(to: document)
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled program completed")
    } catch is CancellationError {}
  }
}
