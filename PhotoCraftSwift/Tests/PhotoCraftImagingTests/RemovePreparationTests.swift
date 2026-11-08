import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RemovePreparationTests: XCTestCase {
  func fixture(_ depth:PixelDepth = .u8) throws -> CraftDocument {
    var doc = try CraftDocument(width:24,height:24,depth:depth)
    var pixels = try Surface(width:24,height:24,depth:depth,fill:Pixel(0.25,0.25,0.25))
    for y in 10..<14 { for x in 10..<14 {
      if depth == .f32 { pixels.setLinearPixel(x:x,y:y,Pixel(2,0,0,1)) }
      else { pixels.setPixel(x:x,y:y,Pixel(1,0,0,1)) }
    } }
    doc.layers[0].content = .raster(pixels); doc.layers[0].locked = false
    return doc
  }
  func testLoopSubtractAndSelectionProtectionUseOrderedCoverage() throws {
    var doc = try fixture(); doc.selection = .init(x:0,y:0,width:12,height:24)
    var settings = RemoveToolSettings(); settings.removeAfterEachStroke = false
    let loop = RemoveStroke(size:1,points:[[7,7],[17,7],[17,17],[7,17],[7.1,7.1]])
    XCTAssertTrue(loop.closesLoop)
    let subtract = RemoveStroke(size:3,subtract:true,points:[[10.5,10.5]])
    let request = RemoveRequest(layerID:doc.layers[0].id,settings:settings,strokes:[loop,subtract])
    let coverage = try RemovePreparation.coverage(request,in:doc)
    XCTAssertEqual(coverage.byte(at:8*24+8),255)
    XCTAssertEqual(coverage.byte(at:10*24+10),0)
    XCTAssertEqual(coverage.byte(at:9*24+13),0)
    XCTAssertEqual(coverage.byte(at:0),0)
    XCTAssertFalse(RemoveStroke(size:4,points:[[1,1],[2,1],[2,2],[1,1]]).closesLoop)
  }
  func testSharedPreparedRemovalAllDepthsPreservesExactOutsideSamplesAndSelectionRepresentation() throws {
    for depth in PixelDepth.allCases {
      var doc = try fixture(depth)
      // Explicit rectangle stays a rectangle, rather than becoming a dense mask.
      doc.selection = .init(x:8,y:8,width:8,height:8)
      let request = RemoveRequest(layerID:doc.layers[0].id,settings:.init(),
        strokes:[.init(size:7,points:[[12,12]])])
      let mask = try RemovePreparation.coverage(request,in:doc)
      let edit = try RemovePreparation.prepare(request,document:doc)
      XCTAssertEqual(edit.label,"Remove"); XCTAssertEqual(edit.source,doc)
      XCTAssertEqual(edit.result.selection,doc.selection); XCTAssertNil(edit.result.selectionMask)
      guard case .raster(let before) = doc.layers[0].content,
        case .raster(let after) = edit.result.layers[0].content else { return XCTFail("Raster missing") }
      var changed = 0
      for y in 0..<24 { for x in 0..<24 {
        let a = depth == .f32 ? before.linearPixel(x:x,y:y):before.pixel(x:x,y:y)
        let b = depth == .f32 ? after.linearPixel(x:x,y:y):after.pixel(x:x,y:y)
        if mask.byte(at:y*24+x) == 0 {
          XCTAssertEqual([a.r.bitPattern,a.g.bitPattern,a.b.bitPattern,a.a.bitPattern],
            [b.r.bitPattern,b.g.bitPattern,b.b.bitPattern,b.a.bitPattern],"\(depth) \(x),\(y)")
        } else if a != b { changed += 1 }
      } }
      XCTAssertGreaterThan(changed,0)
      let expected = depth == .f32 ? before.linearPixel(x:0,y:0):before.pixel(x:0,y:0)
      let repaired = depth == .f32 ? after.linearPixel(x:12,y:12):after.pixel(x:12,y:12)
      XCTAssertEqual(repaired,expected,"The owned fixture has a uniform donor field.")
      var session = EditorSession(document:doc)
      try session.executePrepared(PreparedEdit(command:.regionRetouch(edit),document:doc))
      XCTAssertEqual(session.document,edit.result); XCTAssertEqual(session.undoStack.count,1)
      try session.undo(); XCTAssertEqual(session.document,doc)
      try session.redo(); XCTAssertEqual(session.document,edit.result)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edit.result)),edit.result)
    }
  }
  func testNewLayerRetainsLockedOriginalAndAllLayerSamplingIsDistinct() throws {
    var doc = try fixture(); doc.layers[0].locked = true
    let original = doc.layers[0]
    var overlay = Layer(name:"Owned donor",content:.raster(try Surface(width:24,height:24,fill:Pixel(0,0.75,0))))
    overlay.visible = true; doc.layers.append(overlay)
    var settings = RemoveToolSettings(); settings.createNewLayer = true
    let stroke = RemoveStroke(size:5,points:[[12,12]])
    let current = try RemovePreparation.prepare(.init(layerID:original.id,settings:settings,strokes:[stroke]),document:doc).result
    settings.sampleAllLayers = true
    let all = try RemovePreparation.prepare(.init(layerID:original.id,settings:settings,strokes:[stroke]),document:doc).result
    for result in [current,all] {
      XCTAssertEqual(result.layers.first(where: { $0.id == original.id }),original)
      XCTAssertEqual(result.layers.first(where: { $0.id == overlay.id }),overlay)
      XCTAssertEqual(result.layers.count,3); XCTAssertNil(result.selection); XCTAssertNil(result.selectionMask)
      let output = try XCTUnwrap(result.layers.first(where: { $0.id == result.activeLayerID }))
      XCTAssertEqual(output.name,"Remove"); XCTAssertFalse(output.locked)
    }
    let a = try XCTUnwrap(current.layers.first(where: { $0.id == current.activeLayerID }))
    let b = try XCTUnwrap(all.layers.first(where: { $0.id == all.activeLayerID }))
    XCTAssertNotEqual(a.content,b.content)
  }
  func testGenerativeUnknownTargetEmptyOversizedAndStaleEditsReject() throws {
    let doc = try fixture(),id = doc.layers[0].id
    var settings = RemoveToolSettings(); settings.mode = .generativeOn
    XCTAssertThrowsError(try RemovePreparation.prepare(.init(layerID:id,settings:settings,strokes:[.init(size:5,points:[[12,12]])]),document:doc))
    settings.mode = .generativeOff
    for strokes:[RemoveStroke] in [[],[.init(size:5,subtract:true,points:[[12,12]])],[.init(size:.nan,points:[[12,12]])],[.init(size:5,points:[[Double.infinity,0]])]] {
      XCTAssertThrowsError(try RemovePreparation.prepare(.init(layerID:id,settings:settings,strokes:strokes),document:doc))
    }
    let request = RemoveRequest(layerID:id,settings:settings,strokes:[.init(size:5,points:[[12,12]])])
    let edit = try RemovePreparation.prepare(request,document:doc)
    var stale = doc; stale.name = "Different source"
    XCTAssertThrowsError(try edit.applied(to:stale))
    let unknown = RemoveRequest(layerID:UUID(),settings:settings,strokes:request.strokes)
    XCTAssertThrowsError(try RemovePreparation.prepare(unknown,document:doc))
    let big = try CraftDocument(width:300000,height:300000)
    XCTAssertThrowsError(try RemovePreparation.coverage(.init(layerID:big.layers[0].id,settings:settings,strokes:request.strokes),in:big))
    for dimension in [0,-1,Surface.maxDimension+1] {
      var invalid = doc; invalid.height = dimension
      XCTAssertThrowsError(try RemovePreparation.coverage(request,in:invalid))
      XCTAssertThrowsError(try RemovePreparation.prepare(request,document:invalid))
      invalid = doc; invalid.width = dimension
      XCTAssertThrowsError(try RemovePreparation.coverage(request,in:invalid))
      XCTAssertThrowsError(try RemovePreparation.prepare(request,document:invalid))
    }
  }
  func testSoftSelectionAndHiddenHDRWordsStayProtected() throws {
    var doc = try fixture(.f32)
    guard case .raster(var source) = doc.layers[0].content else { return XCTFail("Raster missing") }
    let sentinel = Pixel(Float(bitPattern:0xc1000003),Float(bitPattern:0x41800001),Float(bitPattern:0x3e000001),0)
    source.setLinearPixel(x:0,y:0,sentinel); doc.layers[0].content = .raster(source)
    var bytes = [UInt8](repeating:0,count:24*24)
    for y in 10..<14 { for x in 10..<14 { bytes[y*24+x] = x == 10 ? 128:255 } }
    doc.setCoverageSelection(try SelectionMask(width:24,height:24,bytes:bytes))
    let request = RemoveRequest(layerID:doc.layers[0].id,settings:.init(),strokes:[.init(size:9,points:[[12,12]])])
    let result = try RemovePreparation.prepare(request,document:doc).result
    XCTAssertEqual(result.selection,doc.selection); XCTAssertEqual(result.selectionMask,doc.selectionMask)
    guard case .raster(let pixels) = result.layers[0].content else { return XCTFail("Raster missing") }
    for y in 0..<24 { for x in 0..<24 where bytes[y*24+x] == 0 {
      let a = source.linearPixel(x:x,y:y),b = pixels.linearPixel(x:x,y:y)
      XCTAssertEqual([a.r.bitPattern,a.g.bitPattern,a.b.bitPattern,a.a.bitPattern],
        [b.r.bitPattern,b.g.bitPattern,b.b.bitPattern,b.a.bitPattern])
    } }
    XCTAssertGreaterThan(pixels.linearPixel(x:10,y:11).r, pixels.linearPixel(x:11,y:11).r)
    XCTAssertLessThan(pixels.linearPixel(x:10,y:11).r, source.linearPixel(x:10,y:11).r)
  }
}
