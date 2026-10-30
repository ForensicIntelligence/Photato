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
    var tag = try PSDSmartObjects.linkedData(d);tag[15] = 9
    var unsupported = d;unsupported.sourceMetadata = ["psdGlobal_lnk2":tag]
    XCTAssertThrowsError(try PSDSmartObjects.files(unsupported))
  }
}
