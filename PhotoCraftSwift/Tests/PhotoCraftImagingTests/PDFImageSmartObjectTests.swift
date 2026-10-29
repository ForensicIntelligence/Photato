import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PDFImageSmartObjectTests: XCTestCase {
  func fixture() throws -> Data {try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/pdf/owned-images.pdf"))}
  func testSelectedImagesKeepWholePDFAndRenderOriginalSamplesAcrossDepths() throws {
    let data = try fixture(),images = try PDFImages.inspect(data)
    for depth in PixelDepth.allCases {
      let parent = try CraftDocument(width:32,height:24,depth:depth)
      for info in images {
        let (object,pixels) = try PDFSmartObjectIO.embeddedImage(data,fileName:"Images.pdf",in:parent,image:info.number)
        var settings = PDFImageImportSettings();settings.images = [info.number];settings.depth = depth
        let expected = try PDFImages.documents(data,name:"Reference",settings:settings)[0]
        XCTAssertEqual(object.data,data);XCTAssertEqual(object.width,info.width);XCTAssertEqual(object.height,info.height)
        XCTAssertEqual(object.pdfSource?.page,info.page);XCTAssertEqual(object.pdfSource?.image,info.number)
        XCTAssertEqual(try pixels.rgbaData(depth:depth),try Renderer.composite(expected).rgbaData(depth:depth))
        XCTAssertEqual(try PDFSmartObjectIO.surface(object,width:info.width,height:info.height,in:parent),pixels)
        var doc = parent;var layer = Layer(name:"Image",content:.raster(pixels));layer.smartObject = object;doc.layers = [layer];doc.activeLayerID = layer.id
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc)),doc)
      }
    }
  }
  func testInvalidImageSelectionAndEnlargementPreserveMetadata() throws {
    let data = try fixture(),parent = try CraftDocument(width:16,height:16)
    XCTAssertThrowsError(try PDFSmartObjectIO.embeddedImage(data,fileName:"Images.pdf",in:parent,image:4096))
    let (object,pixels) = try PDFSmartObjectIO.embeddedImage(data,fileName:"Images.pdf",in:parent,image:1,antialias:false)
    var layer = Layer(name:"Image",content:.raster(pixels));layer.smartObject = object;layer.affine = .scale(3,3)
    let projection = try PDFSmartObjectIO.renderedLayer(layer,in:parent)
    guard case .raster(let enlarged) = projection.content else {return XCTFail("Missing image")}
    XCTAssertEqual(enlarged.width,object.width*3);XCTAssertEqual(enlarged.height,object.height*3)
    XCTAssertEqual(layer.smartObject,object)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_PDF_SMART_OUTPUT"] {
      let root = URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
      var rendered = try CraftDocument(width:enlarged.width,height:enlarged.height)
      rendered.layers = [Layer(name:"Image",content:.raster(enlarged))];rendered.activeLayerID = rendered.layers[0].id
      try RasterIO.encoded(rendered).write(to:root.appendingPathComponent("image-3x.png"))
    }

    var invalid = object;invalid.pdfSource?.page = 4096
    XCTAssertThrowsError(try PDFSmartObjectIO.surface(invalid,width:2,height:2,in:parent))
  }
}
