import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

// Frozen build-524 contour traversal. This is a native regression/CPU reference,
// not an independent Photoshop oracle or a replay of the old app binary.
private enum LegacySelectionOutline525 {
  static func path(_ mask: SelectionMask, region:IntRect? = nil, sampleStep:Int = 1) throws -> SelectionContour {
    if mask.isPaged {
      return try SelectionOutline.boundedPath(mask,region:region ?? IntRect(x:0,y:0,width:mask.width,height:mask.height),sampleStep:max(sampleStep,region == nil ? (max(mask.width,mask.height)+2047)/2048:1))
    }
    let path = CGMutablePath()
    func selected(_ x: Int, _ y: Int) -> Bool { mask.coverage(x: x, y: y) >= 0.5 }
    for y in 0...mask.height {
      try Task.checkCancellation()
      var start: Int?
      for x in 0...mask.width {
        let edge = x < mask.width && selected(x, y - 1) != selected(x, y)
        if edge && start == nil { start = x }
        if !edge, let from = start {
          path.move(to: CGPoint(x: from, y: y))
          path.addLine(to: CGPoint(x: x, y: y))
          start = nil
        }
      }
    }
    for x in 0...mask.width {
      try Task.checkCancellation()
      var start: Int?
      for y in 0...mask.height {
        let edge = y < mask.height && selected(x - 1, y) != selected(x, y)
        if edge && start == nil { start = y }
        if !edge, let from = start {
          path.move(to: CGPoint(x: x, y: from))
          path.addLine(to: CGPoint(x: x, y: y))
          start = nil
        }
      }
    }
    return SelectionContour(path)
  }
}

final class SelectionOutlineResponsivenessTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    await MainActor.run { _ = PhotatoApp.makeDelegate(isolatedSession: true); _ = NSApplication.shared }
  }
  private func mask(_ width: Int = 37, _ height: Int = 29, variant: Int = 0) throws -> SelectionMask {
    var bytes = [UInt8](repeating: 0, count: width*height)
    for y in 3..<min(height-2,23) { for x in 4..<min(width-2,31) {
      let hole = x > 12 && x < 18 && y > 9 && y < 17
      bytes[y*width+x] = hole ? 0 : UInt8([127,128,191,255][(x+y+variant)%4])
    }}
    return try SelectionMask(width:width,height:height,bytes:bytes)
  }
  func testBoundedDenseContoursRetainEveryFrozenRunAndIndependentRectangle() throws {
    for width in [1,2,7,37] { for height in [1,3,29] {
      for pattern in 0..<6 {
        var bytes=[UInt8](repeating:0,count:width*height)
        for y in 0..<height { for x in 0..<width {
          switch pattern {
          case 0: break
          case 1: bytes[y*width+x]=255
          case 2: bytes[y*width+x]=127
          case 3: bytes[y*width+x]=(x+y)%2==0 ? 128:0
          case 4: bytes[y*width+x]=x==0 || y==height-1 ? 255:0
          default: bytes[y*width+x]=UInt8((x*37+y*71)%256)
          }
        }}
        let m=try SelectionMask(width:width,height:height,bytes:bytes)
        let actual=try SelectionOutline.path(m).path,old=try LegacySelectionOutline525.path(m).path
        XCTAssertEqual(actual,old,"\(width)x\(height), pattern\(pattern)")
      }
    }}
    let m=try SelectionMask.make(.rectangle(.init(x:7,y:5,width:8,height:6)),width:37,height:29,antiAlias:false)
    let independent=CGMutablePath()
    for (a,b) in [(CGPoint(x:7,y:5),CGPoint(x:15,y:5)),(.init(x:7,y:11),.init(x:15,y:11)),(.init(x:7,y:5),.init(x:7,y:11)),(.init(x:15,y:5),.init(x:15,y:11))] {
      independent.move(to:a);independent.addLine(to:b)
    }
    XCTAssertEqual(try SelectionOutline.path(m).path,independent)
  }
  func testCacheRetainsOneContourAndAdoptsEqualNewStorageWithoutMutation() async throws {
    let m=try mask(),cache=SelectionOutlineCache(),key=SelectionOutlineRequest(mask:m)
    let built=try await cache.path(for:key)
    let first=try XCTUnwrap(built)
    for _ in 0..<120 {
      let next=try await cache.path(for:key);XCTAssertTrue(next?.path === first.path)
    }
    let copy=try SelectionMask(width:m.width,height:m.height,bytes:m.bytes)
    XCTAssertEqual(copy,m);XCTAssertFalse(copy.sharesCoverageStorage(with:m))
    let copiedKey=SelectionOutlineRequest(mask:copy)
    XCTAssertFalse(copiedKey.sharesSource(with:key))
    let equal=try await cache.path(for:copiedKey);XCTAssertTrue(equal?.path === first.path)
    let builds=await cache.builds,hits=await cache.hits
    XCTAssertEqual(builds,1);XCTAssertEqual(hits,121)
    XCTAssertEqual(try m.bytes,try copy.bytes)
  }
  func testCacheInvalidatesForCoverageViewStepAndClearedSelection() async throws {
    let a=try mask(),b=try mask(variant:1),cache=SelectionOutlineCache()
    XCTAssertEqual(a.bounds,b.bounds);XCTAssertNotEqual(a,b)
    let keys=[SelectionOutlineRequest(mask:a),.init(mask:b),.init(mask:b,region:.init(x:1,y:2,width:20,height:20)),.init(mask:b,region:.init(x:1,y:2,width:20,height:20),sampleStep:2)]
    for key in keys {
      let result=try await cache.path(for:key)
      XCTAssertEqual(result?.path,try SelectionOutline.path(key.mask,region:key.region,sampleStep:key.sampleStep).path)
    }
    let builds=await cache.builds;XCTAssertEqual(builds,4)
    let cleared=try await cache.path(for:nil);XCTAssertNil(cleared)
    _=try await cache.path(for:keys[0]);let rebuilt=await cache.builds;XCTAssertEqual(rebuilt,5)
  }
  func testFailedAndCancelledRequestsCannotReplaceAValidContour() async throws {
    let m=try mask(),key=SelectionOutlineRequest(mask:m)
    let cache=SelectionOutlineCache { request in
      if request.region?.x==13 { throw CraftError.invalid("Injected contour failure") }
      return try SelectionOutline.path(request.mask,region:request.region,sampleStep:request.sampleStep)
    }
    let first=try await cache.path(for:key)
    do { _=try await cache.path(for:.init(mask:m,region:.init(x:13,y:0,width:10,height:10)));XCTFail("Failed build accepted") }catch{}
    let task=Task { () throws -> SelectionContour? in
      withUnsafeCurrentTask { $0?.cancel() };return try await cache.path(for:key)
    }
    do { _=try await task.value;XCTFail("Cancelled request accepted") }catch is CancellationError {}catch{XCTFail("Unexpected error")}
    let next=try await cache.path(for:key);XCTAssertTrue(next?.path === first?.path)
    let builds=await cache.builds;XCTAssertEqual(builds,1)
  }
  func testConcurrentRequestsAndMaximumPagedViewsKeepTheirOwnGeometry() async throws {
    let a=try mask(),b=try mask(variant:1),cache=SelectionOutlineCache()
    let values=[SelectionOutlineRequest(mask:a),.init(mask:b)]
    let expected=try values.map {try SelectionOutline.path($0.mask).path}
    try await withThrowingTaskGroup(of:Bool.self) { group in
      for i in 0..<24 { let index=i%2,key=values[index],reference=SelectionContour(expected[index])
        group.addTask { try await cache.path(for:key)?.path == reference.path }
      }
      for try await matches in group {XCTAssertTrue(matches)}
    }
    let large=try SelectionMask.make(.ellipse(.init(x:149990,y:149990,width:30,height:30)),width:300000,height:300000,antiAlias:true)
    XCTAssertTrue(large.isPaged)
    for rect in [IntRect(x:149980,y:149980,width:100,height:100),.init(x:100,y:100,width:300,height:300)] {
      let key=SelectionOutlineRequest(mask:large,region:rect,sampleStep:2)
      let result=try await cache.path(for:key)
      XCTAssertEqual(result?.path,try SelectionOutline.path(large,region:rect,sampleStep:2).path)
    }
  }
  @MainActor func testPaintingKeepsMatchingOutlineAndChangedCoverageInvalidatesIt() async throws {
    var original=try CraftDocument(width:72,height:48)
    original.setCoverageSelection(try mask(72,48))
    let s=EditorStore(document:original,actions:ActionLibrary(),brushes:BrushLibrary(),paintPalette:PaintPalette())
    defer{s.cancelBrush();s.renderTask?.cancel();s.geometryTask?.cancel()}
    s.tool = .brush;s.brush.size=4;s.brush.color = .black
    await s.renderTask?.value
    let path=try XCTUnwrap(s.selectionPath),key=try XCTUnwrap(s.selectionPathRequest)
    let archive=try NativeArchive.encodeChunked(original)
    s.beginBrush(.init(x:9,y:9),zoom:1);s.extendBrush(.init(x:11,y:12));s.render()
    XCTAssertTrue(s.selectionPath === path);XCTAssertTrue(try XCTUnwrap(s.selectionPathRequest).sharesSource(with:key))
    let gesture=try XCTUnwrap(s.brushGesture);var expected=original;try gesture.command.apply(to:&expected)
    await s.brushPreviewTask?.value;await s.renderTask?.value
    XCTAssertTrue(s.selectionPath === path);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    let builds=await s.selectionOutlineCache.builds;XCTAssertEqual(builds,1)
    s.finishBrush();await s.geometryTask?.value;await s.renderTask?.value
    XCTAssertEqual(s.document,expected);XCTAssertEqual(s.session.undoStack.count,1)
    _=await s.requestHistory(redo:false).value;await s.renderTask?.value
    XCTAssertEqual(try NativeArchive.encodeChunked(s.document),archive)
    try s.session.execute(.selectShape(.ellipse(.init(x:6,y:6,width:25,height:21)),.replace,true,0));s.render()
    XCTAssertNil(s.selectionPath);await s.renderTask?.value
    XCTAssertEqual(s.selectionPath,try s.document.selectionMask.map {try SelectionOutline.path($0).path})
    XCTAssertNil(s.error)
  }
  @MainActor func testAPISelectionPresentationRetainsRevisionPixelsArchiveAndCommands() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      var original=try CraftDocument(width:72,height:48);original.setCoverageSelection(try self.mask(72,48))
      let s=document.store;s.session=EditorSession(document:original);s.render();await s.renderTask?.value;try service.share(document)
      let bytes=try NativeArchive.encodeChunked(original),count=AutomationCommand.definitions.count
      for _ in 0..<5 {s.render();await s.renderTask?.value}
      let revision=service.revision(s)
      let key=try XCTUnwrap(service.shares.first?.id)
      let response=try await helper.request(service,path:"/v1/documents/\(key)")
      XCTAssertEqual(response.0.statusCode,200)
      let object=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any]);XCTAssertNotNil(object["selectionDisplay"])
      XCTAssertEqual(service.revision(s),revision);XCTAssertEqual(s.document,original)
      XCTAssertEqual(try NativeArchive.encodeChunked(s.document),bytes);XCTAssertEqual(AutomationCommand.definitions.count,count)
      XCTAssertNotNil(SelectionAntsAPI.capabilities["contourPreparation"])
      let builds=await s.selectionOutlineCache.builds;XCTAssertEqual(builds,1)
    }
  }
  func testOwned24And36MPContoursMatchFrozenTraversalAndRecordCPUCosts() async throws {
    guard let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]else{throw XCTSkip("Performance evidence requires an owned capture directory")}
    for height in [4000,6000] {
      let width=6000,rect=IntRect(x:2500,y:1800,width:64,height:48)
      var bytes=[UInt8](repeating:0,count:width*height)
      for y in rect.y..<(rect.y+rect.height) {for x in rect.x..<(rect.x+rect.width) {bytes[y*width+x]=255}}
      let m=try SelectionMask(width:width,height:height,bytes:bytes)
      let start=ProcessInfo.processInfo.systemUptime,legacy=try LegacySelectionOutline525.path(m)
      let legacyMS=(ProcessInfo.processInfo.systemUptime-start)*1000
      let currentStart=ProcessInfo.processInfo.systemUptime,current=try SelectionOutline.path(m)
      let currentMS=(ProcessInfo.processInfo.systemUptime-currentStart)*1000
      XCTAssertEqual(current.path,legacy.path)
      let cache=SelectionOutlineCache(),key=SelectionOutlineRequest(mask:m)
      let first=try await cache.path(for:key),cachedStart=ProcessInfo.processInfo.systemUptime
      for _ in 0..<120 {let value=try await cache.path(for:key);XCTAssertTrue(value?.path === first?.path)}
      let cachedMS=(ProcessInfo.processInfo.systemUptime-cachedStart)*1000,builds=await cache.builds,hits=await cache.hits
      XCTAssertEqual(builds,1);XCTAssertEqual(hits,120)
      #if DEBUG
      let configuration="Debug"
      #else
      let configuration="Optimized"
      #endif
      let record:[String:Any]=["width":width,"height":height,"configuration":configuration,"legacy524RecompiledMS":legacyMS,"boundedExactContourMS":currentMS,"retained120RequestsMS":cachedMS,"builds":builds,"hits":hits,"sameContourRuns":true,"physicalFPSMeasured":false,"scope":"Frozen native524 traversal recompiled in the same test binary; no old app or Photoshop-output replay."]
      try FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true)
      try JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]).write(to:URL(fileURLWithPath:folder).appendingPathComponent("contour525-\(height).json"))
    }
  }
}
