import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PrintOutputTests: XCTestCase {
  func document(width: Int = 300, height: Int = 600) throws -> CraftDocument {
    var d = try CraftDocument(width: width, height: height); d.resolution = 300
    d.layers = [Layer(name: "Owned print fixture", content: .raster(try Surface(width: width, height: height, fill: Pixel(0.2, 0.4, 0.8))))]
    d.activeLayerID = d.layers[0].id; return d
  }
  func testPhysicalSizeOrientationTopLeftAndClipping() throws {
    let d = try document(); var s = PrintSettings(); s.scaleToFit = false
    let a = try PrintLayout(document: d, settings: s)
    XCTAssertEqual(a.image, CGRect(x: 270, y: 324, width: 72, height: 144)); XCTAssertEqual(a.effectivePPI, 300); XCTAssertFalse(a.clipped)
    s.orientation = .landscape; s.center = false; s.left = 27; s.top = 54; s.scalePercent = 200
    let b = try PrintLayout(document: d, settings: s)
    XCTAssertEqual(b.page.size, CGSize(width: 792, height: 612)); XCTAssertEqual(b.image, CGRect(x: 27, y: 270, width: 144, height: 288)); XCTAssertEqual(b.effectivePPI, 150)
    s.left = -20; XCTAssertTrue(try PrintLayout(document: d, settings: s).clipped)
  }
  func testFitMediaSelectionAndMarksReserveSpace() throws {
    var d = try document(); d.selection = IntRect(x: 30, y: 60, width: 100, height: 200)
    var s = PrintSettings(); s.selectedArea = true
    let a = try PrintLayout(document: d, settings: s); XCTAssertEqual(a.source, d.selection); XCTAssertEqual(a.image.height, 756, accuracy: 0.00001)
    s.cornerCropMarks = true; let b = try PrintLayout(document: d, settings: s)
    XCTAssertEqual(b.image.height, 720, accuracy: 0.00001); XCTAssertLessThan(b.scalePercent, a.scalePercent)
    d.selection = nil; XCTAssertThrowsError(try PrintLayout(document: d, settings: s))
  }
  func testInvalidGeometryAndProfileRejectWithoutChangingSource() throws {
    let d = try document(width: 2, height: 1)
    var s = PrintSettings(); s.customWidth = .nan; XCTAssertThrowsError(try PrintLayout(document: d, settings: s))
    s = PrintSettings(); s.marginLeft = 700; XCTAssertThrowsError(try PrintLayout(document: d, settings: s))
    s = PrintSettings(); s.content = .hardProof; XCTAssertThrowsError(try PrintOutput.prepare(d, settings: s))
    s.colorHandling = .photatoManages; s.profile = Data(repeating: 0, count: 132); XCTAssertThrowsError(try PrintOutput.prepare(d, settings: s))
    s = PrintSettings(); s.copies = 0; XCTAssertThrowsError(try s.validate())
  }
  func testTransparentPixelsFlattenToPaperAndPreserveDocument() throws {
    var d = try document(width: 3, height: 1), surface = try Surface(width: 3, height: 1)
    surface.setPixel(x: 0, y: 0, Pixel(1, 0, 0, 0)); surface.setPixel(x: 1, y: 0, Pixel(1, 0, 0, 0.5)); surface.setPixel(x: 2, y: 0, .black)
    d.layers[0].content = .raster(surface); let original = d
    let image = try PrintOutput.prepare(d, settings: PrintSettings()).pages[0].image
    let bytes = try XCTUnwrap(image.dataProvider?.data as Data?)
    XCTAssertEqual(Array(bytes.prefix(3)), [255,255,255]); XCTAssertEqual(bytes[3], 255); XCTAssertEqual(bytes[4], 127, accuracy: 1); XCTAssertEqual(bytes[5], 127, accuracy: 1)
    XCTAssertEqual(image.alphaInfo, .none); XCTAssertEqual(d, original)
  }
  func testRetainedCMYKNumbersAndSeparationDensities() throws {
    var d = try document(width: 2, height: 1).convertingMode(.init(mode: .cmyk, depth: .u16))
    var native = try XCTUnwrap(d.layers[0].nativeMode)
    for c in 0..<4 { try native.set(Float(c + 1) / 10, component: c, index: 0); try native.set(0, component: c, index: 1) }
    try native.set(1, component: 4, index: 0); try native.set(1, component: 4, index: 1)
    d.layers[0].nativeMode = native; d.layers[0].content = .raster(try native.surface())
    var s = PrintSettings(); s.sixteenBit = true
    let composite = try PrintOutput.prepare(d, settings: s), bytes = try XCTUnwrap(composite.pages[0].image.dataProvider?.data as Data?)
    XCTAssertEqual(composite.pages[0].image.colorSpace?.model, .cmyk); XCTAssertEqual(composite.pages[0].image.bitsPerComponent, 16)
    for c in 0..<4 { let n = UInt16(bytes[c * 2]) << 8 | UInt16(bytes[c * 2 + 1]); XCTAssertEqual(Float(n) / 65535, native.value(component: c, index: 0), accuracy: 1/65535) }
    s.content = .separations; let split = try PrintOutput.prepare(d, settings: s)
    XCTAssertEqual(split.pages.map(\.label), ["Cyan", "Magenta", "Yellow", "Black"])
    for c in 0..<4 { let b = try XCTUnwrap(split.pages[c].image.dataProvider?.data as Data?), n = UInt16(b[0]) << 8 | UInt16(b[1]); XCTAssertEqual(Float(n) / 65535, 1 - native.value(component: c, index: 0), accuracy: 1/65535) }
    let pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: try split.pdf() as CFData)!)); XCTAssertEqual(pdf.numberOfPages, 4)
  }
  func testRGBPrinterProfileConversionMatchesIndependentColorReference() throws {
    let d = try document(width: 1, height: 1); var s = PrintSettings(); s.sixteenBit = true; s.colorHandling = .photatoManages
    let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)); s.profile = try XCTUnwrap(p3.copyICCData() as Data?)
    let image = try PrintOutput.prepare(d, settings: s).pages[0].image, b = try XCTUnwrap(image.dataProvider?.data as Data?)
    let source = try Renderer.composite(d).pixel(x: 0, y: 0)
    let expected = try XCTUnwrap(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [CGFloat(source.r), CGFloat(source.g), CGFloat(source.b), 1])?.converted(to: p3, intent: .relativeColorimetric, options: nil)?.components)
    for c in 0..<3 { let n = UInt16(b[c * 2]) << 8 | UInt16(b[c * 2 + 1]); XCTAssertEqual(Double(n) / 65535, Double(expected[c]), accuracy: 0.0001) }
  }
  func testHardProofDiffersFromDocumentAndIgnoresScreenWarnings() throws {
    let d = try document(width: 2, height: 1); var s = PrintSettings(); s.colorHandling = .photatoManages; s.profile = try NativeModeProfile.standard(.rgb, depth: .u16)
    let normal = try PrintOutput.prepare(d, settings: s).pages[0].image.dataProvider!.data! as Data
    s.content = .hardProof; s.simulatePaper = true; s.simulateBlack = true; var proof = ProofSettings()
    let hard = try PrintOutput.prepare(d, settings: s, proof: proof).pages[0].image.dataProvider!.data! as Data
    proof.enabled = true; proof.gamutWarning = true; proof.warningColor = Pixel(1,0,1)
    let warning = try PrintOutput.prepare(d, settings: s, proof: proof).pages[0].image.dataProvider!.data! as Data
    XCTAssertNotEqual(normal, hard); XCTAssertEqual(hard, warning)
  }
  func testLabNeutralPrintingAndGrayProfile() throws {
    let d = try document(width: 2, height: 1).convertingMode(.init(mode: .lab, depth: .u16))
    var s = PrintSettings(); s.colorHandling = .photatoManages; s.profile = try NativeModeProfile.standard(.grayscale, depth: .u16); s.sixteenBit = true
    let output = try PrintOutput.prepare(d, settings: s)
    XCTAssertEqual(output.pages[0].image.colorSpace?.model, .monochrome); XCTAssertEqual(output.pages[0].image.bitsPerComponent, 16)
    s.profile = try NativeModeProfile.standard(.lab, depth: .u16); XCTAssertThrowsError(try PrintOutput.prepare(d, settings: s))
  }
  func testPDFMediaBoxAndMarksRenderWithoutMutatingDocument() throws {
    let d = try document(width: 8, height: 4), original = d
    var s = PrintSettings(); s.paper = .a4; s.orientation = .landscape; s.labels = true; s.description = "Owned fixture"; s.cornerCropMarks = true; s.centerCropMarks = true; s.registrationMarks = true; s.border = 1; s.bleed = 2
    let prepared = try PrintOutput.prepare(d, settings: s), pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: try prepared.pdf() as CFData)!)), page = try XCTUnwrap(pdf.page(at: 1))
    XCTAssertEqual(pdf.numberOfPages, 1); XCTAssertEqual(page.getBoxRect(.mediaBox).width, 841.89, accuracy: 0.001); XCTAssertEqual(page.getBoxRect(.mediaBox).height, 595.28, accuracy: 0.001)
    let ctx = try XCTUnwrap(CGContext(data: nil, width: 842, height: 596, bitsPerComponent: 8, bytesPerRow: 842 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.drawPDFPage(page); XCTAssertNotNil(ctx.makeImage()); XCTAssertEqual(d, original)
  }
  func testAsymmetricPrintableAreaCenterAndIndependentInkPages() throws {
    let source = try document(width: 4, height: 3)
    var settings = PrintSettings(); settings.scaleToFit = false; settings.marginLeft = 72; settings.marginRight = 18; settings.marginTop = 90; settings.marginBottom = 36
    let layout = try PrintLayout(document: source, settings: settings)
    XCTAssertEqual(layout.image.midX, 333, accuracy: 0.00001); XCTAssertEqual(layout.image.midY, 369, accuracy: 0.00001)
    let ink = try PSDMultichannelTests().fixture(.u16)
    settings.content = .separations; settings.sixteenBit = true
    let output = try PrintOutput.prepare(ink, settings: settings)
    guard case .multichannel(let raster) = ink.inkMode else { return XCTFail("Missing plates") }
    XCTAssertEqual(output.pages.count, 3)
    for c in raster.plates.indices {
      let bytes = try XCTUnwrap(output.pages[c].image.dataProvider?.data as Data?)
      for i in 0..<12 { let n = UInt16(bytes[i * 2]) << 8 | UInt16(bytes[i * 2 + 1]); XCTAssertEqual(Float(n) / 65535, 1 - raster.plates[c].samples.value(at: i), accuracy: 1 / 65535) }
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/runs/20261028T185522Z-224-native-print")
    try output.pdf().write(to: root.appendingPathComponent("ink-pages-" + UUID().uuidString + ".pdf"))
    var cmykSettings = PrintSettings(); cmykSettings.sixteenBit = true
    let cmyk = try source.convertingMode(.init(mode: .cmyk, depth: .u16)), cmykOutput = try PrintOutput.prepare(cmyk, settings: cmykSettings)
    try cmykOutput.pdf().write(to: root.appendingPathComponent("cmyk-composite-" + UUID().uuidString + ".pdf"))
  }
  func testCancellationBeforePreparation() async throws {
    let d = try document(width: 3, height: 1)
    let task = Task { try await Task.sleep(for: .seconds(1)); return try PrintOutput.prepare(d, settings: PrintSettings()) }; task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
  }
}
