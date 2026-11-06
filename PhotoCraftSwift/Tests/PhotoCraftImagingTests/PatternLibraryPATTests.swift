import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PatternLibraryPATTests:XCTestCase {
  func testHierarchyRoundTripKeepsPixelRecordBytesAllDepthsAndIndependentDescriptorOrder()throws {
    for depth in PixelDepth.allCases {
      let asset=try RasterPattern(name:"Tile",surface:Surface(width:2,height:2,depth:depth,fill:.white),id:"tile")
      var state=PatternLibraryState(patterns:[asset]);let leaf=state.nodes[0].id
      let root=try XCTUnwrap(state.apply(.createGroup("Root",parent:nil))),empty=try XCTUnwrap(state.apply(.createGroup("Empty",parent:root)))
      try state.apply(.move([leaf],parent:root,before:empty))
      let flat=try PATCodec.write([asset]),data=try PATCodec.writeLibrary(state)
      XCTAssertEqual(data.prefix(flat.count),flat)
      var reader=PSDReader(data:Data(data.dropFirst(flat.count)))
      XCTAssertEqual(try reader.string(4),"8BIM");XCTAssertEqual(try reader.string(4),"phry")
      let descriptor=try PSDDescriptor.read(reader.bytes(reader.u32()))
      guard case .list(let items)=descriptor["hierarchy"]else{return XCTFail("Missing hierarchy")}
      let classes=items.compactMap{item->String? in if case .object(let value)=item{return value.classID.text};return nil}
      XCTAssertEqual(classes,["Grup","preset","Grup","groupEnd","groupEnd"])
      let decoded=try PATCodec.readLibrary(data);XCTAssertFalse(decoded.foldersFlattened)
      XCTAssertEqual(decoded.patterns,try PATCodec.read(flat));XCTAssertEqual(decoded.nodes.filter(\.isGroup).map(\.name),["Root","Empty"])
      XCTAssertEqual(try PATCodec.writeLibrary(PatternLibraryState(patterns:decoded.patterns,nodes:decoded.nodes)),data)
    }
  }
  func testRepeatedPresetOccurrencesAndSelectedGroupExportSurvivePAT()throws {
    let asset=try RasterPattern(name:"Repeated",surface:Surface(width:2,height:1,depth:.f32,fill:Pixel(0.25,0.5,0.75,0)),id:"repeat")
    var state=PatternLibraryState(patterns:[asset]);let first=state.nodes[0].id
    let group=try XCTUnwrap(state.apply(.createGroup("Folder",parent:nil)));state.nodes.append(.init(parentID:group,patternID:asset.id))
    let data=try PATCodec.writeLibrary(state),result=try PATCodec.readLibrary(data)
    XCTAssertEqual(result.patterns.count,1);XCTAssertEqual(result.duplicateRecordsMerged,1);XCTAssertEqual(result.nodes.filter{!$0.isGroup}.count,2)
    for x in 0..<2{XCTAssertTrue(result.patterns[0].surface.pixel(x:x,y:0).hasSameBits(as:asset.surface.pixel(x:x,y:0)))}
    let subset=try PATCodec.readLibrary(PATCodec.writeLibrary(state,selected:[group]))
    XCTAssertEqual(subset.nodes.count,2);XCTAssertEqual(subset.nodes.first?.name,"Folder")
    XCTAssertFalse(subset.nodes.contains{$0.id==first})
    let empty=PatternLibraryState(patterns:[],nodes:[.init(name:"Empty group")])
    XCTAssertEqual(try PATCodec.readLibrary(PATCodec.writeLibrary(empty)).nodes.first?.name,"Empty group")
  }
  func testCorruptHierarchyAndUnknownNativeVersionStayRejected()throws {
    let state=PatternLibraryState(patterns:[],nodes:[.init(name:"Folder")]);let data=try PATCodec.writeLibrary(state)
    for amount in [1,2,8,16]{XCTAssertThrowsError(try PATCodec.readLibrary(data.dropLast(amount)))}
    var invalid=state;invalid.nodes[0].parentID=invalid.nodes[0].id
    XCTAssertThrowsError(try PATCodec.writeLibrary(invalid))
    let original=try PATCodec.write([])
    XCTAssertEqual(try PATCodec.readLibrary(original).nodes,[])
    let large=try RasterPattern(name:"Implicit",surface:Surface(width:1024,height:1024,fill:.white),id:"large")
    let repeated=PatternLibraryState(patterns:[large],nodes:(0..<128).map{_ in .init(patternID:large.id)})
    try repeated.validate();XCTAssertThrowsError(try PATCodec.writeLibrary(repeated))
  }
}
