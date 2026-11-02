import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PcraftFilterImportTests:XCTestCase {
  struct Entry:Decodable {let name:String,command:String,depth:String,supported:Bool,cached:String,uncached:String,expected:String,width:Int,height:Int}
  func data(_ name:String)throws->Data{try PcraftImportTests().fixture(name,folder:"PcraftFilters")}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  func words(_ entry:Entry,_ layer:Layer)throws->[UInt32] {
    guard case .raster(let pixels)=layer.content else{throw CraftError.invalid("Expected rendered filter pixels.")}
    var result=[UInt32]();result.reserveCapacity(entry.width*entry.height*4)
    for y in 0..<entry.height{for x in 0..<entry.width{
      let xx=x-layer.x,yy=y-layer.y
      let pixel=xx>=0 && yy>=0 && xx<pixels.width && yy<pixels.height ? (pixels.depth == .f32 ? pixels.linearPixel(x:xx,y:yy):pixels.pixel(x:xx,y:yy)):.clear
      result += [pixel.r.bitPattern,pixel.g.bitPattern,pixel.b.bitPattern,pixel.a.bitPattern]
    }};return result
  }
  func expected(_ entry:Entry)throws->[UInt32] {
    let bytes=try data(entry.expected);XCTAssertEqual(bytes.count,entry.width*entry.height*16)
    return bytes.withUnsafeBytes{raw in (0..<(bytes.count/4)).map{UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}
  }
  func capture(_ rows:[[String:Any]],name:String)throws {
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
      try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(name))
    }
  }
  func testCatalogueMatchesIndependentOriginalDeclarationsAndDelegatedGallery()throws {
    let catalogue=try XCTUnwrap(JSONSerialization.jsonObject(with:data("catalogue.json")) as? [String:Any])
    let mapped=try XCTUnwrap(catalogue["mapped_commands"] as? [String]),original=try XCTUnwrap(catalogue["original_commands"] as? [String]),unmapped=try XCTUnwrap(catalogue["unmapped_commands"] as? [String])
    XCTAssertEqual(Set(PcraftImport.sourceSmartFilterCommands),Set(mapped).union(["filter.render.relight","filter.render.lightingEffects","filter.distort.displace"]));XCTAssertEqual(mapped.count,107);XCTAssertEqual(original.count,110)
    XCTAssertEqual(Set(PcraftImport.unsupportedSourceSmartFilterCommands),Set(unmapped).subtracting(["filter.render.relight","filter.render.lightingEffects","filter.distort.displace"]));XCTAssertEqual(Set(mapped).union(unmapped),Set(original))
    XCTAssertEqual(Set(try entries().filter(\.supported).map(\.command)),Set(mapped))
  }
  func testAllOriginalSavedAppearancesMatchExactWords()throws {
    var results=[[String:Any]]()
    for entry in try entries() where entry.supported {
      let input=try data(entry.cached),doc=try PcraftImport.read(input),layer=try XCTUnwrap(doc.layers.first),cached=try XCTUnwrap(layer.originalSmartAppearanceLayer())
      let actual=try words(entry,cached),wanted=try expected(entry),changed=zip(actual,wanted).filter{$0 != $1}.count
      XCTAssertEqual(changed,0,"\(entry.name)/\(entry.depth): exact original cached filter words")
      XCTAssertEqual(layer.smartFilters?.filters.count,1);XCTAssertEqual(layer.smartFilters?.filters.first?.opacity,0.75);XCTAssertTrue(layer.smartFilters?.filters.first?.enabled == true)
      results.append(["name":entry.name,"command":entry.command,"depth":entry.depth,"words":wanted.count,"changedWords":changed])
      XCTAssertEqual(try data(entry.cached),input)
    }
    try capture(results,name:"source-filter-cached-words.json")
  }
  func testUncachedProgramsMatchStrictOriginalEngineWords()throws {
    var results=[[String:Any]]()
    for entry in try entries() where entry.supported {
      do {
        let doc=try PcraftImport.read(data(entry.uncached)),layer=try XCTUnwrap(doc.layers.first)
        let projected=try SmartFilterEngine.renderedLayer(layer,in:doc),actual=try words(entry,projected),wanted=try expected(entry),changed=zip(actual,wanted).filter{$0 != $1}.count
        results.append(["name":entry.name,"command":entry.command,"depth":entry.depth,"words":wanted.count,"changedWords":changed])
        XCTAssertEqual(changed,0,"\(entry.name)/\(entry.depth): strict original uncached filter words")
      }catch{results.append(["name":entry.name,"command":entry.command,"depth":entry.depth,"error":String(describing:error)]);XCTFail("\(entry.name)/\(entry.depth): original uncached render failed: \(error)")}
    }
    try capture(results,name:"source-filter-uncached-words.json")
  }
  func testTypedOriginalControlsArchiveHistoryAndSourcePreservation()throws {
    for entry in try entries() where entry.supported {
      let input=try data(entry.cached),doc=try PcraftImport.read(input),layer=try XCTUnwrap(doc.layers.first),source=try XCTUnwrap(layer.smartObject)
      XCTAssertEqual(doc.minimumArchiveVersion,70);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(doc)) == doc)
      let child=try SmartObjectIO.sourceDocument(source);XCTAssertEqual(child.width,16);XCTAssertEqual(child.height,12)
      var session=EditorSession(document:doc);var stack=try XCTUnwrap(layer.smartFilters);stack.enabled=false
      try session.execute(.smartFilters(layer.id,stack));XCTAssertEqual(session.undoStack.count,1);XCTAssertNil(session.document.layers.first?.pristineSmartAppearance)
      try session.undo();XCTAssertTrue(session.document == doc);XCTAssertEqual(session.document.layers.first?.smartObject?.data,source.data);XCTAssertEqual(try data(entry.cached),input)
      let filter=try XCTUnwrap(stack.filters.first?.filter)
      if entry.name=="filter-other-hsbHsl-custom"{XCTAssertEqual(filter.otherVideo?.inputMode,.hsb);XCTAssertEqual(filter.otherVideo?.outputMode,.rgb)}
      if entry.name=="filter-other-minimum-custom"{XCTAssertEqual(filter.otherVideo?.preserve,.roundness);XCTAssertEqual(filter.otherVideo?.radius,1.5)}
      if entry.name=="filter-noise-addNoise-custom"{XCTAssertEqual(filter.seed,UInt32.max);XCTAssertEqual(filter.distribution,.gaussian);XCTAssertTrue(filter.monochromatic)}
      if entry.name=="filter-distort-shear-custom"{XCTAssertEqual(filter.distortion?.edge,.repeatEdge);XCTAssertEqual(filter.distortion?.points.count,3);XCTAssertEqual(filter.distortion?.points[1].offset,Double(Float(0.3)))}
      if entry.name=="filter-blurGallery-pathBlur-custom"{XCTAssertEqual(filter.gallery?.paths.first?.points.count,3);XCTAssertEqual(filter.gallery?.paths.first?.curved,false);XCTAssertEqual(filter.gallery?.paths.first?.taper,30)}
      if entry.name=="filter-gallery-glass-custom"{XCTAssertEqual(filter.artistic?.effects.first?.values["texture"],2);XCTAssertEqual(filter.artistic?.effects.first?.values["invert"],1)}
      if entry.name=="gallery-stack"{XCTAssertEqual(filter.artistic?.effects.count,2);XCTAssertEqual(filter.artistic?.effects.last?.visible,false);XCTAssertEqual(filter.artistic?.effects.first?.values["numberOfLevels"],5)}
    }
  }
  func testUnsupportedContextsRangesAndFieldsRejectWithoutChangingOriginals()throws {
    for entry in try entries() where !entry.supported {for file in [entry.cached,entry.uncached]{let input=try data(file);if ["filter.render.relight","filter.render.lightingEffects","filter.distort.displace","filter.distort.wave"].contains(entry.command){XCTAssertNoThrow(try PcraftImport.read(input))}else{XCTAssertThrowsError(try PcraftImport.read(input),"\(entry.name)/\(entry.depth)")};XCTAssertEqual(try data(file),input)}}
  }
}
