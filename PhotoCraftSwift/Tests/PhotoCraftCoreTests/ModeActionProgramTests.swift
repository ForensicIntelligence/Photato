import CoreGraphics
import XCTest
@testable import PhotoCraftCore

final class ModeActionProgramTests: XCTestCase {
  func program(_ values: [[String: Any]]) throws -> PhotoshopActionProgram {
    try .init(actionJSON: String(decoding: JSONSerialization.data(withJSONObject: values), as: UTF8.self))
  }
  func select(_ name: String) -> [String: Any] {
    ["_obj": "select", "_target": [["_ref": "channel", "_enum": "channel", "_value": name]]]
  }
  func fill(_ color: String = "black", _ opacity: Double = 100) -> [String: Any] {
    ["_obj": "fill", "using": ["_enum": "fillContents", "_value": color],
      "mode": ["_enum": "blendMode", "_value": "normal"], "opacity": ["_unit": "percentUnit", "_value": opacity]]
  }
  var names: [DocumentColorMode: [String]] { [.rgb: ["red", "green", "blue"], .grayscale: ["gray"],
    .cmyk: ["cyan", "magenta", "yellow", "black"], .lab: ["lightness", "a", "b"]] }

  func testEveryModeComponentDepthMatchesNativeEditingAndPreservesOtherPlanes() throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let source = try ModeComponentEditingTests().fixture(mode, depth)
      let id = try XCTUnwrap(source.activeLayerID), original = try XCTUnwrap(source.layers[0].nativeMode)
      for (component, name) in names[mode]!.enumerated() {
        var result = try program([select(name), fill()]).applying(to: source)
        let actual = try XCTUnwrap(result.session.document.layers[0].nativeMode)
        for c in original.planes.indices where c != component { XCTAssertEqual(actual.planes[c], original.planes[c]) }
        for i in 0..<12 { XCTAssertEqual(actual.value(component: component, index: i), mode == .cmyk ? 1 : 0) }
        var expected = EditorSession(document: source)
        try expected.execute(.modeComponents(.init(layerID: id, components: [component], operation: .fill(0, 1))))
        XCTAssertEqual(result.session.document, expected.document)
        XCTAssertEqual(result.session.undoStack.count, 1)
        try result.session.undo(); XCTAssertEqual(result.session.document, source)
        try result.session.redo(); XCTAssertEqual(result.session.document, expected.document)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(expected.document)), expected.document)
      }
    } }
  }
  func testMovedSelectionOpacityAndFilterUseNativeChannelCoordinates() throws {
    var source = try ModeComponentEditingTests().fixture(.cmyk, .u16)
    source.layers[0].x = 1; source.layers[0].y = 1
    source.selection = IntRect(x: 2, y: 2, width: 1, height: 1)
    let before = try XCTUnwrap(source.layers[0].nativeMode), id = try XCTUnwrap(source.activeLayerID)
    let result = try program([select("black"), fill("white", 50)]).applying(to: source)
    let after = try XCTUnwrap(result.session.document.layers[0].nativeMode)
    for c in before.planes.indices { for i in 0..<12 {
      let expected = c == 3 && i == 5 ? PixelDepth.u16.quantize(before.value(component: c, index: i) / 2) : before.value(component: c, index: i)
      XCTAssertEqual(after.value(component: c, index: i), expected, accuracy: 1.0 / 65535)
    } }
    let filtered = try program([select("black"), ["_obj": "average"]]).applying(to: source)
    var expected = EditorSession(document: source)
    try expected.execute(.modeComponents(.init(layerID: id, components: [3], operation: .filter(.init(.average)))))
    XCTAssertEqual(filtered.session.document, expected.document)
    let inverted = try program([select("black"), ["_obj": "invert"]]).applying(to: source)
    expected = EditorSession(document: source)
    try expected.execute(.modeComponents(.init(layerID: id, components: [3], operation: .invert)))
    XCTAssertEqual(inverted.session.document, expected.document)
  }
  func testComponentContextSurvivesResourcesAndResetsOnLayerOrComposite() throws {
    let source = try ModeComponentEditingTests().fixture(.lab, .u16)
    let selected = try program([select("a")]).applying(to: source)
    XCTAssertNil(selected.components); XCTAssertEqual(selected.modeComponents?.components, [1])
    let applied = try program([fill()]).applying(to: selected.session, modeComponents: selected.modeComponents)
    XCTAssertEqual(applied.modeComponents?.mode, .lab)
    let composite = try program([select("lab")]).applying(to: applied.session, modeComponents: applied.modeComponents)
    XCTAssertNil(composite.modeComponents); XCTAssertNil(composite.components)
    XCTAssertThrowsError(try program([fill()]).applying(to: composite.session))
    let layer = ["_obj": "select", "_target": [["_ref": "layer", "_name": source.layers[0].name]]] as [String: Any]
    let reset = try program([layer]).applying(to: selected.session, modeComponents: selected.modeComponents)
    XCTAssertNil(reset.modeComponents)
    for descriptor in [select("RGB"), select("cyan"), ["_obj": "$MrgV"], ["_obj": "vibrance", "vibrance": 5, "saturation": 0]] {
      XCTAssertThrowsError(try program([descriptor]).applying(to: selected.session, modeComponents: selected.modeComponents))
    }
  }
  func testConversionDescriptorsPreserveHistoryProfilesAndClearTargets() throws {
    let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.adobeRGB1998)?.copyICCData() as Data?)
    let source = try CraftDocument(width: 3, height: 2, depth: .u16).convertingMode(.init(mode: .rgb, depth: .u16, profile: profile))
    let depth = try program([["_obj": "$CnvM", "$Dpth": 8]]).applying(to: source, components: .red)
    XCTAssertEqual(depth.session.document.depth, .u8); XCTAssertEqual(depth.session.document.modeDescriptor?.profile, profile)
    XCTAssertNil(depth.components)
    let floating = try program([["_obj": "convertMode", "depth": 32]]).applying(to: source)
    let linear = try XCTUnwrap(floating.session.document.modeDescriptor?.profile)
    try NativeModeProfile.validate(linear, mode: .rgb, depth: .f32)
    XCTAssertNotEqual(linear, try NativeModeProfile.standard(.rgb, depth: .f32))
    let forms: [(String, DocumentColorMode)] = [("$RGBM", .rgb), ("$Grys", .grayscale), ("$CMYM", .cmyk), ("$LbCM", .lab)]
    for (value, mode) in forms {
      var result = try program([["_obj": "$CnvM", "$T   ": ["_class": value]]]).applying(to: source)
      XCTAssertEqual(result.session.document.colorMode, mode); XCTAssertEqual(result.session.document.depth, .u16)
      let after = result.session.document
      if after != source { try result.session.undo(); XCTAssertEqual(result.session.document, source); try result.session.redo(); XCTAssertEqual(result.session.document, after) }
      let named = try program([["_obj": "convertMode", "to": ["_enum": "colorSpaceMode", "_value": mode.rawValue]]]).applying(to: source)
      XCTAssertEqual(named.session.document, after)
    }
  }
  func testCustomRGB8ComponentsAndMultiLayerSelectionRemainAuthoritative() throws {
    let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.adobeRGB1998)?.copyICCData() as Data?)
    let source = try ModeComponentEditingTests().fixture(.rgb, .u8).convertingMode(.init(mode: .rgb, depth: .u8, profile: profile))
    let before = try XCTUnwrap(source.layers[0].nativeMode)
    let result = try program([select("green"), fill()]).applying(to: source)
    let after = try XCTUnwrap(result.session.document.layers[0].nativeMode)
    for c in [0, 2, 3] { XCTAssertEqual(after.planes[c], before.planes[c]) }
    XCTAssertEqual(after.planes[1], Data(repeating: 0, count: 12))
    var layers = source, second = source.layers[0]; second.id = UUID(); second.name = "Second"
    layers.layers.append(second)
    let all: [String: Any] = ["_obj": "selectAllLayers", "_target": [["_ref": "layer", "_enum": "ordinal", "_value": "targetEnum"]]]
    let converted = try program([all, ["_obj": "convertMode", "to": ["_class": "$Grys"]]]).applying(to: layers)
    XCTAssertEqual(converted.selectedLayerIDs, Set(layers.layers.map(\.id)))
    XCTAssertEqual(converted.session.document.layers.count, 2)
  }
  func testEncodedFloatingCompositeRetainsItsWorkingProfileWithoutFalseHDRInterpretation() throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.adobeRGB1998))
    let profile = try XCTUnwrap(space.copyICCData() as Data?)
    var surface = try Surface(width: 1, height: 1, depth: .f32, colorEncoding: .sRGB)
    let pixel = Pixel(0.314159, 0.512345, 0.798765, 0.625)
    surface.setPixel(x: 0, y: 0, pixel)
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] {
      let converted = try NativeModeRaster.converting(surface, to: mode, depth: .u16, sourceProfile: profile)
      let target = try XCTUnwrap(mode == .lab ? CGColorSpace(name: CGColorSpace.genericLab) : CGColorSpace(iccData: converted.profile as CFData))
      let input = try XCTUnwrap(CGColor(colorSpace: space, components: [CGFloat(pixel.r), CGFloat(pixel.g), CGFloat(pixel.b), CGFloat(pixel.a)]))
      let reference = try XCTUnwrap(input.converted(to: target, intent: .relativeColorimetric, options: nil)?.components)
      for c in 0..<mode.componentCount {
        var value = Float(reference[c]); if mode == .lab { value = c == 0 ? value / 100 : (value + 128) / 255 }
        XCTAssertEqual(converted.value(component: c, index: 0), PixelDepth.u16.quantize(value))
      }
      XCTAssertEqual(converted.value(component: mode.componentCount, index: 0), PixelDepth.u16.quantize(pixel.a))
    }
  }
  func testConversionSchemaAndGrayAliasAreDiscoverableAndExecutable() throws {
    let schema = PhotoshopActionProgram.modeConversionParameterSchema
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: PhotoshopActionProgram.modeCapabilities))
    let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
    XCTAssertEqual(Set(properties.keys), ["to", "depth", "merge"])
    let source = try ModeComponentEditingTests().fixture(.grayscale, .u8)
    XCTAssertEqual(try program([select("$Gry "), fill()]).applying(to: source).session.document,
      try program([select("gray"), fill()]).applying(to: source).session.document)
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let url = URL(fileURLWithPath: folder); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys]).write(to: url.appendingPathComponent("mode-conversion-parameters-schema.json"))
    }
  }
  func testInvalidModesTargetsLaterFailureAndHDRReductionRemainAtomic() throws {
    for raw in [
      ["_obj": "convertMode"], ["_obj": "convertMode", "depth": true], ["_obj": "convertMode", "depth": 12],
      ["_obj": "convertMode", "depth": 16, "$Dpth": 16], ["_obj": "convertMode", "depth": 16, "merge": 1],
      ["_obj": "convertMode", "to": ["_class": "$IndC"]], ["_obj": "convertMode", "to": ["_enum": "wrong", "_value": "rgb"]],
    ] as [[String: Any]] { XCTAssertThrowsError(try program([raw])) }
    let source = try ModeComponentEditingTests().fixture(.cmyk, .u16), before = source
    for mode in [DocumentColorMode.rgb, .lab] {
      XCTAssertThrowsError(try program([fill()]).applying(to: source, modeComponents: .init(mode: mode, components: [0])))
    }
    XCTAssertThrowsError(try program([fill()]).applying(to: source, modeComponents: .init(mode: .cmyk, components: [4])))
    XCTAssertThrowsError(try program([select("cyan"), fill(), select("lightness")]).applying(to: source))
    XCTAssertEqual(source, before)
    let hdr = try CraftDocument(width: 3, height: 2, depth: .f32)
    XCTAssertThrowsError(try program([["_obj": "convertMode", "depth": 16]]).applying(to: hdr))
    XCTAssertThrowsError(try program([["_obj": "convertMode", "to": ["_class": "$CMYM"]]]).applying(to: hdr))
  }
}
