import XCTest
@testable import PhotoCraftCore

final class RasterFilterTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 9, height: 7, depth: depth)
    var surface = try Surface(width: 9, height: 7, depth: depth,
      colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
    for y in 0..<7 { for x in 0..<9 {
      let p = Pixel(Float(x) / 8, Float(y) / 6, x == 4 ? 1 : 0, x < 2 ? 0 : 1)
      if depth == .f32 { surface.setLinearPixel(x: x, y: y, p) }
      else { surface.setPixel(x: x, y: y, p) }
    } }
    document.layers[0].content = .raster(surface)
    return document
  }
  func pixels(_ document: CraftDocument) throws -> Surface {
    guard case .raster(let pixels) = document.layers[0].content else { throw CraftError.invalid("No raster") }
    return pixels
  }
  func testEveryFilterAtEveryDepthHistoryAndNativePersistence() throws {
    for depth in PixelDepth.allCases { for kind in RasterFilter.Kind.allCases {
      var original = try fixture(depth)
      if kind == .despeckle,case .raster(var pixels)=original.layers[0].content {var p=pixels.pixel(x:4,y:3);p.r+=0.025;pixels.setPixel(x:4,y:3,p);original.layers[0].content = .raster(pixels)}
      var session = EditorSession(document: original)
      var filter = RasterFilter(kind)
      if kind == .smartBlur {filter.classicDetail?.threshold=80}
      if kind == .customFilter {filter.otherVideo?.scale=2}
      if kind == .offset {filter.otherVideo?.horizontal=2}
      if kind == .tiles {filter.stylize?.count=2;filter.stylize?.maxOffset=80}
      if kind == .displace { filter.distortion?.map = .init(width:1,height:1,channels:2,samples:Data([150,90])) }
      if kind == .shear { filter.distortion?.points=[.init(0,0.5),.init(1,-0.5)] }
      if kind.isClassicDetail && !ClassicDetailSettings.depths(kind).contains(depth) {XCTAssertThrowsError(try session.execute(.applyFilter(original.layers[0].id,filter)));XCTAssertEqual(session.document,original);continue}
      if kind == .lensBlur && depth == .f32 { XCTAssertThrowsError(try session.execute(.applyFilter(original.layers[0].id,filter)));XCTAssertEqual(session.document,original);continue }
      if kind == .perspectiveWarp { filter.perspective?.planes=[.init(source:[PathPoint(0,0),PathPoint(8,0),PathPoint(8,6),PathPoint(0,6)],destination:[PathPoint(0,0),PathPoint(9,0),PathPoint(10,6),PathPoint(1,6)])] }
      if kind == .puppetWarp { filter.puppet?.pins = [.init(source:PathPoint(1,1)),.init(source:PathPoint(6,6),destination:PathPoint(7,4))] }
      if kind == .lensCorrection { filter.lens?.distortion = 40 }
      if kind == .adaptiveWideAngle { filter.wideAngle?.scale = 80 }
      if kind == .cameraRaw { filter.cameraRaw?.exposure = 1 }
      if kind == .liquify { filter.liquify?.strokes = [.init(size:6,points:[[4,4],[6,4]])] }
      try session.execute(.applyFilter(original.layers[0].id, filter))
      let changed = session.document
      XCTAssertNotEqual(changed, original, "\(kind) \(depth)")
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(changed)), changed)
      try session.undo(); XCTAssertEqual(session.document, original)
      try session.redo(); XCTAssertEqual(session.document, changed)
    } }
  }
  func testBoxBlurKnownImpulseAndConstantFields() throws {
    var document = try CraftDocument(width: 5, height: 1, depth: .f32)
    var s = try Surface(width: 5, height: 1, depth: .f32, fill: .black, colorEncoding: .linearRGB)
    s.setLinearPixel(x: 2, y: 0, .white)
    document.layers[0].content = .raster(s)
    var box = RasterFilter(.boxBlur); box.radius = 1
    try Command.applyFilter(document.layers[0].id, box).apply(to: &document)
    let result = try pixels(document)
    for x in 0..<5 { XCTAssertEqual(result.linearPixel(x: x, y: 0).r, (1...3).contains(x) ? 1/3 : 0, accuracy: 0.000001) }
    for kind in [RasterFilter.Kind.boxBlur, .gaussianBlur, .motionBlur, .mosaic, .average] {
      document.layers[0].content = .raster(try Surface(width: 5, height: 1, depth: .f32, fill: Pixel(0.25, 0.5, 0.75)))
      let before = try pixels(document)
      try Command.applyFilter(document.layers[0].id, RasterFilter(kind)).apply(to: &document)
      XCTAssertEqual(try pixels(document).pixel(x: 0, y: 0).r, before.pixel(x: 0, y: 0).r, accuracy: 0.00001)
    }
  }
  func testAverageUsesSelectedPixelsAndOutsideRemainsExact() throws {
    var document = try fixture()
    document.selection = IntRect(x: 4, y: 2, width: 2, height: 2)
    let before = try pixels(document)
    try Command.applyFilter(document.layers[0].id, RasterFilter(.average)).apply(to: &document)
    let after = try pixels(document)
    XCTAssertEqual(after.pixel(x: 4, y: 2).r, (before.pixel(x: 4, y: 2).r + before.pixel(x: 5, y: 2).r)/2, accuracy: 1/255)
    XCTAssertEqual(after.pixel(x: 4, y: 2), after.pixel(x: 5, y: 3))
    for y in 0..<7 { for x in 0..<9 where !document.selection!.contains(x, y) {
      XCTAssertTrue(before.pixel(x: x, y: y).hasSameBits(as: after.pixel(x: x, y: y)))
    } }
  }
  func testLocksAndSelectionUseNativeCoordinates() throws {
    var document = try fixture()
    document.layers[0].x = 2
    document.selection = IntRect(x: 5, y: 1, width: 1, height: 1)
    let before = document
    try Command.applyFilter(document.layers[0].id, RasterFilter(.addNoise)).apply(to: &document)
    let old = try pixels(before), new = try pixels(document)
    for y in 0..<7 { for x in 0..<9 where x != 3 || y != 1 {
      XCTAssertEqual(new.pixel(x: x, y: y), old.pixel(x: x, y: y))
    } }
    document = before; document.selection = nil
    document.layers[0].protection = [.transparency]
    try Command.applyFilter(document.layers[0].id, RasterFilter(.boxBlur)).apply(to: &document)
    let locked = try pixels(document)
    for y in 0..<7 { for x in 0..<9 { XCTAssertEqual(old.pixel(x: x, y: y).a, locked.pixel(x: x, y: y).a) } }
    document.layers[0].protection = [.image]
    let protected = document
    XCTAssertThrowsError(try Command.applyFilter(document.layers[0].id, RasterFilter(.boxBlur)).apply(to: &document))
    XCTAssertEqual(document, protected)
  }
  func testNoiseSeedAndMonochromaticCorrelation() throws {
    var original = try CraftDocument(width: 20, height: 20)
    original.layers[0].content = .raster(try Surface(width: 20, height: 20, fill: Pixel(0.5,0.5,0.5)))
    var a = original, b = original
    var filter = RasterFilter(.addNoise)
    try Command.applyFilter(a.layers[0].id, filter).apply(to: &a)
    try Command.applyFilter(b.layers[0].id, filter).apply(to: &b)
    XCTAssertEqual(a, b)
    let samples = try pixels(a)
    for y in 0..<20 { for x in 0..<20 {
      let p = samples.pixel(x: x, y: y); XCTAssertEqual(p.r,p.g); XCTAssertEqual(p.g,p.b)
    } }
    filter.seed = 9; b = original
    try Command.applyFilter(b.layers[0].id, filter).apply(to: &b)
    XCTAssertNotEqual(a, b)
  }
  func testStrictJSONAndInvalidParametersRejectWithoutEditing() throws {
    for json in [#"{"kind":"mosaic","radius":1}"#, #"{"kind":"boxBlur","radius":0.5}"#,
      #"{"kind":"addNoise","seed":-1}"#, #"{"kind":"unsharpMask","amount":true}"#,
      #"{"kind":"addNoise","monochromatic":1}"#, #"{"kind":"unknown"}"#] {
      XCTAssertThrowsError(try RasterFilter.decodeJSON(Data(json.utf8)), json)
    }
    var document = try fixture(); let original = document
    var filter = RasterFilter(.gaussianBlur); filter.radius = .nan
    XCTAssertThrowsError(try Command.applyFilter(document.layers[0].id, filter).apply(to: &document))
    XCTAssertEqual(document, original)
  }
  func testActionDescriptorsShareNativeEngineAndRejectUnknownOptions() throws {
    for kind in RasterFilter.Kind.allCases where kind != .shadowsHighlights && !kind.isClassicDetail && !kind.isOtherVideo && !kind.isRender && !kind.isStylize && !kind.isPixelate && !kind.isDistortion && kind != .liquify && kind != .cameraRaw && kind != .puppetWarp && kind != .perspectiveWarp && kind != .blurGallery && kind != .lensCorrection && kind != .adaptiveWideAngle && kind != .filterGallery && kind != .smartSharpen && kind != .reduceNoise && kind != .lensBlur {
      var descriptor: [String: Any] = ["_obj": kind == .average ? "$Avrg" : kind == .boxBlur ? "boxblur" : kind.rawValue]
      let filter = RasterFilter(kind)
      func unit(_ value: Double, _ unit: String) -> [String: Any] { ["_unit": unit, "_value": value] }
      if kind.parameters.contains("radius") { descriptor["radius"] = unit(filter.radius, "pixelsUnit") }
      if kind.parameters.contains("amount") { descriptor["amount"] = unit(filter.amount, "percentUnit") }
      if kind == .unsharpMask { descriptor["threshold"] = 0 }
      if kind == .motionBlur { descriptor["angle"] = unit(0, "angleUnit"); descriptor["distance"] = unit(10, "pixelsUnit") }
      if kind == .mosaic { descriptor["cellSize"] = unit(10, "pixelsUnit") }
      if kind == .addNoise { descriptor["distribution"] = ["_enum":"distribution", "_value":"uniformDistribution"]; descriptor["monochromatic"] = true }
      let text = String(decoding: try JSONSerialization.data(withJSONObject: [descriptor]), as: UTF8.self)
      let original = try fixture(); var expected = original
      try Command.applyFilter(original.layers[0].id, filter).apply(to: &expected)
      XCTAssertEqual(try PhotoshopActionProgram(actionJSON: text).applying(to: original).session.document, expected)
      descriptor["unsupported"] = true
      XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON: String(decoding: JSONSerialization.data(withJSONObject: [descriptor]), as: UTF8.self)))
    }
  }
}
