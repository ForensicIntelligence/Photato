import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDLayerCompTests: XCTestCase {
  var fixtureURL: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/layer-comps/ag-psd-layer-comps.psd") }
  func document(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 6, height: 4, depth: depth)
    d.layers[0].content = .raster(try Surface(width: 6, height: 4, depth: depth, fill: Pixel(1, 0, 0)))
    var top = Layer(name: "Blue", content: .raster(try Surface(width: 2, height: 2, depth: depth, fill: Pixel(0, 0, 1)))); top.x = 1; top.y = 1; d.layers.append(top)
    let options = LayerCompOptions(visibility: true, position: true, appearance: false)
    try Command.layerComp(.capture(id: UUID(), name: "Left", comment: "First", options: options)).apply(to: &d)
    d.layers[1].x = 4
    try Command.layerComp(.capture(id: UUID(), name: "Right", comment: "Second", options: options)).apply(to: &d)
    d.layers[1].visible = false
    try Command.layerComp(.capture(id: UUID(), name: "Hidden", comment: "Third", options: options)).apply(to: &d)
    let first = d.layerComps!.comps[0].id; try Command.layerComp(.apply(first)).apply(to: &d)
    return d
  }
  func testIndependentSavedFileNamesFlagsCommentsInheritanceOffsetsAndPriorState() throws {
    let d = try PSDCodec.read(Data(contentsOf: fixtureURL)), library = try XCTUnwrap(d.layerComps)
    XCTAssertEqual(library.comps.count,5);XCTAssertTrue(d.layers.contains(where: \.isBackground));XCTAssertEqual(d.minimumArchiveVersion,83)
    XCTAssertEqual(library.comps.map(\.name), (1...5).map { "Layer Comp \($0)" })
    XCTAssertEqual(library.comps[0].options, .init(visibility: false, position: false, appearance: false))
    XCTAssertEqual(library.comps[3].comment, "some comments"); XCTAssertEqual(library.appliedID, PSDLayerComps.uuid(510999610))
    let fifth = try LayerCompIO.document(d, applying: library.comps[4].id)
    XCTAssertEqual(fifth.layers.map(\.visible), [true, false, false, true])
    XCTAssertEqual(fifth.layers[3].x, 7); XCTAssertEqual(fifth.layers[3].y, 4)
    XCTAssertEqual(library.lastDocumentState?.last?.x, 7); XCTAssertEqual(library.lastDocumentState?.last?.y, 4)
    let third = try LayerCompIO.document(d, applying: library.comps[2].id)
    XCTAssertEqual(third.layers.map(\.visible), [true, true, true, true])
    // Any comp can be applied independently, without visiting preceding comps.
    XCTAssertEqual(try LayerCompIO.document(third, applying: library.comps[4].id).layers, fifth.layers)
  }
  func testAllDepthPSDPSBVariationsRetainLibraryAndMatchEveryCompositeSample() throws {
    for depth in PixelDepth.allCases {
      let d = try document(depth), before = d
      for format in [PSDFileFormat.psd, .psb] {
        let bytes = try PSDCodec.writeRasterLayers(d, format: format), opened = try PSDCodec.read(bytes)
        XCTAssertEqual(opened.layerComps?.comps.map(\.name), ["Left", "Right", "Hidden"])
        for index in 0..<3 {
          let native = try LayerCompIO.document(d, applying: d.layerComps!.comps[index].id)
          let read = try LayerCompIO.document(opened, applying: opened.layerComps!.comps[index].id)
          XCTAssertEqual(try Renderer.composite(read).rgbaData(depth: .f32), try Renderer.composite(native).rgbaData(depth: .f32))
        }
        if let capture = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let dir = URL(fileURLWithPath: capture); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          try bytes.write(to: dir.appendingPathComponent("layer-comps-\(depth.rawValue).\(format == .psd ? "psd" : "psb")"))
        }
      }
      XCTAssertEqual(d, before)
    }
  }
  func testOtherLayerMetadataSurvivesAndClearRemovesBothCompResourcesAndLayerRecords() throws {
    var d = try PSDCodec.read(Data(contentsOf: fixtureURL)); let original = d
    let originalOther = try d.layers.map { try PSDLayerComps.metadata($0.sourceTags?["shmd"]).filter { $0.key != "cmls" }.map(\.encoded) }
    for format in [PSDFileFormat.psd, .psb] {
      let opened = try PSDCodec.read(PSDCodec.writeRasterLayers(d, format: format))
      XCTAssertEqual(try opened.layers.map { try PSDLayerComps.metadata($0.sourceTags?["shmd"]).filter { $0.key != "cmls" }.map(\.encoded) }, originalOther)
      XCTAssertEqual(opened.layerComps?.comps.map(\.id), original.layerComps?.comps.map(\.id))
      let originalReference = try PSDLayerComps.descriptor(original.layers[3])?["origFXRefPoint"]
      let retained = try XCTUnwrap(PSDLayerComps.descriptor(opened.layers[3]))
      XCTAssertEqual(retained["origFXRefPoint"], originalReference)
      guard case .list(let settings) = retained["layerSettings"] else { return XCTFail("Missing retained comp states") }
      XCTAssertEqual(settings.count, 6)
      for value in settings {
        guard case .object(let state) = value else { return XCTFail("Missing retained effect reference") }
        XCTAssertEqual(try PSDLayerComps.point(state["FXRefPoint"]), PathPoint(0, 0))
      }
    }
    try Command.layerComp(.clear).apply(to: &d)
    let opened = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertNil(opened.layerComps)
    XCTAssertFalse(try PSDImageResources.blocks(opened.sourceMetadata!["psdResources"]!).contains { $0.id == 1065 })
    XCTAssertTrue(try opened.layers.allSatisfy { try !PSDLayerComps.metadata($0.sourceTags?["shmd"]).contains { $0.key == "cmls" } })
    XCTAssertEqual(try opened.layers.map { try PSDLayerComps.metadata($0.sourceTags?["shmd"]).map(\.encoded) }, originalOther)
  }
  func testIntegerIdentityMappingAndVisibilityInheritanceDefaultMatchPublishedRepro() throws {
    for id in [Int32.min, -20, 1, 441670735, Int32.max] { XCTAssertEqual(PSDLayerComps.originalID(PSDLayerComps.uuid(id)), id) }
    var d = try document(), library = d.layerComps!; library.comps[0].layers[1].visible = true; library.comps[1].layers[1].visible = false; library.comps[2].layers[1].visible = false; d.layerComps = library
    let output = try PSDLayerComps.prepare(d), layer = d.layers[1], number = output.layerIDs[layer.id]!
    var entries = try PSDLayerComps.metadata(output.tags[layer.id]); let position = entries.firstIndex { $0.key == "cmls" }!
    var desc = try PSDDescriptor.read(entries[position].data); guard case .list(var states) = desc["layerSettings"] else { return XCTFail("Missing states") }
    for index in [0, 2] { guard case .object(var state) = states[index] else { return XCTFail("Missing record") }; state.items.removeAll { $0.key.text == "enab" }; states[index] = .object(state) }
    desc.items.removeAll { $0.key.text == "layerSettings" }; desc.items.append(.init("layerSettings", .list(states)))
    entries[position] = .init(signature: Data("8BIM".utf8), key: "cmls", flags: Data(repeating: 0, count: 4), data: try desc.encoded())
    var metadata = PSDWriter(); metadata.n(entries.count, 4); for item in entries { metadata.data.append(item.encoded) }
    d.sourceMetadata = ["psdResources": output.resource!]; d.layers[1].sourceTags = ["shmd": metadata.data]
    var id = PSDWriter(); id.n(Int(number), 4); d.layers[1].sourceTags?["lyid"] = id.data
    d.layers[1].visible = false; d.layerComps = nil; try PSDLayerComps.read(into: &d)
    XCTAssertEqual(d.layerComps?.comps.map { $0.layers.first(where: { $0.layerID == layer.id })?.visible }, [true, false, false])
  }
  func testUnsupportedAppearanceParentChildFractionalAndMissingStatesFailBeforeFileReplacement() throws {
    let source = try document(), dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
    let destination = dir.appendingPathComponent("Existing.psd"), existing = Data("Existing user file".utf8); try existing.write(to: destination)
    var variants: [CraftDocument] = []
    var d = source; d.layerComps?.comps[0].options.smartObjects = true; variants.append(d)
    d = source; let state = LayerCompLayerState(d.layers[1], options: .init()); d.layerComps?.comps[0].options.appearance = true
    let appearances = d.layers.map { LayerCompLayerState($0, options: .init()).appearance }
    for i in d.layers.indices { d.layerComps?.comps[0].layers[i].appearance = appearances[i] }
    d.layerComps?.comps[0].layers[1].appearance?.opacity = 0.25; XCTAssertNotNil(state.appearance); variants.append(d)
    d = source; d.layerComps?.comps[0].layers[1].translation = PathPoint(0.5, 0); variants.append(d)
    d = source; d.layers.removeLast(); d.activeLayerID = d.layers[0].id; variants.append(d)
    for variant in variants {
      let before = variant
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(variant, to: destination)); XCTAssertEqual(try Data(contentsOf: destination), existing); XCTAssertEqual(variant, before)
    }
  }
  func testEmbeddedSharedSourcePSDPSBRetainsIndependentSelectedCompsAndFreshCaches() throws {
    let helper = SmartObjectLayerCompIOTests(), source = try helper.source(); var d = try helper.parent(source)
    // Keep this fixture within the existing editable affine/mask/style subset.
    d.layers[0].mask = nil; d.layers[0].style = nil; d.layers[0].smartFilters = nil; d.layers[0].affine = nil
    let first = d.layers[0].id
    try Command.duplicateLayer(first).apply(to: &d); let second = d.activeLayerID!
    try SmartObjectLayerCompIO.selection(in: d, layerID: first, compID: source.layerComps!.comps[0].id).apply(to: &d)
    try SmartObjectLayerCompIO.selection(in: d, layerID: second, compID: source.layerComps!.comps[1].id).apply(to: &d)
    for format in [PSDFileFormat.psd, .psb] {
      let opened = try PSDCodec.read(PSDCodec.writeRasterLayers(d, format: format))
      XCTAssertEqual(opened.layers[0].smartObject?.sourceID, opened.layers[1].smartObject?.sourceID)
      XCTAssertEqual(opened.layers.compactMap { $0.smartObject?.layerComps?.entries.count }, [2, 2])
      XCTAssertNotEqual(opened.layers[0].smartObject?.layerComps?.selectedID, opened.layers[1].smartObject?.layerComps?.selectedID)
      XCTAssertEqual(try helper.cache(opened.layers[0]).pixel(x: 0, y: 0), Pixel(1, 0, 0)); XCTAssertEqual(try helper.cache(opened.layers[1]).pixel(x: 0, y: 0), Pixel(0, 0, 1))
    }
  }
  func testMalformedOrUnrepresentedMetadataRejectsWithoutPartiallyAssigningALibrary() throws {
    let source = try document(), output = try PSDLayerComps.prepare(source)
    let originalRoot = try PSDDescriptor.read(PSDImageResources.blocks(output.resource!)[0].data)
    guard case .list(let originalList) = originalRoot["list"] else { return XCTFail("Missing catalogue") }
    for mode in 0..<3 {
      var d = source, root = originalRoot, list = originalList
      d.layerComps = nil
      if mode == 0 {
        d.layers[1].sourceTags = ["shmd": Data([0, 0, 0, 255])]
      } else if mode == 1 {
        list.append(list[0])
      } else {
        guard case .object(var record) = list[0] else { return XCTFail("Missing comp") }
        record.items.removeAll { $0.key.text == "capturedInfo" }; record.items.append(.init("capturedInfo", .integer(8))); list[0] = .object(record)
      }
      root.items.removeAll { $0.key.text == "list" }; root.items.append(.init("list", .list(list)))
      d.sourceMetadata = ["psdResources": PSDImageResources.block(1065, data: try root.encoded())]
      let before = d; XCTAssertThrowsError(try PSDLayerComps.read(into: &d)); XCTAssertEqual(d, before)
    }
  }
  func testLegacyNativeOpaqueCompMetadataIsPreservedRatherThanMistakenForClear() throws {
    let original = try PSDCodec.read(Data(contentsOf: fixtureURL)); var legacy = original
    legacy.layerComps = nil // Before typed comp import, native files stored these records opaquely.
    let opened = try NativeArchive.decode(NativeArchive.encode(legacy))
    XCTAssertFalse(opened.clearedSourceLayerComps)
    let sourceBlock = try XCTUnwrap(PSDImageResources.blocks(original.sourceMetadata!["psdResources"]!).first { $0.id == 1065 })
    for format in [PSDFileFormat.psd, .psb] {
      let read = try PSDCodec.read(PSDCodec.writeRasterLayers(opened, format: format))
      let block = try XCTUnwrap(PSDImageResources.blocks(read.sourceMetadata!["psdResources"]!).first { $0.id == 1065 })
      XCTAssertEqual(block.raw, sourceBlock.raw); XCTAssertEqual(read.layerComps?.comps.map(\.id), original.layerComps?.comps.map(\.id))
      XCTAssertEqual(read.layers.map { $0.sourceTags?["shmd"] }, original.layers.map { $0.sourceTags?["shmd"] })
      XCTAssertEqual(read.layers.map{$0.sourceTags?["lyid"]},original.layers.map{$0.sourceTags?["lyid"]})
    }
    XCTAssertEqual(legacy.layerComps, nil)
  }
}
