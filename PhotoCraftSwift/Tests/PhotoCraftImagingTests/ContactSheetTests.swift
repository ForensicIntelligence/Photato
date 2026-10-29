import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ContactSheetTests: XCTestCase {
  func source(_ color: Pixel, name: String = "Photo.png",width: Int = 2,height: Int = 2) throws -> ContactSheet.Source {
    .init(document:try DocumentCreation.blank(width:width,height:height,background:color,name:name))
  }
  func settings() -> ContactSheetSettings {
    var s = ContactSheetSettings();s.units = .pixels;s.width = 8;s.height = 8;s.resolution = 72;s.columns = 2;s.rows = 2;s.autoSpacing = false;s.horizontal = 0;s.vertical = 0;s.caption = false;s.flatten = false;return s
  }
  func testPageOrderPlacementAndIndependentRaster() throws {
    let colors: [Pixel] = [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),.black,.white]
    let sources = try colors.enumerated().map{try source($0.element,name:"Photo\($0.offset).png")}
    for across in [true,false] {
      var s = settings();s.placeAcrossFirst = across
      let result = try ContactSheet.prepare(sources,settings:s)
      XCTAssertEqual(result.documents.count,2);XCTAssertEqual(result.documents.map(\.name),["ContactSheet-001","ContactSheet-002"])
      for (i,p) in result.placements.enumerated() {
        XCTAssertEqual(p.page,i/4);XCTAssertEqual(p.column,across ? (i%4)%2:(i%4)/2);XCTAssertEqual(p.row,across ? (i%4)/2:(i%4)%2)
        XCTAssertEqual(p.width,4);XCTAssertEqual(p.height,4)
        let rendered = try Renderer.composite(result.documents[p.page]);XCTAssertEqual(rendered.pixel(x:p.x,y:p.y),colors[i]);XCTAssertEqual(rendered.pixel(x:p.x+3,y:p.y+3),colors[i])
      }
      if let path = ProcessInfo.processInfo.environment["PHOTATO_CONTACT_SHEET_ARTIFACTS"] {
        let folder = URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for (i,d) in result.documents.enumerated() {try RasterIO.encoded(d,type:.png).write(to:folder.appendingPathComponent("grid-\(across)-\(i).png"))}
      }
    }
  }
  func testRotationPreservesOrientationAndAspect() throws {
    var d = try DocumentCreation.blank(width:2,height:4,background:.black,name:"Portrait")
    var pixels = try Surface(width:2,height:4,fill:.black);pixels.setPixel(x:0,y:0,Pixel(1,0,0));pixels.setPixel(x:1,y:3,Pixel(0,0,1));d.layers[0].content = .raster(pixels)
    var s = settings();s.width = 4;s.height = 2;s.columns = 1;s.rows = 1;s.rotateForBestFit = true
    let result = try ContactSheet.prepare([.init(document:d)],settings:s);XCTAssertTrue(result.placements[0].rotated)
    let raster = try Renderer.composite(result.documents[0]);XCTAssertEqual(raster.pixel(x:3,y:0),Pixel(1,0,0));XCTAssertEqual(raster.pixel(x:0,y:1),Pixel(0,0,1))
    s.rotateForBestFit = false;let upright = try ContactSheet.prepare([.init(document:d)],settings:s)
    XCTAssertFalse(upright.placements[0].rotated);XCTAssertEqual(upright.placements[0].width,1);XCTAssertEqual(upright.placements[0].height,2)
  }
  func testPhysicalUnitsSpacingAndInvalidLayouts() throws {
    let initial = ContactSheetSettings();XCTAssertEqual(try initial.layout().width,2400);XCTAssertEqual(try initial.layout().height,3000)
    for (unit,w,h) in [(ContactSheetSettings.Units.inches,8.0,10.0),(.cm,20.32,25.4),(.mm,203.2,254.0),(.pixels,2400.0,3000.0)] {
      var s = initial;s.units = unit;s.width = w;s.height = h;XCTAssertEqual(try s.layout().width,2400);XCTAssertEqual(try s.layout().height,3000)
    }
    var s = settings();s.width = 14;s.height = 14;s.horizontal = 2;s.vertical = 2
    let layout = try s.layout();XCTAssertEqual(layout.cellWidth,4);XCTAssertEqual(layout.imageHeight,4)
    s.horizontal = 100;XCTAssertThrowsError(try s.layout());s = settings();s.width = .nan;XCTAssertThrowsError(try s.layout());s = settings();s.columns = 0;XCTAssertThrowsError(try s.layout())
    s = settings();s.caption = true;s.fontSize = 300;XCTAssertThrowsError(try s.layout())
    s = settings();s.width = 200;s.height = 200;s.columns = 1;s.rows = 1;s.caption = true;s.font = "PhotatoMissingContactSheetFont"
    XCTAssertThrowsError(try ContactSheet.prepare([source(.black)],settings:s))
    s = settings();s.mode = .cmyk;s.depth = .f32;XCTAssertThrowsError(try s.layout())
  }
  func testCaptionsModesDepthsFlatteningAndArchive() throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      var s = settings();s.width = 120;s.height = 100;s.columns = 1;s.rows = 1;s.caption = true;s.fontSize = 10;s.mode = mode;s.depth = depth
      let inputs = [try source(Pixel(0.3,0.5,0.7),name:"Owned image.png")]
      let result = try ContactSheet.prepare(inputs,settings:s),d = result.documents[0]
      XCTAssertEqual(d.layers.count,3);XCTAssertEqual(d.colorMode,mode);XCTAssertEqual(d.depth,depth)
      guard case .text(let text) = d.layers[2].content else {return XCTFail("Missing editable caption")}
      XCTAssertEqual(text.text,"Owned image.png");XCTAssertEqual(text.typography?.defaultStyle.size,10);XCTAssertEqual(text.typography?.defaultParagraph.alignment,.center)
      let rendered = try Renderer.composite(d)
      let ink = (85..<100).reduce(0) {n,y in n+(0..<120).filter {x in let p = rendered.pixel(x:x,y:y);return p.r < 0.4 && p.g < 0.4 && p.b < 0.4}.count}
      XCTAssertGreaterThan(ink,0,"Caption must draw visible glyphs in \(mode)/\(depth)")
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      s.flatten = true;let flat = try ContactSheet.prepare(inputs,settings:s).documents[0];XCTAssertEqual(flat.layers.count,1);XCTAssertEqual(flat.colorMode,mode)
      if mode == .rgb {XCTAssertEqual(try Renderer.composite(flat),try Renderer.composite(d))}
    } }
  }
  func testCancellationAndLateInvalidInputDoNotChangeSources() async throws {
    let inputs = [try source(.black),try source(.white)],before = inputs.map(\.document),s = settings()
    let task = Task {try ContactSheet.prepare(inputs,settings:s)};task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled preparation succeeded")} catch is CancellationError {} catch {XCTFail("Unexpected \(error)")}
    var invalid = inputs[1].document;invalid.layers.removeAll()
    XCTAssertThrowsError(try ContactSheet.prepare([inputs[0],.init(document:invalid)],settings:s))
    XCTAssertEqual(inputs.map(\.document),before)
    var many = s;many.columns = 1;many.rows = 1
    XCTAssertThrowsError(try ContactSheet.prepare(Array(repeating:inputs[0],count:33),settings:many))
  }
}
