import XCTest
@testable import PhotoCraftCore

final class PatternLibraryStateTests:XCTestCase {
  func assets()throws->[RasterPattern] {
    try PixelDepth.allCases.enumerated().map { index,depth in
      try RasterPattern(name:"Tile \(index)",surface:Surface(width:3,height:2,depth:depth,fill:Pixel(0.25,0.5,0.75,0.5)),id:"tile-\(index)")
    }
  }
  func testOrganizeMoveDuplicateRenameDeletePreservesPixelsAndRejectsCyclesAtomically()throws {
    let assets=try assets();var state=PatternLibraryState(patterns:assets,selectedID:assets[0].id)
    let first=state.nodes[0].id,second=state.nodes[1].id
    let group=try XCTUnwrap(state.apply(.createGroup("Textures",parent:nil)))
    try state.apply(.move([first,second],parent:group,before:nil))
    XCTAssertEqual(state.children(of:group).map(\.id),[first,second]);XCTAssertEqual(state.patterns,assets)
    let nested=try XCTUnwrap(state.apply(.createGroup("Paper",parent:group)))
    let before=state;XCTAssertThrowsError(try state.apply(.move([group],parent:nested,before:nil)));XCTAssertEqual(state,before)
    try state.apply(.move([second],parent:group,before:first));XCTAssertEqual(state.children(of:group).prefix(2).map(\.id),[second,first])
    let copy=try XCTUnwrap(state.apply(.duplicate([group,first],parent:nil,before:group)))
    let copied=try XCTUnwrap(state.nodes.first{$0.parentID==copy && $0.patternID != nil})
    XCTAssertEqual(state.patterns.count,5);let originalBits=try XCTUnwrap(assets.first{$0.id==state.node(second)?.patternID}).surface
    XCTAssertEqual(try XCTUnwrap(state.patterns.first{$0.id==copied.patternID}).surface,originalBits)
    try state.apply(.rename(copied.id,"Independent copy"));XCTAssertEqual(state.name(second),assets[1].displayName)
    try state.apply(.delete([copy]));XCTAssertEqual(state.patterns,assets);XCTAssertEqual(state.nodes.count,before.nodes.count)
    try state.validate()
  }
  func testVersionOneMigrationAndVersionTwoRetainHierarchySelectionAndExactSamples()throws {
    let assets=try assets(),old=try PatternArchive.encode(assets,selectedID:assets[1].id)
    XCTAssertEqual(try PatternArchive.libraryVersion(old),1)
    var state=try PatternArchive.decodeLibraryState(old);XCTAssertEqual(state.patterns,assets);XCTAssertEqual(state.selectedID,assets[1].id)
    XCTAssertEqual(try PatternArchive.encode(assets,selectedID:assets[1].id),old)
    let group=try XCTUnwrap(state.apply(.createGroup("紙 / Textures",parent:nil)));let leaf=state.nodes[0].id
    try state.apply(.move([leaf],parent:group,before:nil));try state.apply(.select([group,leaf],active:leaf));try state.apply(.collapse(group,true))
    let encoded=try PatternArchive.encodeLibraryState(state)
    XCTAssertEqual(try PatternArchive.libraryVersion(encoded),2);XCTAssertEqual(try PatternArchive.decodeLibraryState(encoded),state)
    XCTAssertEqual(try PatternArchive.decodeState(encoded).patterns,assets);XCTAssertEqual(try PatternArchive.decodeState(encoded).selectedID,assets[0].id)
    let plist=try PropertyListSerialization.propertyList(from:encoded,format:nil) as! [String:Any]
    var future=plist;future["version"]=3
    XCTAssertThrowsError(try PatternArchive.decodeLibraryState(PropertyListSerialization.data(fromPropertyList:future,format:.binary,options:0)))
  }
  func testInvalidGraphsReferencesSelectionsAndDepthReject()throws {
    let assets=try assets();let original=PatternLibraryState(patterns:assets)
    var state=original;state.nodes[0].parentID=state.nodes[0].id;XCTAssertThrowsError(try state.validate())
    state=original;state.nodes[0].parentID=UUID();XCTAssertThrowsError(try state.validate())
    state=original;state.nodes[0].patternID="missing";XCTAssertThrowsError(try state.validate())
    state=original;state.nodes.append(state.nodes[0]);XCTAssertThrowsError(try state.validate())
    state=original;state.collapsed=[state.nodes[0].id];XCTAssertThrowsError(try state.validate())
    state=original;state.selectedNodes=[UUID()];XCTAssertThrowsError(try state.validate())
    state=original;state.nodes[1].parentID=state.nodes[0].id;XCTAssertThrowsError(try state.validate())
    state=original;state.nodes[0].patternID=nil;state.nodes[0].name=" ";XCTAssertThrowsError(try state.validate())
    state=PatternLibraryState(patterns:[]);var parent:UUID?
    for i in 0..<64{let node=PatternLibraryNode(parentID:parent,name:"\(i)");state.nodes.append(node);parent=node.id}
    try state.validate();state.nodes.append(.init(parentID:parent,name:"Too deep"));XCTAssertThrowsError(try state.validate())
    let a=PatternLibraryNode(name:"A"),b=PatternLibraryNode(parentID:a.id,name:"B")
    state=PatternLibraryState(patterns:[],nodes:[a,b]);state.nodes[0].parentID=b.id;XCTAssertThrowsError(try state.validate())
  }
  func testSelectedGroupExportKeepsSubtreesEmptyGroupsAndRepeatedAssetReferences()throws {
    let assets=try assets();var state=PatternLibraryState(patterns:assets)
    let group=try XCTUnwrap(state.apply(.createGroup("Export",parent:nil))),leaf=state.nodes[0].id
    try state.apply(.move([leaf],parent:group,before:nil));let empty=try XCTUnwrap(state.apply(.createGroup("Empty",parent:group)))
    state.nodes.append(.init(parentID:empty,patternID:assets[0].id));try state.validate()
    let subset=try state.subset([group,leaf]);XCTAssertEqual(subset.patterns,[assets[0]]);XCTAssertEqual(subset.nodes.count,4)
    XCTAssertEqual(subset.nodes.filter{$0.patternID==assets[0].id}.count,2);XCTAssertEqual(subset.children(of:nil).map(\.id),[group])
    try state.apply(.delete([leaf]));XCTAssertTrue(state.patterns.contains{$0.id==assets[0].id})
    try state.apply(.delete([empty]));XCTAssertFalse(state.patterns.contains{$0.id==assets[0].id})
    try state.validate()
  }
  func testInstallingLibrariesRemapsNodeIdentityRetainsFoldersAndIsAtomicOnFailure()throws {
    let assets=try assets();var incoming=PatternLibraryState(patterns:[assets[0]])
    let group=try XCTUnwrap(incoming.apply(.createGroup("Imported",parent:nil)));try incoming.apply(.move([incoming.nodes[0].id],parent:group,before:nil))
    var state=PatternLibraryState(patterns:[assets[1]]);try state.install(incoming);try state.install(incoming)
    XCTAssertEqual(state.patterns.count,2);XCTAssertEqual(state.nodes.filter(\.isGroup).map(\.name),["Imported","Imported"])
    XCTAssertEqual(Set(state.nodes.map(\.id)).count,5);XCTAssertFalse(Set(state.nodes.map(\.id)).contains(group))
    let before=state;XCTAssertThrowsError(try state.install(incoming,into:state.nodes[0].id));XCTAssertEqual(state,before)
    try state.apply(.rename(state.nodes.first{$0.patternID==assets[0].id}!.id,"Shared asset name"))
    XCTAssertEqual(incoming.patterns[0].name,assets[0].name)
  }
}
