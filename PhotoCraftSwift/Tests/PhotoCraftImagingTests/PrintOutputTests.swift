import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PrintOutputTests: XCTestCase {
  func testSharedPhotoshopPrintFieldsIgnoreUnknownOrMalformedResources() throws {
    let output = try PSDDescriptor("printOutput", items: [
      .init("Inte", .enumerated(PSDID("Inte"), PSDID("Img "))),
      .init("printSixteenBit", .boolean(true)), .init("MpBl", .boolean(false)),
      .init("printerName", .text(Array("Fixture Printer\0".utf16))),
      .init("futureOption", .text(Array("kept by the resource writer".utf16)))
    ]).encoded()
    let style = try PSDDescriptor("printOutputOptions", items: [
      .init("CrnC", .boolean(true)), .init("CntC", .boolean(false)),
      .init("Lbls", .boolean(true)), .init("RgsM", .boolean(true))
    ]).encoded()
    let outputBlock = PSDImageResources.block(1082, data: output)
    let styleBlock = PSDImageResources.block(1083, data: style)
    var document = try CraftDocument(width: 2, height: 2)
    document.sourceMetadata = ["psdResources": outputBlock + styleBlock]
    var defaults = PrintSettings()
    defaults.paper = .a3
    defaults.centerCropMarks = true
    let imported = try XCTUnwrap(PhotoshopPrintSettings(document)).applying(to: defaults)
    XCTAssertEqual(imported.paper, .a3)
    XCTAssertEqual(imported.printerName, "Fixture Printer")
    XCTAssertEqual(imported.intent, .perceptual)
    XCTAssertTrue(imported.sixteenBit)
    XCTAssertFalse(imported.blackPointCompensation)
    XCTAssertTrue(imported.cornerCropMarks && imported.labels && imported.registrationMarks)
    XCTAssertFalse(imported.centerCropMarks)
    XCTAssertEqual(try PSDImageResources.preserved(outputBlock + styleBlock), outputBlock + styleBlock)

    var override = defaults
    override.labels = true
    override.printerName = "New fixture printer"
    override.intent = .relativeColorimetric
    let extra = PSDImageResources.block(1812, data: Data([0x18, 0x34, 0xfa]))
    let updated = try PhotoshopPrintSettings.writing(override, to: outputBlock + extra + styleBlock)
    let resources = try PSDImageResources.blocks(updated)
    XCTAssertEqual(resources.map(\.id), [1082, 1812, 1083])
    XCTAssertEqual(resources[1].raw, extra)
    let descriptor = try PSDDescriptor.read(resources[0].data)
    XCTAssertEqual(descriptor["futureOption"], .text(Array("kept by the resource writer".utf16)))
    document.sourceMetadata = ["psdResources": updated]
    let restored = try XCTUnwrap(PhotoshopPrintSettings(document)).applying(to: PrintSettings())
    XCTAssertEqual(restored.intent, .relativeColorimetric)
    XCTAssertEqual(restored.printerName, "New fixture printer")
    XCTAssertTrue(restored.labels)
    XCTAssertFalse(restored.sixteenBit)

    document.sourceMetadata = ["psdResources": outputBlock + outputBlock + styleBlock]
    let duplicate = try XCTUnwrap(PhotoshopPrintSettings(document)).applying(to: defaults)
    XCTAssertFalse(duplicate.sixteenBit)
    XCTAssertTrue(duplicate.cornerCropMarks)
    document.sourceMetadata = ["psdResources": PSDImageResources.block(1082, data: Data([1, 2]))]
    XCTAssertNil(PhotoshopPrintSettings(document))
  }

  func testFitMediaKeepsEverySourcePixelOfAFourThousandPixelPhoto() throws {
    let width = 4000, height = 3000
    var source = try CraftDocument(width: width, height: height, depth: .u16)
    var pixels = try Surface(width: width, height: height, depth: .u16, fill: .white)
    pixels.setPixel(x: 2000, y: 261, Pixel(1, 0, 0))
    pixels.setPixel(x: 2000, y: 262, Pixel(0, 0, 1))
    pixels.setPixel(x: width - 1, y: height - 1, .black)
    source.layers[0].content = .raster(pixels)
    var settings = PrintSettings()
    settings.sixteenBit = true
    let output = try PrintOutput.prepare(source, settings: settings)
    XCTAssertFalse(output.layout.clipped)
    XCTAssertEqual(output.layout.rasterSource, output.layout.source)
    let image = try XCTUnwrap(output.pages.first?.image)
    XCTAssertEqual(image.width, width)
    XCTAssertEqual(image.height, height)
    XCTAssertEqual(image.bitsPerComponent, 16)
    let data = try XCTUnwrap(image.dataProvider?.data as Data?)
    XCTAssertEqual(data.count, width * height * 6)
    func sample(_ x: Int, _ y: Int) -> [UInt8] {
      let start = y * image.bytesPerRow + x * 6
      return Array(data[start..<(start + 6)])
    }
    XCTAssertEqual(sample(0, 0), [255, 255, 255, 255, 255, 255])
    XCTAssertEqual(sample(2000, 261), [255, 255, 0, 0, 0, 0])
    XCTAssertEqual(sample(2000, 262), [0, 0, 0, 0, 255, 255])
    XCTAssertEqual(sample(width - 1, height - 1), [0, 0, 0, 0, 0, 0])
  }

  func testOversizeActualSizeKeepsPagePlacementAndUsesOnlyVisibleSamples() throws {
    let side = Surface.maxDimension
    var source = try CraftDocument(width: side, height: side)
    source.resolution = 72
    var pixels = try Surface(width: side, height: side, fill: .white)
    let middle = side / 2
    pixels.setPixel(x: middle - 40, y: middle - 40, Pixel(1, 0, 0))
    pixels.setPixel(x: middle + 39, y: middle + 39, Pixel(0, 0, 1))
    source.layers[0].content = .raster(pixels)

    var settings = PrintSettings()
    settings.paper = .custom
    settings.customWidth = 120
    settings.customHeight = 120
    settings.scaleToFit = false
    let output = try PrintOutput.prepare(source, settings: settings)
    XCTAssertTrue(output.layout.clipped)
    XCTAssertEqual(output.layout.source, IntRect(x: 0, y: 0, width: side, height: side))
    XCTAssertEqual(output.layout.image.size, CGSize(width: side, height: side))
    XCTAssertEqual(output.layout.rasterSource, IntRect(x: middle - 50, y: middle - 50, width: 100, height: 100))
    XCTAssertEqual(output.layout.rasterDestination, CGRect(x: 10, y: 10, width: 100, height: 100))
    XCTAssertEqual(output.layout.effectivePPI, 72)

    var control = try CraftDocument(width: 100, height: 100)
    control.resolution = 72
    control.layers[0].content = .raster(try pixels.cropped(to: output.layout.rasterSource))
    let controlOutput = try PrintOutput.prepare(control, settings: settings)
    func pagePixels(_ output: PreparedPrint) throws -> Data {
      let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 120, bitsPerComponent: 8,
        bytesPerRow: 480, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      output.draw(page: 0, in: context)
      return Data(bytes: try XCTUnwrap(context.data), count: 120 * 480)
    }
    XCTAssertEqual(try pagePixels(output), try pagePixels(controlOutput))

    settings.center = false
    settings.left = 200
    let blank = try PrintOutput.prepare(source, settings: settings)
    XCTAssertTrue(blank.layout.rasterDestination.isNull)
    XCTAssertEqual(blank.layout.rasterSource.width * blank.layout.rasterSource.height, 1)
  }

  func testSelectedAreaOnMaximumCanvasUsesBoundsAndExactRGBSamples() throws {
    let side = Surface.maxDimension
    let region = IntRect(x: side - 2, y: side - 2, width: 2, height: 2)
    var source = try document(width: side, height: side)
    var pixels = try Surface(width: side, height: side)
    pixels.setPixel(x: 0, y: 0, .black)
    pixels.setPixel(x: region.x, y: region.y, Pixel(1, 0, 0))
    pixels.setPixel(x: region.x + 1, y: region.y + 1, Pixel(0, 0, 1))
    source.layers[0].content = .raster(pixels)
    source.selectionMask = try SelectionMask.sampledCoverage(width: side, height: side, regions: [region]) { x, y in
      (x == region.x && y == region.y) || (x == region.x + 1 && y == region.y + 1) ? 96 : 0
    }
    source.selection = source.selectionMask?.bounds

    XCTAssertThrowsError(try PrintOutput.prepare(source, settings: PrintSettings()))
    var settings = PrintSettings()
    settings.selectedArea = true
    let output = try PrintOutput.prepare(source, settings: settings)
    XCTAssertEqual(output.layout.source, region)
    let image = try XCTUnwrap(output.pages.first?.image)
    XCTAssertEqual(image.width, region.width)
    XCTAssertEqual(image.height, region.height)
    let rgb = try XCTUnwrap(image.dataProvider?.data as Data?)
    XCTAssertEqual(Array(rgb), [255, 0, 0, 255, 255, 255, 255, 255, 255, 0, 0, 255])

    source.selectionMask = nil
    source.selection = .init(x: 0, y: 0, width: side, height: side)
    XCTAssertThrowsError(try PrintLayout(document: source, settings: settings))
  }

  func testSelectedAreaOnMaximumLayeredCMYKCanvasRetainsExactProcessAndSpotWords() throws {
    let side = Surface.maxDimension
    let baseWords: [UInt32] = [1400, 15300, 30000, 53000]
    let patchWords: [UInt32] = [62000, 11200, 37000, 17100]
    let base = try NativeModeRaster.RowBuilder(width: side, height: side, mode: .cmyk, depth: .u16)
    for index in baseWords.indices { try base.fill(component: index, word: baseWords[index]) }
    try base.fill(component: 4, word: 65535)
    let bottom = try base.finish()
    let local = try NativeModeRaster.RowBuilder(width: 2, height: 1, mode: .cmyk, depth: .u16, profile: bottom.profile)
    for index in patchWords.indices {
      try local.appendRow([patchWords[index], patchWords[index] - 300], component: index)
    }
    try local.fill(component: 4, word: 65535)
    let native = try local.finish()
    var source = try CraftDocument(width: side, height: side, depth: .u16)
    source.modeDescriptor = try .init(mode: .cmyk, depth: .u16, profile: bottom.profile)
    source.layers[0].nativeMode = bottom
    source.layers[0].content = .raster(try bottom.surface())
    var patch = Layer(name: "Far corner", content: .raster(try native.surface()))
    patch.nativeMode = native
    patch.x = side - 2
    patch.y = side - 1
    source.layers.append(patch)
    source.selection = .init(x: side - 3, y: side - 1, width: 3, height: 1)
    let spot = try source.newSpotChannel(name: "Spot", ink: .init(color: .black, solidity: 0.5), density: 0)
    var ink = spot
    ink.pixels.setPixel(x: side - 1, y: side - 1, Pixel(1, 1, 1))
    source.alphaChannels = [ink]

    var settings = PrintSettings()
    settings.selectedArea = true
    settings.sixteenBit = true
    settings.content = .separations
    let output = try PrintOutput.prepare(source, settings: settings)
    XCTAssertEqual(output.layout.source, source.selection)
    XCTAssertEqual(output.pages.map(\.label), ["Cyan", "Magenta", "Yellow", "Black", "Spot"])
    for index in baseWords.indices {
      let expected = [baseWords[index], patchWords[index], patchWords[index] - 300].map { UInt16(65535 - $0) }
      XCTAssertEqual(try grayWords(output.pages[index]), expected)
    }
    XCTAssertEqual(try grayWords(output.pages[4]), [65535, 65535, 0])
  }

  func testLayeredCMYKPrintsExactProcessAndSpotPagesWithoutSavedMasks() throws {
    let width = 2
    let bottomWords: [UInt32] = [4000, 14000, 29000, 52000]
    let topWords: [UInt32] = [9000, 25000, 46000, 8300]
    let bottom = try NativeModeRaster.RowBuilder(width: width, height: 1, mode: .cmyk, depth: .u16)
    let top = try NativeModeRaster.RowBuilder(width: 1, height: 1, mode: .cmyk, depth: .u16)
    for index in 0..<4 {
      try bottom.fill(component: index, word: bottomWords[index])
      try top.fill(component: index, word: topWords[index])
    }
    let alpha: UInt32 = 16001
    try bottom.fill(component: 4, word: 65535)
    try top.fill(component: 4, word: alpha)
    let base = try bottom.finish(), patch = try top.finish()
    var d = try document(width: width, height: 1).convertingMode(.init(mode: .cmyk, depth: .u16))
    d.layers[0].nativeMode = base
    d.layers[0].content = .raster(try base.surface())
    var layer = Layer(name: "Ink patch", content: .raster(try patch.surface()))
    layer.nativeMode = patch
    d.layers.append(layer)
    var hidden = Layer(name: "Hidden fill", content: .fill(.black))
    hidden.visible = false
    d.layers.append(hidden)
    let density = Float(0x4567) / 65535
    let spot = try d.newSpotChannel(name: "Spot Indigo",
      ink: SpotInk(color: Pixel(0.4, 0.1, 0.9), solidity: 0.21), density: density)
    let mask = AlphaChannel(name: "Saved Selection", pixels: try Surface(width: width, height: 1, depth: .u16))
    d.alphaChannels = [mask, spot]
    d.selection = .init(x: 0, y: 0, width: 1, height: 1)

    var settings = PrintSettings()
    settings.content = .separations
    settings.sixteenBit = true
    let output = try PrintOutput.prepare(d, settings: settings)
    XCTAssertEqual(output.pages.map(\.label), ["Cyan", "Magenta", "Yellow", "Black", "Spot Indigo"])
    for (component, page) in output.pages.prefix(4).enumerated() {
      let ink = (Int(bottomWords[component]) * Int(65535 - alpha) + Int(topWords[component]) * Int(alpha) + 32767) / 65535
      let untouched = Int(65535 - bottomWords[component])
      XCTAssertEqual(try grayWords(page), [UInt16(65535 - ink), UInt16(untouched)])
    }
    XCTAssertEqual(try grayWords(XCTUnwrap(output.pages.last)), [0xba98, 0xba98])
    settings.selectedArea = true
    let crop = try PrintOutput.prepare(d, settings: settings)
    XCTAssertEqual(crop.layout.source, d.selection)
    XCTAssertEqual(try grayWords(XCTUnwrap(crop.pages.last)), [0xba98])
    XCTAssertEqual(d.alphaChannels?[1], spot)

    var rich = d
    rich.layers[1].blendMode = .multiply
    XCTAssertThrowsError(try PrintOutput.prepare(rich, settings: settings))
  }

  func testInkPrintOrderIncludesSpotsAndSkipsMaskRows() throws {
    let width = 2
    let cyan = InkPlate(name: "Cyan", color: Pixel(0, 1, 1),
      samples: try InkPlane(width: width, height: 1, depth: .u16, value: Float(0x1111) / 65535))
    let black = InkPlate(name: "Black", color: .black,
      samples: try InkPlane(width: width, height: 1, depth: .u16, value: Float(0x3333) / 65535))
    let source = try CraftDocument(width: width, height: 1, depth: .u16)
    let spot = try source.newSpotChannel(name: "Spot", ink: .init(color: Pixel(1, 0, 0), solidity: 0.79),
      density: Float(0x2222) / 65535)
    let mask = AlphaChannel(name: "Saved Mask", pixels: try Surface(width: width, height: 1, depth: .u16))
    var multi = try source.replacingInkMode(.multichannel(.init(plates: [cyan, black])))
    multi.alphaChannels = [mask, spot]
    try multi.setMultichannelChannelOrder([cyan.id, mask.id, spot.id, black.id])
    var settings = PrintSettings()
    settings.content = .separations
    settings.sixteenBit = true
    let multiOutput = try PrintOutput.prepare(multi, settings: settings)
    XCTAssertEqual(multiOutput.pages.map(\.label), ["Cyan", "Spot", "Black"])
    XCTAssertEqual(try multiOutput.pages.map(grayWords), [[0xeeee, 0xeeee], [0xdddd, 0xdddd], [0xcccc, 0xcccc]])

    let gray = try InkPlane(width: width, height: 1, depth: .u8, value: 0.5)
    var duo = try source.replacingInkMode(.duotone(.init(gray: gray, settings: .init())))
    duo.alphaChannels = try [spot.convertedCoverage(to: .u8), mask.convertedCoverage(to: .u8)]
    settings.sixteenBit = false
    let duoOutput = try PrintOutput.prepare(duo, settings: settings)
    XCTAssertEqual(duoOutput.pages.map(\.label), ["Black", "Spot"])
    let spotBytes = try XCTUnwrap(duoOutput.pages[1].image.dataProvider?.data as Data?)
    XCTAssertEqual(Array(spotBytes), [221, 221])
  }

  private func grayWords(_ page: PrintPage) throws -> [UInt16] {
    let data = try XCTUnwrap(page.image.dataProvider?.data as Data?)
    XCTAssertEqual(page.image.bitsPerComponent, 16)
    return stride(from: 0, to: data.count, by: 2).map {
      UInt16(data[$0]) << 8 | UInt16(data[$0 + 1])
    }
  }

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
