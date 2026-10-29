import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ScanCropTests: XCTestCase {
  func scan(depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width:180,height:120,depth:depth,name:"Owned scan")
    var pixels = try Surface(width:180,height:120,depth:depth,fill:.white)
    for y in 20..<100 {for x in 15..<165 where x < 75 || x >= 105 {pixels.setPixel(x:x,y:y,x<75 ? Pixel(0.2,0.4,0.6):Pixel(0.7,0.3,0.1))}}
    document.layers[0].content = .raster(pixels);document.resolution = 300;return document
  }
  func testSeparateOutputsSelectedLayerSelectionAndSourcePreservation() throws {
    var document = try scan();let original = document
    let extra = Layer(name:"Unselected",content:.fill(.black));document.layers.append(extra)
    let result = try ScanCrop.prepare(document);XCTAssertEqual(result.documents.count,2)
    for (i,output) in result.documents.enumerated() {
      XCTAssertEqual(output.width,58);XCTAssertEqual(output.height,78);XCTAssertEqual(output.pixelsPerInch,300)
      XCTAssertEqual(output.name,"Owned scan copy \(i+1)");XCTAssertEqual(output.layers[0].protection,[.transparency,.position]);XCTAssertNil(output.selection)
      let pixel = try Renderer.composite(output).pixel(x:20,y:20)
      XCTAssertEqual(pixel,(i == 0 ? Pixel(0.2,0.4,0.6):Pixel(0.7,0.3,0.1)).quantized(.u8))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(output)),output)
    }
    document.selection = IntRect(x:95,y:5,width:80,height:110)
    let selected = try ScanCrop.prepare(document);XCTAssertEqual(selected.documents.count,1);XCTAssertEqual(selected.photos[0].centerX,135)
    document.selection = nil
    XCTAssertEqual(try ScanCrop.prepare(document,forceSingle:true).documents.count,1)
    XCTAssertEqual(original.layers[0],document.layers[0]);XCTAssertEqual(document.layers.count,2)
    XCTAssertTrue(try ScanCrop.analyze(document,layerID:extra.id).photos.isEmpty)
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_SCANCROP_OUTPUT"] {
      let directory = URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
      for (i,output) in result.documents.enumerated() {try RasterIO.encoded(output,type:.png).write(to:directory.appendingPathComponent("photo-\(i).png"))}
      try JSONEncoder().encode(result.photos).write(to:directory.appendingPathComponent("detections.json"))
    }
  }
  func testRotatedGradientStraightensAndKeepsOrientation() throws {
    var document = try CraftDocument(width:250,height:200,depth:.f32)
    var pixels = try Surface(width:250,height:200,depth:.f32,fill:.white)
    let radians = 12.0 * .pi/180
    for y in 0..<200 {for x in 0..<250 {
      let dx = Double(x)+0.5-125,dy = Double(y)+0.5-100
      let u = cos(radians)*dx+sin(radians)*dy,v = -sin(radians)*dx+cos(radians)*dy
      if abs(u)<70,abs(v)<45 {pixels.setPixel(x:x,y:y,Pixel(Float((u+70)/400+0.1),Float((v+45)/400+0.1),0.2))}
    }}
    document.layers[0].content = .raster(pixels)
    let result = try ScanCrop.prepare(document);XCTAssertEqual(result.documents.count,1)
    let photo = try XCTUnwrap(result.photos.first);XCTAssertEqual(photo.angle,12,accuracy:1)
    let surface = try Renderer.composite(XCTUnwrap(result.documents.first))
    let a = surface.pixel(x:20,y:20),b = surface.pixel(x:100,y:20),c = surface.pixel(x:20,y:60)
    XCTAssertGreaterThan(b.r-a.r,0.15);XCTAssertEqual(b.g,a.g,accuracy:0.005)
    XCTAssertGreaterThan(c.g-a.g,0.08);XCTAssertEqual(c.r,a.r,accuracy:0.005)
  }
  func testNativeComponentModesAndDepthsRetainProfilesAndSeparations() throws {
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      let rgb = try scan(depth:depth)
      let document = mode == .rgb ? rgb:try rgb.convertingMode(.init(mode:mode,depth:depth))
      let analysis = try ScanCrop.analyze(document);XCTAssertTrue(analysis.preservesNativeComponents)
      let result = try ScanCrop.extract(analysis,from:document)
      XCTAssertEqual(result.documents.count,2)
      let output = try XCTUnwrap(result.documents.first)
      XCTAssertEqual(output.modeDescriptor,document.modeDescriptor);XCTAssertEqual(output.depth,depth)
      if let before = document.layers[0].nativeMode,let after = output.layers[0].nativeMode {
        for c in 0..<mode.componentCount {XCTAssertEqual(after.value(component:c,index:20*output.width+20),before.value(component:c,index:60*180+40),accuracy:depth == .u8 ? 1/255:depth == .u16 ? 1/65535:0.00001)}
      } else {XCTAssertEqual(mode,.rgb)}
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(output)),output)
    }}
  }
  func testInvalidBlankSelectionAndCancellation() async throws {
    var document = try scan();XCTAssertThrowsError(try ScanCrop.prepare(document,layerID:UUID()))
    document.selection = IntRect(x:0,y:0,width:5,height:5);XCTAssertThrowsError(try ScanCrop.prepare(document))
    let blank = try CraftDocument(width:50,height:50);XCTAssertTrue(try ScanCrop.analyze(blank).photos.isEmpty);XCTAssertThrowsError(try ScanCrop.prepare(blank))
    document = try scan();let snapshot = document
    let task = Task {try ScanCrop.prepare(snapshot)};task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled extraction succeeded")} catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
    XCTAssertEqual(document,snapshot)
  }
}
