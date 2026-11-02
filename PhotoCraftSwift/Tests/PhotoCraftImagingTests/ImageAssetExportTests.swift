import Foundation
import CoreGraphics
import ImageIO
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ImageAssetExportTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 3, depth: depth, name: "owned")
    var pixels = try Surface(width: 4, height: 3, depth: depth)
    for y in 0..<3 { for x in 0..<4 { pixels.setPixel(x: x, y: y, x == 3 && y == 2 ? .clear : Pixel(Float(x%2), Float(y%2), Float((x+y)%2))) } }
    d.layers[0].content = .raster(pixels); return d
  }
  func capture(_ data: Data, _ name: String) throws {
    guard let root = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else { return }
    let folder = URL(fileURLWithPath: root); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); try data.write(to: folder.appendingPathComponent(name))
  }
  func testDocumentScalesAndCanvasMatchAnalyticalPixelsWithoutChangingSource() throws {
    let d = try fixture(), before = d; var settings = ImageExportSettings(); settings.scales = [.init(), .init(2, suffix: "@2x")]; settings.resampling = .nearest
    let files = try ImageAssetExport.render(d, settings: settings); XCTAssertEqual(files.map(\.name), ["owned.png", "owned@2x.png"]); XCTAssertEqual(files.map(\.width), [4, 8]); XCTAssertEqual(d, before)
    let expected = try Renderer.composite(d)
    for (i, file) in files.enumerated() {
      let read = try RasterIO.read(file.data), actual = try Renderer.composite(read), factor = i == 0 ? 1 : 2
      for y in 0..<actual.height { for x in 0..<actual.width { XCTAssertEqual(actual.pixel(x: x, y: y), expected.pixel(x: x/factor, y: y/factor)) } }
      try capture(file.data, i == 0 ? "document.png" : "document-2x.png")
    }
    settings.scales = [.init()]; settings.canvasWidth = 6; settings.canvasHeight = 5
    let canvas = try ImageAssetExport.render(d, settings: settings)[0], image = try Renderer.composite(RasterIO.read(canvas.data))
    XCTAssertEqual(image.pixel(x: 0, y: 0), .clear); XCTAssertEqual(image.pixel(x: 2, y: 1), expected.pixel(x: 1, y: 0)); XCTAssertEqual([canvas.width, canvas.height], [6, 5]); try capture(canvas.data, "canvas.png")
    settings.canvasWidth = 3; settings.canvasHeight = 2
    let cropped = try Renderer.composite(RasterIO.read(ImageAssetExport.render(d, settings: settings)[0].data))
    XCTAssertEqual(cropped.pixel(x: 0, y: 0), expected.pixel(x: 1, y: 1))
  }
  func testSelectedHiddenLayersGroupsAndOffCanvasBoundsAreIsolated() throws {
    var d = try fixture(), layer = Layer(name: "Selected", content: .raster(try Surface(width: 2, height: 2, fill: Pixel(1,0,0))))
    layer.x = -2; layer.y = 1; layer.visible = false; let group = Layer(name: "Group", content: .group(.init())); layer.parentID = group.id
    d.layers += [layer, group]; let before = d
    for id in [layer.id, group.id] {
      var settings = ImageExportSettings(); settings.target = .layers; settings.ids = [id]
      let file = try ImageAssetExport.render(d, settings: settings)[0]; XCTAssertEqual([file.width,file.height],[2,2])
      XCTAssertEqual(try Renderer.composite(RasterIO.read(file.data)).pixel(x: 0,y: 0), id == layer.id ? Pixel(1,0,0) : .clear)
      if id == layer.id { try capture(file.data, "layer.png") }
    }
    XCTAssertEqual(d, before)
    let full = try ImageAssetSelection.document(d, ids: [layer.id], crop: .documentBounds); XCTAssertEqual([full.width,full.height],[4,3]); XCTAssertEqual(try Renderer.composite(full).pixel(x:0,y:1),.clear)
  }
  func testArtboardBackgroundBoundsAndSourceHistoryArePreserved() throws {
    var d = try CraftDocument(width: 10,height: 8), blue = Layer(name:"Blue",content:.raster(try Surface(width:3,height:3,fill:Pixel(0,0,1))))
    blue.x = 4; blue.y = 2; d.layers.append(blue)
    try Command.artboard(.create(name:"Board",bounds:.init(x:4,y:2,width:3,height:3),background:.clear,children:[blue.id])).apply(to:&d)
    let before = d; var settings = ImageExportSettings(); settings.target = .artboards; settings.ids = d.artboards.map(\.id)
    let file = try ImageAssetExport.render(d,settings:settings)[0]; XCTAssertEqual([file.width,file.height],[3,3]); XCTAssertEqual(try Renderer.composite(RasterIO.read(file.data)).pixel(x:0,y:0),Pixel(0,0,1)); XCTAssertEqual(d,before); try capture(file.data,"artboard.png")
  }
  func testTransparencyJPEGMatteGIFAndEmbeddedProfileChoices() throws {
    let d = try fixture(); var settings = ImageExportSettings()
    let untagged = try ImageAssetExport.render(d,settings:settings)[0].data
    XCTAssertEqual(try UntaggedOutput.hasProfile(untagged), false)
    XCTAssertEqual(try RasterIO.read(untagged).profileIsUntagged, true)
    settings.embedProfile = true; let tagged = try ImageAssetExport.render(d,settings:settings)[0].data
    XCTAssertEqual(try UntaggedOutput.hasProfile(tagged), true)
    settings.embedProfile = false; settings.transparency = false
    XCTAssertEqual(try Renderer.composite(RasterIO.read(ImageAssetExport.render(d,settings:settings)[0].data)).pixel(x:3,y:2),.white)
    settings.format = .jpeg; let jpeg = try ImageAssetExport.render(d,settings:settings)[0]; XCTAssertTrue(jpeg.data.starts(with:[255,216])); XCTAssertEqual(try Renderer.composite(RasterIO.read(jpeg.data)).pixel(x:3,y:2).a,1)
    XCTAssertFalse(try JPEGContainer.segments([UInt8](jpeg.data)).contains { [225,237,254].contains($0.marker) })
    settings.format = .gif; settings.transparency = true; let gif = try ImageAssetExport.render(d,settings:settings)[0]; XCTAssertTrue(gif.data.starts(with:Data("GIF".utf8))); XCTAssertEqual(CGImageSourceGetCount(CGImageSourceCreateWithData(gif.data as CFData,nil)!),1)
    settings.embedProfile = true; XCTAssertThrowsError(try ImageAssetExport.render(d,settings:settings))
  }
  func testMetadataAllowlistDoesNotLeakTitleKeywordsOrOriginalPackets() throws {
    var d = try fixture(), info = FileInformation(); info.title = "Private title"; info.author = "Artist"; info.copyright = "Copyright Artist"; info.copyrightStatus = .copyrighted; info.keywords = ["Private tag"]; info.copyrightUrl = "https://example.test/rights"
    d = try FileInfoMetadata.applying(info,fields:Set(FileInformation.fields),to:d); let before = d
    var settings = ImageExportSettings()
    let none = try RasterIO.read(ImageAssetExport.render(d,settings:settings)[0].data); XCTAssertEqual(try FileInfoMetadata.read(none),FileInformation())
    settings.metadata = .copyright
    let read = try FileInfoMetadata.read(RasterIO.read(ImageAssetExport.render(d,settings:settings)[0].data)); XCTAssertEqual(read.author,info.author); XCTAssertEqual(read.copyright,info.copyright); XCTAssertEqual(read.copyrightUrl,info.copyrightUrl); XCTAssertEqual(read.title,""); XCTAssertTrue(read.keywords.isEmpty); XCTAssertEqual(d,before)
    settings.metadata = .none; d.sourceMetadata?[RasterMetadata.xmpKey] = Data([1,2,3]); XCTAssertNoThrow(try ImageAssetExport.render(d,settings:settings))
  }
  func testValidationBudgetsDuplicateNamesAndDimensionOverflow() throws {
    var d = try fixture(), settings = ImageExportSettings()
    for suffix in ["../escape", "a/b", "\0"] { settings.scales = [.init(1,suffix:suffix)]; XCTAssertThrowsError(try ImageAssetExport.render(d,settings:settings)) }
    settings.scales = [.init(),.init(2)]; XCTAssertThrowsError(try ImageAssetExport.render(d,settings:settings))
    settings = .init(); settings.width = Surface.maxDimension; settings.scales = [.init(1000)]; XCTAssertThrowsError(try ImageAssetExport.render(d,settings:settings))
    settings = .init(); XCTAssertThrowsError(try ImageAssetExport.render(d,settings:settings,maximumBytes:20))
    var other = d.layers[0]; other.id = UUID(); other.name = d.layers[0].name.uppercased(); d.layers.append(other); settings.target = .layers; settings.ids = d.layers.map(\.id)
    let files = try ImageAssetExport.render(d,settings:settings); XCTAssertEqual(Set(files.map { $0.name.lowercased() }).count,2)
    XCTAssertLessThanOrEqual(ImageAssetExport.safeName(String(repeating:"🖌",count:200)).utf8.count,150)
  }
  func testHighDepthAspectRatioAndNativeResamplingAreImmutable() throws {
    for depth in [PixelDepth.u16,.f32] {
      let d = try fixture(depth), before = d; var settings = ImageExportSettings(); settings.width = 8
      let file = try ImageAssetExport.render(d,settings:settings)[0]; XCTAssertEqual([file.width,file.height],[8,6]); XCTAssertEqual(try RasterIO.read(file.data).depth,.u8); XCTAssertEqual(d,before)
    }
  }
  func testAssetCroppingRetainsAffinePixelsAndMasksWithoutResamplingArtwork() throws {
    var d = try CraftDocument(width:24,height:24,depth:.f32)
    var pixels = try Surface(width:5,height:4,depth:.f32,colorEncoding:.linearRGB)
    var mask = try Surface(width:5,height:4,depth:.f32,fill:.white)
    for y in 0..<4 { for x in 0..<5 { pixels.setLinearPixel(x:x,y:y,Pixel(Float(x)/4,Float(y)/3,Float(x+y)/7)); if x == 1 { mask.setPixel(x:x,y:y,Pixel(0.5,0.5,0.5)) } } }
    var layer = Layer(name:"Transformed",content:.raster(pixels)); layer.mask = mask; layer.affine = .translation(9,7) * .rotation(23) * .scale(1.3,1.1)
    d.layers = [layer]; d.activeLayerID = layer.id; let before = d
    let box = try XCTUnwrap(Renderer.layoutBounds(layer,in:d,stored:true)), original = try Renderer.composite(d).cropped(to:box)
    let extracted = try ImageAssetSelection.document(d,ids:[layer.id],crop:.layerBounds)
    XCTAssertEqual(extracted.layers[0].content,layer.content); XCTAssertEqual(extracted.layers[0].mask,layer.mask); XCTAssertEqual(extracted.layers[0].affine,layer.affine)
    XCTAssertEqual(try Renderer.composite(extracted).rgbaData(depth:.u8),try original.rgbaData(depth:.u8)); XCTAssertEqual(d,before)
  }
  func testCanvasFillLayerExportsAtDocumentBoundsWithoutInvokingAlignmentRestrictions() throws {
    var source = try CraftDocument(width:6,height:4)
    source.layers = [Layer(name:"Gradient",content:.gradientFill(GradientFill(gradient:.blackToWhite)))]; source.activeLayerID=source.layers[0].id
    let selected = try ImageAssetSelection.document(source,ids:[source.layers[0].id],crop:.layerBounds,includingAncestors:true)
    XCTAssertEqual([selected.width,selected.height],[6,4]); XCTAssertEqual(try Renderer.composite(selected).rgbaData(depth:.f32),try Renderer.composite(source).rgbaData(depth:.f32))
  }
  func testCancellationDoesNotYieldAssets() async throws {
    let d = try fixture(); let worker = Task.detached { () throws -> [ImageExportFile] in withUnsafeCurrentTask { $0?.cancel() }; return try ImageAssetExport.render(d,settings:.init()) }
    do { _ = try await worker.value; XCTFail("Cancelled export returned files") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }
}
