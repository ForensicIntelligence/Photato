import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class DocumentDuplicateIOTests: XCTestCase {
  func testMergedCopyPreservesTransparencyPrecisionAndIgnoresSelection() throws {
    var vectors:[[String:Any]]=[]
    for depth in PixelDepth.allCases {
      var source=try CraftDocument(width:2,height:1,depth:depth)
      var pixels=try Surface(width:2,height:1,depth:depth,fill:Pixel(1,0,0,0.5))
      pixels.setPixel(x:1,y:0,.clear);source.layers[0].content = .raster(pixels)
      var hidden=Layer(name:"Hidden",content:.raster(try Surface(width:2,height:1,depth:depth,fill:Pixel(0,0,1))));hidden.visible=false;source.layers.append(hidden)
      source.selection=IntRect(x:1,y:0,width:1,height:1)
      let result=try DocumentDuplicatePreparation.copy(source,name:"Merged",merged:true)
      XCTAssertNotEqual(result.id,source.id);XCTAssertEqual(result.layers.count,1);XCTAssertEqual(result.selection,source.selection)
      XCTAssertFalse(result.layers[0].isBackground)
      guard case .raster(let actual)=result.layers[0].content else{return XCTFail("Raster")}
      XCTAssertEqual(actual.depth,depth);XCTAssertEqual(actual.pixel(x:0,y:0),Pixel(1,0,0,0.5).quantized(depth))
      XCTAssertEqual(actual.pixel(x:1,y:0).a,0)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
      let bytes=try actual.rgbaData(depth:.u8);vectors.append(["depth":depth.rawValue,"rgba8":Array(bytes)])
      if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try RasterIO.encoded(result,type:.png).write(to:dir.appendingPathComponent("duplicate-owned-\(depth.rawValue).png"))
      }
    }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try JSONSerialization.data(withJSONObject:vectors,options:[.sortedKeys]).write(to:URL(fileURLWithPath:path).appendingPathComponent("duplicate-analytical.json"))}
  }
  func testRichCopyRetainsEditableObjectsWhileMergedCopyBakesVisibleAppearance() throws {
    var source=try CraftDocument(width:32,height:24)
    var shape=Layer(name:"Shape",content:.shape(.init(kind:.ellipse,width:12,height:10,color:Pixel(0,0,1))));shape.x=3;shape.y=4
    source.layers.append(shape)
    source.layers.append(Layer(name:"Type",content:.text(.init(text:"Owned",size:10,color:Pixel(1,0,0)))))
    let independent=try DocumentDuplicatePreparation.copy(source,name:"Editable")
    XCTAssertEqual(independent.layers,source.layers)
    let expected=try Renderer.composite(source).rgbaData(depth:source.depth)
    let merged=try DocumentDuplicatePreparation.copy(source,name:"Merged",merged:true)
    XCTAssertEqual(try Renderer.composite(merged).rgbaData(depth:source.depth),expected)
    XCTAssertEqual(source.layers.count,3)
  }
  func testMaximumSparseMergedCopyAndAllHiddenOutputStayBounded() throws {
    var source=try CraftDocument(width:300000,height:300000,depth:.f32)
    source.layers[0].content = .raster(try Surface(width:source.width,height:source.height,depth:.f32,fill:Pixel(1,0,0,0.5)))
    let result=try DocumentDuplicatePreparation.copy(source,name:"Large merged",merged:true)
    XCTAssertLessThan(result.estimatedBytes,2*1024*1024)
    source.layers[0].visible=false
    let empty=try DocumentDuplicatePreparation.copy(source,name:"Hidden merged",merged:true)
    guard case .raster(let pixels)=empty.layers[0].content else{return XCTFail("Raster")}
    XCTAssertEqual(pixels.tileCount,0);XCTAssertEqual(pixels.defaultPixel.a,0);XCTAssertFalse(empty.layers[0].isBackground)
  }
  func testMergedNativeModeRejectsWithoutConvertingOrChangingSource() throws {
    let source=try CraftDocument(width:2,height:1).convertingMode(.init(mode:.cmyk,depth:.u16))
    XCTAssertThrowsError(try DocumentDuplicatePreparation.copy(source,name:"Merged",merged:true))
    let copy=try DocumentDuplicatePreparation.copy(source,name:"Full")
    XCTAssertEqual(copy.layers,source.layers);XCTAssertEqual(copy.modeDescriptor,source.modeDescriptor)
  }
}
