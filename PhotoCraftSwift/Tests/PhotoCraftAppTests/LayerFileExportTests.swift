import AppKit
import CoreGraphics
import Foundation
import ImageIO
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging
@testable import PhotoCraft

final class LayerFileExportTests: XCTestCase {
  func fixture(_ depth:PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:6,height:4,depth:depth,name:"Owned layers")
    var red = Layer(name:"Red",content:.raster(try Surface(width:2,height:2,depth:depth,fill:Pixel(1,0,0)))); red.x=1; red.y=1
    var blue = Layer(name:"Hidden / blue",content:.raster(try Surface(width:2,height:2,depth:depth,fill:Pixel(0,0,1)))); blue.x=3; blue.visible=false
    var empty = Layer(name:"Zero opacity",content:.raster(try Surface(width:1,height:1,depth:depth,fill:.white))); empty.opacity=0
    var group = Layer(name:"Parent",content:.group(.init())); group.opacity=0.5
    var green = Layer(name:"Green",content:.raster(try Surface(width:2,height:2,depth:depth,fill:Pixel(0,1,0)))); green.x=3; green.y=2; green.parentID=group.id
    d.layers=[red,blue,empty,green,group]; d.activeLayerID=red.id; d.resolution=144; return d
  }
  func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("photato-layer-test-"+UUID().uuidString,isDirectory:true); try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false); return url
  }
  func testLayerSelectionUsesTopOrderAndEyeVisibilityThroughAncestorsIncludingZeroOpacity() throws {
    var d = try fixture(), options = LayerFileExportSettings(); XCTAssertEqual(try options.layers(in:d).map(\.name),["Green","Zero opacity","Hidden / blue","Red"])
    options.visibleOnly=true; XCTAssertEqual(try options.layers(in:d).map(\.name),["Green","Zero opacity","Red"])
    d.layers[4].visible=false; XCTAssertEqual(try options.layers(in:d).map(\.name),["Zero opacity","Red"])
    options.ids=[d.layers[1].id]; XCTAssertThrowsError(try options.layers(in:d)); options.visibleOnly=false; XCTAssertEqual(try options.layers(in:d).map(\.name),["Hidden / blue"])
  }
  func testAncestorOpacityAndDocumentBoundsAreSharedWithPublishedAdobeLayerOutputs() throws {
    let d = try fixture(), before = d; var options = LayerFileExportSettings(); options.format = .png24
    let native = try LayerFileExport.variation(d,layer:d.layers[3],options:options)
    XCTAssertEqual(native.layers.map(\.name),["Green","Parent"]); XCTAssertEqual([native.width,native.height],[6,4])
    let request = try AdobeLayerOutput(["layers":[["id":4]],"cropMode":"document_bounds"],createComposite:true,mediaType:.png)
    let adobe = try request.document(d)
    XCTAssertEqual(try Renderer.composite(native).rgbaData(depth:.f32),try Renderer.composite(adobe).rgbaData(depth:.f32)); XCTAssertEqual(try Renderer.composite(native).pixel(x:3,y:2).a,0.5)
    options.trim=true; let trimmed = try LayerFileExport.variation(d,layer:d.layers[3],options:options)
    XCTAssertEqual([trimmed.width,trimmed.height],[2,2]); XCTAssertEqual(try Renderer.composite(trimmed).pixel(x:0,y:0).a,0.5)
    var assets=ImageExportSettings(); assets.target = .layers; assets.ids=[d.layers[3].id]
    let exportAs=try ImageAssetExport.assets(d,settings:assets)[0].2
    XCTAssertEqual(try Renderer.composite(exportAs).rgbaData(depth:.f32),try Renderer.composite(trimmed).rgbaData(depth:.f32)); XCTAssertEqual(d,before)
  }
  func testAllTenFormatsUseExpectedContainersAndNativeArchiveRemainsEditable() throws {
    let d = try fixture(); let directory = try folder(); defer { try? FileManager.default.removeItem(at:directory) }
    for format in LayerFileExportSettings.Format.allCases {
      var options = LayerFileExportSettings(); options.format=format; options.includeICC=format.supportsICC; options.ids=[d.layers[0].id]; options.prefix="Batch"; options.paletteDither = .none
      let prepared = try LayerFileExport.prepare(d,options:options,directory:directory); defer { prepared.discard() }
      let file = try XCTUnwrap(prepared.files.first); XCTAssertEqual(file.file,"Batch_0000_Red."+format.ext); XCTAssertGreaterThan(file.bytes,0)
      let bytes = try Data(contentsOf:prepared.staging.appendingPathComponent(file.file))
      switch format {
      case .psd,.psb:
        XCTAssertTrue(bytes.starts(with:Data("8BPS".utf8))); let read = try PSDCodec.read(bytes); XCTAssertEqual(read.layers.count,1); XCTAssertEqual([read.width,read.height],[6,4])
      case .photato: let read = try NativeArchive.decode(bytes); XCTAssertEqual(read.layers[0].content,d.layers[0].content); XCTAssertEqual(read.layers[0].x,1)
      case .pdf:
        let pdf = try XCTUnwrap(CGPDFDocument(CGDataProvider(data:bytes as CFData)!)); XCTAssertEqual(pdf.numberOfPages,1); XCTAssertEqual(pdf.page(at:1)?.getBoxRect(.mediaBox),CGRect(x:0,y:0,width:3,height:2))
      default:
        let image = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData,nil)), properties = CGImageSourceCopyPropertiesAtIndex(image,0,nil) as! [CFString:Any]
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int,6); XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int,4)
        if format == .png8 { XCTAssertEqual(bytes[24],8); XCTAssertEqual(bytes[25],3) }
        if format == .png24 { XCTAssertEqual(bytes[24],8); XCTAssertTrue([2,6].contains(bytes[25])) }
        if format == .bmp { XCTAssertTrue(bytes.starts(with:Data("BM".utf8))) }
        if [.bmp,.tga].contains(format) {
          let decoded = try Renderer.composite(RasterIO.read(bytes)); XCTAssertEqual(decoded.pixel(x:1,y:1),Pixel(1,0,0)); XCTAssertEqual(decoded.pixel(x:0,y:0),format == .bmp ? .white:.clear)
        }
        if format == .jpeg { XCTAssertTrue(bytes.starts(with:[255,216])) }
      }
    }
  }
  func testPSDPSBNativeAndTIFFRetainHighDepthSamplesAndPNG24UsesEightBits() throws {
    for depth in [PixelDepth.u16,.f32] {
      let d = try fixture(depth), before = d, directory = try folder(); defer { try? FileManager.default.removeItem(at:directory) }
      for format in [LayerFileExportSettings.Format.psd,.psb,.photato,.tiff,.png24] {
        var options = LayerFileExportSettings(); options.format=format; options.ids=[d.layers[0].id]
        let prepared = try LayerFileExport.prepare(d,options:options,directory:directory); defer { prepared.discard() }
        let bytes = try Data(contentsOf:prepared.staging.appendingPathComponent(prepared.files[0].file))
        let read = format == .photato ? try NativeArchive.decode(bytes) : try RasterIO.read(bytes)
        XCTAssertEqual(read.depth,format == .png24 ? .u8:depth)
        if format != .png24 { XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.f32),try Renderer.composite(LayerFileExport.variation(d,layer:d.layers[0],options:options)).rgbaData(depth:.f32)) }
      }; XCTAssertEqual(d,before)
    }
  }
  func testPNGProfilePaletteTransparencyNamingAndZIPManifest() throws {
    let d = try fixture(), directory = try folder(); defer { try? FileManager.default.removeItem(at:directory) }
    var options = LayerFileExportSettings(); options.format = .png24; options.includeICC=false; options.prefix="assets"
    let prepared = try LayerFileExport.prepare(d,options:options,directory:directory); defer { prepared.discard() }
    XCTAssertEqual(prepared.files.map(\.file),["assets_0000_Green.png","assets_0001_Zero opacity.png","assets_0002_Hidden _ blue.png","assets_0003_Red.png"])
    let zip = try PcraftZIP(prepared.archive()); let manifest = try JSONSerialization.jsonObject(with:zip.read("photato-layer-files.json")) as! [String:Any]
    XCTAssertEqual((manifest["files"] as? [Any])?.count,4)
    for file in prepared.files { let bytes = try zip.read(file.file); XCTAssertEqual(try UntaggedOutput.hasProfile(bytes),false) }
    let hidden = try Renderer.composite(RasterIO.read(zip.read(prepared.files[2].file))); XCTAssertEqual(hidden.pixel(x:3,y:0),Pixel(0,0,1))
    let zero = try Renderer.composite(RasterIO.read(zip.read(prepared.files[1].file))); XCTAssertEqual(zero.pixel(x:0,y:0),.clear)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] { let dir = URL(fileURLWithPath:path); try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true); for file in prepared.files { try zip.read(file.file).write(to:dir.appendingPathComponent(file.file)) } }
    options.format = .png8; options.ids=[d.layers[0].id]; options.paletteColors=4; options.paletteDither = .none
    let indexed = try LayerFileExport.prepare(d,options:options,directory:directory); defer { indexed.discard() }; let bytes = try Data(contentsOf:indexed.staging.appendingPathComponent(indexed.files[0].file))
    XCTAssertEqual(bytes[25],3); let image = try Renderer.composite(RasterIO.read(bytes)); XCTAssertEqual(image.pixel(x:1,y:1),Pixel(1,0,0)); XCTAssertEqual(image.pixel(x:0,y:0),.clear)
  }
  func testPublicationPreflightsAllNamesAndRollsBackOnlyNewlyLinkedFilesOnFailure() throws {
    let d = try fixture(), directory = try folder(); defer { try? FileManager.default.removeItem(at:directory) }; var options = LayerFileExportSettings(); options.format = .png24
    let first = try LayerFileExport.prepare(d,options:options,directory:directory); defer { first.discard() }
    let existing = directory.appendingPathComponent(first.files[1].file); let original = Data("Existing artwork".utf8); try original.write(to:existing)
    XCTAssertThrowsError(try first.publish(to:directory)); XCTAssertEqual(try Data(contentsOf:existing),original); XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent(first.files[0].file).path))
    try FileManager.default.removeItem(at:existing)
    try FileManager.default.removeItem(at:first.staging.appendingPathComponent(first.files[1].file))
    XCTAssertThrowsError(try first.publish(to:directory)); XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent(first.files[0].file).path))
    let second = try LayerFileExport.prepare(d,options:options,directory:directory); defer { second.discard() }; let publication = try second.publish(to:directory); XCTAssertEqual(publication.count,4)
    for file in second.files { XCTAssertTrue(FileManager.default.fileExists(atPath:directory.appendingPathComponent(file.file).path)) }
    PreparedLayerFiles.rollback(publication); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).allSatisfy { $0.hasPrefix(".photato-layer-files-") })
  }
  func testNativeBatchCanExceedAPIArchiveLimitWithoutAggregatingFileData() throws {
    var d = try CraftDocument(width:1,height:1,name:"Owned aggregate boundary")
    d.layers = (0..<260).map { Layer(name:"Layer \($0)",content:.raster(try! Surface(width:1,height:1,fill:.white))) }; d.activeLayerID=d.layers[0].id
    d.sourceMetadata=["psdResources":PSDImageResources.block(4000,data:Data(repeating:42,count:512*1024))]
    let before=d, directory=try folder(); defer { try? FileManager.default.removeItem(at:directory) }
    let prepared=try LayerFileExport.prepare(d,options:.init(),directory:directory); defer { prepared.discard() }
    let total=prepared.files.reduce(0) { $0+$1.bytes }; XCTAssertGreaterThan(total,ImageAssetExport.maximumBytes); XCTAssertEqual(prepared.files.count,260)
    XCTAssertThrowsError(try prepared.archive()); let publication=try prepared.publish(to:directory); XCTAssertEqual(publication.count,260)
    XCTAssertEqual(d,before); print("LAYER_FILE_NATIVE_AGGREGATE bytes=\(total) files=\(prepared.files.count) APIZIPLimit=\(ImageAssetExport.maximumBytes)")
  }
  func testInvalidSettingsZIPBudgetAndCancellationLeaveNoPublishedOrStagedFiles() async throws {
    let d = try fixture(), directory = try folder(); defer { try? FileManager.default.removeItem(at:directory) }
    for prefix in ["..","../escape","a/b","\0"] { var settings = LayerFileExportSettings(); settings.prefix=prefix; XCTAssertThrowsError(try LayerFileExport.prepare(d,options:settings,directory:directory)) }
    var settings = LayerFileExportSettings(); settings.ids=[UUID()]; XCTAssertThrowsError(try LayerFileExport.prepare(d,options:settings,directory:directory))
    settings = .init(); settings.format = .png24; let prepared = try LayerFileExport.prepare(d,options:settings,directory:directory); defer { prepared.discard() }; XCTAssertThrowsError(try prepared.archive(maximumBytes:20))
    prepared.discard()
    let worker = Task.detached { () throws -> PreparedLayerFiles in withUnsafeCurrentTask { $0?.cancel() }; return try LayerFileExport.prepare(d,options:.init(),directory:directory) }
    do { _ = try await worker.value; XCTFail("Cancelled export returned files") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
  }
}
