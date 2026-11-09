import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class PcraftArtboardImportTests:XCTestCase {
  func fixture(_ name:String) throws -> Data { try PcraftImportTests().fixture(name,folder:"PcraftArtboards") }
  func changed(_ input:Data,_ edit:(inout [String:Any])->Void) throws -> CraftDocument {
    try PcraftImportTests().convert(PcraftImportTests().source(input,mutate:edit))
  }
  func testFourBackgroundsBoundsPresetsAndClippingAtEveryDepth() throws {
    let expected:[Pixel] = [.white,.black,.clear,Pixel(1,0,1,1)]
    for bits in ["u8","u16","f32"] {
      let data = try fixture("empty-\(bits).pcraft"),doc = try PcraftImport.read(data)
      XCTAssertEqual(doc.artboards.count,4);XCTAssertEqual(doc.layers.count,4)
      XCTAssertEqual(doc.width,220);XCTAssertEqual(doc.height,100)
      let image = try Renderer.composite(doc)
      for (i,board) in doc.artboards.enumerated() {
        XCTAssertEqual(board.artboardBounds,IntRect(x:i*48,y:8,width:40,height:48))
        XCTAssertEqual(board.artboard?.preset,"Owned 40 × 48")
        XCTAssertEqual(board.artboard?.background,expected[i]);XCTAssertEqual(board.group?.expanded,i%2==0)
        let p = bits == "f32" ? image.linearPixel(x:i*48+10,y:20):image.pixel(x:i*48+10,y:20)
        XCTAssertTrue(p.hasSameBits(as:expected[i]))
        XCTAssertEqual(image.pixel(x:i*48+42,y:20).a,0)
      }
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(doc)),doc)
      XCTAssertEqual(try fixture("empty-\(bits).pcraft"),data)
    }
  }
  func testChildrenRemainEditableAndFillCompositesHaveAnalyticalValues() throws {
    let wanted = [Pixel(1,0.5,0.5,1),Pixel(0.5,0,0,1),Pixel(1,0,0,0.5),Pixel(1,0,0.5,1)]
    for bits in ["u8","u16","f32"] {
      let doc = try PcraftImport.read(fixture("filled-\(bits).pcraft")),image = try Renderer.composite(doc)
      XCTAssertEqual(doc.layers.count,8)
      for (i,board) in doc.artboards.enumerated() {
        let child = try XCTUnwrap(doc.children(of:board.id).first)
        guard case .fill(let color) = child.content else { return XCTFail("Fill was flattened") }
        XCTAssertEqual(color,Pixel(1,0,0,1));XCTAssertEqual(child.opacity,0.5)
        XCTAssertEqual(child.x,0);XCTAssertEqual(child.y,0)
        let p = bits == "f32" ? image.linearPixel(x:i*48+10,y:20):image.pixel(x:i*48+10,y:20)
        // Artboard composition retains a Float32 intermediate. Quantization is
        // an encoding boundary, not part of this analytical blend calculation.
        XCTAssertEqual(image.depth,.f32)
        XCTAssertTrue(p.hasSameBits(as:wanted[i]),"\(bits) board\(i): \(p)")
      }
      let board = doc.artboards[0];var session = EditorSession(document:doc)
      var settings = try XCTUnwrap(board.artboard);settings.background = .black
      try session.execute(.artboard(.settings(board.id,settings)))
      XCTAssertEqual(session.document.artboards[0].artboard?.background,.black)
      try session.undo();XCTAssertEqual(session.document,doc);try session.redo()
      XCTAssertEqual(session.document.artboards[0].artboard?.background,.black)
    }
  }
  func testNegativeBoardsKeepLogicalCoordinatesAndExtractEditableChildren() throws {
    for bits in ["u8","u16","f32"] {
      let data = try fixture("negative-\(bits).pcraft"),project = try PcraftProject.read(data),doc = try PcraftImport.read(data)
      XCTAssertEqual(doc.width,240);XCTAssertEqual(doc.height,112)
      XCTAssertEqual(doc.artboardOrigin,.init(x:-20,y:-12))
      XCTAssertEqual(doc.sourceMetadata?["pcraft.manifest"],project.rawManifest)
      for (i,board) in doc.artboards.enumerated() {
        XCTAssertEqual(doc.logicalArtboardBounds(board),IntRect(x:i*48-20,y:-12,width:40,height:48))
        let one = try doc.extractedArtboard(board.id)
        XCTAssertEqual(one.width,40);XCTAssertEqual(one.height,48);XCTAssertEqual(one.layers.count,2)
        XCTAssertEqual(one.artboards[0].artboardBounds,IntRect(x:0,y:0,width:40,height:48))
        XCTAssertEqual(one.layers.first?.name,"Editable red")
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(one)),one)
        XCTAssertNoThrow(try RasterIO.encoded(one,type:.png))
      }
    }
  }
  func testAllSourceSmartCachesAndOriginalsSurviveCanvasRebaseAndExtraction() throws {
    for bits in ["u8","u16","f32"] {
      for name in ["affine-cached","projective-cached","warp-cached","filtermask-cached","mask-cached","nested-cached","shared"] {
        let before = try PcraftImport.read(PcraftImportTests().fixture("\(name)-\(bits).pcraft",folder:"PcraftSmart"))
        let imported = try PcraftImport.read(fixture("\(name)-\(bits).pcraft"))
        XCTAssertEqual(imported.artboards.count,1);XCTAssertEqual(imported.artboardOrigin,.init(x:-7,y:-5))
        for source in before.layers {
          let moved = try XCTUnwrap(imported.layers.first { $0.name == source.name })
          let old = try XCTUnwrap(source.pristineSmartAppearance),cache = try XCTUnwrap(moved.pristineSmartAppearance)
          XCTAssertEqual(cache.pixels,old.pixels);XCTAssertEqual(cache.placedRecord,old.placedRecord)
          XCTAssertEqual(cache.x,old.x+7);XCTAssertEqual(cache.y,old.y+5)
          XCTAssertEqual(moved.smartObject?.data,source.smartObject?.data)
          XCTAssertEqual(moved.coordinateTransform,.translation(7,5)*source.coordinateTransform)
        }
        // A positive board shift without moving its children exercises a nonzero
        // extraction translation, independently of the import's initial rebase.
        var session = EditorSession(document:imported)
        let board = imported.artboards[0],bounds = try XCTUnwrap(board.artboardBounds)
        let origin = imported.artboardOrigin ?? .init()
        try session.execute(.artboard(.resize(board.id,bounds:.init(x:9+origin.x,y:11+origin.y,width:bounds.width,height:bounds.height),moveContents:false)))
        let one = try session.document.extractedArtboard(board.id)
        for source in imported.layers where source.smartObject != nil {
          let moved = try XCTUnwrap(one.layers.first { $0.id == source.id }),old = try XCTUnwrap(source.pristineSmartAppearance)
          let cache = try XCTUnwrap(moved.pristineSmartAppearance)
          XCTAssertEqual(cache.pixels,old.pixels);XCTAssertEqual(cache.x,old.x-9);XCTAssertEqual(cache.y,old.y-11)
          XCTAssertEqual(cache.placedRecord,old.placedRecord);XCTAssertEqual(moved.smartObject?.data,source.smartObject?.data)
        }
        XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(one)),one)
      }
    }
  }
  func testStaleCachesStayStaleAndSourcePointTypeRemainsPristine() throws {
    var doc = try PcraftImport.read(fixture("affine-cached-u8.pcraft"))
    let index = try XCTUnwrap(doc.layers.firstIndex { $0.smartObject != nil })
    doc.layers[index].affine = .scale(1.25,1.5)
    XCTAssertNil(doc.layers[index].pristineSmartAppearance)
    let board = try XCTUnwrap(doc.layers.firstIndex { $0.artboard != nil });doc.layers[board].x = -3;doc.layers[board].y = -4
    let reframed = try doc.fittingArtboardCanvas()
    XCTAssertNil(reframed.layers[index].pristineSmartAppearance)
    var text = TextContent(text:"Owned point type",fontName:"Helvetica",size:12,color:.white)
    let cache = try Surface(width:12,height:8,fill:Pixel(0,1,1,1))
    text.importedAppearance = .init(content:text,pixels:cache,x:-3,y:-2,textTransform:.translation(0.25,9.5))
    var child = Layer(name:"Source point type",content:.text(text));child.x = -3;child.y = -2
    var group = Layer(name:"Source board",content:.group(.init()))
    var content = try XCTUnwrap(group.group);content.artboard = .init(width:40,height:30,background:.clear);group.content = .group(content);group.x = -5;group.y = -7;child.parentID = group.id
    var source = try CraftDocument(width:32,height:24);source.layers = [child,group];source.activeLayerID = child.id
    let result = try source.fittingArtboardCanvas()
    let copied = try XCTUnwrap(result.layers[0].typeContent)
    XCTAssertNil(copied.layoutWidth);XCTAssertNotNil(copied.pristineSourceAppearance)
    XCTAssertEqual(copied.importedAppearance,text.importedAppearance)
    XCTAssertEqual(try result.layers[0].sourceTypeTransform(),.translation(5,7)*(try XCTUnwrap(child.sourceTypeTransform())))
    XCTAssertEqual(try Renderer.layerSurface(result.layers[0],in:result),cache)
    let one = try result.extractedArtboard(group.id)
    XCTAssertNotNil(one.layers[0].typeContent?.pristineSourceAppearance)
    XCTAssertEqual(try Renderer.layerSurface(one.layers[0],in:one),cache)
  }
  func testInvalidFieldsGeometryHierarchyAndCancellationRejectAtomically() async throws {
    let input = try fixture("empty-u8.pcraft")
    let edits:[(inout [String:Any])->Void] = [
      { d in var ls=d["layers"] as! [[String:Any]];var c=ls[0]["content"] as! [String:Any];var b=c["artboard"] as! [String:Any];b["future"]=true;c["artboard"]=b;ls[0]["content"]=c;d["layers"]=ls },
      { d in var ls=d["layers"] as! [[String:Any]];var c=ls[0]["content"] as! [String:Any];var b=c["artboard"] as! [String:Any];b["background"]="guessed";c["artboard"]=b;ls[0]["content"]=c;d["layers"]=ls },
      { d in var ls=d["layers"] as! [[String:Any]];var c=ls[0]["content"] as! [String:Any];var b=c["artboard"] as! [String:Any];b["rect"]=["x0":0,"y0":0,"x1":0,"y1":48];c["artboard"]=b;ls[0]["content"]=c;d["layers"]=ls },
      { d in var ls=d["layers"] as! [[String:Any]];ls[0]["clipped"]=true;d["layers"]=ls },
      { d in let ls=d["layers"] as! [[String:Any]];var parent=ls[0],c=parent["content"] as! [String:Any];c["artboard"]=NSNull();c["children"]=[ls[1]];parent["content"]=c;d["layers"]=[parent] }
    ]
    for edit in edits { XCTAssertThrowsError(try changed(input,edit)) }
    let worker = Task { try Task.checkCancellation();return try PcraftImport.read(input) };worker.cancel()
    do { _ = try await worker.value;XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(try fixture("empty-u8.pcraft"),input)
  }
  func testMaximumSparseCanvasArtboardKeepsAllLogicalExtent() throws {
    let doc = try changed(fixture("empty-u8.pcraft")) { d in
      d["size"]=["width":1,"height":1]
      var groups=d["layers"] as! [[String:Any]],group=groups[0],content=group["content"] as! [String:Any],board=content["artboard"] as! [String:Any]
      board["rect"]=["x0":-1,"y0":-1,"x1":299999,"y1":299999];content["artboard"]=board;group["content"]=content;groups=[group];d["layers"]=groups
    }
    XCTAssertEqual(doc.width,300000);XCTAssertEqual(doc.height,300000)
    XCTAssertEqual(doc.logicalArtboardBounds(doc.artboards[0]),IntRect(x:-1,y:-1,width:300000,height:300000))
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(doc)),doc)
  }
}
