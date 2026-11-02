import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class SourceLayerEffectTests:XCTestCase {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SourceEffects")
  func bytes(_ name:String)throws->Data {try Data(contentsOf:root.appendingPathComponent(name))}
  func words(_ data:Data)->[UInt32] {data.withUnsafeBytes{p in (0..<(data.count/4)).map{UInt32(littleEndian:p.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}}
  func surface(_ name:String,width:Int,height:Int,depth:PixelDepth)throws->Surface {
    let values=words(try bytes(name));XCTAssertEqual(values.count,width*height*4)
    var s=try Surface(width:width,height:height,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<height {for x in 0..<width {let i=(y*width+x)*4,p=Pixel(Float(bitPattern:values[i]),Float(bitPattern:values[i+1]),Float(bitPattern:values[i+2]),Float(bitPattern:values[i+3]));if depth == .f32{s.setLinearPixel(x:x,y:y,p)}else{s.setPixel(x:x,y:y,p)}}};return s
  }
  func rows()throws->[[String:Any]] {try XCTUnwrap(JSONSerialization.jsonObject(with:bytes("cases.json")) as? [[String:Any]])}
  func fixture(_ row:[String:Any])throws->(CraftDocument,Surface) {
    let width=row["width"] as! Int,height=row["height"] as! Int,depth:PixelDepth=row["depth"] as! String == "u8" ? .u8:row["depth"] as! String == "u16" ? .u16:.f32
    var d=try CraftDocument(width:width,height:height,depth:depth)
    d.layers[0].content = .raster(try surface(row["input"] as! String,width:width,height:height,depth:depth));d.layers[0].opacity=(row["opacity"] as! NSNumber).floatValue
    d.layers[0].style=try LayerStyle.decodeJSON(JSONSerialization.data(withJSONObject:row["native"]!));d.globalLight=GlobalLight(angle:113.375,altitude:41.25)
    let tile=try surface("pattern.rgba32",width:4,height:3,depth:.u8);d.patterns=[try RasterPattern(name:"Owned FX",surface:tile,id:"owned-fx")];try d.validate()
    // Working buffers use the document's transfer domain, regardless of their f32 storage.
    var base=try surface(row["backdrop"] as! String,width:width,height:height,depth:.f32)
    if depth != .f32 {base=try Surface(width:width,height:height,depth:.f32,colorEncoding:.sRGB);let values=words(try bytes(row["backdrop"] as! String));for y in 0..<height{for x in 0..<width{let i=(y*width+x)*4;base.setPixel(x:x,y:y,Pixel(Float(bitPattern:values[i]),Float(bitPattern:values[i+1]),Float(bitPattern:values[i+2]),Float(bitPattern:values[i+3])))}}}
    return(d,base)
  }
  func testAllOriginalEffectReferenceWordsExactly()throws {
    var metrics=[[String:Any]](),projectMetrics=[[String:Any]]()
    let entries=try rows();XCTAssertEqual(entries.count,138)
    for row in entries {
      let(d,base)=try fixture(row),region=IntRect(x:0,y:0,width:d.width,height:d.height),output=try SourceLayerStyleRenderer.composite(d.layers[0],in:d,over:base,region:region,frameOverride:region),expected=words(try bytes(row["expected"] as! String));var actual=[UInt32]()
      for y in 0..<d.height {for x in 0..<d.width {let p=d.depth == .f32 ? output.linearPixel(x:x,y:y):output.pixel(x:x,y:y);actual += [p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern]}}
      let changed=zip(actual,expected).filter{$0 != $1}.count;XCTAssertEqual(changed,0,"\(row["name"]!)/\(row["depth"]!): strict original effect stack")
      metrics.append(["name":row["name"]!,"depth":row["depth"]!,"words":expected.count,"changedWords":changed,"firstDifferences":actual.indices.filter{actual[$0] != expected[$0]}.prefix(4).map{["index":$0,"actual":actual[$0],"expected":expected[$0]]}])
      let imported=try PcraftImport.read(bytes(row["project"] as! String)),merged=try Renderer.composite(imported),projectExpected=words(try bytes(row["projectExpected"] as! String));var projectActual=[UInt32]()
      for y in 0..<imported.height {for x in 0..<imported.width {let p=imported.depth == .f32 ? merged.linearPixel(x:x,y:y):merged.pixel(x:x,y:y);projectActual += [p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern]}}
      let projectChanged=zip(projectActual,projectExpected).filter{$0 != $1}.count;XCTAssertEqual(projectChanged,0,"\(row["name"]!)/\(row["depth"]!): strict original source project")
      projectMetrics.append(["name":row["name"]!,"depth":row["depth"]!,"words":projectExpected.count,"changedWords":projectChanged])
    }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {let directory=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("source-effect-words.json"));try JSONSerialization.data(withJSONObject:projectMetrics,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("source-effect-project-words.json"))}
  }
  func testRegionRenderingLeavesUnrequestedBackdropUntouched()throws {
    let row=try XCTUnwrap(rows().first{$0["name"] as? String == "multiple-stacks" && $0["depth"] as? String == "u8"}), (d,base)=try fixture(row)
    let full=try LayerStyleRenderer.composite(d.layers[0],in:d,over:base,region:IntRect(x:0,y:0,width:d.width,height:d.height)),region=IntRect(x:9,y:7,width:8,height:6),part=try LayerStyleRenderer.composite(d.layers[0],in:d,over:base,region:region)
    for y in 0..<d.height {for x in 0..<d.width {let inside=x>=9 && x<17 && y>=7 && y<13;XCTAssertEqual(part.pixel(x:x,y:y),inside ? full.pixel(x:x,y:y):base.pixel(x:x,y:y))}}
  }
  func testNativeDispatchFillLayerAndOverallOpacity()throws {
    var d=try CraftDocument(width:12,height:12);var pixels=try Surface(width:12,height:12);pixels.setPixel(x:5,y:5,Pixel(0,1,0));d.layers[0].content = .raster(pixels)
    var effect=LayerEffect(.colorOverlay);effect.opacity=1;effect.color=Pixel(1,0,0);effect.advanced=LayerEffectAdvanced();var style=LayerStyle(effects:[effect]);style.fillOpacity=0;d.layers[0].style=style;d.layers[0].opacity=0.5
    let background=Layer(name:"Background",content:.fill(Pixel(0,0,1)));d.layers.insert(background,at:0)
    let output=try Renderer.composite(d);XCTAssertEqual(output.pixel(x:5,y:5),Pixel(0.5,0,0.5));XCTAssertEqual(output.pixel(x:0,y:0),Pixel(0,0,1))
  }
  func testUnresolvedPatternDoesNotSubstituteDocumentArtwork()throws {
    let row=try XCTUnwrap(rows().first{$0["name"] as? String == "pattern-unresolved" && $0["depth"] as? String == "u8"});var(d,base)=try fixture(row);let region=IntRect(x:0,y:0,width:d.width,height:d.height)
    let missing=try LayerStyleRenderer.composite(d.layers[0],in:d,over:base,region:region);d.layers[0].style?.effects=[]
    XCTAssertEqual(try missing.rgbaData(depth:.u16),try LayerStyleRenderer.composite(d.layers[0],in:d,over:base,region:region).rgbaData(depth:.u16))
  }
  func testCancelledStyleRenderingDoesNotMutateSource()async throws {
    let(d,base)=try fixture(XCTUnwrap(rows().first));let task=Task.detached {withUnsafeCurrentTask{$0?.cancel()};return try LayerStyleRenderer.composite(d.layers[0],in:d,over:base,region:IntRect(x:0,y:0,width:d.width,height:d.height))}
    do {_ = try await task.value;XCTFail("Cancelled effects must stop")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(d.layers[0].style?.effects.count,1)
  }
}
