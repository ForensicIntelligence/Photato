import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RichLayerMergeTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3,depth:depth)
    d.layers[0].name="Red";d.layers[0].content = .raster(try Surface(width:4,height:3,depth:depth,fill:Pixel(1,0,0)))
    var top=Layer(name:"Blue",content:.shape(.init(kind:.rectangle,width:2,height:3,color:Pixel(0,0,1))));top.x=2
    top.mask=try Surface(width:2,height:3,fill:.white)
    d.layers.append(top);d.activeLayerID=top.id;return d
  }
  func merged(_ d:CraftDocument,_ op:LayerMergeOperation = .down,_ ids:Set<UUID>? = nil)throws->CraftDocument {
    try LayerMergePreparation.prepare(d,layerIDs:ids ?? Set(d.activeLayerID.map{[$0]} ?? []),operation:op).result
  }
  func capture(_ data:Data,_ name:String)throws {
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try data.write(to:dir.appendingPathComponent(name))
    }
  }
  func testMaskedShapeDownHasIndependentRedBlueSamplesAtAllDepths()throws {
    var records:[[String:Any]]=[]
    for depth in PixelDepth.allCases {
      var d=try fixture(depth);d.selection = .init(x:0,y:0,width:1,height:1)
      d.sourceMetadata=["owned":Data([1,2,3])];d.guides=[.init(axis:.vertical,position:1)]
      d.alphaChannels=[.init(name:"Saved",pixels:try Surface(width:4,height:3,depth:depth,fill:.white))]
      try Command.layerComp(.capture(id:UUID(),name:"Before",comment:"Preserve",options:.init())).apply(to:&d)
      let result=try merged(d);XCTAssertEqual(result.sourceMetadata,d.sourceMetadata);XCTAssertEqual(result.guides,d.guides);XCTAssertEqual(result.alphaChannels,d.alphaChannels);XCTAssertEqual(result.layerComps,d.layerComps);XCTAssertEqual(result.layers.count,1);XCTAssertEqual(result.layers[0].name,"Red");XCTAssertEqual(result.layers[0].id,d.layers[0].id)
      let data=try Renderer.composite(result).rgbaData(depth:.u8)
      let expected=Data((0..<3).flatMap{_ in [UInt8](repeating:0,count:0)+[255,0,0,255,255,0,0,255,0,0,255,255,0,0,255,255]})
      XCTAssertEqual(data,expected);XCTAssertEqual(result.selection,d.selection)
      records.append(["depth":depth.rawValue,"rgba8":Array(data)])
      try capture(RasterIO.encoded(result,type:.png),"rich-merge-\(depth.rawValue).png")
    }
    try capture(JSONSerialization.data(withJSONObject:records,options:[.sortedKeys]),"rich-merge-vectors.json")
  }
  func testRichVisibleGroupsTypeStylesSmartArtworkAndAdjustmentBakeSameComposite()throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth)
      var text=Layer(name:"Type",content:.text(.init(text:"A",size:9,color:Pixel(0,1,0))));text.opacity=0.5;d.layers.append(text)
      d.layers[1].style=LayerStyle(effects:[LayerEffect(.dropShadow)])
      try Command.newGroup(.init(name:"Group"),children:[text.id,d.layers[1].id]).apply(to:&d)
      let embedded=try SmartObjectIO.embedded(document:fixture(depth),in:d)
      var smart=Layer(name:"Smart",content:.raster(embedded.1));smart.smartObject=embedded.0;smart.opacity=0.2;d.layers.append(smart)
      d.layers.append(Layer(name:"Adjustment",content:.adjustment(.levels(.init()))));d.activeLayerID=smart.id
      let expected=try Renderer.composite(d).rgbaData(depth:depth)
      let result=try merged(d,.visible,[])
      XCTAssertEqual(result.layers.count,1);XCTAssertEqual(result.layers[0].name,"Smart")
      XCTAssertEqual(try Renderer.composite(result).rgbaData(depth:depth),expected)
      XCTAssertNil(result.layers[0].smartObject);XCTAssertNil(result.layers[0].style)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
    }
  }
  func testSelectedChildrenAndGroupPreserveUntouchedParentAndHiddenRoots()throws {
    var d=try fixture();try Command.newGroup(.init(name:"Group"),children:d.layers.map(\.id)).apply(to:&d)
    let group=try XCTUnwrap(d.activeLayerID),children=Set(d.layers.filter{!$0.isGroup}.map(\.id))
    let result=try merged(d,.selected,children)
    XCTAssertEqual(result.layers.count,2);XCTAssertEqual(result.layers[0].parentID,group);XCTAssertEqual(result.layers[1],d.layers.last)
    var hidden=Layer(name:"Hidden",content:.fill(Pixel(0,1,0)));hidden.visible=false;d.layers.append(hidden)
    let whole=try merged(d,.selected,[group]);XCTAssertEqual(whole.layers.count,2);XCTAssertEqual(whole.layers[1],hidden);XCTAssertFalse(whole.layers[0].isGroup)
  }
  func testClippedArtworkAndAffineSourceBakeWithoutDiscardingUnmergedData()throws {
    var d=try fixture();d.layers[1].clipped=true;d.layers[1].affine = .translation(-1,0)
    let expected=try Renderer.composite(d).rgbaData(depth:.u8)
    let result=try merged(d);XCTAssertEqual(try Renderer.composite(result).rgbaData(depth:.u8),expected)
    XCTAssertNil(result.layers[0].clipped);XCTAssertNil(result.layers[0].mask);XCTAssertNil(result.layers[0].affine)
  }
  func testBackgroundAndEntirelyTransparentResultHaveValidStorage()throws {
    var d=try fixture();d.layers[0].background=true
    let result=try merged(d);XCTAssertTrue(result.layers[0].isBackground);XCTAssertEqual(result.layers[0].name,"Background");XCTAssertTrue(try Renderer.composite(result).isOpaque())
    d=try fixture();for i in d.layers.indices{d.layers[i].content = .raster(try Surface(width:1,height:1))};d.layers[1].mask=try Surface(width:1,height:1,fill:.white)
    let empty=try merged(d);XCTAssertEqual(empty.layers.count,1);XCTAssertNil(try Renderer.composite(empty).contentBounds())
  }
  func testMaximumSparseRGB32MergeRetainsHDRAndDoesNotAllocateCanvas()throws {
    var d=try CraftDocument(width:300000,height:300000,depth:.f32)
    d.layers[0].content = .raster(try Surface(width:d.width,height:d.height,depth:.f32,fill:Pixel(4,-0.0,2,1)).interpretingSamples(as:.linearRGB))
    let top=Layer(name:"Empty",content:.raster(try Surface(width:1,height:1,depth:.f32)));d.layers.append(top);d.activeLayerID=top.id
    let result=try merged(d,.visible,[])
    guard case .raster(let pixels)=result.layers[0].content else{return XCTFail("Raster")}
    XCTAssertEqual(pixels.width,300000);XCTAssertEqual(pixels.height,300000);XCTAssertLessThan(pixels.allocatedBytes,1024*1024)
    XCTAssertTrue(pixels.linearPixel(x:299999,y:299999).hasSameBits(as:Pixel(4,-0.0,2,1)))
  }
  func testOffCanvasSelectedGeometryIsRetainedBeyondCanvas()throws {
    var d=try fixture();d.layers[1].x = -2
    let result=try merged(d,.selected,Set(d.layers.map(\.id)))
    XCTAssertEqual(result.layers[0].x,-2)
    guard case .raster(let p)=result.layers[0].content else{return XCTFail("Raster")}
    XCTAssertEqual(p.width,6);XCTAssertEqual(p.pixel(x:0,y:0),Pixel(0,0,1));XCTAssertEqual(p.pixel(x:5,y:0),Pixel(1,0,0))
  }
  func testPSDPSBSaveOpenPreservesRichMergedSamplesAtAllDepths()throws {
    for depth in PixelDepth.allCases {
      let result=try merged(fixture(depth))
      for format:PSDFileFormat in [.psd,.psb] {
        let bytes=try PSDCodec.writeRasterLayers(result,format:format),read=try PSDCodec.read(bytes)
        XCTAssertEqual(read.layers.count,1);XCTAssertEqual(read.layers[0].name,"Red");XCTAssertEqual(read.depth,depth)
        XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:depth),try Renderer.composite(result).rgbaData(depth:depth))
        try capture(bytes,"rich-merge-\(depth.rawValue).\(format == .psd ? "psd":"psb")")
      }
    }
  }
}
