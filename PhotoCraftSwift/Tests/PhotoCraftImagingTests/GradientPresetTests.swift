import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class GradientPresetTests: XCTestCase {
  private func oracle() throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "gradient-presets-oracle", withExtension: "grd", subdirectory: "Fixtures")))
  }
  private func root(_ data: Data) throws -> PSDDescriptor {
    try PSDDescriptor.readPrefix(Data(data.dropFirst(6))).descriptor
  }
  private func file(_ root: PSDDescriptor) throws -> Data {
    var output = PSDWriter()
    output.text("8BGR")
    output.n(5, 2)
    output.data.append(try root.encoded())
    return output.data
  }
  func testOriginalRustFileAndFreshNativeExportAreByteIdentical() throws {
    let bytes = try oracle()
    let library = try GRDCodec.read(bytes)
    XCTAssertEqual(library.presets.count, 2)
    XCTAssertEqual(library.presets[0].name, "Sunset ✓")
    let first = try XCTUnwrap(library.presets[0].gradient)
    XCTAssertEqual(first.method, .classic)
    XCTAssertEqual(first.smoothness, 1)
    XCTAssertEqual(first.colors[1], .init(0.25, .rgb(Pixel(1, 0.5, 0)), midpoint: 0.3))
    XCTAssertEqual(first.opacity[1], .init(1, 0.25, midpoint: 0.7))
    XCTAssertEqual(try GRDCodec.write(library), bytes)
    let rebuilt = try GRDCodec.write(GRDLibrary(library.presets.compactMap(\.gradient)))
    XCTAssertEqual(
      rebuilt, bytes,
      "Execute the native writer; do not qualify only the original-byte preservation shortcut")
    try rebuilt.write(to: URL(fileURLWithPath: "/private/tmp/photato-native-gradient-presets.grd"))
  }
  func testAllMethodsColorModelsSmoothnessAndStopPrecision() throws {
    // Wire identifiers checked against the independent ag-psd descriptor mapping.
    // These literals prevent a mutually consistent reader/writer from hiding a bad format ID.
    for (method, code) in [
      (GradientMethod.classic, "Gcls"), (.linear, "Lnr "), (.perceptual, "Perc"),
      (.stripes, "GIMs"),
    ] {
      let value = PSDValue.enumerated(PSDID("gradientInterpolationMethodType"), PSDID(code))
      XCTAssertEqual(PSDGradient.methodValue(method), value)
      XCTAssertEqual(try PSDGradient.method(value), method)
    }
    XCTAssertThrowsError(
      try PSDGradient.method(.enumerated(PSDID("gradientInterpolationMethodType"), PSDID("Clsc"))))
    XCTAssertThrowsError(
      try PSDGradient.method(.enumerated(PSDID("gradientInterpolationMethodType"), PSDID("Smoo"))))
    for method in GradientMethod.allCases {
      let definition = GradientDefinition(
        name: "Editable \(method)",
        colors: [
          .init(0, .foreground),
          .init(0.25, .hsb(hue: 210, saturation: 0.5, brightness: 0.75), midpoint: 0.3),
          .init(0.75, .gray(ink: 0.25), midpoint: 0.7), .init(1, .background),
        ], opacity: [.init(0, 0.2), .init(1, 0.9, midpoint: 0.4)], smoothness: 0.375, method: method
      )
      var library = GRDLibrary([definition])
      let encoded = try GRDCodec.write(library)
      if method != .classic {
        guard case .list(let items) = try root(encoded)["GrdL"],
          case .object(let wrapper) = items[0]
        else { return XCTFail("wrapper") }
        XCTAssertNotNil(wrapper["gradientsInterpolationMethod"])
        XCTAssertNil(wrapper["gs99"])
      }
      let read = try GRDCodec.read(encoded)
      XCTAssertEqual(read.presets[0].gradient, definition)
      library = read
      library.presets[0].gradient?.colors[1].position = 0.3
      library.presets[0].gradient?.colors[1].midpoint = 0.337
      let changed = try XCTUnwrap(GRDCodec.read(GRDCodec.write(library)).presets[0].gradient)
      XCTAssertEqual(changed.colors[1].position, Float((Float(0.3) * 4096).rounded()) / 4096)
      XCTAssertEqual(changed.colors[1].midpoint, 0.34)
      XCTAssertEqual(changed.smoothness, definition.smoothness)
      XCTAssertEqual(changed.method, method)
    }
  }
  func testFoldersAndOriginalMetadataSurviveAnEdit() throws {
    var library = GRDLibrary([.blackToWhite, .foregroundToBackground, .foregroundToTransparent])
    library.hierarchy = [
      .group("Photato", [.preset(0), .group("Nested ✓", [.preset(1)])]), .preset(2),
    ]
    let data = try GRDCodec.write(library)
    var decoded = try GRDCodec.read(data)
    XCTAssertEqual(decoded.hierarchy, library.hierarchy)
    XCTAssertEqual(try GRDCodec.write(decoded), data)
    decoded.presets[1].gradient?.name = "Changed"
    let changedBytes = try GRDCodec.write(decoded)
    XCTAssertNotEqual(changedBytes, data)
    let changed = try GRDCodec.read(changedBytes)
    XCTAssertEqual(changed.presets[1].name, "Changed")
    XCTAssertEqual(changed.hierarchy, library.hierarchy)
    // The folder extension survives exactly when only a preset is edited.
    let oldPrefix = try PSDDescriptor.readPrefix(Data(data.dropFirst(6))).consumed + 6
    let newPrefix = try PSDDescriptor.readPrefix(Data(changedBytes.dropFirst(6))).consumed + 6
    XCTAssertEqual(data.dropFirst(oldPrefix), changedBytes.dropFirst(newPrefix))
    decoded.hierarchy = [.group("Moved", [.preset(0), .preset(1), .preset(2)])]
    XCTAssertEqual(try GRDCodec.read(GRDCodec.write(decoded)).hierarchy, decoded.hierarchy)
    decoded.hierarchy = [.preset(0), .preset(0), .preset(2)]
    XCTAssertThrowsError(try GRDCodec.write(decoded))
    var truncated = data
    truncated.removeLast()
    XCTAssertThrowsError(try GRDCodec.read(truncated))
  }
  func testNoiseAndUnknownSemanticsArePreservedAndExplicitlyUnavailable() throws {
    var outer = try root(oracle())
    guard case .list(var list) = outer["GrdL"], case .object(var wrapper) = list[0],
      case .object(var gradient) = wrapper["Grad"]
    else { return XCTFail("fixture") }
    PSDGradient.set(&gradient, "GrdF", .enumerated(PSDID("GrdF"), PSDID("ClNs")))
    PSDGradient.set(&gradient, "RndS", .integer(1234))
    PSDGradient.set(&wrapper, "Grad", .object(gradient))
    list[0] = .object(wrapper)
    PSDGradient.set(&outer, "GrdL", .list(list))
    let bytes = try file(outer)
    var decoded = try GRDCodec.read(bytes)
    XCTAssertNil(decoded.presets[0].gradient)
    XCTAssertTrue(try XCTUnwrap(decoded.presets[0].unavailableReason).contains("Noise"))
    XCTAssertEqual(try GRDCodec.write(decoded), bytes)
    decoded.presets[1].gradient?.name = "Other preset changed"
    let changed = try root(GRDCodec.write(decoded))
    guard case .list(let changedList) = changed["GrdL"] else { return XCTFail("list") }
    XCTAssertEqual(
      changedList[0], list[0], "Editing another preset must not discard unknown noise parameters")
    PSDGradient.set(&gradient, "GrdF", .enumerated(PSDID("GrdF"), PSDID("CstS")))
    PSDGradient.set(&wrapper, "Grad", .object(gradient))
    list[0] = .object(wrapper)
    PSDGradient.set(&outer, "GrdL", .list(list))
    let unknown = try GRDCodec.read(file(outer))
    XCTAssertNil(unknown.presets[0].gradient)
    XCTAssertTrue(try XCTUnwrap(unknown.presets[0].unavailableReason).contains("unrepresented"))
  }
  func testMalformedCountsDuplicatesUnitsAndMutationsAreBounded() throws {
    let bytes = try oracle()
    for cut in 0..<bytes.count { XCTAssertThrowsError(try GRDCodec.read(bytes.prefix(cut))) }
    var outer = try root(bytes)
    outer.items.append(outer.items[0])
    XCTAssertThrowsError(try GRDCodec.read(file(outer)))
    outer = try root(bytes)
    guard case .list(var list) = outer["GrdL"], case .object(var wrapper) = list[0],
      case .object(var gradient) = wrapper["Grad"]
    else { return XCTFail("fixture") }
    PSDGradient.set(&gradient, "Intr", .number(.infinity))
    PSDGradient.set(&wrapper, "Grad", .object(gradient))
    list[0] = .object(wrapper)
    PSDGradient.set(&outer, "GrdL", .list(list))
    XCTAssertThrowsError(try GRDCodec.read(file(outer)))
    for i in stride(from: 0, to: bytes.count, by: 7) {
      var changed = bytes
      changed[i] ^= 0x5A
      do {
        let library = try GRDCodec.read(changed)
        for preset in library.presets { try preset.gradient?.validate() }
        XCTAssertEqual(try GRDCodec.write(library), changed)
      } catch {
        // Invalid or unsupported input must fail, never trap or silently drop a stop.
      }
    }
    XCTAssertThrowsError(try GRDCodec.write(GRDLibrary([])))
    XCTAssertThrowsError(
      try PSDGradient.number(.unit(Data("#Pxl".utf8), 1.0.bitPattern), unit: "#Prc"))
  }
}
