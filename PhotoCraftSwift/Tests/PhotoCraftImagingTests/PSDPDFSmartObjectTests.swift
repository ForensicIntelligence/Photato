import Foundation
import ImageIO
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDPDFSmartObjectTests: XCTestCase {
  func fixture(_ name: String) throws -> Data {
    try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/pdf-psd/"+name))
  }
  func model(crop: PDFImportSettings.Crop = .media,page: Int = 2,depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:144,height:108,depth:depth)
    var s = PDFImportSettings();s.pages = [page];s.crop = crop;s.resolution = 72
    let data = try PDFSmartObjectTests().data()
    let layer = try PDFSmartObjectIO.placed(data,fileName:"Owned pages.pdf",in:d,settings:s,fit:false)
    d.layers = [layer];d.activeLayerID = layer.id;return d
  }
  func output(_ name: String,_ data: Data) throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_PSD_PDF_OUTPUT"] else {return}
    let root = URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    try data.write(to:root.appendingPathComponent(name))
  }
  func testOwnedPDFIdentityWarpKeepsEnlargedVectorSamplesAndRasterizeMatches() throws {
    let imported = try PSDCodec.read(fixture("photoshop-art-page.psd"))
    var layer = try XCTUnwrap(imported.layers.first { $0.smartObject?.pdfSource != nil })
    let object = try XCTUnwrap(layer.smartObject)
    var parent = try CraftDocument(width: object.width * 3 + 32, height: object.height * 3 + 32, depth: imported.depth)
    layer.x = 12; layer.y = 12; layer.affine = .scale(3, 3)
    parent.layers = [layer]; parent.activeLayerID = layer.id
    let expected = try Renderer.composite(parent).rgbaData(depth: parent.depth)
    let warp = try WarpDefinition().custom(width: object.width, height: object.height)
    let prepared = try SmartObjectIO.prepareWarp(parent, layerID: layer.id, warp: warp)
    let warped = prepared.result
    XCTAssertEqual(warped.layers[0].content, parent.layers[0].content)
    XCTAssertEqual(warped.layers[0].smartObject, object)
    XCTAssertEqual(try Renderer.composite(warped).rgbaData(depth: parent.depth), expected)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(warped)), warped)
    var session = EditorSession(document: warped)
    try session.execute(SmartObjectIO.rasterizationCommand(warped.layers[0], in: warped))
    XCTAssertNil(session.document.layers[0].smartObject)
    XCTAssertNil(session.document.layers[0].warp)
    XCTAssertEqual(try Renderer.composite(session.document).rgbaData(depth: parent.depth), expected)
    try session.undo()
    XCTAssertEqual(session.document, warped)
    for format in PSDFileFormat.allCases {
      let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(warped, format: format))
      XCTAssertEqual(saved.layers[0].smartObject, object)
      XCTAssertEqual(saved.layers[0].warp, warp)
      XCTAssertNotNil(saved.layers[0].pristineSmartAppearance)
      XCTAssertEqual(try Renderer.composite(saved).rgbaData(depth: parent.depth), expected)
    }
  }

  func testPDFWarpUsesLocalMagnificationAndKeepsMaskGeometry() throws {
    var parent = try model(crop: .art)
    let original = try XCTUnwrap(parent.layers[0].smartObject)
    parent.width *= 3; parent.height *= 3
    parent.layers[0].x = 20; parent.layers[0].y = 18
    var mask = try Surface(width: original.width, height: original.height, fill: .white)
    mask.setPixel(x: 5, y: 8, .black)
    parent.layers[0].mask = mask
    var warp = try WarpDefinition().custom(width: original.width, height: original.height)
    // The placement itself is at 100%. The mesh expands the source by three.
    let expanded = try XCTUnwrap(warp.mesh).points.map { $0.transformed(.scale(3, 3)) }
    warp.mesh?.points = expanded
    let prepared = try SmartObjectIO.prepareWarp(parent, layerID: parent.layers[0].id, warp: warp)
    let warped = prepared.result.layers[0]
    let samples = try XCTUnwrap(PDFSmartObjectIO.rasterizationSamples(warped, in: parent))
    XCTAssertEqual(samples.width, 3 * original.width)
    XCTAssertEqual(samples.height, 3 * original.height)
    let old = try WarpRaster.baked(warped, in: parent)
    let high = try SmartObjectIO.renderedLayer(warped, in: parent)
    XCTAssertNotEqual(high.content, old.content)
    XCTAssertEqual(high.x, old.x); XCTAssertEqual(high.y, old.y)
    XCTAssertEqual(high.maskCoordinateTransform, old.maskCoordinateTransform)
    XCTAssertEqual(try XCTUnwrap(high.mask).rgbaData(depth: .u8), try XCTUnwrap(old.mask).rgbaData(depth: .u8))
  }

  func testProjectedPDFCylinderAndMissingLinkedArtReopenAndRelinkInBothFormats() throws {
    for linked in [false, true] {
      var d = try model(crop: .art)
      d.width *= 3; d.height *= 3
      var layer = d.layers[0]
      layer.x = 30; layer.y = 20
      let object = try XCTUnwrap(layer.smartObject)
      let corners = [PathPoint(0, 0), .init(Double(object.width) * 2, 10),
                     .init(Double(object.width) * 2.5, Double(object.height) * 2), .init(-8, Double(object.height) * 1.8)]
      layer.sourceProjection = try SelectionTransform.projection(
        bounds: .init(x: 0, y: 0, width: object.width, height: object.height), corners: corners)
      let reference = try LinkedSmartObjectSource(reference: "/Missing/Owned pages.pdf",
        contentHash: object.dataFingerprint, byteLength: UInt64(object.data.count))
      if linked { layer = try LinkedSmartObjectIO.linked(layer, reference: reference) }
      d.layers = [layer]
      var warp = WarpDefinition(); warp.style = .cylinder
      warp.cylinder = try .init(photoshopValues: [0, Double(object.height), Double(object.width), 0, -0.2, 0.3, 0.25])
      let warped = try SmartObjectIO.prepareWarp(d, layerID: layer.id, warp: warp).result
      let expected = try Renderer.composite(warped).rgbaData(depth: .u8)
      for format in PSDFileFormat.allCases {
        let opened = try PSDCodec.readPaged(PSDCodec.writeRasterLayers(warped, format: format))
        let readLayer = opened.layers[0]
        XCTAssertEqual(readLayer.smartObject?.pdfSource?.page, object.pdfSource?.page)
        XCTAssertEqual(readLayer.smartObject?.pdfSource?.crop, object.pdfSource?.crop)
        XCTAssertEqual(try Renderer.composite(opened).rgbaData(depth: .u8), expected)
        if linked {
          XCTAssertEqual(try readLayer.linkedSmartObjectPreview()?.warp, warp)
          XCTAssertTrue(try XCTUnwrap(readLayer.smartObject).data.isEmpty)
          let native = try NativeArchive.decodePaged(NativeArchive.encodeChunked(opened))
          let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(native, format: format))
          XCTAssertEqual(try saved.layers[0].linkedSmartObjectPreview()?.warp, warp)
          var relinked = native
          try LinkedSmartObjectIO.replacement(object.data, fileName: object.fileName, reference: reference,
            in: native, layerID: layer.id, preserveSize: true).apply(to: &relinked)
          XCTAssertEqual(relinked.layers[0].smartObject?.data, object.data)
          XCTAssertEqual(relinked.layers[0].smartObject?.pdfSource, object.pdfSource)
          XCTAssertEqual(relinked.layers[0].warp, warp)
          XCTAssertNil(try relinked.layers[0].linkedSmartObjectPreview())
          XCTAssertEqual(try Renderer.composite(relinked).rgbaData(depth: .u8), expected)
        } else {
          XCTAssertEqual(readLayer.smartObject, object)
          XCTAssertEqual(readLayer.warp, warp)
          XCTAssertNotNil(readLayer.sourceProjection)
        }
      }
    }
  }

  func testOwnedPhotoshop2026Version8PDFPageImportsWithOriginalSourceAndPixels() throws {
    let bytes = try fixture("photoshop-page2-media.psd"),d = try PSDCodec.read(bytes)
    let layer = try XCTUnwrap(d.layers.first(where:{$0.smartObject != nil})),source = try XCTUnwrap(layer.smartObject)
    XCTAssertEqual(source.data,try fixture("photoshop-page2-source.pdf"));XCTAssertEqual(source.fileName,"Owned PDF pages Page 2.pdf")
    XCTAssertEqual(source.pdfSource?.page,1);XCTAssertEqual(source.pdfSource?.crop,.media)
    XCTAssertEqual(source.width,108);XCTAssertEqual(source.height,72);XCTAssertEqual(source.resolution,72)
    XCTAssertEqual(layer.coordinateTransform,.translation(18,18))
    let cgSource = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData,nil)),cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(cgSource,0,nil))
    let merged = try RasterIO.surface(cg)
    XCTAssertEqual(try Renderer.composite(d).rgbaData(depth:.u8),try merged.rgbaData(depth:.u8))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
    let placement = "f8093e70-083e-1648-a563-29ff37c30312"
    XCTAssertEqual(layer.id, UUID(uuidString: placement))
    for format in PSDFileFormat.allCases {
      let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(d, format: format))
      let savedLayer = try XCTUnwrap(saved.layers.first { $0.smartObject != nil })
      let tag = try XCTUnwrap(savedLayer.sourceTags?["SoLd"])
      XCTAssertEqual(PSDSmartObjects.placedIdentifier(in: try PSDSmartObjects.descriptor(tag)), placement)
    }
    try output("photoshop-import.png",RasterIO.encoded(d))
  }
  func testOwnedArtBoxAndMultiplePDFSourcesImportWithoutSourceConversion() throws {
    let d = try PSDCodec.read(fixture("photoshop-art-page.psd")),sources = d.layers.compactMap(\.smartObject)
    XCTAssertEqual(sources.count,2);XCTAssertEqual(Set(sources.compactMap{$0.pdfSource?.crop}),[.media,.art])
    XCTAssertTrue(sources.allSatisfy{$0.mediaType == "application/pdf" && PDFImport.recognizes($0.data)})
    for format in PSDFileFormat.allCases {
      let read = try PSDCodec.read(PSDCodec.writeRasterLayers(d,format:format))
      XCTAssertEqual(read.layers.compactMap(\.smartObject),sources)
      XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.u8),try Renderer.composite(d).rgbaData(depth:.u8))
    }
  }
  func testEveryPDFCropPageDepthAndContainerRetainsSourceAndSelection() throws {
    for depth in PixelDepth.allCases {for crop in PDFImportSettings.Crop.allCases {for page in [1,2] {for format in PSDFileFormat.allCases {
      let d = try model(crop:crop,page:page,depth:depth),bytes = try PSDCodec.writeRasterLayers(d,format:format),read = try PSDCodec.read(bytes)
      XCTAssertEqual(read.layers[0].smartObject,d.layers[0].smartObject,"\(crop) page\(page) \(depth) \(format)")
      XCTAssertEqual(read.layers[0].coordinateTransform,d.layers[0].coordinateTransform)
      XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:depth),try Renderer.composite(d).rgbaData(depth:depth))
      if depth == .u8 {try output("page\(page)-\(crop.rawValue).\(format == .psd ? "psd":"psb")",bytes)}
    }}}}
  }
  func testEnlargedPreviewAndSharedMaskedInstancesSurviveEditableInterchange() throws {
    var d = try model(page:1);let id = d.layers[0].id
    d.layers[0].mask = try Surface(width:144,height:108,fill:.white)
    try Command.transform(id,.scale(2,2),.bicubic).apply(to:&d)
    try Command.duplicateLayer(id).apply(to:&d)
    let before = d,bytes = try PSDCodec.writeRasterLayers(d),read = try PSDCodec.read(bytes)
    XCTAssertEqual(d,before);XCTAssertEqual(read.layers.compactMap(\.smartObject),d.layers.compactMap(\.smartObject))
    XCTAssertEqual(read.layers.map(\.coordinateTransform),d.layers.map(\.coordinateTransform))
    XCTAssertTrue(read.layers.allSatisfy{$0.mask != nil})
    for layer in read.layers {XCTAssertEqual(layer.maskCoordinateTransform.a,1);XCTAssertEqual(layer.maskCoordinateTransform.d,1)}
    XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.u8),try Renderer.composite(d).rgbaData(depth:.u8))
    try output("enlarged-shared.psd",bytes)
  }
  func testMaskExportProjectionUsesDocumentPixelCentersAndRetainsProperties() throws {
    var d = try model(page:1),mask = try Surface(width:2,height:2,depth:.f32)
    mask.setPixel(x:0,y:0,.white);mask.setPixel(x:1,y:1,.white)
    d.layers[0].mask = mask
    var properties = MaskProperties();properties.transform = .translation(-20,-20) * .scale(2,2)
    properties.enabled = false;properties.inverted = true;properties.density = 0.5;properties.linked = false
    d.layers[0].maskProperties = properties
    let original = d.layers[0],output = try PSDMaskExport.prepared(original)
    XCTAssertEqual(original,d.layers[0]);XCTAssertEqual(output.effectiveMaskProperties.enabled,false)
    XCTAssertEqual(output.effectiveMaskProperties.inverted,true);XCTAssertEqual(output.effectiveMaskProperties.density,0.5)
    XCTAssertEqual(output.effectiveMaskProperties.linked,false)
    let inverse = try original.maskCoordinateTransform.inverted(),actual = try XCTUnwrap(output.mask),t = output.maskCoordinateTransform
    for y in 0..<actual.height {for x in 0..<actual.width {
      let p = inverse.point(t.tx+Double(x)+0.5,t.ty+Double(y)+0.5)
      XCTAssertEqual(actual.pixel(x:x,y:y).r,MaskSampler.sample(mask,x:p.x,y:p.y,outside:0))
    }}
    var feathered = original;feathered.maskProperties?.feather = 2
    XCTAssertThrowsError(try PSDMaskExport.prepared(feathered))
  }
  func testMalformedPDFDescriptorsAndUnsupportedSelectionsReject() throws {
    let d = try model(),original = d.layers[0],source = try XCTUnwrap(original.smartObject)
    let base = try PSDSmartObjects.descriptor(PSDSmartObjects.placedDescriptor(original))
    for (key,value) in [("PgNm",PSDValue.integer(4)),("totalPages",.integer(2)),("Crop",.integer(99)),("Annt",.integer(0)),("Type",.integer(2)),("Sz  ",.object(PSDDescriptor("Pnt ",items:[.init("Wdth",.number(.infinity)),.init("Hght",.number(72))])))] {
      var bad = base;bad.items.removeAll{$0.key.text == key};bad.items.append(.init(key,value))
      XCTAssertThrowsError(try PSDPDFSmartObjects.restore(source.data,fileName:source.fileName,descriptor:bad,in:d),key)
    }
    var noAA = d;noAA.layers[0].smartObject?.pdfSource?.antialias = false
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(noAA))
    let (image,pixels) = try PDFSmartObjectIO.embeddedImage(PDFSmartObjectTests().data("owned-images"),fileName:"Images.pdf",in:d,image:1)
    var imageDoc = d;imageDoc.layers[0].smartObject = image;imageDoc.layers[0].content = .raster(pixels)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(imageDoc))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(imageDoc)),imageDoc)
    var tag = Data(try PSDSmartObjects.linkedData(d).joined());tag[15] = 9
    var unsupported = d;unsupported.sourceMetadata = ["psdGlobal_lnk2":tag]
    XCTAssertThrowsError(try PSDSmartObjects.files(unsupported))
  }
}
