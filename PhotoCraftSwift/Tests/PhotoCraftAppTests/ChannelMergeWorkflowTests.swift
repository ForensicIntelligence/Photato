import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ChannelMergeWorkflowTests: XCTestCase {
  func fixture(_ index: Int, depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 16, height: 12, depth: depth, name: "Owned gray \(index)")
    let profile = try NativeModeProfile.standard(.grayscale, depth: depth)
    var gray = try NativeModeRaster(width: 16, height: 12, mode: .grayscale, depth: depth, profile: profile)
    let integers8: [Float] = [0, 1, 17, 64, 128, 192, 254, 255]
    let integers16: [Float] = [0, 1, 32767, 32768, 32769, 49151, 65534, 65535]
    let floats: [Float] = [-0.25, 0, 0.125, 0.25, 0.5, 1, 1.5, 2]
    for y in 0..<12 { for x in 0..<16 {
      let at = y * 16 + x, i = (x + 3 * y + index * 5) % 8
      let value = depth == .u8 ? integers8[i] / 255 : depth == .u16 ? integers16[i] / 65535 : floats[i]
      try gray.set(value, component: 0, index: at); try gray.set(1, component: 1, index: at)
    } }
    document.modeDescriptor = try .init(mode: .grayscale, depth: depth, profile: profile)
    document.profileIsUntagged = true
    document.layers[0].nativeMode = gray; document.layers[0].content = .raster(try gray.surface())
    document.layers[0].background = true
    try document.validate(); return document
  }
  func testOwnedNativeGrayFixturesRetainAllNumericComponents() throws {
    for depth in PixelDepth.allCases { for index in 0..<4 {
      let source = try fixture(index, depth: depth), bytes = try PSDCodec.writeRasterLayers(source)
      let reopened = try PSDCodec.read(bytes)
      let before = try XCTUnwrap(source.layers[0].nativeMode), after = try XCTUnwrap(reopened.layers[0].nativeMode)
      for at in 0..<192 {
        XCTAssertEqual(before.rawWord(component: 0, index: at), after.rawWord(component: 0, index: at))
      }
      if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let root = URL(fileURLWithPath: path), name = "native-owned-gray-\(index)-\(depth).psd"
        try bytes.write(to: root.appendingPathComponent(name))
        try NativeArchive.encode(source).write(to: root.appendingPathComponent("native-owned-gray-\(index)-\(depth).photato"))
      }
    } }
  }
  @MainActor func testRealHTTPMergesThreeSharedGraySourcesAndClosesThemAtomically() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, first in
      first.store.renderTask?.cancel(); first.store.session = EditorSession(document: try self.fixture(0))
      let second = CraftNSDocument(model: try self.fixture(1)), third = CraftNSDocument(model: try self.fixture(2))
      service.controller.addDocument(second); service.controller.addDocument(third)
      defer {
        for item in service.controller.documents.compactMap({ $0 as? CraftNSDocument }) where item !== first {
          item.store.renderTask?.cancel(); service.controller.removeDocument(item)
        }
      }
      for item in [first, second, third] { item.store.renderTask?.cancel(); try service.share(item) }
      service.setDocumentTransfersEnabled(true); service.setDocumentClosingEnabled(true)
      let inputs = try [first, second, third].map { doc -> [String: String] in
        let share = try XCTUnwrap(service.shares.first(where: { $0.document === doc }))
        return ["shareID": share.id.uuidString, "revision": service.revision(doc.store)]
      }
      let share = try XCTUnwrap(service.shares.first(where: { $0.document === first }))
      let response = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: [
        "command": "channel.merge", "revision": service.revision(first.store),
        "parameters": ["mode": "rgb", "sources": inputs]])
      XCTAssertEqual(response.0.statusCode, 201, String(decoding: response.1, as: UTF8.self))
      guard response.0.statusCode == 201 else { return }
      XCTAssertNil(first.ownerController); XCTAssertNil(second.ownerController); XCTAssertNil(third.ownerController)
      let result = try XCTUnwrap(service.controller.documents.first as? CraftNSDocument)
      XCTAssertEqual(service.controller.documents.count, 1); XCTAssertEqual(result.store.document.colorMode, .rgb)
      XCTAssertTrue(result.isDocumentEdited); XCTAssertNil(result.fileURL); XCTAssertTrue(result.store.session.undoStack.isEmpty)
    }
  }
}

extension ChannelMergeWorkflowTests {
  func reference(_ name: String) throws -> CraftDocument {
    try PSDCodec.read(XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"psd",subdirectory:"Fixtures/channel-merge")))
  }
  /// Independent literal parser for these raw Photoshop-owned merged references.
  /// No production PSD decoder, color-management policy or component transform.
  func literalReference(_ name: String) throws -> (width:Int,height:Int,depth:Int,raw:Data) {
    let url = try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"psd",subdirectory:"Fixtures/channel-merge"))
    let bytes = try Data(contentsOf:url)
    func number(_ at:Int,_ count:Int)->Int { bytes[at..<at+count].reduce(0) { $0*256+Int($1) } }
    XCTAssertEqual(bytes.prefix(6),Data([56,66,80,83,0,1]))
    let channels = number(12,2), height = number(14,4), width = number(18,4), depth = number(22,2)
    var offset = 26
    for _ in 0..<3 { let length = number(offset,4); offset += 4+length }
    XCTAssertEqual(number(offset,2),0,"Owned reference must contain raw merged planes")
    let raw = bytes.subdata(in:offset+2..<bytes.count)
    XCTAssertEqual(raw.count,width*height*channels*depth/8)
    return (width,height,depth,raw)
  }
  func testEverySmallReferenceModeMatchesAllIndependentPhotoshopComponentWords() throws {
    for (mode, depth, order, filename) in [
      (ChannelMergeMode.rgb,PixelDepth.u8,[2,1,0],"photoshop-merge-rgb8-CBA"),
      (.rgb,.u16,[0,1,2],"photoshop-merge-rgb16-ABC"),
      (.cmyk,.u16,[2,0,1,3],"photoshop-merge-cmyk16-CABD"),
      (.lab,.u16,[2,0,1],"photoshop-merge-lab16-CAB"),
      (.multichannel,.u8,[0,1],"photoshop-merge-multichannel8-AB"),
      (.multichannel,.u16,[0,1],"photoshop-merge-multichannel16-AB")
    ] {
      let inputs = try order.map { try fixture($0,depth:depth) }
      let result = try ChannelMerge.prepare(inputs,mode:mode).document
      let expected = try literalReference(filename)
      XCTAssertEqual(result.width,expected.width); XCTAssertEqual(result.height,expected.height)
      XCTAssertEqual(result.depth == .u8 ? 8 : 16,expected.depth)
      var actual = Data()
      let maximum = depth == .u8 ? 255 : 65535
      for c in order.indices { for y in 0..<result.height { for x in 0..<result.width {
        let word: Int
        if mode == .multichannel {
          let plane = try XCTUnwrap(result.alphaChannels?[c].pixels)
          word = Int((plane.pixel(x:x,y:y).r * Float(maximum)).rounded())
        } else if mode == .rgb {
          guard case .raster(let pixels) = result.layers[0].content else { return XCTFail("RGB raster") }
          let p = pixels.pixel(x:x,y:y)
          word = Int(([p.r,p.g,p.b][c] * Float(maximum)).rounded())
        } else {
          let native = try XCTUnwrap(result.layers[0].nativeMode)
          let value = Int(native.rawWord(component:c,index:y*result.width+x))
          word = mode == .cmyk ? maximum - value : value
        }
        if depth == .u16 { actual.append(UInt8(word >> 8)) }
        actual.append(UInt8(word & 255))
      } } }
      XCTAssertEqual(actual,expected.raw,filename)
      if mode == .multichannel {
        XCTAssertTrue(result.isChannelOnly); XCTAssertTrue(result.layers.isEmpty)
        XCTAssertEqual(result.alphaChannels?.map(\.name),order.indices.map { "Alpha \($0+1)" })
      }
      XCTAssertTrue(result.profileIsUntagged == true)
      for format in PSDFileFormat.allCases {
        let bytes = try PSDCodec.writeRasterLayers(result,format:format), reopened = try PSDCodec.read(bytes)
        XCTAssertEqual(reopened.colorMode,result.colorMode)
        if mode == .cmyk || mode == .lab { XCTAssertEqual(try reopened.layers[0].nativeMode?.planes,try result.layers[0].nativeMode?.planes) }
      }
    }
  }
  func testComplete16BitWordGridMatchesEveryPhotoshopRGBReferenceWord() throws {
    var gray = try NativeModeRaster(width:256,height:256,mode:.grayscale,depth:.u16)
    for i in 0..<65536 { try gray.set(Float(i)/65535,component:0,index:i); try gray.set(1,component:1,index:i) }
    var source = try CraftDocument(width:256,height:256,depth:.u16)
    source.modeDescriptor = try .init(mode:.grayscale,depth:.u16,profile:gray.profile)
    source.layers[0].nativeMode = gray; source.layers[0].content = .raster(try gray.surface()); source.layers[0].background = true
    var inputs = [CraftDocument]()
    for _ in 0..<3 { var copy = source; copy.id = UUID(); inputs.append(copy) }
    let output = try ChannelMerge.prepare(inputs,mode:.rgb).document, expected = try reference("photoshop-merge-rgb16-full-grid")
    guard case .raster(let actual) = output.layers[0].content, case .raster(let oracle) = expected.layers[0].content else { return XCTFail("RGB") }
    XCTAssertEqual(try actual.rgbaData(depth:.u16),try oracle.rgbaData(depth:.u16))
  }
  func testFloat32MergeRetainsNegativeAndHDRWordsAndRejectsUnsupportedModes() throws {
    let sources = try (0..<3).map { try fixture($0,depth:.f32) }, result = try ChannelMerge.prepare(sources,mode:.rgb).document
    guard case .raster(let rgb) = result.layers[0].content else { return XCTFail("RGB") }
    XCTAssertEqual(rgb.colorEncoding,.linearRGB)
    for i in 0..<192 {
      let p = rgb.linearPixel(x:i%16,y:i/16)
      for (c,v) in [p.r,p.g,p.b].enumerated() { XCTAssertEqual(v.bitPattern,sources[c].layers[0].nativeMode?.rawWord(component:0,index:i)) }
      XCTAssertEqual(p.a,1)
    }
    for mode in [ChannelMergeMode.lab,.cmyk,.multichannel] { XCTAssertThrowsError(try ChannelMerge.prepare(sources,mode:mode)) }
  }
  func test56AuxiliaryOnlyChannelsKeepNativePSDAndPSBStorageAndLimit() throws {
    let sources = try (0..<56).map { try fixture($0,depth:.u16) }
    let result = try ChannelMerge.prepare(sources,mode:.multichannel).document
    XCTAssertTrue(result.isChannelOnly); XCTAssertNil(result.inkMode); XCTAssertEqual(result.alphaChannels?.count,56)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)),result)
    for format in PSDFileFormat.allCases {
      let read = try PSDCodec.read(PSDCodec.writeRasterLayers(result,format:format))
      XCTAssertTrue(read.isChannelOnly); XCTAssertEqual(read.alphaChannels?.count,56)
      for i in 0..<56 { XCTAssertEqual(try read.alphaChannels?[i].pixels.rgbaData(depth:.u16),try result.alphaChannels?[i].pixels.rgbaData(depth:.u16)) }
    }
    var tooMany = result; tooMany.alphaChannels?.append(try XCTUnwrap(result.alphaChannels?.first).withFreshMergeTestID())
    XCTAssertThrowsError(try tooMany.validate())
    var quick = result
    quick.quickMask = AlphaChannel(name:"Quick Mask",pixels:try Surface(width:16,height:12,depth:.u16,fill:.white))
    XCTAssertThrowsError(try quick.validate())
    quick.alphaChannels?.removeLast(); XCTAssertNoThrow(try quick.validate())
  }
  func testInvalidSourcesCountsAndDuplicateDocumentsRejectWithoutChangingSources() throws {
    let source = try fixture(0), other = try fixture(1), before = source
    XCTAssertThrowsError(try ChannelMerge.prepare([source,source,other],mode:.rgb))
    XCTAssertThrowsError(try ChannelMerge.prepare([source,other],mode:.rgb))
    var wrong = try fixture(2); wrong.layers[0].opacity = 0.5
    XCTAssertNotNil(ChannelMerge.unavailableReason(wrong)); XCTAssertThrowsError(try ChannelMerge.prepare([source,other,wrong],mode:.rgb))
    XCTAssertEqual(source,before)
    for mode in [ChannelMergeMode.cmyk,.lab] { for depth in [PixelDepth.u8,.u16] {
      let count = mode.components.count, inputs = try (0..<count).map { try fixture($0,depth:depth) }
      XCTAssertNoThrow(try ChannelMerge.prepare(inputs,mode:mode))
    } }
  }
  @MainActor func testPublicationRollsBackNewDocumentBeforeClosingAnySource() throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces:WorkspaceLibrary())
    let files = try (0..<3).map { CraftNSDocument(model:try fixture($0)) }
    for file in files { controller.addDocument(file); file.store.renderTask?.cancel() }
    defer { for file in controller.documents.compactMap({$0 as? CraftNSDocument}) { controller.removeDocument(file) } }
    let plan = try ChannelMerge.prepare(files.map { $0.store.document },mode:.rgb)
    XCTAssertThrowsError(try controller.publishChannelMerge(plan,sources:files,display:false) { _ in throw CraftError.invalid("Owned registration failure") })
    XCTAssertEqual(controller.documents.count,3); XCTAssertTrue(files.allSatisfy { $0.ownerController === controller })
    XCTAssertEqual(files.map { $0.store.document },plan.sources)
  }
}
private extension AlphaChannel {
  func withFreshMergeTestID() -> AlphaChannel { var value = self; value.id = UUID(); return value }
}

extension ChannelMergeWorkflowTests {
  @MainActor func withGrayShares(_ body: @MainActor (AutomationService,[CraftNSDocument],[[String:String]]) async throws -> Void) async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,first in
      first.store.renderTask?.cancel(); first.store.session = EditorSession(document:try self.fixture(0))
      let second = CraftNSDocument(model:try self.fixture(1)), third = CraftNSDocument(model:try self.fixture(2))
      service.controller.addDocument(second); service.controller.addDocument(third)
      let files = [first,second,third]
      defer { for file in service.controller.documents.compactMap({$0 as? CraftNSDocument}) where file !== first { file.store.renderTask?.cancel(); service.controller.removeDocument(file) } }
      for file in files { file.store.renderTask?.cancel(); try service.share(file) }
      service.setDocumentTransfersEnabled(true); service.setDocumentClosingEnabled(true)
      let inputs = try files.map { file -> [String:String] in
        ["shareID":try XCTUnwrap(service.shares.first(where:{$0.document === file})).id.uuidString,"revision":service.revision(file.store)]
      }
      try await body(service,files,inputs)
    }
  }
  @MainActor func testUnusedAnchorAndItsShareRemainOpenWhenOnlyTwoOtherSourcesMerge() async throws {
    try await withGrayShares { service,files,inputs in
      let helper = AutomationTests(), original = files[0].store.document
      let response = try await helper.request(service,path:"/v1/documents/\(inputs[0]["shareID"]!)/commands",body:["command":ChannelMergeAPI.name,"revision":inputs[0]["revision"]!,"parameters":["mode":"multichannel","sources":Array(inputs.dropFirst())]])
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self))
      XCTAssertTrue(files[0].ownerController === service.controller); XCTAssertEqual(files[0].store.document,original)
      XCTAssertNil(files[1].ownerController); XCTAssertNil(files[2].ownerController)
      XCTAssertEqual(service.shares.count,2); XCTAssertTrue(service.shares.contains { $0.id.uuidString == inputs[0]["shareID"] })
      let result = try XCTUnwrap(service.controller.documents.compactMap({$0 as? CraftNSDocument}).first { $0 !== files[0] })
      XCTAssertTrue(result.store.document.isChannelOnly); XCTAssertEqual(result.store.document.alphaChannels?.count,2)
      XCTAssertNil(result.fileURL); XCTAssertTrue(result.isDocumentEdited); XCTAssertTrue(result.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testAPIRejectsPermissionStaleBusyDuplicateAndUnsharedInputsWithoutPublication() async throws {
    try await withGrayShares { service,files,inputs in
      let helper = AutomationTests(), before = files.map { $0.store.document }
      @MainActor func request(_ sources: [[String:String]]) async throws -> Int {
        try await helper.request(service,path:"/v1/documents/\(inputs[0]["shareID"]!)/commands",body:["command":ChannelMergeAPI.name,"revision":inputs[0]["revision"]!,"parameters":["mode":"rgb","sources":sources]]).0.statusCode
      }
      service.setDocumentClosingEnabled(false); let denied = try await request(inputs); XCTAssertEqual(denied,403)
      service.setDocumentClosingEnabled(true); service.setDocumentTransfersEnabled(false); let deniedTransfer = try await request(inputs); XCTAssertEqual(deniedTransfer,403)
      service.setDocumentTransfersEnabled(true)
      var stale = inputs; stale[1]["revision"] = "old"; let staleCode = try await request(stale); XCTAssertEqual(staleCode,409)
      let duplicate = try await request([inputs[0],inputs[0],inputs[2]]); XCTAssertEqual(duplicate,400)
      files[1].store.geometryBusy = true; let busy = try await request(inputs); XCTAssertEqual(busy,409); files[1].store.geometryBusy = false
      var missing = inputs; missing[1]["shareID"] = UUID().uuidString; let notFound = try await request(missing); XCTAssertEqual(notFound,404)
      XCTAssertEqual(service.controller.documents.count,3); XCTAssertEqual(files.map { $0.store.document },before)
      XCTAssertTrue(files.allSatisfy { $0.ownerController === service.controller && $0.store.session.undoStack.isEmpty })
    }
  }
  @MainActor func testCancellationRevocationAndSourceChangesCannotPublishLateResults() async throws {
    for action in ["cancel","revoke","edit","closingPermission"] {
      try await withGrayShares { service,files,inputs in
        let gate = MergeChannelTestGate(), helper = AutomationTests()
        files[0].store.mergeChannelsPreparation = { sources,mode,profile,name in
          gate.markStarted()
          guard gate.resume.wait(timeout:.now()+5) == .success else { throw CraftError.invalid("Owned test preparation gate timed out") }
          try Task.checkCancellation()
          return try ChannelMerge.prepare(sources,mode:mode,profile:profile,name:name)
        }
        let operation = Task { try await helper.request(service,path:"/v1/documents/\(inputs[0]["shareID"]!)/commands",body:["command":ChannelMergeAPI.name,"revision":inputs[0]["revision"]!,"parameters":["mode":"rgb","sources":inputs]]) }
        var entered = false
        for _ in 0..<200 {
          if gate.hasStarted { entered = true; break }
          try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertTrue(entered,"Preparation should reach the owned gate")
        if action == "cancel" {
          let cancel = try await helper.request(service,path:"/v1/documents/\(inputs[0]["shareID"]!)/commands",body:["command":ChannelMergeAPI.cancel,"revision":inputs[0]["revision"]!,"parameters":[:]])
          XCTAssertEqual(cancel.0.statusCode,200)
        } else if action == "revoke" { service.revoke(UUID(uuidString:inputs[1]["shareID"]!)!) }
        else if action == "edit" { var changed = files[1].store.document; changed.name = "Changed while preparing"; files[1].store.session = EditorSession(document:changed) }
        else { service.setDocumentClosingEnabled(false) }
        gate.resume.signal()
        let response = try await operation.value
        XCTAssertEqual(response.0.statusCode,409,action+": "+String(decoding:response.1,as:UTF8.self))
        XCTAssertEqual(service.controller.documents.count,3)
        XCTAssertTrue(files.allSatisfy { $0.ownerController === service.controller })
        XCTAssertTrue(files.allSatisfy { !$0.store.geometryBusy })
        XCTAssertNil(service.mergeChannelsTask)
      }
    }
  }
  @MainActor func testNativeModeAndAssignmentValidationPreserveOpeningOrderAndCancel() throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces:WorkspaceLibrary())
    let files = try (0..<3).map { CraftNSDocument(model:try fixture($0)) }
    for file in files { controller.addDocument(file); file.store.renderTask?.cancel() }
    defer { for file in files { controller.removeDocument(file) } }
    let model = ChannelMergeWorkspace(controller:controller,anchor:files[2]); controller.channelMergeWorkspace = model
    XCTAssertEqual(model.sources.map { $0.store.document.id },files.map { $0.store.document.id })
    XCTAssertEqual(model.mode,.multichannel); XCTAssertEqual(model.countText,"3")
    model.countText = "0"; model.advance(); XCTAssertEqual(model.stage,0); XCTAssertNotNil(model.error)
    model.countText = "2"; model.advance(); XCTAssertEqual(model.assignments,[0,1]); XCTAssertEqual(model.stage,1)
    model.advance(); XCTAssertEqual(model.stage,2)
    model.assignments = [0,0]; model.advance(); XCTAssertNotNil(model.error); XCTAssertFalse(model.busy)
    model.cancel(); XCTAssertNil(controller.channelMergeWorkspace)
    XCTAssertEqual(controller.documents.count,3); XCTAssertTrue(files.allSatisfy { $0.ownerController === controller })
  }
}
private final class MergeChannelTestGate: @unchecked Sendable {
  private let lock = NSLock()
  private var entered = false
  func markStarted() { lock.withLock { entered = true } }
  var hasStarted: Bool { lock.withLock { entered } }
  let resume = DispatchSemaphore(value:0)
}

extension ChannelMergeWorkflowTests {
  func testMaximumLogicalPhotoshopGeometryRemainsSparseForRGBAnd56Channels() throws {
    let side = 300_000
    var gray = try NativeModeRaster(width:side,height:side,mode:.grayscale,depth:.u16)
    gray = try gray.replacingOpacity(with:Surface(width:side,height:side,depth:.u16,fill:.white))
    var source = try CraftDocument(width:side,height:side,depth:.u16)
    source.modeDescriptor = try .init(mode:.grayscale,depth:.u16,profile:gray.profile)
    source.layers[0].nativeMode = gray; source.layers[0].content = .raster(try gray.surface()); source.layers[0].background = true
    var inputs = [CraftDocument]()
    for _ in 0..<56 { var copy = source; copy.id = UUID(); inputs.append(copy) }
    let rgb = try ChannelMerge.prepare(Array(inputs.prefix(3)),mode:.rgb).document
    XCTAssertEqual(rgb.width,side); XCTAssertEqual(rgb.height,side)
    guard case .raster(let pixels) = rgb.layers[0].content else { return XCTFail("RGB") }
    XCTAssertEqual(pixels.tileCount,0); XCTAssertEqual(pixels.mappedTileCount,0); XCTAssertEqual(pixels.allocatedBytes,pixels.residentTileIndexEstimate); XCTAssertEqual(pixels.pixel(x:side-1,y:side-1),.black)
    let multi = try ChannelMerge.prepare(inputs,mode:.multichannel).document
    XCTAssertEqual(multi.alphaChannels?.count,56)
    XCTAssertTrue(multi.alphaChannels?.allSatisfy { $0.pixels.tileCount == 0 && $0.pixels.mappedTileCount == 0 && $0.pixels.allocatedBytes == $0.pixels.residentTileIndexEstimate } == true)
    XCTAssertEqual(multi.alphaChannels?[55].pixels.pixel(x:side-1,y:side-1),.black)
    // Logical geometry/sparse admission, not a dense90GP or physical-capacity claim.
  }
}

extension ChannelMergeWorkflowTests {
  func testNativeOutputModeAvailabilityRequiresEnoughSourcesAndSupportedDepth() {
    for count in 0...60 { for depth in PixelDepth.allCases {
      XCTAssertEqual(ChannelMergeMode.rgb.canChoose(sourceCount:count,depth:depth),count >= 3)
      XCTAssertEqual(ChannelMergeMode.cmyk.canChoose(sourceCount:count,depth:depth),count >= 4 && depth != .f32)
      XCTAssertEqual(ChannelMergeMode.lab.canChoose(sourceCount:count,depth:depth),count >= 3 && depth != .f32)
      XCTAssertEqual(ChannelMergeMode.multichannel.canChoose(sourceCount:count,depth:depth),count >= 2 && depth != .f32)
    } }
  }
}

extension ChannelMergeWorkflowTests {
  @MainActor func testAPIAvailabilityDoesNotAdvertiseAnIneligibleRGBAnchor() async throws {
    try await withGrayShares { service,files,_ in
      XCTAssertEqual(service.channelMergeState(files[0])["available"] as? Bool,true)
      let rgb = CraftNSDocument(model:try CraftDocument(width:16,height:12))
      service.controller.addDocument(rgb); rgb.store.renderTask?.cancel(); try service.share(rgb)
      let state = service.channelMergeState(rgb)
      XCTAssertEqual(state["eligibleSharedSources"] as? Int,3)
      XCTAssertEqual(state["available"] as? Bool,false)
      XCTAssertFalse(state.keys.contains("sources"))
      let value = try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:state))
      XCTAssertNoThrow(try BrushAPI.merge(value,schema:ChannelMergeAPI.stateSchema))
    }
  }
}
