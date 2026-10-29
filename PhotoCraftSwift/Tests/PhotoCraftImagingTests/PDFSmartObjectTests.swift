import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PDFSmartObjectTests: XCTestCase {
  func data(_ name: String = "owned-boxes") throws -> Data {
    try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/pdf/"+name+".pdf"))
  }
  func settings(_ crop: PDFImportSettings.Crop = .media, page: Int = 1) -> PDFImportSettings {
    var value = PDFImportSettings();value.resolution = 72;value.crop = crop
    value.pages = [page];value.antialias = false;return value
  }
  func document(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:432,height:324,depth:depth)
    var layer = try PDFSmartObjectIO.placed(data(),fileName:"Owned.pdf",in:d,settings:settings(),fit:false)
    layer.x = 0;layer.y = 0;d.layers = [layer];d.activeLayerID = layer.id
    return d
  }
  func testPDFTextInPNGMetadataDoesNotChangeSmartObjectSourceType() throws {
    let source = try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/pdf/owned-pdf-text.png"))
    XCTAssertNotNil(source.prefix(1024).range(of:Data("%PDF-".utf8)))
    XCTAssertFalse(PDFImport.recognizes(source))
    let parent = try CraftDocument(width:8,height:8,depth:.u8)
    let layer = try SmartObjectIO.placed(data:source,fileName:"Metadata.png",in:parent,fit:false)
    XCTAssertEqual(layer.smartObject?.mediaType,"image/png")
    XCTAssertEqual(layer.smartObject?.data,source)
    XCTAssertNil(layer.smartObject?.pdfSource)
    guard case .raster(let pixels) = layer.content else {return XCTFail("PNG content must be raster")}
    XCTAssertEqual(pixels.width,2);XCTAssertEqual(pixels.height,2)
    let original = try data()
    XCTAssertTrue(PDFImport.recognizes(original))
    XCTAssertTrue(PDFImport.recognizes(Data("\n \n".utf8)+original))
  }
  func testOriginalSourceSelectionRevisionAndBothNativeArchives() throws {
    for crop in PDFImportSettings.Crop.allCases {
      var d = try document()
      let layer = try PDFSmartObjectIO.placed(data(),fileName:"Owned.pdf",in:d,settings:settings(crop),fit:false)
      d.layers = [layer];d.activeLayerID = layer.id
      XCTAssertEqual(d.minimumArchiveVersion,62)
      XCTAssertEqual(layer.smartObject?.data,try data())
      XCTAssertEqual(layer.smartObject?.pdfSource?.crop.rawValue,crop.rawValue)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      var changed = try XCTUnwrap(layer.smartObject)
      changed.pdfSource?.antialias.toggle()
      XCTAssertNotEqual(changed.revision,layer.smartObject?.revision)
      XCTAssertFalse(changed.sharesSource(with:try XCTUnwrap(layer.smartObject)))
    }
    let d = try document();var bytes = try NativeArchive.encodeChunked(d)
    bytes[8] = 61
    XCTAssertThrowsError(try NativeArchive.decode(bytes))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
  }
  func testEnlargementRendersVectorsAtTargetResolutionWithoutReplacingSource() throws {
    for depth in PixelDepth.allCases {
      let d = try document(depth),source = d.layers[0]
      var session = EditorSession(document:d)
      try session.execute(.transform(source.id,.scale(3,3),.bicubic))
      let enlarged = session.document
      XCTAssertEqual(enlarged.layers[0].content,source.content)
      XCTAssertEqual(enlarged.layers[0].smartObject,source.smartObject)
      var direct = settings();direct.resolution = 216;direct.depth = depth
      let reference = try PDFImport.pages(data(),name:"Direct",settings:direct)[0]
      XCTAssertEqual(try Renderer.composite(enlarged).rgbaData(depth:depth),
        try Renderer.composite(reference).rgbaData(depth:depth))
      let reopened = try NativeArchive.decode(NativeArchive.encodeChunked(enlarged))
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth:depth),
        try Renderer.composite(reference).rgbaData(depth:depth))
      if depth == .u8,let path = ProcessInfo.processInfo.environment["PHOTATO_PDF_SMART_OUTPUT"] {
        let directory = URL(fileURLWithPath:path)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try RasterIO.encoded(enlarged).write(to:directory.appendingPathComponent("vector-3x.png"))
      }
      try session.undo();XCTAssertEqual(session.document,d)
      try session.redo();XCTAssertEqual(session.document,enlarged)
      try session.execute(.transform(source.id,.scale(1.0/30,1.0/30),.bicubic))
      try session.execute(.transform(source.id,.scale(30,30),.bicubic))
      XCTAssertEqual(session.document.layers[0].smartObject,source.smartObject)
      XCTAssertEqual(try Renderer.composite(session.document).rgbaData(depth:depth),
        try Renderer.composite(reference).rgbaData(depth:depth))
    }
  }
  func testRenderProjectionPreservesMaskCoordinatesAndOriginalLayer() throws {
    var d = try document();var layer = d.layers[0]
    layer.affine = .scale(3,2);layer.x = 4;layer.y = -2
    layer.mask = try Surface(width:144,height:108,fill:.white)
    var properties = MaskProperties();properties.transform = .translation(7,9);properties.linked = false
    layer.maskProperties = properties;d.layers = [layer]
    let result = try PDFSmartObjectIO.renderedLayer(layer,in:d)
    XCTAssertEqual(result.maskCoordinateTransform,layer.maskCoordinateTransform)
    XCTAssertEqual(try result.coordinateTransform.bounds(width:432,height:324),
      try layer.coordinateTransform.bounds(width:144,height:108))
    XCTAssertNil(result.smartObject);XCTAssertNotNil(d.layers[0].smartObject)
    XCTAssertEqual(d.layers[0],layer)
  }
  func testFilteredPDFAndRasterizeUseTheEnlargedSourceAndUndo() throws {
    for filtered in [false,true] {
      var d = try document();let id = d.layers[0].id
      try Command.transform(id,.scale(3,3),.bicubic).apply(to:&d)
      if filtered {try Command.applyFilter(id,RasterFilter(.highPass)).apply(to:&d)}
      let output = try Renderer.composite(d)
      // Build the reference from a direct full-resolution PDF render, then
      // apply the same document-space filter to an ordinary pixel layer.
      var options = settings();options.resolution = 216
      var reference = try PDFImport.pages(data(),name:"Reference",settings:options)[0]
      if filtered {try Command.applyFilter(reference.layers[0].id,RasterFilter(.highPass)).apply(to:&reference)}
      XCTAssertEqual(try output.rgbaData(depth:.u8),try Renderer.composite(reference).rgbaData(depth:.u8))
      var session = EditorSession(document:d)
      try session.execute(SmartObjectIO.rasterizationCommand(d.layers[0],in:d))
      XCTAssertNil(session.document.layers[0].smartObject)
      XCTAssertNil(session.document.layers[0].smartFilters)
      XCTAssertEqual(try Renderer.composite(session.document).rgbaData(depth:.u8),try output.rgbaData(depth:.u8))
      try session.undo();XCTAssertEqual(session.document,d)
    }
  }
  func testSharedReplacementIndependentCopyAndUndoRetainPDFSelection() throws {
    var session = EditorSession(document:try document());let id = session.document.layers[0].id
    try session.execute(.duplicateLayer(id));let shared = session.document.activeLayerID!
    try session.execute(.independentSmartObjectCopy(id));let independent = session.document.activeLayerID!
    let before = session.document
    try session.execute(PDFSmartObjectIO.replacement(data(),fileName:"Page2.pdf",in:before,
      layerID:id,settings:settings(.crop,page:2)))
    for target in [id,shared] {
      XCTAssertEqual(session.document.layers.first{$0.id == target}?.smartObject?.pdfSource?.page,2)
    }
    XCTAssertEqual(session.document.layers.first{$0.id == independent}?.smartObject?.pdfSource?.page,1)
    try session.undo();XCTAssertEqual(session.document,before)
    try session.execute(.lock(shared,true));let locked = session.document
    XCTAssertThrowsError(try session.execute(PDFSmartObjectIO.replacement(data(),fileName:"Page2.pdf",in:locked,
      layerID:id,settings:settings(.crop,page:2))))
    XCTAssertEqual(session.document,locked)
  }
  func testInvalidMetadataSelectionsEncryptionAndRenderBudgets() throws {
    let d = try document(),source = try data()
    for pages in [[],[0],[4],[1,2]] {
      var options = settings();options.pages = pages
      XCTAssertThrowsError(try PDFSmartObjectIO.placed(source,fileName:"Bad.pdf",in:d,settings:options))
    }
    var options = settings();options.width = 100
    XCTAssertThrowsError(try PDFSmartObjectIO.placed(source,fileName:"Bad.pdf",in:d,settings:options))
    XCTAssertThrowsError(try PDFSmartObjectIO.placed(data("owned-password"),fileName:"Locked.pdf",in:d,settings:settings()))
    var object = try XCTUnwrap(d.layers[0].smartObject);object.pdfSource?.x = -1
    XCTAssertThrowsError(try object.validate())
    object = try XCTUnwrap(d.layers[0].smartObject);object.pdfSource?.width += 1
    XCTAssertThrowsError(try PDFSmartObjectIO.surface(object,width:144,height:108,in:d))
    object = try XCTUnwrap(d.layers[0].smartObject);object.pdfSource = nil
    XCTAssertThrowsError(try object.validate())
    var layer = d.layers[0];layer.affine = .scale(1000,1000)
    XCTAssertThrowsError(try PDFSmartObjectIO.renderedLayer(layer,in:d))
  }
  func testCancelledPDFRenderDoesNotReturnProjection() async throws {
    let d = try document();var layer = d.layers[0];layer.affine = .scale(3,3);let frozen = layer
    let worker = Task.detached {
      while !Task.isCancelled {await Task.yield()}
      return try PDFSmartObjectIO.renderedLayer(frozen,in:d)
    }
    worker.cancel()
    do {_ = try await worker.value;XCTFail("Cancelled render succeeded")}catch is CancellationError {}
  }
}
