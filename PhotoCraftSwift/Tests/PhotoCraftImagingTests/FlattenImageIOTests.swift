import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class FlattenImageIOTests: XCTestCase {
  func simple(_ depth:PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:2,height:1,depth:depth)
    var s = try Surface(width:2,height:1,depth:depth,fill:Pixel(1,0,0,0.5),colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    if depth == .f32 {s.setLinearPixel(x:1,y:0,Pixel(0,0,4,0))} else {s.setPixel(x:1,y:0,Pixel(0,0,1,0))}
    d.layers[0].content = .raster(s); return d
  }
  func capture(_ data:Data,_ name:String) throws {
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
      try data.write(to:dir.appendingPathComponent(name))
    }
  }
  func testTransparentPixelsAreCompositedOverWhiteAtDocumentPrecision() throws {
    var vectors:[[String:Any]]=[]
    for depth in PixelDepth.allCases {
      let source=try simple(depth),result=try FlattenPreparation.prepare(source).result
      let layer=try XCTUnwrap(result.layers.first);XCTAssertTrue(layer.isBackground);XCTAssertEqual(layer.name,"Background")
      guard case .raster(let p)=layer.content else{return XCTFail("Raster")}
      XCTAssertEqual(p.depth,depth);XCTAssertTrue(try p.isOpaque());XCTAssertEqual(result.selection,source.selection)
      let expected:Pixel = depth == .u8 ? Pixel(1,127.0/255,127.0/255) : depth == .u16 ? Pixel(1,32767.0/65535,32767.0/65535) : Pixel(1,0.5,0.5)
      XCTAssertTrue((depth == .f32 ? p.linearPixel(x:0,y:0):p.pixel(x:0,y:0)).hasSameBits(as:expected))
      XCTAssertEqual(p.pixel(x:1,y:0),.white)
      vectors.append(["depth":depth.rawValue,"actualRGBA8":Array(try p.rgbaData(depth:.u8))])
      try capture(RasterIO.encoded(result,type:.png),"flatten-owned-\(depth.rawValue).png")
    }
    try capture(JSONSerialization.data(withJSONObject:vectors,options:[.sortedKeys]),"flatten-analytical.json")
  }
  func testRichVisibleArtworkBakesGroupsMasksTypeShapeStyleAdjustmentAndSmartSource() throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:64,height:48,depth:depth)
      d.layers[0].background=true
      var shape=Layer(name:"Shape",content:.shape(.init(kind:.ellipse,width:15,height:12,color:Pixel(0,0,1))));shape.x=4;shape.y=4
      shape.style=LayerStyle(effects:[LayerEffect(.dropShadow)])
      d.layers.append(shape)
      var text=Layer(name:"Type",content:.text(.init(text:"Owned",size:12,color:Pixel(1,0,0))));text.y=20;d.layers.append(text)
      try Command.newGroup(.init(name:"Artwork"),children:[shape.id,text.id]).apply(to:&d)
      let source=try simple(depth),embedded=try SmartObjectIO.embedded(document:source,in:d)
      var smart=Layer(name:"Embedded",content:.raster(embedded.1));smart.smartObject=embedded.0;smart.x=30;smart.y=5
      smart.mask=try Surface(width:2,height:1,depth:depth,fill:Pixel(0.5,0.5,0.5));d.layers.append(smart)
      d.layers.append(Layer(name:"Levels",content:.adjustment(.levels(.init()))))
      let expected=try Renderer.composite(d).rgbaData(depth:depth)
      let result=try FlattenPreparation.prepare(d).result
      XCTAssertEqual(result.layers.count,1);XCTAssertEqual(result.layers[0].id,d.layers[0].id)
      XCTAssertEqual(try Renderer.composite(result).rgbaData(depth:depth),expected)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
    }
  }
  func testMaximumSparseFlattenAndHiddenOnlyOutputDoNotMaterializeCanvas() throws {
    var d=try CraftDocument(width:300000,height:300000,depth:.f32)
    var source=try Surface(width:d.width,height:d.height,depth:.f32,fill:Pixel(4,-0.25,0.5,0.5)).interpretingSamples(as:.linearRGB)
    source.setLinearPixel(x:150000,y:150000,Pixel(8,-0.0,2,1));d.layers[0].content = .raster(source)
    let result=try FlattenPreparation.prepare(d).result
    guard case .raster(let p)=result.layers[0].content else{return XCTFail("Raster")}
    XCTAssertEqual(p.width,300000);XCTAssertEqual(p.height,300000);XCTAssertLessThan(p.allocatedBytes,2*1024*1024)
    XCTAssertTrue(p.linearPixel(x:0,y:0).hasSameBits(as:Pixel(2.5,0.375,0.75,1)))
    d.layers[0].visible=false
    let hidden=try FlattenPreparation.prepare(d).result
    guard case .raster(let blank)=hidden.layers[0].content else{return XCTFail("Raster")}
    XCTAssertEqual(blank.defaultPixel,.white);XCTAssertEqual(blank.tileCount,0)
  }
  func testNativeAndPSDPSBRetainOpaqueBackgroundAndNumericalDepth() throws {
    for depth in PixelDepth.allCases {
      let d=try FlattenPreparation.prepare(simple(depth)).result
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      for format:PSDFileFormat in [.psd,.psb] {
        let data=try PSDCodec.writeRasterLayers(d,format:format),read=try PSDCodec.read(data)
        XCTAssertEqual(read.layers.count,1);XCTAssertTrue(read.layers[0].isBackground);XCTAssertEqual(read.depth,depth)
        guard case .raster(let before)=d.layers[0].content,case .raster(let after)=read.layers[0].content else{return XCTFail("Raster")}
        if depth == .f32 {for x in 0..<2 {XCTAssertTrue(after.linearPixel(x:x,y:0).hasSameBits(as:before.linearPixel(x:x,y:0)))}}
        else {XCTAssertEqual(try after.rgbaData(depth:depth),try before.rgbaData(depth:depth))}
        try capture(data,"flatten-background-\(depth.rawValue).\(format == .psd ? "psd":"psb")")
      }
    }
  }
  func testSavedDocumentChannelsSelectionsGuidesCompsAndMetadataSurviveUndo() throws {
    var source=try simple();source.selection = .init(x:0,y:0,width:1,height:1)
    source.guides=[.init(axis:.vertical,position:1)]
    source.alphaChannels=[AlphaChannel(name:"Saved",pixels:try Surface(width:2,height:1,fill:.white))]
    source.sourceMetadata=["owned":Data([1,2,3])]
    let compID=UUID()
    try Command.layerComp(.capture(id:compID,name:"Before",comment:"Retain",options:.init())).apply(to:&source)
    source.workingICC = try RasterIO.colorSpace().copyICCData() as Data?
    var s=EditorSession(document:source);try s.execute(FlattenPreparation.command(source))
    XCTAssertEqual(s.document.selection,source.selection);XCTAssertEqual(s.document.alphaChannels,source.alphaChannels);XCTAssertEqual(s.document.sourceMetadata,source.sourceMetadata);XCTAssertEqual(s.document.layerComps,source.layerComps);XCTAssertEqual(s.document.workingICC,source.workingICC);XCTAssertEqual(s.document.guides,source.guides)
    try s.undo();XCTAssertEqual(s.document,source);try s.redo();XCTAssertTrue(s.document.layers[0].isBackground)
  }
  func testNativeComponentPlanesRetainExactBytesAndUnsupportedStacksDoNotConvert() throws {
    for mode:DocumentColorMode in [.grayscale,.cmyk,.lab] {
      let source=try simple().convertingMode(.init(mode:mode,depth:.u16))
      // The transparent fixture is deliberately rejected before any RGB reinterpretation.
      XCTAssertThrowsError(try FlattenPreparation.prepare(source))
      var opaque=try CraftDocument(width:2,height:1).convertingMode(.init(mode:mode,depth:.u16))
      let native=try XCTUnwrap(opaque.layers[0].nativeMode)
      let result=try FlattenPreparation.prepare(opaque).result
      XCTAssertEqual(result.layers[0].nativeMode,native);XCTAssertEqual(result.modeDescriptor,opaque.modeDescriptor);XCTAssertTrue(result.layers[0].isBackground)
      var copy=opaque.layers[0];copy.id=UUID();opaque.layers.append(copy);let before=opaque
      XCTAssertThrowsError(try FlattenPreparation.prepare(opaque));XCTAssertEqual(opaque,before)
    }
  }
  func testSemanticAndOfficialActionJSONUseTheSameCompositorAndRejectExtraFields() throws {
    let source=try simple(),command=try FlattenPreparation.command(source)
    var recording=EditorSession(document:source);try recording.startActionRecording(name:"Flatten");try recording.execute(command)
    let action=try XCTUnwrap(recording.actionRecording?.snapshot),rendered=try RecordedActionRenderer.prepare(action,in:source)
    var replay=source;try rendered.command.apply(to:&replay);XCTAssertEqual(replay,recording.document)
    for event in ["flattenImage","$FltI"] {
      let program=try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"\(event)\"}]")
      let result=try program.applying(to:source,flattenRenderer:FlattenPreparation.command).session.document
      XCTAssertEqual(result,recording.document)
    }
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"flattenImage\",\"unexpected\":true}]"))
  }
}
