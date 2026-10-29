import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PDFImagesTests: XCTestCase {
  func data() throws -> Data {try PDFImportTests().data("owned-images")}
  func options(_ ids: [Int]) -> PDFImageImportSettings {var s = PDFImageImportSettings();s.images = ids;return s}
  func testDiscoveryFindsNestedAndInlineImagesDeduplicatesAndDoesNotExposeMasks() throws {
    let info = try PDFImages.inspect(data())
    XCTAssertEqual(info.count,8);XCTAssertEqual(info.map(\.number),Array(1...8));XCTAssertEqual(info.map(\.page),Array(repeating:1,count:8))
    XCTAssertEqual(info.map(\.width),[2,2,4,4,2,2,3,1]);XCTAssertEqual(info.map(\.height),[2,2,1,1,1,1,2,1])
    XCTAssertEqual(info.map(\.bitsPerComponent),[8,8,2,8,8,16,8,8]);XCTAssertTrue(info.allSatisfy{!$0.imageMask})
    XCTAssertTrue(try PDFImages.inspect(PDFImportTests().data()).isEmpty)
  }
  func testExtractedPixelsMasksPalettesDecodeAndIntrinsicDimensions() throws {
    let source = try data(),documents = try PDFImages.documents(source,name:"Extracted",settings:options(Array(1...8)))
    XCTAssertEqual(documents.map(\.name),(1...8).map{"Extracted-\($0)"});XCTAssertEqual(try data(),source)
    for (index,document) in documents.enumerated() {try PDFImportTests().output(document,"image-\(index+1)")}
    let rgb = try Renderer.composite(documents[0]);XCTAssertEqual(rgb.pixel(x:0,y:0),Pixel(1,0,0));XCTAssertEqual(rgb.pixel(x:1,y:0),Pixel(0,1,0));XCTAssertEqual(rgb.pixel(x:0,y:1),Pixel(0,0,1))
    let gray = try Renderer.composite(documents[1]);XCTAssertEqual(gray.pixel(x:0,y:0),.white);XCTAssertEqual(gray.pixel(x:1,y:1),Pixel(0,0,0))
    let palette = try Renderer.composite(documents[2]);XCTAssertEqual((0..<4).map{palette.pixel(x:$0,y:0)},[Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),.white])
    let masked = try Renderer.composite(documents[3]);for x in 0..<4 {XCTAssertEqual(masked.pixel(x:x,y:0).a,Float(x)/3,accuracy:1/255);if x>0 {XCTAssertEqual(masked.pixel(x:x,y:0).r,1)}}
    XCTAssertEqual(try Renderer.composite(documents[7]).pixel(x:0,y:0),Pixel(1,1,0))
  }
  func testSelectionOrderPersistenceEditUndoAndResolutionDoesNotResample() throws {
    var s = options([8,1]);s.resolution = 300
    let docs = try PDFImages.documents(data(),name:"Selected",settings:s)
    XCTAssertEqual(docs.map(\.width),[1,2]);XCTAssertEqual(docs.map(\.name),["Selected-8","Selected-1"]);XCTAssertEqual(docs.map(\.resolution),[300,300])
    for doc in docs {
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc)),doc)
      XCTAssertEqual(try PSDCodec.read(PSDCodec.writeRasterLayers(doc)).width,doc.width)
      var session = EditorSession(document:doc);try session.execute(.renameLayer(doc.layers[0].id,"Editable"));try session.undo();XCTAssertEqual(session.document,doc)
    }
    let preview = try PDFImages.thumbnail(data(),image:1);XCTAssertFalse(preview.isEmpty)
  }
  func testModesDepthsAndSource16BitOutput() throws {
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      var s = options([6]);s.mode = mode;s.depth = depth
      let doc = try PDFImages.documents(data(),name:"Color",settings:s)[0]
      XCTAssertEqual(doc.colorMode,mode);XCTAssertEqual(doc.depth,depth);XCTAssertEqual(doc.width,2)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc)),doc)
    }}
  }
  func testUpscaledPDFImagesAndThumbnailsRetainBothSourcePixels() throws {
    for depth in PixelDepth.allCases {
      var settings = PDFImportTests().settings();settings.depth = depth
      let doc = try PDFImport.pages(data(),name:"Scaled images",settings:settings)[0]
      let pixels = try Renderer.composite(doc)
      XCTAssertEqual(pixels.pixel(x:98,y:60),Pixel(1,0,0),depth.rawValue)
      XCTAssertEqual(pixels.pixel(x:112,y:60),Pixel(0,1,0),depth.rawValue)
    }
    let bytes = try PDFImages.thumbnail(data(),image:6)
    let doc = try RasterIO.read(bytes,name:"Thumbnail"),pixels = try Renderer.composite(doc)
    XCTAssertEqual([doc.width,doc.height],[160,80])
    XCTAssertEqual(pixels.pixel(x:20,y:40),Pixel(1,0,0));XCTAssertEqual(pixels.pixel(x:140,y:40),Pixel(0,1,0))
    try PDFImportTests().output(doc,"image6-thumbnail")
  }
  func testBadSelectionsBudgetsPasswordsAndCancellation() async throws {
    for ids in [[],[0],[9],[1,1],[Int.max]] {XCTAssertThrowsError(try PDFImages.documents(data(),name:"Bad",settings:options(ids)))}
    XCTAssertThrowsError(try PDFImages.documents(data(),name:"Budget",settings:options([1]),maximumPixels:1))
    XCTAssertThrowsError(try PDFImages.documents(data(),name:"Budget",settings:options([1]),maximumBytes:1024))
    XCTAssertThrowsError(try PDFImages.inspect(PDFImportTests().data("owned-password")))
    XCTAssertTrue(try PDFImages.inspect(PDFImportTests().data("owned-password"),password:"photato-fixture").isEmpty)
    let bytes = try data();let job = Task.detached {while !Task.isCancelled {await Task.yield()};return try PDFImages.inspect(bytes)};job.cancel()
    do {_ = try await job.value;XCTFail("Cancelled image scan succeeded")} catch is CancellationError {}
  }
}
