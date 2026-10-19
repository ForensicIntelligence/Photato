import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class AdobeActionsRequestTests: XCTestCase {
  private let select = """
    [{"_obj":"select","_target":[{"_ref":"$Chnl","_enum":"$Chnl","_value":"$Rd  "}]}]
    """
  private func fill(_ contents: String = "white", opacity: Double = 50) -> String {
    """
    [{"_obj":"fill","using":{"_enum":"fillContents","_value":"\(contents)"},"mode":{"_enum":"blendMode","_value":"normal"},"opacity":{"_unit":"percentUnit","_value":\(opacity)}}]
    """
  }
  private func body(actions: [String]? = nil, outputs: [[String: Any]]? = nil) -> [String: Any] {
    [
      "image": ["source": ["url": "https://input.example.test/original.psd?signature=example"]],
      "options": [
        "actions": (actions ?? [select, fill()]).map {
          ["source": ["content": $0, "contentType": "application/json"]]
        }
      ],
      "outputs": outputs ?? [
        ["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 3600]]
      ],
    ]
  }
  private func request(_ object: [String: Any]) throws -> AdobeActionsRequest {
    try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: object))
  }

  func testMultipleActionResourcesShareTargetsAndNativeHistory() throws {
    let request = try request(body(actions: [select, fill(), fill("black", opacity: 33)]))
    var document = try CraftDocument(width: 3, height: 1)
    var pixels = try Surface(width: 3, height: 1)
    for (x, a) in [Float(1), Float(128) / 255, 0].enumerated() {
      pixels.setPixel(x: x, y: 0, Pixel(Float(32) / 255, Float(96) / 255, Float(192) / 255, a))
    }
    document.layers[0].content = .raster(pixels)
    var expected = EditorSession(document: document)
    try expected.execute(
      .fillComponents(document.layers[0].id, .init(components: .red, value: 1, opacity: 0.5)))
    let afterWhite = expected.document
    try expected.execute(
      .fillComponents(document.layers[0].id, .init(components: .red, value: 0, opacity: 0.33)))
    var actual = try request.applying(to: document)
    XCTAssertEqual(actual.session.document, expected.document)
    XCTAssertEqual(actual.components, .red)
    XCTAssertEqual(actual.session.undoStack.map(\.label), ["Fill", "Fill"])
    actual.session.undo()
    XCTAssertEqual(actual.session.document, afterWhite)
    actual.session.undo()
    XCTAssertEqual(actual.session.document, document)
    actual.session.redo()
    XCTAssertEqual(actual.session.document, afterWhite)
  }

  func testHostedAndExternalDestinationsPreserveDeclaredOutputOrder() throws {
    let outputs: [[String: Any]] = [
      [
        "mediaType": "image/png", "destination": ["validityPeriod": 60],
        "cropMode": "document_bounds",
      ],
      [
        "mediaType": "image/vnd.adobe.photoshop",
        "destination": [
          "url": "https://output.example.test/result.psd?sig=example", "storageType": "azure",
        ], "shouldOverwrite": false,
      ],
      [
        "mediaType": "image/png", "destination": ["validityPeriod": 86400],
        "scriptOutputPattern": NSNull(),
      ],
    ]
    let parsed = try request(body(outputs: outputs))
    XCTAssertEqual(parsed.outputs.count, 3)
    XCTAssertEqual(parsed.outputs[0].mediaType, .png)
    XCTAssertEqual(parsed.outputs[0].destination, .hosted(validityPeriod: 60))
    XCTAssertEqual(parsed.outputs[1].mediaType, .psd)
    XCTAssertEqual(
      parsed.outputs[1].destination,
      .external(
        try XCTUnwrap(URL(string: "https://output.example.test/result.psd?sig=example")),
        storageType: "azure"))
    XCTAssertEqual(parsed.outputs[1].shouldOverwrite, false)
    XCTAssertEqual(parsed.outputs[2].destination, .hosted(validityPeriod: 86400))
    XCTAssertNil(parsed.outputs[2].shouldOverwrite)
  }

  func testInvalidBodiesMissingFieldsAndResourceTypesHaveAdobeErrorShape() throws {
    for data in [Data("{".utf8), Data("[]".utf8), Data("null".utf8), Data("{}".utf8)] {
      XCTAssertThrowsError(try AdobeActionsRequest(data: data)) { error in
        guard let error = error as? AdobeAPIError else { return XCTFail("Wrong error type") }
        XCTAssertEqual(error.status, 400)
        let response = error.response
        let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        XCTAssertNotNil(json?["error_code"])
        XCTAssertNotNil(json?["message"])
        XCTAssertNil(json?["error"], "Adobe and Photato errors must keep separate envelopes")
      }
    }
    for key in ["image", "options", "outputs"] {
      var value = body()
      value.removeValue(forKey: key)
      XCTAssertThrowsError(try request(value))
    }
    for url in [
      "", "file:///tmp/input.psd", "data:image/png;base64,abc",
      "https://name:secret@example.test/x", "https://example.test/x#fragment",
    ] {
      var value = body()
      value["image"] = ["source": ["url": url]]
      XCTAssertThrowsError(try request(value))
    }
  }

  func testUnknownAndUnimplementedOptionsCannotSilentlyChangeMeaning() throws {
    var values: [[String: Any]] = []
    var value = body()
    value["options"] = ["uxp": ["source": ["content": "script"]]]
    values.append(value)
    value = body()
    value["image"] = ["source": ["creativeCloudPath": "photo.psd"]]
    values.append(value)
    value = body()
    value["options"] = ["actions": [["source": ["url": "https://example.test/action.atn"]]]]
    values.append(value)
    value = body()
    value["outputs"] = [["mediaType": "image/png", "destination": ["embedded": "base64"]]]
    values.append(value)
    value = body()
    value["outputs"] = [
      ["mediaType": "image/png", "destination": ["validityPeriod": 3600], "width": 128]
    ]
    values.append(value)
    value = body()
    value["outputs"] = [
      [
        "mediaType": "image/png", "destination": ["validityPeriod": 3600],
        "cropMode": "trim_to_transparency",
      ]
    ]
    values.append(value)
    value = body()
    value["outputs"] = [["mediaType": "image/jpeg", "destination": ["validityPeriod": 3600]]]
    values.append(value)
    value = body()
    value["unknown"] = true
    values.append(value)
    for value in values {
      XCTAssertThrowsError(try request(value)) { error in
        XCTAssertEqual((error as? AdobeAPIError)?.status, 422)
      }
    }
    let unknown = "[{\"_obj\":\"arbitraryScript\"}]"
    XCTAssertThrowsError(try request(body(actions: [select, fill(), unknown])))
  }

  func testArrayBoundsOutputStorageAndInlineContentValidation() throws {
    XCTAssertThrowsError(try request(body(actions: [])))
    XCTAssertThrowsError(try request(body(actions: Array(repeating: select, count: 11))))
    XCTAssertEqual(
      try request(body(actions: Array(repeating: select, count: 10))).actions.count, 10)
    let output: [String: Any] = ["mediaType": "image/png", "destination": ["validityPeriod": 60]]
    XCTAssertEqual(
      try request(body(outputs: Array(repeating: output, count: 25))).outputs.count, 25)
    XCTAssertThrowsError(try request(body(outputs: Array(repeating: output, count: 26))))
    XCTAssertThrowsError(try request(body(outputs: [])))
    for period: Any in [59, 86_401, 60.5, true, "3600", NSNull()] {
      XCTAssertThrowsError(
        try request(
          body(outputs: [["mediaType": "image/png", "destination": ["validityPeriod": period]]])))
    }
    for destination: [String: Any] in [
      [:], ["url": "http://output.example.test/file.png"],
      ["url": "https://output.example.test/file.png", "validityPeriod": 3600],
      ["url": "https://output.example.test/file.png", "storageType": "s3"],
      ["validityPeriod": 3600, "storageType": "azure"],
    ] {
      XCTAssertThrowsError(
        try request(body(outputs: [["mediaType": "image/png", "destination": destination]])))
    }
    var value = body()
    value["options"] = ["actions": [["source": ["content": select]]]]
    XCTAssertThrowsError(try request(value))
    value["options"] = [
      "actions": [["source": ["content": select, "contentType": "text/javascript"]]]
    ]
    XCTAssertThrowsError(try request(value))
    XCTAssertThrowsError(
      try AdobeActionsRequest(
        data: Data(repeating: 32, count: AdobeActionsRequest.maximumBodyBytes + 1))
    ) { error in
      XCTAssertEqual((error as? AdobeAPIError)?.status, 413)
    }
  }

  func testFailedLaterResourceCannotMutateInputOrReturnPartialResult() throws {
    let parsed = try request(
      body(actions: [
        select, fill(),
        "[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]",
        fill(),
      ]))
    let document = try CraftDocument(width: 2, height: 2)
    let original = document
    XCTAssertThrowsError(try parsed.applying(to: document))
    XCTAssertEqual(document, original)
  }

  func testAdapterConstraintsStayBoundToPinnedAdobeSchema() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let raw =
      try JSONSerialization.jsonObject(
        with: Data(
          contentsOf:
            root.appendingPathComponent("docs/contracts/adobe-photoshop-v2.json")))
      as! [String: Any]
    let components = try XCTUnwrap(raw["components"] as? [String: Any])
    let schemas = try XCTUnwrap(components["schemas"] as? [String: Any])
    func schema(_ name: String) throws -> [String: Any] {
      try XCTUnwrap(schemas[name] as? [String: Any])
    }
    let required = try XCTUnwrap(schema("ActionsRequest")["required"] as? [String])
    XCTAssertEqual(Set(required), ["image", "options", "outputs"])
    let options = try XCTUnwrap(schema("ActionsOptions")["properties"] as? [String: Any])
    XCTAssertEqual((options["actions"] as? [String: Any])?["maxItems"] as? Int, 10)
    let requestProperties = try XCTUnwrap(schema("ActionsRequest")["properties"] as? [String: Any])
    XCTAssertEqual((requestProperties["outputs"] as? [String: Any])?["maxItems"] as? Int, 25)
    let inlineParts = try XCTUnwrap(
      schema("InlineContentResourceInput")["allOf"] as? [[String: Any]])
    let inlineProperties = try XCTUnwrap(inlineParts.last?["properties"] as? [String: Any])
    XCTAssertEqual(
      (inlineProperties["content"] as? [String: Any])?["maxLength"] as? Int,
      PhotoshopActionProgram.maximumCharacters)
    // These assertions pin only the selected constraints. They do not claim
    // complete schema conformance or behavior of the remote Adobe service.
  }
}
