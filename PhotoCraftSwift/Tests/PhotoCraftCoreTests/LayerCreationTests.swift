import PhotoCraftCore
import XCTest

final class LayerCreationTests: XCTestCase {
  func testConfiguredCreationPreservesSelectionAndIsOneUndoAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 7, height: 5, depth: depth)
      document.selection = .init(x: 1, y: 1, width: 2, height: 2)
      var options = NewPixelLayerOptions(name: "Dodge & Burn")
      options.mode = .softLight
      options.opacity = 0.37
      options.color = .seafoam
      options.clipped = true
      options.neutralFill = true
      var session = EditorSession(document: document)
      try session.execute(.newPixelLayer(options))
      let created = session.document
      let layer = try XCTUnwrap(created.layers.last)
      XCTAssertEqual(layer.name, "Dodge & Burn")
      XCTAssertEqual(layer.opacity, 0.37)
      XCTAssertEqual(layer.colorLabel, .seafoam)
      XCTAssertEqual(layer.blendMode, .softLight)
      XCTAssertTrue(layer.isClipped)
      XCTAssertEqual(created.activeLayerID, layer.id)
      XCTAssertEqual(created.selection, document.selection)
      guard case .raster(let surface) = layer.content else { return XCTFail("Expected raster") }
      let expected: Float =
        depth == .u8 ? 128.0 / 255 : depth == .u16 ? 32768.0 / 65535 : SRGBTransfer.encoded(0.5)
      XCTAssertEqual(surface.pixel(x: 0, y: 0), Pixel(expected, expected, expected))
      XCTAssertEqual(surface.pixel(x: 6, y: 4), surface.pixel(x: 0, y: 0))
      XCTAssertEqual(surface.tileCount, 0)
      XCTAssertEqual(session.undoStack.count, 1)
      XCTAssertEqual(session.undoStack.last?.label, "New Layer")
      session.undo()
      XCTAssertEqual(session.document, document)
      session.redo()
      XCTAssertEqual(session.document, created)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(created)), created)
    }
  }

  func testBelowGroupInsertsBeforeWholeSubtreeAndAboveInsertsInside() throws {
    var document = try CraftDocument(width: 2, height: 2)
    let folder = Layer(name: "Folder", content: .group(.init()))
    var child = Layer(name: "Child", content: .fill(.white))
    child.parentID = folder.id
    document.layers += [child, folder]
    document.activeLayerID = folder.id
    var below = EditorSession(document: document)
    try below.execute(.newPixelLayer(.init(name: "Below"), below: true))
    XCTAssertEqual(below.document.layers.map(\.name), ["Background", "Below", "Child", "Folder"])
    XCTAssertNil(below.document.layers[1].parentID)
    var inside = EditorSession(document: document)
    try inside.execute(.newPixelLayer(.init(name: "Inside")))
    XCTAssertEqual(inside.document.layers.map(\.name), ["Background", "Child", "Inside", "Folder"])
    XCTAssertEqual(inside.document.layers[2].parentID, folder.id)
    inside.selectLayer(child.id)
    try inside.execute(.newPixelLayer(.init(name: "Before Child"), below: true))
    XCTAssertEqual(
      inside.document.layers.map(\.name),
      ["Background", "Before Child", "Child", "Inside", "Folder"])
    XCTAssertEqual(inside.document.layers[1].parentID, folder.id)
  }

  func testInvalidOptionsClippingLockedParentAndLimitNeverMutateSession() throws {
    let document = try CraftDocument(width: 2, height: 2)
    for kind in 0..<6 {
      var session = EditorSession(document: document)
      var options = NewPixelLayerOptions(name: "Test")
      switch kind {
      case 0: options.name = "  "
      case 1: options.opacity = .nan
      case 2: options.opacity = 1.01
      case 3: options.opacity = -0.01
      case 4: options.neutralFill = true
      default: options.clipped = true
      }
      XCTAssertThrowsError(try session.execute(.newPixelLayer(options, below: true)))
      XCTAssertEqual(session.document, document)
      XCTAssertTrue(session.undoStack.isEmpty)
    }
    var locked = document
    var folder = Layer(name: "Locked", content: .group(.init()))
    folder.locked = true
    locked.layers.append(folder)
    locked.activeLayerID = folder.id
    var session = EditorSession(document: locked)
    XCTAssertThrowsError(try session.execute(.newPixelLayer(.init(name: "Inside"))))
    XCTAssertEqual(session.document, locked)
    try session.execute(.newPixelLayer(.init(name: "Outside"), below: true))
    var full = document
    for i in 1..<512 { full.layers.append(Layer(name: "\(i)", content: .fill(.white))) }
    session = EditorSession(document: full)
    XCTAssertThrowsError(try session.execute(.newPixelLayer(.init(name: "Over limit"))))
    XCTAssertEqual(session.document, full)
  }

  func testNeutralModeFamiliesAndTransparentDefault() throws {
    let white: Set<BlendMode> = [
      .darken, .multiply, .colorBurn, .linearBurn, .darkerColor, .divide,
    ]
    let gray: Set<BlendMode> = [
      .overlay, .softLight, .hardLight, .vividLight, .linearLight, .pinLight,
    ]
    let black: Set<BlendMode> = [
      .lighten, .screen, .colorDodge, .linearDodge, .lighterColor, .difference, .exclusion,
      .subtract,
    ]
    for mode in BlendMode.allCases {
      let expected: Float? =
        white.contains(mode) ? 1 : gray.contains(mode) ? 0.5 : black.contains(mode) ? 0 : nil
      XCTAssertEqual(mode.neutralFillValue, expected, mode.rawValue)
      if let value = expected {
        let background = SIMD3<Float>(0.1, 0.4, 0.9)
        let result = mode.rgb(background, .init(repeating: value))
        for i in 0..<3 { XCTAssertEqual(result[i], background[i], accuracy: 0.000001) }
      }
    }
    let document = try CraftDocument(width: 2, height: 2)
    let layer = try NewPixelLayerOptions(name: "Empty").layer(in: document)
    guard case .raster(let surface) = layer.content else { return XCTFail("Expected raster") }
    XCTAssertEqual(surface.defaultPixel, .clear)
    XCTAssertNil(layer.sourceTags)
  }

  func testColorLabelByteCodesPreserveUnrelatedAndFutureMetadata() throws {
    var layer = Layer(name: "Labels", content: .fill(.white))
    XCTAssertEqual(layer.colorLabel, LayerColorLabel.none)
    for code in UInt16(0)...11 {
      layer.sourceTags = ["test": Data([4, 5]), "lclr": Data([0, UInt8(code), 1, 2, 3, 4, 5, 6])]
      XCTAssertEqual(layer.colorLabel?.rawValue, code)
      layer.colorLabel = .red
      XCTAssertEqual(layer.sourceTags?["lclr"], Data([0, 1, 1, 2, 3, 4, 5, 6]))
      XCTAssertEqual(layer.sourceTags?["test"], Data([4, 5]))
    }
    for data in [Data([0, 99, 0, 0, 0, 0, 0, 0]), Data([0])] {
      layer.sourceTags = ["lclr": data]
      XCTAssertNil(layer.colorLabel)
      var document = try CraftDocument(width: 2, height: 2)
      document.layers = [layer]
      document.activeLayerID = layer.id
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)), document)
    }
  }

  func testSuggestedNameAvoidsExistingNamesAndStartsAtOne() throws {
    var document = try CraftDocument(width: 2, height: 2)
    XCTAssertEqual(document.suggestedPixelLayerName, "Layer 1")
    document.layers += ["Layer 1", "Layer 3", "Other"].map {
      Layer(name: $0, content: .fill(.white))
    }
    XCTAssertEqual(document.suggestedPixelLayerName, "Layer 2")
  }
}
