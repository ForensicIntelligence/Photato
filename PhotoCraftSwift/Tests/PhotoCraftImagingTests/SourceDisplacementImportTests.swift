import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class SourceDisplacementImportTests:XCTestCase {
  struct Entry:Decodable {let name:String,depth:String,width:Int,height:Int,horizontal:Float,vertical:Float,fit:DistortionSettings.Fit,edge:DistortionSettings.Edge,mapWidth:Int,mapHeight:Int,mapChannels:Int,mapSamples:String,mapProject:String,cachedBound:Bool,source:String,input:String,unresolvedExpected:String,boundExpected:String,cached:String,uncached:String}
  func data(_ name:String)throws->Data{try PcraftImportTests().fixture(name,folder:"SourceDisplacement")}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  func words(_ data:Data)->[UInt32]{data.withUnsafeBytes{b in (0..<(b.count/4)).map{UInt32(littleEndian:b.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}}
  func samples(_ layer:Layer,_ e:Entry)throws->[UInt32]{guard case .raster(let s)=layer.content else{throw CraftError.invalid("Expected displacement pixels.")};var out=[UInt32]();for y in 0..<e.height{for x in 0..<e.width{let xx=x-layer.x,yy=y-layer.y,p=xx>=0 && yy>=0 && xx<s.width && yy<s.height ? (s.depth == .f32 ? s.linearPixel(x:xx,y:yy):s.pixel(x:xx,y:yy)):.clear;out += [p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern]}};return out}
  func map(_ e:Entry)throws->FloatDisplacementMap{let m=try FloatDisplacementMap(width:e.mapWidth,height:e.mapHeight,channels:e.mapChannels,samples:data(e.mapSamples),name:e.name);try m.validate();return m}
  func capture(_ rows:[[String:Any]],_ name:String)throws{if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(name))}}
  func testCachedOriginalAppearanceReferencesNative73AndHistory()throws {
    var rows=[[String:Any]]()
    for e in try entries(){let input=try data(e.cached),d=try PcraftImport.read(input),layer=try XCTUnwrap(d.layers.first),cache=try XCTUnwrap(layer.originalSmartAppearanceLayer()),wanted=words(try data(e.cachedBound ? e.boundExpected:e.unresolvedExpected)),actual=try samples(cache,e),changed=zip(actual,wanted).filter{$0 != $1}.count
      XCTAssertEqual(changed,0,"\(e.name)/\(e.depth): original cache");let s=try XCTUnwrap(layer.smartFilters?.filters.first?.filter.distortion);XCTAssertEqual(s.horizontalScale,Double(e.horizontal));XCTAssertEqual(s.verticalScale,Double(e.vertical));XCTAssertEqual(s.fit,e.fit);XCTAssertEqual(s.edge,e.edge);XCTAssertNotNil(s.source);XCTAssertNil(s.source?.map);XCTAssertNil(s.map);XCTAssertEqual(d.minimumArchiveVersion,73)
      if e.name=="path"{XCTAssertEqual(s.source?.reference.path,"Owned missing map.psd")};if e.name=="document-name"{XCTAssertEqual(s.source?.reference.documentName,"Owned map document");XCTAssertEqual(s.source?.reference.layerID,17)};if e.name=="document-index"{XCTAssertEqual(s.source?.reference.documentIndex,1)}
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(d))==d);var session=EditorSession(document:d);try session.execute(SmartObjectIO.rasterizationCommand(layer,in:d));XCTAssertEqual(try Renderer.composite(session.document),try Renderer.composite(d));try session.undo();XCTAssertTrue(session.document==d);XCTAssertEqual(try data(e.cached),input);rows.append(["name":e.name,"depth":e.depth,"words":wanted.count,"changedWords":changed])
    };try capture(rows,"source-displacement-cached-words.json")
  }
  func testUnresolvedSmartProgramsMatchOriginalIdentityExactly()throws {
    var rows=[[String:Any]]()
    for e in try entries(){let d=try PcraftImport.read(data(e.uncached)),layer=try XCTUnwrap(d.layers.first);var noOp=EditorSession(document:d);try noOp.execute(.smartFilters(layer.id,layer.smartFilters));XCTAssertTrue(noOp.document==d);XCTAssertTrue(noOp.undoStack.isEmpty);let wanted=words(try data(e.unresolvedExpected)),actual=try samples(SmartFilterEngine.renderedLayer(layer,in:d),e),changed=zip(actual,wanted).filter{$0 != $1}.count;XCTAssertEqual(changed,0,"\(e.name)/\(e.depth): strict unresolved original stage");rows.append(["name":e.name,"depth":e.depth,"words":wanted.count,"changedWords":changed])};try capture(rows,"source-displacement-unresolved-words.json")
  }
  func testExplicitFloatBindingNativeHistoryAndAtomicMissingMapGuards()throws {
    XCTAssertEqual(PcraftImport.sourceSmartFilterCommands.count,110);XCTAssertTrue(PcraftImport.unsupportedSourceSmartFilterCommands.isEmpty)
    for e in try entries() where ["path","fractional","hdr-map","transparent-edges"].contains(e.name){let input=try data(e.cached),d=try PcraftImport.read(input),id=d.layers[0].id;var session=EditorSession(document:d),stack=try XCTUnwrap(d.layers[0].smartFilters);stack.filters[0].opacity=0.5;XCTAssertThrowsError(try session.execute(.smartFilters(id,stack)));XCTAssertTrue(session.document==d)
      stack=try XCTUnwrap(d.layers[0].smartFilters);stack.filters[0].filter.distortion?.source?.map=try map(e);try session.execute(.smartFilters(id,stack));let bound=session.document;XCTAssertEqual(bound.layers[0].smartObject,d.layers[0].smartObject);XCTAssertNil(bound.layers[0].pristineSmartAppearance);XCTAssertEqual(bound.minimumArchiveVersion,73);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(bound))==bound);try session.undo();XCTAssertTrue(session.document==d);try session.redo();XCTAssertTrue(session.document==bound);XCTAssertEqual(try data(e.cached),input)
      let mapDocument=try PcraftImport.read(data(e.mapProject));XCTAssertEqual(try FloatDisplacementMap.read(Renderer.composite(mapDocument),name:e.name).samples,try data(e.mapSamples))
    }
  }
  func testBoundProgramsMatchIndependentOriginalMapWordsStrictly()throws {
    var rows=[[String:Any]]()
    for e in try entries(){var d=try PcraftImport.read(data(e.uncached));d.layers[0].smartFilters?.filters[0].filter.distortion?.source?.map=try map(e);let wanted=words(try data(e.boundExpected)),actual=try samples(SmartFilterEngine.renderedLayer(d.layers[0],in:d),e),changed=zip(actual,wanted).filter{$0 != $1}.count;XCTAssertEqual(changed,0,"\(e.name)/\(e.depth): strict original bound map");let differences=zip(actual,wanted).enumerated().filter{$0.element.0 != $0.element.1};let maximum=differences.map{abs(Double(Float(bitPattern:$0.element.0))-Double(Float(bitPattern:$0.element.1)))}.max() ?? 0;let first=differences.prefix(16).map{["index":$0.offset,"actual":$0.element.0,"expected":$0.element.1] as [String:Any]};rows.append(["name":e.name,"depth":e.depth,"words":wanted.count,"changedWords":changed,"maximumAbsoluteDifference":maximum,"firstDifferences":first])};try capture(rows,"source-displacement-bound-words.json")
  }
}
