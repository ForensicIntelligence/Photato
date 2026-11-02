import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PcraftShapeImportTests:XCTestCase {
  func file(_ name:String)throws->Data{try PcraftImportTests().fixture(name,folder:"PcraftShapes")}
  func expected(_ bits:String)throws->[[String:Any]]{try XCTUnwrap(JSONSerialization.jsonObject(with:file("expected-\(bits).json"))as?[[String:Any]])}
  func samples(_ layer:Layer,in doc:CraftDocument)throws->([UInt32],[UInt8]) {
    let surface=try Renderer.layerSurface(layer,in:doc);let inverse=try layer.coordinateTransform.inverted();var words:[UInt32]=[],bytes:[UInt8]=[]
    for y in 0..<64{for x in 0..<96{let p=inverse.point(Double(x)+0.5,Double(y)+0.5);let pixel=doc.depth == .f32 ? surface.linearPixel(x:Int(floor(p.x)),y:Int(floor(p.y))):surface.pixel(x:Int(floor(p.x)),y:Int(floor(p.y)))
      for value in [pixel.r,pixel.g,pixel.b,pixel.a]{words.append(value.bitPattern);bytes.append(UInt8((min(1,max(0,value))*255+0.5).rounded(.down)))}}};return(words,bytes)
  }
  func compare(cached:Bool,curveOnly:Bool=false)throws {
    var metrics:[[String:Any]]=[]
    for bits in ["u8","u16","f32"]{let doc=try PcraftImport.read(file("shapes-\(bits).pcraft"));for entry in try expected(bits) where entry["cached"]as?Bool == cached {
      let name=entry["name"]as!String;if !cached && (name=="uncached-curve") != curveOnly{continue}
      let layer=try XCTUnwrap(doc.layers.first{$0.name==name}),actual=try samples(layer,in:doc),wanted=(entry["float_bits"]as![NSNumber]).map(\.uint32Value),rgba=(entry["rgba8"]as![NSNumber]).map(\.uint8Value)
      let count=zip(actual.0,wanted).filter{$0 != $1}.count;metrics.append(["name":name,"depth":bits,"floatWords":wanted.count,"changedWords":count,"changedRGBA8":zip(actual.1,rgba).filter{$0 != $1}.count])
      XCTAssertEqual(actual.0.count,wanted.count);XCTAssertEqual(count,0,"\(bits)/\(name): exact original-source sample words")
    }}
    if let dir=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let url=URL(fileURLWithPath:dir);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys]).write(to:url.appendingPathComponent(cached ? "source-shape-caches.json":curveOnly ? "source-shape-uncached-curve.json":"source-shape-uncached-rectangle.json"))}
  }
  func testSourceLiveRegularOpenBooleanInvertedPaintAndMetadataAtAllDepths()throws {
    for bits in ["u8","u16","f32"]{let doc=try PcraftImport.read(file("shapes-\(bits).pcraft"));XCTAssertEqual(doc.layers.count,13);XCTAssertEqual(doc.patterns?.count,1);XCTAssertEqual(doc.minimumArchiveVersion,68)
      for i in 0..<5{let layer=try XCTUnwrap(doc.layers.first{$0.name=="live-\(i)"}),shape=try XCTUnwrap(layer.shape),definition=try XCTUnwrap(shape.definition);XCTAssertNotNil(shape.importedAppearance?.pixels);XCTAssertNotNil(definition.components[0].pathOverride);XCTAssertEqual(definition.stroke.opacity,0.6);XCTAssertEqual(definition.stroke.widthRelativeDashes,true);XCTAssertEqual(definition.stroke.pathContours,true);XCTAssertEqual(shape.importedAppearance?.vectorRecord,Data("PHOTATO".utf8));XCTAssertNotEqual(definition.components[0].geometry.kind,.custom)}
      let open=try XCTUnwrap(doc.layers.first{$0.name=="open"}?.shape?.definition);XCTAssertFalse(try open.path().components[0].closed);XCTAssertEqual(open.stroke.dash,[1,0.5]);XCTAssertEqual(open.stroke.phase,0.25);XCTAssertEqual(open.stroke.miterLimit,100)
      let even=try XCTUnwrap(doc.layers.first{$0.name=="evenodd"}?.shape?.definition);XCTAssertEqual(even.fillRule,.evenOdd);XCTAssertEqual(try even.path().components.map(\.operation),[.intersect,.join])
      let inverted=try XCTUnwrap(doc.layers.first{$0.name=="inverted"}?.shape?.definition);XCTAssertEqual(inverted.inversionBounds,.init(x:0,y:0,width:96,height:64));XCTAssertEqual(inverted.inverted,true)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc)),doc)
    }
  }
  func testPristineOriginalRustCacheSamplesMatchExactly()throws{try compare(cached:true)}
  func testUncachedOriginalRustRectangleSamplesMatchExactly()throws{try compare(cached:false)}
  func testUncachedOriginalRustCurvedStrokeSamplesMatchExactly()throws{try compare(cached:false,curveOnly:true)}
  func testEditingInvalidatesCacheAndSourceRejectsUnknownInvalidBudgetAndCancellation()async throws {
    let input=try file("shapes-u8.pcraft"),doc=try PcraftImport.read(input),layer=try XCTUnwrap(doc.layers.first{$0.name=="pattern-cache"});var definition=try XCTUnwrap(layer.shape?.definition)
    XCTAssertEqual(try Renderer.layerSurface(layer,in:doc).pixel(x:0,y:0).a,0)
    definition.stroke.opacity=0.25;var edited=doc;try Command.shape(.configure(layer.id,definition)).apply(to:&edited);XCTAssertNil(edited.layers.first{$0.id==layer.id}?.shape?.importedAppearance)
    XCTAssertGreaterThan(try Renderer.layerSurface(edited.layers.first{$0.id==layer.id}!,in:edited).pixel(x:10,y:10).a,0)
    for field in ["unknown","stroke","live"]{let project=try PcraftImportTests().source(input){doc in var layers=doc["layers"]as![[String:Any]],content=layers[0]["content"]as![String:Any];if field=="unknown"{content[field]=true}else if field=="stroke"{var stroke=content[field]as![String:Any];stroke["opacity"]=2;content[field]=stroke}else{content[field]=["kind":"unknown"]};layers[0]["content"]=content;doc["layers"]=layers};XCTAssertThrowsError(try PcraftImportTests().convert(project))}
    XCTAssertThrowsError(try PcraftImport.read(input,rasterByteLimit:1))
    let task=Task{while !Task.isCancelled{await Task.yield()};return try PcraftImport.read(input)};task.cancel();do{_ = try await task.value;XCTFail("Cancelled import")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(try file("shapes-u8.pcraft"),input)
  }
}
