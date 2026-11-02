import Foundation
import XCTest
@testable import PhotoCraftCore

final class LightingTests:XCTestCase {
  struct Entry:Decodable {let name:String,depth:String,width:Int,height:Int,params:LightingSettings,input:String,expected:String}
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/Lighting")
  func data(_ name:String)throws->Data{try Data(contentsOf:root.appendingPathComponent(name))}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  func words(_ data:Data)->[UInt32]{data.withUnsafeBytes{b in (0..<(data.count/4)).map{UInt32(littleEndian:b.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}}
  func surface(_ e:Entry)throws->Surface{let raw=words(try data(e.input));var s=try Surface(width:e.width,height:e.height,depth:.f32,colorEncoding:.linearRGB);for y in 0..<e.height{for x in 0..<e.width{let i=(y*e.width+x)*4;s.setLinearPixel(x:x,y:y,Pixel(Float(bitPattern:raw[i]),Float(bitPattern:raw[i+1]),Float(bitPattern:raw[i+2]),Float(bitPattern:raw[i+3])))}};return s}
  func samples(_ s:Surface)->[UInt32]{var a=[UInt32]();for y in 0..<s.height{for x in 0..<s.width{let p=s.linearPixel(x:x,y:y);a += [p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern]}};return a}
  func testIndependentOriginalFloat32LightingWordsExactly()throws{
    var rows=[[String:Any]]()
    for e in try entries() where e.depth=="f32"{let input=try surface(e),result=try LightingEngine.render(input,settings:e.params),actual=samples(result),wanted=words(try data(e.expected)),changed=zip(actual,wanted).filter{$0 != $1}.count;XCTAssertEqual(changed,0,"\(e.name): strict original Lighting Effects words");XCTAssertEqual(try surface(e),input);rows.append(["name":e.name,"words":wanted.count,"changedWords":changed])}
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("lighting-core-words.json"))}
  }
  func testPresetsStrictSchemaAndClosedFormAmbientHDR()throws{
    var source=try Surface(width:1,height:1,depth:.f32,colorEncoding:.linearRGB);source.setLinearPixel(x:0,y:0,Pixel(0.5,0.25,2.5,0.4));var s=LightingSettings();s.lights=[];s.ambience=100
    let p=try LightingEngine.render(source,settings:s).linearPixel(x:0,y:0);XCTAssertTrue(p.hasSameBits(as:Pixel(0.25,0.125,1.25,0.4)))
    for preset in LightingSettings.Preset.allCases{let s=preset.settings;try s.validate();XCTAssertEqual(try LightingSettings.decodeJSON(s.presetData()),s)}
    for bad in ["{\"unknown\":1}","{\"whiteIsHigh\":1}","{\"gloss\":true}","{\"texture\":\"missing\"}","{\"lights\":[{\"x\":true}]}","{\"lights\":[{\"kind\":\"missing\"}]}","{\"lights\":[{\"color\":[1,0]}]}","{\"lights\":[{\"intensity\":101}]}","{\"texture\":\"alphaChannel\"}"]{XCTAssertThrowsError(try LightingSettings.decodeJSON(Data(bad.utf8)),bad)}
    s.lights=Array(repeating:.init(),count:65);XCTAssertThrowsError(try s.validate());XCTAssertThrowsError(try LightingSettings.decodeJSON(Data(repeating:32,count:LightingSettings.maximumPresetBytes+1)))
    var normal=LightingSettings();normal.texture = .none;var bump=normal;bump.texture = .red
    let reference=IntRect(x:0,y:0,width:1,height:1);XCTAssertEqual(try LightingEngine.render(source,settings:normal,referenceBounds:reference),try LightingEngine.render(source,settings:bump,referenceBounds:reference),"A one-pixel texture reference has no gradient")
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:LightingSettings.apiSchema));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:LightingSettings.apiCapabilities))
    XCTAssertEqual(try RasterFilter.decodeJSON(Data("{\"kind\":\"lightingEffects\"}".utf8)),RasterFilter(.lightingEffects));XCTAssertThrowsError(try RasterFilter.decodeJSON(Data("{\"kind\":\"lightingEffects\",\"radius\":1}".utf8)))
  }
  func testSelectionProtectionCancellationAndNative72()async throws{
    let e=try XCTUnwrap(entries().first{$0.depth=="f32"}),source=try surface(e);var d=try CraftDocument(width:e.width,height:e.height,depth:.f32);d.layers[0].content = .raster(source);d.selection=IntRect(x:4,y:3,width:7,height:5);let id=d.layers[0].id
    var session=EditorSession(document:d);try session.execute(.applyFilter(id,.init(.lightingEffects)));guard case .raster(let changed)=session.document.layers[0].content else{return XCTFail()}
    for y in 0..<source.height{for x in 0..<source.width where !(4..<11).contains(x) || !(3..<8).contains(y){XCTAssertTrue(changed.linearPixel(x:x,y:y).hasSameBits(as:source.linearPixel(x:x,y:y)))}}
    try session.undo();XCTAssertTrue(session.document==d);d.selection=nil;d.layers[0].smartObject=try SmartObject(fileName:"Owned.png",mediaType:"image/png",data:Data([1]),width:e.width,height:e.height)
    var smart=EditorSession(document:d);try smart.execute(.applyFilter(id,.init(.lightingEffects)));XCTAssertEqual(smart.document.minimumArchiveVersion,72);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(smart.document))==smart.document);try smart.undo();XCTAssertTrue(smart.document==d)
    d.layers[0].locked=true;var locked=EditorSession(document:d);XCTAssertThrowsError(try locked.execute(.applyFilter(id,.init(.lightingEffects))));XCTAssertTrue(locked.document==d)
    let task=Task.detached{withUnsafeCurrentTask{$0?.cancel()};return try LightingEngine.render(source,settings:.init())};do{_ = try await task.value;XCTFail("Cancelled lighting must reject")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertThrowsError(try LightingEngine.render(Surface(width:300_000,height:300_000,depth:.f32),settings:.init()))
  }
  func testSavedAlphaTextureIdentityReferencesAndHistory()throws{
    var pixels=try Surface(width:8,height:6,depth:.f32,colorEncoding:.linearRGB),alpha=try Surface(width:8,height:6,depth:.f32)
    for y in 0..<6{for x in 0..<8{let a:Float=(x+y)%3==0 ? 0.4:1;pixels.setLinearPixel(x:x,y:y,Pixel(0.3,0.6,1.5,a));alpha.setPixel(x:x,y:y,Pixel(a,a,a,1))}}
    var settings=LightingSettings();settings.texture = .alpha;let expected=try LightingEngine.render(pixels,settings:settings);let channel=AlphaChannel(name:"Owned bump",pixels:alpha);settings.texture = .alphaChannel;settings.textureChannelID=channel.id
    XCTAssertEqual(try LightingEngine.render(pixels,settings:settings,texture:alpha),expected)
    var d=try CraftDocument(width:8,height:6,depth:.f32);d.layers[0].content = .raster(pixels);d.alphaChannels=[channel];d.layers[0].smartObject=try SmartObject(fileName:"Owned.png",mediaType:"image/png",data:Data([1]),width:8,height:6)
    var f=RasterFilter(.lightingEffects);f.lighting=settings;var session=EditorSession(document:d);try session.execute(.applyFilter(d.layers[0].id,f));let edited=session.document
    XCTAssertThrowsError(try session.execute(.channel(.delete(channel.id))));XCTAssertTrue(session.document==edited)
    try session.execute(.channel(.rename(channel.id,"Renamed bump")));XCTAssertEqual(try SmartFilterEngine.renderedLayer(session.document.layers[0],in:session.document).content,try SmartFilterEngine.renderedLayer(edited.layers[0],in:edited).content)
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encode(session.document))==session.document);try session.undo();try session.undo();XCTAssertTrue(session.document==d)
    settings.textureChannelID=UUID();XCTAssertThrowsError(try settings.validateReferences(in:d));XCTAssertThrowsError(try LightingEngine.render(pixels,settings:settings))
  }
}
