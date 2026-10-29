import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PDFImportTests: XCTestCase {
  func data(_ filename: String = "owned-boxes") throws -> Data {
    let folder = URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/pdf")
    return try Data(contentsOf:folder.appendingPathComponent(filename+".pdf"))
  }
  func settings(_ crop: PDFImportSettings.Crop = .media) -> PDFImportSettings {
    var options = PDFImportSettings();options.resolution = 72;options.crop = crop;options.antialias = false;return options
  }
  func output(_ document: CraftDocument,_ name: String) throws {
    if let directory = ProcessInfo.processInfo.environment["PHOTATO_PDF_OUTPUT"] {
      let root = URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
      try RasterIO.encoded(document).write(to:root.appendingPathComponent(name+".png"))
    }
  }
  func testInspectAllPageBoxesAndRotationWithoutChangingSource() throws {
    let source = try data(),info = try PDFImport.inspect(source)
    XCTAssertEqual(info.pages.count,3);XCTAssertFalse(info.encrypted)
    XCTAssertEqual(info.pages[0].boxes["media"],[144,108]);XCTAssertEqual(info.pages[0].boxes["crop"],[120,88])
    XCTAssertEqual(info.pages[0].boxes["bleed"],[128,96]);XCTAssertEqual(info.pages[0].boxes["trim"],[112,80]);XCTAssertEqual(info.pages[0].boxes["art"],[90,66])
    XCTAssertEqual(info.pages[1].rotation,90);XCTAssertEqual(info.pages[1].boxes["media"],[108,72])
    XCTAssertEqual(try data(),source)
  }
  func testVectorPageCoordinatesAlphaAndEditablePersistence() throws {
    let document = try PDFImport.pages(data(),name:"Original",settings:settings())[0]
    XCTAssertEqual(document.width,144);XCTAssertEqual(document.height,108);XCTAssertEqual(document.resolution,72)
    XCTAssertEqual(document.layers.count,1);XCTAssertNil(document.layers[0].smartObject)
    let pixels = try Renderer.composite(document)
    XCTAssertEqual(pixels.pixel(x:18,y:66),Pixel(1,0,0));XCTAssertEqual(pixels.pixel(x:53,y:89),Pixel(1,0,0))
    XCTAssertEqual(pixels.pixel(x:90,y:24),Pixel(0,0,1));XCTAssertEqual(pixels.pixel(x:107,y:47),Pixel(0,0,1))
    XCTAssertEqual(pixels.pixel(x:0,y:0).a,0);XCTAssertEqual(pixels.pixel(x:18,y:90).a,0)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(document)),document)
    XCTAssertEqual(try PSDCodec.read(PSDCodec.writeRasterLayers(document)).width,144)
    var session = EditorSession(document:document);try session.execute(.renameLayer(document.layers[0].id,"Imported artwork"));try session.undo();XCTAssertEqual(session.document,document)
    try output(document,"media-1")
  }
  func testCropBoxesAndRenderedContentBounds() throws {
    let sizes: [PDFImportSettings.Crop:[Int]] = [.media:[144,108],.crop:[120,88],.bleed:[128,96],.trim:[112,80],.art:[90,66],.bounding:[90,66]]
    for crop in PDFImportSettings.Crop.allCases {
      let doc = try PDFImport.pages(data(),name:"Crop",settings:settings(crop))[0]
      XCTAssertEqual([doc.width,doc.height],sizes[crop],crop.rawValue)
      try output(doc,crop.rawValue+"-box")
      if crop == .bounding || crop == .art {
        let pixels = try Renderer.composite(doc)
        XCTAssertEqual(pixels.pixel(x:0,y:42),Pixel(1,0,0),crop.rawValue)
        XCTAssertEqual(pixels.pixel(x:72,y:0),Pixel(0,0,1),crop.rawValue)
      }
    }
    var blank = settings(.bounding);blank.pages = [3]
    let doc = try PDFImport.pages(data(),name:"Blank",settings:blank)[0]
    XCTAssertEqual([doc.width,doc.height],[72,72]);XCTAssertNil(try Renderer.composite(doc).contentBounds())
  }
  func testMultiplePagesProportionsExactDimensionsAndResolution() throws {
    var options = settings();options.pages = [2,1];options.width = 288
    let docs = try PDFImport.pages(data(),name:"Multiple",settings:options)
    XCTAssertEqual(docs.map(\.name),["Multiple-2","Multiple-1"])
    XCTAssertEqual(docs.map(\.width),[216,288]);XCTAssertEqual(docs.map(\.height),[144,216])
    options.width = nil;options.resolution = 144
    let dpi = try PDFImport.pages(data(),name:"DPI",settings:options)
    XCTAssertEqual(dpi.map(\.width),[216,288]);XCTAssertEqual(dpi.map(\.resolution),[144,144])
    options.width = 100;options.height = 80;options.constrainProportions = false
    let stretch = try PDFImport.pages(data(),name:"Stretch",settings:options)
    XCTAssertTrue(stretch.allSatisfy{$0.width == 100 && $0.height == 80})
    var rotated = settings();rotated.pages = [2]
    try output(PDFImport.pages(data(),name:"Rotated",settings:rotated)[0],"rotated-2")
  }
  func testColorModesAndDepthsRetainEditableStorage() throws {
    for mode in [DocumentColorMode.rgb,.grayscale,.cmyk,.lab] {
      for depth in mode.depths {
        var options = settings(.art);options.mode = mode;options.depth = depth
        let doc = try PDFImport.pages(data(),name:"Color",settings:options)[0]
        XCTAssertEqual(doc.colorMode,mode);XCTAssertEqual(doc.depth,depth)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc)),doc)
        XCTAssertEqual(try Renderer.composite(doc).pixel(x:0,y:0).a,0)
        if mode == .rgb {XCTAssertEqual(try Renderer.composite(doc).pixel(x:0,y:42),Pixel(1,0,0))}
      }
    }
  }
  func testEncryptedInvalidSelectionsAndBudgetsRejectAtomically() throws {
    let encrypted = try data("owned-password")
    XCTAssertThrowsError(try PDFImport.inspect(encrypted));XCTAssertThrowsError(try PDFImport.inspect(encrypted,password:"incorrect"))
    XCTAssertTrue(try PDFImport.inspect(encrypted,password:"photato-fixture").encrypted)
    let opened = try PDFImport.pages(encrypted,name:"Unlocked",settings:settings(),password:"photato-fixture")
    XCTAssertEqual(opened.count,1);XCTAssertEqual(opened[0].width,144)
    XCTAssertThrowsError(try PDFImport.pages(data(),name:"Limit",settings:settings(),maximumPixels:10))
    XCTAssertThrowsError(try PDFImport.pages(data(),name:"Limit",settings:settings(),maximumBytes:1024))
    for pages in [[],[0],[4],[1,1],[1,Int.max]] {
      var options = settings();options.pages = pages
      XCTAssertThrowsError(try PDFImport.pages(data(),name:"Invalid",settings:options))
    }
    for resolution in [Double.nan,.infinity,0,10001] {
      var options = settings();options.resolution = resolution
      XCTAssertThrowsError(try PDFImport.pages(data(),name:"Invalid",settings:options))
    }
    var huge = settings();huge.width = Int.max
    XCTAssertThrowsError(try PDFImport.pages(data(),name:"Invalid",settings:huge))
    XCTAssertThrowsError(try PDFImport.inspect(Data("%PDF-1.4\ninvalid".utf8)))
  }
  func testCancellationReturnsNoDocuments() async throws {
    let source = try data(),options = settings()
    let worker = Task.detached {while !Task.isCancelled {await Task.yield()};return try PDFImport.pages(source,name:"Cancelled",settings:options)}
    worker.cancel()
    do {_ = try await worker.value;XCTFail("Cancelled PDF import succeeded")} catch is CancellationError {}
  }
}
