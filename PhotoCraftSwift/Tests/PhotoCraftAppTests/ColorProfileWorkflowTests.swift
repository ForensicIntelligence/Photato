import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ColorProfileWorkflowTests: XCTestCase {
  func profile(_ name: CFString, depth: PixelDepth = .u16) throws -> Data {
    let data = try XCTUnwrap(CGColorSpace(name: name)?.copyICCData() as Data?)
    return try NativeModeProfile.atDepth(data, mode: ProofSettings.mode(of: data), depth: depth)
  }
  func fixture(_ depth: PixelDepth = .u16) throws -> CraftDocument {
    var d = try CraftDocument(width: 3, height: 1, depth: depth)
    var s = try Surface(width: 3, height: 1, depth: depth)
    s.setPixel(x: 0, y: 0, Pixel(0.2, 0.6, 0.8, 0.7))
    s.setPixel(x: 1, y: 0, Pixel(0.8, 0.3, 0.1, 0))
    s.setPixel(x: 2, y: 0, Pixel(0.1, 0.1, 0.1, 1))
    d.layers[0].content = .raster(s); return d
  }
  func apply(_ request: ColorProfileRequest, _ d: CraftDocument) throws -> CraftDocument {
    var s = EditorSession(document: d); try s.execute(ColorProfileInput.command(request, in: d)); return s.document
  }
  func testAssignRetainsEverySampleAndUndoArchiveForAllRGBDepths() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth), p3 = try profile(CGColorSpace.displayP3, depth: depth)
      let request = ColorProfileRequest(.assign, profile: p3)
      let command = try ColorProfileInput.command(request, in: source)
      var session = EditorSession(document: source); try session.execute(command)
      let changed = session.document
      XCTAssertEqual(changed.layers, source.layers); XCTAssertEqual(changed.workingICC, p3)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(changed)), changed)
      XCTAssertThrowsError(try session.execute(command)); XCTAssertEqual(session.document, changed)
      try session.undo(); XCTAssertEqual(session.document, source)
      try session.redo(); XCTAssertEqual(session.document, changed)
    }
  }
  func testNativeAssignmentRetainsCMYKAndGrayPlanesExactly() throws {
    for mode in [DocumentColorMode.cmyk, .grayscale, .lab, .rgb] {
      let source = try fixture().convertingMode(.init(mode: mode, depth: .u16))
      let profile = mode == .grayscale ? try self.profile(CGColorSpace.genericGrayGamma2_2) : try NativeModeProfile.standard(mode, depth: .u16)
      let result = try apply(.init(.assign, profile: profile), source)
      XCTAssertEqual(result.layers[0].nativeMode?.planes, source.layers[0].nativeMode?.planes)
      XCTAssertEqual(result.modeDescriptor?.profile, profile)
    }
  }
  func testConversionMatchesIndependentSRGBToDisplayP3MatrixAndRetainsHiddenAlpha() throws {
    let source = try fixture(), p3 = try profile(CGColorSpace.displayP3)
    let result = try apply(.init(.convert, profile: p3), source)
    guard case .raster(let before) = source.layers[0].content, case .raster(let after) = result.layers[0].content else { return XCTFail("raster") }
    // IEC sRGB transfer + published D65 RGB primary matrices; independent of ColorSync API.
    func linear(_ n: Float) -> Double { let x = Double(n); return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    func encoded(_ x: Double) -> Float { Float(x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055) }
    let matrix = [[0.82259287,0.17753395,0.0],[0.03319951,0.9667835,0.0],[0.01708535,0.07239572,0.91030148]]
    for x in 0..<3 {
      let p = before.pixel(x:x,y:0), q = after.pixel(x:x,y:0), values = [linear(p.r),linear(p.g),linear(p.b)]
      let expected = matrix.map { row in encoded(zip(row,values).reduce(0) { $0 + $1.0 * $1.1 }) }
      for (actual, expected) in zip([q.r,q.g,q.b],expected) { XCTAssertEqual(actual, expected, accuracy: 0.001) }
      XCTAssertEqual(q.a, p.a)
    }
    XCTAssertNotEqual(after.pixel(x:1,y:0).r, before.pixel(x:1,y:0).r)
    XCTAssertEqual(result.layers[0].id, source.layers[0].id)
  }
  func testConversionPreservesFloatExtendedSamples() throws {
    var source = try fixture(.f32)
    var s = try Surface(width:3,height:1,depth:.f32,colorEncoding:.linearRGB)
    s.setLinearPixel(x:0,y:0,Pixel(2.5,1.2,0.3,0.5)); s.setLinearPixel(x:1,y:0,Pixel(-0.1,0.2,0.3,0))
    source.layers[0].content = .raster(s)
    let result = try apply(.init(.convert,profile:profile(CGColorSpace.displayP3,depth:.f32)),source)
    guard case .raster(let out) = result.layers[0].content else {return XCTFail("raster")}
    XCTAssertGreaterThan(out.linearPixel(x:0,y:0).r,2)
    XCTAssertLessThan(out.linearPixel(x:1,y:0).r,0)
    XCTAssertEqual(out.linearPixel(x:0,y:0).a,0.5)
  }
  func testUntaggedNative49PSDAndNumericIdentity() throws {
    let source = try fixture()
    var request = ColorProfileRequest(.assign,profile:try NativeModeProfile.standard(.rgb,depth:.u16));request.removeProfile=true
    let result = try apply(request,source)
    XCTAssertEqual(result.layers,source.layers);XCTAssertEqual(result.minimumArchiveVersion,49)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)),result)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
    let psd=try DocumentIO.encode(result,format:.psd), read=try PSDCodec.read(psd)
    XCTAssertEqual(read.profileIsUntagged,true);XCTAssertNil(read.sourceICC)
    XCTAssertNil(try PSDCodec.read(DocumentIO.encode(source,format:.psd)).profileIsUntagged)
    let tiff=try DocumentIO.encode(result,format:.tiff)
    XCTAssertEqual(try RasterIO.read(tiff).profileIsUntagged, true)
    if let directory = ProcessInfo.processInfo.environment["PHOTATO_PROFILE_EVIDENCE"] {
      let url = URL(fileURLWithPath: directory); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      for (name, data) in [("untagged.psd", psd), ("untagged.tiff", tiff), ("untagged.png", try DocumentIO.encode(result,format:.png)), ("untagged.jpg", try DocumentIO.encode(result,format:.jpeg)), ("untagged.photato", try NativeArchive.encodeChunked(result))] {
        try data.write(to:url.appendingPathComponent(name))
      }
    }
  }
  func testNativeConversionPreservesAlphaAndProfilesAcrossPSDAndTIFF() throws {
    let source=try fixture().convertingMode(.init(mode:.cmyk,depth:.u16))
    for mode in [DocumentColorMode.rgb,.grayscale,.lab] {
      let result=try apply(.init(.convert,profile:NativeModeProfile.standard(mode,depth:.u16)),source)
      XCTAssertEqual(result.layers[0].nativeMode?.planes.last,source.layers[0].nativeMode?.planes.last)
      for format in [DocumentIO.Format.psd,.tiff] {
        let bytes=try DocumentIO.encode(result,format:format),read=try RasterIO.read(bytes)
        let restored = try mode == .rgb ? read.convertingMode(.init(mode: .rgb, depth: .u16, profile: result.modeDescriptor?.profile)) : read
        XCTAssertEqual(restored.layers[0].nativeMode?.planes,result.layers[0].nativeMode?.planes)
      }
    }
  }
  func testEditableRGBFillAndTextRetainedAndComplexMergeExplicit() throws {
    var source=try fixture()
    source.layers.append(Layer(name:"Color",content:.fill(Pixel(0.2,0.4,0.8))))
    source.layers.append(Layer(name:"Type",content:.text(.init(text:"Editable",size:12,color:Pixel(0.2,0.4,0.8)))))
    let result=try apply(.init(.convert,profile:profile(CGColorSpace.displayP3)),source)
    XCTAssertEqual(result.layers.map(\.id),source.layers.map(\.id))
    guard case .text(let text)=result.layers.last?.content else{return XCTFail("live text lost")}
    XCTAssertEqual(text.text,"Editable");XCTAssertNotEqual(text.color,Pixel(0.2,0.4,0.8))
    var cmyk=ColorProfileRequest(.convert,profile:try NativeModeProfile.standard(.cmyk,depth:.u16))
    XCTAssertThrowsError(try apply(cmyk,source));cmyk.mergeVisible=true
    XCTAssertEqual(try apply(cmyk,source).layers.count,1)
  }
  @MainActor func testPreviewCancelCommitAndBusyState() async throws {
    let original=try fixture(),store=EditorStore(document:original)
    defer{store.cancelColorProfile();store.renderTask?.cancel()}
    store.beginColorProfile(.assign);let draft=try XCTUnwrap(store.colorProfileWorkspace)
    try draft.loadProfile(profile(CGColorSpace.displayP3));await draft.task?.value
    XCTAssertTrue(draft.ready,draft.error ?? "no preview");XCTAssertTrue(store.hasToneDraft)
    XCTAssertEqual(store.document,original);XCTAssertFalse(store.canBeginColorProfile)
    store.cancelColorProfile();XCTAssertEqual(store.document,original)
    store.beginColorProfile(.assign);let commit=try XCTUnwrap(store.colorProfileWorkspace)
    try commit.loadProfile(profile(CGColorSpace.displayP3));await commit.task?.value
    store.commitColorProfile();await commit.commitTask?.value
    XCTAssertNil(store.colorProfileWorkspace,commit.error ?? "commit did not finish")
    XCTAssertEqual(store.document.layers,original.layers)
    XCTAssertNotEqual(store.document.workingICC,original.workingICC)
    try store.session.undo();XCTAssertEqual(store.document,original)
  }
  @MainActor func testFactoryProfileMenusAndCancelledCommit() async throws {
    let helper = PhotoshopMenuTests()
    try helper.withMenus { app, menu in
      for path in ["Edit > Assign Profile…", "Edit > Convert to Profile…"] {
        let item = try XCTUnwrap(helper.allItems(menu).first { $0.identifier?.rawValue == path })
        XCTAssertEqual(item.action, #selector(AppDelegate.colorProfileDialog(_:)))
      }
    }
    let original = try fixture(), store = EditorStore(document: original)
    defer { store.cancelColorProfile(); store.renderTask?.cancel() }
    store.beginColorProfile(.convert)
    let draft = try XCTUnwrap(store.colorProfileWorkspace)
    try draft.loadProfile(profile(CGColorSpace.displayP3)); await draft.task?.value
    store.commitColorProfile(); let task = draft.commitTask
    store.cancelColorProfile(); await task?.value
    XCTAssertEqual(store.document, original)
  }
  @MainActor func testAPIUsesSameEngineAndUntaggedVersionNegotiation() async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests(),p3=try profile(CGColorSpace.displayP3)
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let source=document.store.document
      let expected=try self.apply(.init(.assign,profile:p3),source)
      let assigned=try await helper.edit(service,document,"document.assignProfile",["profileBase64":p3.base64EncodedString()])
      XCTAssertEqual(assigned,200);XCTAssertEqual(document.store.document,expected)
      let removed=try await helper.edit(service,document,"document.assignProfile",["removeProfile":true])
      XCTAssertEqual(removed,200);XCTAssertEqual(document.store.document.profileIsUntagged,true)
      let share=try XCTUnwrap(service.shares.first)
      let old=try await files.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"48"])
      XCTAssertEqual(old.0.statusCode,422)
      let saved=try await files.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"49"])
      XCTAssertEqual(saved.0.statusCode,200,String(decoding:saved.1,as:UTF8.self))
      XCTAssertEqual(try NativeArchive.decode(saved.1),document.store.document)
      let invalid=try await helper.edit(service,document,"document.assignProfile",["profileBase64":p3.base64EncodedString(),"removeProfile":true])
      XCTAssertEqual(invalid,400)
      document.store.beginColorProfile(.assign)
      let busy=try await helper.edit(service,document,"document.convertProfile",["profileBase64":p3.base64EncodedString()])
      XCTAssertEqual(busy,409);document.store.cancelColorProfile()
    }
  }
}
